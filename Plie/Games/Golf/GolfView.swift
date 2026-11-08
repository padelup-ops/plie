import SwiftUI

// MARK: - MINIGOLF : le dessin et l'écran

final class GolfRenderer {
    private var canvas: PixelCanvas?
    private var background: CGImage?
    private var bgKey = ""

    func render(_ g: GolfGame) -> CGImage? {
        let rows = max(64, Int((g.height * Double(g.cols)).rounded()))
        if canvas == nil || canvas?.rows != rows {
            canvas = PixelCanvas(cols: g.cols, rows: rows)
            background = nil
        }
        guard let c = canvas else { return nil }
        let key = "\(g.hole)-\(rows)-\(px(g.topY, g))-\(px(g.botY, g))"
        if background == nil || key != bgKey {
            background = makeBackground(g, rows: rows)
            bgKey = key
        }
        if let bg = background { c.blit(bg, x: 0, y: 0) }
        let t = g.time

        // Reflets sur l'eau
        for r in g.current.water {
            let q = g.rect(r)
            let x0 = px(q.x0, g), y0 = px(q.y0, g), x1 = px(q.x1, g), y1 = px(q.y1, g)
            let shift = Int(t * 6)
            var y = y0 + 2
            while y < y1 - 1 {
                var x = x0 + ((y / 3 + shift) % 7)
                while x < x1 - 2 {
                    c.fill(x, y, 2, 1, PX.c(0x8FD8FF))
                    x += 9
                }
                y += 4
            }
        }

        // La pente : des chevrons qui descendent vers la charnière
        if g.tiltDegrees > 0 {
            let half = px(g.half, g), top = px(g.topY, g)
            let span = max(1, half - top - 8)
            let speed = 10 + g.tiltDegrees / 3
            for (k, x) in [6, g.cols - 9].enumerated() {
                let y = top + 4 + (Int(t * speed) + k * span / 2) % span
                c.dot(x, y, PX.c(0xB8F0A8)); c.dot(x + 2, y, PX.c(0xB8F0A8)); c.dot(x + 1, y + 1, PX.c(0xB8F0A8))
            }
        }

        // Les barrières qui bougent
        for m in g.current.movers {
            let q = g.rect(m.rect, dx: g.moverOffset(m))
            wall(c, px(q.x0, g), px(q.y0, g), px(q.x1, g) - px(q.x0, g), px(q.y1, g) - px(q.y0, g), moving: true)
        }

        // Le drapeau (il se balance)
        let cup = g.cup
        let cx = px(cup.x, g), cy = px(cup.y, g)
        if g.phase != .sinking || g.sinkT < 0.3 {
            c.fill(cx, cy - 14, 1, 13, PX.c(0xF0F0F0))
            let wave = Int(t * 4) % 2
            c.fill(cx + 1, cy - 14, 6, 2, PX.c(0xFF4F4F))
            c.fill(cx + 1, cy - 12, 4 + wave, 2, PX.c(0xE83A3A))
            c.fill(cx + 1, cy - 10, 2, 1, PX.c(0xC82A2A))
        }

        // La visée
        if let a = g.aim {
            let n = 3 + Int(a.power * 9)
            let col = PX.c(PixelArt.mix(0x9CFF6B, 0xFF4F4F, a.power))
            for k in 1...n {
                let d = Double(k) * 0.028
                let x = px(g.ball.x + a.dx * d, g), y = px(g.ball.y + a.dy * d, g)
                if k == n { c.fill(x - 1, y - 1, 3, 3, col) } else { c.dot(x, y, col) }
            }
        }

        // La balle
        let bx = px(g.ball.x, g), by = px(g.ball.y, g)
        let color: UInt32 = g.player == 0 ? 0xFFFFFF : 0xFF7BEA
        if g.phase == .sinking {
            let r = max(0, 3 - Int(g.sinkT * 5))
            if r > 0 { c.disc(bx, by, r - 1, PX.c(color)) }
        } else {
            c.disc(bx + 1, by + 1, 3, PX.c(0x2E6A2A))
            c.disc(bx, by, 3, PX.c(PixelArt.mix(color, 0x07040F, 0.25)))
            c.disc(bx, by, 2, PX.c(color))
            c.dot(bx - 1, by - 1, PX.c(0xFFFFFF))
        }
        if g.splashT > 0 {
            let r = Int((0.5 - g.splashT) * 20) + 2
            for a in stride(from: 0.0, to: 6.28, by: 0.7) {
                c.dot(bx + Int(cos(a) * Double(r)), by + Int(sin(a) * Double(r)), PX.c(0xCFEFFF))
            }
        }
        return c.image()
    }

