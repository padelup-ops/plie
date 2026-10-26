import SwiftUI

extension Theme {
    static let sillage = Color(hex: 0x2EF2FF)
    static let sillageA = Color(hex: 0x2EF2FF)
    static let sillageB = Color(hex: 0xFF3DB8)
}

// MARK: - SILLAGE
//
// Duo ouvert à plat entre deux joueurs. Chacun pilote une moto de lumière qui laisse un mur derrière elle.
// On glisse le doigt sur sa moitié pour tourner, on touche pour un coup de turbo.
// Le premier qui se cogne (bord, mur, sillage) perd la manche. Seul : contre l'ordinateur.

struct SillageCell: Hashable {
    var x: Int
    var y: Int

    func moved(_ d: SwipeDirection) -> SillageCell { SillageCell(x: x + d.dx, y: y + d.dy) }
}

struct SillageRider {
    var head: SillageCell
    var dir: SwipeDirection
    var alive = true
    /// Le départ du mur, puis chaque virage : de quoi dessiner le sillage en quelques segments.
    var corners: [SillageCell]
    var queue: [SwipeDirection] = []
    /// Fraction de case déjà parcourue vers la case suivante (pour un mouvement fluide).
    var progress: Double = 0
    var turbo = 3
    var turboLeft: Double = 0
}

struct SillageSpark {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    var seat: Int
}

@Observable
final class SillageGame {
    enum Phase: Equatable { case menu, countdown, running, crash, over }

    static let cols = 26

    var rows = 38
    var vsComputer = false
    var level = 2
    var target = 3

    private(set) var phase: Phase = .menu
    private(set) var riders: [SillageRider] = []
    private(set) var walls: Set<SillageCell> = []
    private(set) var score = [0, 0]
    private(set) var countdown: Double = 0
    /// Gagnant de la dernière manche (nil : égalité).
    private(set) var roundWinner: Int?
    private(set) var matchWinner = 0
    private(set) var sparks: [SillageSpark] = []
    private(set) var crashAt: SillageCell?
    private(set) var crashTime: Double = 0
    private(set) var time: Double = 0
    private(set) var round = 0
    private(set) var paused = false
    private(set) var folded = false

    @ObservationIgnored private var grid: [UInt8] = []
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var lastTurnSound: Double = 0

    var isPaused: Bool { paused || folded }

    func name(_ seat: Int) -> String {
        if vsComputer { return seat == 0 ? L("Toi") : L("Ordi") }
        return seat == 0 ? L("Bleu") : L("Rose")
    }

    static func color(_ seat: Int) -> Color { seat == 0 ? Theme.sillageA : Theme.sillageB }

    // MARK: Partie

    func start() {
        score = [0, 0]
        round = 0
        paused = false
        startRound()
    }

    func backToMenu() {
        phase = .menu
        paused = false
        sparks = []
    }

    func togglePause() {
        guard phase == .running || phase == .countdown else { return }
        paused.toggle()
    }

    func setFolded(_ f: Bool) {
        if folded != f { folded = f }
    }

    private func startRound() {
        round += 1
        let rows = self.rows
        let cols = Self.cols
        grid = Array(repeating: 0, count: cols * rows)
        walls = round == 1 ? [] : Self.arena(Int.random(in: 1...4), cols: cols, rows: rows)
        for w in walls { grid[w.y * cols + w.x] = 3 }
        let x0 = cols / 2 - 1
        let a = SillageCell(x: x0, y: rows - 3)
        let b = SillageCell(x: cols - 1 - x0, y: 2)
        // On dégage la route devant chaque moto.
        for k in 0..<8 {
            clear(SillageCell(x: a.x, y: a.y - k))
            clear(SillageCell(x: b.x, y: b.y + k))
        }
        riders = [SillageRider(head: a, dir: .up, corners: [a]), SillageRider(head: b, dir: .down, corners: [b])]
        grid[a.y * cols + a.x] = 1
        grid[b.y * cols + b.x] = 2
        sparks = []
        crashAt = nil
        roundWinner = nil
        elapsed = 0
        countdown = 3
        phase = .countdown
        SoundPlayer.shared.play(.whoosh, volume: 0.5)
    }

