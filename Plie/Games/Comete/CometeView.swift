import SwiftUI

// MARK: - COMÈTE : le dessin et l'écran

final class CometeRenderer {
    private var canvas: PixelCanvas?
    private var background: CGImage?
    private var bgRows = 0
    private let stars: [(x: Int, y: Double, layer: Int)]
    private let ship: CGImage
    private let sprites: [CometeGame.Kind: CGImage]
    private let white: [CometeGame.Kind: CGImage]

    private static let shipRows = [
        ".....w.....",
        "....wcw....",
        "....wcw....",
        "...wwcww...",
        "..wwbbbww..",
        ".wwwbbbwww.",
        "wwwwwwwwwww",
        "ww.wwwww.ww",
        "r...www...r",
    ]
    private static let art: [CometeGame.Kind: ([String], [Character: UInt32])] = [
        .drone: ([
            ".ggggg.",
            "gGgggGg",
            "ggkgkgg",
            ".ggggg.",
            "g.g.g.g",
            "g.....g",
        ], ["g": 0x7AE85A, "G": 0xC8FF9A, "k": 0x07040F]),
        .zigzag: ([
            "...y...",
            "..yYy..",
            ".yyyyy.",
            "yykykyy",
            ".yyyyy.",
            "..yyy..",
            "...y...",
        ], ["y": 0xFFD23A, "Y": 0xFFF2A8, "k": 0x07040F]),
        .shooter: ([
            "..ppppp..",
            ".pPpppPp.",
            "ppkpppkpp",
            "ppppppppp",
            "p.ppppp.p",
            "p..p.p..p",
            "...r.r...",
        ], ["p": 0xFF5AD8, "P": 0xFFB0F0, "k": 0x07040F, "r": 0xFF4F4F]),
        .tank: ([
            "..ooooooo..",
            ".oOOOOOOOo.",
            "ooookkkoooo",
            "oooookooooo",
            "ooooooooooo",
            "o.ooooooo.o",
            "o.o.....o.o",
            "..o.....o..",
        ], ["o": 0xFF8A3D, "O": 0xFFC08A, "k": 0x07040F]),
    ]

    init() {
        var seed = PixelArt.Seeded(21)
        stars = (0..<70).map { _ in (x: seed.next(128), y: Double(seed.next(1000)) / 1000, layer: seed.next(3)) }
        ship = PixelArt.sprite(Self.shipRows, ["w": 0xE6ECF8, "c": 0x3FB5E8, "b": 0x7D88A6, "r": 0xFF4F4F])
        var s: [CometeGame.Kind: CGImage] = [:], w: [CometeGame.Kind: CGImage] = [:]
        for (k, a) in Self.art {
            s[k] = PixelArt.sprite(a.0, a.1)
            var pal: [Character: UInt32] = [:]
            for key in a.1.keys { pal[key] = 0xFFFFFF }
            w[k] = PixelArt.sprite(a.0, pal)
        }
        sprites = s
        white = w
    }

