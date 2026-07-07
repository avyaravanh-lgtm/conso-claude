using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;

namespace ConsoClaude;

// Port GDI+ de Banner.swift. Tout est rendu dans une seule Bitmap (fiable dans la
// fenêtre layered click-through, une seule texture à animer). Coordonnées converties
// en top-down (GDI, y vers le bas) depuis le repère bottom-up de macOS.
public static class BannerRenderer
{
    private static readonly Color Ink       = ColorTranslator.FromHtml("#262625");
    private static readonly Color Coral      = ColorTranslator.FromHtml("#D97757");
    private static readonly Color CoralDark  = Color.FromArgb(178, 92, 64);   // 0.70/0.36/0.25
    private static readonly Color Ivory      = ColorTranslator.FromHtml("#F0EEE6");

    // Petit avion à hélice vu de profil, pointé vers la droite, palette Anthropic.
    private static void DrawPlane(Graphics g, RectangleF box)
    {
        float x = box.Left, cy = box.Top + box.Height / 2f, w = box.Width, h = box.Height;

        using var coral = new SolidBrush(Coral);
        using var coralDark = new SolidBrush(CoralDark);
        using var ivory = new SolidBrush(Ivory);

        // Aile haute, derrière le fuselage.
        g.FillPolygon(coralDark, new[]
        {
            new PointF(x + w*0.60f, cy - 1),
            new PointF(x + w*0.48f, cy - h*0.44f),
            new PointF(x + w*0.40f, cy - h*0.40f),
            new PointF(x + w*0.50f, cy + 1),
        });

        // Stabilisateur de queue.
        g.FillPolygon(coralDark, new[]
        {
            new PointF(x + w*0.28f, cy),
            new PointF(x + w*0.16f, cy + h*0.18f),
            new PointF(x + w*0.10f, cy + h*0.13f),
            new PointF(x + w*0.22f, cy - 2),
        });

        // Fuselage — capsule.
        float bodyH = h * 0.36f;
        using (var body = Capsule(new RectangleF(x + w*0.20f, cy - bodyH/2f, w*0.74f, bodyH)))
            g.FillPath(coral, body);

        // Dérive de queue.
        g.FillPolygon(coral, new[]
        {
            new PointF(x + w*0.30f, cy - bodyH*0.28f),
            new PointF(x + w*0.19f, cy - h*0.48f),
            new PointF(x + w*0.12f, cy - h*0.42f),
            new PointF(x + w*0.21f, cy + bodyH*0.05f),
        });

        // Aile basse, devant le fuselage.
        g.FillPolygon(coralDark, new[]
        {
            new PointF(x + w*0.66f, cy - 1),
            new PointF(x + w*0.58f, cy + h*0.38f),
            new PointF(x + w*0.50f, cy + h*0.33f),
            new PointF(x + w*0.56f, cy + 1),
        });

        // Hublot.
        g.FillEllipse(ivory, x + w*0.72f, cy - bodyH*0.02f - 5, 5, 5);

        // Hélice — disque flou au nez + moyeu.
        using (var prop = new SolidBrush(Color.FromArgb(71, Ink)))   // 0.28
            g.FillEllipse(prop, x + w*0.93f, cy - h*0.34f, w*0.07f, h*0.68f);
        using (var hub = new SolidBrush(Color.FromArgb(191, Ink)))   // 0.75
            g.FillEllipse(hub, x + w*0.945f, cy - 2, 4, 4);
    }

