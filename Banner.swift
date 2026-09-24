// Dessin de la carte d'alerte conso, partagé entre l'app et l'outil d'aperçu.
// Tout est rendu dans une seule NSImage : fiable dans une fenêtre borderless,
// et une seule texture à animer.

import Cocoa

// Petit avion à hélice vu de profil, pointé vers la droite, palette Anthropic.
func drawPlane(in box: NSRect) {
    let ink = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.14, alpha: 1)
    let coral = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    let coralDark = NSColor(srgbRed: 0.70, green: 0.36, blue: 0.25, alpha: 1)
    let ivory = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1)
    let x = box.minX, cy = box.midY, w = box.width, h = box.height

    // Aile haute, derrière le fuselage — fine et en flèche vers l'arrière.
    let wingBack = NSBezierPath()
    wingBack.move(to: NSPoint(x: x + w * 0.60, y: cy + 1))
    wingBack.line(to: NSPoint(x: x + w * 0.48, y: cy + h * 0.44))
    wingBack.line(to: NSPoint(x: x + w * 0.40, y: cy + h * 0.40))
    wingBack.line(to: NSPoint(x: x + w * 0.50, y: cy - 1))
    wingBack.close()
    coralDark.setFill(); wingBack.fill()

    // Stabilisateur de queue (petit, vers le bas-arrière).
    let tailplane = NSBezierPath()
    tailplane.move(to: NSPoint(x: x + w * 0.28, y: cy))
    tailplane.line(to: NSPoint(x: x + w * 0.16, y: cy - h * 0.18))
    tailplane.line(to: NSPoint(x: x + w * 0.10, y: cy - h * 0.13))
    tailplane.line(to: NSPoint(x: x + w * 0.22, y: cy + 2))
    tailplane.close()
    coralDark.setFill(); tailplane.fill()

    // Fuselage — capsule.
    let bodyH = h * 0.36
    let body = NSBezierPath(roundedRect: NSRect(x: x + w * 0.20, y: cy - bodyH / 2, width: w * 0.74, height: bodyH),
                            xRadius: bodyH / 2, yRadius: bodyH / 2)
    coral.setFill(); body.fill()

    // Dérive de queue — élancée, inclinée vers l'arrière.
    let fin = NSBezierPath()
    fin.move(to: NSPoint(x: x + w * 0.30, y: cy + bodyH * 0.28))
    fin.line(to: NSPoint(x: x + w * 0.19, y: cy + h * 0.48))
    fin.line(to: NSPoint(x: x + w * 0.12, y: cy + h * 0.42))
    fin.line(to: NSPoint(x: x + w * 0.21, y: cy - bodyH * 0.05))
    fin.close()
    coral.setFill(); fin.fill()

    // Aile basse, devant le fuselage — fine.
    let wingFront = NSBezierPath()
    wingFront.move(to: NSPoint(x: x + w * 0.66, y: cy + 1))
    wingFront.line(to: NSPoint(x: x + w * 0.58, y: cy - h * 0.38))
    wingFront.line(to: NSPoint(x: x + w * 0.50, y: cy - h * 0.33))
    wingFront.line(to: NSPoint(x: x + w * 0.56, y: cy - 1))
    wingFront.close()
    coralDark.setFill(); wingFront.fill()

    // Hublot.
    let win = NSBezierPath(ovalIn: NSRect(x: x + w * 0.72, y: cy + bodyH * 0.02, width: 5, height: 5))
    ivory.setFill(); win.fill()

    // Hélice — disque flou au nez + moyeu.
    let prop = NSBezierPath(ovalIn: NSRect(x: x + w * 0.93, y: cy - h * 0.34, width: w * 0.07, height: h * 0.68))
    ink.withAlphaComponent(0.28).setFill(); prop.fill()
    let hub = NSBezierPath(ovalIn: NSRect(x: x + w * 0.945, y: cy - 2, width: 4, height: 4))
    ink.withAlphaComponent(0.75).setFill(); hub.fill()
}

// Quelle CONSO l'avion annonce-t-il ? Trois familles, chacune sa couleur, son icône
// et son libellé court — pour la reconnaître SANS lire (le texte ne fait que confirmer).
// La couleur de la FAMILLE (bleu/violet/vert) est indépendante de la couleur d'URGENCE
// du grand nombre (corail/orange/rouge) : l'une dit « laquelle », l'autre « combien ».
enum BannerKind { case session, weeklyAll, weeklyModel }

