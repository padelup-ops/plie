import SwiftUI

extension Theme {
    static let briques = Color(hex: 0x7C83FD)
}

// MARK: - CASSE-BRIQUES
//
// Duo plié en L : le mur de briques est debout sur la moitié haute, la raquette glisse
// sur la moitié posée à plat, et la balle traverse la charnière.

enum BriquesLevel {
    /// Les murs, 10 colonnes : « . » vide, « 1 » brique, « 2 » brique blindée (2 coups),
    /// « # » acier (incassable), « * » brique bonus (lâche une capsule).
    static let patterns: [[String]] = [
        ["..........", "1111111111", "1111111111", "1111111111"],
        ["....11....", "...1111...", "..111111..", ".11111111.", "1111111111"],
        ["2222222222", "1111111111", "1*111111*1", "1111111111"],
        ["1.1.1.1.1.", ".1.1.1.1.1", "1.1.*.1.1.", ".1.1.1.1.1", "1.1.1.1.1."],
        [".11....11.", "1111..1111", "1111111111", "1111*11111", ".11111111.", "..111111..", "...1111...", "....11...."],
        ["#.#.##.#.#", "1111111111", "1222222221", "1211111121", "1211**1121", "1211111121", "1222222221"],
        ["....22....", "...2112...", "..211*12..", ".21111112.", "..211112..", "...2112...", "....22...."],
        ["..1....1..", "...1..1...", "..111111..", ".11.11.11.", "1111111111", "1.11**11.1", "1.1....1.1", "...11.11.."],
        ["2222222222", "#........#", "#.111111.#", "#.1*11*1.#", "#.111111.#", "#........#", "####..####"],
        [".21111112.", "2111111112", "21*1111*12", "2111111112", "2121111212", ".21222212.", "..222222.."],
        ["1.........", "11........", "211.......", "2211......", "22211.....", "222211....", "*222211...", "2222221..."],
        ["2222222222", "2111111112", "21#2222#12", "21#2*12#12", "21#2222#12", "2111111112", "2222222222"],
        ["1....1....", ".1..1.1..1", "..11...11.", "2....2....", ".2..2.2..2", "..22...22.", "*....*...."],
        ["#2#2#2#2#2", "2222222222", "1111111111", "1*11111*11", "1111111111", "..........", "##......##"],
        ["2222222222", "2#22**22#2", "2222222222", "1111111111", "1#1#11#1#1", "1111111111", "2222222222"]
    ]

    static let count = 30
    static let cols = 10

    /// Les niveaux 16 à 30 reprennent les murs, retournés, avec plus de briques blindées et une balle plus rapide.
    static func rows(_ number: Int) -> [String] {
        let n = max(1, min(count, number))
        if n <= patterns.count { return patterns[n - 1] }
        let base = patterns[(n - patterns.count - 1) % patterns.count]
        return base.enumerated().map { index, row in
            let flipped = String(row.reversed())
            return index % 2 == 0 ? flipped.replacingOccurrences(of: "1", with: "2") : flipped
        }
    }

    static func speed(_ number: Int) -> Double {
        min(1.55, 0.92 + Double(number - 1) * 0.022)
    }
}

struct Brick {
    let row: Int
    let col: Int
    var hits: Int
    let steel: Bool
    let bonus: Bool
    var alive = true
}

struct BriquesBall {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
}

struct BriquesCapsule {
    enum Kind: CaseIterable { case wide, multi, slow, life }
    let kind: Kind
    var x: Double
    var y: Double
}

struct BriquesShard {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    let color: Int
}

@Observable
final class BriquesGame {
    enum Phase: Equatable { case menu, ready, playing, won, lost }

    static let brickH = 0.05
    static let top = 0.16
    static let ballR = 0.016
    static let paddleH = 0.026

