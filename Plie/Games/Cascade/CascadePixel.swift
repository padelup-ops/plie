import SwiftUI
import CoreGraphics
import CoreText

// MARK: - CASCADE en pixel art
//
// Tout est dessiné dans une petite image (192 pixels de large), puis agrandie sans lissage :
// des pixels nets, et un dessin très rapide (des petits sprites copiés, pas de dégradés).

enum PixelFont {
    static let name = "PressStart2P-Regular"
    private static var registered = false

    /// La police pixel (Press Start 2P, licence OFL) est chargée une fois, sans passer par Info.plist.
    static func register() {
        guard !registered else { return }
        registered = true
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(_ size: CGFloat) -> Font {
        register()
        return .custom(name, fixedSize: size)
    }
}

/// Couleurs de la machine (palette limitée, comme une vieille borne d'arcade).
enum PX {
    static func c(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static let night = c(0x1A1033), night2 = c(0x241547), star = c(0x6E5BC4), star2 = c(0xB9A8FF)
    static let rail = c(0xF2A33A), railDark = c(0x9C4F1C), railLight = c(0xFFD37A)
    static let peg = c(0xCFE3FF), pegShadow = c(0x0D0820)
    static let felt = c(0x0E5560), felt2 = c(0x0B4650), felt3 = c(0x13707C)
    static let wall = c(0x7A3A16), void = c(0x07040F), hole = c(0x03020A)
    static let metal = c(0xAEB8D0), metal2 = c(0x7D88A6), metal3 = c(0xE6ECF8), metalDark = c(0x4A5370)
    static let gold = c(0xFFC93C), gold2 = c(0xE8941A), goldDark = c(0x8A4B0C), goldLight = c(0xFFF2A8)
    static let silver = c(0xE9EDF7), silver2 = c(0xA9B2C8), silverDark = c(0x5A6380), silverLight = c(0xFFFFFF)
    static let gem = c(0xFF7BEA), gem2 = c(0x9B4DFF), gemDark = c(0x4A1C8C), gemLight = c(0xFFE0FA)
    static let pink = c(0xFF4FD8), pinkDark = c(0x8C1C78)
    static let white = c(0xFFFFFF), yellow = c(0xFFE066)
}

/// Petite police 3×5 dessinée à la main, pour les gains qui s'envolent (+12K, ×4…).
enum TinyFont {
    static let glyphs: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "011", "001", "111"],
        "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
        "+": ["000", "010", "111", "010", "000"], ".": ["000", "000", "000", "000", "010"],
        "×": ["000", "101", "010", "101", "000"], "K": ["101", "110", "100", "110", "101"],
        "M": ["101", "111", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
        "T": ["111", "010", "010", "010", "010"], "Q": ["111", "101", "101", "111", "001"],
        "a": ["000", "110", "011", "101", "111"], "i": ["010", "000", "010", "010", "010"],
    ]

    static func width(_ s: String) -> Int { max(0, s.count * 4 - 1) }

    /// Dessine le texte (coin haut gauche en x, y), avec une ombre d'un pixel.
    static func draw(_ s: String, x: Int, y: Int, color: CGColor, in ctx: CGContext) {
        for (pass, col) in [(1, PX.void), (0, color)] {
            ctx.setFillColor(col)
            var cx = x
            for ch in s {
                if let g = glyphs[ch] {
                    for (row, line) in g.enumerated() {
                        for (k, bit) in line.enumerated() where bit == "1" {
                            ctx.fill(CGRect(x: cx + k + pass, y: y + row + pass, width: 1, height: 1))
                        }
                    }
                }
                cx += 4
            }
        }
    }
}

/// Les sprites (dessinés une fois, au pixel près).
final class PixelSprites {
    /// Pièce qui tombe, vue de face, 4 étapes de rotation (11 px de haut).
    private(set) var spin: [CascadeCoin.Kind: [CGImage]] = [:]
    /// Pièce couchée sur le plateau, en 3 tailles (loin, milieu, près).
    private(set) var flat: [CascadeCoin.Kind: [CGImage]] = [:]

