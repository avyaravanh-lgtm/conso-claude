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

    func serif(_ size: CGFloat, _ weight: NSFont.Weight, italic: Bool) -> NSFont {
        var desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)
        if italic { desc = desc?.withSymbolicTraits(.italic) }
        return desc.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    // Le héros : le pourcentage restant, gros serif coloré.
    let numberStr = NSAttributedString(string: "\(remaining) %", attributes: [
        .font: serif(27, .semibold, italic: false),
        .foregroundColor: accent,
    ])
    let captionStr = NSAttributedString(string: "restants · \(context)".uppercased(), attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .kern: 1.6,
        .foregroundColor: ink.withAlphaComponent(0.5),
    ])
    let phraseStr = NSAttributedString(string: phrase, attributes: [
        .font: serif(14, .regular, italic: true),
        .foregroundColor: ink.withAlphaComponent(0.85),
    ])
    let markStr = NSAttributedString(string: "✳", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: accent,
    ])

    let numberSize = numberStr.size()
    let captionSize = captionStr.size()
    let phraseSize = phraseStr.size()
    let markSize = markStr.size()

    let markCol = markSize.width + 14
    let line1W = numberSize.width + 10 + captionSize.width
    let textW = max(line1W, phraseSize.width)
    let cardW = 20 + markCol + textW + 22
    let cardH: CGFloat = 74
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

        ink.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        markStr.draw(at: NSPoint(x: cardX + 18, y: margin + (cardH - markSize.height) / 2))

        let xText = cardX + 20 + markCol
        let numberY = margin + cardH - numberSize.height - 8
        numberStr.draw(at: NSPoint(x: xText, y: numberY))
        captionStr.draw(at: NSPoint(x: xText + numberSize.width + 10, y: numberY + 9))
        phraseStr.draw(at: NSPoint(x: xText, y: margin + 10))
        return true
    }
}
