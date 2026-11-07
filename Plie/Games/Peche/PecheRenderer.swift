import SwiftUI
import CoreGraphics

// MARK: - Le dessin de PÊCHE

enum FishArt {
    /// Le sprite d'un poisson tourné vers la droite (ou sa silhouette, pour le carnet).
    static func sprite(_ s: FishSpecies, silhouette: Bool = false, flip: Bool = false) -> CGImage {
        let shadow: UInt32 = 0x2A2350
        let body = silhouette ? shadow : s.body
        let belly = silhouette ? shadow : s.belly
        let fin = silhouette ? shadow : s.fin
        let eye: UInt32 = silhouette ? shadow : 0x07040F

        switch s.shape {
        case .boot:
            return PixelArt.sprite([
                "..bbbb..",
                "..bBbb..",
                "..bbbb..",
                "..bbbbb.",
                ".bbbbbbb",
                "bbbbbbbb",
                "ssssssss",
            ], ["b": body, "B": belly, "s": fin], flipX: flip)
        case .chest:
            return PixelArt.sprite([
                ".ssssssss.",
                "sbbbbbbbbs",
                "sBBBBBBBBs",
                "ssssyyssss",
                "sbbbyybbbs",
                "sbbbbbbbbs",
                "ssssssssss",
            ], ["b": body, "B": silhouette ? shadow : PixelArt.mix(s.body, 0xFFFFFF, 0.25), "s": fin, "y": belly], flipX: flip)
        case .ray:
            let w = s.length + 5, h = s.height
            return PixelArt.draw(w, h) { c in
                let cx = 5 + s.length / 2, cy = h / 2
                for y in 0..<h {
                    let t = 1 - abs(Double(y - cy)) / Double(cy + 1)
                    let half = Int((Double(s.length / 2) * t).rounded())
                    c.fill(cx - half, y, half * 2 + 1, 1, PX.c(y < cy ? body : belly))
                }
                c.fill(0, cy, 5, 1, PX.c(fin))
                c.dot(cx + 2, cy - 1, PX.c(eye))
                c.dot(cx + 2, cy + 1, PX.c(eye))
            }.flippedIfNeeded(flip)
        default:
            break
        }

        let tail = 3
        let nose = s.shape == .sword ? 5 : 0
        let top = s.shape == .shark ? 3 : (s.shape == .lantern ? 4 : 1)
        let L = s.length, H = s.height
        let w = tail + L + nose, h = H + top + 1
        let image = PixelArt.draw(w, h) { c in
            let cy = Double(top) + Double(H - 1) / 2
            let cx = Double(tail) + Double(L - 1) / 2
            let rx = Double(L) / 2, ry = Double(H) / 2
            // La queue
            for k in 0..<tail {
                let span = Double(tail - k) + (s.shape == .shark ? 1 : 0)
                let y0 = Int((cy - span).rounded()), y1 = Int((cy + span).rounded())
                c.fill(k, y0, 1, y1 - y0 + 1, PX.c(fin))
            }
            // Le corps (ovale), le ventre plus clair en bas
            for x in tail..<(tail + L) {
                let t = (Double(x) - cx) / rx
                let hh = ry * sqrt(max(0, 1 - t * t)) + (s.shape == .round ? 0.4 : 0.15)
                let y0 = Int((cy - hh).rounded()), y1 = Int((cy + hh).rounded())
                guard y1 >= y0 else { continue }
                for y in y0...y1 {
                    let below = Double(y) > cy + ry * 0.2
                    var col = below ? belly : body
                    if s.shape == .stripes && !below && (x % 3 == 0) { col = fin }
                    if s.shape == .clown {
                        let a = tail + L / 3, b = tail + 2 * L / 3
                        if x == a || x == b { col = silhouette ? shadow : 0xFFFFFF }
                        if x == a - 1 || x == b + 1 { col = fin }
                    }
                    c.dot(x, y, PX.c(col))
                }
                // Une ombre sous le ventre
                c.dot(x, y1, PX.c(silhouette ? shadow : PixelArt.mix(belly, 0x07040F, 0.35)))
            }
            // Nageoire du dessus
            let mid = Int(cx.rounded())
            if s.shape == .shark {
                for k in 0..<3 { c.fill(mid - 1 + k, top - 3 + (2 - k), 1, 3 - (2 - k) + 1, PX.c(fin)) }
            } else if s.shape != .round {
                c.fill(mid - 1, top - 1, 3, 1, PX.c(fin))
            } else {
                c.fill(mid - 1, top - 1, 2, 1, PX.c(fin))
                c.fill(mid - 1, top + H, 2, 1, PX.c(fin))
            }
            // L'œil et la bouche
            let ex = tail + L - 3
            let ey = Int((cy - Double(H) / 4).rounded())
            if H >= 5 && !silhouette { c.dot(ex - 1, ey, PX.c(0xFFFFFF)) }
            c.dot(ex, ey, PX.c(eye))
            c.dot(tail + L - 1, Int((cy + 0.6).rounded()), PX.c(silhouette ? shadow : PixelArt.mix(body, 0x07040F, 0.5)))
            // L'épée de l'espadon
            if nose > 0 { c.fill(tail + L, Int(cy.rounded()) - 1, nose, 1, PX.c(fin)) }
            // La lumière du poisson-lanterne
            if s.shape == .lantern {
                c.fill(ex, 1, 1, top - 1, PX.c(fin))
                c.fill(ex + 1, 0, 2, 2, PX.c(silhouette ? shadow : 0x9CFF6B))
            }
            // Les reflets du poisson doré
            if s.shape == .gold && !silhouette {
                c.dot(tail + 3, top + 1, PX.c(0xFFFFFF))
                c.dot(tail + 5, top + 2, PX.c(0xFFFFFF))
            }
        }
        return image.flippedIfNeeded(flip)
    }

}