func bannerKind(_ context: String) -> BannerKind {
    let lc = context.lowercased()
    if lc.contains("session") { return .session }
    if lc.contains("all models") { return .weeklyAll }
    if lc.hasPrefix("weekly") { return .weeklyModel }   // « Weekly — Fable », « Weekly — Opus »…
    return .weeklyAll
}

// Libellé court, en capitales tracées. Pour un modèle nommé (Fable…), on garde son nom.
func bannerLabel(_ context: String, _ kind: BannerKind) -> String {
    switch kind {
    case .session:   return "SESSION · 5 H"
    case .weeklyAll: return "TOUS MODÈLES · SEMAINE"
    case .weeklyModel:
        let model = context.components(separatedBy: "—").last?.trimmingCharacters(in: .whitespaces) ?? context
        return "\(model) · SEMAINE".uppercased()
    }
}

func bannerKindColor(_ kind: BannerKind) -> NSColor {
    switch kind {
    case .session:     return NSColor(srgbRed: 0.24, green: 0.52, blue: 0.78, alpha: 1)  // bleu
    case .weeklyAll:   return NSColor(srgbRed: 0.52, green: 0.42, blue: 0.82, alpha: 1)  // violet
    case .weeklyModel: return NSColor(srgbRed: 0.16, green: 0.60, blue: 0.52, alpha: 1)  // vert-sarcelle
    }
}