    init() {
        for k in [CascadeCoin.Kind.silver, .gold, .gem] {
            spin[k] = [11, 8, 5, 2].map { w in Self.face(k, width: w) }
            flat[k] = [5, 7, 9].map { w in Self.lying(k, width: w) }
        }
    }

    private static func colors(_ k: CascadeCoin.Kind) -> (CGColor, CGColor, CGColor, CGColor) {
        switch k {
        case .gold: return (PX.gold, PX.gold2, PX.goldDark, PX.goldLight)
        case .silver: return (PX.silver, PX.silver2, PX.silverDark, PX.silverLight)
        case .gem: return (PX.gem, PX.gem2, PX.gemDark, PX.gemLight)
        }
    }

    private static func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        draw(ctx)
        return ctx.makeImage()!
    }

    /// Disque pixel : pour chaque ligne, la largeur occupée.
    private static func disc(_ w: Int, _ h: Int, _ y: Int) -> (Int, Int) {
        let cy = Double(h - 1) / 2, ry = Double(h) / 2, rx = Double(w) / 2
        let t = (Double(y) - cy) / ry
        let half = rx * sqrt(max(0, 1 - t * t))
        let a = Int((Double(w) / 2 - half).rounded()), b = Int((Double(w) / 2 + half).rounded())
        return (a, max(a, b))
    }

    static func face(_ k: CascadeCoin.Kind, width w: Int) -> CGImage {
        let h = 11
        let (fill, mid, dark, light) = colors(k)
        if k == .gem {
            return image(11, h) { ctx in
                let ww = max(1, w)
                let x0 = (11 - ww) / 2
                for y in 0..<h {
                    let t = 1 - abs(Double(y) - 5) / 5.5
                    let rw = max(1, Int((Double(ww) * t).rounded()))
                    let xs = x0 + (ww - rw) / 2
                    ctx.setFillColor(y < 4 ? light : (y < 7 ? fill : mid)); ctx.fill(CGRect(x: xs, y: y, width: rw, height: 1))
                    ctx.setFillColor(dark); ctx.fill(CGRect(x: xs, y: y, width: 1, height: 1)); ctx.fill(CGRect(x: xs + rw - 1, y: y, width: 1, height: 1))
                }
            }
        }
        return image(11, h) { ctx in
            let x0 = (11 - w) / 2
            for y in 0..<h {
                let (a, b) = disc(w, h, y)
                guard b > a else { continue }
                ctx.setFillColor(y < h / 2 ? fill : mid)
                ctx.fill(CGRect(x: x0 + a, y: y, width: b - a, height: 1))
                ctx.setFillColor(dark)
                ctx.fill(CGRect(x: x0 + a, y: y, width: 1, height: 1))
                ctx.fill(CGRect(x: x0 + b - 1, y: y, width: 1, height: 1))
            }
            ctx.setFillColor(dark)
            let (a0, b0) = disc(w, h, 0); ctx.fill(CGRect(x: x0 + a0, y: 0, width: b0 - a0, height: 1))
            let (a1, b1) = disc(w, h, h - 1); ctx.fill(CGRect(x: x0 + a1, y: h - 1, width: b1 - a1, height: 1))
            if w >= 5 {
                ctx.setFillColor(light)
                ctx.fill(CGRect(x: x0 + w / 2 - 2, y: 2, width: 2, height: 1))
                ctx.fill(CGRect(x: x0 + w / 2 - 3, y: 3, width: 1, height: 2))
                // Le motif au centre
                ctx.setFillColor(mid); ctx.fill(CGRect(x: x0 + w / 2 - 1, y: 4, width: 2, height: 3))
            }
        }
    }

