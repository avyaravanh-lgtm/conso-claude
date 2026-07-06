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

When you cross **50%, 75% and 90%** of a limit, a small coral prop plane flies across your screen towing an ivory banner: how much you have left, plus a rotating encouragement — *«&nbsp;Make these tokens count.&nbsp;»*, *«&nbsp;Maybe it's time to rest.&nbsp;»* (the pool is time-aware: late-night and Friday-evening phrases included). Once per session, never twice for the same threshold.

<p align="center">
  <img src="assets/banner-preview.png" width="560" alt="The three banner tiers: 50% coral, 25% orange, 10% red">
</p>

> Weekend project, shared as-is. **Windows** port: [`windows/`](windows/README.md).

## Install

**Requirements:** macOS 15+, and [Claude Code](https://claude.com/claude-code) installed and **logged in with a Pro/Max subscription** (the app reads its OAuth token from the Keychain — that's where the usage data comes from). API-key setups (`ANTHROPIC_API_KEY`, Bedrock/Vertex) have no usage limits to show.

1. Download `Conso Claude.zip` from [Releases](../../releases), unzip, drag to `/Applications`.
2. First launch: the app is not notarized, so macOS blocks it — click **"Done"** (not "Move to Trash"), then open **System Settings → Privacy & Security**, scroll down to *"Conso Claude was blocked…"* and click **"Open Anyway"**. One time only.
   *Terminal alternative:* `xattr -d com.apple.quarantine "/Applications/Conso Claude.app"`
3. If macOS asks whether `security` can access "Claude Code-credentials" → **Always Allow** (once).
4. Right-click the ✳ icon → "Start with macOS" to make it permanent.

## Build from source

No dependencies, no Xcode project — just `swiftc` (Xcode Command Line Tools):

```bash
git clone https://github.com/avyaravanh-lgtm/conso-claude.git
cd conso-claude
./build.sh --install   # universal binary (Apple Silicon + Intel) → /Applications
```

## How it works

- Reads Claude Code's OAuth token from the macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`), at request time only.
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

Small enough to audit in one sitting: `main.swift` + `Banner.swift`, ~900 lines total.

## Customize the phrases

Drop a `phrases.json` in `~/Library/Application Support/Conso Claude/` to extend the pool (keys: `"50"`, `"25"`, `"10"`, `"night"`, `"friday"`, `"weekly"`, `"reset"` — arrays of strings). See the bundled [phrases.json](phrases.json) for the voice: calm, a bit literary, never guilt-tripping.

## Caveats

- The usage endpoint is not officially documented; if Anthropic changes it, the app shows a friendly error until updated.
- Not notarized (no Apple Developer account) — hence the "Open Anyway" dance in System Settings.
- If the menu bar shows `✳ !`: open Claude Code once to refresh the token, then right-click → Refresh.

---

*Built in an afternoon with [Claude Code](https://claude.com/claude-code). Docs en français : [README.fr.md](README.fr.md).*