// Icône de la famille, dessinée dans `r` avec la couleur de la famille.
func drawKindIcon(_ kind: BannerKind, in r: NSRect, color: NSColor) {
    color.setStroke(); color.setFill()
    switch kind {
    case .session:
        // Horloge : la fenêtre glissante de 5 h.
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 2; ring.stroke()
        let c = NSPoint(x: r.midX, y: r.midY)
        let hands = NSBezierPath()
        hands.move(to: c); hands.line(to: NSPoint(x: c.x, y: c.y + r.height * 0.24))          // aiguille des minutes
        hands.move(to: c); hands.line(to: NSPoint(x: c.x + r.width * 0.20, y: c.y))            // aiguille des heures
        hands.lineWidth = 2; hands.lineCapStyle = .round; hands.stroke()
    case .weeklyAll:
        // Trois barres croissantes : l'agrégat de TOUS les modèles.
        let n = 3, gap = r.width * 0.16
        let bw = (r.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let heights: [CGFloat] = [0.45, 0.72, 1.0]
        for i in 0..<n {
            let x = r.minX + CGFloat(i) * (bw + gap)
            NSBezierPath(roundedRect: NSRect(x: x, y: r.minY, width: bw, height: r.height * heights[i]),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
    case .weeklyModel:
        // Losange plein : UN modèle donné (Fable…).
        let d = NSBezierPath()
        d.move(to: NSPoint(x: r.midX, y: r.maxY))
        d.line(to: NSPoint(x: r.maxX, y: r.midY))
        d.line(to: NSPoint(x: r.midX, y: r.minY))
        d.line(to: NSPoint(x: r.minX, y: r.midY))
        d.close(); d.fill()
    }
}

func makeBannerImage(remaining: Int, context: String, phrase: String) -> NSImage {
    // Palette Anthropic : ivoire, encre, accent selon l'urgence.
    let ivory = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1)   // #F0EEE6
    let ink = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.14, alpha: 1)     // #262625
    let accent: NSColor
    if remaining <= 10 {
        accent = NSColor(srgbRed: 0.90, green: 0.29, blue: 0.23, alpha: 1)  // rouge
    } else if remaining <= 25 {
        accent = NSColor(srgbRed: 0.91, green: 0.58, blue: 0.05, alpha: 1)  // orange
    } else {
        accent = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)  // corail
    }

    let kind = bannerKind(context)
    let kindColor = bannerKindColor(kind)

    func serif(_ size: CGFloat, _ weight: NSFont.Weight, italic: Bool) -> NSFont {
        var desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)
        if italic { desc = desc?.withSymbolicTraits(.italic) }
        return desc.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    // Ligne du haut : la FAMILLE (icône + libellé, couleur de famille).
    let labelStr = NSAttributedString(string: bannerLabel(context, kind), attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .bold),
        .kern: 1.4,
        .foregroundColor: kindColor,
    ])
    // Le héros : le pourcentage restant, gros serif en couleur d'urgence.
    let numberStr = NSAttributedString(string: "\(remaining) %", attributes: [
        .font: serif(26, .semibold, italic: false),
        .foregroundColor: accent,
    ])
    let leftStr = NSAttributedString(string: "restant", attributes: [
        .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
        .kern: 1.0,
        .foregroundColor: ink.withAlphaComponent(0.4),
    ])
    let phraseStr = NSAttributedString(string: phrase, attributes: [
        .font: serif(13.5, .regular, italic: true),
        .foregroundColor: ink.withAlphaComponent(0.85),
    ])

    let labelSize = labelStr.size()
    let numberSize = numberStr.size()
    let leftSize = leftStr.size()
    let phraseSize = phraseStr.size()

    let iconBox: CGFloat = 26
    let iconCol = iconBox + 14          // icône + gouttière
    let gaugeW: CGFloat = 84            // jauge entre le nombre et « restant »
    // Ligne 2 : nombre · jauge · « restant ».
    let line2W = numberSize.width + 12 + gaugeW + 6 + leftSize.width
    let labelRowW = iconBox + 8 + labelSize.width   // icône + libellé sur la 1re ligne
    let textW = max(max(labelRowW, line2W), phraseSize.width)
    let cardW = 18 + iconCol + textW + 20
    let cardH: CGFloat = 90
    let margin: CGFloat = 18   // marge pour l'ombre
    let planeW: CGFloat = 58
    let planeH: CGFloat = 36
    let ropeW: CGFloat = 22
    let cardX = margin
    let planeX = cardX + cardW + ropeW

    return NSImage(size: NSSize(width: planeX + planeW + margin, height: cardH + margin * 2), flipped: false) { _ in
        let cy = margin + cardH / 2

        // L'avion (pointé vers la droite — il tire la banderole derrière lui).
        drawPlane(in: NSRect(x: planeX, y: cy - planeH / 2, width: planeW, height: planeH))

        // La corde, avec un léger ventre.
        let rope = NSBezierPath()
        rope.move(to: NSPoint(x: cardX + cardW - 1, y: cy))
        rope.curve(to: NSPoint(x: planeX + planeW * 0.10, y: cy),
                   controlPoint1: NSPoint(x: cardX + cardW + ropeW * 0.3, y: cy - 4),
                   controlPoint2: NSPoint(x: cardX + cardW + ropeW * 0.7, y: cy - 4))
        ink.withAlphaComponent(0.4).setStroke()
        rope.lineWidth = 1
        rope.stroke()

        let rect = NSRect(x: cardX, y: margin, width: cardW, height: cardH)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        ivory.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Liseré de la carte, teinté par la FAMILLE (renfort de la couleur d'identité).
        kindColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let padTop: CGFloat = 12
        let xText = cardX + 18 + iconCol

        // Ligne 1 : icône de famille + libellé, alignés en haut.
        let labelBaseY = margin + cardH - padTop - labelSize.height
        drawKindIcon(kind, in: NSRect(x: cardX + 18, y: labelBaseY - (iconBox - labelSize.height) / 2 - 2,
                                      width: iconBox, height: iconBox), color: kindColor)
        labelStr.draw(at: NSPoint(x: xText, y: labelBaseY))

        // Ligne 2 : grand nombre · jauge · « restant ».
        let numberY = margin + 12 + phraseSize.height + 8
        numberStr.draw(at: NSPoint(x: xText, y: numberY))

        // Jauge : piste + remplissage = ce qu'il RESTE, en couleur d'urgence.
        let gaugeH: CGFloat = 6
        let gaugeX = xText + numberSize.width + 12
        let gaugeMidY = numberY + numberSize.height / 2 - 2
        let gaugeY = gaugeMidY - gaugeH / 2
        let track = NSBezierPath(roundedRect: NSRect(x: gaugeX, y: gaugeY, width: gaugeW, height: gaugeH),
                                 xRadius: gaugeH / 2, yRadius: gaugeH / 2)
        ink.withAlphaComponent(0.12).setFill(); track.fill()
        let fillW = max(gaugeH, gaugeW * CGFloat(max(0, min(remaining, 100))) / 100)
        let fill = NSBezierPath(roundedRect: NSRect(x: gaugeX, y: gaugeY, width: fillW, height: gaugeH),
                                xRadius: gaugeH / 2, yRadius: gaugeH / 2)
        accent.setFill(); fill.fill()

        // « restant » après la jauge, centré sur elle.
        leftStr.draw(at: NSPoint(x: gaugeX + gaugeW + 6, y: gaugeMidY - leftSize.height / 2))

        // Ligne 3 : la phrase, en bas.
        phraseStr.draw(at: NSPoint(x: xText, y: margin + 12))
        return true
    }
}