    static func lying(_ k: CascadeCoin.Kind, width w: Int) -> CGImage {
        let h = max(3, Int((Double(w) * 0.6).rounded()))
        let edge = max(1, w / 4)
        let (fill, mid, dark, light) = colors(k)
        return image(w, h + edge) { ctx in
            if k == .gem {
                let cx = w / 2
                for y in 0..<(h + edge) {
                    let t = 1 - abs(Double(y) - Double(h + edge - 1) / 2) / (Double(h + edge) / 2)
                    let rw = max(1, Int((Double(w) * t).rounded()))
                    ctx.setFillColor(y < (h + edge) / 2 ? light : fill); ctx.fill(CGRect(x: cx - rw / 2, y: y, width: rw, height: 1))
                }
                ctx.setFillColor(dark); ctx.fill(CGRect(x: cx - 1, y: h + edge - 1, width: 2, height: 1))
                return
            }
            // Tranche (l'épaisseur de la pièce), puis le dessus
            for y in 0..<h {
                let (a, b) = disc(w, h, y)
                ctx.setFillColor(dark); ctx.fill(CGRect(x: a, y: y + edge, width: b - a, height: 1))
            }
            for y in 0..<h {
                let (a, b) = disc(w, h, y)
                ctx.setFillColor(y == 0 ? light : (y < h / 2 ? fill : mid))
                ctx.fill(CGRect(x: a, y: y, width: b - a, height: 1))
            }
            if w >= 7 { ctx.setFillColor(light); ctx.fill(CGRect(x: w / 2 - 2, y: 1, width: 2, height: 1)) }
            ctx.setFillColor(mid); ctx.fill(CGRect(x: 0, y: h / 2, width: 1, height: 1)); ctx.fill(CGRect(x: w - 1, y: h / 2, width: 1, height: 1))
        }
    }
}

/// Dessine la machine dans une image de `cols` pixels de large.
final class CascadeRenderer {
    let cols = 192
    private(set) var rows = 0
    private var ctx: CGContext?
    private var background: CGImage?
    private var bgKey = ""
    private let sprites = PixelSprites()

    /// Taille d'un pixel de jeu, en unités du terrain (largeur 1).
    var unit: Double { 1 / Double(cols) }

