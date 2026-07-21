// Conso Claude — app barre de menus macOS.
// Clic → popover compact (web view : CSS glass, barres springs, compteurs).
// Franchissement de seuil → avion-banderole qui traverse l'écran ✈️.
// Clic droit sur l'icône → menu (démarrage, test avion, quitter).

import Cocoa
import WebKit
import ServiceManagement
import CryptoKit
import Security

// MARK: - Données

struct UsageLimit {
    let kind: String
    let label: String
    let percent: Int
    let resetsAt: Date?
    let severity: String
    let isSession: Bool
}

struct UsageState {
    var limits: [UsageLimit] = []
    var error: String?
    var fetchedAt: Date?
    var stale = false
    // Aucun token en Keychain (ou expiré) → le popover propose « Sign in » plutôt
    // qu'un message qui renvoie vers le Terminal.
    var needsLogin = false
}

// OAuth Claude Code : on sait rafraîchir le token nous-mêmes (via le refreshToken
// stocké dans le Keychain), sans dépendre de l'ouverture de Claude Code. Mieux : on
// sait aussi faire le PREMIER login (flux OAuth complet), donc l'app est autonome —
// pas besoin d'installer Claude Code ni de passer par le Terminal.
let OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
let OAUTH_TOKEN_URL = "https://api.anthropic.com/v1/oauth/token"
// URL d'autorisation « subscription » de Claude Code. NB : ce n'est PLUS
// claude.ai/oauth/authorize (qui renvoie 403 « Invalid request format ») — le login
// a migré sur claude.com/cai. Valeurs relevées dans le binaire claude-code en prod.
let OAUTH_AUTHORIZE_URL = "https://claude.com/cai/oauth/authorize"
// Un SEUL scope — relevé sur `claude setup-token` (le flux subscription réel).
// Envoyer davantage (org:create_api_key…) fait rejeter la requête.
let OAUTH_SCOPES = "user:inference"
// Callback hébergé par Claude : la page affiche le code à copier (« code#state »).
// C'est le redirect utilisé par `claude setup-token`, et il doit être identique
// dans l'échange de token.
let OAUTH_REDIRECT = "https://platform.claude.com/oauth/code/callback"
// Endpoint d'échange/refresh de secours (si api.anthropic.com refuse le code).
let OAUTH_TOKEN_URL_ALT = "https://platform.claude.com/v1/oauth/token"
let OAUTH_USER_AGENT = "claude-cli/1.0 (external, cli)"
let KEYCHAIN_SERVICE = "Claude Code-credentials"

// MARK: - PKCE

// base64url sans padding — encodage attendu par le challenge PKCE et le state.
func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// Jeton aléatoire cryptographique (verifier PKCE, state anti-CSRF).
func randomToken(_ n: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: n)
    _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
    return b64url(Data(bytes))
}

// challenge = base64url(SHA256(verifier)) — méthode S256.
func pkceChallenge(_ verifier: String) -> String {
    b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
}

struct KeychainCreds {
    let account: String
    let full: [String: Any]      // blob complet (contient "claudeAiOauth")
    let oauth: [String: Any]     // full["claudeAiOauth"]
    let accessToken: String
    let refreshToken: String?
    let expiresAtMs: Double?
}

let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseDate(_ s: String?) -> Date? {
    guard let s = s else { return nil }
    let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return isoParser.date(from: cleaned)
}

func fmtResetShort(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return "reset" }
    let h = s / 3600, m = (s % 3600) / 60
    if h >= 24 { return "\(h / 24) d \(h % 24) h" }
    if h > 0 { return "\(h) h \(String(format: "%02d", m))" }
    return "\(m) min"
}

func fmtResetFull(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US")
    df.dateFormat = "EEEE, MMMM d 'at' HH:mm"
    return "Resets \(df.string(from: d))"
}

var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

// MARK: - Popover HTML (glass, springs, compteurs)

