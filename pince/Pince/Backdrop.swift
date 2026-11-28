import UIKit

/// Les images peintes du décor : l'affiche du fond de la machine, les papiers peints, l'enseigne, les reflets des vitres.
/// Tout est dessiné au lancement, il n'y a aucun fichier d'image.
enum Backdrop {
    private static func canvas(_ w: CGFloat, _ h: CGFloat, opaque: Bool = true, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: w, height: h)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in draw(ctx.cgContext, size) }
    }

    private static func gradient(_ c: CGContext, _ colors: [UInt32], from a: CGPoint, to b: CGPoint) {
        let cg = colors.map { UIColor(hex: $0).cgColor } as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cg, locations: nil) else { return }
        c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func disc(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ hex: UInt32, _ alpha: CGFloat = 1) {
        c.setFillColor(UIColor(hex: hex, alpha: alpha).cgColor)
        c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private static func cloud(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-1.5, 0.15, 0.7), (-0.7, -0.35, 0.95), (0.3, -0.55, 1.1), (1.3, -0.1, 0.85), (0.2, 0.25, 0.9), (-0.8, 0.3, 0.75)]
        for (dx, dy, r) in puffs { disc(c, x + dx * s, y + dy * s + s * 0.16, r * s, 0xF4C6DE, 0.7) }
        for (dx, dy, r) in puffs { disc(c, x + dx * s, y + dy * s, r * s, 0xFFFFFF) }
    }

    /// Une étoile à quatre branches, comme un scintillement.
    private static func sparkle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ hex: UInt32 = 0xFFFFFF, _ alpha: CGFloat = 0.95) {
        let p = CGMutablePath()
        let k = r * 0.22
        p.move(to: CGPoint(x: x, y: y - r))
        p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + k, y: y - k))
        p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x + k, y: y + k))
        p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - k, y: y + k))
        p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x - k, y: y - k))
        c.addPath(p)
        c.setFillColor(UIColor(hex: hex, alpha: alpha).cgColor)
        c.fillPath()
    }

    private static func hill(_ c: CGContext, _ size: CGSize, base: CGFloat, bumps: [(CGFloat, CGFloat)], _ top: UInt32, _ bottom: UInt32) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -20, y: size.height + 20))
        p.addLine(to: CGPoint(x: -20, y: base))
        var x: CGFloat = -20
        for (w, h) in bumps {
            p.addQuadCurve(to: CGPoint(x: x + w, y: base), control: CGPoint(x: x + w / 2, y: base - h))
            x += w
        }
        p.addLine(to: CGPoint(x: size.width + 20, y: size.height + 20))
        p.closeSubpath()
        c.saveGState()
        c.addPath(p)
        c.clip()
        gradient(c, [top, bottom], from: CGPoint(x: 0, y: base - 160), to: CGPoint(x: 0, y: size.height))
        c.restoreGState()
    }

    /// L'affiche du fond : un coucher de soleil tout doux, un arc-en-ciel, des collines.
    static func poster() -> UIImage {
        canvas(1536, 992) { c, size in
            gradient(c, [0xA9A4F5, 0xD7B4F3, 0xFFC4DA, 0xFFE3BD], from: .zero, to: CGPoint(x: 0, y: size.height * 0.8))

            // Le soleil, ses halos et son visage endormi
            let sx: CGFloat = 1090, sy: CGFloat = 360
            disc(c, sx, sy, 250, 0xFFF3C4, 0.22)
            disc(c, sx, sy, 200, 0xFFF3C4, 0.3)
            disc(c, sx, sy, 150, 0xFFE89A)
            disc(c, sx - 62, sy + 34, 26, 0xFFB3A0, 0.8)
            disc(c, sx + 62, sy + 34, 26, 0xFFB3A0, 0.8)
            c.setStrokeColor(UIColor(hex: 0xB9773C).cgColor)
            c.setLineWidth(9)
            c.setLineCap(.round)
            for dx in [CGFloat(-52), 52] {
                c.addArc(center: CGPoint(x: sx + dx, y: sy - 6), radius: 20, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                c.strokePath()
            }
            c.addArc(center: CGPoint(x: sx, y: sy + 26), radius: 16, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
            c.strokePath()

            // L'arc-en-ciel
            let bands: [UInt32] = [0xFF9DB5, 0xFFC78A, 0xFFE89A, 0xA8E6CF, 0x9AD4F5, 0xC9B6F2]
            for (i, hex) in bands.enumerated() {
                c.setStrokeColor(UIColor(hex: hex, alpha: 0.92).cgColor)
                c.setLineWidth(30)
                c.addArc(center: CGPoint(x: 470, y: 800), radius: 470 - CGFloat(i) * 30, startAngle: .pi, endAngle: 0, clockwise: false)
                c.strokePath()
            }

            cloud(c, 230, 190, 62)
            cloud(c, 1370, 140, 46)
            cloud(c, 760, 110, 38)

            let stars: [(CGFloat, CGFloat, CGFloat)] = [(90, 90, 22), (480, 170, 14), (930, 70, 18), (1420, 320, 16), (800, 290, 12),
                                                         (60, 400, 13), (1180, 60, 11), (640, 400, 10), (1480, 90, 13), (360, 60, 10)]
            for (x, y, r) in stars { sparkle(c, x, y, r) }

            hill(c, size, base: 720, bumps: [(520, 220), (540, 150), (540, 240)], 0xC9E9D0, 0xA8DDBE)
            hill(c, size, base: 820, bumps: [(440, 150), (620, 220), (540, 130)], 0xA9E0B4, 0x86CFA0)
            hill(c, size, base: 920, bumps: [(660, 170), (480, 110), (460, 190)], 0x8FD49C, 0x6FC088)
            cloud(c, 190, 720, 40)
            cloud(c, 1380, 690, 34)

            // Des fleurs sur les collines
            let flowers: [(CGFloat, CGFloat, UInt32)] = [(160, 880, 0xFFFFFF), (420, 930, 0xFFE89A), (760, 870, 0xFFB7CB), (1040, 940, 0xFFFFFF),
                                                         (1320, 860, 0xFFE89A), (1450, 950, 0xFFB7CB), (620, 960, 0xFFFFFF), (930, 810, 0xFFE89A)]
            for (x, y, hex) in flowers {
                for i in 0..<5 {
                    let a = CGFloat(i) * 2 * .pi / 5
                    disc(c, x + cos(a) * 9, y + sin(a) * 9, 7, hex)
                }
                disc(c, x, y, 5, 0xFFB14A)
            }
        }
    }

    /// Combien de points d'image pour une unité de la scène, sur le décor du pupitre.
    static let panelScale: CGFloat = 512

    /// La face avant de la machine, autour des commandes : claire et sobre, avec le ruban arc-en-ciel de la maison.
    /// `width` et `height` sont en unités de la scène.
    static func panelArt(width: CGFloat, height: CGFloat) -> UIImage {
        canvas(width * panelScale, height * panelScale) { c, size in
            gradient(c, [0xFFFDF8, 0xFFF6EE, 0xFFEFE8], from: .zero, to: CGPoint(x: 0, y: size.height))

            // Le ruban arc-en-ciel, tout en haut, sous la vitre
            let bands: [UInt32] = [0xFF9DB5, 0xFFC78A, 0xFFE89A, 0xA8E6CF, 0x9AD4F5, 0xC9B6F2]
            for (i, hex) in bands.enumerated() {
                c.setFillColor(UIColor(hex: hex).cgColor)
                c.fill(CGRect(x: 0, y: 22 + CGFloat(i) * 9, width: size.width, height: 9))
            }

            // Une ombre légère sur les bords : la face avant paraît bombée
            let edge = [UIColor(hex: 0xE7B8C6, alpha: 0.55).cgColor, UIColor(hex: 0xE7B8C6, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: edge, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 70, y: 0), options: [])
                c.drawLinearGradient(g, start: CGPoint(x: size.width, y: 0), end: CGPoint(x: size.width - 70, y: 0), options: [])
            }
        }
    }

    /// Un morceau de cette image (en points d'image, depuis le coin haut gauche).
    static func piece(of image: UIImage, _ rect: CGRect) -> UIImage {
        guard let cut = image.cgImage?.cropping(to: rect.integral) else { return image }
        return UIImage(cgImage: cut)
    }

    /// Papier peint à pois pour les machines voisines.
    static func dots(_ base: UInt32, _ dot: UInt32) -> UIImage {
        canvas(512, 512) { c, size in
            c.setFillColor(UIColor(hex: base).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            for row in 0..<8 {
                for col in 0..<8 {
                    let x = CGFloat(col) * 64 + (row % 2 == 0 ? 16 : 48)
                    disc(c, x, CGFloat(row) * 64 + 32, 10, dot, 0.9)
                }
            }
        }
    }

    /// Le mur de la salle : de larges rayures.
    static func stripes(_ a: UInt32, _ b: UInt32) -> UIImage {
        canvas(256, 64) { c, size in
            c.setFillColor(UIColor(hex: a).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(hex: b).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        }
    }

    /// L'enseigne au-dessus de la machine.
    static func marquee(_ title: String) -> UIImage {
        canvas(1050, 320) { c, size in
            gradient(c, [Tint.coral, Tint.rose], from: .zero, to: CGPoint(x: 0, y: size.height))
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 26, dy: 26)
            c.setStrokeColor(UIColor(hex: Tint.cream).cgColor)
            c.setLineWidth(10)
            c.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 60).cgPath)
            c.strokePath()
            // Les ampoules
            let bulbs = 22
            for i in 0..<bulbs {
                let x = 70 + CGFloat(i) * (size.width - 140) / CGFloat(bulbs - 1)
                for y in [CGFloat(26), size.height - 26] {
                    disc(c, x, y, 13, 0xFFFFFF, 0.5)
                    disc(c, x, y, 9, i % 2 == 0 ? Tint.butter : 0xFFFFFF)
                }
            }
            // Le titre prend toute la largeur disponible, quelle que soit la langue.
            func rounded(_ points: CGFloat) -> UIFont {
                let base = UIFont.systemFont(ofSize: points, weight: .black)
                return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: points) } ?? base
            }
            var points: CGFloat = 132
            while points > 60, (title as NSString).size(withAttributes: [.font: rounded(points), .kern: 3]).width > size.width - 150 {
                points -= 4
            }
            let font = rounded(points)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let box = CGRect(x: 0, y: (size.height - font.lineHeight) / 2 - 4, width: size.width, height: font.lineHeight)
            let shadow: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: UIColor(hex: Tint.plum, alpha: 0.55), .kern: 3]
            (title as NSString).draw(in: box.offsetBy(dx: 0, dy: 9), withAttributes: shadow)
            let face: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: UIColor(hex: Tint.paper), .kern: 3]
            (title as NSString).draw(in: box, withAttributes: face)
        }
    }

    /// Des reflets en biais, pour que les vitres se voient.
    static func glare() -> UIImage {
        canvas(512, 512, opaque: false) { c, size in
            c.setFillColor(UIColor(white: 1, alpha: 0.07).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            for (x, w, alpha) in [(CGFloat(60), CGFloat(70), CGFloat(0.2)), (170, 24, 0.14), (360, 46, 0.12)] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x + 220, y: -10))
                p.addLine(to: CGPoint(x: x + 220 + w, y: -10))
                p.addLine(to: CGPoint(x: x + w - 120, y: size.height + 10))
                p.addLine(to: CGPoint(x: x - 120, y: size.height + 10))
                p.closeSubpath()
                c.addPath(p)
                c.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                c.fillPath()
            }
        }
    }

    /// Une paillette : une étoile blanche à quatre branches, que la scène teinte à sa guise.
    static func glitter() -> UIImage {
        canvas(64, 64, opaque: false) { c, _ in
            disc(c, 32, 32, 20, 0xFFFFFF, 0.25)
            sparkle(c, 32, 32, 30, 0xFFFFFF, 1)
            disc(c, 32, 32, 7, 0xFFFFFF, 1)
        }
    }

    /// Une ombre ronde et floue, posée sous les doudous du décor.
    static func blob() -> UIImage {
        canvas(128, 128, opaque: false) { c, size in
            let tint = UIColor(red: 0.22, green: 0.12, blue: 0.38, alpha: 1)
            let colors = [tint.withAlphaComponent(0.5).cgColor, tint.withAlphaComponent(0.36).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) else { return }
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
        }
    }
}
