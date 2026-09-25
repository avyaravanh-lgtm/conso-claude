// Conso Claude — app barre de menus macOS.
// Clic → popover compact (web view : CSS glass, barres springs, compteurs).
// Franchissement de seuil → avion-banderole qui traverse l'écran ✈️.
// Clic droit sur l'icône → menu (démarrage, test avion, quitter).

import Cocoa
import WebKit
import ServiceManagement
import CryptoKit   // SHA256 pour le challenge PKCE du login indépendant
import Network     // serveur loopback (retour du navigateur) du login indépendant

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
    // État BÉNIN et FRÉQUENT (≈ chaque soir) : le jeton de Claude Code a expiré et
    // l'app, lectrice seule, attend simplement que Claude Code le renouvelle au prochain
    // usage. Distinct de `error` : ce n'est pas une panne, donc on l'affiche en gris
    // discret et sans « Session expired » anxiogène (voir SESSION_WAIT_MSG,
    // waitForClaudeCode, et le rendu `.calm` dans le popover). Mutuellement exclusif
    // avec `error` : entrer en attente efface l'erreur, et toute vraie erreur/succès
    // efface l'attente.
    var waiting = false
}

// DEUX entrées de Trousseau, deux rôles bien séparés — c'est ce qui rend le jeton
// indépendant SÛR, là où le partage a tué la session le 14/09/2026 :
//
//  • CLAUDE_KEYCHAIN — le jeton de Claude Code. Conso le LIT (repli) mais ne le
//    RÉÉCRIT JAMAIS. Motif du 14/09 : le refreshToken de Claude Code est à usage
//    unique et tourne à chaque échange ; deux clients qui rafraîchissent LA MÊME
//    entrée finissent par présenter un jeton déjà consommé → mort pour tout le monde.
//
//  • CONSO_KEYCHAIN — le jeton PROPRE de Conso, obtenu par SON login (startLogin).
//    Conso le lit ET le rafraîchit, mais dans SA propre entrée : aucune entrée n'est
//    partagée, donc aucune rotation ne peut se marcher dessus. writeConsoCreds n'écrit
//    QUE là — jamais dans CLAUDE_KEYCHAIN (invariant vérifiable, un seul chemin d'écriture).
//
// readCreds() préfère l'entrée de Conso ; à défaut elle emprunte celle de Claude Code
// en lecture seule (comportement historique). Si Conso a son propre jeton, elle reste
// live en permanence ; sinon elle se comporte comme avant (attend Claude Code).
let KEYCHAIN_SERVICE = "Claude Code-credentials"   // = CLAUDE_KEYCHAIN (repli, lecture seule)
let CONSO_KEYCHAIN   = "Conso Claude-credentials"  // jeton propre de Conso (lecture + écriture)

// Client OAuth public de Claude Code (RFC 8252 : redirect loopback autorisé, PKCE S256).
// Conso réutilise ce client_id pour SA propre autorisation — une 3ᵉ autorisation qui
// coexiste avec celles du mini et du MacBook (déjà deux jetons indépendants du même
// compte qui vivent côte à côte). Rien de secret ici : c'est un identifiant public.
let OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
// Endpoints RELEVÉS dans la config du vrai CLI `claude` (bundle, 25/09/2026) :
//   CONSOLE_AUTHORIZE_URL  = https://platform.claude.com/oauth/authorize   (comptes API/Console)
//   CLAUDE_AI_AUTHORIZE_URL= https://claude.com/cai/oauth/authorize        (abonnement claude.ai / Max)
//   TOKEN_URL              = https://platform.claude.com/v1/oauth/token
// Monsieur est en **Max** → autorisation par la voie claude.ai (CLAUDE_AI_AUTHORIZE_URL).
// L'échec « Invalid request format » du 25/09 venait du REDIRECT loopback `localhost` (non
// accepté par le client) ; on passe donc par le callback HÉBERGÉ + collage du code, exactement
// comme `claude` en CLI. Le token s'échange sur platform.claude.com (repli api.anthropic.com).
let OAUTH_TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
let OAUTH_TOKEN_URL_ALT = "https://api.anthropic.com/v1/oauth/token"
let OAUTH_AUTHORIZE_URL = "https://claude.com/cai/oauth/authorize"
// Scopes RÉELLEMENT accordés à un login claude.ai/Max (relevés dans le jeton de Claude
// Code : user:inference/profile/sessions:claude_code/mcp_servers/file_upload). ⚠️ SURTOUT
// PAS `org:create_api_key` : c'est un scope Console/org qu'un compte perso Max n'a pas —
// il est toléré à l'affichage du consentement mais fait échouer le CALLBACK
// (« Invalid request format », constaté le 25/09). Ce sont d'ailleurs exactement les
// permissions listées sur la page de consentement.
let OAUTH_SCOPES = "user:inference user:profile user:sessions:claude_code user:mcp_servers user:file_upload"
let OAUTH_REDIRECT_MANUAL = "https://platform.claude.com/oauth/code/callback"
// Cloudflare bloque certains User-Agent (erreur 1010) : on force celui du CLI.
let OAUTH_USER_AGENT = "claude-cli/1.0 (external, cli)"

