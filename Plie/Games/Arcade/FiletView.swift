import SwiftUI
import Combine

extension Theme {
    static let filet = Color(hex: 0x5B8CFF)
}

// MARK: - Règles et physique
//
// Repère de la table, en mètres : x en travers (0 → 1,525), z dans la longueur
// (0 = ton bout de table, 2,74 = celui de l'adversaire), y = hauteur au-dessus de la table.
// Le filet est en z = 1,37 : pile sur la charnière du Duo plié en L.

struct FVec: Equatable {
    var x: Double
    var y: Double
    var z: Double
}

@Observable
final class FiletGame {
    enum Phase: Equatable {
        case menu, serve, rally, point, over
    }

    enum Level: Int, CaseIterable, Identifiable {
        case beginner = 1, club, champion

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .beginner: return L("Débutant")
            case .club: return L("Joueur de club")
            case .champion: return L("Champion")
            }
        }

        var color: Color {
            switch self {
            case .beginner: return Color(hex: 0x3CCB7F)
            case .club: return Color(hex: 0xFF8A3D)
            case .champion: return Color(hex: 0xA46BFF)
            }
        }

        /// Vitesse de déplacement de l'ordinateur (m/s).
        var speed: Double { [0.85, 1.4, 2.0][rawValue - 1] }
        /// Temps de réaction après ta frappe.
        var reaction: Double { [0.36, 0.22, 0.12][rawValue - 1] }
        /// Durée de vol de ses balles jusqu'au rebond.
        var flight: Double { [1.05, 0.86, 0.72][rawValue - 1] }
        var errorRate: Double { [0.16, 0.08, 0.05][rawValue - 1] }
        var reach: Double { [0.18, 0.2, 0.22][rawValue - 1] }
    }

    struct Ripple: Equatable {
        let x: Double
        let z: Double
        let time: Double
    }

    struct Flash: Equatable {
        let at: FVec
        let time: Double
        let smash: Bool
    }

    static let length = 2.74
    static let width = 1.525
    static let half = 1.37
    static let netHeight = 0.1525
    static let gravity = 3.2
    static let ballRadius = 0.02
    static let batRadius = 0.16
    static let tableHeight = 0.76
    static let winScore = 7
    static let aiZ = length + 0.2

    private(set) var phase: Phase = .menu
    private(set) var level: Level = .beginner
    private(set) var ball = FVec(x: width / 2, y: 0.2, z: -0.1)
    private(set) var velocity = FVec(x: 0, y: 0, z: 0)
    private(set) var bat = FVec(x: width / 2, y: 0, z: -0.25)
    private(set) var batVelocity = FVec(x: 0, y: 0, z: 0)
    private(set) var aiBat = FVec(x: width / 2, y: 0, z: aiZ)
    private(set) var scoreMe = 0
    private(set) var scoreAI = 0
    private(set) var server = 0
    private(set) var message: String?
    private(set) var messageGood = true
    private(set) var messageAt: Double = 0
    private(set) var trail: [FVec] = []
    private(set) var ripples: [Ripple] = []
    private(set) var hitFlash: Flash?
    private(set) var aiSwing: Double = -10
    private(set) var clock: Double = 0
    private(set) var rally = 0
    private(set) var longestRally = 0
    private(set) var won = false

    @ObservationIgnored private var lastHitter = 1
    @ObservationIgnored private var receiverBounces = 0
    @ObservationIgnored private var resolved = false
    @ObservationIgnored private var aiMissed = false
    @ObservationIgnored private var timer: Double = 0
    @ObservationIgnored private var hitTime: Double = 0
    @ObservationIgnored private var batTarget: FVec?

    // MARK: Partie

    func start(level: Level) {
        self.level = level
        scoreMe = 0
        scoreAI = 0
        longestRally = 0
        won = false
        server = 0
        message = nil
        aiBat = FVec(x: Self.width / 2, y: 0, z: Self.aiZ)
        prepareServe()
        SoundPlayer.shared.play(.go)
    }

    func backToMenu() {
        phase = .menu
        message = nil
    }

    /// Position voulue pour ta raquette (coordonnées de la table), ou nil quand le doigt est levé.
    func moveBat(to target: FVec?) {
        batTarget = target
    }

    /// Le doigt se lève : si c'est à toi de servir, la balle part.
    func releaseBat() {
        batTarget = nil
        if phase == .serve && server == 0 && timer > 0.3 {
            playerHit(serve: true)
        }
    }

    private func prepareServe() {
        phase = .serve
        resolved = false
        aiMissed = false
        receiverBounces = 0
        rally = 0
        timer = 0
        trail = []
        velocity = FVec(x: 0, y: 0, z: 0)
        lastHitter = server
        if server == 0 {
            bat = FVec(x: Self.width / 2, y: 0, z: 0.25)
            batVelocity = FVec(x: 0, y: 0, z: 0)
            ball = FVec(x: bat.x, y: 0.2, z: bat.z + 0.04)
        } else {
            aiBat.x = Self.width * Double.random(in: 0.3...0.7)
            ball = FVec(x: aiBat.x, y: 0.22, z: Self.length + 0.1)
        }
    }

    // MARK: Boucle

    func tick(dt: Double) {
        clock += dt
        ripples.removeAll { clock - $0.time > 0.6 }
        if let flash = hitFlash, clock - flash.time > 0.4 { hitFlash = nil }
        if message != nil, phase != .point, clock - messageAt > 1.1 { message = nil }
        guard phase == .serve || phase == .rally || phase == .point else { return }

        updateBat(dt)
        updateAI(dt)

        switch phase {
        case .serve:
            timer += dt
            if server == 0 {
                ball = FVec(x: bat.x, y: 0.2 + 0.05 * sin(clock * 5), z: bat.z + 0.04)
                // Un geste vers le filet sert tout de suite ; sinon la balle part quand le doigt se lève.
                if batVelocity.z > 0.6 && timer > 0.3 { playerHit(serve: true) }
            } else {
                ball = FVec(x: aiBat.x, y: 0.22 + 0.05 * sin(clock * 5), z: Self.length + 0.1)
                if timer > 1.1 { aiHit(serve: true) }
            }
        case .rally, .point:
            let steps = 4
            let h = dt / Double(steps)
            for _ in 0..<steps {
                step(h)
            }
            trail.append(ball)
            if trail.count > 9 { trail.removeFirst(trail.count - 9) }
            if phase == .point {
                timer -= dt
                if timer <= 0 { nextPoint() }
            }
        default:
            break
        }
    }

    private func updateBat(_ dt: Double) {
        if let target = batTarget {
            let maxZ = Self.half - 0.1
            let nx = min(Self.width + 0.6, max(-0.6, target.x))
            let nz = min(maxZ, max(-0.75, target.z))
            let vx = (nx - bat.x) / dt
            let vz = (nz - bat.z) / dt
            batVelocity = FVec(x: batVelocity.x * 0.55 + vx * 0.45, y: 0, z: batVelocity.z * 0.55 + vz * 0.45)
            bat = FVec(x: nx, y: 0, z: nz)
        } else {
            batVelocity = FVec(x: batVelocity.x * 0.8, y: 0, z: batVelocity.z * 0.8)
        }
    }

    /// L'ordinateur suit la balle qui arrive (avec un temps de réaction), puis revient au centre.
    private func updateAI(_ dt: Double) {
        var goal = Self.width / 2
        if phase == .serve && server == 1 {
            goal = aiBat.x
        } else if phase == .rally && lastHitter == 0 && !aiMissed && clock - hitTime > level.reaction && velocity.z > 0.1 {
            let tHit = max(0, (Self.length - 0.05 - ball.z) / velocity.z)
            goal = ball.x + velocity.x * tHit
        }
        let maxStep = level.speed * dt
        aiBat.x += max(-maxStep, min(maxStep, goal - aiBat.x))
        aiBat.x = min(Self.width + 0.5, max(-0.5, aiBat.x))
    }

    private func onTable(_ p: FVec) -> Bool {
        p.x >= -0.005 && p.x <= Self.width + 0.005 && p.z >= 0 && p.z <= Self.length
    }

    private func step(_ h: Double) {
        let previous = ball
        velocity.y -= Self.gravity * h
        ball.x += velocity.x * h
        ball.y += velocity.y * h
        ball.z += velocity.z * h

        guard !resolved else {
            // Le point est joué : la balle finit sa course (rebonds sur la table ou par terre).
            if ball.y <= Self.ballRadius && ball.y > -0.06 && velocity.y < 0 && onTable(ball) {
                ball.y = Self.ballRadius
                velocity.y = -velocity.y * 0.75
                SoundPlayer.shared.play(.tock, volume: 0.35)
            } else if ball.y <= -Self.tableHeight + Self.ballRadius && velocity.y < 0 {
                ball.y = -Self.tableHeight + Self.ballRadius
                velocity.y = -velocity.y * 0.55
                velocity.x *= 0.8
                velocity.z *= 0.8
            }
            return
        }

        // Le filet
        if (previous.z - Self.half) * (ball.z - Self.half) < 0,
           ball.y < Self.netHeight + Self.ballRadius, ball.x > -0.16, ball.x < Self.width + 0.16 {
            ball.z = previous.z
            velocity = FVec(x: velocity.x * 0.3, y: min(0, velocity.y) * 0.2, z: -velocity.z * 0.12)
            SoundPlayer.shared.play(.net, volume: 0.85)
            point(to: 1 - lastHitter, text: L("Filet !"))
            return
        }

        // Rebond sur la table
        if ball.y <= Self.ballRadius && velocity.y < 0 && onTable(ball) {
            ball.y = Self.ballRadius
            velocity.y = -velocity.y * 0.86
            velocity.x *= 0.98
            velocity.z *= 0.98
            ripples.append(Ripple(x: ball.x, z: ball.z, time: clock))
            SoundPlayer.shared.play(.tock, volume: 0.8)
            let side = ball.z < Self.half ? 0 : 1
            if side == lastHitter {
                point(to: 1 - lastHitter, text: L("Faute !"))
            } else {
                receiverBounces += 1
                if receiverBounces >= 2 {
                    point(to: lastHitter, text: lastHitter == 1 ? L("Deux rebonds") : L("Point !"))
                }
            }
            return
        }

        // Sortie
        let fell = ball.y < -0.3
        let away = ball.z < -1.5 || ball.z > Self.length + 1.5 || ball.x < -1.2 || ball.x > Self.width + 1.2
        if fell || away {
            if receiverBounces == 0 {
                point(to: 1 - lastHitter, text: L("Dehors !"))
            } else {
                point(to: lastHitter, text: lastHitter == 1 ? L("Raté !") : L("Point !"))
            }
            return
        }

        // Ta frappe : la balle touche la raquette
        if lastHitter == 1 && velocity.z < 0 && ball.z < Self.half && ball.y < 0.55 {
            let dx = ball.x - bat.x
            let dz = ball.z - bat.z
            let reach = Self.batRadius + Self.ballRadius + 0.02
            if dx * dx + dz * dz < reach * reach {
                playerHit(serve: false)
                return
            }
        }

        // La frappe de l'ordinateur, après un rebond de son côté
        if lastHitter == 0 && !aiMissed && velocity.z > 0 && receiverBounces == 1
            && ball.z >= Self.length - 0.12 && ball.y < 0.7 {
            if abs(ball.x - aiBat.x) <= level.reach {
                aiHit(serve: false)
            } else {
                aiMissed = true
            }
        }
    }

    /// Lance la balle pour qu'elle touche la table en (x, z) au bout de `time` secondes.
    /// Si besoin, la trajectoire monte un peu plus pour passer le filet.
    private func launch(toX x: Double, z: Double, time: Double, mayHitNet: Bool) {
        let g = Self.gravity
        let y0 = ball.y
        var t = time
        if !mayHitNet {
            for _ in 0..<14 {
                let vz = (z - ball.z) / t
                guard vz != 0 else { break }
                let tNet = (Self.half - ball.z) / vz
                guard tNet > 0 else { break }
                let vy = (Self.ballRadius - y0 + 0.5 * g * t * t) / t
                let yNet = y0 + vy * tNet - 0.5 * g * tNet * tNet
                if yNet >= Self.netHeight + 0.05 { break }
                t += 0.04
            }
        }
        velocity = FVec(x: (x - ball.x) / t,
                        y: (Self.ballRadius - y0 + 0.5 * g * t * t) / t,
                        z: (z - ball.z) / t)
    }

    private func playerHit(serve: Bool) {
        let forward = max(0, batVelocity.z)
        var power = min(1.8, forward / 2.4)
        if serve { power = max(0.35, min(power, 1.0)) }
        let high = ball.y > 0.14
        let smash = !serve && power > 0.95 && high
        let noise = 0.05 * (0.5 + power)
        let depth = 0.32 + 0.48 * power + Double.random(in: -noise...noise)
        // Par défaut la balle repart vers la table ; un geste de côté la fait viser un coin.
        let lateral = max(-0.5, min(0.5, batVelocity.x * 0.25)) + (ball.x - bat.x) * 1.4 + Double.random(in: -noise...noise)
        let flight = max(0.45, 0.98 - 0.36 * min(power, 1.25))
        ball.y = max(ball.y, 0.04)
        launch(toX: Self.width / 2 + (ball.x - Self.width / 2) * 0.5 + lateral, z: Self.half + depth * Self.half, time: flight, mayHitNet: power > 0.95 && !high)
        lastHitter = 0
        receiverBounces = 0
        aiMissed = false
        hitTime = clock
        rally += 1
        if phase == .serve { phase = .rally }
        hitFlash = Flash(at: ball, time: clock, smash: smash)
        if smash {
            message = L("Smash !")
            messageGood = true
            messageAt = clock
        }
        SoundPlayer.shared.play(smash ? .smash : .pok, volume: 0.9)
        Haptics.tap()
    }

    private func aiHit(serve: Bool) {
        let incoming = abs(velocity.z)
        var errorChance = serve ? 0.02 : level.errorRate + max(0, incoming - 2.4) * 0.18
        if ball.x < 0.12 || ball.x > Self.width - 0.12 { errorChance += 0.06 }
        if level == .champion { errorChance *= 0.8 }
        let smash = !serve && level != .beginner && ball.y > 0.3
            && Double.random(in: 0...1) < (level == .champion ? 0.7 : 0.35)
        var x: Double
        if level == .champion && Double.random(in: 0...1) < 0.7 {
            // Le champion vise loin de ta raquette.
            x = bat.x < Self.width / 2 ? Self.width * Double.random(in: 0.66...0.9) : Self.width * Double.random(in: 0.1...0.34)
        } else {
            x = Self.width * Double.random(in: 0.14...0.86)
        }
        var z = serve ? Double.random(in: 0.35...0.95) : Double.random(in: 0.22...1.05)
        var flight = serve ? level.flight + 0.12 : level.flight * Double.random(in: 0.88...1.12)
        if smash {
            flight = 0.5
            z = Double.random(in: 0.15...0.5)
        }
        if Double.random(in: 0...1) < errorChance {
            if Bool.random() {
                z = -Double.random(in: 0.1...0.4)
            } else {
                x = Bool.random() ? -Double.random(in: 0.08...0.3) : Self.width + Double.random(in: 0.08...0.3)
            }
        }
        ball.y = max(ball.y, 0.05)
        launch(toX: x, z: z, time: flight, mayHitNet: false)
        lastHitter = 1
        receiverBounces = 0
        hitTime = clock
        aiSwing = clock
        rally += 1
        if phase == .serve { phase = .rally }
        hitFlash = Flash(at: ball, time: clock, smash: smash)
        if smash {
            message = L("Smash de l'ordi !")
            messageGood = false
            messageAt = clock
        }
        SoundPlayer.shared.play(smash ? .smash : .pok, volume: 0.65)
    }

    private func point(to winner: Int, text: String) {
        guard !resolved else { return }
        resolved = true
        if winner == 0 { scoreMe += 1 } else { scoreAI += 1 }
        longestRally = max(longestRally, rally)
        message = text
        messageGood = winner == 0
        messageAt = clock
        phase = .point
        timer = 1.5
        if winner == 0 {
            SoundPlayer.shared.play(.point, volume: 0.7)
            SoundPlayer.shared.play(.applause, volume: Float(min(1, 0.3 + Double(rally) * 0.06)))
            Haptics.correct(subtle: false)
        } else {
            SoundPlayer.shared.play(.wrong, volume: 0.45)
            Haptics.warning()
        }
    }

    private func nextPoint() {
        if max(scoreMe, scoreAI) >= Self.winScore && abs(scoreMe - scoreAI) >= 2 {
            phase = .over
            won = scoreMe > scoreAI
            message = nil
            SoundPlayer.shared.play(won ? .win : .wrong, volume: 0.8)
            if won {
                SoundPlayer.shared.play(.applause, volume: 1)
                Haptics.success()
            }
            return
        }
        // Service : deux points chacun, puis un seul en fin de partie serrée.
        let total = scoreMe + scoreAI
        let tight = scoreMe >= Self.winScore - 1 && scoreAI >= Self.winScore - 1
        server = tight ? total % 2 : (total / 2) % 2
        prepareServe()
    }
}

