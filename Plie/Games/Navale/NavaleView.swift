import SwiftUI

// MARK: - BATAILLE NAVALE : les écrans

struct NavaleView: View {
    @Environment(AppState.self) private var app
    @State private var game = NavaleGame()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x04121F), Color(hex: 0x071E33)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch game.phase {
            case .menu: menu
            case .placing: NavalePlacement(game: game)
            case .handover: NavaleHandover(game: game)
            case .aiming, .enemyTurn: NavaleBattle(game: game)
            case .over: NavaleOver(game: game)
            }
        }
        .foregroundStyle(.white)
        .onFrame(step: 1.0 / 30.0) { dt in game.tick(dt) }
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.hinge(degrees)
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordNavale(won: game.vsComputer && game.winner == 0) }
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                    HowToButton(game: .navale)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                NavaleEmblem()
                    .frame(width: 150, height: 120)
                    .accessibilityHidden(true)
                Text(L("BATAILLE NAVALE"))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(L("Plie le Duo en L : en haut les eaux ennemies où tu tires, en bas ta flotte. À deux, refermez le Duo pour vous le passer : personne ne voit les bateaux de l'autre."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)

                Picker(L("Adversaire"), selection: $game.vsComputer) {
                    Text(L("Contre l'ordi")).tag(true)
                    Text(L("À deux")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if game.vsComputer {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { l in
                            pill(BoardOpponent.levelName(l), selected: game.level == l) { game.level = l }
                        }
                    }
                    .frame(maxWidth: 420)
                }

                VStack(spacing: 8) {
                    Picker(L("Règle"), selection: $game.salvo) {
                        Text(L("Salve")).tag(true)
                        Text(L("Classique")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(game.salvo ? L("Un tir par bateau encore à flot, à chaque tour.") : L("Un seul tir par tour."))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: 420)

                Button {
                    game.start()
                } label: {
                    Label(L("Placer ma flotte"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.navale, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)

                if app.navaleWins > 0 {
                    Text(L("\(app.navaleWins) victoire\(app.navaleWins > 1 ? "s" : "") contre l'ordi"))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.plie(15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(selected ? Theme.navale : Color.white.opacity(0.1)))
                .foregroundStyle(selected ? Theme.ink : .white)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Une ancre dans un hublot, pour le menu.
struct NavaleEmblem: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0x1E6FA8), Theme.navaleSea], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Color(hex: 0xC9D6E3), lineWidth: 8)
            Image(systemName: "ferry.fill")
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - La grille

/// Une grille 10 × 10 : la mer, les bateaux (si on a le droit de les voir), les tirs et les explosions.
struct NavaleGrid: View {
    let board: NavaleBoard
    let seat: Int
    let showShips: Bool
    let blasts: [NavaleBlast]
    let time: Double
    var radar = false
    var onTap: ((Int) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 10
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            Canvas { context, _ in
                drawSea(context, origin: origin, side: side, cell: cell)
                drawShips(context, origin: origin, cell: cell)
                drawShots(context, origin: origin, cell: cell)
                drawBlasts(context, origin: origin, cell: cell)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                let x = Int((location.x - origin.x) / cell)
                let y = Int((location.y - origin.y) / cell)
                guard x >= 0, y >= 0, x < 10, y < 10 else { return }
                onTap(y * 10 + x)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func rect(_ c: Int, _ origin: CGPoint, _ cell: CGFloat) -> CGRect {
        CGRect(x: origin.x + CGFloat(c % 10) * cell, y: origin.y + CGFloat(c / 10) * cell, width: cell, height: cell)
    }

    private func drawSea(_ context: GraphicsContext, origin: CGPoint, side: CGFloat, cell: CGFloat) {
        let frame = CGRect(x: origin.x, y: origin.y, width: side, height: side)
        let shape = Path(roundedRect: frame, cornerRadius: 12)
        context.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0x14598A), Theme.navaleSea]),
                                                  startPoint: CGPoint(x: frame.minX, y: frame.minY), endPoint: CGPoint(x: frame.maxX, y: frame.maxY)))
        // Petites vagues qui bougent
        var waves = Path()
        for row in 0..<10 {
            let y = frame.minY + (CGFloat(row) + 0.62) * cell
            let shift = CGFloat(sin(time * 1.3 + Double(row))) * cell * 0.25
            for k in stride(from: 0, to: 10, by: 3) {
                let x = frame.minX + (CGFloat(k) + 0.4 + CGFloat(row % 3) * 0.9) * cell + shift
                guard x + cell * 0.5 < frame.maxX, x > frame.minX else { continue }
                waves.move(to: CGPoint(x: x, y: y))
                waves.addQuadCurve(to: CGPoint(x: x + cell * 0.5, y: y), control: CGPoint(x: x + cell * 0.25, y: y - cell * 0.12))
            }
        }
        context.stroke(waves, with: .color(.white.opacity(0.1)), lineWidth: 1)
        var grid = Path()
        for k in 1..<10 {
            let v = CGFloat(k) * cell
            grid.move(to: CGPoint(x: frame.minX + v, y: frame.minY))
            grid.addLine(to: CGPoint(x: frame.minX + v, y: frame.maxY))
            grid.move(to: CGPoint(x: frame.minX, y: frame.minY + v))
            grid.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + v))
        }
        context.stroke(grid, with: .color(.white.opacity(0.13)), lineWidth: 1)
        context.stroke(shape, with: .color(Theme.navale.opacity(0.5)), lineWidth: 2)
        if radar {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let a1 = CGFloat(time * 1.6)
            let a0 = a1 - 0.55
            let reach = side * 0.5
            var sweep = Path()
            sweep.move(to: center)
            sweep.addArc(center: center, radius: side * 0.72, startAngle: .radians(Double(a0)), endAngle: .radians(Double(a1)), clockwise: false)
            sweep.closeSubpath()
            let from = CGPoint(x: center.x + cos(a0) * reach, y: center.y + sin(a0) * reach)
            let to = CGPoint(x: center.x + cos(a1) * reach, y: center.y + sin(a1) * reach)
            var clipped = context
            clipped.clip(to: shape)
            clipped.fill(sweep, with: .linearGradient(Gradient(colors: [Color(hex: 0x3DFFB0, opacity: 0), Color(hex: 0x3DFFB0, opacity: 0.18)]),
                                                     startPoint: from, endPoint: to))
        }
    }

    private func drawShips(_ context: GraphicsContext, origin: CGPoint, cell: CGFloat) {
        for ship in board.ships {
            let sunk = board.isSunk(ship)
            guard showShips || sunk else { continue }
            NavaleShipArt.draw(context, ship: ship, origin: origin, cell: cell, sunk: sunk)
        }
    }

    private func drawShots(_ context: GraphicsContext, origin: CGPoint, cell: CGFloat) {
        for (c, hit) in board.shots {
            let r = rect(c, origin, cell)
            let center = CGPoint(x: r.midX, y: r.midY)
            if hit {
                let g = cell * 0.42
                context.fill(Path(ellipseIn: CGRect(x: center.x - g, y: center.y - g, width: 2 * g, height: 2 * g)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFFD23D), Color(hex: 0xFF5C2E), Color(hex: 0xFF5C2E, opacity: 0)]),
                                                   center: center, startRadius: 0, endRadius: g))
                let flicker = CGFloat(0.85 + 0.15 * sin(time * 9 + Double(c)))
                var cross = Path()
                let k = cell * 0.2 * flicker
                cross.move(to: CGPoint(x: center.x - k, y: center.y - k))
                cross.addLine(to: CGPoint(x: center.x + k, y: center.y + k))
                cross.move(to: CGPoint(x: center.x + k, y: center.y - k))
                cross.addLine(to: CGPoint(x: center.x - k, y: center.y + k))
                context.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: max(2, cell * 0.09), lineCap: .round))
            } else {
                let d = cell * 0.16
                context.fill(Path(ellipseIn: CGRect(x: center.x - d, y: center.y - d, width: 2 * d, height: 2 * d)), with: .color(.white.opacity(0.75)))
                context.stroke(Path(ellipseIn: CGRect(x: center.x - d * 2, y: center.y - d * 2, width: 4 * d, height: 4 * d)),
                               with: .color(.white.opacity(0.25)), lineWidth: 1)
            }
        }
    }

    private func drawBlasts(_ context: GraphicsContext, origin: CGPoint, cell: CGFloat) {
        for b in blasts where b.seat == seat {
            let age = time - b.at
            guard age >= 0, age < 1.2 else { continue }
            let r = rect(b.cell, origin, cell)
            let center = CGPoint(x: r.midX, y: r.midY)
            let k = CGFloat(age / 1.2)
            if b.hit {
                let size = cell * (b.sunk ? 2.6 : 1.5) * (0.4 + k)
                context.fill(Path(ellipseIn: CGRect(x: center.x - size, y: center.y - size, width: 2 * size, height: 2 * size)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF3B0, opacity: Double(1 - k)), Color(hex: 0xFF7A2E, opacity: Double(1 - k) * 0.8), Color(hex: 0xFF2E2E, opacity: 0)]),
                                                   center: center, startRadius: 0, endRadius: size))
            } else {
                for ring in 0..<2 {
                    let rr = cell * (0.3 + 1.1 * k + CGFloat(ring) * 0.35)
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr)),
                                   with: .color(.white.opacity(Double(1 - k) * 0.8)), lineWidth: 2)
                }
            }
        }
    }
}