    private func px(_ v: Double, _ g: GolfGame) -> Int { Int((v * Double(g.cols)).rounded()) }

    private func wall(_ c: PixelCanvas, _ x: Int, _ y: Int, _ w: Int, _ h: Int, moving: Bool = false) {
        c.fill(x + 1, y + 1, w, h, PX.c(0x2E6A2A))
        c.fill(x, y, w, h, PX.c(moving ? 0x9C5AC8 : 0x8A5A2C))
        c.fill(x, y, w, 1, PX.c(moving ? 0xC890F0 : 0xC88A4A))
        c.fill(x, y + h - 1, w, 1, PX.c(moving ? 0x5A2E80 : 0x4A2E14))
        if !moving {
            var k = x + 3
            while k < x + w - 1 { c.dot(k, y + h / 2, PX.c(0x6E4420)); k += 6 }
        }
    }

    private func makeBackground(_ g: GolfGame, rows: Int) -> CGImage? {
        let c = PixelCanvas(cols: g.cols, rows: rows)
        let top = px(g.topY, g), bot = px(g.botY, g), half = px(g.half, g)
        c.fill(0, 0, g.cols, rows, PX.c(0x16301E))
        // Le gazon en damier (un peu plus clair en haut, la partie qui penche)
        let tile = 8
        for y in top..<bot {
            for xb in stride(from: 0, to: g.cols, by: tile) {
                let light = ((xb / tile) + (y - top) / tile) % 2 == 0
                let col: UInt32 = y < half ? (light ? 0x6ACB62 : 0x5DBC56) : (light ? 0x5CC45A : 0x4FB24E)
                c.fill(xb, y, tile, 1, PX.c(col))
            }
        }
        var seed = PixelArt.Seeded(UInt64(g.hole + 5))
        for _ in 0..<60 {
            let x = seed.next(g.cols), y = top + seed.next(max(1, bot - top))
            c.dot(x, y, PX.c(0x3E9A3E))
        }
        // La charnière : une couture dans le gazon
        for x in stride(from: 0, to: g.cols, by: 2) { c.dot(x, half, PX.c(0x3A8A3A)) }

        // Le sable et l'eau
        for r in g.current.sand {
            let q = g.rect(r)
            let x0 = px(q.x0, g), y0 = px(q.y0, g), x1 = px(q.x1, g), y1 = px(q.y1, g)
            c.fill(x0, y0, x1 - x0, y1 - y0, PX.c(0xE8D49A))
            for y in y0..<y1 { for x in x0..<x1 where (x * 7 + y * 13) % 11 == 0 { c.dot(x, y, PX.c(0xCDB47A)) } }
            c.fill(x0, y0, x1 - x0, 1, PX.c(0xF6E6B8))
        }
        for r in g.current.water {
            let q = g.rect(r)
            let x0 = px(q.x0, g), y0 = px(q.y0, g), x1 = px(q.x1, g), y1 = px(q.y1, g)
            c.fill(x0, y0, x1 - x0, y1 - y0, PX.c(0x2E8BD0))
            c.fill(x0, y0, x1 - x0, 2, PX.c(0x1F64A6))
            c.fill(x0, y1 - 1, x1 - x0, 1, PX.c(0x5AB0E8))
        }
        // Les murs fixes
        for r in g.current.walls {
            let q = g.rect(r)
            wall(c, px(q.x0, g), px(q.y0, g), max(2, px(q.x1, g) - px(q.x0, g)), max(2, px(q.y1, g) - px(q.y0, g)))
        }
        // Le cadre en bois
        wall(c, 0, top - 3, g.cols, 3)
        wall(c, 0, bot, g.cols, 3)
        c.fill(0, top, 2, bot - top, PX.c(0x8A5A2C)); c.fill(g.cols - 2, top, 2, bot - top, PX.c(0x8A5A2C))
        c.fill(2, top, 1, bot - top, PX.c(0x4A2E14)); c.fill(g.cols - 3, top, 1, bot - top, PX.c(0x4A2E14))

        // Le départ et le trou
        let tee = g.current.tee
        let tx = px(tee.x, g), ty = px(g.fy(tee.y), g)
        c.fill(tx - 4, ty - 4, 9, 9, PX.c(0x7AD872))
        c.fill(tx - 4, ty - 4, 9, 1, PX.c(0x9AE892))
        let cup = g.cup
        let cx = px(cup.x, g), cy = px(cup.y, g)
        c.disc(cx, cy, 6, PX.c(0x3E8A3A))
        c.disc(cx, cy, 5, PX.c(0x07140A))
        c.fill(cx - 3, cy - 4, 6, 1, PX.c(0x1A2A1A))
        return c.image()
    }
}