    private(set) var phase: Phase = .menu
    private(set) var level = 1
    private(set) var bricks: [Brick] = []
    private(set) var balls: [BriquesBall] = []
    private(set) var capsules: [BriquesCapsule] = []
    private(set) var shards: [BriquesShard] = []
    private(set) var paddleX = 0.5
    private(set) var lives = 3
    private(set) var lostLives = 0
    private(set) var score = 0
    private(set) var wideTime = 0.0
    private(set) var slowTime = 0.0
    /// Hauteur du terrain (la largeur vaut 1).
    var height = 1.3

    @ObservationIgnored private var target = 0.5
    #if DEBUG
    /// Démo : la raquette suit la balle toute seule.
    @ObservationIgnored var autopilot = false

    func demoMulti() { apply(.multi) }
    #endif
    @ObservationIgnored private var baseSpeed = 0.92

    var paddleW: Double { wideTime > 0 ? 0.3 : 0.19 }
    var paddleY: Double { height - 0.11 }
    var brickW: Double { 1.0 / Double(BriquesLevel.cols) }
    var stars: Int { lostLives == 0 ? 3 : (lostLives == 1 ? 2 : 1) }

    func start(_ number: Int) {
        level = number
        baseSpeed = BriquesLevel.speed(number)
        bricks = []
        for (r, line) in BriquesLevel.rows(number).enumerated() {
            for (c, ch) in line.enumerated() where ch != "." && c < BriquesLevel.cols {
                bricks.append(Brick(row: r, col: c, hits: ch == "2" ? 2 : 1, steel: ch == "#", bonus: ch == "*"))
            }
        }
        lives = 3
        lostLives = 0
        score = 0
        capsules = []
        shards = []
        wideTime = 0
        slowTime = 0
        resetBall()
    }

    func backToMenu() {
        phase = .menu
    }

    private func resetBall() {
        balls = [BriquesBall(x: paddleX, y: paddleY - Self.paddleH / 2 - Self.ballR, vx: 0, vy: 0)]
        phase = .ready
    }

    /// Le doigt sur la moitié du bas : la raquette le suit.
    func aim(_ x: Double) {
        target = min(1, max(0, x))
    }

    func launch() {
        guard phase == .ready, !balls.isEmpty else { return }
        let angle = Double.random(in: -0.45...0.45)
        balls[0].vx = baseSpeed * sin(angle)
        balls[0].vy = -baseSpeed * cos(angle)
        phase = .playing
        SoundPlayer.shared.play(.pok, volume: 0.6)
    }

    func brickRect(_ b: Brick) -> CGRect {
        let gap = 0.006
        return CGRect(x: Double(b.col) * brickW + gap, y: Self.top + Double(b.row) * Self.brickH + gap,
                      width: brickW - gap * 2, height: Self.brickH - gap * 2)
    }

    // MARK: Un pas de jeu (1/60 s)

    func tick(dt: Double) {
        guard phase == .ready || phase == .playing else {
            ageShards(dt)
            return
        }
        #if DEBUG
        if autopilot, let low = balls.filter({ $0.vy > 0 }).max(by: { $0.y < $1.y }) ?? balls.first {
            target = low.x + 0.05 * sin(Double(score) * 0.7)
        }
        #endif
        // La raquette rattrape le doigt, vite mais sans téléporter.
        let half = paddleW / 2
        let goal = min(1 - half, max(half, target))
        paddleX += (goal - paddleX) * min(1, dt * 22)
        if wideTime > 0 { wideTime = max(0, wideTime - dt) }
        if slowTime > 0 { slowTime = max(0, slowTime - dt) }

        if phase == .ready {
            balls[0].x = paddleX
            balls[0].y = paddleY - Self.paddleH / 2 - Self.ballR
            ageShards(dt)
            return
        }

        let factor = slowTime > 0 ? 0.72 : 1.0
        let steps = 3
        for _ in 0..<steps {
            for i in balls.indices { moveBall(i, dt: dt / Double(steps) * factor) }
        }
        balls.removeAll { $0.y > height + 0.1 }
        if balls.isEmpty {
            loseLife()
            return
        }

        // Capsules
        for i in capsules.indices { capsules[i].y += 0.33 * dt }
        let pr = CGRect(x: paddleX - paddleW / 2, y: paddleY - Self.paddleH / 2, width: paddleW, height: Self.paddleH)
        var caught: [BriquesCapsule.Kind] = []
        capsules.removeAll { c in
            if pr.insetBy(dx: -0.02, dy: -0.02).contains(CGPoint(x: c.x, y: c.y)) {
                caught.append(c.kind)
                return true
            }
            return c.y > height + 0.05
        }
        for kind in caught { apply(kind) }
        ageShards(dt)

        if !bricks.contains(where: { $0.alive && !$0.steel }) {
            phase = .won
            score += lives * 100
            SoundPlayer.shared.play(.win, volume: 0.8)
            Haptics.success()
        }
    }