    private func clear(_ c: SillageCell) {
        guard inside(c) else { return }
        walls.remove(c)
        grid[c.y * Self.cols + c.x] = 0
    }

    func inside(_ c: SillageCell) -> Bool { c.x >= 0 && c.y >= 0 && c.x < Self.cols && c.y < rows }

    private func free(_ c: SillageCell) -> Bool { inside(c) && grid[c.y * Self.cols + c.x] == 0 }

    /// Les obstacles, toujours symétriques (un demi-tour de l'écran) : aucun joueur n'est avantagé.
    static func arena(_ kind: Int, cols: Int, rows: Int) -> Set<SillageCell> {
        var cells: [SillageCell] = []
        switch kind {
        case 1: // quatre piliers
            for (fx, fy) in [(0.26, 0.28), (0.74, 0.28)] {
                let cx = Int(Double(cols) * fx), cy = Int(Double(rows) * fy)
                for dx in 0..<2 { for dy in 0..<2 { cells.append(SillageCell(x: cx + dx, y: cy + dy)) } }
            }
        case 2: // deux barrières décalées
            let y = Int(Double(rows) * 0.34)
            for x in 2..<(cols / 2 - 2) { cells.append(SillageCell(x: x, y: y)) }
        case 3: // une croix au milieu, à cheval sur la charnière
            let cx = cols / 2, cy = rows / 2
            for k in 1...4 {
                cells.append(SillageCell(x: cx - 1 - k, y: cy))
                cells.append(SillageCell(x: cx - 1, y: cy - k))
            }
            cells.append(SillageCell(x: cx - 1, y: cy))
            cells.append(SillageCell(x: cx - 1, y: cy - 1))
        default: // couloirs
            let x = cols / 3
            for y in Int(Double(rows) * 0.18)..<Int(Double(rows) * 0.4) { cells.append(SillageCell(x: x, y: y)) }
        }
        var set = Set(cells)
        for c in cells { set.insert(SillageCell(x: cols - 1 - c.x, y: rows - 1 - c.y)) }
        return set.filter { $0.x >= 0 && $0.y >= 0 && $0.x < cols && $0.y < rows }
    }

    // MARK: Commandes

    func steer(_ seat: Int, _ d: SwipeDirection) {
        guard phase == .running || phase == .countdown, seat < riders.count, riders[seat].alive else { return }
        if vsComputer && seat == 1 { return }
        var r = riders[seat]
        let last = r.queue.last ?? r.dir
        guard d != last, d != last.opposite, r.queue.count < 2 else { return }
        r.queue.append(d)
        riders[seat] = r
    }

    func boost(_ seat: Int) {
        guard phase == .running, !isPaused, seat < riders.count, riders[seat].alive else { return }
        if vsComputer && seat == 1 { return }
        guard riders[seat].turbo > 0, riders[seat].turboLeft <= 0 else { return }
        riders[seat].turbo -= 1
        riders[seat].turboLeft = 0.9
        SoundPlayer.shared.play(.swish, volume: 0.7)
        Haptics.tap()
    }

    // MARK: Horloge

    func tick(_ dt: Double) {
        switch phase {
        case .menu, .over:
            if !sparks.isEmpty { updateSparks(dt) }
            return
        case .countdown:
            if isPaused { return }
            time += dt
            let before = Int(ceil(countdown))
            countdown -= dt
            if Int(ceil(countdown)) != before && countdown > 0 { SoundPlayer.shared.play(.clockTick, volume: 0.8) }
            if countdown <= 0 {
                phase = .running
                SoundPlayer.shared.play(.go, volume: 0.8)
                Haptics.tap()
            }
        case .running:
            if isPaused { return }
            time += dt
            elapsed += dt
            run(dt)
        case .crash:
            time += dt
            crashTime += dt
            updateSparks(dt)
            if crashTime > 1.9 { endRound() }
        }
    }

