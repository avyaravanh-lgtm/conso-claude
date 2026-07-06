// Conso Claude — app barre de menus macOS.
// Clic → popover compact (web view : CSS glass, barres springs, compteurs).
// Franchissement de seuil → avion-banderole qui traverse l'écran ✈️.
// Clic droit sur l'icône → menu (démarrage, test avion, quitter).

import Cocoa
import WebKit
import ServiceManagement

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
    if h >= 24 { return "\(h / 24) j \(h % 24) h" }
    if h > 0 { return "\(h) h \(String(format: "%02d", m))" }
    return "\(m) min"
}

func fmtResetFull(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let df = DateFormatter()
    df.locale = Locale(identifier: "fr_FR")
    df.dateFormat = "EEEE d MMMM 'à' HH:mm"
    return "Réinitialisation \(df.string(from: d))"
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
.label { font-size:11px; font-weight:500; color: light-dark(rgba(20,18,15,.55), rgba(245,240,232,.55));
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
#spk { margin:-2px 0 8px; color: light-dark(rgba(20,18,15,.8), rgba(245,240,232,.8)); }
.eta { color:#e8940c; }
#foot { display:flex; align-items:center; gap:4px; margin-top:1px; }
.btn { width:20px; height:18px; display:flex; align-items:center; justify-content:center;
  border-radius:5px; color: light-dark(rgba(20,18,15,.35), rgba(245,240,232,.38)); }
.btn:hover { color: light-dark(rgba(20,18,15,.75), rgba(245,240,232,.8));
  background: light-dark(rgba(20,18,15,.06), rgba(245,240,232,.08)); }
.btn svg { width:12px; height:12px; }
.btn:active svg { transform: scale(.85); }
#btn-r.spin svg { animation: rot .5s ease; }
@keyframes rot { to { transform: rotate(360deg); } }
#time { margin-left:auto; font-size:9px; font-variant-numeric:tabular-nums;
  color: light-dark(rgba(20,18,15,.25), rgba(245,240,232,.28)); }
</style></head><body>
<div id="rows"></div>
<div id="err" hidden></div>
<div id="spk" hidden></div>
<div id="foot">
  <div class="btn" id="btn-r" title="Rafraîchir"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 1.5v3h-3"/></svg></div>
  <div class="btn" id="btn-p" title="Tester l'avion"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M14.5 1.5 1.5 6.8l4.2 1.9m8.8-7.2L9.2 14.5 7.3 10.3m7.2-8.8L5.7 8.7"/></svg></div>
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
  // Fenêtre adaptative : la courbe remplit toute la largeur, 6 h max.
  const W = 220, H = 28, win = Math.min(Math.max(span, 1800), 6 * 3600);
  const xs = p => W - (Math.min(p.a, win) / win) * W;
  const ys = p => H - 3 - (p.v / 100) * (H - 9);
  const sorted = points.slice().sort((a, b) => b.a - a.a);
  let d = '';
  sorted.forEach((p, i) => { d += (i ? 'L' : 'M') + xs(p).toFixed(1) + ',' + ys(p).toFixed(1); });
  const last = sorted[sorted.length - 1];
  const area = d + 'L' + xs(last).toFixed(1) + ',' + (H - 3) + 'L' + xs(sorted[0]).toFixed(1) + ',' + (H - 3) + 'Z';
  const label = win >= 5400 ? Math.round(win / 3600) + ' H' : Math.round(win / 60) + ' MIN';
  const mid = H - 3 - (H - 9) / 2;
  return '<svg width="' + W + '" height="' + H + '" style="display:block">' +
    '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">' +
    '<stop offset="0" stop-color="#d97757" stop-opacity=".28"/>' +
    '<stop offset="1" stop-color="#d97757" stop-opacity="0"/></linearGradient></defs>' +
    '<line x1="0" y1="' + (H - 3) + '" x2="' + W + '" y2="' + (H - 3) + '" stroke="currentColor" opacity=".15"/>' +
    '<line x1="0" y1="' + mid + '" x2="' + W + '" y2="' + mid + '" stroke="currentColor" opacity=".07" stroke-dasharray="2 3"/>' +
    '<text x="1" y="7" font-size="6.5" fill="currentColor" opacity=".4" letter-spacing="1.2">SESSION · ' + label + '</text>' +
    '<path d="' + area + '" fill="url(#g)"/>' +
    '<path d="' + d + '" fill="none" stroke="#d97757" stroke-width="1.5" stroke-linejoin="round" opacity=".9"/></svg>';
}
function render(d, animate) {
  const rows = $('rows');
  rows.innerHTML = '';
  d.limits.forEach((l, i) => {
    const s = sev(l);
    const row = document.createElement('div');
    row.className = 'row' + (l.session ? ' session' : '');
    row.title = 'reste ' + (100 - l.percent) + ' % · ' + l.resetFull;
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
  const sp = spark(d.spark);
  $('spk').innerHTML = sp;
  $('spk').hidden = !sp;
  $('spk').title = 'Consommation de la session dans le temps (6 h max)';
  $('time').textContent = (d.stale ? '⚠︎ ' : '') + (d.time || '');
  $('time').title = d.stale ? 'Données en cache — dernière mise à jour ' + d.time : 'Mis à jour à ' + d.time;
}
const post = m => window.webkit.messageHandlers.act.postMessage(m);
$('btn-r').addEventListener('click', () => {
  $('btn-r').classList.remove('spin'); void $('btn-r').offsetWidth; $('btn-r').classList.add('spin');
  post('refresh');
});
$('btn-p').addEventListener('click', () => post('plane'));
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let contentVC = NSViewController()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✳︎ …"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        contentVC.view = web.webView
        popover.contentViewController = contentVC
        popover.behavior = .transient
        popover.animates = true

        web.onAction = { [weak self] action in
            switch action {
            case "refresh": self?.refresh(force: true)
            case "plane": self?.testPlane()
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
        let refreshItem = NSMenuItem(title: "Rafraîchir", action: #selector(forceRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let planeItem = NSMenuItem(title: "Tester l'avion ✈️", action: #selector(testPlane), keyEquivalent: "")
        planeItem.target = self
        menu.addItem(planeItem)
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Lancer au démarrage du Mac", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Conso Claude", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        pushToWeb(animate: true)
        popover.contentSize = popoverSize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Refetch seulement si les données datent (> 5 min) — sinon on garde le cache.
        if state.fetchedAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            refresh()
        }
    }

    func popoverSize() -> NSSize {
        let n = max(state.limits.count, 1)
        var h: CGFloat = 12 + CGFloat(n) * 38 + 19 + 8
        if state.error != nil { h += 22 }
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
        let isWeekly = context.lowercased().contains("hebdo")

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
        PlaneBanner.fly(remaining: remaining, context: "Session 5 h",
                        phrase: encouragement(remaining: remaining, context: "Session 5 h"))
    }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
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
                    PlaneBanner.fly(remaining: 100 - l.percent, context: "Session 5 h",
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
        return history.filter { now - $0.t <= 6 * 3600 }.map { ["a": now - $0.t, "v": $0.v] }
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
        return "à sec ~\(df.string(from: eta))"
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

    func getToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }

    func refresh(force: Bool = false) {
        guard !fetching else { return }
        if force, Date().timeIntervalSince(lastFetchAttempt) < 3 { return }
        guard force || Date() >= backoffUntil else { return }
        lastFetchAttempt = Date()
        fetching = true
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { self.fetching = false } }
            guard let token = self.getToken() else {
                self.apply(limits: nil, error: "Token introuvable — ouvre Claude Code puis rafraîchis.")
                return
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.timeoutInterval = 15
            let sem = DispatchSemaphore(value: 0)
            self.urlSession.dataTask(with: req) { data, resp, err in
                defer { sem.signal() }
                if let err = err {
                    self.apply(limits: nil, error: "Réseau : \(err.localizedDescription)")
                    return
                }
                guard let http = resp as? HTTPURLResponse, let data = data else {
                    self.apply(limits: nil, error: "Pas de réponse de l'API.")
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
                            ? "Limite API atteinte — réessai dans \(Int(pause / 60)) min."
                            : nil
                        self.updateStatusTitle()
                        if self.popover.isShown {
                            self.pushToWeb(animate: false)
                            self.popover.contentSize = self.popoverSize()
                        }
                    }
                    return
                }
                if http.statusCode == 401 {
                    self.apply(limits: nil, error: "Token expiré — ouvre Claude Code puis rafraîchis.")
                    return
                }
                guard http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawLimits = json["limits"] as? [[String: Any]] else {
                    self.apply(limits: nil, error: "API : HTTP \(http.statusCode)")
                    return
                }
                var limits: [UsageLimit] = []
                for l in rawLimits {
                    let kind = l["kind"] as? String ?? "?"
                    var label: String
                    switch kind {
                    case "session": label = "Session 5 h"
                    case "weekly_all": label = "Hebdo — tous modèles"
                    case "weekly_scoped":
                        let scope = l["scope"] as? [String: Any]
                        let model = scope?["model"] as? [String: Any]
                        label = "Hebdo — \(model?["display_name"] as? String ?? "modèle")"
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
            }.resume()
            sem.wait()
        }
    }

    func apply(limits: [UsageLimit]?, error: String?) {
        DispatchQueue.main.async {
            self.state.error = error
            if let limits = limits {
                self.state.limits = limits
                self.state.fetchedAt = Date()
                self.state.stale = false
                self.checkThresholds(limits)
                self.saveCachedState()
                if let s = limits.first(where: { $0.isSession }) {
                    self.recordHistory(sessionPercent: s.percent)
                }
            } else if error != nil {
                self.state.stale = !self.state.limits.isEmpty
            }
            self.updateStatusTitle()
            if self.popover.isShown {
                self.pushToWeb(animate: false)
                self.popover.contentSize = self.popoverSize()
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
        let warn = session.percent >= 70 || session.severity == "warning" || session.severity == "critical"
        let accent: NSColor = session.percent >= 90 || session.severity == "critical"
            ? .systemRed
            : (warn ? .systemOrange : .labelColor)
        let title = NSMutableAttributedString(string: "✳︎ ", attributes: [.foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(string: "\(session.percent) %", attributes: [
            .foregroundColor: accent,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: warn ? .bold : .medium),
        ]))
        statusItem.button?.attributedTitle = title
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
