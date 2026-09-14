<p align="center">
  <img src="assets/icon.png" width="128" alt="Conso Claude icon">
</p>

<h1 align="center">Conso Claude</h1>

<p align="center">
  A tiny macOS menu bar app that shows your Claude usage at a glance —<br>
  and sends a little plane across your screen when you're running low.
</p>

<p align="center">
  <img src="assets/plane-flight.gif" width="820" alt="The plane flying across the screen towing a banner: 25% remaining — Distill, then ask.">
</p>

---

**`✳ 62 %`** sits in your menu bar — how much of your 5-hour session is **left**, always visible (coral when little remains). Click it for a compact popover: session and weekly limits as animated bars, a sparkline of your session over time, and a burn-rate prediction («&nbsp;empty ~14:30&nbsp;») when you're consuming fast enough to run dry before the reset.

<p align="center">
  <img src="assets/popover.png" width="380" alt="The popover: 5-hour session, weekly all-models and weekly Fable as animated bars, plus a per-hour usage sparkline.">
</p>

When you cross **50%, 75% and 90%** of a limit, a small coral prop plane flies across your screen towing an ivory banner: how much you have left, plus a rotating encouragement — *«&nbsp;Make these tokens count.&nbsp;»*, *«&nbsp;Maybe it's time to rest.&nbsp;»* (the pool is time-aware: late-night and Friday-evening phrases included). Once per session, never twice for the same threshold.

<p align="center">
  <img src="assets/banner-preview.png" width="560" alt="The three banner tiers: 50% coral, 25% orange, 10% red">
</p>

> Weekend project, shared as-is — distributed as source (build it yourself, see below). **Windows** port: [`windows/`](windows/README.md).

## Install (build from source)

This app is a **companion to [Claude Code](https://claude.com/claude-code)**: it reads the OAuth token Claude Code stores in your Keychain and shows your usage. So the requirements are:

- macOS 15+, on Apple Silicon or Intel
- a **Pro/Max Claude subscription**
- **Claude Code installed and signed in** — run `claude` once and sign in with `/login`. That puts a working token in your Keychain, which this app reads. *(API-key setups — `ANTHROPIC_API_KEY`, Bedrock/Vertex — have no usage limits to show.)*

Build it yourself — no dependencies, no Xcode project, just `swiftc`. A **locally-built app is never quarantined**, so there's no Gatekeeper prompt and no notarization needed:

```bash
xcode-select --install    # once, if you don't have the Command Line Tools
git clone https://github.com/avyaravanh-lgtm/conso-claude.git
cd conso-claude
./build.sh --install      # universal binary (Apple Silicon + Intel) → /Applications, then launches
```

Right-click the ✳ icon → "Start with macOS" to make it permanent.

> **Signing in is Claude Code's job.** This app reads the token Claude Code puts in your Keychain — it never signs in, never refreshes the token, and never writes that Keychain entry. (An earlier version did its own refresh; because Claude Code's refresh token is single-use and rotates on every exchange, two clients sharing it eventually killed the session for both. Read-only fixes that at the root.) No Claude Code yet? Run `claude auth login`, then right-click the ✳ icon → **Refresh**.

## How it works

- Reads Claude Code's OAuth token from the macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`), at request time only — **read-only**: it never renews the token or rewrites that entry (that's Claude Code's job).
- When the token has expired, it doesn't try to refresh it (Claude Code does that): it shows the last known numbers as **stale** with "open Claude Code to refresh", re-reads the Keychain about once a minute, and resumes on its own once a fresh token appears.
- Queries `https://api.anthropic.com/api/oauth/usage` — the same endpoint the official "Usage limits" page uses. Exact numbers, not an estimate.
- Polite with the API: polls every 10 minutes, refreshes on popover open only if data is older than 5 minutes, silent backoff on 429 (cached data stays displayed with a ⚠ next to the timestamp).
- Usage history is kept locally (UserDefaults, 3 rolling days) for the sparkline and the dry-by prediction.
- The popover is a transparent WKWebView over the native glass; the plane is vector-drawn (`Banner.swift`) and rendered to a single texture per flight.

## Security & privacy

- The token is **never written to disk or logged**: read from the Keychain when needed, kept in memory, sent only to `api.anthropic.com` (HTTPS, hardcoded URL, ephemeral URLSession → zero disk cache).
- Keychain is accessed via absolute path (`/usr/bin/security`) — no PATH hijacking.
- No telemetry, no local server, no third-party dependencies.
- Only data persisted locally: timestamped usage percentages and the last shown phrases. Nothing sensitive.
- External data is HTML-escaped before display (anti-injection).
- The banner window ignores the mouse and captures no input.

Small enough to audit in one sitting: `main.swift` + `Banner.swift`, ~1,400 lines total.

## Customize the phrases

Drop a `phrases.json` in `~/Library/Application Support/Conso Claude/` to extend the pool (keys: `"50"`, `"25"`, `"10"`, `"night"`, `"friday"`, `"weekly"`, `"reset"` — arrays of strings). See the bundled [phrases.json](phrases.json) for the voice: calm, a bit literary, never guilt-tripping.

## Caveats

- The usage endpoint is not officially documented; if Anthropic changes it, the app shows a friendly error until updated.
- Distributed as source, not as a notarized download — building it locally is what keeps it out of Gatekeeper's way (no Apple Developer account needed).
- If the menu bar shows `✳ !` or "Not signed in": make sure Claude Code is signed in on this Mac (`claude auth login`, or `claude` → `/login`), then right-click the icon → **Refresh**.

---

*Built in an afternoon with [Claude Code](https://claude.com/claude-code). Docs en français : [README.fr.md](README.fr.md).*
