using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace ConsoClaude;

// Variante A — le % RESTANT peint dans l'icône du tray : chiffre plein sur tuile
// ivoire (DA Anthropic ivoire/encre/corail). Le tray Windows n'affiche pas de texte
// à côté de l'icône (limite OS), donc on régénère l'image à chaque poll, façon
// widgets batterie/CPU. Sémantique couleur inversée : corail = il reste peu.
public static class TrayIconRenderer
{
    // Palette Anthropic.
    private static readonly Color Ivory = ColorTranslator.FromHtml("#F0EEE6");
    private static readonly Color Ink   = ColorTranslator.FromHtml("#262625");
    private static readonly Color Coral = ColorTranslator.FromHtml("#D97757");
    private static readonly Color Amber = ColorTranslator.FromHtml("#E8940C");
    private static readonly Color Crit  = ColorTranslator.FromHtml("#E5493A");

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    // Rend l'icône pour un % restant donné (ou null = erreur/inconnu → « ! »).
    // Retourne l'Icon + le HICON à détruire une fois l'icône remplacée.
    public static (Icon icon, IntPtr handle) Render(int? remaining, int size)
    {
        using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);

            // À sec (0 %) → tuile pleine corail, chiffre ivoire. Sinon tuile ivoire.
            bool dry = remaining is <= 0;
            Color tile = dry ? Crit : Ivory;
            Color digit;
            if (remaining is null) digit = Amber;
            else if (dry) digit = Ivory;
            else if (remaining <= 25) digit = Coral;
            else if (remaining <= 50) digit = Amber;
            else digit = Ink;

            float pad = MathF.Max(1f, size * 0.06f);
            float radius = MathF.Max(2f, size * 0.22f);
            var rect = new RectangleF(pad, pad, size - 2 * pad, size - 2 * pad);
            using (var path = Rounded(rect, radius))
            using (var fill = new SolidBrush(tile))
                g.FillPath(fill, path);
            // Liseré discret pour détacher la tuile ivoire des fonds clairs.
            if (!dry)
                using (var pen = new Pen(Color.FromArgb(38, Ink), MathF.Max(1f, size / 32f)))
                using (var path = Rounded(rect, radius))
                    g.DrawPath(pen, path);

            string text = remaining is null ? "!" : remaining.Value.ToString();
            DrawFittedText(g, text, rect, digit, bold: remaining is null || remaining <= 25);
        }

        IntPtr handle = bmp.GetHicon();
        return (Icon.FromHandle(handle), handle);
    }

    public static void Destroy(IntPtr handle)
    {
        if (handle != IntPtr.Zero) DestroyIcon(handle);
    }

    private static GraphicsPath Rounded(RectangleF r, float radius)
    {
        float d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    // Cherche la taille de police qui remplit la tuile (« 100 » plus petit que « 5 »).
    private static void DrawFittedText(Graphics g, string text, RectangleF rect, Color color, bool bold)
    {
        var fmt = new StringFormat(StringFormat.GenericTypographic)
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
        };
        float target = rect.Width * 0.90f;
        float targetH = rect.Height * 0.86f;
        var style = bold ? FontStyle.Bold : FontStyle.Bold; // toujours gras : lisible en 16 px
        float lo = 4, hi = rect.Height, best = lo;
        // Recherche dichotomique de la taille max qui tient dans la tuile.
        for (int i = 0; i < 12; i++)
        {
            float mid = (lo + hi) / 2f;
            using var font = new Font("Segoe UI", mid, style, GraphicsUnit.Pixel);
            var s = g.MeasureString(text, font, PointF.Empty, fmt);
            if (s.Width <= target && s.Height <= targetH) { best = mid; lo = mid; }
            else hi = mid;
        }
        using var chosen = new Font("Segoe UI", best, style, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(color);
        g.DrawString(text, chosen, brush, rect, fmt);
    }
}
