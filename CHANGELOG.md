# Changelog

All notable changes to Conso Claude are documented here.

## 1.3.6 — 2026-07-21

### Coin haut-gauche du popover : fond opaque, fini le glint
- Le coin haut-gauche montrait une tache colorée (« moche ») : le Liquid Glass
  (NSGlassEffectView) — puis le matériau frosté (NSVisualEffectView) — laissaient
  **transparaître/refléter le fond derrière la fenêtre** et le concentraient en un
  glint de bord au coin (ex. un onglet vert derrière → coin verdâtre). Vérifié à
  l'écran sur fond vert pur.
- **Fix** : la carte du popover est désormais **opaque** (fond ivoire adaptatif
  clair/sombre peint par le HTML), coins arrondis en squircle continu + hairline
  discrète. Rendu net et identique sur **n'importe quel** fond, plus aucun glint.

## 1.3.5 — 2026-07-21

### Numéro de version visible + constat sur le login
- **Version affichée** dans l'app : en haut du menu clic droit (« Conso Claude
  1.3.5 ») et dans le pied du popover. Permet de vérifier d'un coup d'œil quelle
  build tourne.
- **Login OAuth — diagnostic** : l'échec « Invalid request format » après clic sur
  « Autoriser » n'est **pas** un bug de l'app. Vérifié en lançant l'outil officiel
  `claude setup-token` : il ouvre une URL byte-identique à celle de l'app et
  échoue **exactement pareil** au même moment. C'est un problème côté serveur
  d'autorisation (ou lié à un compte ayant déjà autorisé Claude Code). L'app lit
  toujours parfaitement le token existant ; le login intégré reste en place pour
  quand le flux d'Anthropic refonctionnera / sur une machine jamais autorisée.

## 1.3.4 — 2026-07-21

### LA vraie cause du bouton « Sign in » toujours affiché : un bug CSS
Depuis la 1.3, le bouton « Sign in to Claude » restait visible **en permanence**,
même avec un token valide et `needsLogin=false`. Toutes les corrections de logique
Swift précédentes étaient correctes mais **masquées** par ce bug :
- La règle `#login { display:block }` a une spécificité (id) supérieure à celle de
  l'attribut `[hidden]` du navigateur → `element.hidden = true` était **ignoré**,
  le bouton s'affichait toujours.
- Fix : `#login[hidden] { display:none }`.

Vérifié **à l'écran** (capture du popover) : `needsLogin=false` → bouton bien
masqué, popover propre (conso + graphe), coins arrondis corrects. La logique
`needsLogin` des versions 1.3.1→1.3.3 fonctionnait déjà ; il ne manquait que ça.

## 1.3.3 — 2026-07-21

### Plus de bouton « Sign in » fantôme quand un token existe
- **Bug corrigé** : un essai de login manuel raté (mauvais code collé, annulation)
  mettait `needsLogin=true` de façon collante — le gros bouton « Sign in » restait
  affiché **alors qu'un token Claude Code valide était présent et lu**. `needsLogin`
  est désormais re-dérivé à chaque refresh depuis l'état réel du token : bouton
  seulement s'il n'y a vraiment aucun token lisible.
- `loginFailed` ne force plus le bouton ; il relance un refresh qui rétablit l'état.
- **Garde-fou** : « Sign in » sur une machine qui a déjà un token (Claude Code
  connecté) demande maintenant confirmation — se reconnecter écraserait le token
  par un scope plus étroit. Sur une telle machine, l'app affiche la conso toute
  seule, aucune connexion n'est nécessaire.