extension CGImage {
    /// Le même sprite, retourné de gauche à droite.
    func flippedIfNeeded(_ flip: Bool) -> CGImage {
        guard flip else { return self }
        let c = PixelCanvas(cols: width, rows: height)
        c.ctx.saveGState()
        c.ctx.translateBy(x: CGFloat(width), y: CGFloat(height))
        c.ctx.scaleBy(x: -1, y: -1)
        c.ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        c.ctx.restoreGState()
        return c.image() ?? self
    }
}

final class PecheRenderer {
    private var canvas: PixelCanvas?
    private var background: CGImage?
    private var bgKey = ""
    private var right: [CGImage] = []
    private var left: [CGImage] = []
    private let boat: CGImage
    private let fisher: CGImage

    init() {
        right = FishSpecies.all.map { FishArt.sprite($0) }
        left = FishSpecies.all.map { FishArt.sprite($0, flip: true) }
        boat = PixelArt.sprite([
            "..wwwwwwwwwwwwwwwwwwwwwwww..",
            "hhhhhhhhhhhhhhhhhhhhhhhhhhhh",
            ".HHHHHHHHHHHHHHHHHHHHHHHHHH.",
            ".hhhhhhhhhhhhhhhhhhhhhhhhhh.",
            "..HHHHHHHHHHHHHHHHHHHHHHHH..",
            "...dddddddddddddddddddddd...",
        ], ["w": 0xE8D2A8, "h": 0xA8582E, "H": 0xC9703C, "d": 0x6E3418])
        fisher = PixelArt.sprite([
            ".yyyy.",
            "yyyyyy",
            ".ffff.",
            ".fkfk.",
            ".ffff.",
            "rrrrrr",
            "rrrrrr",
            "rRrrRr",
            "bbbbbb",
        ], ["y": 0xFFD23A, "f": 0xF2C29B, "k": 0x07040F, "r": 0xE84A4A, "R": 0xB8302E, "b": 0x3A4A8C])
    }

    func sprite(_ species: Int, facingRight: Bool) -> CGImage { facingRight ? right[species] : left[species] }