    private func ageShards(_ dt: Double) {
        guard !shards.isEmpty else { return }
        for i in shards.indices {
            shards[i].x += shards[i].vx * dt
            shards[i].y += shards[i].vy * dt
            shards[i].vy += 1.6 * dt
            shards[i].life -= dt
        }
        shards.removeAll { $0.life <= 0 }
    }

    private func moveBall(_ i: Int, dt: Double) {
        var b = balls[i]
        b.x += b.vx * dt
        b.y += b.vy * dt
        let r = Self.ballR
        // Les murs
        if b.x < r { b.x = r; b.vx = abs(b.vx); SoundPlayer.shared.play(.tock, volume: 0.25) }
        if b.x > 1 - r { b.x = 1 - r; b.vx = -abs(b.vx); SoundPlayer.shared.play(.tock, volume: 0.25) }
        if b.y < r + 0.02 { b.y = r + 0.02; b.vy = abs(b.vy); SoundPlayer.shared.play(.tock, volume: 0.25) }

        // La raquette
        let px = paddleX, pw = paddleW, py = paddleY
        if b.vy > 0 && b.y + r >= py - Self.paddleH / 2 && b.y - r <= py + Self.paddleH / 2 &&
            b.x >= px - pw / 2 - r && b.x <= px + pw / 2 + r {
            let hit = max(-1, min(1, (b.x - px) / (pw / 2)))
            let angle = hit * 1.05
            let speed = (b.vx * b.vx + b.vy * b.vy).squareRoot()
            b.vx = speed * sin(angle)
            b.vy = -speed * cos(angle)
            b.y = py - Self.paddleH / 2 - r
            SoundPlayer.shared.play(.clack, volume: 0.5)
            Haptics.tap()
        }

        // Les briques : un seul rebond par pas
        if b.y - r < Self.top + Self.brickH * 9 {
            for k in bricks.indices where bricks[k].alive {
                let rect = brickRect(bricks[k])
                let x0 = Double(rect.minX), x1 = Double(rect.maxX), y0 = Double(rect.minY), y1 = Double(rect.maxY)
                let cx: Double = min(max(b.x, x0), x1)
                let cy: Double = min(max(b.y, y0), y1)
                let dx = b.x - cx, dy = b.y - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                // De quel côté ?
                let overlapX: Double = min(b.x + r - x0, x1 - (b.x - r))
                let overlapY: Double = min(b.y + r - y0, y1 - (b.y - r))
                if overlapX < overlapY {
                    b.vx = b.x < (x0 + x1) / 2 ? -abs(b.vx) : abs(b.vx)
                } else {
                    b.vy = b.y < (y0 + y1) / 2 ? -abs(b.vy) : abs(b.vy)
                }
                hitBrick(k)
                break
            }
        }
        balls[i] = b
    }