// MARK: - Projection
//
// Moitié basse (posée à plat) : ton côté de la table vu de dessus.
// Moitié haute (debout quand le Duo est plié en L) : le côté adverse en perspective.
// Les deux se rejoignent sur la charnière, là où se trouve le filet.

struct FiletProjection {
    let size: CGSize
    let fold: CGFloat
    let ppm: CGFloat
    let horizon: CGFloat
    static let depth = 1.9

    init(size: CGSize) {
        self.size = size
        fold = size.height * 0.5
        let byWidth = size.width * 0.6 / CGFloat(FiletGame.width)
        let byHeight = (size.height * 0.5) * 0.72 / CGFloat(FiletGame.half)
        ppm = max(1, min(byWidth, byHeight))
        horizon = size.height * 0.03
    }

    func k(_ z: Double) -> CGFloat {
        CGFloat(Self.depth / (Self.depth + max(0, z - FiletGame.half)))
    }

    func scale(_ z: Double) -> CGFloat {
        z <= FiletGame.half ? 1 : k(z)
    }

    func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let cx = size.width / 2
        if z <= FiletGame.half {
            return CGPoint(x: cx + CGFloat(x - FiletGame.width / 2) * ppm,
                           y: fold + CGFloat(FiletGame.half - z) * ppm - CGFloat(y) * ppm)
        }
        let s = k(z)
        return CGPoint(x: cx + CGFloat(x - FiletGame.width / 2) * ppm * s,
                       y: horizon + (fold - horizon) * s - CGFloat(y) * ppm * s)
    }

    /// Doigt → position de la raquette (un peu au-dessus du doigt pour la voir).
    func table(from p: CGPoint) -> FVec {
        FVec(x: FiletGame.width / 2 + Double((p.x - size.width / 2) / ppm),
             y: 0,
             z: FiletGame.half - Double((p.y - fold) / ppm) + 0.12)
    }
}