struct GolfView: View {
    @Environment(AppState.self) private var app
    @State private var game = GolfGame()
    @State private var renderer = GolfRenderer()

    var body: some View {
        GeometryReader { safe in
            ZStack {
                GeometryReader { full in
                    GolfField(game: game, renderer: renderer)
                        .frame(width: full.size.width, height: full.size.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in game.drag(dx: v.translation.width, dy: v.translation.height) }
                                .onEnded { _ in game.release() }
                        )
                        .onAppear { layout(full.size, safe) }
                        .onChange(of: full.size) { _, s in layout(s, safe) }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    PixelTopBar(title: L("MINIGOLF"), subtitle: game.phase == .menu ? L("9 trous") : L("Trou \(game.hole + 1) / \(GolfHole.all.count) · Par \(game.current.par)"),
                                game: .golf, border: Theme.golf, onBack: { app.route = .hub }) {
                        if game.phase != .menu {
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(L("Coups : \(game.strokes)")).font(PixelFont.font(10)).foregroundStyle(Color(hex: 0xFFE066))
                                if game.players > 1 {
                                    Text(L("Joueur \(game.player + 1)")).font(PixelFont.font(7))
                                        .foregroundStyle(game.player == 0 ? .white : Color(hex: 0xFF7BEA))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    Spacer()
                    footer
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if let banner = game.banner {
                    Text(banner)
                        .font(PixelFont.font(14))
                        .foregroundStyle(Color(hex: 0xFFE066))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .pixelBox(fill: Color(hex: 0x07040F).opacity(0.85), border: Color(hex: 0xFFE066))
                        .padding(.horizontal, 20)
                        .position(x: safe.size.width / 2, y: safe.size.height * 0.5)
                        .allowsHitTesting(false)
                }

                if game.phase == .menu { menu }
                if game.phase == .finished { scorecard }
            }
        }
        .foregroundStyle(.white)
        .background(Color(hex: 0x16301E).ignoresSafeArea())
        .onFrame { dt in game.tick(dt: dt) }
        .onHingeAngle { game.hinge($0) }
        .onChange(of: game.phase) { _, p in
            if p == .finished {
                if game.players == 1 { GameCenter.shared.submit(game.total(0), to: .golf) }
                app.gamePlayed()
                if game.total(0) <= game.totalPar { app.celebrate() }
            }
        }
        .onAppear {
            PixelFont.register()
            #if DEBUG
            Demo.schedule("golf", [(0.3, { game.start(players: 2) })])
            Demo.every("golf", 2.5, from: 1.2, until: 60) { game.demoShot() }
            #endif
        }
    }

    private func layout(_ size: CGSize, _ safe: GeometryProxy) {
        guard size.width > 0, size.height > 0 else { return }
        game.configure(height: Double(size.height / size.width),
                       topReserve: Double((safe.safeAreaInsets.top + 70) / size.width),
                       bottomReserve: Double((safe.safeAreaInsets.bottom + 44) / size.width))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if game.players > 1 && game.phase != .menu {
                Text(L("J1 : \(game.total(0))")).font(PixelFont.font(8))
                Text(L("J2 : \(game.total(1))")).font(PixelFont.font(8)).foregroundStyle(Color(hex: 0xFF7BEA))
            }
            Spacer(minLength: 4)
            Text(game.tiltDegrees > 0 ? L("Pente : \(Int(game.tiltDegrees.rounded()))°") : L("Tire en arrière pour viser"))
                .font(PixelFont.font(7))
                .foregroundStyle(game.tiltDegrees > 0 ? Color(hex: 0xB8F0A8) : .white.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(8)
        .pixelBox(fill: Color(hex: 0x0E2414).opacity(0.9), border: Color(hex: 0x3E8A3A))
    }

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("MINIGOLF")).font(PixelFont.font(20)).foregroundStyle(Theme.golf)
                Text(L("Plie le Duo : la moitié du haut devient une pente.")).font(PixelFont.font(8)).lineSpacing(6)
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85))
                PixelButton(fill: Color(hex: 0x6BD35A), border: Color(hex: 0x2E6A2A)) {
                    game.start(players: 1)
                } label: {
                    Text(L("1 joueur")).font(PixelFont.font(13)).foregroundStyle(Color(hex: 0x0E2414)).frame(maxWidth: .infinity, minHeight: 48)
                }
                PixelButton(fill: Color(hex: 0xFF7BEA), border: Color(hex: 0x8C1C78)) {
                    game.start(players: 2)
                } label: {
                    Text(L("2 joueurs")).font(PixelFont.font(13)).foregroundStyle(Color(hex: 0x2A0A24)).frame(maxWidth: .infinity, minHeight: 48)
                }
                if game.best > 0 {
                    Text(L("Record : \(game.best) coups (par \(game.totalPar))")).font(PixelFont.font(8)).foregroundStyle(Color(hex: 0xFFE066))
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .pixelBox(fill: Color(hex: 0x0E2414), border: Theme.golf)
        }
    }