    public static Bitmap MakeBanner(int remaining, string context, string phrase)
    {
        // Accent selon l'urgence (palette Anthropic).
        Color accent = remaining <= 10 ? ColorTranslator.FromHtml("#E5493A")
                     : remaining <= 25 ? ColorTranslator.FromHtml("#E8940C")
                     : Coral;

        using var number  = Serif(27, FontStyle.Bold);
        using var caption = new Font("Segoe UI", 10, FontStyle.Bold, GraphicsUnit.Pixel);
        using var phraseF = Serif(14, FontStyle.Italic);
        using var markF   = new Font("Segoe UI", 22, FontStyle.Bold, GraphicsUnit.Pixel);

        string numberStr = $"{remaining} %";
        string captionStr = ("remaining · " + context).ToUpperInvariant();
        string markStr = "✳";

        // Mesures (repère typographique pour coller à la mise en page).
        SizeF numberSize, captionSize, phraseSize, markSize;
        using (var probe = new Bitmap(1, 1))
        using (var pg = Graphics.FromImage(probe))
        {
            pg.TextRenderingHint = TextRenderingHint.AntiAlias;
            numberSize = Measure(pg, numberStr, number);
            captionSize = MeasureTracked(pg, captionStr, caption, 1.6f);
            phraseSize = Measure(pg, phrase, phraseF);
            markSize = Measure(pg, markStr, markF);
        }

        float markCol = markSize.Width + 14;
        float line1W = numberSize.Width + 10 + captionSize.Width;
        float textW = MathF.Max(line1W, phraseSize.Width);
        float cardW = 20 + markCol + textW + 22;
        const float cardH = 74;
        const float margin = 18;      // marge pour l'ombre
        const float planeW = 58, planeH = 36, ropeW = 22;
        float cardX = margin;
        float planeX = cardX + cardW + ropeW;

        int imgW = (int)MathF.Ceiling(planeX + planeW + margin);
        int imgH = (int)MathF.Ceiling(cardH + margin * 2);

        // PArgb : alpha prémultiplié, requis par UpdateLayeredWindow.
        var bmp = new Bitmap(imgW, imgH, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            g.Clear(Color.Transparent);

            float cy = margin + cardH / 2f;

            // L'avion (tire la banderole derrière lui).
            DrawPlane(g, new RectangleF(planeX, cy - planeH / 2f, planeW, planeH));

            // La corde, avec un léger ventre.
            using (var rope = new GraphicsPath())
            using (var ropePen = new Pen(Color.FromArgb(102, Ink), 1))  // 0.4
            {
                rope.AddBezier(
                    new PointF(cardX + cardW - 1, cy),
                    new PointF(cardX + cardW + ropeW * 0.3f, cy + 4),
                    new PointF(cardX + cardW + ropeW * 0.7f, cy + 4),
                    new PointF(planeX + planeW * 0.10f, cy));
                g.DrawPath(ropePen, rope);
            }

            var rect = new RectangleF(cardX, margin, cardW, cardH);

            // Ombre douce (approx blur par passes concentriques).
            for (int i = 6; i >= 1; i--)
            {
                float grow = i * 1.6f;
                var sr = new RectangleF(rect.X - grow, rect.Y - grow + 3, rect.Width + 2 * grow, rect.Height + 2 * grow);
                using var sp = RoundedRect(sr, 12 + grow);
                using var sb = new SolidBrush(Color.FromArgb(10, 0, 0, 0));
                g.FillPath(sb, sp);
            }

            using (var card = RoundedRect(rect, 12))
            {
                using var fill = new SolidBrush(Ivory);
                g.FillPath(fill, card);
                using var border = new Pen(Color.FromArgb(31, Ink), 1);  // 0.12
                g.DrawPath(border, card);
            }

            // ✳ centré verticalement.
            using (var markBrush = new SolidBrush(accent))
                DrawString(g, markStr, markF, markBrush,
                    cardX + 18, margin + (cardH - markSize.Height) / 2f);

            float xText = cardX + 20 + markCol;
            using (var numBrush = new SolidBrush(accent))
                DrawString(g, numberStr, number, numBrush, xText, margin + 8);
            using (var capBrush = new SolidBrush(Color.FromArgb(128, Ink)))
                DrawTracked(g, captionStr, caption, capBrush,
                    xText + numberSize.Width + 10, margin + numberSize.Height - captionSize.Height - 1, 1.6f);
            using (var phBrush = new SolidBrush(Color.FromArgb(217, Ink)))
                DrawString(g, phrase, phraseF, phBrush, xText, margin + cardH - phraseSize.Height - 10);
        }
        return bmp;
    }

    // MARK: helpers

    private static Font Serif(float px, FontStyle style)
    {
        // Georgia : serif présent partout sur Windows, proche de la DA « New York » du mac.
        try { return new Font("Georgia", px, style, GraphicsUnit.Pixel); }
        catch { return new Font(FontFamily.GenericSerif, px, style, GraphicsUnit.Pixel); }
    }

    private static readonly StringFormat Typo = new(StringFormat.GenericTypographic)
    {
        FormatFlags = StringFormatFlags.MeasureTrailingSpaces,
    };

    private static SizeF Measure(Graphics g, string s, Font f)
        => g.MeasureString(s, f, PointF.Empty, Typo);

    private static SizeF MeasureTracked(Graphics g, string s, Font f, float tracking)
    {
        float w = 0, h = 0;
        foreach (var ch in s)
        {
            var sz = g.MeasureString(ch.ToString(), f, PointF.Empty, Typo);
            w += sz.Width + tracking;
            h = MathF.Max(h, sz.Height);
        }
        return new SizeF(MathF.Max(0, w - tracking), h);
    }

    private static void DrawString(Graphics g, string s, Font f, Brush b, float x, float y)
        => g.DrawString(s, f, b, x, y, Typo);

    private static void DrawTracked(Graphics g, string s, Font f, Brush b, float x, float y, float tracking)
    {
        foreach (var ch in s)
        {
            g.DrawString(ch.ToString(), f, b, x, y, Typo);
            x += g.MeasureString(ch.ToString(), f, PointF.Empty, Typo).Width + tracking;
        }
    }

    private static GraphicsPath Capsule(RectangleF r)
    {
        float d = r.Height;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 90, 180);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 180);
        p.CloseFigure();
        return p;
    }

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
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
}