    func render(_ g: PecheGame) -> CGImage? {
        if canvas == nil || canvas?.rows != g.rows || canvas?.cols != g.cols {
            canvas = PixelCanvas(cols: g.cols, rows: g.rows)
            background = nil
        }
        guard let c = canvas else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        let key = "\(g.rows)-\(Int(g.floorY))-\(Self.sky(hour))"
        if background == nil || key != bgKey {
            background = makeBackground(g, hour: hour)
            bgKey = key
        }
        if let bg = background { c.blit(bg, x: 0, y: 0) }

        let half = Int(g.half)
        let t = g.time

        // Les vagues à la surface
        let shift = Int(t * 8)
        for x in 0..<g.cols where (x + shift) % 9 < 2 { c.dot(x, half - 3, PX.c(0xCFEFFF)) }
        for x in 0..<g.cols where (x - shift + 4) % 11 < 2 { c.dot(x, half - 5, PX.c(0x7FC8F0)) }

        // Les algues qui ondulent au fond
        var seed = PixelArt.Seeded(11)
        let floor = Int(g.floorY)
        for k in 0..<8 {
            let x0 = 6 + k * (g.cols - 12) / 8 + seed.next(10)
            let h = 10 + seed.next(16)
            let phase = Double(seed.next(100)) / 16
            for row in 0..<h {
                let sway = Int((sin(t * 1.5 + phase + Double(row) * 0.3) * Double(row) / 8).rounded())
                c.dot(x0 + sway, floor - 1 - row, PX.c(row % 4 == 0 ? 0x2F9E5A : 0x1F7A44))
                if row % 3 == 1 { c.dot(x0 + sway + (row % 2 == 0 ? 1 : -1), floor - 1 - row, PX.c(0x3FC46E)) }
            }
        }

        // Les poissons
        for (i, f) in g.fish.enumerated() {
            let facingRight: Bool
            if i == g.hooked && g.phase == .fighting {
                facingRight = f.x > g.rodTip.x + 18
            } else {
                facingRight = f.vx >= 0
            }
            let img = sprite(f.species, facingRight: facingRight)
            c.blitCentered(img, x: Int(f.x.rounded()), y: Int(f.y.rounded()))
        }

        // La barque et le pêcheur, qui se balancent
        let by = Int(g.bob.rounded())
        let bx = Int(g.boatX)
        c.blit(boat, x: bx, y: half - 8 + by)
        c.blit(fisher, x: bx + 14, y: half - 17 + by)
        let tip = g.rodTip
        let tx = Int(tip.x.rounded()), ty = Int(tip.y.rounded())
        c.line(bx + 19, half - 11 + by, tx, ty, PX.c(0x5A3A1A))
        c.line(bx + 20, half - 11 + by, tx, ty + 1, PX.c(0x8A5A2C))

        // La ligne et l'hameçon
        let lx = Int(g.lureX.rounded()), ly = Int(g.lureY.rounded())
        let lineColor = PX.c(g.tension > 0.8 && g.phase == .fighting && Int(t * 10) % 2 == 0 ? 0xFF6A6A : 0xE8F0FF)
        switch g.phase {
        case .ready, .aiming:
            c.line(tx, ty, tx, ty + 5, lineColor)
            c.fill(tx - 1, ty + 5, 2, 2, PX.c(0xFF4F4F))
        case .flying:
            c.line(tx, ty, lx, ly, lineColor)
            c.fill(lx - 1, ly - 1, 2, 2, PX.c(0xFF4F4F))
        case .sinking, .bite, .fighting:
            let sx = g.phase == .fighting ? Int(g.rodTip.x + 18) : lx
            c.line(tx, ty, sx, half, lineColor)
            c.line(sx, half, lx, ly, lineColor)
            c.fill(lx - 1, ly - 1, 2, 2, PX.c(0xFF4F4F))
            c.dot(lx, ly + 1, PX.c(0xCFD6E6))
            if g.phase == .bite && Int(t * 8) % 2 == 0 {
                // « ! » au-dessus du poisson qui mord
                c.fill(lx, ly - 10, 2, 5, PX.c(0xFFE066))
                c.fill(lx, ly - 4, 2, 2, PX.c(0xFFE066))
            }
        default:
            break
        }

        // Bulles et éclaboussures
        for p in g.particles {
            let x = Int(p.x.rounded()), y = Int(p.y.rounded())
            if p.bubble {
                c.dot(x, y, PX.c(p.color))
                if p.life > 1 { c.dot(x + 1, y, PX.c(0x8FD4FF)) }
            } else {
                c.dot(x, y, PX.c(p.color))
            }
        }
        return c.image()
    }

    /// Jour, soir ou nuit, d'après l'heure de l'iPhone.
    static func sky(_ hour: Int) -> Int {
        if hour >= 7 && hour < 18 { return 0 }
        if hour >= 18 && hour < 21 { return 1 }
        return 2
    }