    private func hitBrick(_ k: Int) {
        if bricks[k].steel {
            SoundPlayer.shared.play(.tock, volume: 0.5)
            return
        }
        bricks[k].hits -= 1
        if bricks[k].hits > 0 {
            SoundPlayer.shared.play(.tock, volume: 0.6)
            score += 5
            return
        }
        bricks[k].alive = false
        score += bricks[k].bonus ? 50 : 10
        SoundPlayer.shared.play(.pok, volume: 0.6)
        let rect = brickRect(bricks[k])
        for s in 0..<6 {
            shards.append(BriquesShard(x: Double(rect.midX), y: Double(rect.midY),
                                       vx: Double.random(in: -0.5...0.5), vy: Double.random(in: -0.6...0.1),
                                       life: 0.5 + Double(s) * 0.03, color: bricks[k].row))
        }
        if bricks[k].bonus {
            let kinds: [BriquesCapsule.Kind] = [.wide, .wide, .multi, .multi, .slow, .life]
            capsules.append(BriquesCapsule(kind: kinds.randomElement() ?? .wide, x: Double(rect.midX), y: Double(rect.midY)))
        }
    }

    private func apply(_ kind: BriquesCapsule.Kind) {
        SoundPlayer.shared.play(.chime, volume: 0.7)
        Haptics.success()
        switch kind {
        case .wide:
            wideTime = 15
        case .slow:
            slowTime = 10
        case .life:
            lives = min(5, lives + 1)
        case .multi:
            guard let b = balls.first else { return }
            let speed = max(baseSpeed, (b.vx * b.vx + b.vy * b.vy).squareRoot())
            for angle in [-0.6, 0.6] {
                balls.append(BriquesBall(x: b.x, y: b.y, vx: speed * sin(angle), vy: -speed * cos(angle)))
            }
        }
    }

    private func loseLife() {
        lives -= 1
        lostLives += 1
        capsules = []
        wideTime = 0
        slowTime = 0
        SoundPlayer.shared.play(.wrong, volume: 0.7)
        Haptics.error()
        if lives <= 0 {
            phase = .lost
        } else {
            resetBall()
        }
    }
}

// MARK: - Écran