    private var scorecard: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("CARTE DE SCORE")).font(PixelFont.font(14))
                VStack(spacing: 6) {
                    scoreRow(L("Trou"), values: (1...GolfHole.all.count).map { "\($0)" }, total: "Σ", color: .white.opacity(0.6))
                    scoreRow(L("Par"), values: GolfHole.all.map { "\($0.par)" }, total: "\(game.totalPar)", color: .white.opacity(0.8))
                    ForEach(0..<game.players, id: \.self) { p in
                        scoreRow(game.players > 1 ? L("J\(p + 1)") : L("Toi"), values: game.cards[p].map { "\($0)" },
                                 total: "\(game.total(p))", color: p == 0 ? .white : Color(hex: 0xFF7BEA))
                    }
                }
                Text(resultLine).font(PixelFont.font(9)).foregroundStyle(Color(hex: 0xFFE066)).multilineTextAlignment(.center).lineSpacing(5)
                PixelButton(fill: Color(hex: 0x6BD35A), border: Color(hex: 0x2E6A2A)) {
                    game.start(players: game.players)
                } label: {
                    Text(L("Rejouer")).font(PixelFont.font(12)).foregroundStyle(Color(hex: 0x0E2414)).frame(maxWidth: .infinity, minHeight: 46)
                }
                PixelButton(fill: Color(hex: 0x2C1B5C)) {
                    game.backToMenu()
                } label: {
                    Text(L("Menu")).font(PixelFont.font(10)).frame(maxWidth: .infinity, minHeight: 40)
                }
            }
            .padding(18)
            .frame(maxWidth: 380)
            .pixelBox(fill: Color(hex: 0x0E2414), border: Theme.golf)
            .padding(12)
        }
    }

    private var resultLine: String {
        if game.players > 1 {
            let a = game.total(0), b = game.total(1)
            if a == b { return L("Égalité !") }
            return L("Joueur \(a < b ? 1 : 2) gagne !")
        }
        let diff = game.total(0) - game.totalPar
        if diff < 0 { return L("\(-diff) sous le par. Bravo !") }
        if diff == 0 { return L("Pile le par !") }
        return L("\(diff) au-dessus du par")
    }

    private func scoreRow(_ title: String, values: [String], total: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(title).font(PixelFont.font(6)).frame(width: 34, alignment: .leading).lineLimit(1).minimumScaleFactor(0.5)
            ForEach(0..<GolfHole.all.count, id: \.self) { i in
                Text(verbatim: i < values.count ? values[i] : "-").font(PixelFont.font(7)).frame(maxWidth: .infinity)
            }
            Text(verbatim: total).font(PixelFont.font(7)).frame(width: 26)
        }
        .foregroundStyle(color)
    }
}

struct GolfField: View {
    let game: GolfGame
    let renderer: GolfRenderer

    var body: some View {
        let _ = game.frame
        PixelImage(image: renderer.render(game), label: L("Le parcours de minigolf"))
    }
}