    private func run(_ dt: Double) {
        let base = 8.5 + min(7, elapsed * 0.16)
        for i in 0..<riders.count where riders[i].alive {
            var mult = 1.0
            if riders[i].turboLeft > 0 {
                riders[i].turboLeft = max(0, riders[i].turboLeft - dt)
                mult = 1.8
            }
            riders[i].progress += dt * base * mult
        }
        var loops = 0
        while phase == .running && loops < 6 {
            let m0 = riders[0].alive && riders[0].progress >= 1
            let m1 = riders[1].alive && riders[1].progress >= 1
            if !m0 && !m1 { break }
            step(move0: m0, move1: m1)
            loops += 1
        }
    }

    private func step(move0: Bool, move1: Bool) {
        let moving = [move0, move1]
        if vsComputer && move1 { think() }
        var next: [SillageCell] = riders.map { $0.head }
        for i in 0..<2 where moving[i] {
            var r = riders[i]
            while let q = r.queue.first {
                r.queue.removeFirst()
                if q != r.dir && q != r.dir.opposite {
                    r.corners.append(r.head)
                    r.dir = q
                    if time - lastTurnSound > 0.06 {
                        lastTurnSound = time
                        SoundPlayer.shared.play(.zap, volume: 0.35)
                    }
                    break
                }
            }
            riders[i] = r
            next[i] = r.head.moved(r.dir)
        }
        var crashed = [false, false]
        for i in 0..<2 where moving[i] {
            if !free(next[i]) { crashed[i] = true }
        }
        if move0 && move1 {
            if next[0] == next[1] { crashed = [true, true] }
            if next[0] == riders[1].head && next[1] == riders[0].head { crashed = [true, true] }
        }
        for i in 0..<2 where moving[i] && !crashed[i] {
            riders[i].head = next[i]
            riders[i].progress -= 1
            grid[next[i].y * Self.cols + next[i].x] = UInt8(i + 1)
        }
        if crashed[0] || crashed[1] { crash(crashed) }
    }

    private func crash(_ crashed: [Bool]) {
        for i in 0..<2 where crashed[i] {
            riders[i].alive = false
            riders[i].progress = 0.35
            explode(i)
        }
        if crashed[0] && crashed[1] {
            roundWinner = nil
        } else {
            let w = crashed[0] ? 1 : 0
            roundWinner = w
            score[w] += 1
        }
        crashTime = 0
        phase = .crash
        SoundPlayer.shared.play(.boom, volume: 0.8)
        Haptics.chomp()
    }

    private func explode(_ seat: Int) {
        let r = riders[seat]
        let x = Double(r.head.x) + 0.5 + Double(r.dir.dx) * 0.5
        let y = Double(r.head.y) + 0.5 + Double(r.dir.dy) * 0.5
        crashAt = r.head
        for _ in 0..<46 {
            let a = Double.random(in: 0..<(2 * .pi))
            let s = Double.random(in: 2...13)
            sparks.append(SillageSpark(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s, life: Double.random(in: 0.5...1.2), seat: seat))
        }
    }

    private func updateSparks(_ dt: Double) {
        var kept: [SillageSpark] = []
        kept.reserveCapacity(sparks.count)
        for var s in sparks {
            s.life -= dt
            guard s.life > 0 else { continue }
            s.x += s.vx * dt
            s.y += s.vy * dt
            s.vx *= 1 - 2.2 * dt
            s.vy *= 1 - 2.2 * dt
            kept.append(s)
        }
        sparks = kept
    }

    private func endRound() {
        if score.max() ?? 0 >= target {
            matchWinner = score[0] >= target ? 0 : 1
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
            Haptics.success()
        } else {
            startRound()
        }
    }

    // MARK: L'ordinateur

