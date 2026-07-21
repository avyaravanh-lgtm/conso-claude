# Changelog

All notable changes to Conso Claude are documented here.

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
