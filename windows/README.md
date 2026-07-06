# Conso Claude — Windows

Native Windows port of [Conso Claude](../README.md): a menu-bar-style tray monitor
for your Claude usage (Pro/Max plans). Separate codebase from the macOS app — the
Swift app is untouched (**Voie A**).

The tray icon paints the **percentage left** onto the icon itself — a filled digit on
an ivory tile (Anthropic palette ivory/ink/coral). A click opens the same compact
popover as macOS (WebView2), and crossing a usage threshold sends a little plane with
an encouragement banner gliding across your screen ✈️.

## Requirements

- Windows 10 or 11 (x64).
- [Claude Code](https://code.claude.com) installed and signed in with a **Pro or Max**
  subscription (API-key setups have no limits to display).
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) — preinstalled
  on Windows 11 and current Windows 10; the popover is skipped gracefully if it is missing.
- [.NET 8 SDK](https://dotnet.microsoft.com/download) to build.

## How it reads your usage

Same doctrine as the mac app: the exact figures beat any estimate. On Windows, Claude
Code stores its OAuth token as a **plain file** at
`%USERPROFILE%\.claude\.credentials.json` (no keychain; override the folder with
`CLAUDE_CONFIG_DIR`). The app reads `claudeAiOauth.accessToken` and calls
`api.anthropic.com/api/oauth/usage` — the same endpoint as the "Usage limits" page.
The session is ephemeral, the URL is hard-coded, there is zero telemetry, and no API
response is ever written to disk.

Polling is polite: every 10 minutes, an immediate re-fetch only if data is older than
5 minutes, and a silent backoff on HTTP 429 (the cache stays on screen with a small ⚠).

## Build & run

```powershell
cd windows
dotnet restore
dotnet build -c Release
dotnet run -c Release
```

Publish a self-contained single-file executable to share:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

The result lands in `bin\Release\net8.0-windows\win-x64\publish\Conso Claude.exe`.

## Data & settings

Everything lives under `%APPDATA%\ConsoClaude\`:

- `history.json` — 3 rolling days of session usage (sparkline + burn-rate prediction).
- `cache.json` — last known limits, so a relaunch shows figures immediately.
- `phrases.json` — optional override, merged on top of the embedded pool.
  Keep the voice: calm, literary, a touch of humour, never guilt-tripping.
- `WebView2\` — the popover's isolated browser profile.

"Start with Windows" (tray menu) toggles an entry under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

## Notes on the port

- The Windows tray cannot show text next to the icon (`Shell_NotifyIcon` is icon +
  tooltip only), so the percentage is **painted into the icon**, regenerated on each
  poll — the one place that cannot be pixel-identical to macOS. Everything else is
  reused as-is: the popover HTML/CSS, the plane banner (ported to GDI+), the phrases,
  the thresholds (50/75/90).
- The plane rides in a layered, click-through window (`UpdateLayeredWindow` +
  `WS_EX_TRANSPARENT`), the equivalent of the transparent canvas window on macOS.
- Colour semantics are inverted, like the mac menu-bar figure: coral when little is
  left (≤ 25 %), a full coral tile at 0 % (dry).