    /// À chaque case, l'ordi compare tout droit, gauche et droite.
    /// Facile : évite juste le mur. Moyen : garde le plus de place. Difficile : prend le territoire à l'autre.
    private func think() {
        var me = riders[1]
        let options = [me.dir, me.dir.turnedLeft, me.dir.turnedRight]
        let safe = options.filter { free(me.head.moved($0)) }
        guard !safe.isEmpty else { return }
        var choice = me.dir
        switch level {
        case 1:
            if !safe.contains(me.dir) || Double.random(in: 0...1) < 0.08 {
                choice = safe.randomElement() ?? me.dir
            }
        case 2:
            var best = -1
            for d in safe {
                let n = reach(from: me.head.moved(d), limit: 500)
                let bonus = d == me.dir ? 1 : 0
                if n * 2 + bonus > best {
                    best = n * 2 + bonus
                    choice = d
                }
            }
        default:
            var best = Int.min
            for d in safe {
                let cell = me.head.moved(d)
                let value = territory(me: cell, other: riders[0].alive ? riders[0].head.moved(riders[0].dir) : riders[0].head)
                let bonus = d == me.dir ? 1 : 0
                if value * 2 + bonus > best {
                    best = value * 2 + bonus
                    choice = d
                }
            }
        }
        if choice != me.dir {
            me.queue = [choice]
        } else {
            me.queue = []
        }
        riders[1] = me
    }

    private func reach(from start: SillageCell, limit: Int) -> Int {
        let cols = Self.cols
        var seen = grid
        var stack = [start]
        seen[start.y * cols + start.x] = 9
        var count = 0
        while let c = stack.popLast(), count < limit {
            count += 1
            for d in SwipeDirection.allCases {
                let n = c.moved(d)
                guard inside(n), seen[n.y * cols + n.x] == 0 else { continue }
                seen[n.y * cols + n.x] = 9
                stack.append(n)
            }
        }
        return count
    }

    /// Cases que j'atteins avant l'autre, moins celles qu'il atteint avant moi.
    private func territory(me: SillageCell, other: SillageCell) -> Int {
        let cols = Self.cols
        let total = cols * rows
        var dist = [[Int]](repeating: [Int](repeating: Int.max, count: total), count: 2)
        let starts = [me, other]
        for k in 0..<2 {
            let s = starts[k]
            guard inside(s) else { continue }
            var queue = [s]
            var head = 0
            dist[k][s.y * cols + s.x] = 0
            while head < queue.count {
                let c = queue[head]
                head += 1
                let dc = dist[k][c.y * cols + c.x]
                for d in SwipeDirection.allCases {
                    let n = c.moved(d)
                    guard inside(n) else { continue }
                    let idx = n.y * cols + n.x
                    guard grid[idx] == 0, dist[k][idx] == Int.max, n != me || k == 0 else { continue }
                    dist[k][idx] = dc + 1
                    queue.append(n)
                }
            }
        }
        var value = 0
        for i in 0..<total {
            let a = dist[0][i], b = dist[1][i]
            if a < b { value += 1 } else if b < a { value -= 1 }
        }
        return value
    }
}

// MARK: - Écran

