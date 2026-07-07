using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ConsoClaude;

// L'avion-banderole qui traverse l'écran ✈️ — équivalent Windows de PlaneBanner.
// Fenêtre layered (alpha par pixel) + click-through (WS_EX_TRANSPARENT) + sans
// activation. Glisse depuis la gauche → pause au centre → sort à droite.
public sealed class PlaneOverlay : Form
{
    // Sérialise les vols : deux seuils franchis au même refresh → deux passages
    // successifs, pas deux banderoles superposées.
    private static DateTime _busyUntil = DateTime.MinValue;

    public static void Fly(int remaining, string context, string phrase)
    {
        var now = DateTime.Now;
        var start = now > _busyUntil ? now : _busyUntil;
        _busyUntil = start.AddSeconds(5.3);
        var delay = start - now;

        if (delay.TotalSeconds < 0.05) FlyNow(remaining, context, phrase);
        else
        {
            var t = new System.Windows.Forms.Timer { Interval = Math.Max(1, (int)delay.TotalMilliseconds) };
            t.Tick += (_, _) => { t.Stop(); t.Dispose(); FlyNow(remaining, context, phrase); };
            t.Start();
        }
    }

    private static void FlyNow(int remaining, string context, string phrase)
    {
        var bmp = BannerRenderer.MakeBanner(remaining, context, phrase);
        var overlay = new PlaneOverlay(bmp);
        overlay.Run();
    }

    private readonly Bitmap _bitmap;
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 16 };
    private readonly Stopwatch _clock = new();
    private Rectangle _wa;
    private int _laneY;
    private byte _alpha = 255;
    private readonly bool _reduceMotion = !ClientAreaAnimationEnabled();

    // Chronologie (identique au mac).
    private const double Arrive = 0.65, Dwell = 3.4, Exit = 0.55;
    private const double Total = Arrive + Dwell + Exit;

    private PlaneOverlay(Bitmap bmp)
    {
        _bitmap = bmp;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Size = bmp.Size;
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST;
            return cp;
        }
    }

    private void Run()
    {
        // Écran sous le curseur — c'est là que l'utilisateur regarde.
        var screen = Screen.FromPoint(Cursor.Position);
        _wa = screen.WorkingArea;
        _laneY = _wa.Top + 36;

        if (_reduceMotion)
        {
            // Fondu au centre, sans translation (respect de « Réduire les animations »).
            Location = new Point(_wa.Left + (_wa.Width - _bitmap.Width) / 2, _laneY);
            _alpha = 0;
            Show();
            RenderLayered(0);
        }
        else
        {
            Location = new Point(_wa.Left - _bitmap.Width, _laneY);
            Show();
            RenderLayered(255);
        }

        _clock.Start();
        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(object? sender, EventArgs e)
    {
        double t = _clock.Elapsed.TotalSeconds;

        if (_reduceMotion)
        {
            // 0.4 s fondu entrant · 4 s pause · 0.6 s fondu sortant.
            const double fin = 0.4, hold = 4.0, fout = 0.6;
            if (t < fin) _alpha = (byte)(255 * (t / fin));
            else if (t < fin + hold) _alpha = 255;
            else if (t < fin + hold + fout) _alpha = (byte)(255 * (1 - (t - fin - hold) / fout));
            else { Finish(); return; }
            RenderLayered(_alpha);
            return;
        }

        if (t >= Total + 0.3) { Finish(); return; }

        double x;
        int startX = _wa.Left - _bitmap.Width;
        int centerX = _wa.Left + (_wa.Width - _bitmap.Width) / 2;
        int outX = _wa.Right;
        if (t < Arrive)
        {
            double p = EaseOutCubic(t / Arrive);
            x = startX + (centerX - startX) * p;
        }
        else if (t < Arrive + Dwell)
        {
            x = centerX;
        }
        else if (t < Total)
        {
            double p = EaseInCubic((t - Arrive - Dwell) / Exit);
            x = centerX + (outX - centerX) * p;
        }
        else x = outX;

        // Flottement discret pendant la pause.
        double bob = (t >= Arrive && t < Arrive + Dwell)
            ? Math.Sin((t - Arrive) * Math.PI / 0.7) * 2 : 0;

        Location = new Point((int)Math.Round(x), _laneY + (int)Math.Round(bob));
    }

    private void Finish()
    {
        _timer.Stop();
        _timer.Dispose();
        _clock.Stop();
        Close();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _bitmap.Dispose();
        base.Dispose(disposing);
    }

    // Peint la Bitmap dans la fenêtre layered avec un alpha global.
    private void RenderLayered(byte alpha)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBitmap = _bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr oldBitmap = SelectObject(memDc, hBitmap);
        try
        {
            var size = new SIZE { cx = _bitmap.Width, cy = _bitmap.Height };
            var src = new POINT { x = 0, y = 0 };
            var dst = new POINT { x = Left, y = Top };
            var blend = new BLENDFUNCTION
            {
                BlendOp = AC_SRC_OVER,
                BlendFlags = 0,
                SourceConstantAlpha = alpha,
                AlphaFormat = AC_SRC_ALPHA,
            };
            UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref blend, ULW_ALPHA);
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screenDc);
            SelectObject(memDc, oldBitmap);
            DeleteObject(hBitmap);
            DeleteDC(memDc);
        }
    }

    private static double EaseOutCubic(double t) => 1 - Math.Pow(1 - Math.Clamp(t, 0, 1), 3);
    private static double EaseInCubic(double t) { t = Math.Clamp(t, 0, 1); return t * t * t; }

    private static bool ClientAreaAnimationEnabled()
    {
        bool enabled = true;
        try { SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, ref enabled, 0); }
        catch { }
        return enabled;
    }

    // MARK: interop

    private const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80,
                      WS_EX_NOACTIVATE = 0x8000000, WS_EX_TOPMOST = 0x8;
    private const int ULW_ALPHA = 0x2;
    private const byte AC_SRC_OVER = 0x00, AC_SRC_ALPHA = 0x01;
    private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential)] private struct BLENDFUNCTION
    { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
        IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref bool pvParam, uint fWinIni);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
}