let POPOVER_HTML = #"""
<!doctype html><html><head><meta charset="utf-8"><style>
:root { color-scheme: light dark; }
* { margin:0; padding:0; box-sizing:border-box; -webkit-user-select:none; cursor:default; }
html,body { background:transparent; overflow:hidden; }
body {
  font: 12px/1.4 -apple-system, "SF Pro Text", sans-serif;
  color: light-dark(rgba(20,18,15,.88), rgba(245,240,232,.92));
  padding: 12px 14px 8px;
}
.row { margin-bottom: 12px; }
.line { display:flex; align-items:baseline; margin-bottom:5px; }
.label { font-size:11px; font-weight:500; color: light-dark(rgba(20,18,15,.6), rgba(245,240,232,.6));
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.session .label { font-weight:600; color: light-dark(rgba(20,18,15,.85), rgba(245,240,232,.9)); }
.meta { margin-left:auto; display:flex; gap:7px; align-items:baseline; }
.reset { font-size:9.5px; font-variant-numeric:tabular-nums;
  color: light-dark(rgba(20,18,15,.32), rgba(245,240,232,.35)); }
.pct { font-size:12px; font-weight:700; font-variant-numeric:tabular-nums; min-width:38px; text-align:right; }
.session .pct { font-size:13px; }
.ok   { color:#d97757; } .warn { color:#e8940c; } .crit { color:#e5493a; }
.bar {
  position:relative; height:4px; border-radius:2.5px; overflow:hidden;
  background: light-dark(rgba(20,18,15,.1), rgba(245,240,232,.12));
  background-image: linear-gradient(90deg, light-dark(rgba(20,18,15,.14), rgba(245,240,232,.16)) 1px, transparent 1px);
  background-size: 25% 100%;
}
.session .bar { height:5px; }
.fill {
  position:absolute; top:0; bottom:0; left:0; width:0; border-radius:3px;
  transition: width .9s cubic-bezier(.16,1,.3,1);
}
.fill.ok   { background:linear-gradient(90deg,#f2a984,#d97757); box-shadow:0 0 6px rgba(217,119,87,.55); }
.fill.warn { background:linear-gradient(90deg,#fac05a,#e8940c); box-shadow:0 0 6px rgba(232,148,12,.55); }
.fill.crit { background:linear-gradient(90deg,#fa7362,#e5493a); box-shadow:0 0 6px rgba(229,73,58,.6); }
.fill.anim::after {
  content:""; position:absolute; top:0; bottom:0; left:-40px; width:36px;
  background:linear-gradient(90deg,transparent,rgba(255,255,255,.6),transparent);
  animation: shine .8s .45s both;
}
@keyframes shine { to { left:110%; } }
#err { font-size:10px; color:#e8940c; margin:-4px 0 8px; }
#login { display:block; width:100%; margin:2px 0 8px; padding:7px 10px; border:none;
  border-radius:8px; font:600 12px/1 -apple-system; color:#fff; cursor:pointer;
  background:linear-gradient(90deg,#f2a984,#d97757); box-shadow:0 1px 4px rgba(217,119,87,.4);
  transition: filter .12s ease, transform .1s ease; }
/* Sans ça, `#login { display:block }` bat l'attribut [hidden] (spécificité id >
   attribut) et le bouton reste TOUJOURS visible, même needsLogin=false. */
#login[hidden] { display:none; }
#login:hover { filter:brightness(1.06); }
#login:active { transform:scale(.98); }
#spk { margin:2px 0 4px; padding-top:10px; color: light-dark(rgba(20,18,15,.8), rgba(245,240,232,.8));
  border-top:.5px solid light-dark(rgba(20,18,15,.08), rgba(245,240,232,.09)); }
.eta { color:#e8940c; }
#foot { display:flex; align-items:center; gap:4px; margin-top:4px; padding-top:8px;
  border-top:.5px solid light-dark(rgba(20,18,15,.08), rgba(245,240,232,.09)); }
.btn { width:20px; height:18px; display:flex; align-items:center; justify-content:center;
  border-radius:5px; color: light-dark(rgba(20,18,15,.35), rgba(245,240,232,.38));
  transition: background .15s ease, color .15s ease; }
.btn:hover { color: light-dark(rgba(20,18,15,.75), rgba(245,240,232,.8));
  background: light-dark(rgba(20,18,15,.06), rgba(245,240,232,.08)); }
.btn svg { width:12px; height:12px; transition: transform .12s ease; }
.btn:active svg { transform: scale(.82); }
#btn-r.spin svg { animation: rot .5s ease; }
@keyframes rot { to { transform: rotate(360deg); } }
#time { margin-left:auto; font-size:9px; font-variant-numeric:tabular-nums;
  color: light-dark(rgba(20,18,15,.25), rgba(245,240,232,.28)); }
/* Accessibilité : respecte « Augmenter le contraste » (Réglages > Accessibilité
   > Affichage). On densifie tous les gris uniquement si l'utilisateur l'a activé —
   le look discret reste par défaut. Booster #spk relève aussi le texte SVG du
   graphe (fill=currentColor). */
@media (prefers-contrast: more) {
  body { color: light-dark(rgba(20,18,15,.98), rgba(245,240,232,1)); }
  .label { color: light-dark(rgba(20,18,15,.82), rgba(245,240,232,.82)); }
  .session .label { color: light-dark(rgba(20,18,15,1), rgba(245,240,232,1)); }
  .reset, #time { color: light-dark(rgba(20,18,15,.6), rgba(245,240,232,.62)); }
  #spk { color: light-dark(rgba(20,18,15,1), rgba(245,240,232,1)); }
}
</style></head><body>
<div id="rows"></div>
<div id="err" hidden></div>
<button id="login" hidden>Sign in to Claude</button>
<div id="spk" hidden></div>
<div id="foot">
  <div class="btn" id="btn-r" title="Refresh"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 1.5v3h-3"/></svg></div>
  <div class="btn" id="btn-p" title="Test the plane"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M14.5 1.5 1.5 6.8l4.2 1.9m8.8-7.2L9.2 14.5 7.3 10.3m7.2-8.8L5.7 8.7"/></svg></div>
  <span id="time"></span>
</div>
<script>
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function sev(l) {
  if (l.severity === 'critical' || l.percent >= 90) return 'crit';
  if (l.severity === 'warning'  || l.percent >= 70) return 'warn';
  return 'ok';
}
function countUp(el, v, delay, animate) {
  if (!animate) { el.textContent = v + ' %'; return; }
  el.textContent = '0 %';
  const t0 = performance.now() + delay * 1000;
  function tick(t) {
    const p = Math.min(Math.max((t - t0) / 700, 0), 1);
    el.textContent = Math.round(v * (1 - Math.pow(1 - p, 3))) + ' %';
    if (p < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}
function spark(points) {
  if (!points || points.length < 3) return '';
  const span = Math.max(...points.map(p => p.a));
  if (span < 1800) return '';  // < 30 min d'historique
  const W = 220, H = 42;
  // Points en ordre chronologique (ancien -> récent).
  const pts = points.slice().sort((a, b) => b.a - a.a);
  // % consommés dans chacune des dernières heures : la dérivée du cumul.
  // Le % de session ne fait que monter puis retombe à 0 au reset ; une baisse
  // = nouvelle session, on ne compte alors que la remontée depuis zéro.
  // Fenêtre adaptative : grandit avec l'historique dispo, jusqu'à 24 h.
  const hours = Math.min(Math.ceil(span / 3600), 24);
  const buckets = new Array(hours).fill(0);
  for (let i = 1; i < pts.length; i++) {
    const prev = pts[i - 1], cur = pts[i];
    const used = cur.v >= prev.v ? cur.v - prev.v : cur.v;
    if (used <= 0) continue;
    const idx = Math.min(Math.floor(cur.a / 3600), hours - 1);  // 0 = heure en cours
    buckets[idx] += used;
  }
  const peak = Math.max(...buckets);
  // Plancher d'échelle : un jour calme reste visuellement calme. Les barres ne
  // gonflent pour remplir le graphe qu'au-delà de 20 %/h — le rythme qui
  // viderait une session entière (100 %) en 5 h, soit du plein régime.
  const scale = Math.max(peak, 20);
  const baseY = H - 12, topY = 9, maxBarH = baseY - topY;  // 12px sous la ligne pour les heures
  const slot = W / hours, bw = Math.min(slot * 0.6, 26);
  const now = new Date();
  const step = Math.max(1, Math.round(hours / 4));  // ~4 repères d'heure
  let bars = '', ticks = '';
  for (let j = 0; j < hours; j++) {
    const v = buckets[j];
    const h = v > 0 ? Math.max(1.5, (v / scale) * maxBarH) : 1.5;
    const cx = W - (j + 0.5) * slot;  // centre de la barre ; heure 0 (récente) à droite
    bars += '<rect x="' + (cx - bw / 2).toFixed(1) + '" y="' + (baseY - h).toFixed(1) +
      '" width="' + bw.toFixed(1) + '" height="' + h.toFixed(1) + '" rx="1" fill="#d97757" opacity="' +
      (v > 0 ? '.9' : '.15') + '"/>';
    if (j % step === 0) {
      const t = new Date(now.getTime() - (j + 0.5) * 3600 * 1000);
      const tx = Math.min(Math.max(cx, 8), W - 8);
      ticks += '<text x="' + tx.toFixed(1) + '" y="' + (H - 2) + '" font-size="6.5" text-anchor="middle" ' +
        'fill="currentColor" opacity=".62">' + String(t.getHours()).padStart(2, '0') + 'h</text>';
    }
  }
  const cap = peak > 0 ? ' · PEAK ' + Math.round(peak) + '%/H' : '';
  return '<svg width="' + W + '" height="' + H + '" style="display:block">' +
    '<line x1="0" y1="' + baseY + '" x2="' + W + '" y2="' + baseY + '" stroke="currentColor" opacity=".15"/>' +
    '<text x="1" y="7" font-size="7" fill="currentColor" opacity=".62" letter-spacing="1.2">USED / HOUR' + cap + '</text>' +
    bars + ticks + '</svg>';
}
function render(d, animate) {
  const rows = $('rows');
  rows.innerHTML = '';
  d.limits.forEach((l, i) => {
    const s = sev(l);
    const row = document.createElement('div');
    row.className = 'row' + (l.session ? ' session' : '');
    row.title = (100 - l.percent) + ' % left · ' + l.resetFull;
    row.innerHTML =
      '<div class="line"><span class="label">' + esc(l.label) + '</span>' +
      '<span class="meta"><span class="reset">' + (l.eta ? '<span class="eta">' + esc(l.eta) + '</span> · ' : '') + esc(l.reset) + '</span>' +
      '<span class="pct ' + s + '"></span></span></div>' +
      '<div class="bar"><div class="fill ' + s + (animate ? ' anim' : '') + '"></div></div>';
    rows.appendChild(row);
    const fill = row.querySelector('.fill');
    const pct = row.querySelector('.pct');
    const w = Math.max(0, Math.min(l.percent, 100)) + '%';
    if (animate) {
      fill.style.transitionDelay = (i * 0.07) + 's';
      requestAnimationFrame(() => requestAnimationFrame(() => { fill.style.width = w; }));
    } else {
      fill.style.transition = 'none';
      fill.style.width = w;
    }
    countUp(pct, l.percent, i * 0.07, animate);
  });
  $('err').hidden = !d.error;
  $('err').textContent = d.error || '';
  const lg = $('login');
  lg.hidden = !d.needsLogin;
  lg.textContent = 'Sign in to Claude';
  lg.disabled = false;
  const sp = spark(d.spark);
  $('spk').innerHTML = sp;
  $('spk').hidden = !sp;
  $('spk').title = 'Usage per hour (last 24 h)';
  // Plus d'horloge : on ne garde que l'alerte ⚠︎ si les données sont en cache
  // (l'heure de dernière maj reste dispo au survol).
  $('time').textContent = d.stale ? '⚠︎' : '';
  $('time').title = d.stale ? 'Cached data — last updated ' + d.time : 'Updated at ' + d.time;
}
const post = m => window.webkit.messageHandlers.act.postMessage(m);
$('btn-r').addEventListener('click', () => {
  $('btn-r').classList.remove('spin'); void $('btn-r').offsetWidth; $('btn-r').classList.add('spin');
  post('refresh');
});
$('btn-p').addEventListener('click', () => post('plane'));
$('login').addEventListener('click', () => {
  $('login').textContent = 'Opening browser…'; $('login').disabled = true; post('login');
});
</script>
</body></html>
"""#

final class WebPopover: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var onAction: ((String) -> Void)?
    private var ready = false
    private var pendingJS: String?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = WKUserContentController()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 248, height: 160), configuration: cfg)
        super.init()
        cfg.userContentController.add(self, name: "act")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.loadHTMLString(POPOVER_HTML, baseURL: nil)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        onAction?(message.body as? String ?? "")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        if let js = pendingJS { webView.evaluateJavaScript(js); pendingJS = nil }
    }

    func run(_ js: String) {
        if ready { webView.evaluateJavaScript(js) } else { pendingJS = js }
    }

    /// Vue de contenu du popover. Sur macOS 26+ on enveloppe la web view dans un
    /// NSGlassEffectView (Liquid Glass natif) ; repli sur la web view nue avant.
    func contentView() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular        // matériau adaptatif : garantit la lisibilité
                                          // quel que soit le fond (.clear était illisible sur blanc)
            // Voile adaptatif : rend le verre un peu moins transparent et stabilise
            // le contraste du texte. Curseur = la composante alpha ci-dessous.
            glass.tintColor = NSColor(name: nil) { app in
                let dark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return dark ? NSColor(white: 0.10, alpha: 0.32)
                            : NSColor(white: 1.00, alpha: 0.32)
            }
            glass.cornerRadius = 16
            // Masque arrondi sur la web view : coupe son bord rectangulaire (le
            // « cadre fantôme » qu'on devinait aux coins).
            webView.wantsLayer = true
            webView.layer?.cornerRadius = 16
            webView.layer?.masksToBounds = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = glass.bounds
            glass.contentView = webView
            return glass
        }
        return webView
    }
}

// MARK: - Avion-banderole ✈️

enum PlaneBanner {
    static var activeWindows: [NSWindow] = []
    static var busyUntil = Date.distantPast

    // Sérialise les vols : deux seuils franchis au même refresh → deux passages
    // successifs, pas deux banderoles superposées.
    static func fly(remaining: Int, context: String, phrase: String) {
        let now = Date()
        let start = max(now, busyUntil)
        busyUntil = start.addingTimeInterval(5.3)
        let delay = start.timeIntervalSince(now)
        if delay < 0.05 {
            flyNow(remaining: remaining, context: context, phrase: phrase)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                flyNow(remaining: remaining, context: context, phrase: phrase)
            }
        }
    }

    private static func flyNow(remaining: Int, context: String, phrase: String) {
        // Écran où se trouve la souris — c'est là que l'utilisateur regarde.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }
        let sf = screen.visibleFrame

        let image = makeBannerImage(remaining: remaining, context: context, phrase: phrase)
        let laneH = image.size.height
        let cardW = image.size.width
        let card = NSImageView(frame: NSRect(x: -cardW, y: 0, width: cardW, height: laneH))
        card.image = image
        card.imageScaling = .scaleNone
        card.wantsLayer = true

        let win = NSWindow(
            contentRect: NSRect(x: sf.minX, y: sf.maxY - laneH - 36, width: sf.width, height: laneH),
            styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: sf.width, height: laneH)))
        container.wantsLayer = true
        container.addSubview(card)
        win.contentView = container
        win.orderFrontRegardless()
        activeWindows.append(win)

        let cleanup = {
            win.orderOut(nil)
            activeWindows.removeAll { $0 === win }
        }

        if reduceMotion {
            card.frame.origin.x = (sf.width - cardW) / 2
            card.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                card.animator().alphaValue = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.6
                    card.animator().alphaValue = 0
                }, completionHandler: cleanup)
            }
            return
        }

        // Glisse depuis la gauche → pause au centre (le temps de lire) → sort à droite.
        let arrive = 0.65, dwell = 3.4, exit = 0.55
        let total = arrive + dwell + exit
        let center = (sf.width + cardW) / 2
        let out = sf.width + cardW
        let glide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        glide.values = [0, center, center, out]
        glide.keyTimes = [0,
                          NSNumber(value: arrive / total),
                          NSNumber(value: (arrive + dwell) / total),
                          1]
        glide.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(controlPoints: 0.7, 0, 0.84, 0),
        ]
        glide.duration = total
        glide.isRemovedOnCompletion = false
        glide.fillMode = .forwards
        card.layer?.add(glide, forKey: "glide")

        // Flottement discret pendant la pause.
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -2
        bob.toValue = 2
        bob.duration = 1.4
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        card.layer?.add(bob, forKey: "bob")

        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.3, execute: cleanup)
    }
}

// MARK: - App

/// Panneau flottant sans bord (façon Centre de contrôle) : pas de triangle
/// d'ancrage, fond transparent → le Liquid Glass réfracte le vrai bureau.
/// Borderless mais autorisé à devenir key pour que la web view soit interactive.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let panel = GlassPanel(contentRect: NSRect(x: 0, y: 0, width: 248, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    var clickMonitor: Any?
    let web = WebPopover()
    var state = UsageState()

    // Anti-429 : backoff + pas de refetch si les données sont fraîches.
    var backoffUntil = Date.distantPast
    var fetching = false
    var lastFetchAttempt = Date.distantPast
    // Session éphémère : aucune réponse (autorisée par token) en cache disque.
    let urlSession = URLSession(configuration: .ephemeral)

    // Seuils déjà annoncés par limite (kind → seuils), pour ne pas répéter l'avion.
    var announced: [String: Set<Int>] = [:]
    var lastPercents: [String: Int] = [:]
    let thresholds = [50, 75, 90]

    // Login OAuth en cours (empêche deux flux simultanés).
    var loggingIn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✳︎ …"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel.isOpaque = false
        panel.backgroundColor = .clear
        // L'ombre de fenêtre serait rectangulaire (forme du cadre, pas du verre) :
        // on la coupe et on laisse le NSGlassEffectView porter sa propre ombre arrondie.
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = web.contentView()

        web.onAction = { [weak self] action in
            switch action {
            case "refresh": self?.refresh(force: true)
            case "plane": self?.testPlane()
            case "login": self?.startLogin()
            default: break
            }
        }

        loadHistory()
        loadCachedState()
        refresh()
        // Endpoint pensé pour la consultation ponctuelle : 10 min suffisent,
        // le popover force un refresh si les données sont vieilles.
        let t = Timer(timeInterval: 600, repeats: true) { _ in self.refresh() }
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: Clics

    @objc func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func showContextMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(forceRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let planeItem = NSMenuItem(title: "Test the plane ✈️", action: #selector(testPlane), keyEquivalent: "")
        planeItem.target = self
        menu.addItem(planeItem)
        menu.addItem(.separator())
        let signInItem = NSMenuItem(title: "Sign in to Claude…", action: #selector(startLogin), keyEquivalent: "")
        signInItem.target = self
        menu.addItem(signInItem)
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Start with macOS", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Conso Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func togglePopover() {
        if panel.isVisible {
            closePanel()
            return
        }
        pushToWeb(animate: true)
        repositionPanel()
        panel.makeKeyAndOrderFront(nil)
        installClickMonitor()
        // Refetch seulement si les données datent (> 5 min) — sinon on garde le cache.
        if state.fetchedAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            refresh()
        }
    }

    /// Place le panneau juste sous l'icône de la barre de menu (bord haut ancré),
    /// recadré pour rester dans l'écran visible.
    func repositionPanel() {
        guard let button = statusItem.button, let bwin = button.window else { return }
        let size = popoverSize()
        let onScreen = bwin.convertToScreen(button.convert(button.bounds, to: nil))
        var x = onScreen.midX - size.width / 2
        let y = onScreen.minY - size.height - 6
        if let vf = (bwin.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vf.minX + 6), vf.maxX - size.width - 6)
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func closePanel() {
        panel.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    /// Ferme le panneau sur un clic hors de lui. On exclut l'icône de la barre
    /// de menu : c'est l'action du bouton (toggle) qui gère ce cas.
    func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if let button = self.statusItem.button, let bwin = button.window {
                let r = bwin.convertToScreen(button.convert(button.bounds, to: nil))
                if r.contains(NSEvent.mouseLocation) { return }
            }
            self.closePanel()
        }
    }

    func popoverSize() -> NSSize {
        let n = max(state.limits.count, 1)
        var h: CGFloat = 12 + CGFloat(n) * 38 + 19 + 8
        if state.error != nil { h += 22 }
        if state.needsLogin && !loggingIn { h += 34 }   // bouton « Sign in »
        let spk = sparkPayload()
        if spk.count >= 3, (spk.compactMap { $0["a"] as? Double }.max() ?? 0) >= 1800 { h += 38 }
        return NSSize(width: 248, height: h)
    }

    func pushToWeb(animate: Bool) {
        let eta = sessionEta()
        var limitsJSON: [[String: Any]] = []
        for l in state.limits {
            limitsJSON.append([
                "label": l.label,
                "percent": l.percent,
                "reset": fmtResetShort(l.resetsAt),
                "resetFull": fmtResetFull(l.resetsAt),
                "severity": l.severity,
                "session": l.isSession,
                "eta": l.isSession ? (eta ?? "") : "",
            ])
        }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        var payload: [String: Any] = [
            "limits": limitsJSON,
            "time": state.fetchedAt.map { df.string(from: $0) } ?? "",
            "stale": state.stale,
            "spark": sparkPayload(),
            "needsLogin": state.needsLogin && !loggingIn,
        ]
        if let e = state.error { payload["error"] = e }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let anim = (animate && !reduceMotion) ? "true" : "false"
        web.run("render(\(json), \(anim))")
    }

    // MARK: Actions

    @objc func forceRefresh() { refresh(force: true) }

    // Pool additionnel : phrases.json — override utilisateur dans Application
    // Support, sinon la copie embarquée dans le bundle au build. (Pas de lecture
    // dans ~/Documents : évite la demande d'accès macOS.)
    func phrasesFromDisk() -> [String: [String]] {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(appSupport.appendingPathComponent("Conso Claude/phrases.json"))
        }
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("phrases.json"))
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Cast clé par clé : le fichier contient aussi des clés
                // non-tableau (ex. "_note") qui font échouer un cast global.
                var out: [String: [String]] = [:]
                for (k, v) in obj { if let arr = v as? [String] { out[k] = arr } }
                return out
            }
        }
        return [:]
    }

    // Encouragement à l'anglaise — pools par palier, plus des variantes
    // contextuelles (nuit, vendredi soir, limite hebdo). Rotation aléatoire
    // sans resservir les 4 derniers messages affichés.
    func encouragement(remaining: Int, context: String) -> String {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let weekday = Calendar.current.component(.weekday, from: now) // 1 = dimanche
        let isNight = hour >= 23 || hour < 6
        let isFridayEvening = weekday == 6 && hour >= 17
        let isWeekly = context.lowercased().contains("weekly")

        var pool: [String]
        if remaining >= 50 {
            pool = ["Plenty of runway left.",
                    "Keep thinking big.",
                    "Halfway there — pace yourself.",
                    "The best half is still ahead.",
                    "Deep breath. Deep work.",
                    "Good thinking takes time. You have it.",
                    "Still plenty of room to be curious.",
                    "Onwards, thoughtfully."]
            if isWeekly { pool += ["A week is a marathon. Pace it."] }
        } else if remaining >= 25 {
            pool = ["Make these tokens count.",
                    "Good ideas take tokens.",
                    "Still room for one great idea.",
                    "Choose your next question well.",
                    "Quality over quantity, from here.",
                    "Sharpen the prompt, spare the tokens.",
                    "Now's the time for your best question.",
                    "Less throughput, more thought."]
            if isWeekly { pool += ["Spend the week's thinking wisely."] }
        } else {
            pool = ["Maybe it's time to rest.",
                    "Almost out — finish strong.",
                    "Land this plane gracefully.",
                    "One good prompt left. Make it sing.",
                    "Save something for tomorrow.",
                    "Great work knows when to stop.",
                    "Ship it, then step away."]
            if isWeekly { pool += ["The week's almost spent. Spend it well."] }
        }
        if isNight {
            pool += ["It's late. Great ideas keep till morning.",
                     "The tokens will still be here tomorrow.",
                     "Night shift? Make it a short one.",
                     "Maybe it's time to rest."]
        }
        if isFridayEvening {
            pool += ["It's Friday. The week forgives.",
                     "Weekend mode approaching."]
        }

        // Extension par phrases.json.
        let disk = phrasesFromDisk()
        pool += disk[remaining >= 50 ? "50" : (remaining >= 25 ? "25" : "10")] ?? []
        if isWeekly { pool += disk["weekly"] ?? [] }
        if isNight { pool += disk["night"] ?? [] }
        if isFridayEvening { pool += disk["friday"] ?? [] }

        // Éviter de resservir les derniers messages.
        var recent = UserDefaults.standard.stringArray(forKey: "recentPhrases") ?? []
        let fresh = pool.filter { !recent.contains($0) }
        let phrase = (fresh.isEmpty ? pool : fresh).randomElement() ?? pool[0]
        recent.append(phrase)
        if recent.count > 4 { recent.removeFirst(recent.count - 4) }
        UserDefaults.standard.set(recent, forKey: "recentPhrases")
        return phrase
    }

    @objc func testPlane() {
        // Chaque test tire un palier au hasard — pour voir toute la variété.
        let remaining = [50, 25, 10].randomElement()!
        PlaneBanner.fly(remaining: remaining, context: "5-hour session",
                        phrase: encouragement(remaining: remaining, context: "5-hour session"))
    }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: Login OAuth intégré

    // Flux calqué à l'identique sur `claude setup-token` (subscription) :
    // 1. on ouvre le navigateur sur la page d'autorisation Claude,
    // 2. l'utilisateur approuve → la page affiche un code (« code#state »),
    // 3. il colle ce code, on l'échange contre un token et on écrit le Keychain.
    // Pas de serveur loopback : le vrai flux n'en utilise pas (le redirect est un
    // callback hébergé par Claude).
    @objc func startLogin() {
        if loggingIn { return }
        // Garde-fou : si un token est déjà en place (Claude Code connecté sur cette
        // machine), se reconnecter l'écraserait par un token à scope plus étroit.
        // On confirme d'abord — inutile et risqué de le faire pour rien.
        if readCreds() != nil {
            let warn = NSAlert()
            warn.messageText = "Already signed in"
            warn.informativeText = "This Mac already has a Claude token (from Claude Code). "
                + "You don't need to sign in here — the usage shows automatically. "
                + "Signing in again would replace that token. Continue anyway?"
            warn.addButton(withTitle: "Cancel")
            warn.addButton(withTitle: "Sign in anyway")
            NSApp.activate(ignoringOtherApps: true)
            guard warn.runModal() == .alertSecondButtonReturn else { return }
        }
        loggingIn = true
        let verifier = randomToken()
        let stateTok = randomToken(16)
        openAuthorize(state: stateTok, challenge: pkceChallenge(verifier))

        let alert = NSAlert()
        alert.messageText = "Sign in to Claude"
        alert.informativeText = "Your browser just opened the Claude authorization page. "
            + "Approve access, copy the code shown, and paste it here."
        alert.addButton(withTitle: "Sign in")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Paste the code here"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        let pasted = alert.runModal() == .alertFirstButtonReturn
            ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !pasted.isEmpty else { loggingIn = false; return }

        // La page rend le code sous la forme « code#state ».
        let parts = pasted.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts[0]
        let retState = parts.count > 1 ? parts[1] : stateTok
        state.error = "Signing in…"; state.needsLogin = false
        if panel.isVisible { pushToWeb(animate: false); repositionPanel() }
        exchangeAsync(code: code, state: retState, verifier: verifier)
    }

    // Construit l'URL d'autorisation OAuth et l'ouvre. On encode chaque valeur
    // exactement comme `URLSearchParams` du CLI (`:` → %3A, `/` → %2F) pour que la
    // requête soit byte-identique à celle de `claude setup-token` — URLComponents
    // laisserait `:` et `/` en clair, ce qui peut faire échouer un serveur strict.
    func openAuthorize(state: String, challenge: String) {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")               // non-réservés RFC 3986
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let query = [
            "code=true",
            "client_id=\(enc(OAUTH_CLIENT_ID))",
            "response_type=code",
            "redirect_uri=\(enc(OAUTH_REDIRECT))",
            "scope=\(enc(OAUTH_SCOPES))",
            "code_challenge=\(enc(challenge))",
            "code_challenge_method=S256",
            "state=\(enc(state))",
        ].joined(separator: "&")
        if let url = URL(string: OAUTH_AUTHORIZE_URL + "?" + query) {
            NSWorkspace.shared.open(url)
        }
    }

    // Échange code→tokens en tâche de fond, puis écrit le Keychain et rafraîchit.
    func exchangeAsync(code: String, state: String, verifier: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = self.exchangeCode(code: code, state: state, verifier: verifier)
            DispatchQueue.main.async {
                self.loggingIn = false
                if ok {
                    self.state.needsLogin = false
                    self.state.error = nil
                    self.refresh(force: true)
                } else {
                    self.loginFailed("Sign-in failed — check the code and try again.")
                }
            }
        }
    }

    // POST authorization_code → tokens (essaie les deux endpoints connus), puis
    // écrit le blob claudeAiOauth dans le Keychain.
    func exchangeCode(code: String, state: String, verifier: String) -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": OAUTH_CLIENT_ID,
            "redirect_uri": OAUTH_REDIRECT,
            "code_verifier": verifier,
        ])
        let j = postToken(body: body, url: OAUTH_TOKEN_URL)
             ?? postToken(body: body, url: OAUTH_TOKEN_URL_ALT)
        guard let j = j, let access = j["access_token"] as? String else { return false }
        var oauth: [String: Any] = ["accessToken": access]
        if let rt = j["refresh_token"] as? String { oauth["refreshToken"] = rt }
        if let ei = (j["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = (Date().timeIntervalSince1970 + ei) * 1000
        }
        if let scope = j["scope"] as? String { oauth["scopes"] = scope.split(separator: " ").map(String.init) }
        return writeCreds(account: NSUserName(), full: ["claudeAiOauth": oauth])
    }

    // POST JSON synchrone vers un endpoint de token ; renvoie le JSON sur 200, sinon nil.
    func postToken(body: Data?, url: String) -> [String: Any]? {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(OAUTH_USER_AGENT, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        req.timeoutInterval = 20
        var json: [String: Any]? = nil
        let sem = DispatchSemaphore(value: 0)
        urlSession.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            json = obj
        }.resume()
        sem.wait()
        return json
    }

    func loginFailed(_ message: String) {
        loggingIn = false
        state.error = message
        updateStatusTitle()
        if panel.isVisible { pushToWeb(animate: false); repositionPanel() }
        // On NE force PAS needsLogin ici : un token valide peut très bien exister
        // (ex. sur la machine où Claude Code est connecté). Un refresh re-dérive
        // l'état réel — bouton « Sign in » seulement s'il n'y a vraiment pas de token.
        refresh(force: true)
    }

    // MARK: Seuils → avion

    func checkThresholds(_ limits: [UsageLimit]) {
        for l in limits {
            let old = lastPercents[l.kind] ?? l.percent
            if l.percent < old - 20 {
                announced[l.kind] = []
                // Petite fête : la session repart de zéro après avoir été bien entamée.
                if l.isSession && old >= 75 {
                    let resetPool = ["Fresh tokens. Clean slate.",
                                     "New session, new ideas.",
                                     "The counter is kind again."] + (phrasesFromDisk()["reset"] ?? [])
                    PlaneBanner.fly(remaining: 100 - l.percent, context: "5-hour session",
                                    phrase: resetPool.randomElement()!)
                }
            }
            for t in thresholds {
                if old < t && l.percent >= t && !(announced[l.kind, default: []].contains(t)) {
                    announced[l.kind, default: []].insert(t)
                    PlaneBanner.fly(remaining: 100 - t, context: l.label,
                                    phrase: encouragement(remaining: 100 - t, context: l.label))
                }
            }
            lastPercents[l.kind] = l.percent
        }
    }

    // MARK: Historique local (sparkline + prédiction)

    var history: [(t: Double, v: Int)] = []

    func loadHistory() {
        guard let arr = UserDefaults.standard.array(forKey: "history") as? [[Double]] else { return }
        history = arr.compactMap { $0.count == 2 ? (t: $0[0], v: Int($0[1])) : nil }
    }

    func recordHistory(sessionPercent: Int) {
        let now = Date().timeIntervalSince1970
        if let last = history.last, now - last.t < 120, last.v == sessionPercent { return }
        history.append((t: now, v: sessionPercent))
        let cutoff = now - 3 * 86400
        history.removeAll { $0.t < cutoff }
        UserDefaults.standard.set(history.map { [$0.t, Double($0.v)] }, forKey: "history")
    }

    func sparkPayload() -> [[String: Any]] {
        let now = Date().timeIntervalSince1970
        return history.filter { now - $0.t <= 24 * 3600 }.map { ["a": now - $0.t, "v": $0.v] }
    }

    // Au rythme observé, quand la session sera-t-elle à sec ?
    func sessionEta() -> String? {
        guard let session = state.limits.first(where: { $0.isSession }),
              session.percent >= 10, session.percent < 100 else { return nil }
        // Remonter la session courante : les % ne font que monter depuis le reset.
        var pts: [(t: Double, v: Int)] = []
        var ceiling = session.percent
        for h in history.reversed() {
            if h.v <= ceiling { pts.append(h); ceiling = h.v } else { break }
            if pts.count >= 18 { break }
        }
        guard pts.count >= 2 else { return nil }
        let newest = pts.first!, oldest = pts.last!
        let dt = newest.t - oldest.t
        let dv = Double(newest.v - oldest.v)
        guard dt >= 600, dv >= 1 else { return nil }
        let etaSec = (100 - Double(session.percent)) / (dv / dt)
        guard etaSec.isFinite, etaSec > 0 else { return nil }
        let eta = Date().addingTimeInterval(etaSec)
        // Si la réinitialisation arrive avant, rien à signaler.
        if let reset = session.resetsAt, eta >= reset { return nil }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "empty ~\(df.string(from: eta))"
    }

    // MARK: Cache disque (l'app relancée affiche direct les dernières données)

    func saveCachedState() {
        var arr: [[String: Any]] = []
        for l in state.limits {
            arr.append([
                "kind": l.kind, "label": l.label, "percent": l.percent,
                "severity": l.severity,
                "resetsAt": l.resetsAt.map { isoParser.string(from: $0) } ?? "",
            ])
        }
        UserDefaults.standard.set(arr, forKey: "limits")
        UserDefaults.standard.set(state.fetchedAt, forKey: "fetchedAt")
    }

    func loadCachedState() {
        guard let arr = UserDefaults.standard.array(forKey: "limits") as? [[String: Any]], !arr.isEmpty else { return }
        state.limits = arr.map { d in
            let kind = d["kind"] as? String ?? "?"
            return UsageLimit(
                kind: kind,
                label: d["label"] as? String ?? kind,
                percent: d["percent"] as? Int ?? 0,
                resetsAt: parseDate(d["resetsAt"] as? String),
                severity: d["severity"] as? String ?? "normal",
                isSession: kind == "session")
        }
        state.fetchedAt = UserDefaults.standard.object(forKey: "fetchedAt") as? Date
        state.stale = true
        updateStatusTitle()
    }

    // MARK: Fetch

    // Exécute `/usr/bin/security` et renvoie sa sortie standard.
    func runSecurity(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // Lit le blob OAuth complet dans le Keychain (accessToken + refreshToken + expiry).
    func readCreds() -> KeychainCreds? {
        guard let blob = runSecurity(["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"]),
              let data = blob.data(using: .utf8),
              let full = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = full["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        // Le compte du même item (nécessaire pour réécrire au bon endroit).
        var account = NSUserName()
        if let attrs = runSecurity(["find-generic-password", "-s", KEYCHAIN_SERVICE]),
           let m = attrs.range(of: #"(?<="acct"<blob>=")[^"]*"#, options: .regularExpression) {
            account = String(attrs[m])
        }
        return KeychainCreds(
            account: account, full: full, oauth: oauth,
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAtMs: (oauth["expiresAt"] as? NSNumber)?.doubleValue
        )
    }

    // Réécrit le blob OAuth mis à jour dans le Keychain (met à jour l'item existant).
    func writeCreds(account: String, full: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: full),
              let str = String(data: data, encoding: .utf8) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["add-generic-password", "-U", "-a", account, "-s", KEYCHAIN_SERVICE, "-w", str]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // Renouvelle le token via le refreshToken puis réécrit le Keychain (rotation
    // incluse : on persiste le nouveau refreshToken pour rester en phase avec
    // Claude Code). Renvoie le nouvel accessToken, ou nil si l'échange a échoué.
    func refreshOAuthToken() -> String? {
        guard let creds = readCreds(), let rt = creds.refreshToken else { return nil }
        var req = URLRequest(url: URL(string: OAUTH_TOKEN_URL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Cloudflare bloque certains User-Agent (erreur 1010) : on force celui du CLI.
        req.setValue(OAUTH_USER_AGENT, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": OAUTH_CLIENT_ID,
        ])
        req.timeoutInterval = 15
        var json: [String: Any]? = nil
        let sem = DispatchSemaphore(value: 0)
        urlSession.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            json = obj
        }.resume()
        sem.wait()
        guard let j = json, let access = j["access_token"] as? String else { return nil }
        var oauth = creds.oauth
        oauth["accessToken"] = access
        if let newRt = j["refresh_token"] as? String { oauth["refreshToken"] = newRt }
        if let expiresIn = (j["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        var full = creds.full
        full["claudeAiOauth"] = oauth
        guard writeCreds(account: creds.account, full: full) else { return nil }
        return access
    }

    // Appel synchrone de l'API usage. Renvoie (réponse HTTP, données, erreur réseau).
    func performUsageRequest(token: String) -> (HTTPURLResponse?, Data?, Error?) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        var out: (HTTPURLResponse?, Data?, Error?) = (nil, nil, nil)
        let sem = DispatchSemaphore(value: 0)
        urlSession.dataTask(with: req) { data, resp, err in
            out = (resp as? HTTPURLResponse, data, err)
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    func refresh(force: Bool = false) {
        guard !fetching else { return }
        if force, Date().timeIntervalSince(lastFetchAttempt) < 3 { return }
        guard force || Date() >= backoffUntil else { return }
        lastFetchAttempt = Date()
        fetching = true
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { self.fetching = false } }
            guard let creds = self.readCreds() else {
                DispatchQueue.main.async { self.state.needsLogin = true }
                self.apply(limits: nil, error: "Not signed in to Claude.")
                return
            }
            // Un token lisible existe → on n'a JAMAIS besoin de « Sign in » (on sait
            // le rafraîchir nous-mêmes). On lève tout de suite un éventuel needsLogin
            // resté collé après un essai de login manuel raté.
            DispatchQueue.main.async { self.state.needsLogin = false }
            var token = creds.accessToken
            var didRefresh = false
            // Proactif : token déjà expiré (ou dans < 1 min) → on le renouvelle nous-mêmes.
            let nowMs = Date().timeIntervalSince1970 * 1000
            if let exp = creds.expiresAtMs, nowMs >= exp - 60_000,
               let fresh = self.refreshOAuthToken() {
                token = fresh
                didRefresh = true
            }
            var (resp, data, err) = self.performUsageRequest(token: token)
            // 401 malgré un token censé valide → une tentative de refresh + retry.
            if resp?.statusCode == 401, !didRefresh, let fresh = self.refreshOAuthToken() {
                token = fresh
                (resp, data, err) = self.performUsageRequest(token: token)
            }
            self.handleUsageResponse(resp: resp, data: data, err: err)
        }
    }

    func handleUsageResponse(resp: HTTPURLResponse?, data: Data?, err: Error?) {
        if let err = err {
            self.apply(limits: nil, error: "Network: \(err.localizedDescription)")
            return
        }
        guard let http = resp, let data = data else {
            self.apply(limits: nil, error: "No response from the API.")
            return
        }
        if http.statusCode == 429 {
            // Rate-limité : backoff silencieux — le cache reste affiché avec
            // juste le ⚠ à côté de l'heure, pas de message anxiogène.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 900
            let pause = max(900, min(retryAfter, 3600))
            DispatchQueue.main.async {
                self.backoffUntil = Date().addingTimeInterval(pause)
                self.state.stale = !self.state.limits.isEmpty
                self.state.error = self.state.limits.isEmpty
                    ? "API limit reached — retrying in \(Int(pause / 60)) min."
                    : nil
                self.updateStatusTitle()
                if self.panel.isVisible {
                    self.pushToWeb(animate: false)
                    self.repositionPanel()
                }
            }
            return
        }
        if http.statusCode == 401 {
            // Le refresh automatique a lui aussi échoué → reconnexion nécessaire.
            DispatchQueue.main.async { self.state.needsLogin = true }
            self.apply(limits: nil, error: "Session expired — sign in again.")
            return
        }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLimits = json["limits"] as? [[String: Any]] else {
            self.apply(limits: nil, error: "API: HTTP \(http.statusCode)")
            return
        }
        var limits: [UsageLimit] = []
        for l in rawLimits {
            let kind = l["kind"] as? String ?? "?"
            var label: String
            switch kind {
            case "session": label = "5-hour session"
            case "weekly_all": label = "Weekly — all models"
            case "weekly_scoped":
                let scope = l["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                label = "Weekly — \(model?["display_name"] as? String ?? "model")"
            default: label = kind
            }
            limits.append(UsageLimit(
                kind: kind,
                label: label,
                percent: (l["percent"] as? NSNumber)?.intValue ?? 0,
                resetsAt: parseDate(l["resets_at"] as? String),
                severity: l["severity"] as? String ?? "normal",
                isSession: kind == "session"
            ))
        }
        self.apply(limits: limits, error: nil)
    }

    func apply(limits: [UsageLimit]?, error: String?) {
        DispatchQueue.main.async {
            self.state.error = error
            if let limits = limits {
                self.state.limits = limits
                self.state.fetchedAt = Date()
                self.state.stale = false
                self.state.needsLogin = false
                self.checkThresholds(limits)
                self.saveCachedState()
                if let s = limits.first(where: { $0.isSession }) {
                    self.recordHistory(sessionPercent: s.percent)
                }
            } else if error != nil {
                self.state.stale = !self.state.limits.isEmpty
            }
            self.updateStatusTitle()
            if self.panel.isVisible {
                self.pushToWeb(animate: false)
                self.repositionPanel()
            }
        }
    }

    func updateStatusTitle() {
        if state.limits.isEmpty {
            if state.error != nil {
                statusItem.button?.attributedTitle = NSAttributedString(
                    string: "✳︎ !", attributes: [.foregroundColor: NSColor.systemOrange])
            }
            return
        }
        guard let session = state.limits.first(where: { $0.isSession }) else { return }
        // On affiche le % RESTANT (100 − consommé), cohérent avec l'avion (« il te reste X % »).
        // Pas de dégradé de couleur : blanc (labelColor) tout du long, rouge seulement à ≤ 10 %.
        let remaining = 100 - session.percent
        let crit = remaining <= 10
        let accent: NSColor = crit ? .systemRed : .labelColor
        // Même taille que les autres extras du menu bar (batterie, etc.) : ~11pt, poids regular.
        // Mesuré : la batterie rend plus petit que systemFontSize (13pt) → smallSystemFontSize.
        // On ne passe en gras que dans le rouge (≤ 10 %), pour attirer l'œil.
        let barSize = NSFont.smallSystemFontSize
        let title = NSMutableAttributedString(string: "✳︎ ", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: barSize),
        ])
        title.append(NSAttributedString(string: "\(remaining) %", attributes: [
            .foregroundColor: accent,
            .font: NSFont.monospacedDigitSystemFont(ofSize: barSize, weight: crit ? .bold : .regular),
        ]))
        statusItem.button?.attributedTitle = title
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