    func render(_ g: CometeGame) -> CGImage? {
        if canvas == nil || canvas?.rows != g.rows {
            canvas = PixelCanvas(cols: g.cols, rows: g.rows)
            background = nil
        }
        guard let c = canvas else { return nil }
        if background == nil || bgRows != g.rows {
            background = makeBackground(cols: g.cols, rows: g.rows)
            bgRows = g.rows
        }
        c.ctx.saveGState()
        if g.shake > 0 {
            let a = max(1, Int(g.shake * 6))
            c.ctx.translateBy(x: CGFloat(Int.random(in: -a...a)), y: CGFloat(Int.random(in: -a...a)))
        }
        if let bg = background { c.blit(bg, x: 0, y: 0) }
        let t = g.time

        // Les étoiles défilent (trois vitesses)
        for s in stars {
            let speed = [8.0, 22.0, 50.0][s.layer]
            let y = Int((s.y * Double(g.rows) + t * speed).truncatingRemainder(dividingBy: Double(g.rows)))
            let col: UInt32 = [0x4A4A8A, 0x8A8AD0, 0xFFFFFF][s.layer]
            c.dot(s.x, y, PX.c(col))
            if s.layer == 2 { c.dot(s.x, y - 1, PX.c(0x6A6AB0)) }
        }

        // Les bonus
        for b in g.bonuses {
            let x = Int(b.x), y = Int(b.y)
            let blink = Int(t * 6) % 2 == 0
            let frame: UInt32
            switch b.kind {
            case .power: frame = 0xFF4F4F
            case .shield: frame = 0x3FB5E8
            case .bomb: frame = 0xFFC93C
            }
            c.fill(x - 3, y - 3, 7, 7, PX.c(blink ? frame : PixelArt.mix(frame, 0xFFFFFF, 0.4)))
            c.fill(x - 2, y - 2, 5, 5, PX.c(0x07061A))
            switch b.kind {
            case .power:
                c.dot(x, y - 1, PX.c(0xFFFFFF)); c.fill(x - 1, y, 3, 1, PX.c(0xFFFFFF)); c.fill(x, y + 1, 1, 1, PX.c(0xFFFFFF))
            case .shield:
                c.fill(x - 1, y - 1, 3, 1, PX.c(0x8FD8FF)); c.dot(x - 1, y, PX.c(0x8FD8FF)); c.dot(x + 1, y, PX.c(0x8FD8FF)); c.dot(x, y + 1, PX.c(0x8FD8FF))
            case .bomb:
                c.fill(x - 1, y - 1, 3, 3, PX.c(0xFFC93C)); c.dot(x + 1, y - 2, PX.c(0xFF4F4F))
            }
        }

        // Les ennemis
        for e in g.enemies {
            let x = Int(e.x.rounded()), y = Int(e.y.rounded())
            if e.kind == .boss {
                drawBoss(c, x: x, y: y, e: e, t: t)
            } else if let img = (e.flash > 0 ? white[e.kind] : sprites[e.kind]) {
                c.blitCentered(img, x: x, y: y)
            }
        }

        // Les tirs
        for s in g.shots {
            let x = Int(s.x), y = Int(s.y)
            c.fill(x, y - 2, 1, 4, PX.c(0xFFF2A8))
            c.dot(x, y - 3, PX.c(0xFFFFFF))
        }
        for s in g.enemyShots {
            let x = Int(s.x), y = Int(s.y)
            c.fill(x - 1, y - 1, 2, 2, PX.c(Int(t * 12) % 2 == 0 ? 0xFF5AD8 : 0xFFB0F0))
        }

        // Le vaisseau (il clignote quand il est invincible)
        if g.phase != .over && (g.invincible <= 0 || Int(t * 14) % 2 == 0) {
            let sx = Int(g.shipX.rounded()), sy = Int(g.shipY.rounded())
            c.blitCentered(ship, x: sx, y: sy)
            let flame = Int(t * 20) % 2 == 0
            c.fill(sx - 1, sy + 5, 3, flame ? 2 : 1, PX.c(0xFFC93C))
            c.dot(sx, sy + 6 + (flame ? 1 : 0), PX.c(0xFF8A3D))
            if g.shield > 0 {
                let r = 8
                for k in 0..<20 {
                    let a = Double(k) / 20 * 2 * .pi + t * 3
                    if (k + Int(t * 8)) % 3 != 0 { c.dot(sx + Int(cos(a) * Double(r)), sy + Int(sin(a) * Double(r)), PX.c(0x8FD8FF)) }
                }
            }
        }

        // Les étincelles
        for s in g.sparks { c.dot(Int(s.x), Int(s.y), PX.c(s.color)) }
        c.ctx.restoreGState()

        // L'éclair de la bombe
        if g.bombFlash > 0 {
            c.ctx.setFillColor(CGColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: min(0.85, g.bombFlash * 1.4)))
            c.ctx.fill(CGRect(x: 0, y: 0, width: g.cols, height: g.rows))
        }
        return c.image()
    }

    private func drawBoss(_ c: PixelCanvas, x: Int, y: Int, e: CometeGame.Enemy, t: Double) {
        let hit = e.flash > 0
        let body: UInt32 = hit ? 0xFFFFFF : 0x9B4DFF
        let light: UInt32 = hit ? 0xFFFFFF : 0xC890FF
        let dark: UInt32 = hit ? 0xE0E0E0 : 0x4A1C8C
        // La soucoupe
        for dy in -5...5 {
            let k = Double(dy) / 5.5
            let half = Int((15.5 * sqrt(max(0, 1 - k * k))).rounded())
            c.fill(x - half, y + dy, half * 2 + 1, 1, PX.c(dy < -1 ? light : (dy > 2 ? dark : body)))
        }
        // La coupole
        for dy in -10 ... -5 {
            let k = Double(dy + 5) / 5.5
            let half = Int((6.5 * sqrt(max(0, 1 - k * k))).rounded())
            c.fill(x - half, y + dy, half * 2 + 1, 1, PX.c(hit ? 0xFFFFFF : 0x3FB5E8))
        }
        c.fill(x - 3, y - 9, 2, 1, PX.c(0xCFEFFF))
        // Les lumières qui tournent
        for k in 0..<7 {
            let on = (k + Int(t * 8)) % 3 == 0
            c.fill(x - 12 + k * 4, y, 2, 2, PX.c(on ? 0xFFE066 : 0x7A3AB8))
        }
        // Les canons
        c.fill(x - 13, y + 5, 3, 3, PX.c(dark)); c.fill(x + 11, y + 5, 3, 3, PX.c(dark)); c.fill(x - 1, y + 5, 3, 3, PX.c(dark))
    }

    private func makeBackground(cols: Int, rows: Int) -> CGImage? {
        let c = PixelCanvas(cols: cols, rows: rows)
        let bands: [UInt32] = [0x07061A, 0x0B0824, 0x110A30, 0x0B0824, 0x07061A]
        for (k, col) in bands.enumerated() {
            let y0 = rows * k / bands.count, y1 = rows * (k + 1) / bands.count
            c.fill(0, y0, cols, y1 - y0, PX.c(col))
            if k > 0 { for x in stride(from: y0 % 2, to: cols, by: 2) { c.dot(x, y0, PX.c(bands[k - 1])) } }
        }
        // Une nébuleuse tramée
        var seed = PixelArt.Seeded(8)
        for _ in 0..<260 {
            let x = seed.next(cols), y = seed.next(rows)
            let d = hypot(Double(x - cols * 2 / 3), Double(y - rows / 3) * 0.7)
            if d < Double(cols) / 3 && seed.next(3) == 0 { c.dot(x, y, PX.c(0x2A1458)) }
        }
        // Une planète au loin
        c.disc(18, rows * 3 / 4, 9, PX.c(0x2A3A7A))
        c.disc(16, rows * 3 / 4 - 2, 7, PX.c(0x3A4E9A))
        c.fill(4, rows * 3 / 4, 28, 1, PX.c(0x5A6ABA))
        return c.image()
    }
}