    private func makeBackground(_ g: PecheGame, hour: Int) -> CGImage? {
        let c = PixelCanvas(cols: g.cols, rows: g.rows)
        let half = Int(g.half)
        let floor = Int(g.floorY)
        let kind = Self.sky(hour)
        let skyColors: [UInt32] = kind == 0 ? [0x5EB8F2, 0x7CC8F6, 0x9ED8FA, 0xC2E8FC]
            : (kind == 1 ? [0x3A2A6E, 0x8A3A7A, 0xE8645A, 0xFFAA66] : [0x0C1230, 0x141C44, 0x1C2858, 0x26346A])
        let skyBottom = half - 12
        for (k, col) in skyColors.enumerated() {
            let y0 = skyBottom * k / skyColors.count, y1 = skyBottom * (k + 1) / skyColors.count
            c.fill(0, y0, g.cols, y1 - y0, PX.c(col))
            if k > 0 {
                for x in stride(from: y0 % 2, to: g.cols, by: 2) { c.dot(x, y0, PX.c(skyColors[k - 1])) }
            }
        }
        var seed = PixelArt.Seeded(3)
        if kind == 0 {
            // Le soleil et deux nuages
            c.disc(g.cols - 30, skyBottom / 3, 7, PX.c(0xFFE680))
            c.disc(g.cols - 30, skyBottom / 3, 5, PX.c(0xFFF4B8))
            for (cx, cy) in [(34, skyBottom / 4), (92, skyBottom / 2)] {
                c.fill(cx - 10, cy, 22, 4, PX.c(0xFFFFFF))
                c.fill(cx - 5, cy - 3, 12, 3, PX.c(0xFFFFFF))
                c.fill(cx - 10, cy + 3, 22, 1, PX.c(0xDCEFFA))
            }
        } else {
            if kind == 2 {
                for _ in 0..<30 { c.dot(seed.next(g.cols), seed.next(max(1, skyBottom - 6)), PX.c(seed.next(3) == 0 ? 0xFFFFFF : 0x8C9CD8)) }
            }
            c.disc(g.cols - 32, skyBottom / 3, 6, PX.c(kind == 1 ? 0xFFD27A : 0xF2F0DC))
            if kind == 2 { c.disc(g.cols - 29, skyBottom / 3 - 2, 5, PX.c(skyColors[1])) }
        }
        // La mer au loin (moitié debout)
        c.fill(0, skyBottom, g.cols, half - skyBottom, PX.c(kind == 2 ? 0x1A3A6E : 0x2A7FC4))
        c.fill(0, skyBottom, g.cols, 1, PX.c(kind == 2 ? 0x2A4A8A : 0x5AB0E8))
        // La charnière : la ligne de l'eau
        c.fill(0, half - 1, g.cols, 1, PX.c(0xCFEFFF))

        // Sous l'eau : de plus en plus sombre
        let water: [UInt32] = kind == 2 ? [0x1C4A86, 0x173E74, 0x123262, 0x0E2852, 0x0A1E42, 0x081734]
                                        : [0x2E8BD0, 0x2677BC, 0x1F64A6, 0x18528E, 0x124276, 0x0D335E]
        let span = max(1, floor - half)
        for (k, col) in water.enumerated() {
            let y0 = half + span * k / water.count, y1 = half + span * (k + 1) / water.count
            c.fill(0, y0, g.cols, y1 - y0, PX.c(col))
            if k > 0 {
                for x in stride(from: y0 % 2, to: g.cols, by: 2) { c.dot(x, y0, PX.c(water[k - 1])) }
            }
        }
        // Rayons de lumière sous la surface
        for k in 0..<4 {
            let x0 = 20 + k * 38
            for y in 0..<min(span / 2, 60) where y % 2 == 0 {
                c.dot(x0 + y / 3, half + 1 + y, PX.c(PixelArt.mix(water[0], 0xFFFFFF, 0.18 - Double(y) / 400)))
            }
        }
        // Le sable, quelques cailloux
        c.fill(0, floor, g.cols, 5, PX.c(0xD9C08A))
        c.fill(0, floor, g.cols, 1, PX.c(0xF0DCA8))
        for _ in 0..<14 { c.dot(seed.next(g.cols), floor + 1 + seed.next(4), PX.c(0xB89A62)) }
        for _ in 0..<5 {
            let x = seed.next(g.cols)
            c.fill(x, floor - 2, 4, 2, PX.c(0x6E6A7A))
            c.dot(x + 1, floor - 2, PX.c(0x9A96A8))
        }
        // Sous le sable : le fond du tableau de bord
        c.fill(0, floor + 5, g.cols, g.rows - floor - 5, PX.c(0x0A0A1E))
        return c.image()
    }
}