// Message affiché quand le jeton de Claude Code a expiré. On est LECTEUR SEUL : on ne
// renouvelle jamais le jeton, c'est Claude Code qui le fait — et il ne le fait qu'au
// moment d'un VRAI appel (pas juste parce qu'une fenêtre est ouverte, restée oisive depuis
// avant l'expiration). Le jeton de Claude Code expire ainsi ≈ chaque soir/nuit et le reste
// TANT QUE Monsieur ne se sert pas de Claude Code — c.-à-d. des heures durant, chaque nuit
// (constaté dans oauth.log : expiration ~17-18h, reprise le lendemain matin au premier
// usage). Ce n'est donc PAS une panne, c'est le fonctionnement normal d'un lecteur seul —
// et l'afficher en orange « Session expired » chaque soir, c'est crier au feu tous les
// jours. Le texte est donc CALME et honnête (« en pause, ça repart au prochain usage »),
// et il s'affiche en GRIS discret, pas en orange d'alerte (drapeau `waiting`, pas `error` ;
// voir UsageState.waiting, waitForClaudeCode, et le rendu `.calm` dans le popover). Conso
// repart tout seul dès que Claude Code repose un jeton frais (poll 1/min + relecture à
// l'ouverture du popover). Voir waitForClaudeCode / pollKeychainIfWaiting.
let SESSION_WAIT_MSG = "Paused — refreshes next time you use Claude Code."