/// Les bateaux vus du ciel : une coque grise, un pont, des tourelles.
enum NavaleShipArt {
    static func draw(_ context: GraphicsContext, ship: NavaleShip, origin: CGPoint, cell: CGFloat, sunk: Bool) {
        let w = CGFloat(ship.horizontal ? ship.length : 1) * cell
        let h = CGFloat(ship.horizontal ? 1 : ship.length) * cell
        let frame = CGRect(x: origin.x + CGFloat(ship.x) * cell, y: origin.y + CGFloat(ship.y) * cell, width: w, height: h)
            .insetBy(dx: cell * 0.12, dy: cell * 0.12)
        let hull = Path(roundedRect: frame, cornerRadius: min(frame.width, frame.height) / 2)
        let top = sunk ? Color(hex: 0x5A2A22) : Color(hex: 0xB8C4D0)
        let bottom = sunk ? Color(hex: 0x2E1612) : Color(hex: 0x6E7C8C)
        context.fill(hull, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                 startPoint: CGPoint(x: frame.minX, y: frame.minY),
                                                 endPoint: ship.horizontal ? CGPoint(x: frame.minX, y: frame.maxY) : CGPoint(x: frame.maxX, y: frame.minY)))
        context.stroke(hull, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
        // Le pont et les tourelles
        let deck = frame.insetBy(dx: ship.horizontal ? cell * 0.35 : cell * 0.22, dy: ship.horizontal ? cell * 0.22 : cell * 0.35)
        context.fill(Path(roundedRect: deck, cornerRadius: 3), with: .color(.black.opacity(sunk ? 0.3 : 0.18)))
        for k in 0..<ship.length {
            guard k % 2 == 1 || ship.length <= 2 else { continue }
            let cx = ship.horizontal ? frame.minX + (CGFloat(k) + 0.5) * cell - cell * 0.12 : frame.midX
            let cy = ship.horizontal ? frame.midY : frame.minY + (CGFloat(k) + 0.5) * cell - cell * 0.12
            let d = cell * 0.13
            context.fill(Path(ellipseIn: CGRect(x: cx - d, y: cy - d, width: 2 * d, height: 2 * d)), with: .color(sunk ? .black.opacity(0.4) : Color(hex: 0x4A5664)))
        }
    }
}