struct SillageView: View {
    @Environment(AppState.self) private var app
    @State private var game = SillageGame()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: 0x04050E).ignoresSafeArea()
                if game.phase == .menu {
                    menu
                } else {
                    SillageArena(game: game)
                }
            }
            .onAppear { layout(proxy) }
            .onChange(of: proxy.size) { _, _ in layout(proxy) }
        }
        .foregroundStyle(.white)
        .onFrame { dt in game.tick(dt) }
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setFolded(degrees < 120)
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over {
                app.recordSillage(won: game.vsComputer && game.matchWinner == 0)
            }
        }
    }

    /// Autant de lignes que l'écran en permet (un nombre pair : la charnière tombe entre deux lignes).
    private func layout(_ proxy: GeometryProxy) {
        guard game.phase == .menu else { return }
        let w = proxy.size.width
        let h = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let margin = max(proxy.safeAreaInsets.top, proxy.safeAreaInsets.bottom) + 58
        let cell = w / CGFloat(SillageGame.cols)
        var rows = Int(((h - 2 * margin) / cell).rounded(.down))
        rows = max(20, min(60, rows - rows % 2))
        game.rows = rows
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                    HowToButton(game: .sillage)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                SillageLogo()
                    .frame(height: 150)
                    .accessibilityHidden(true)
                Text(L("SILLAGE"))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(3)
                    .shadow(color: Theme.sillageA.opacity(0.8), radius: 6)
                Text(L("Ta moto de lumière laisse un mur derrière elle. Enferme l'autre, ne te cogne pas !"))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Picker(L("Adversaire"), selection: $game.vsComputer) {
                    Text(L("À deux, face à face")).tag(false)
                    Text(L("Contre l'ordi")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if game.vsComputer {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { l in
                            choice(BoardOpponent.levelName(l), selected: game.level == l) { game.level = l }
                        }
                    }
                    .frame(maxWidth: 420)
                }

                HStack(spacing: 8) {
                    choice(L("3 manches"), selected: game.target == 3) { game.target = 3 }
                    choice(L("5 manches"), selected: game.target == 5) { game.target = 5 }
                }
                .frame(maxWidth: 420)

                Button {
                    game.start()
                } label: {
                    Label(L("Jouer"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sillage, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)

                Text(app.sillageWins > 0 ? L("\(app.sillageWins) victoire\(app.sillageWins > 1 ? "s" : "") contre l'ordi") : L("Glisse pour tourner, touche pour le turbo"))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.plie(15, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(selected ? Theme.sillage : Color.white.opacity(0.1)))
                .foregroundStyle(selected ? Theme.ink : .white)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Deux sillages qui se croisent, pour le menu.
struct SillageLogo: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let ctx = context
            func trail(_ points: [CGPoint], _ color: Color) {
                var p = Path()
                p.addLines(points)
                ctx.stroke(p, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)), with: .color(.white))
                }
            }
            let cx = w / 2
            trail([CGPoint(x: cx - 120, y: h * 0.9), CGPoint(x: cx - 120, y: h * 0.35), CGPoint(x: cx + 10, y: h * 0.35), CGPoint(x: cx + 10, y: h * 0.12)], Theme.sillageA)
            trail([CGPoint(x: cx + 120, y: h * 0.1), CGPoint(x: cx + 120, y: h * 0.62), CGPoint(x: cx - 20, y: h * 0.62), CGPoint(x: cx - 20, y: h * 0.86)], Theme.sillageB)
        }
    }
}

// MARK: - L'arène

struct SillageArena: View {
    let game: SillageGame

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let cell = size.width / CGFloat(SillageGame.cols)
            let arenaH = cell * CGFloat(game.rows)
            let origin = CGPoint(x: 0, y: (size.height - arenaH) / 2)
            ZStack {
                SillageGrid(cols: SillageGame.cols, rows: game.rows, cell: cell, origin: origin)
                SillageField(game: game, cell: cell, origin: origin)
                // Les commandes : chaque joueur glisse sur sa moitié de l'écran.
                VStack(spacing: 0) {
                    zone(1)
                    zone(0)
                }
                FaceToFace { seat in
                    SillageHUD(game: game, seat: seat)
                }
                .allowsHitTesting(game.phase == .over)
                HStack {
                    HingeButton(symbol: game.paused ? "play.fill" : "pause.fill", label: L("Pause")) { game.togglePause() }
                        .padding(.leading, 10)
                    Spacer()
                }
                .opacity(game.phase == .over ? 0 : 1)
                if game.paused {
                    pauseCard
                } else if game.folded && (game.phase == .running || game.phase == .countdown) {
                    Text(L("Déplie le Duo à plat pour reprendre"))
                        .font(.plie(18))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func zone(_ seat: Int) -> some View {
        SwipeZone(onSwipe: { d in
            // Repère de l'écran : la moitié du haut n'est pas retournée ici, donc « vers le bas » est bien vers le bas.
            game.steer(seat, d)
        }, onTap: {
            game.boost(seat)
        })
    }

    private var pauseCard: some View {
        VStack(spacing: 12) {
            Text(L("Pause")).font(.plie(28))
            Button {
                game.togglePause()
            } label: {
                Label(L("Reprendre"), systemImage: "play.fill")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.sillage, textColor: Theme.ink, height: 54))
            Button(L("Quitter la partie")) { game.backToMenu() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 320)
        .winCard(accent: Theme.sillage)
    }
}

/// Le quadrillage et la charnière : dessinés une fois, ils ne bougent pas.
struct SillageGrid: View {
    let cols: Int
    let rows: Int
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: origin.x, y: origin.y, width: cell * CGFloat(cols), height: cell * CGFloat(rows))
            context.fill(Path(rect), with: .color(Color(hex: 0x070A1C)))
            var thin = Path()
            for c in 0...cols {
                let x = rect.minX + CGFloat(c) * cell
                thin.move(to: CGPoint(x: x, y: rect.minY))
                thin.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for r in 0...rows {
                let y = rect.minY + CGFloat(r) * cell
                thin.move(to: CGPoint(x: rect.minX, y: y))
                thin.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(thin, with: .color(Color(hex: 0x2EF2FF, opacity: 0.07)), lineWidth: 1)
            // La charnière : une ligne pointillée au milieu
            var hinge = Path()
            hinge.move(to: CGPoint(x: rect.minX, y: rect.midY))
            hinge.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            context.stroke(hinge, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            context.stroke(Path(rect), with: .color(Color(hex: 0x7B5CFF, opacity: 0.7)), lineWidth: 2)
        }
    }
}

/// Les motos, leurs murs de lumière et les étincelles.
struct SillageField: View {
    let game: SillageGame
    let cell: CGFloat
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            _ = game.time
            drawWalls(context)
            for seat in 0..<game.riders.count {
                drawTrail(context, seat: seat)
            }
            drawSparks(context)
        }
    }

