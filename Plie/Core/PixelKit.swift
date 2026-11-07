import SwiftUI
import CoreGraphics
import QuartzCore

// MARK: - Boîte à outils pixel (PÊCHE, MINIGOLF, COMÈTE)
//
// Comme CASCADE : chaque jeu dessine dans une petite image (quelques centaines de pixels),
// puis l'écran l'agrandit sans lissage. Les pixels restent nets et le dessin est très rapide.

/// Une petite image où l'on dessine au pixel près (origine en haut à gauche).
final class PixelCanvas {
    let cols: Int
    let rows: Int
    let ctx: CGContext

    init(cols: Int, rows: Int) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        ctx = CGContext(data: nil, width: self.cols, height: self.rows, bitsPerComponent: 8, bytesPerRow: self.cols * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: self.cols, height: self.rows))
        ctx.translateBy(x: 0, y: CGFloat(self.rows))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
    }

    func clear() { ctx.clear(CGRect(x: 0, y: 0, width: cols, height: rows)) }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: CGColor) {
        guard w > 0, h > 0 else { return }
        ctx.setFillColor(c)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func dot(_ x: Int, _ y: Int, _ c: CGColor) { fill(x, y, 1, 1, c) }

    /// Copie un sprite (le contexte est retourné, donc on redresse l'image).
    func blit(_ img: CGImage, x: Int, y: Int) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(x), y: CGFloat(y + img.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.restoreGState()
    }

    /// Sprite centré sur (x, y).
    func blitCentered(_ img: CGImage, x: Int, y: Int) { blit(img, x: x - img.width / 2, y: y - img.height / 2) }

    /// Ligne pixel (Bresenham).
    func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: CGColor, dotted: Int = 0) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        var k = 0
        ctx.setFillColor(c)
        for _ in 0...(dx - dy + 1) {
            if dotted == 0 || (k / dotted) % 2 == 0 { ctx.fill(CGRect(x: x, y: y, width: 1, height: 1)) }
            k += 1
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// Disque plein (rayon en pixels).
    func disc(_ cx: Int, _ cy: Int, _ r: Int, _ c: CGColor) {
        guard r > 0 else { dot(cx, cy, c); return }
        ctx.setFillColor(c)
        for dy in -r...r {
            let half = Int((sqrt(Double(r * r - dy * dy)) + 0.3).rounded(.down))
            ctx.fill(CGRect(x: cx - half, y: cy + dy, width: half * 2 + 1, height: 1))
        }
    }

    /// Petit texte 3×5 (chiffres, + et ×), avec une ombre.
    func tiny(_ s: String, x: Int, y: Int, _ c: CGColor) { TinyFont.draw(s, x: x, y: y, color: c, in: ctx) }

    func image() -> CGImage? { ctx.makeImage() }
}

enum PixelArt {
    /// Un sprite à partir de lignes de caractères : chaque caractère est une couleur de la palette,
    /// « . » (ou tout caractère absent de la palette) est transparent.
    static func sprite(_ rows: [String], _ palette: [Character: UInt32], flipX: Bool = false) -> CGImage {
        let h = rows.count
        let w = rows.map(\.count).max() ?? 1
        let c = PixelCanvas(cols: w, rows: h)
        for (y, line) in rows.enumerated() {
            for (x, ch) in line.enumerated() {
                guard let hex = palette[ch] else { continue }
                c.dot(flipX ? w - 1 - x : x, y, PX.c(hex))
            }
        }
        return c.image()!
    }

    /// Un sprite dessiné à la main dans un petit canevas.
    static func draw(_ w: Int, _ h: Int, _ body: (PixelCanvas) -> Void) -> CGImage {
        let c = PixelCanvas(cols: w, rows: h)
        body(c)
        return c.image()!
    }

    /// Mélange deux couleurs (t de 0 à 1).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let t = min(1, max(0, t))
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * (1 - t) + ch(b, s) * t).rounded()) << s }
        return m(16) | m(8) | m(0)
    }

    /// Hasard reproductible (le même décor à chaque fois).
    struct Seeded {
        var state: UInt64
        init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(max(1, n)))
        }
        mutating func unit() -> Double { Double(next(1_000_000)) / 1_000_000 }
    }
}

/// Affiche une image pixel agrandie, sans lissage.
struct PixelImage: View {
    let image: CGImage?
    var label: String = ""

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .accessibilityLabel(label)
        } else {
            Color(hex: 0x07040F)
        }
    }
}

/// La barre du haut des jeux pixel : retour, mode d'emploi, titre, et ce qu'on veut à droite.
struct PixelTopBar<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    let game: GameID
    var border: Color = Color(hex: 0xF2A33A)
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            PixelButton(fill: Color(hex: 0x2C1B5C)) {
                onBack()
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .black)).frame(width: 34, height: 34)
            }
            .accessibilityLabel(L("Retour"))
            HowToButton(game: game)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(PixelFont.font(13)).lineLimit(1).minimumScaleFactor(0.6)
                if !subtitle.isEmpty {
                    Text(subtitle).font(PixelFont.font(7)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(8)
        .pixelBox(fill: Color(hex: 0x120B26).opacity(0.92), border: border)
        .foregroundStyle(.white)
    }
}

/// Une jauge pixel (0 à 1), en petits blocs.
struct PixelGauge: View {
    let value: Double
    var color: Color
    var blocks = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<blocks, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < (value * Double(blocks)).rounded(.up) ? color : Color.white.opacity(0.12))
            }
        }
        .padding(2)
        .background(Rectangle().fill(Color(hex: 0x07040F)))
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int((value * 100).rounded())) %")
    }
}

/// Mémorise l'angle de la charnière et sa vitesse (degrés par seconde), lissée.
struct HingeTracker {
    private(set) var degrees: Double?
    private(set) var speed: Double = 0
    private var lastTime: CFTimeInterval = 0

    var hasHinge: Bool { degrees != nil }
    var isOpen: Bool { HingeMapping.isOpen(degrees) }

    mutating func update(_ value: Double?) {
        let now = CACurrentMediaTime()
        if let value, let old = degrees, lastTime > 0 {
            let dt = max(0.008, now - lastTime)
            let raw = (value - old) / dt
            speed = speed * 0.6 + raw * 0.4
        }
        degrees = value
        lastTime = now
    }

    /// La vitesse retombe quand la charnière ne bouge plus (appelé à chaque image).
    mutating func decay(_ dt: Double) {
        if CACurrentMediaTime() - lastTime > 0.12 { speed *= pow(0.02, dt) }
    }
}

/// Bouton pixel qu'on garde appuyé (mouliner, tirer…) : `held` est vrai tant que le doigt est dessus.
struct PixelHoldButton<Label: View>: View {
    var fill: Color
    var border: Color = Color(hex: 0x6E5BC4)
    @Binding var held: Bool
    @ViewBuilder var label: () -> Label

    var body: some View {
        label()
            .background(
                ZStack {
                    Rectangle().fill(fill)
                    Rectangle().strokeBorder(border, lineWidth: 3)
                    VStack { Rectangle().fill(.white.opacity(held ? 0 : 0.18)).frame(height: 3).padding(.horizontal, 3).padding(.top, 3); Spacer() }
                }
            )
            .offset(x: held ? 3 : 0, y: held ? 3 : 0)
            .background(Rectangle().fill(Color(hex: 0x07040F)).offset(x: 3, y: 3))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !held { held = true; Haptics.tap() } }
                    .onEnded { _ in held = false }
            )
            .accessibilityAddTraits(.isButton)
    }
}