- Effet de bord réglé : la hauteur du popover (et les « coins » de l'état sign-in)
  ne s'affichent plus par erreur sur une machine déjà connectée.

## 1.3.2 — 2026-07-21

### Login OAuth aligné à l'identique sur `claude setup-token`
Le 1.3.1 échouait encore (« Invalid request format »). J'ai capturé l'URL réelle
générée par `claude setup-token` et corrigé les trois derniers écarts :
- **Scope** : `user:inference` **seul** (j'envoyais 3 scopes → rejet).
- **Redirect** : `https://platform.claude.com/oauth/code/callback` (callback
  hébergé qui affiche le code), au lieu d'un serveur loopback local.
- **Encodage** : `redirect_uri` et `scope` sont maintenant percent-encodés
  (`%3A`, `%2F`) exactement comme le CLI ; URLComponents les laissait en clair.
- **Flux** = copier-coller (comme `setup-token`) : le navigateur affiche un code,
  on le colle dans l'app. Le serveur loopback (jamais accepté par le serveur) est
  supprimé, ainsi que la dépendance au framework Network.
- L'échange essaie les deux endpoints de token connus (api.anthropic.com puis
  platform.claude.com) par sécurité.

Vérif : l'URL d'autorisation produite est désormais **byte-identique** à celle de
`claude setup-token` (qui fonctionne), donc l'erreur « Invalid request format »
est éliminée. Le seul maillon non automatisable reste le clic « Autoriser » +
collage du code.

## 1.3.1 — 2026-07-21

### Correctif login OAuth (le 1.3 ne se connectait pas)
- **Mauvais endpoint d'autorisation.** Le 1.3 tapait `claude.ai/oauth/authorize`
  (→ HTTP 403 « Invalid request format »). Le login de Claude Code a migré sur
  **`claude.com/cai/oauth/authorize`** — corrigé. Valeurs relevées directement
  dans le binaire `claude-code` de prod (client_id, scopes, ordre des paramètres).
- **`code=true` manquant** dans le flux loopback : il est maintenant toujours
  envoyé, comme le fait le CLI.
- **Redirect en `localhost`** (et non `127.0.0.1`) — c'est la forme déclarée comme
  autorisée côté client OAuth ; le serveur local écoute désormais sur l'interface
  **loopback** (couvre IPv4 et IPv6, rien exposé au réseau).
- Vérifs : URL d'autorisation 307 (vs 403 avant), endpoint d'échange qui accepte
  le format (`invalid_grant` sur code bidon, pas `invalid_request`), PKCE conforme
  RFC 7636, capture loopback du `localhost` OK.

## 1.3 — 2026-07-21

### Login intégré — l'app est autonome
- Nouveau bouton **« Sign in to Claude »** dans le popover (et dans le menu clic
  droit). Plus besoin d'installer Claude Code ni de passer par le Terminal : l'app
  fait **le premier login OAuth elle-même** et écrit le token dans le Keychain.
- Flux **loopback local + PKCE** (comme le login de Claude Code) : le navigateur
  s'ouvre, on autorise, le retour est capté automatiquement — **zéro copier-coller**.
- **Repli copier-coller** accessible en maintenant **⌥** sur le menu (ou déclenché
  automatiquement si le serveur local ne peut pas démarrer) : la page affiche un
  code, on le colle dans l'app.
- Garde-fou **timeout 2 min** : plus de blocage en « attente d'autorisation » si
  l'onglet est fermé ou l'accès refusé.
- Messages remaniés : « Token not found → open Claude Code » devient
  « Not signed in » avec le bouton de connexion ; le 401 devient « Session expired
  — sign in again ».

## 1.2 — 2026-07-14

### Auto-refresh du token
- L'app **renouvelle le token OAuth elle-même** via le `refreshToken` du Keychain,
  sans dépendre de l'ouverture de Claude Code. Au réveil du Mac, la conso repart
  toute seule au lieu de rester bloquée sur « Token expired ».
- Refresh **proactif** quand le token est expiré (ou l'est dans la minute), et
  **réactif** en secours sur un 401, suivi d'un retry de l'appel usage.
- Le nouveau token (rotation du `refreshToken` incluse) est **réécrit dans le
  Keychain**, donc Claude Code reste en phase.
- Si le refresh échoue lui aussi, message clair : « reconnect Claude Code (/login) ».

## 1.1 — 2026-07-13

### Usage chart
- **Per-hour usage bars** instead of the old cumulative session curve. Each bar
  shows how much you actually burned during that hour (the derivative), so a
  calm hour and a heavy one read at a glance. Session resets no longer look like
  a misleading "hill".
- **24-hour window**, adaptive: it grows with the history available (no empty
  bars early on) and tops out at a full day.
- **Hour labels** under the bars (local time); the current hour sits on the right.
- **Scale floor at 20 %/h** — the rate that would drain a whole session in 5 h.
  Below it, the scale stays put so a quiet day looks quiet; above it, the chart
  goes back to adaptive so heavy days are never squashed. A `PEAK N%/H` label
  gives the exact figure.

### Accessibility & readability
- Boosted the smallest chart text (caption + hour labels) for contrast.
- Gauge labels nudged over the WCAG AA threshold (4.5:1).
- Honors macOS **"Increase contrast"** (`prefers-contrast`): every tier gets
  denser when the setting is on, quiet look by default.

### Look & feel
- **Liquid Glass** (macOS 26+): the panel now uses a native `NSGlassEffectView`.
  On older macOS it falls back cleanly to the previous rendering.
- The popover became a **borderless floating panel** (like Control Center):
  no anchor triangle, clean rounded corners, and it lets the desktop show
  through subtly behind the glass.
- Hairline separators between gauges / chart / buttons, softer button hovers.
- Removed the clock in the footer (a `⚠︎` still flags cached data).

## 1.0 — 2026-07-06

- First release: menu-bar monitor for Claude usage limits on macOS (session +
  weekly), with the paper-plane banner and local history.