    private func center(_ c: SillageCell) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(c.x) + 0.5) * cell, y: origin.y + (CGFloat(c.y) + 0.5) * cell)
    }

    private func drawWalls(_ context: GraphicsContext) {
        guard !game.walls.isEmpty else { return }
        var p = Path()
        for w in game.walls {
            p.addRoundedRect(in: CGRect(x: origin.x + CGFloat(w.x) * cell + 1, y: origin.y + CGFloat(w.y) * cell + 1,
                                        width: cell - 2, height: cell - 2), cornerSize: CGSize(width: 3, height: 3))
        }
        context.fill(p, with: .color(Color(hex: 0x241B5A)))
        context.stroke(p, with: .color(Color(hex: 0x9B7BFF, opacity: 0.8)), lineWidth: 1.2)
    }

    private func drawTrail(_ context: GraphicsContext, seat: Int) {
        let r = game.riders[seat]
        let color = SillageGame.color(seat)
        var points = r.corners.map { center($0) }
        let h = center(r.head)
        let frac = CGFloat(min(0.98, max(0, r.progress)))
        let tip = CGPoint(x: h.x + CGFloat(r.dir.dx) * frac * cell, y: h.y + CGFloat(r.dir.dy) * frac * cell)
        points.append(h)
        points.append(tip)
        var path = Path()
        path.addLines(points)
        let fade: Double = r.alive ? 1 : 0.55
        context.stroke(path, with: .color(color.opacity(0.22 * fade)), style: StrokeStyle(lineWidth: cell * 0.95, lineCap: .square, lineJoin: .miter))
        context.stroke(path, with: .color(color.opacity(fade)), style: StrokeStyle(lineWidth: cell * 0.38, lineCap: .square, lineJoin: .miter))
        context.stroke(path, with: .color(.white.opacity(0.55 * fade)), style: StrokeStyle(lineWidth: max(1, cell * 0.1), lineCap: .square, lineJoin: .miter))
        guard r.alive else { return }
        // La moto : un halo, puis une petite flèche lumineuse
        let glow = cell * (r.turboLeft > 0 ? 2.4 : 1.6)
        context.fill(Path(ellipseIn: CGRect(x: tip.x - glow, y: tip.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]), center: tip, startRadius: 0, endRadius: glow))
        var bike = Path()
        let fx = CGFloat(r.dir.dx), fy = CGFloat(r.dir.dy)
        let nose = CGPoint(x: tip.x + fx * cell * 0.75, y: tip.y + fy * cell * 0.75)
        let left = CGPoint(x: tip.x - fy * cell * 0.42 - fx * cell * 0.35, y: tip.y + fx * cell * 0.42 - fy * cell * 0.35)
        let right = CGPoint(x: tip.x + fy * cell * 0.42 - fx * cell * 0.35, y: tip.y - fx * cell * 0.42 - fy * cell * 0.35)
        bike.move(to: nose)
        bike.addLine(to: left)
        bike.addLine(to: right)
        bike.closeSubpath()
        context.fill(bike, with: .color(.white))
        context.stroke(bike, with: .color(color), lineWidth: 1.5)
    }

    private func drawSparks(_ context: GraphicsContext) {
        guard !game.sparks.isEmpty else { return }
        for s in game.sparks {
            let p = CGPoint(x: origin.x + CGFloat(s.x) * cell, y: origin.y + CGFloat(s.y) * cell)
            let a = min(1, s.life * 1.6)
            let len = CGFloat(hypot(s.vx, s.vy)) * cell * 0.05
            var line = Path()
            line.move(to: p)
            line.addLine(to: CGPoint(x: p.x - CGFloat(s.vx) * cell * 0.05, y: p.y - CGFloat(s.vy) * cell * 0.05))
            context.stroke(line, with: .color(SillageGame.color(s.seat).opacity(a)), style: StrokeStyle(lineWidth: max(1.5, len * 0.25), lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(a)))
        }
        if let c = game.crashAt, game.phase == .crash {
            let p = center(c)
            let k = CGFloat(min(1, game.crashTime / 0.5))
            let radius = cell * (1 + 5 * k)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(.white.opacity(Double(1 - k) * 0.8)), lineWidth: 3)
        }
    }
}