// MARK: - Écran

struct FiletView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var game = FiletGame()
    @State private var hingeSeen = false


    var body: some View {
        // La scène occupe tout l'écran : le filet tombe pile sur la charnière, au milieu.
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                ZStack {
                    FiletScene(game: game)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    game.moveBat(to: FiletProjection(size: proxy.size).table(from: value.location))
                                }
                                .onEnded { _ in game.releaseBat() }
                        )
                    if game.phase == .menu || game.phase == .over {
                        if game.phase == .over && game.won {
                            ConfettiView()
                        }
                        menu
                    }
                }
            }
            .ignoresSafeArea()

            GameHeader(title: L("FILET"), subtitle: subtitle, onBack: { app.route = .hub }) {
                if game.phase != .menu {
                    Pill(text: "\(game.scoreMe) – \(game.scoreAI)", color: Theme.filet.opacity(0.25), textColor: Theme.filet)
                }
                HowToButton(game: .filet)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onHingeAngle { degrees in
            if degrees != nil { hingeSeen = true }
        }
        .onFrame { _ in
            let wasOver = game.phase == .over
            game.tick(dt: 1.0 / 60.0)
            if !wasOver && game.phase == .over {
                app.recordFilet(level: game.level.rawValue, won: game.won)
            }
        }
    }

    private var subtitle: String {
        game.phase == .menu ? L("Ping-pong contre l'ordinateur") : L("Contre : \(game.level.name)")
    }

    /// Plié en L, le filet est sur la charnière : le score et l'explication sur la moitié debout,
    /// le choix de l'adversaire sur la moitié à plat. Rien sur la pliure.
    private var menu: some View {
        HingeSplit {
            VStack(spacing: 10) {
                if game.phase == .over {
                    WinIcon(systemName: game.won ? "trophy.fill" : "figure.table.tennis", color: game.won ? Theme.gold : Theme.filet)
                    Text(game.won ? L("Tu as gagné !") : L("L'ordinateur gagne"))
                        .font(.paperTitle(28))
                    Text(L("\(game.scoreMe) – \(game.scoreAI) · plus long échange : \(game.longestRally) coups"))
                        .font(.plie(15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    if game.won {
                        ShareResultButton(game: L("FILET"), result: L("Victoire \(game.scoreMe) – \(game.scoreAI) contre : \(game.level.name)"), accent: Theme.filet)
                    }
                } else {
                    WinIcon(systemName: "figure.table.tennis", color: Theme.filet)
                    Text(L("Le premier à 7 points gagne"))
                        .font(.paperTitle(22))
                        .multilineTextAlignment(.center)
                    Text(hingeSeen
                         ? L("Plie ton iPhone Duo en L et pose-le sur la table : la charnière devient le filet. Ta raquette suit ton doigt sur l'écran du bas, et l'ordinateur renvoie la balle depuis l'écran du haut.")
                         : L("Ta raquette suit ton doigt sur la moitié basse. Pousse vers le filet pour frapper fort, de côté pour viser. Trop fort, et la balle sort !"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(18)
            .frame(maxWidth: 460)
            .winCard(accent: Theme.filet)
            .padding(.horizontal, 16)
            .padding(.top, 56)
        } bottom: {
            VStack(spacing: 10) {
                Text(L("Choisis ton adversaire"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                VStack(spacing: 8) {
                    ForEach(FiletGame.Level.allCases) { level in
                        levelButton(level)
                    }
                }
                .frame(maxWidth: 360)
            }
            .foregroundStyle(Theme.text)
            .padding(18)
            .frame(maxWidth: 460)
            .winCard(accent: Theme.filet)
            .padding(.horizontal, 16)
        }
    }

    private func levelButton(_ level: FiletGame.Level) -> some View {
        let needsPass = app.filetNeedsPass(level.rawValue, hasPass: store.hasEverything)
        let beaten = app.filetBestLevel >= level.rawValue
        return Button {
            if needsPass {
                app.showPass = true
            } else {
                game.start(level: level)
            }
        } label: {
            HStack(spacing: 10) {
                Text(level.name)
                Spacer(minLength: 0)
                if beaten {
                    Image(systemName: "checkmark.seal.fill")
                }
                if needsPass {
                    Image(systemName: "crown.fill")
                }
            }
        }
        .buttonStyle(ChunkyButtonStyle(color: level.color, textColor: level == .champion ? .white : Theme.ink, height: 52))
        .accessibilityLabel(L("Jouer contre : \(level.name)"))
    }
}

// MARK: - Dessin

struct FiletScene: View {
    let game: FiletGame

    var body: some View {
        let ball = game.ball
        let bat = game.bat
        let batVelocity = game.batVelocity
        let ai = game.aiBat
        let trail = game.trail
        let ripples = game.ripples
        let flash = game.hitFlash
        let clock = game.clock
        let message = game.message
        let messageGood = game.messageGood
        let scoreMe = game.scoreMe
        let scoreAI = game.scoreAI
        let server = game.server
        let level = game.level
        let aiSwing = game.aiSwing
        let phase = game.phase
        let serveHint = game.phase == .serve && game.server == 0

        Canvas { context, size in
            let P = FiletProjection(size: size)
            let w = size.width
            let h = size.height
            let fold = P.fold
            let L2 = FiletGame.half
            let W = FiletGame.width
            let floorY = -FiletGame.tableHeight

            // Salle : mur du fond, projecteurs, public, panneaux
            let backZ = FiletGame.length + 2.4
            let wallLine = P.point(0, floorY, backZ).y
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: wallLine)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x0D1030), Color(hex: 0x1E2558)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: wallLine)))
            // Sol de la salle (haut) et de ton côté (bas)
            context.fill(Path(CGRect(x: 0, y: wallLine, width: w, height: fold - wallLine)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x4A1E22), Color(hex: 0x8A3530)]),
                                               startPoint: CGPoint(x: 0, y: wallLine), endPoint: CGPoint(x: 0, y: fold)))
            context.fill(Path(CGRect(x: 0, y: fold, width: w, height: h - fold)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x8A3530), Color(hex: 0xA2443A)]),
                                               startPoint: CGPoint(x: 0, y: fold), endPoint: CGPoint(x: 0, y: h)))
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.1), .clear]),
                                               center: CGPoint(x: w / 2, y: fold), startRadius: 0, endRadius: max(w, h) * 0.6))
            // Projecteurs : des dégradés plutôt qu'un flou recalculé à chaque image (plus fluide).
            do {
                let lights = context
                for k in 0..<3 {
                    let lx = w * (0.22 + 0.28 * CGFloat(k))
                    lights.fill(Path(ellipseIn: CGRect(x: lx - w * 0.09, y: -h * 0.06, width: w * 0.18, height: h * 0.13)),
                                with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF1C9).opacity(0.55), Color(hex: 0xFFF1C9).opacity(0)]),
                                                      center: CGPoint(x: lx, y: h * 0.005), startRadius: 0, endRadius: w * 0.09))
                    var cone = Path()
                    cone.move(to: CGPoint(x: lx - w * 0.02, y: 0))
                    cone.addLine(to: CGPoint(x: lx + w * 0.02, y: 0))
                    cone.addLine(to: CGPoint(x: w / 2 + (lx - w / 2) * 0.4 + w * 0.12, y: fold))
                    cone.addLine(to: CGPoint(x: w / 2 + (lx - w / 2) * 0.4 - w * 0.12, y: fold))
                    cone.closeSubpath()
                    lights.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF1C9).opacity(0.09 + 0.02 * sin(clock * 0.7 + Double(k) * 2)), Color(hex: 0xFFF1C9).opacity(0.02)]),
                                                            startPoint: CGPoint(x: lx, y: 0), endPoint: CGPoint(x: lx, y: fold)))
                }
            }
            // Public (têtes derrière les panneaux)
            let boardZ = FiletGame.length + 1.9
            let boardTop = P.point(0, floorY + 0.75, boardZ).y
            let boardBottom = P.point(0, floorY, boardZ).y
            for i in 0..<46 {
                let px = CGFloat(Draw.hash(i, 31)) * w
                let row = CGFloat(Draw.hash(i, 32))
                let pr = P.ppm * P.k(boardZ + 0.6) * CGFloat(0.12 + 0.03 * Draw.hash(i, 33))
                let py = boardTop - pr * (0.6 + 2.2 * row)
                let cheer = phase == .point && messageGood ? CGFloat(abs(sin(clock * 9 + Double(i)))) * pr * 0.7 : 0
                let tone = Draw.hash(i, 34)
                context.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr - cheer, width: pr * 2, height: pr * 2.3)),
                             with: .color(Color(hex: tone < 0.5 ? 0x3A4378 : 0x4B3A78).opacity(0.85)))
            }
            // Panneaux autour de l'aire de jeu
            let boards = CGRect(x: 0, y: boardTop, width: w, height: boardBottom - boardTop)
            context.fill(Path(boards), with: .linearGradient(Gradient(colors: [Color(hex: 0x1C3F9E), Color(hex: 0x12286A)]),
                                                            startPoint: CGPoint(x: 0, y: boards.minY), endPoint: CGPoint(x: 0, y: boards.maxY)))
            context.fill(Path(CGRect(x: 0, y: boardTop, width: w, height: max(1, boards.height * 0.08))), with: .color(.white.opacity(0.25)))
            let logoSize = max(8, boards.height * 0.5)
            var lx: CGFloat = w * 0.12
            var flip = false
            while lx < w {
                context.draw(Text(verbatim: flip ? "FILET" : "ORIGAMO").font(.system(size: logoSize, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.55)),
                             at: CGPoint(x: lx, y: boards.midY))
                lx += max(70, logoSize * 6)
                flip.toggle()
            }

            // Tableau des scores
            let card = min(w * 0.07, max(18, (boardTop - h * 0.02) * 0.5))
            let sbY = max(card * 0.65, boardTop * 0.32)
            for (i, value) in [scoreMe, scoreAI].enumerated() {
                let cx = w / 2 + (i == 0 ? -1 : 1) * card * 0.72
                let rect = CGRect(x: cx - card * 0.6, y: sbY - card * 0.62, width: card * 1.2, height: card * 1.24)
                context.fill(Path(roundedRect: rect, cornerRadius: card * 0.16),
                             with: .linearGradient(Gradient(colors: [Color(hex: 0x2A2F55), Color(hex: 0x14172E)]),
                                                   startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                context.stroke(Path(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: 0.5)), with: .color(.black.opacity(0.6)), lineWidth: 1)
                context.draw(Text("\(value)").font(.system(size: card * 0.8, weight: .heavy, design: .rounded))
                                .foregroundColor(i == 0 ? Theme.filet : level.color),
                             at: CGPoint(x: rect.midX, y: rect.midY))
                if server == i && phase != .menu && phase != .over {
                    let d = card * 0.14
                    context.fill(Path(ellipseIn: CGRect(x: rect.midX - d, y: rect.maxY + d * 0.8, width: d * 2, height: d * 2)),
                                 with: .color(.white))
                }
            }


            // Barrières sur les côtés de l'aire de jeu, et lumière au sol
            for sx in [-2.0, W + 2.0] {
                let a = P.point(sx, floorY, 2.2), b = P.point(sx, floorY, boardZ)
                let c = P.point(sx, floorY + 0.75, boardZ), d = P.point(sx, floorY + 0.75, 2.2)
                var side = Path()
                side.move(to: a); side.addLine(to: b); side.addLine(to: c); side.addLine(to: d); side.closeSubpath()
                context.fill(side, with: .linearGradient(Gradient(colors: [Color(hex: 0x1C3F9E), Color(hex: 0x12286A)]), startPoint: d, endPoint: a))
                var rim = Path()
                rim.move(to: d); rim.addLine(to: c)
                context.stroke(rim, with: .color(.white.opacity(0.25)), lineWidth: 1)
            }
            let pool = P.point(W / 2, floorY, FiletGame.length - 0.2)
            let poolR = P.ppm * P.k(FiletGame.length)
            context.fill(Path(ellipseIn: CGRect(x: pool.x - poolR * 2.4, y: pool.y - poolR * 0.9, width: poolR * 4.8, height: poolR * 1.8)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .clear]), center: pool, startRadius: 0, endRadius: poolR * 2.3))

            // La raquette de l'ordinateur : elle flotte seule au-dessus de son bout de table
            let swing = max(0, 1 - (clock - aiSwing) / 0.25)
            let aiS = P.k(FiletGame.aiZ)
            let batC = P.point(ai.x, 0.16 + 0.1 * swing, FiletGame.aiZ)
            let aiR = CGFloat(FiletGame.batRadius) * P.ppm * aiS
            let floorSpot = P.point(ai.x, floorY, FiletGame.aiZ)
            context.fill(Path(ellipseIn: CGRect(x: floorSpot.x - aiR * 1.3, y: floorSpot.y - aiR * 0.3, width: aiR * 2.6, height: aiR * 0.6)),
                         with: .color(.black.opacity(0.28)))
            context.fill(Path(ellipseIn: CGRect(x: batC.x - aiR * 1.6, y: batC.y - aiR * 1.6, width: aiR * 3.2, height: aiR * 3.2)),
                         with: .radialGradient(Gradient(colors: [level.color.opacity(0.4 + 0.4 * swing), level.color.opacity(0)]),
                                               center: batC, startRadius: aiR * 0.4, endRadius: aiR * 1.6))
            FiletScene.paddle(&context, center: batC, radius: aiR, tilt: -0.5 + 0.8 * swing, color: level.color)

            // La table : moitié adverse en perspective, ta moitié vue de dessus
            let blueTop = Color(hex: 0x2A6FD6)
            let blueBottom = Color(hex: 0x1B4FA8)
            let f1 = P.point(0, 0, L2), f2 = P.point(W, 0, L2), f3 = P.point(W, 0, FiletGame.length), f4 = P.point(0, 0, FiletGame.length)
            // pieds du côté adverse
            for (lxm, lzm) in [(0.12, FiletGame.length - 0.2), (W - 0.12, FiletGame.length - 0.2)] {
                var leg = Path()
                leg.move(to: P.point(lxm, -0.03, lzm))
                leg.addLine(to: P.point(lxm, floorY, lzm))
                context.stroke(leg, with: .color(Color(hex: 0x22252F)), lineWidth: max(2, 0.04 * P.ppm * P.k(lzm)))
            }
            var far = Path()
            far.move(to: f1); far.addLine(to: f2); far.addLine(to: f3); far.addLine(to: f4); far.closeSubpath()
            context.fill(far, with: .linearGradient(Gradient(colors: [blueBottom, blueTop]), startPoint: f4, endPoint: f1))
            let n1 = P.point(0, 0, 0), n2 = P.point(W, 0, 0)
            let near = CGRect(x: n1.x, y: fold, width: n2.x - n1.x, height: n1.y - fold)
            // ombre et épaisseur de ton bout de table
            // Ombre douce de la table, sans flou : deux rectangles transparents décalés.
            context.fill(Path(roundedRect: near.offsetBy(dx: P.ppm * 0.05, dy: P.ppm * 0.1).insetBy(dx: -P.ppm * 0.03, dy: -P.ppm * 0.03), cornerRadius: P.ppm * 0.05),
                         with: .color(.black.opacity(0.18)))
            context.fill(Path(near.offsetBy(dx: P.ppm * 0.04, dy: P.ppm * 0.08)), with: .color(.black.opacity(0.28)))
            context.fill(Path(CGRect(x: near.minX, y: near.maxY, width: near.width, height: max(3, P.ppm * 0.035))),
                         with: .color(Color(hex: 0x123672)))
            context.fill(Path(near), with: .linearGradient(Gradient(colors: [blueTop, blueBottom]),
                                                          startPoint: CGPoint(x: 0, y: near.minY), endPoint: CGPoint(x: 0, y: near.maxY)))
            // reflet des projecteurs
            context.fill(Path(near), with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .clear]),
                                                          center: CGPoint(x: near.midX, y: near.minY + near.height * 0.3),
                                                          startRadius: 0, endRadius: near.width * 0.55))
            context.fill(far, with: .linearGradient(Gradient(colors: [.white.opacity(0.0), .white.opacity(0.12)]), startPoint: f4, endPoint: f1))
            // lignes blanches
            let edge = max(1.5, 0.02 * P.ppm)
            var lines = Path()
            lines.move(to: n1); lines.addLine(to: n2); lines.addLine(to: f2); lines.addLine(to: f3); lines.addLine(to: f4); lines.addLine(to: f1); lines.closeSubpath()
            context.stroke(lines, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: edge, lineJoin: .round))
            var center = Path()
            center.move(to: P.point(W / 2, 0, 0))
            center.addLine(to: P.point(W / 2, 0, L2))
            center.addLine(to: P.point(W / 2, 0, FiletGame.length))
            context.stroke(center, with: .color(.white.opacity(0.7)), lineWidth: max(1, edge * 0.4))

            // Rebonds : petites ondes sur la table
            for r in ripples {
                let age = (clock - r.time) / 0.6
                let c = P.point(r.x, 0, r.z)
                let s = P.scale(r.z)
                let rr = P.ppm * s * CGFloat(0.03 + 0.12 * age)
                let squash: CGFloat = r.z > L2 ? 0.45 : 1
                context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * squash, width: rr * 2, height: rr * 2 * squash)),
                               with: .color(.white.opacity(0.7 * (1 - age))), lineWidth: 2)
            }

            // Balle (dessinée avant ou après le filet selon son côté)
            func drawBall(_ context: inout GraphicsContext) {
                guard phase != .menu else { return }
                let s = P.scale(ball.z)
                let br = max(3.5, 0.034 * P.ppm * s)
                // ombre portée
                if ball.y > -0.05 {
                    let sp = P.point(ball.x, 0, ball.z)
                    let fade = max(0, 1 - ball.y * 1.6)
                    let sr = br * (1.2 - min(0.5, CGFloat(ball.y)))
                    context.fill(Path(ellipseIn: CGRect(x: sp.x - sr, y: sp.y - sr * 0.5, width: sr * 2, height: sr)),
                                 with: .color(.black.opacity(0.35 * fade)))
                }
                for (i, p) in trail.enumerated() {
                    let f = CGFloat(i + 1) / CGFloat(max(1, trail.count))
                    let tp = P.point(p.x, p.y, p.z)
                    let tr = br * (0.35 + 0.55 * f) * (p.z > L2 ? P.k(p.z) / max(0.1, s) : 1)
                    context.fill(Path(ellipseIn: CGRect(x: tp.x - tr, y: tp.y - tr, width: tr * 2, height: tr * 2)),
                                 with: .color(Color(hex: 0xFFF3D6).opacity(0.22 * Double(f))))
                }
                let bp = P.point(ball.x, ball.y, ball.z)
                if let flash, flash.smash {
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius: br * 1.2))
                        glow.fill(Path(ellipseIn: CGRect(x: bp.x - br * 2, y: bp.y - br * 2, width: br * 4, height: br * 4)),
                                  with: .color(Color(hex: 0xFF8A3D).opacity(0.8)))
                    }
                }
                Draw.shadedBall(&context, center: bp, radius: br, color: Color(hex: 0xFFF6E6), highlight: .white)
            }

            if ball.z > L2 { drawBall(&context) }

            // Le filet, sur la charnière
            let netL = P.point(-0.1525, 0, L2).x
            let netR = P.point(W + 0.1525, 0, L2).x
            let netTop = fold - CGFloat(FiletGame.netHeight) * P.ppm
            let netRect = CGRect(x: netL, y: netTop, width: netR - netL, height: fold - netTop)
            context.fill(Path(netRect), with: .color(Color(hex: 0x0B0E1C).opacity(0.45)))
            var mesh = Path()
            var mx = netRect.minX
            while mx < netRect.maxX {
                mesh.move(to: CGPoint(x: mx, y: netRect.minY)); mesh.addLine(to: CGPoint(x: mx, y: netRect.maxY))
                mx += max(3, P.ppm * 0.02)
            }
            var my = netRect.minY
            while my < netRect.maxY {
                mesh.move(to: CGPoint(x: netRect.minX, y: my)); mesh.addLine(to: CGPoint(x: netRect.maxX, y: my))
                my += max(3, P.ppm * 0.02)
            }
            context.stroke(mesh, with: .color(.white.opacity(0.14)), lineWidth: 0.6)
            context.fill(Path(CGRect(x: netRect.minX, y: netRect.minY, width: netRect.width, height: max(2, P.ppm * 0.014))),
                         with: .color(.white))
            for px in [netRect.minX, netRect.maxX] {
                context.fill(Path(roundedRect: CGRect(x: px - 3, y: netRect.minY - 3, width: 6, height: netRect.height + 6), cornerRadius: 2),
                             with: .color(Color(hex: 0x2A2D3A)))
            }

            // Ta raquette
            if phase != .menu {
                let bc = P.point(bat.x, 0.12, bat.z)
                let rr = CGFloat(FiletGame.batRadius) * P.ppm
                let sp = P.point(bat.x, 0, bat.z)
                context.drawLayer { shadow in
                    shadow.addFilter(.blur(radius: rr * 0.25))
                    shadow.fill(Path(ellipseIn: CGRect(x: sp.x - rr * 0.9 + rr * 0.15, y: sp.y - rr * 0.6 + rr * 0.3, width: rr * 1.8, height: rr * 1.2)),
                                with: .color(.black.opacity(0.3)))
                }
                let tilt = max(-0.6, min(0.6, batVelocity.x * 0.12))
                FiletScene.paddle(&context, center: bc, radius: rr, tilt: tilt, color: Color(hex: 0xE23442))
            }

            if ball.z <= L2 { drawBall(&context) }

            // Éclair de frappe
            if let flash {
                let age = (clock - flash.time) / 0.4
                let c = P.point(flash.at.x, flash.at.y, flash.at.z)
                let s = P.scale(flash.at.z)
                var rays = Path()
                let n = flash.smash ? 12 : 8
                for i in 0..<n {
                    let a = Double(i) / Double(n) * 2 * .pi
                    let r0 = P.ppm * s * CGFloat(0.05 + 0.1 * age)
                    let r1 = r0 + P.ppm * s * CGFloat(flash.smash ? 0.12 : 0.06)
                    rays.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * r0, y: c.y + CGFloat(sin(a)) * r0))
                    rays.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r1, y: c.y + CGFloat(sin(a)) * r1))
                }
                context.stroke(rays, with: .color((flash.smash ? Color(hex: 0xFFB35C) : .white).opacity(0.85 * (1 - age))),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            // Messages
            if let message {
                let at = CGPoint(x: w / 2, y: fold + (h - fold) * 0.42)
                let color = messageGood ? Color(hex: 0x5BFF9E) : Color(hex: 0xFF6B6B)
                let size = min(44, max(22, w * 0.05))
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 10))
                    glow.draw(Text(message).font(.plie(size)).foregroundColor(color), at: at)
                }
                context.draw(Text(message).font(.plie(size)).foregroundColor(.white), at: at)
            } else if serveHint {
                let at = CGPoint(x: w / 2, y: h - (h - fold) * 0.12)
                let bob = CGFloat(sin(clock * 5)) * 4
                context.draw(Text(L("Touche l'écran pour servir")).font(.plie(16, weight: .bold)).foregroundColor(.white.opacity(0.9)),
                             at: CGPoint(x: at.x, y: at.y + bob))
            }
        }
        .accessibilityLabel(L("Table de ping-pong, \(scoreMe) à \(scoreAI)"))
    }

    /// Raquette : plaque de caoutchouc ronde et manche en bois.
    static func paddle(_ context: inout GraphicsContext, center: CGPoint, radius r: CGFloat, tilt: Double, color: Color) {
        var c = context
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(tilt))
        let handle = CGRect(x: -r * 0.17, y: r * 0.72, width: r * 0.34, height: r * 0.85)
        c.fill(Path(roundedRect: handle, cornerRadius: r * 0.12),
               with: .linearGradient(Gradient(colors: [Color(hex: 0xE2B07A), Color(hex: 0xA8743E)]),
                                     startPoint: CGPoint(x: handle.minX, y: 0), endPoint: CGPoint(x: handle.maxX, y: 0)))
        let blade = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        c.fill(Path(ellipseIn: blade.insetBy(dx: -r * 0.05, dy: -r * 0.05)), with: .color(Color(hex: 0x1A1A1A)))
        c.fill(Path(ellipseIn: blade), with: .radialGradient(Gradient(colors: [color.opacity(0.85), color, color.opacity(0.75)]),
                                                            center: CGPoint(x: -r * 0.3, y: -r * 0.35), startRadius: 0, endRadius: r * 1.4))
        c.fill(Path(ellipseIn: CGRect(x: -r * 0.55, y: -r * 0.6, width: r * 0.5, height: r * 0.28)), with: .color(.white.opacity(0.25)))
    }
}