    func render(_ game: CascadeGame) -> CGImage? {
        let r = max(64, Int((game.height * Double(cols)).rounded()))
        if r != rows || ctx == nil {
            rows = r
            ctx = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.translateBy(x: 0, y: CGFloat(rows)); ctx?.scaleBy(x: 1, y: -1)
            ctx?.setShouldAntialias(false)
            ctx?.interpolationQuality = .none
            background = nil
        }
        guard let ctx else { return nil }
        let key = "\(rows)-\(game.edgeFraction)-\(game.pegs.count)"
        if background == nil || key != bgKey { background = makeBackground(game); bgKey = key }

        // Secousse : toute l'image tremble de quelques pixels.
        ctx.saveGState()
        if game.shakeTime > 0 {
            let a = Int((game.shakeTime * 8).rounded())
            ctx.translateBy(x: CGFloat(Int.random(in: -a...a)), y: CGFloat(Int.random(in: -a / 2...a / 2)))
        }
        if let bg = background { blit(bg, x: 0, y: 0, in: ctx) }

        let half = Int((game.half * Double(cols)).rounded())
        let edgeY = Int((game.bedEdge * Double(cols)).rounded())

        // La trémie (en haut) et la cible rose
        let dx = px(game.dropperX), dy = px(game.half * 0.1)
        fill(ctx, dx - 9, dy - 3, 18, 5, PX.railDark)
        fill(ctx, dx - 8, dy - 3, 16, 3, PX.rail)
        fill(ctx, dx - 8, dy - 3, 16, 1, PX.railLight)
        fill(ctx, dx - 2, dy + 2, 4, 2, PX.railDark)
        let gx = px(game.gateX), gy = px(game.half * 0.92)
        let blink = Int(game.time * 6) % 2 == 0
        fill(ctx, gx - 13, gy - 1, 27, 3, blink ? PX.pink : PX.pinkDark)
        fill(ctx, gx - 13, gy - 1, 1, 3, PX.white); fill(ctx, gx + 13, gy - 1, 1, 3, PX.white)
        TinyFont.draw("×4", x: gx - 3, y: gy - 8, color: PX.white, in: ctx)

        // Le plateau en perspective : y du terrain -> ligne d'écran, et largeur qui s'élargit vers l'avant.
        let span = max(0.0001, game.bedEdge - game.bedTop)
        func depth(_ y: Double) -> Double { min(1.05, max(0, (y - game.bedTop) / span)) }
        func scale(_ t: Double) -> Double { 0.64 + 0.36 * t }
        func bedX(_ x: Double, _ t: Double) -> Int { px(0.5 + (x - 0.5) * scale(t)) }
        func bedY(_ t: Double) -> Int { half + Int((Double(edgeY - half) * t).rounded()) }

        // Le poussoir : une plaque métallique qui avance
        let pt = depth(game.pusherFront)
        let py = bedY(pt)
        let inner = 0.5 - CascadeGame.wall
        for y in half..<max(half, py) {
            let t = Double(y - half) / Double(max(1, edgeY - half))
            let xa = bedX(0.5 - inner, t), xb = bedX(0.5 + inner, t)
            fill(ctx, xa, y, xb - xa, 1, (y - half) % 6 == 0 ? PX.metal2 : PX.metal)
        }
        let pxa = bedX(0.5 - inner, pt), pxb = bedX(0.5 + inner, pt)
        fill(ctx, pxa, py - 1, pxb - pxa, 1, PX.metal3)
        fill(ctx, pxa, py, pxb - pxa, 2, PX.metalDark)

        // Les pièces couchées, du fond vers l'avant (celles de devant passent par-dessus)
        let bed = game.bed.sorted { $0.y < $1.y }
        for c in bed {
            let t = depth(c.y)
            guard let set = sprites.flat[c.kind] else { continue }
            let img = set[t < 0.33 ? 0 : (t < 0.7 ? 1 : 2)]
            let x = bedX(c.x, t) - img.width / 2, y = bedY(t) - img.height / 2
            blit(img, x: x, y: y, in: ctx)
        }

        // Les pièces qui tombent (elles tournent)
        for c in game.falling {
            guard let set = sprites.spin[c.kind] else { continue }
            let f = Int(c.spin * 2) % 6
            let img = set[[0, 1, 2, 3, 2, 1][f]]
            blit(img, x: px(c.x) - 5, y: px(c.y) - 5, in: ctx)
        }

        // Les gains qui s'envolent
        for p in game.pops {
            let onBed = p.y >= game.bedTop
            let x = onBed ? bedX(p.x, depth(p.y)) : px(p.x)
            let y = onBed ? bedY(depth(p.y)) - 6 - Int((0.8 - p.life) * 14) : px(p.y)
            TinyFont.draw(p.text, x: x - TinyFont.width(p.text) / 2, y: y, color: p.gold ? PX.yellow : PX.white, in: ctx)
        }

        // La CASCADE : le cadre clignote
        if game.frenzy > 0 && Int(game.time * 8) % 2 == 0 {
            ctx.setStrokeColor(PX.gem); ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: 0.5, y: 0.5, width: CGFloat(cols - 1), height: CGFloat(rows - 1)))
            ctx.stroke(CGRect(x: 1.5, y: 1.5, width: CGFloat(cols - 3), height: CGFloat(rows - 3)))
        }
        ctx.restoreGState()
        return ctx.makeImage()
    }

    private func px(_ v: Double) -> Int { Int((v * Double(cols)).rounded()) }

    private func fill(_ ctx: CGContext, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: CGColor) {
        guard w > 0, h > 0 else { return }
        ctx.setFillColor(c)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Copie un sprite au pixel près (le contexte est retourné, donc on redresse l'image).
    private func blit(_ img: CGImage, x: Int, y: Int, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(x), y: CGFloat(y + img.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.restoreGState()
    }

    /// Le décor fixe : ciel étoilé, rails, clous, plateau, vide devant.
    private func makeBackground(_ game: CascadeGame) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(rows)); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        let half = Int((game.half * Double(cols)).rounded())
        let edgeY = Int((game.bedEdge * Double(cols)).rounded())
        let wall = Int((CascadeGame.wall * Double(cols)).rounded())

        // Le ciel (moitié debout) : un fond calme en trois bandes, une transition tramée, quelques étoiles
        let bands = [PX.night, PX.night2, PX.c(0x2E1A57)]
        for (k, col) in bands.enumerated() {
            let y0 = half * k / 3, y1 = half * (k + 1) / 3
            fill(ctx, 0, y0, cols, y1 - y0, col)
            if k > 0 {
                // trame d'une ligne sur deux entre deux bandes
                for x in stride(from: (y0 % 2), to: cols, by: 2) { fill(ctx, x, y0, 1, 1, bands[k - 1]) }
            }
        }
        var seed: UInt64 = 7
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(1, n))) }
        for _ in 0..<22 { fill(ctx, wall + 2 + rnd(cols - 2 * wall - 4), 2 + rnd(half / 2), 1, 1, rnd(3) == 0 ? PX.star2 : PX.star) }

        // Les rails sur les côtés (briques dorées)
        for x in [0, cols - wall] {
            fill(ctx, x, 0, wall, half, PX.rail)
            for y in stride(from: 0, to: half, by: 6) {
                fill(ctx, x, y, wall, 1, PX.railDark)
                fill(ctx, x + ((y / 6) % 2 == 0 ? wall / 2 : 1), y, 1, 6, PX.railDark)
            }
            fill(ctx, x == 0 ? wall - 1 : x, 0, 1, half, PX.railLight)
        }

        // Les clous : une tête claire, une ombre
        for p in game.pegs {
            let x = Int((p.x * Double(cols)).rounded()), y = Int((p.y * Double(cols)).rounded())
            fill(ctx, x - 1, y, 3, 2, PX.pegShadow)
            fill(ctx, x - 1, y - 1, 2, 2, PX.peg)
            fill(ctx, x - 1, y - 1, 1, 1, PX.white)
        }

        // La charnière : une ligne sombre
        fill(ctx, 0, half - 1, cols, 2, PX.void)

        // Le plateau (trapèze), en damier de feutre
        let inner = 0.5 - CascadeGame.wall
        for y in half..<edgeY {
            let t = Double(y - half) / Double(max(1, edgeY - half))
            let sc = 0.64 + 0.36 * t
            let xa = Int(((0.5 - inner * sc) * Double(cols)).rounded()), xb = Int(((0.5 + inner * sc) * Double(cols)).rounded())
            fill(ctx, 0, y, xa, 1, PX.wall)
            fill(ctx, xb, y, cols - xb, 1, PX.wall)
            fill(ctx, xa - 1, y, 1, 1, PX.railLight); fill(ctx, xb, y, 1, 1, PX.railLight)
            for x in xa..<xb {
                let lane = Int(Double(x - xa) / Double(max(1, xb - xa)) * 8)
                fill(ctx, x, y, 1, 1, (x + y) % 2 == 0 ? (lane % 2 == 0 ? PX.felt : PX.felt2) : PX.felt2)
            }
            if (y - half) % 9 == 0 { fill(ctx, xa, y, xb - xa, 1, PX.felt3) }
        }
        // Les trous des côtés, près du bord avant (là, les pièces sont perdues)
        let ha = Int(((0.5 - inner) * Double(cols)).rounded()), hb = Int(((0.5 + inner) * Double(cols)).rounded())
        let holeW = Int((0.09 * Double(cols)).rounded())
        for (x0, w0) in [(ha, holeW), (hb - holeW, holeW)] {
            fill(ctx, x0, edgeY - 6, w0, 6, PX.c(0x062A30))
            fill(ctx, x0, edgeY - 6, w0, 1, PX.c(0x03181C))
        }
        // Le bord avant, puis le vide
        fill(ctx, 0, edgeY, cols, rows - edgeY, PX.void)
        fill(ctx, ha, edgeY, hb - ha, 2, PX.rail)
        fill(ctx, ha, edgeY + 2, hb - ha, 1, PX.railDark)
        return ctx.makeImage()
    }
}