/// Ce que voit chaque joueur sur sa moitié : son nom, ses manches, son turbo, le compte à rebours.
struct SillageHUD: View {
    let game: SillageGame
    let seat: Int

    private var color: Color { SillageGame.color(seat) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            centerMessage
            Spacer(minLength: 0)
            if game.phase == .over && seat == 0 {
                overButtons
                    .padding(.bottom, 8)
            }
            bar
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Text(game.name(seat))
                .font(.plie(17))
                .foregroundStyle(color)
            HStack(spacing: 5) {
                ForEach(0..<game.target, id: \.self) { k in
                    Circle()
                        .fill(k < game.score[seat] ? color : Color.white.opacity(0.15))
                        .frame(width: 11, height: 11)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(game.score[seat]) manche\(game.score[seat] > 1 ? "s" : "") gagnée\(game.score[seat] > 1 ? "s" : "")"))
            Spacer()
            if !(game.vsComputer && seat == 1) && seat < game.riders.count {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(k < game.riders[seat].turbo ? Theme.gold : Color.white.opacity(0.15))
                    }
                }
                .accessibilityLabel(L("Turbo : \(game.riders[seat].turbo)"))
            }
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private var centerMessage: some View {
        switch game.phase {
        case .countdown:
            VStack(spacing: 8) {
                Text("\(max(1, Int(ceil(game.countdown))))")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.8), radius: 8)
                if !(game.vsComputer && seat == 1) {
                    Text(L("Glisse pour tourner · Touche pour le turbo"))
                        .font(.plie(15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        case .crash:
            Text(crashText)
                .font(.plie(26))
                .foregroundStyle(game.roundWinner.map { SillageGame.color($0) } ?? .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.6)))
        case .over:
            VStack(spacing: 6) {
                Text(overText)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(game.matchWinner == seat ? color : .white.opacity(0.7))
                    .shadow(color: color.opacity(game.matchWinner == seat ? 0.8 : 0), radius: 8)
                Text("\(game.score[seat]) – \(game.score[1 - seat])")
                    .font(.plie(22))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.6)))
        default:
            EmptyView()
        }
    }

    private var crashText: String {
        guard let w = game.roundWinner else { return L("Collision ! Égalité") }
        if w == seat { return L("Manche gagnée !") }
        return L("Crash !")
    }

    private var overText: String {
        if game.vsComputer && seat == 1 { return game.matchWinner == 1 ? L("Gagné !") : L("Perdu") }
        return game.matchWinner == seat ? L("Gagné !") : L("Perdu…")
    }

    private var overButtons: some View {
        HStack(spacing: 10) {
            Button {
                game.start()
            } label: {
                Label(L("Revanche"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.sillage, textColor: Theme.ink, height: 50))
            Button(L("Menu")) { game.backToMenu() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 130)
        }
        .padding(.horizontal, 20)
    }
}