// MARK: - Placement

struct NavalePlacement: View {
    let game: NavaleGame

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                HowToButton(game: .navale)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Text(game.vsComputer ? L("Place ta flotte") : L("\(NavaleGame.playerName(game.current)) : place ta flotte"))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(L("Glisse un bateau pour le déplacer, touche-le pour le tourner."))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            NavalePlacementGrid(game: game)
                .padding(.horizontal, 16)
                .frame(maxWidth: 560)
            HStack(spacing: 10) {
                Button {
                    game.shuffleFleet()
                } label: {
                    Label(L("Au hasard"), systemImage: "dice.fill")
                }
                .buttonStyle(GhostButtonStyle())
                Button {
                    game.fleetReady()
                } label: {
                    Label(L("Prêt !"), systemImage: "checkmark")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.navale, textColor: Theme.ink, height: 56))
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }
}

struct NavalePlacementGrid: View {
    let game: NavaleGame
    @State private var dragging: Int?
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 10
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            let board = game.boards[game.current]
            ZStack {
                NavaleGrid(board: NavaleBoard(ships: board.ships.filter { $0.id != dragging }), seat: game.current,
                           showShips: true, blasts: [], time: game.time)
                if let id = dragging, let ship = board.ships.first(where: { $0.id == id }) {
                    let preview = moved(ship, cell: cell)
                    Canvas { context, _ in
                        NavaleShipArt.draw(context, ship: preview, origin: origin, cell: cell, sunk: false)
                        let ok = board.fits(preview)
                        let w = CGFloat(preview.horizontal ? preview.length : 1) * cell
                        let h = CGFloat(preview.horizontal ? 1 : preview.length) * cell
                        let frame = CGRect(x: origin.x + CGFloat(preview.x) * cell, y: origin.y + CGFloat(preview.y) * cell, width: w, height: h)
                        context.stroke(Path(roundedRect: frame.insetBy(dx: 2, dy: 2), cornerRadius: 8),
                                       with: .color(ok ? Theme.go : Theme.stop), lineWidth: 3)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragging == nil {
                            let x = Int((value.startLocation.x - origin.x) / cell)
                            let y = Int((value.startLocation.y - origin.y) / cell)
                            guard x >= 0, y >= 0, x < 10, y < 10 else { return }
                            dragging = board.ship(at: y * 10 + x)?.id
                        }
                        offset = value.translation
                    }
                    .onEnded { value in
                        defer {
                            dragging = nil
                            offset = .zero
                        }
                        guard let id = dragging, let ship = board.ships.first(where: { $0.id == id }) else { return }
                        if hypot(value.translation.width, value.translation.height) < 10 {
                            game.rotate(id)
                        } else {
                            let p = moved(ship, cell: cell)
                            game.move(id, x: p.x, y: p.y)
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func moved(_ ship: NavaleShip, cell: CGFloat) -> NavaleShip {
        var s = ship
        s.x += Int((offset.width / cell).rounded())
        s.y += Int((offset.height / cell).rounded())
        return s
    }
}

// MARK: - Passer le Duo

struct NavaleHandover: View {
    let game: NavaleGame

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(Theme.navale)
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.plie(18, weight: .bold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            if game.handoverStage == 2 {
                Button {
                    game.finishHandover()
                } label: {
                    Label(L("C'est moi, \(NavaleGame.playerName(game.handoverTo)) !"), systemImage: "hand.raised.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.navale, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 400)
            } else if game.handoverStage == 0 {
                Button(L("Passer sans fermer")) { game.finishHandover() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 260)
            }
        }
        .padding(24)
    }

    private var icon: String {
        switch game.handoverStage {
        case 0: return "rectangle.portrait.on.rectangle.portrait.fill"
        case 1: return "book.fill"
        default: return "arrow.left.arrow.right"
        }
    }

    private var title: String {
        switch game.handoverStage {
        case 0: return L("Ferme le Duo")
        case 1: return L("\(NavaleGame.playerName(game.handoverTo)), à toi !")
        default: return L("Passe le téléphone à \(NavaleGame.playerName(game.handoverTo))")
        }
    }

    private var detail: String {
        switch game.handoverStage {
        case 0: return L("…et passe-le à \(NavaleGame.playerName(game.handoverTo)), sans regarder ses bateaux.")
        case 1: return L("Ouvre le Duo en L : tes eaux ennemies en haut, ta flotte en bas.")
        default: return L("Pas de triche : on ne regarde pas les bateaux de l'autre.")
        }
    }
}

// MARK: - La bataille

struct NavaleBattle: View {
    let game: NavaleGame

    private var me: Int { game.vsComputer ? 0 : game.current }
    private var enemy: Int { 1 - me }

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.height / 2
            VStack(spacing: 0) {
                // En haut, debout : les eaux ennemies
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Abandonner")) { game.backToMenu() }
                        Text(L("Eaux ennemies"))
                            .font(.plie(18))
                        Spacer()
                        shotsBadge
                    }
                    .padding(.horizontal, 14)
                    NavaleGrid(board: game.boards[enemy], seat: enemy, showShips: false, blasts: game.blasts, time: game.time,
                               radar: game.phase == .aiming && !game.finishing,
                               onTap: canFire ? fireAction : nil)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
                .padding(.top, proxy.safeAreaInsets.top + 4)
                .frame(height: half)
                // En bas, à plat : ma flotte
                VStack(spacing: 6) {
                    statusLine
                        .padding(.top, 8)
                    NavaleGrid(board: game.boards[me], seat: me, showShips: true, blasts: game.blasts, time: game.time)
                        .padding(.horizontal, 14)
                    Text(L("Ta flotte · \(game.boards[me].afloat) bateau\(game.boards[me].afloat > 1 ? "x" : "") à flot"))
                        .font(.plie(14, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.bottom, proxy.safeAreaInsets.bottom + 6)
                .frame(height: half)
            }
            .overlay { banner }
        }
        .ignoresSafeArea()
    }

    private var fireAction: (Int) -> Void {
        { cell in game.fire(cell) }
    }

    private var canFire: Bool {
        game.phase == .aiming && game.shotsLeft > 0 && !game.finishing
    }

    private var shotsBadge: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(game.shotsLeft, 0), id: \.self) { _ in
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .opacity(game.phase == .aiming ? 1 : 0)
        .accessibilityLabel(L("\(game.shotsLeft) tir\(game.shotsLeft > 1 ? "s" : "") restant\(game.shotsLeft > 1 ? "s" : "")"))
    }

    private var statusLine: some View {
        Text(status)
            .font(.plie(17))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    private var status: String {
        if game.finishing { return game.winner == me ? L("Dernier bateau coulé !") : L("Ta flotte est au fond…") }
        if game.phase == .enemyTurn { return L("L'ordinateur tire…") }
        if game.shotsLeft > 0 {
            if !game.vsComputer { return L("\(NavaleGame.playerName(game.current)) : touche une case en haut") }
            return game.shotsLeft > 1 ? L("Feu ! Encore \(game.shotsLeft) tirs") : L("Feu ! Touche une case en haut")
        }
        return game.vsComputer ? L("Tour terminé") : L("Tour terminé : ferme le Duo et passe-le")
    }

    @ViewBuilder
    private var banner: some View {
        if let text = game.banner, game.time - game.bannerAt < 1.8 {
            Text(text)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Fin

struct NavaleOver: View {
    let game: NavaleGame

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 10)
            Image(systemName: winnerIsYou ? "trophy.fill" : "water.waves")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(winnerIsYou ? Theme.gold : Theme.navale)
            Text(title)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(L("Précision : \(game.accuracy[game.winner]) % en \(game.shotsFired[game.winner]) tirs"))
                .font(.plie(17, weight: .bold))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { seat in
                    VStack(spacing: 6) {
                        Text(game.name(seat)).font(.plie(15, weight: .bold))
                        NavaleGrid(board: game.boards[seat], seat: seat, showShips: true, blasts: [], time: game.time)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 640)
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                Button {
                    game.start()
                } label: {
                    Label(L("Revanche"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.navale, textColor: Theme.ink, height: 56))
                Button(L("Menu")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 140)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var winnerIsYou: Bool { !game.vsComputer || game.winner == 0 }

    private var title: String {
        if game.vsComputer { return game.winner == 0 ? L("Victoire ! Flotte ennemie coulée") : L("L'ordinateur a coulé ta flotte") }
        return L("\(NavaleGame.playerName(game.winner)) gagne la bataille !")
    }
}