// Journal du flux de login OAuth — ÉVÉNEMENTS uniquement, JAMAIS de secret : aucun
// token, code, verifier ni refreshToken n'y entre (on n'y met que des statuts, ports,
// hôtes et raisons d'erreur). But : diagnostiquer un échec de reconnexion sur le VRAI
// bundle, où stdout n'existe pas. Écrit dans
// ~/Library/Application Support/Conso Claude/oauth.log, borné à ~64 KB (retroncage par
// la fin, on garde l'historique récent).
let oauthLogURL: URL? = {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("Conso Claude", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("oauth.log")
}()
let oauthLogQueue = DispatchQueue(label: "conso.oauthlog")
let oauthLogStamp: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
}()
func oauthLog(_ message: String) {
    guard let url = oauthLogURL else { return }
    let when = Date()
    // Tout se passe sur une file série : DateFormatter et le fichier n'y sont jamais
    // touchés en concurrence, quel que soit le thread appelant.
    oauthLogQueue.async {
        let line = "[\(oauthLogStamp.string(from: when))] \(message)\n"
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        text += line
        if text.utf8.count > 64_000 { text = "…\n" + String(text.suffix(40_000)) }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// D'où vient le jeton courant. `own` = l'entrée PROPRE de Conso (on peut la rafraîchir
// et la réécrire) ; `claudeCode` = jeton EMPRUNTÉ à Claude Code (lecture seule, jamais
// réécrit — on attend que Claude Code le renouvelle). Cette distinction décide, à chaque
// refresh, si Conso a le droit de renouveler le jeton elle-même.
enum CredsSource { case own, claudeCode }

// Ce qu'on lit du Trousseau. Pour l'entrée EMPRUNTÉE (Claude Code), seuls accessToken +
// expiresAt servent (on ne réécrit jamais). Pour l'entrée PROPRE de Conso, on garde aussi
// le blob complet + le refreshToken, nécessaires pour rafraîchir et réécrire NOTRE entrée.
struct KeychainCreds {
    let source: CredsSource
    let account: String
    let full: [String: Any]      // blob complet (contient "claudeAiOauth")
    let oauth: [String: Any]     // full["claudeAiOauth"]
    let accessToken: String
    let refreshToken: String?
    let expiresAtMs: Double?
}

// base64url sans padding — encodage attendu par le challenge PKCE et le state.
func b64url(_ d: Data) -> String {
    Data(d).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
// Jeton aléatoire cryptographique (verifier PKCE, state anti-CSRF). Si le CSPRNG système
// échouait (quasi impossible), on ne renvoie SURTOUT pas des octets nuls (verifier
// prévisible) : repli sur le générateur système.
func randomToken(_ n: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: n)
    if SecRandomCopyBytes(kSecRandomDefault, n, &bytes) != errSecSuccess {
        var rng = SystemRandomNumberGenerator()
        for i in 0..<n { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
    }
    return b64url(Data(bytes))
}
// challenge = base64url(SHA256(verifier)) — méthode S256.
func pkceChallenge(_ verifier: String) -> String {
    b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
}

// Petit serveur HTTP sur l'interface loopback : capte le retour du navigateur
// (`/callback?code=…&state=…`) sans copier-coller. Rien n'est exposé au réseau local.
final class OAuthLoopback {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var fired = false
    private var settled = false               // le port n'est livré qu'une seule fois
    private(set) var lastStartError: String?  // raison lisible d'un échec (→ journal)
    var onResult: ((_ code: String?, _ state: String?) -> Void)?

    // Démarre l'écoute et livre le port par `completion` (sur le main thread) quand le
    // listener passe .ready — ou nil (+ lastStartError) sur échec / attente trop longue.
    func start(completion: @escaping (UInt16?) -> Void) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback   // lo0 : couvre 127.0.0.1 et ::1
        guard let l = try? NWListener(using: params) else {
            lastStartError = "NWListener init a échoué"
            DispatchQueue.main.async { completion(nil) }
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        let deliver: (UInt16?) -> Void = { [weak self] port in
            DispatchQueue.main.async {
                guard let self = self, !self.settled else { return }
                self.settled = true
                completion(port)
            }
        }
        l.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready:          deliver(l.port?.rawValue)
            case .waiting(let e): self?.lastStartError = "waiting(\(e))"
            case .failed(let e):  self?.lastStartError = "failed(\(e))"; deliver(nil)
            case .cancelled:      deliver(nil)
            default: break
            }
        }
        l.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !self.settled else { return }
            if self.lastStartError == nil { self.lastStartError = "timeout — jamais .ready" }
            deliver(nil)
        }
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self else { return }
            var code: String?, state: String?
            if let data = data, let req = String(data: data, encoding: .utf8),
               let line = req.split(separator: "\r\n").first,
               let path = line.split(separator: " ").dropFirst().first,
               let comps = URLComponents(string: "http://localhost\(path)") {
                for item in comps.queryItems ?? [] {
                    if item.name == "code" { code = item.value }
                    if item.name == "state" { state = item.value }
                }
            }
            let ok = code != nil
            let body = ok
                ? "<h2>Signed in \u{2713}</h2><p>You can close this tab and return to Conso&nbsp;Claude.</p>"
                : "<h2>Sign-in failed</h2><p>Please try again from the app.</p>"
            let html = "<!doctype html><meta charset=utf-8><title>Conso Claude</title>" +
                "<body style='font:16px -apple-system;text-align:center;margin-top:18vh;color:#333'>\(body)</body>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            if ok, !self.fired { self.fired = true; self.onResult?(code, state) }
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
    }
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
html,body { background: light-dark(#f5f0e8, #201d19); overflow:hidden; }
body {
  font: 12px/1.4 -apple-system, "SF Pro Text", sans-serif;
  color: light-dark(rgba(20,18,15,.88), rgba(245,240,232,.92));
  padding: 12px 14px 8px;
}
.row { margin-bottom: 12px; }
.line { display:flex; align-items:baseline; margin-bottom:5px; }
/* min-width:0 : sans lui, un flex item refuse de descendre sous la largeur de son
   contenu (min-width:auto par défaut) et l'ellipsis ne se déclenche jamais — le
   libellé pousse alors la meta au lieu de se tronquer. */
.label { font-size:11px; font-weight:500; color: light-dark(rgba(20,18,15,.6), rgba(245,240,232,.6));
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis; min-width:0; }
.session .label { font-weight:600; color: light-dark(rgba(20,18,15,.85), rgba(245,240,232,.9)); }
/* flex-shrink:0 + nowrap : la meta (prédiction · reset · %) garde toujours UNE seule
   ligne. Le libellé absorbe tout le rétrécissement. C'est l'invariant sur lequel
   repose popoverSize() (38 px/ligne) : si une ligne passe sur deux rangées, le total
   calculé est faux et le footer (↻ ✈︎ version) sort de body{overflow:hidden}. */
.meta { margin-left:auto; display:flex; gap:7px; align-items:baseline; flex-shrink:0; }
.reset { font-size:9.5px; font-variant-numeric:tabular-nums; white-space:nowrap;
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
/* Attente bénigne (jeton expiré → Conso attend Claude Code, ≈ chaque soir) : gris
   discret, jamais l'orange d'alerte — ce n'est pas une panne. */
#err.calm { color: light-dark(rgba(20,18,15,.4), rgba(245,240,232,.42)); }
/* Bloc d'INFO (pas un bouton) : l'app ne fait plus le login elle-même — elle est
   lectrice du jeton de Claude Code. On renvoie donc vers Claude Code / `claude auth
   login` au lieu d'ouvrir un navigateur. */
#login { display:block; margin:2px 0 8px; padding:8px 10px; border-radius:8px;
  font:12px/1.4 -apple-system; text-align:left;
  color: light-dark(rgba(20,18,15,.82), rgba(245,240,232,.85));
  background: light-dark(rgba(20,18,15,.05), rgba(245,240,232,.06));
  border:.5px solid light-dark(rgba(20,18,15,.09), rgba(245,240,232,.1)); }
/* Sans ça, `#login { display:block }` bat l'attribut [hidden] (spécificité id >
   attribut) et le bloc reste TOUJOURS visible, même needsLogin=false. */
#login[hidden] { display:none; }
#login b { font-weight:600; }
#login code { font:11px ui-monospace, Menlo, monospace; padding:1px 4px; border-radius:4px;
  background: light-dark(rgba(20,18,15,.07), rgba(245,240,232,.09)); }
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
#ver { font-size:9px; margin-left:6px; color: light-dark(rgba(20,18,15,.22), rgba(245,240,232,.25)); }
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
<div id="login" hidden></div>
<div id="spk" hidden></div>
<div id="foot">
  <div class="btn" id="btn-r" title="Refresh"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M13.5 8a5.5 5.5 0 1 1-1.6-3.9M13.5 1.5v3h-3"/></svg></div>
  <div class="btn" id="btn-p" title="Test the plane"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M14.5 1.5 1.5 6.8l4.2 1.9m8.8-7.2L9.2 14.5 7.3 10.3m7.2-8.8L5.7 8.7"/></svg></div>
  <span id="time"></span>
  <span id="ver"></span>
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
  // Le message d'erreur et le bloc de connexion ne coexistent pas : quand on
  // propose de se connecter, l'instruction se suffit à elle-même.
  $('err').hidden = !d.error || d.needsLogin;
  $('err').textContent = d.error || '';
  // Attente calme (jeton expiré) en gris ; vraie erreur en orange.
  $('err').classList.toggle('calm', !!d.calm);
  const lg = $('login');
  lg.hidden = !d.needsLogin;
  // Contenu figé (aucune donnée utilisateur) → innerHTML sûr.
  lg.innerHTML = '<b>Sign in with Claude Code</b><br>Run <code>claude auth login</code> in your terminal (or open Claude Code), then refresh ↻.';
  const sp = spark(d.spark);
  $('spk').innerHTML = sp;
  $('spk').hidden = !sp;
  $('spk').title = 'Usage per hour (last 24 h)';
  // Plus d'horloge : on ne garde que l'alerte ⚠︎ si les données sont en cache
  // (l'heure de dernière maj reste dispo au survol).
  $('time').textContent = d.stale ? '⚠︎' : '';
  $('time').title = d.stale ? 'Cached data — last updated ' + d.time : 'Updated at ' + d.time;
  $('ver').textContent = d.version ? 'v' + d.version : '';
  // La fenêtre native se dimensionne sur la hauteur RÉELLE du contenu, mesurée ici
  // après mise en page (rAF). Fini les hauteurs devinées à la main dans popoverSize()
  // qui coupaient le bas dès qu'un cas dépassait la supposition (prédiction, message
  // « Paused » sur 2 lignes, etc.). body{overflow:hidden} garde scrollHeight juste
  // même quand le contenu déborde le cadre courant.
  requestAnimationFrame(() => post('h:' + Math.ceil(document.body.scrollHeight)));
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

    /// Vue de contenu du popover : carte arrondie **opaque**. On a abandonné le
    /// Liquid Glass (NSGlassEffectView) ET le matériau frosté (NSVisualEffectView) :
    /// tous deux laissaient transparaître/refléter le fond derrière la fenêtre, ce
    /// qui produisait un glint coloré au coin haut-gauche (ex. un onglet vert
    /// derrière → coin verdâtre). Un fond solide (couleur adaptative peinte par le
    /// HTML) garantit un rendu net et identique sur n'importe quel fond. Les coins
    /// arrondis (squircle continu) viennent du masque de calque de la web view, et
    /// une hairline discrète détache la carte des fonds clairs.
    func contentView() -> NSView {
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 16
        webView.layer?.cornerCurve = .continuous
        webView.layer?.masksToBounds = true
        webView.layer?.borderWidth = 0.5
        webView.layer?.borderColor = NSColor(white: 0.5, alpha: 0.22).cgColor
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

    // Jeton présent mais inutilisable (expiré ou rejeté) : on attend que Claude Code
    // le renouvelle et le repose dans le Trousseau. Tant que ce drapeau est levé, le
    // poll relit le Trousseau une fois par minute et ne relance l'API que lorsqu'un
    // jeton FRAIS et DIFFÉRENT du dernier rejeté apparaît (voir pollKeychainIfWaiting).
    var awaitingClaudeCode = false
    // Dernier accessToken qu'on a vu rejeté (401/403) : on ne retente pas dessus, on
    // attend que Claude Code en pose un autre — sinon on bouclerait sur le même 401.
    var lastRejectedToken: String?

    // Login indépendant de Conso (voir startLogin). `loggingIn` évite deux flux en
    // parallèle ; `loopback` garde le serveur vivant le temps du retour navigateur ;
    // `loginTimeout` abandonne si le navigateur ne revient jamais.
    var loggingIn = false
    var loopback: OAuthLoopback?
    var loginTimeout: DispatchWorkItem?

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
            guard let self else { return }
            switch action {
            case "refresh": self.refresh(force: true)
            case "plane": self.testPlane()
            case let a where a.hasPrefix("h:"):
                if let h = Double(a.dropFirst(2)) { self.applyMeasuredHeight(CGFloat(h)) }
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
        // Poll léger (1/min) UNIQUEMENT en attente de Claude Code : relit le Trousseau
        // localement (aucun appel réseau) et repart dès qu'un jeton frais y apparaît.
        let poll = Timer(timeInterval: 60, repeats: true) { _ in self.pollKeychainIfWaiting() }
        RunLoop.main.add(poll, forMode: .common)
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
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let verItem = NSMenuItem(title: "Conso Claude \(ver)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        menu.addItem(verItem)
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(forceRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let planeItem = NSMenuItem(title: "Test the plane ✈️", action: #selector(testPlane), keyEquivalent: "")
        planeItem.target = self
        menu.addItem(planeItem)
        menu.addItem(.separator())
        let signInItem = NSMenuItem(title: "How to sign in…", action: #selector(showSignInHelp), keyEquivalent: "")
        signInItem.target = self
        menu.addItem(signInItem)
        menu.addItem(.separator())

        // Jeton indépendant de Conso. On indique la source courante, on propose le login,
        // et — si Conso a son propre jeton — un retrait qui REVIENT au jeton de Claude Code
        // (rollback complet, aucune trace : c'est ce qui rend l'essai sans risque).
        let hasOwn = readCredsFrom(CONSO_KEYCHAIN, source: .own) != nil
        let tokenInfo = NSMenuItem(
            title: hasOwn ? "Token — Conso's own ✓" : "Token — borrowed from Claude Code",
            action: nil, keyEquivalent: "")
        tokenInfo.isEnabled = false
        menu.addItem(tokenInfo)
        let ownLoginItem = NSMenuItem(
            title: hasOwn ? "Re-sign in to Conso…" : "Sign in to Conso (independent token)…",
            action: #selector(startLogin), keyEquivalent: "")
        ownLoginItem.target = self
        menu.addItem(ownLoginItem)
        if hasOwn {
            let signOutItem = NSMenuItem(title: "Remove Conso's token (back to Claude Code)…",
                                         action: #selector(signOutConso), keyEquivalent: "")
            signOutItem.target = self
            menu.addItem(signOutItem)
        }
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
        // Si on ATTEND un jeton frais (session expirée), relire le Trousseau tout de suite :
        // Monsieur vient probablement de se servir de Claude Code, le jeton neuf est peut-être
        // déjà là. On repart à l'instant de l'ouverture au lieu d'attendre le poll d'1 min —
        // c'est exactement ce qui manquait quand « ça ne prend pas » à chaque ↻.
        if awaitingClaudeCode || state.needsLogin { pollKeychainIfWaiting() }
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

    // Hauteur RÉELLE du contenu, mesurée par le popover après mise en page (voir le
    // `post('h:…')` dans render() et applyMeasuredHeight). Fait AUTORITÉ dès qu'elle
    // arrive ; le calcul ci-dessous n'est plus qu'un secours pour la toute première
    // ouverture, avant la première mesure.
    var measuredContentHeight: CGFloat?

    func popoverSize() -> NSSize {
        if let m = measuredContentHeight { return NSSize(width: 248, height: m) }
        let n = max(state.limits.count, 1)
        var h: CGFloat = 12 + CGFloat(n) * 38 + 19 + 8
        if (state.error != nil || state.waiting) && !state.needsLogin { h += 22 }
        if state.needsLogin { h += 52 }   // bloc d'info « Sign in with Claude Code »
        let spk = sparkPayload()
        if spk.count >= 3, (spk.compactMap { $0["a"] as? Double }.max() ?? 0) >= 1800 { h += 38 }
        return NSSize(width: 248, height: h)
    }

    // Le popover a mesuré sa hauteur de contenu : on redimensionne la fenêtre pile
    // dessus. Borné (garde-fou anti-valeur folle), et on ne bouge la fenêtre que si
    // la hauteur a réellement changé, pour ne pas la faire vibrer à chaque render.
    func applyMeasuredHeight(_ h: CGFloat) {
        let clamped = max(80, min(h, 900))
        guard abs((measuredContentHeight ?? -1) - clamped) >= 1 else { return }
        measuredContentHeight = clamped
        if panel.isVisible { repositionPanel() }
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
            "needsLogin": state.needsLogin,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]
        // Attente calme (jeton expiré, on attend Claude Code) : même emplacement que le
        // message d'erreur, mais drapeau `calm` → rendu gris discret, pas orange d'alerte.
        // `waiting` et `error` sont mutuellement exclusifs (voir UsageState.waiting).
        if state.waiting {
            payload["error"] = SESSION_WAIT_MSG
            payload["calm"] = true
        } else if let e = state.error {
            payload["error"] = e
        }
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

    // Le test envoie UN SEUL avion par clic, en changeant de famille à chaque fois
    // (session → tous modèles → Fable → …). Reclique pour voir la famille suivante —
    // jamais de rafale ni de file qui s'accumule (c'est ce qui donnait l'impression que
    // « les avions tournent en boucle »).
    var testPlaneIdx = 0
    @objc func testPlane() {
        let demos: [(Int, String)] = [
            (52, "5-hour session"),
            (25, "Weekly — all models"),
            (10, "Weekly — Fable"),
        ]
        let (remaining, context) = demos[testPlaneIdx % demos.count]
        testPlaneIdx += 1
        PlaneBanner.fly(remaining: remaining, context: context,
                        phrase: encouragement(remaining: remaining, context: context))
    }

    @objc func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: Connexion — déléguée à Claude Code

    // L'app ne fait PLUS le login OAuth elle-même (voir le commentaire en tête sur
    // KEYCHAIN_SERVICE). Le menu « How to sign in… » explique simplement la marche à
    // suivre : le login et le renouvellement du jeton appartiennent à Claude Code.
    @objc func showSignInHelp() {
        let alert = NSAlert()
        alert.messageText = "Sign in with Claude Code"
        alert.informativeText = "Conso Claude reads the token that Claude Code stores in your "
            + "Keychain — it doesn't sign in on its own.\n\n"
            + "• If you use Claude Code, run  claude auth login  in your terminal (or open the "
            + "Claude Code app and sign in).\n"
            + "• Then right-click the menu-bar icon → Refresh.\n\n"
            + "The usage will appear on its own, and stay in sync as Claude Code refreshes the "
            + "session."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // Jeton présent mais inutilisable (expiré ou rejeté par l'API) : Claude Code le
    // renouvellera tout seul. On GARDE les derniers chiffres connus en « stale », on
    // affiche un message qui pointe vers Claude Code, et on pose un BACKOFF FRANC de
    // 60 s — au grand maximum une tentative réseau par minute, jamais de boucle. Le
    // poll (pollKeychainIfWaiting) fera repartir l'app dès que Claude Code aura reposé
    // un jeton frais dans le Trousseau. `rejected` = le jeton qui vient d'être refusé
    // (401/403), qu'on mémorise pour ne pas le retenter ; nil quand c'est une simple
    // expiration (l'expiresAt suffit alors à savoir qu'il faut attendre).
    func waitForClaudeCode(reason: String, rejected: String?) {
        DispatchQueue.main.async {
            if !self.awaitingClaudeCode { oauthLog("jeton inutilisable → attente du renouvellement par Claude Code (\(reason))") }
            self.awaitingClaudeCode = true
            if let r = rejected { self.lastRejectedToken = r }
            self.backoffUntil = Date().addingTimeInterval(60)
            self.state.needsLogin = false
            // État calme, pas une erreur : gris discret dans le popover, jamais l'orange
            // d'alerte. `error` est réservé aux VRAIES pannes (réseau, 429, HTTP) et
            // s'efface ici pour ne pas cohabiter avec l'attente.
            self.state.waiting = true
            self.state.error = nil
            self.state.stale = !self.state.limits.isEmpty
            self.updateStatusTitle()
            if self.panel.isVisible { self.pushToWeb(animate: false); self.repositionPanel() }
        }
    }

    // Poll 1/min tant que l'app n'a pas de jeton utilisable : soit un jeton expiré/rejeté
    // (awaitingClaudeCode), soit aucun jeton du tout (needsLogin — ex. Claude Code a vidé
    // l'entrée, puis on refait `claude auth login`). On relit le Trousseau (aucun réseau)
    // et on ne relance un vrai fetch que si un jeton FRAIS (non expiré) et DIFFÉRENT du
    // dernier rejeté apparaît — sinon on retomberait aussitôt sur le même 401. Hors de
    // ces états, rien ne tourne ici : le cycle normal de 10 min suffit.
    func pollKeychainIfWaiting() {
        guard awaitingClaudeCode || state.needsLogin else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let creds = self.readCreds() else { return }
            let nowMs = Date().timeIntervalSince1970 * 1000
            let expired = creds.expiresAtMs.map { nowMs >= $0 - 60_000 } ?? false
            DispatchQueue.main.async {
                guard self.awaitingClaudeCode || self.state.needsLogin else { return }
                guard !expired, creds.accessToken != self.lastRejectedToken else { return }
                oauthLog("jeton utilisable retrouvé dans le Trousseau → reprise")
                self.awaitingClaudeCode = false
                self.refresh(force: true)
            }
        }
    }

    // Aucun jeton du tout dans le Trousseau (jamais connecté, ou entrée vidée) : on le
    // dit franchement — bloc « Sign in with Claude Code » — ET on EFFACE les chiffres
    // périmés (mémoire + cache disque). Différent de l'attente ci-dessus : ici il n'y a
    // rien à attendre tant que personne n'a fait `claude auth login`.
    func signedOut(reason: String) {
        oauthLog("aucun jeton dans le Trousseau — \(reason)")
        DispatchQueue.main.async {
            self.awaitingClaudeCode = false
            self.lastRejectedToken = nil
            self.state.waiting = false
            self.state.needsLogin = true
            self.state.limits = []
            self.state.stale = false
            self.state.fetchedAt = nil
            self.state.error = reason
            UserDefaults.standard.removeObject(forKey: "limits")
            UserDefaults.standard.removeObject(forKey: "fetchedAt")
            self.updateStatusTitle()
            if self.panel.isVisible { self.pushToWeb(animate: false); self.repositionPanel() }
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

    // Jeton courant, par PRIORITÉ : d'abord l'entrée PROPRE de Conso (qu'on peut
    // rafraîchir), sinon celle de Claude Code en lecture seule (repli historique).
    func readCreds() -> KeychainCreds? {
        readCredsFrom(CONSO_KEYCHAIN, source: .own)
            ?? readCredsFrom(KEYCHAIN_SERVICE, source: .claudeCode)
    }

    // Lit une entrée donnée. On garde le blob complet + le refreshToken (utiles seulement
    // pour réécrire NOTRE entrée) ; pour l'entrée empruntée, ils existent mais ne seront
    // jamais réécrits (writeConsoCreds ne vise que CONSO_KEYCHAIN).
    func readCredsFrom(_ service: String, source: CredsSource) -> KeychainCreds? {
        guard let blob = runSecurity(["find-generic-password", "-s", service, "-w"]),
              let data = blob.data(using: .utf8),
              let full = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = full["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              // accessToken vidé ("") = session morte → « pas de jeton » pour cette entrée.
              !token.isEmpty else { return nil }
        var account = NSUserName()
        if let attrs = runSecurity(["find-generic-password", "-s", service]),
           let m = attrs.range(of: #"(?<="acct"<blob>=")[^"]*"#, options: .regularExpression) {
            account = String(attrs[m])
        }
        return KeychainCreds(
            source: source, account: account, full: full, oauth: oauth,
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAtMs: (oauth["expiresAt"] as? NSNumber)?.doubleValue
        )
    }

    // ⚠️ SEUL chemin d'écriture du Trousseau, et il vise EXCLUSIVEMENT l'entrée de Conso.
    // Le service (CONSO_KEYCHAIN) et le compte (NSUserName) sont EN DUR : aucun appelant
    // ne peut lui faire écrire l'entrée de Claude Code. C'est l'invariant qui garantit
    // qu'on ne peut pas reproduire le 14/09.
    func writeConsoCreds(_ full: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: full),
              let str = String(data: data, encoding: .utf8) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["add-generic-password", "-U", "-a", NSUserName(), "-s", CONSO_KEYCHAIN, "-w", str]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
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
                self.signedOut(reason: "Not signed in.")
                return
            }
            // Principe : le jeton PROPRE de Conso ne peut qu'AJOUTER de la vivacité. Au
            // moindre pépin (refresh échoué, jeton refusé), on RETOMBE sur le repli
            // lecture-seule (jeton frais de Claude Code, sinon attente) — jamais on
            // n'efface les chiffres. Conso avec son jeton n'est donc jamais PIRE que sans.
            var token = creds.accessToken
            var didRefresh = false   // a-t-on DÉJÀ consommé notre refresh token ce cycle ?
            let nowMs = Date().timeIntervalSince1970 * 1000
            let expired = creds.expiresAtMs.map { nowMs >= $0 - 60_000 } ?? false
            if expired {
                if creds.source == .own, let fresh = self.refreshConsoToken(creds) {
                    token = fresh; didRefresh = true   // renouvelé nous-mêmes (aucun partage, aucun risque)
                } else if let borrowed = self.freshBorrowedToken() {
                    token = borrowed   // repli : jeton frais de Claude Code
                } else {
                    self.waitForClaudeCode(reason: SESSION_WAIT_MSG, rejected: nil)
                    return
                }
            }
            let (resp, data, err) = self.performUsageRequest(token: token)
            // 401/403 : jeton révoqué ou tourné ailleurs.
            if resp?.statusCode == 401 || resp?.statusCode == 403 {
                // On ne RE-refresh que si on ne l'a PAS déjà fait ce cycle : rejouer un
                // refresh token déjà consommé (RT0) déclencherait la détection de réutilisation
                // côté serveur et tuerait NOTRE famille de jetons. Sinon (ou après), on retombe
                // sur le repli : jeton frais de Claude Code, ou attente.
                if creds.source == .own, !didRefresh, let fresh = self.refreshConsoToken(creds), fresh != token {
                    let (r2, d2, e2) = self.performUsageRequest(token: fresh)
                    if r2?.statusCode == 401 || r2?.statusCode == 403 {
                        if let b = self.freshBorrowedToken() {
                            let (r3, d3, e3) = self.performUsageRequest(token: b)
                            self.handleUsageResponse(resp: r3, data: d3, err: e3)
                        } else {
                            self.waitForClaudeCode(reason: SESSION_WAIT_MSG, rejected: nil)
                        }
                    } else {
                        self.handleUsageResponse(resp: r2, data: d2, err: e2)
                    }
                } else if let b = self.freshBorrowedToken(), b != token {
                    let (r3, d3, e3) = self.performUsageRequest(token: b)
                    self.handleUsageResponse(resp: r3, data: d3, err: e3)
                } else {
                    self.waitForClaudeCode(reason: SESSION_WAIT_MSG, rejected: token)
                }
                return
            }
            self.handleUsageResponse(resp: resp, data: data, err: err)
        }
    }

    // Jeton frais EMPRUNTÉ à Claude Code (repli lecture seule) : nil s'il n'existe pas ou
    // est expiré. Sert de filet quand le jeton propre de Conso fait défaut — on ne renouvelle
    // jamais celui de Claude Code, on l'utilise seulement s'il est déjà bon.
    func freshBorrowedToken() -> String? {
        guard let b = readCredsFrom(KEYCHAIN_SERVICE, source: .claudeCode) else { return nil }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let expired = b.expiresAtMs.map { nowMs >= $0 - 60_000 } ?? false
        return expired ? nil : b.accessToken
    }

    // Renouvelle le jeton PROPRE de Conso via SON refreshToken, puis réécrit SON entrée
    // (rotation incluse : on persiste le nouveau refreshToken). N'agit QUE sur une entrée
    // `own` — jamais sur celle de Claude Code. Renvoie le nouvel accessToken, ou nil.
    func refreshConsoToken(_ creds: KeychainCreds) -> String? {
        guard creds.source == .own, let rt = creds.refreshToken else { return nil }
        let body = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": OAUTH_CLIENT_ID,
        ])
        guard let j = postToken(body: body, url: OAUTH_TOKEN_URL)
                    ?? postToken(body: body, url: OAUTH_TOKEN_URL_ALT),
              let access = j["access_token"] as? String else { return nil }
        var oauth = creds.oauth
        oauth["accessToken"] = access
        if let newRt = j["refresh_token"] as? String { oauth["refreshToken"] = newRt }
        if let ei = (j["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = (Date().timeIntervalSince1970 + ei) * 1000
        }
        var full = creds.full
        full["claudeAiOauth"] = oauth
        guard writeConsoCreds(full) else { return nil }
        oauthLog("refresh du jeton propre de Conso : OK (entrée Conso réécrite)")
        return access
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
        urlSession.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            oauthLog("POST token \(URL(string: url)?.host ?? url) → HTTP \(status)\(err != nil ? " (réseau: \(err!.localizedDescription))" : "")")
            guard status == 200, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            json = obj
        }.resume()
        sem.wait()
        return json
    }

    // MARK: Login indépendant de Conso (son propre jeton)

    // Ouvre le navigateur pour que Conso obtienne SON jeton (entrée séparée). Ne remplace
    // JAMAIS le jeton de Claude Code. Voie = callback HÉBERGÉ + collage du code (exactement
    // comme le CLI `claude` ; le client OAuth n'accepte pas de redirect loopback).
    @objc func startLogin() {
        // Réinitialise tout login précédent resté en l'air : sans ça, un essai qui a échoué
        // sans retour navigateur laisse loggingIn=true et un reclic ne ferait plus rien.
        loginTimeout?.cancel(); loginTimeout = nil
        loopback?.stop(); loopback = nil
        loggingIn = false

        let info = NSAlert()
        info.messageText = "Give Conso its own token?"
        info.informativeText = "Conso will sign in to Claude in your browser and keep its OWN token, "
            + "separate from Claude Code's. The usage then stays live even when you're not using "
            + "Claude Code on this Mac — no more \u{201C}Paused\u{201D}.\n\n"
            + "It does NOT touch Claude Code's token — Conso only ever writes its own Keychain entry.\n\n"
            + "Your browser will open Claude's page. Approve, then copy the code it shows and paste "
            + "it back here."
        info.addButton(withTitle: "Sign in")
        info.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard info.runModal() == .alertFirstButtonReturn else { return }

        pasteLogin(verifier: randomToken(), state: randomToken(16))
    }

    // Flux hébergé : le redirect `platform.claude.com/oauth/code/callback` affiche
    // « code#state » que l'utilisateur colle. C'est la voie du CLI `claude`.
    func pasteLogin(verifier: String, state stateTok: String) {
        loggingIn = true
        state.needsLogin = false
        oauthLog("login Conso: flux hébergé (collage de code) — redirect=\(OAUTH_REDIRECT_MANUAL)")
        openAuthorize(redirect: OAUTH_REDIRECT_MANUAL, state: stateTok, challenge: pkceChallenge(verifier))
        let alert = NSAlert()
        alert.messageText = "Sign in to Claude"
        alert.informativeText = "Your browser opened the Claude authorization page. Approve access, "
            + "copy the code shown, and paste it here."
        alert.addButton(withTitle: "Sign in")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Paste the code here"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        let pasted = alert.runModal() == .alertFirstButtonReturn
            ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !pasted.isEmpty else {
            oauthLog("manuel: annulé")
            loggingIn = false; refresh(force: true); return
        }
        // omittingEmptySubsequences:false → "#" seul donne ["",""] (pas [] qui ferait
        // planter parts[0]). On garde le code éventuellement vide, filtré juste après.
        let parts = pasted.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let code = parts.first ?? ""
        guard !code.isEmpty else {
            oauthLog("manuel: code vide"); loggingIn = false; refresh(force: true); return
        }
        let retState = parts.count > 1 ? parts[1] : stateTok
        state.error = "Signing in…"; state.needsLogin = false
        if panel.isVisible { pushToWeb(animate: false); repositionPanel() }
        exchangeAsync(code: code, state: retState, verifier: verifier, redirect: OAUTH_REDIRECT_MANUAL)
    }

    // Retour du serveur loopback : valide le state, échange le code, écrit l'entrée Conso.
    func completeLogin(code: String?, returnedState: String?,
                       verifier: String, expectedState: String, redirect: String) {
        loginTimeout?.cancel(); loginTimeout = nil
        loopback?.stop(); loopback = nil
        oauthLog("retour navigateur — code=\((code?.isEmpty == false) ? "présent" : "absent"), state=\(returnedState == expectedState ? "OK" : "≠")")
        guard let code = code, !code.isEmpty else { loginFailed("Sign-in was cancelled."); return }
        // Le state DOIT être présent ET égal (anti-CSRF). On n'accepte pas un state absent :
        // notre autorisation en envoie toujours un, le serveur le renvoie toujours.
        guard returnedState == expectedState else { loginFailed("Sign-in check failed — try again."); return }
        state.error = "Signing in…"
        if panel.isVisible { pushToWeb(animate: false); repositionPanel() }
        exchangeAsync(code: code, state: returnedState ?? expectedState, verifier: verifier, redirect: redirect)
    }

    func loginTimedOut() {
        loopback?.stop(); loopback = nil
        loginTimeout = nil
        oauthLog("login: time-out (navigateur jamais revenu)")
        loginFailed("Sign-in timed out — no response from the browser.")
    }

    func loginFailed(_ message: String) {
        loggingIn = false
        oauthLog("login échec: \(message)")
        state.error = message
        updateStatusTitle()
        if panel.isVisible { pushToWeb(animate: false); repositionPanel() }
        // On ne force PAS needsLogin : le repli lecture-seule (Claude Code) peut très bien
        // fonctionner. Un refresh re-dérive l'état réel.
        refresh(force: true)
    }

    // Retire le jeton PROPRE de Conso (supprime SON entrée du Trousseau) et revient au
    // repli lecture-seule sur Claude Code. Réversible et sans trace — le filet de sécurité
    // de l'essai : si le jeton indépendant pose souci, un clic annule tout.
    @objc func signOutConso() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["delete-generic-password", "-s", CONSO_KEYCHAIN]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        oauthLog("entrée Conso supprimée → repli sur le jeton de Claude Code")
        state.needsLogin = false
        refresh(force: true)
    }

    // Construit l'URL d'autorisation OAuth et l'ouvre. On encode chaque valeur comme
    // `URLSearchParams` du CLI (`:`→%3A, `/`→%2F) : un serveur strict peut refuser sinon.
    func openAuthorize(redirect: String, state: String, challenge: String) {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let query = [
            "code=true",
            "client_id=\(enc(OAUTH_CLIENT_ID))",
            "response_type=code",
            "redirect_uri=\(enc(redirect))",
            "scope=\(enc(OAUTH_SCOPES))",
            "code_challenge=\(enc(challenge))",
            "code_challenge_method=S256",
            "state=\(enc(state))",
        ].joined(separator: "&")
        if let url = URL(string: OAUTH_AUTHORIZE_URL + "?" + query) {
            oauthLog("authorize ouvert — redirect=\(redirect)")
            NSWorkspace.shared.open(url)
        }
    }

    // Échange code→tokens en fond, écrit l'entrée Conso, puis rafraîchit l'affichage.
    func exchangeAsync(code: String, state: String, verifier: String, redirect: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = self.exchangeCode(code: code, state: state, verifier: verifier, redirect: redirect)
            oauthLog(ok ? "échange code→token: OK (entrée Conso écrite)" : "échange code→token: ÉCHEC")
            DispatchQueue.main.async {
                self.loggingIn = false
                if ok {
                    self.state.needsLogin = false
                    self.state.error = nil
                    self.refresh(force: true)
                } else {
                    self.loginFailed("Sign-in failed — please try again.")
                }
            }
        }
    }

    // POST authorization_code → tokens (deux endpoints connus), puis écrit l'entrée Conso.
    func exchangeCode(code: String, state: String, verifier: String, redirect: String) -> Bool {
        let body = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": OAUTH_CLIENT_ID,
            "redirect_uri": redirect,
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
        return writeConsoCreds(["claudeAiOauth": oauth])
    }

    func handleUsageResponse(resp: HTTPURLResponse?, data: Data?, err: Error?) {
        if let err = err {
            oauthLog("usage: erreur réseau — \(err.localizedDescription)")
            self.apply(limits: nil, error: "Network: \(err.localizedDescription)")
            return
        }
        guard let http = resp, let data = data else {
            oauthLog("usage: aucune réponse de l'API")
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
                self.state.waiting = false
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
        if http.statusCode == 401 || http.statusCode == 403 {
            // Filet : `refresh()` intercepte normalement le 401/403 (avec le jeton en
            // main). Si on arrive quand même ici, même conduite — on attend Claude Code
            // au lieu d'effacer les chiffres : c'est lui qui renouvelle le jeton.
            self.waitForClaudeCode(reason: SESSION_WAIT_MSG, rejected: nil)
            return
        }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLimits = json["limits"] as? [[String: Any]] else {
            oauthLog("usage: HTTP \(http.statusCode) (réponse inattendue)")
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
                self.state.waiting = false
                // Un 200 clôt toute attente : jeton valide, on repart normalement.
                self.awaitingClaudeCode = false
                self.lastRejectedToken = nil
                self.backoffUntil = .distantPast
                self.checkThresholds(limits)
                self.saveCachedState()
                if let s = limits.first(where: { $0.isSession }) {
                    self.recordHistory(sessionPercent: s.percent)
                }
            } else if error != nil {
                // Vraie erreur (réseau, HTTP inattendu) : elle prime sur l'attente calme
                // pour ne pas afficher les deux à la fois.
                self.state.waiting = false
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