struct BriquesView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var game = BriquesGame()

    var body: some View {
        ZStack {
            BriquesBackdrop()
            switch game.phase {
            case .menu:
                menu
            default:
                play
            }
        }
        .foregroundStyle(.white)
        .onFrame { dt in game.tick(dt: dt) }
        .onChange(of: game.phase) { _, phase in
            if phase == .won { app.recordBriques(game.level, stars: game.stars) }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("briques", [(0.0, { game.start(5); game.autopilot = true }), (0.8, { game.launch() }),
                                      (2.4, { game.demoMulti() })])
            #endif
        }
    }

    // MARK: Menu

    /// Plié en L : le titre sur la moitié debout, les niveaux sur la moitié à plat (rien sur la charnière).
    private var menu: some View {
        HingeSplit {
            VStack(spacing: 14) {
                GameHeader(title: L("CASSE-BRIQUES"),
                           subtitle: L("\(app.briquesStars.count) / \(BriquesLevel.count) niveaux"),
                           onBack: { app.route = .hub }) {
                    HowToButton(game: .briques)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Image(systemName: "square.grid.3x2.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.briques)
                Text(L("Plie le Duo en L : le mur debout, la raquette sur la moitié posée à plat. Casse toutes les briques sans laisser tomber la balle !"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        } bottom: {
            VStack(spacing: 12) {
                SectionTitle(text: L("Les niveaux"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(1...BriquesLevel.count, id: \.self) { n in
                        levelButton(n)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 680)
        }
    }

    private func levelButton(_ n: Int) -> some View {
        let done = app.briquesStars[n] != nil
        let needsPass = app.briquesNeedsPass(n, hasPass: store.hasEverything)
        let unlocked = app.briquesIsUnlocked(n, hasPass: store.hasEverything)
        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                game.start(n)
            }
        } label: {
            VStack(spacing: 5) {
                if unlocked {
                    Text(verbatim: "\(n)").font(.plie(22)).foregroundStyle(.white)
                    StarsView(count: app.briquesStars[n] ?? 0, size: 10)
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                    Text(verbatim: "\(n)").font(.plie(12, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(LevelTile(done: done, accent: Theme.briques, cornerRadius: 16))
        }
        .buttonStyle(PressableStyle())
        .disabled(!unlocked && !needsPass)
        .accessibilityLabel(unlocked ? L("Niveau \(n)") : (needsPass ? L("Niveau \(n), avec le Pass") : L("Niveau \(n), verrouillé")))
    }

    // MARK: Partie

    private var play: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                BriquesField(game: game)
                    .onAppear { game.height = Double(size.height / max(1, size.width)) }
                    .onChange(of: size) { _, s in game.height = Double(s.height / max(1, s.width)) }
                VStack {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                        HowToButton(game: .briques)
                        Text(L("Niveau \(game.level)")).font(.plie(17))
                        Spacer()
                        Text(verbatim: "\(game.score)").font(.plie(20)).monospacedDigit()
                        HStack(spacing: 3) {
                            ForEach(0..<max(0, game.lives), id: \.self) { _ in
                                Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.coral)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("\(game.lives) vies"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, max(8, proxy.safeAreaInsets.top))
                    Spacer()
                    if game.phase == .ready {
                        Text(L("Glisse le doigt en bas pour bouger la raquette, touche pour lancer"))
                            .font(.plie(17, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(.bottom, size.height * 0.2)
                            .allowsHitTesting(false)
                    }
                }
                if game.phase == .won || game.phase == .lost {
                    result
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        game.aim(Double(v.location.x / max(1, size.width)))
                    }
                    .onEnded { v in
                        if abs(v.translation.width) < 12 && abs(v.translation.height) < 12 { game.launch() }
                    }
            )
        }
        .ignoresSafeArea()
    }

    /// Le résultat s'affiche sur la moitié à plat, sous les doigts, pas sur la charnière.
    private var result: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            LowerHalf {
            VStack(spacing: 12) {
                Text(game.phase == .won ? L("Mur détruit !") : L("Plus de balles…"))
                    .font(.paperTitle(32))
                if game.phase == .won {
                    StarsView(count: game.stars, size: 30)
                }
                Text(L("Score : \(game.score)")).font(.plie(20)).foregroundStyle(Theme.star)
                if game.phase == .won && game.level < BriquesLevel.count {
                    Button {
                        let next = game.level + 1
                        if app.briquesNeedsPass(next, hasPass: store.hasEverything) {
                            app.showPass = true
                        } else {
                            game.start(next)
                        }
                    } label: {
                        Label(L("Niveau suivant"), systemImage: "arrow.right")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.briques, textColor: Theme.ink, height: 56))
                }
                Button(game.phase == .won ? L("Rejouer") : L("Réessayer")) { game.start(game.level) }
                    .buttonStyle(GhostButtonStyle())
                Button(L("Les niveaux")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 380)
            .winCard(accent: game.phase == .won ? Theme.briques : Theme.coral)
            .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Le terrain (dessiné en une fois, à chaque image)

struct BriquesField: View {
    let game: BriquesGame

    static let rowColors: [UInt32] = [0xFF5C8A, 0xFF8A3D, 0xFFC53D, 0x8BDB4F, 0x2FD08C, 0x3DE0FF, 0x5B8CFF, 0xB06BFF]

    var body: some View {
        Canvas { context, size in
            let s = size.width
            func rect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s) }

            // La charnière, au milieu de l'écran
            var hinge = Path()
            hinge.move(to: CGPoint(x: 0, y: size.height / 2))
            hinge.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(hinge, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 2, dash: [8, 10]))

            // Briques
            for b in game.bricks where b.alive {
                let r = rect(game.brickRect(b))
                let path = Path(roundedRect: r, cornerRadius: r.height * 0.22)
                if b.steel {
                    context.fill(path, with: .linearGradient(Gradient(colors: [Color(hex: 0xC9CED8), Color(hex: 0x7A8091)]),
                                                             startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.minX, y: r.maxY)))
                    for dx in [0.18, 0.82] {
                        context.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * dx - 2, y: r.midY - 2, width: 4, height: 4)), with: .color(Color(hex: 0x4A4F5C)))
                    }
                } else {
                    let base = Color(hex: Self.rowColors[b.row % Self.rowColors.count])
                    context.fill(path, with: .linearGradient(Gradient(colors: [base, base.opacity(0.72)]),
                                                             startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.minX, y: r.maxY)))
                    context.fill(Path(roundedRect: CGRect(x: r.minX + 3, y: r.minY + 2, width: r.width - 6, height: r.height * 0.28), cornerRadius: 2),
                                 with: .color(.white.opacity(0.3)))
                    if b.hits >= 2 {
                        context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 2.5)
                    }
                    if b.bonus {
                        context.draw(Text(verbatim: "★").font(.system(size: r.height * 0.7, weight: .black)).foregroundColor(.white), at: CGPoint(x: r.midX, y: r.midY))
                    }
                }
            }

            // Éclats
            for sh in game.shards {
                let c = Color(hex: Self.rowColors[sh.color % Self.rowColors.count]).opacity(max(0, sh.life * 1.6))
                context.fill(Path(CGRect(x: CGFloat(sh.x) * s - 3, y: CGFloat(sh.y) * s - 3, width: 6, height: 6)), with: .color(c))
            }

            // Capsules
            for c in game.capsules {
                let r = CGRect(x: CGFloat(c.x) * s - s * 0.045, y: CGFloat(c.y) * s - s * 0.018, width: s * 0.09, height: s * 0.036)
                let (color, letter): (Color, String) = {
                    switch c.kind {
                    case .wide: return (Theme.go, "↔")
                    case .multi: return (Theme.laser, "×3")
                    case .slow: return (Theme.gold, "≈")
                    case .life: return (Theme.coral, "♥")
                    }
                }()
                context.fill(Path(roundedRect: r, cornerRadius: r.height / 2), with: .color(color))
                context.draw(Text(verbatim: letter).font(.system(size: r.height * 0.7, weight: .black, design: .rounded)).foregroundColor(Theme.ink),
                             at: CGPoint(x: r.midX, y: r.midY))
            }

            // Raquette
            let pw = CGFloat(game.paddleW) * s, ph = CGFloat(BriquesGame.paddleH) * s
            let pr = CGRect(x: CGFloat(game.paddleX) * s - pw / 2, y: CGFloat(game.paddleY) * s - ph / 2, width: pw, height: ph)
            context.fill(Path(roundedRect: pr.insetBy(dx: -6, dy: -6), cornerRadius: ph), with: .color(Theme.briques.opacity(0.18)))
            context.fill(Path(roundedRect: pr, cornerRadius: ph / 2),
                         with: .linearGradient(Gradient(colors: [.white, Theme.briques]), startPoint: CGPoint(x: pr.minX, y: pr.minY), endPoint: CGPoint(x: pr.minX, y: pr.maxY)))

            // Balles (halo en dégradé : pas de flou)
            let br = CGFloat(BriquesGame.ballR) * s
            for b in game.balls {
                let c = CGPoint(x: CGFloat(b.x) * s, y: CGFloat(b.y) * s)
                context.fill(Path(ellipseIn: CGRect(x: c.x - br * 3, y: c.y - br * 3, width: br * 6, height: br * 6)),
                             with: .radialGradient(Gradient(colors: [Theme.laser.opacity(0.45), Theme.laser.opacity(0)]), center: c, startRadius: br, endRadius: br * 3))
                context.fill(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)), with: .color(.white))
            }
        }
        .accessibilityLabel(L("Le mur de briques et la raquette"))
    }
}

/// Fond sombre, légèrement bleuté. Dessiné une fois.
struct BriquesBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x10123A), Color(hex: 0x070818)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
