using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;

namespace ConsoClaude;

// Le contrôleur de l'app — port de AppDelegate (mac). NotifyIcon + poll 10 min +
// popover WebView2 + avion aux franchissements de seuil.
public sealed class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _tray = new();
    private readonly PopoverForm _popover = new();
    private readonly UsageClient _client = new();
    private readonly System.Windows.Forms.Timer _poll = new() { Interval = 600_000 }; // 10 min

    private readonly UsageState _state = new();

    // Anti-429 : backoff + pas de refetch si les données sont fraîches.
    private DateTime _backoffUntil = DateTime.MinValue;
    private bool _fetching;
    private DateTime _lastFetchAttempt = DateTime.MinValue;

    // Seuils déjà annoncés par limite (kind → seuils), pour ne pas répéter l'avion.
    private readonly Dictionary<string, HashSet<int>> _announced = new();
    private readonly Dictionary<string, int> _lastPercents = new();
    private static readonly int[] Thresholds = { 50, 75, 90 };

    private List<HistoryPoint> _history = new();
    private IntPtr _currentHicon = IntPtr.Zero;
    private ToolStripMenuItem _loginItem = null!;

    public TrayApp()
    {
        _tray.Visible = true;
        _tray.Text = "Conso Claude";
        _tray.Icon = SystemIcons.Application; // placeholder avant le premier rendu

        BuildMenu();

        _tray.MouseUp += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) TogglePopover();
        };

        _popover.OnAction += action =>
        {
            switch (action)
            {
                case "refresh": Refresh(force: true); break;
                case "plane": TestPlane(); break;
            }
        };

        _history = Store.LoadHistory();
        LoadCachedState();
        Refresh();

        _poll.Tick += (_, _) => Refresh();
        _poll.Start();
    }

    private void BuildMenu()
    {
        var menu = new ContextMenuStrip();

        var refreshItem = new ToolStripMenuItem("Refresh", null, (_, _) => Refresh(force: true))
            { ShortcutKeyDisplayString = "R" };
        menu.Items.Add(refreshItem);

        var planeItem = new ToolStripMenuItem("Test the plane ✈️", null, (_, _) => TestPlane());
        menu.Items.Add(planeItem);

        menu.Items.Add(new ToolStripSeparator());

        _loginItem = new ToolStripMenuItem("Start with Windows", null, (_, _) => ToggleLogin());
        menu.Items.Add(_loginItem);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit Conso Claude", null, (_, _) => Quit()));

        menu.Opening += (_, _) => _loginItem.Checked = Store.LaunchAtLogin;
        _tray.ContextMenuStrip = menu;
    }

    // MARK: Actions

    private void ToggleLogin() => Store.LaunchAtLogin = !Store.LaunchAtLogin;

    private void TestPlane()
    {
        // Chaque test tire un palier au hasard — pour voir toute la variété.
        int remaining = new[] { 50, 25, 10 }[Random.Shared.Next(3)];
        PlaneOverlay.Fly(remaining, "5-hour session", Encouragement.For(remaining, "5-hour session"));
    }

    private void TogglePopover()
    {
        if (_popover.IsOpen) { _popover.HidePopover(); return; }
        // Le popover vient de se fermer via Deactivate (clic sur le tray) → ne pas rouvrir.
        if ((DateTime.Now - _popover.LastHidden).TotalMilliseconds < 300) return;
        PushToWeb(animate: true);
        _popover.SetContentSize(248, PopoverHeight());
        _popover.ShowAt(Cursor.Position);
        // Refetch seulement si les données datent (> 5 min).
        if (_state.FetchedAt is not { } f || (DateTime.Now - f).TotalSeconds > 300)
            Refresh();
    }

    private int PopoverHeight()
    {
        int n = Math.Max(_state.Limits.Count, 1);
        int h = 12 + n * 38 + 19 + 8;
        if (_state.Error != null) h += 22;
        var spark = SparkPayload();
        if (spark.Count >= 3 && spark.Max(p => p.A) >= 1800) h += 38;
        return h;
    }

    // MARK: Fetch

    private async void Refresh(bool force = false)
    {
        if (_fetching) return;
        if (force && (DateTime.Now - _lastFetchAttempt).TotalSeconds < 3) return;
        if (!force && DateTime.Now < _backoffUntil) return;
        _lastFetchAttempt = DateTime.Now;
        _fetching = true;
        try
        {
            var result = await _client.FetchAsync().ConfigureAwait(true); // reprise sur le thread UI
            if (result.RateLimited)
            {
                _backoffUntil = DateTime.Now.AddSeconds(result.BackoffSeconds);
                _state.Stale = _state.Limits.Count > 0;
                _state.Error = _state.Limits.Count == 0
                    ? $"API limit reached — retrying in {(int)(result.BackoffSeconds / 60)} min."
                    : null;
                UpdateTray();
                if (_popover.IsOpen) { PushToWeb(false); _popover.SetContentSize(248, PopoverHeight()); }
                return;
            }
            Apply(result.Limits, result.Error);
        }
        finally { _fetching = false; }
    }

    private void Apply(List<UsageLimit>? limits, string? error)
    {
        _state.Error = error;
        if (limits != null)
        {
            _state.Limits = limits;
            _state.FetchedAt = DateTime.Now;
            _state.Stale = false;
            CheckThresholds(limits);
            SaveCachedState();
            if (_state.Session is { } s) RecordHistory(s.Percent);
        }
        else if (error != null)
        {
            _state.Stale = _state.Limits.Count > 0;
        }
        UpdateTray();
        if (_popover.IsOpen) { PushToWeb(false); _popover.SetContentSize(248, PopoverHeight()); }
    }

    // MARK: Seuils → avion

    private void CheckThresholds(List<UsageLimit> limits)
    {
        foreach (var l in limits)
        {
            int old = _lastPercents.TryGetValue(l.Kind, out var o) ? o : l.Percent;
            if (l.Percent < old - 20)
            {
                _announced[l.Kind] = new HashSet<int>();
                // Petite fête : la session repart de zéro après avoir été bien entamée.
                if (l.IsSession && old >= 75)
                    PlaneOverlay.Fly(100 - l.Percent, "5-hour session", Encouragement.ForReset());
            }
            foreach (var t in Thresholds)
            {
                var set = _announced.TryGetValue(l.Kind, out var s) ? s : (_announced[l.Kind] = new HashSet<int>());
                if (old < t && l.Percent >= t && !set.Contains(t))
                {
                    set.Add(t);
                    PlaneOverlay.Fly(100 - t, l.Label, Encouragement.For(100 - t, l.Label));
                }
            }
            _lastPercents[l.Kind] = l.Percent;
        }
    }

    // MARK: Tray icon (Variante A : % restant peint dans l'icône)

    private void UpdateTray()
    {
        int? remaining = _state.Session is { } s ? 100 - s.Percent : null;
        int size = SmallIconSize();
        var (icon, handle) = TrayIconRenderer.Render(_state.Limits.Count == 0 && _state.Error != null ? null : remaining, size);
        _tray.Icon = icon;
        if (_currentHicon != IntPtr.Zero) TrayIconRenderer.Destroy(_currentHicon);
        _currentHicon = handle;

        // Le tray Windows n'affiche pas de texte à côté de l'icône → tout dans le tooltip.
        string tip;
        if (remaining is { } r)
            tip = $"Conso Claude · {r}% left" + (_state.Stale ? " (cached)" : "");
        else
            tip = _state.Error ?? "Conso Claude";
        _tray.Text = tip.Length > 63 ? tip[..63] : tip;
    }

    // MARK: Popover payload

    private void PushToWeb(bool animate)
    {
        var eta = SessionEta();
        var limits = _state.Limits.Select(l => new
        {
            label = l.Label,
            percent = l.Percent,          // % CONSOMMÉ — le popover calcule le restant lui-même
            reset = FmtResetShort(l.ResetsAt),
            resetFull = FmtResetFull(l.ResetsAt),
            severity = l.Severity,
            session = l.IsSession,
            eta = l.IsSession ? (eta ?? "") : "",
        });

        var payload = new Dictionary<string, object?>
        {
            ["limits"] = limits,
            ["time"] = _state.FetchedAt?.ToString("HH:mm") ?? "",
            ["stale"] = _state.Stale,
            ["spark"] = SparkPayload().Select(p => new { a = p.A, v = p.V }),
        };
        if (_state.Error != null) payload["error"] = _state.Error;

        string json = JsonSerializer.Serialize(payload);
        _popover.Run($"render({json}, {(animate ? "true" : "false")})");
    }

    // MARK: Historique local (sparkline + prédiction)

    private void RecordHistory(int sessionPercent)
    {
        double now = DateTimeOffset.Now.ToUnixTimeMilliseconds() / 1000.0;
        if (_history.Count > 0)
        {
            var last = _history[^1];
            if (now - last.T < 120 && last.V == sessionPercent) return;
        }
        _history.Add(new HistoryPoint(now, sessionPercent));
        double cutoff = now - 3 * 86400;
        _history.RemoveAll(p => p.T < cutoff);
        Store.SaveHistory(_history);
    }

    private readonly record struct SparkPoint(double A, int V);

    private List<SparkPoint> SparkPayload()
    {
        double now = DateTimeOffset.Now.ToUnixTimeMilliseconds() / 1000.0;
        return _history.Where(p => now - p.T <= 6 * 3600)
            .Select(p => new SparkPoint(now - p.T, p.V)).ToList();
    }

    // Au rythme observé, quand la session sera-t-elle à sec ?
    private string? SessionEta()
    {
        if (_state.Session is not { } session || session.Percent < 10 || session.Percent >= 100) return null;
        var pts = new List<HistoryPoint>();
        int ceiling = session.Percent;
        for (int i = _history.Count - 1; i >= 0; i--)
        {
            var h = _history[i];
            if (h.V <= ceiling) { pts.Add(h); ceiling = h.V; } else break;
            if (pts.Count >= 18) break;
        }
        if (pts.Count < 2) return null;
        var newest = pts[0];
        var oldest = pts[^1];
        double dt = newest.T - oldest.T;
        double dv = newest.V - oldest.V;
        if (dt < 600 || dv < 1) return null;
        double etaSec = (100 - session.Percent) / (dv / dt);
        if (!double.IsFinite(etaSec) || etaSec <= 0) return null;
        var eta = DateTime.Now.AddSeconds(etaSec);
        if (session.ResetsAt is { } reset && eta >= reset) return null;
        return $"empty ~{eta:HH:mm}";
    }

    // MARK: Cache disque

    private void SaveCachedState()
    {
        var c = new Store.CachedState
        {
            FetchedAt = _state.FetchedAt,
            Limits = _state.Limits.Select(l => new Store.CachedLimit
            {
                Kind = l.Kind,
                Label = l.Label,
                Percent = l.Percent,
                Severity = l.Severity,
                ResetsAt = l.ResetsAt?.ToString("o") ?? "",
            }).ToList(),
        };
        Store.SaveCache(c);
    }

    private void LoadCachedState()
    {
        var c = Store.LoadCache();
        if (c.Limits.Count == 0) return;
        _state.Limits = c.Limits.Select(d => new UsageLimit(
            Kind: d.Kind,
            Label: d.Label,
            Percent: d.Percent,
            ResetsAt: UsageClient.ParseDate(d.ResetsAt),
            Severity: d.Severity,
            IsSession: d.Kind == "session")).ToList();
        _state.FetchedAt = c.FetchedAt;
        _state.Stale = true;
        UpdateTray();
    }

    // MARK: Formatage (anglais)

    private static string FmtResetShort(DateTime? d)
    {
        if (d is not { } dt) return "";
        int s = (int)(dt - DateTime.Now).TotalSeconds;
        if (s <= 0) return "reset";
        int h = s / 3600, m = (s % 3600) / 60;
        if (h >= 24) return $"{h / 24}d {h % 24}h";
        if (h > 0) return $"{h}h {m:D2}";
        return $"{m} min";
    }

    private static string FmtResetFull(DateTime? d)
    {
        if (d is not { } dt) return "";
        return "Resets " + dt.ToString("dddd, MMMM d 'at' HH:mm", CultureInfo.GetCultureInfo("en-US"));
    }

    // MARK: Quit

    private void Quit()
    {
        _poll.Stop();
        _tray.Visible = false;
        if (_currentHicon != IntPtr.Zero) TrayIconRenderer.Destroy(_currentHicon);
        _tray.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _tray.Dispose();
            _popover.Dispose();
        }
        base.Dispose(disposing);
    }

    // MARK: interop

    private static int SmallIconSize()
    {
        try
        {
            int s = GetSystemMetrics(SM_CXSMICON);
            return s > 0 ? s : 16;
        }
        catch { return 16; }
    }

    private const int SM_CXSMICON = 49;
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int nIndex);
}
