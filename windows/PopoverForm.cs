using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace ConsoClaude;

// Le popover compact — WebView2 hébergeant le HTML/CSS du mac tel quel.
// Comportement « transient » : se ferme dès qu'il perd le focus.
public sealed class PopoverForm : Form
{
    private readonly WebView2 _web = new();
    private bool _ready;
    private string? _pendingScript;
    private bool _navigated;

    public event Action<string>? OnAction;   // "refresh" | "plane"

    public PopoverForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        ClientSize = new Size(248, 160);
        // Surface derrière le HTML transparent : suit le thème système.
        BackColor = IsDarkTheme() ? ColorTranslator.FromHtml("#1E1B17") : ColorTranslator.FromHtml("#F4F1EA");

        _web.Dock = DockStyle.Fill;
        _web.DefaultBackgroundColor = Color.Transparent;
        Controls.Add(_web);

        Deactivate += (_, _) => HidePopover();
        InitWebAsync();
        RoundCorners();
    }

    protected override bool ShowWithoutActivation => false;

    private async void InitWebAsync()
    {
        try
        {
            // Environnement isolé dans %APPDATA% : pas de trace hors du dossier de l'app.
            var env = await CoreWebView2Environment.CreateAsync(
                userDataFolder: Path.Combine(Store.Dir, "WebView2"));
            await _web.EnsureCoreWebView2Async(env);

            var s = _web.CoreWebView2.Settings;
            s.AreDevToolsEnabled = false;
            s.AreDefaultContextMenusEnabled = false;
            s.IsStatusBarEnabled = false;
            s.AreBrowserAcceleratorKeysEnabled = false;
            s.IsZoomControlEnabled = false;

            _web.CoreWebView2.WebMessageReceived += (_, e) =>
            {
                try { OnAction?.Invoke(e.TryGetWebMessageAsString() ?? ""); } catch { }
            };

            _web.NavigationCompleted += (_, _) =>
            {
                _ready = true;
                if (_pendingScript is { } js) { _ = _web.ExecuteScriptAsync(js); _pendingScript = null; }
            };

            _web.CoreWebView2.NavigateToString(Store.ReadEmbeddedText("popover.html"));
            _navigated = true;
        }
        catch
        {
            // WebView2 Runtime absent : on laisse le tray fonctionner sans popover.
        }
    }

    public void Run(string js)
    {
        if (_ready && _navigated) _ = _web.ExecuteScriptAsync(js);
        else _pendingScript = js;
    }

    public bool IsOpen => Visible;

    // Un clic sur le tray déclenche d'abord Deactivate (masquage) puis MouseUp :
    // ce timestamp permet au toggle d'ignorer une réouverture immédiate.
    public DateTime LastHidden { get; private set; } = DateTime.MinValue;

    public void SetContentSize(int width, int height) => ClientSize = new Size(width, height);

    // Affiche le popover ancré près du tray (coin bas-droit, au-dessus de la barre des tâches).
    public void ShowAt(Point anchor)
    {
        var wa = Screen.FromPoint(anchor).WorkingArea;
        int x = Math.Min(anchor.X - Width + 20, wa.Right - Width - 8);
        x = Math.Max(x, wa.Left + 8);
        int y = Math.Min(anchor.Y - Height - 8, wa.Bottom - Height - 8);
        y = Math.Max(y, wa.Top + 8);
        Location = new Point(x, y);
        Show();
        Activate();
        BringToFront();
    }

    public void HidePopover()
    {
        if (Visible) { Hide(); LastHidden = DateTime.Now; }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x80;        // WS_EX_TOOLWINDOW : hors Alt-Tab
            cp.ClassStyle |= 0x20000;  // CS_DROPSHADOW
            return cp;
        }
    }

    private void RoundCorners()
    {
        try
        {
            int pref = 2; // DWMWCP_ROUND
            DwmSetWindowAttribute(Handle, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, ref pref, sizeof(int));
        }
        catch { }
    }

    private static bool IsDarkTheme()
    {
        try
        {
            using var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch { return false; }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
}