struct CometeView: View {
    @Environment(AppState.self) private var app
    @State private var game = CometeGame()
    @State private var renderer = CometeRenderer()
    @State private var dragging = false

    var body: some View {
        GeometryReader { safe in
            ZStack {
                GeometryReader { full in
                    let ptPerPx = full.size.width / CGFloat(game.cols)
                    CometeField(game: game, renderer: renderer)
                        .frame(width: full.size.width, height: full.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if !dragging { dragging = true; game.dragBegan() }
                                    game.drag(dx: Double(v.translation.width / ptPerPx), dy: Double(v.translation.height / ptPerPx))
                                }
                                .onEnded { _ in dragging = false; game.dragEnded() }
                        )
                        .onAppear { layout(full.size, safe) }
                        .onChange(of: full.size) { _, s in layout(s, safe) }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    hud
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    if let hp = game.bossHP {
                        PixelGauge(value: hp, color: Color(hex: 0xFF7BEA), blocks: 20)
                            .frame(height: 10)
                            .padding(.horizontal, 24)
                            .padding(.top, 6)
                    }
                    Spacer()
                    if game.phase == .playing {
                        HStack {
                            Spacer()
                            PixelButton(fill: Color(hex: game.bombs > 0 ? 0xFFC93C : 0x2C1B5C), border: Color(hex: 0x8A4B0C)) {
                                game.bomb()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(L("BOMBE")).font(PixelFont.font(8))
                                    Text(verbatim: "×\(game.bombs)").font(PixelFont.font(10))
                                }
                                .foregroundStyle(game.bombs > 0 ? Color(hex: 0x3A1D00) : .white.opacity(0.5))
                                .frame(width: 74, height: 48)
                            }
                            .accessibilityHint(L("Ou plie le Duo à moitié"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }

                if let b = game.banner, game.phase == .playing {
                    Text(b)
                        .font(PixelFont.font(14))
                        .foregroundStyle(Color(hex: 0xFFE066))
                        .shadow(color: Color(hex: 0x07040F), radius: 0, x: 3, y: 3)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 20)
                        .position(x: safe.size.width / 2, y: safe.size.height * 0.3)
                        .allowsHitTesting(false)
                }

                if game.phase == .menu { menu }
                if game.phase == .over { over }
            }
        }
        .foregroundStyle(.white)
        .background(Color(hex: 0x07061A).ignoresSafeArea())
        .onFrame { dt in game.tick(dt: dt) }
        .onHingeAngle { game.hinge($0) }
        .onChange(of: game.phase) { _, p in
            if p == .over {
                app.gamePlayed()
                if game.score >= game.best && game.score > 0 { app.celebrate() }
            }
        }
        .onAppear {
            PixelFont.register()
            #if DEBUG
            Demo.schedule("comete", [(0.3, { game.demo() })])
            Demo.every("comete", 0.05, from: 0.5, until: 60) { game.demoMove() }
            #endif
        }
    }

    private func layout(_ size: CGSize, _ safe: GeometryProxy) {
        guard size.width > 0, size.height > 0 else { return }
        let ptPerPx = size.width / CGFloat(game.cols)
        game.configure(rows: Int((size.height / ptPerPx).rounded()),
                       topReserve: Double((safe.safeAreaInsets.top + 60) / ptPerPx),
                       bottomReserve: Double((safe.safeAreaInsets.bottom + 12) / ptPerPx))
    }

    private var hud: some View {
        PixelTopBar(title: L("COMÈTE"), subtitle: game.phase == .playing ? L("Vague \(game.wave)") : L("Record : \(game.best)"),
                    game: .comete, border: Theme.comete, onBack: { app.route = .hub }) {
            VStack(alignment: .trailing, spacing: 5) {
                Text(verbatim: "\(game.score)").font(PixelFont.font(14)).foregroundStyle(Color(hex: 0xFFE066))
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: "heart.fill").font(.system(size: 9, weight: .black))
                            .foregroundStyle(k < game.lives ? Color(hex: 0xFF4F7B) : .white.opacity(0.2))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(game.lives) vies"))
            }
        }
    }

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("COMÈTE")).font(PixelFont.font(24)).foregroundStyle(Theme.comete)
                    .shadow(color: Color(hex: 0x07040F), radius: 0, x: 3, y: 3)
                Text(L("Glisse le doigt pour piloter. Le tir est automatique.")).font(PixelFont.font(8)).lineSpacing(6).multilineTextAlignment(.center)
                Text(L("Plie le Duo à moitié : BOMBE !")).font(PixelFont.font(8)).foregroundStyle(Color(hex: 0xFFC93C)).multilineTextAlignment(.center)
                PixelButton(fill: Color(hex: 0x7B5CFF), border: Color(hex: 0x2A1458)) {
                    game.start()
                } label: {
                    Text(L("DÉCOLLER")).font(PixelFont.font(14)).frame(maxWidth: .infinity, minHeight: 52)
                }
                if game.best > 0 {
                    Text(L("Record : \(game.best)")).font(PixelFont.font(9)).foregroundStyle(Color(hex: 0xFFE066))
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .pixelBox(fill: Color(hex: 0x110A30), border: Theme.comete)
        }
    }

    private var over: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("PARTIE TERMINÉE")).font(PixelFont.font(14))
                Text(verbatim: "\(game.score)").font(PixelFont.font(28)).foregroundStyle(Color(hex: 0xFFE066))
                Text(game.score >= game.best && game.score > 0 ? L("Nouveau record !") : L("Record : \(game.best)"))
                    .font(PixelFont.font(9)).foregroundStyle(Color(hex: 0xFF7BEA))
                Text(L("Vague \(game.wave)")).font(PixelFont.font(8)).foregroundStyle(.white.opacity(0.75))
                PixelButton(fill: Color(hex: 0x7B5CFF), border: Color(hex: 0x2A1458)) {
                    game.start()
                } label: {
                    Text(L("Rejouer")).font(PixelFont.font(12)).frame(maxWidth: .infinity, minHeight: 46)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .pixelBox(fill: Color(hex: 0x110A30), border: Theme.comete)
        }
    }
}

struct CometeField: View {
    let game: CometeGame
    let renderer: CometeRenderer

    var body: some View {
        let _ = game.frame
        PixelImage(image: renderer.render(game), label: L("L'espace et ton vaisseau"))
    }
}
