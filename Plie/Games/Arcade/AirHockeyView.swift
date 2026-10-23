import SwiftUI
import Combine

extension Theme {
    static let hockeyA = Color(hex: 0xFF5C4D)
    static let hockeyB = Color(hex: 0x3DE0FF)
}

// MARK: - Physique
//
// Repère du terrain : u va du but du joueur A (u = 0) au but du joueur B (u = 1),
// v va d'un bord à l'autre (de 0 à `width`). La ligne médiane u = 0,5 est la charnière.

struct HVec {
    var u: Double
    var v: Double

    static func + (a: HVec, b: HVec) -> HVec { HVec(u: a.u + b.u, v: a.v + b.v) }
    static func - (a: HVec, b: HVec) -> HVec { HVec(u: a.u - b.u, v: a.v - b.v) }
    static func * (a: HVec, k: Double) -> HVec { HVec(u: a.u * k, v: a.v * k) }
    var length: Double { (u * u + v * v).squareRoot() }
    func dot(_ o: HVec) -> Double { u * o.u + v * o.v }
}

@Observable
final class HockeyGame {
    enum Phase: Equatable {
        case menu, playing, goal, over
    }

    static let malletR = 0.075
    static let puckR = 0.042
    static let maxSpeed = 3.4
    static let winScore = 7

    var width = 1.4
    private(set) var phase: Phase = .menu
    private(set) var solo = true
    private(set) var puck = HVec(u: 0.5, v: 0.7)
    private(set) var puckVel = HVec(u: 0, v: 0)
    private(set) var malletA = HVec(u: 0.15, v: 0.7)
    private(set) var malletB = HVec(u: 0.85, v: 0.7)
    private(set) var scoreA = 0
    private(set) var scoreB = 0
    private(set) var lastScorer = 0
    private(set) var goalTimer: Double = 0
    /// Dernières positions du palet, pour sa traînée lumineuse.
    private(set) var trail: [HVec] = []
    /// Moment du dernier choc (pour l'onde autour du maillet).
    private(set) var impact: (at: HVec, time: Double)?
    private(set) var time: Double = 0

    @ObservationIgnored private var velA = HVec(u: 0, v: 0)
    @ObservationIgnored private var velB = HVec(u: 0, v: 0)
    @ObservationIgnored private var targetA: HVec?
    @ObservationIgnored private var targetB: HVec?
    @ObservationIgnored private var lastHit: Double = 0
    /// Anti-blocage : palet presque arrêté, ou serré contre un bord par un maillet.
    @ObservationIgnored private var slowTime: Double = 0
    @ObservationIgnored private var jamTime: Double = 0
    /// Après une frappe, l'ordinateur recule un instant au lieu de coincer le palet.
    @ObservationIgnored private var aiCooldown: Double = 0
    /// Moment de la dernière remise en jeu (pour l'afficher).
    private(set) var noticeAt: Double = -10
    @ObservationIgnored private var clock: Double = 0

    var goalWidth: Double { min(width * 0.46, 0.62) }

    func start(solo: Bool) {
        self.solo = solo
        scoreA = 0
        scoreB = 0
        resetPositions(serveToA: true)
        phase = .playing
        SoundPlayer.shared.play(.go)
    }

    private func resetPositions(serveToA: Bool) {
        malletA = HVec(u: 0.14, v: width / 2)
        malletB = HVec(u: 0.86, v: width / 2)
        puck = HVec(u: serveToA ? 0.3 : 0.7, v: width / 2)
        puckVel = HVec(u: 0, v: 0)
        trail = []
        targetA = nil
        targetB = nil
        velA = HVec(u: 0, v: 0)
        velB = HVec(u: 0, v: 0)
        slowTime = 0
        jamTime = 0
        aiCooldown = 0
    }

    /// Le doigt d'un joueur, en coordonnées du terrain.
    func touch(player: Int, at p: HVec?) {
        if player == 0 { targetA = p } else if !solo { targetB = p }
    }

    func tick(dt: Double) {
        clock += dt
        time = clock
        switch phase {
        case .goal:
            goalTimer -= dt
            if goalTimer <= 0 {
                if scoreA >= Self.winScore || scoreB >= Self.winScore {
                    phase = .over
                    SoundPlayer.shared.play(.win)
                    Haptics.success()
                } else {
                    resetPositions(serveToA: lastScorer == 1)
                    phase = .playing
                }
            }
            return
        case .playing:
            break
        default:
            return
        }

        let steps = 3
        let h = dt / Double(steps)
        for _ in 0..<steps {
            moveMallets(h)
            movePuck(h)
            if phase != .playing { break }
        }
        if phase == .playing { unstick(dt) }
        trail.append(puck)
        if trail.count > 12 { trail.removeFirst(trail.count - 12) }
    }

    /// Le palet ne doit jamais rester bloqué : arrêté trop longtemps, ou coincé contre un bord.
    private func unstick(_ dt: Double) {
        let r = Self.puckR
        let nearWall = puck.u < r + 0.02 || puck.u > 1 - r - 0.02 || puck.v < r + 0.02 || puck.v > width - r - 0.02
        let contact = Self.malletR + Self.puckR + 0.012
        let pinned = nearWall && ((puck - malletA).length < contact || (puck - malletB).length < contact)
        jamTime = pinned ? jamTime + dt : 0
        slowTime = puckVel.length < 0.12 ? slowTime + dt : 0
        // Un palet arrêté dans le camp d'un joueur humain lui laisse plus de temps pour le frapper.
        let humanSide = puck.u < 0.5 || !solo
        if jamTime > 1.2 || slowTime > (humanSide ? 6.0 : 3.0) {
            faceOff(towardA: puck.u >= 0.5)
        }
    }

    /// Remise en jeu au centre, vers le joueur qui n'avait pas le palet.
    private func faceOff(towardA: Bool) {
        jamTime = 0
        slowTime = 0
        puck = HVec(u: 0.5, v: width / 2)
        puckVel = HVec(u: towardA ? -0.55 : 0.55, v: Double.random(in: -0.25...0.25))
        trail = []
        noticeAt = clock
        SoundPlayer.shared.play(.whoosh, volume: 0.5)
    }

    private func clampA(_ p: HVec) -> HVec {
        HVec(u: min(0.5 - Self.malletR, max(Self.malletR, p.u)), v: min(width - Self.malletR, max(Self.malletR, p.v)))
    }

    private func clampB(_ p: HVec) -> HVec {
        HVec(u: min(1 - Self.malletR, max(0.5 + Self.malletR, p.u)), v: min(width - Self.malletR, max(Self.malletR, p.v)))
    }

    private func moveMallets(_ h: Double) {
        if let t = targetA {
            let next = clampA(t)
            velA = (next - malletA) * (1 / h) * 0.6 + velA * 0.4
            malletA = next
        } else {
            velA = velA * 0.8
        }
        if solo {
            aiTarget(h)
        } else if let t = targetB {
            let next = clampB(t)
            velB = (next - malletB) * (1 / h) * 0.6 + velB * 0.4
            malletB = next
        } else {
            velB = velB * 0.8
        }
    }

    /// Adversaire de l'ordinateur : défend son but, attaque quand le palet est de son côté.
    private func aiTarget(_ h: Double) {
        var attacking = puck.u > 0.5 && puckVel.u < 1.2
        if aiCooldown > 0 {
            aiCooldown -= h
            attacking = false
        }
        var goal: HVec
        if attacking {
            if puck.u > 1 - Self.malletR - Self.puckR - 0.01 {
                // Palet collé à mon fond : je le dégage par le côté au lieu de l'écraser contre le bord.
                let side: Double = puck.v > width / 2 ? 1 : -1
                goal = HVec(u: puck.u, v: puck.v + side * (Self.malletR + Self.puckR))
            } else {
                goal = HVec(u: puck.u + 0.06, v: puck.v)
            }
        } else {
            let gw = goalWidth
            goal = HVec(u: 0.88, v: min(width / 2 + gw / 2, max(width / 2 - gw / 2, puck.v)))
        }
        goal = clampB(goal)
        let delta = goal - malletB
        let dist = delta.length
        let maxStep = 1.25 * h
        let next = dist <= maxStep ? goal : malletB + delta * (maxStep / dist)
        velB = (next - malletB) * (1 / h)
        malletB = next
    }

    private func movePuck(_ h: Double) {
        puck = puck + puckVel * h
        puckVel = puckVel * (1 - 0.35 * h)
        let r = Self.puckR

        // Bords latéraux
        if puck.v < r {
            puck.v = r
            puckVel.v = abs(puckVel.v) * 0.9
            bump()
        } else if puck.v > width - r {
            puck.v = width - r
            puckVel.v = -abs(puckVel.v) * 0.9
            bump()
        }

        // Fonds et buts
        let gw = goalWidth
        let inGoalMouth = abs(puck.v - width / 2) < gw / 2 - r * 0.3
        // Un palet arrêté dans l'entrée du but finit par y glisser.
        if inGoalMouth && puck.u < r { puckVel.u -= 0.9 * h }
        if inGoalMouth && puck.u > 1 - r { puckVel.u += 0.9 * h }
        if puck.u < r {
            if inGoalMouth {
                if puck.u < -r { scored(by: 1) }
            } else {
                puck.u = r
                puckVel.u = abs(puckVel.u) * 0.9
                bump()
            }
        } else if puck.u > 1 - r {
            if inGoalMouth {
                if puck.u > 1 + r { scored(by: 0) }
            } else {
                puck.u = 1 - r
                puckVel.u = -abs(puckVel.u) * 0.9
                bump()
            }
        }

        collide(mallet: malletA, vel: velA, isComputer: false)
        collide(mallet: malletB, vel: velB, isComputer: solo)

        let speed = puckVel.length
        if speed > Self.maxSpeed {
            puckVel = puckVel * (Self.maxSpeed / speed)
        }
    }

    private func collide(mallet: HVec, vel: HVec, isComputer: Bool) {
        let d = puck - mallet
        let dist = d.length
        let minDist = Self.malletR + Self.puckR
        guard dist < minDist, dist > 0.0001 else { return }
        if isComputer { aiCooldown = 0.35 }
        let n = d * (1 / dist)
        puck = mallet + n * minDist
        let rel = puckVel - vel
        let vn = rel.dot(n)
        if vn < 0 {
            puckVel = puckVel - n * ((1 + 0.9) * vn)
        }
        if clock - lastHit > 0.08 {
            lastHit = clock
            impact = (puck, clock)
            Haptics.tap()
            SoundPlayer.shared.play(.puck, volume: 0.9)
        }
    }

    private func bump() {
        if clock - lastHit > 0.08 {
            lastHit = clock
            impact = (puck, clock)
            SoundPlayer.shared.play(.puck, volume: 0.45)
        }
    }

    private func scored(by player: Int) {
        if player == 0 { scoreA += 1 } else { scoreB += 1 }
        lastScorer = player
        phase = .goal
        goalTimer = 1.3
        Haptics.success()
        SoundPlayer.shared.play(.goal, volume: 0.85)
    }
}

// MARK: - Écran

struct AirHockeyView: View {
    @Environment(AppState.self) private var app
    @State private var game = HockeyGame()
    @State private var hingePresent = false

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            GameHeader(title: L("AIR HOCKEY"), subtitle: game.solo ? L("Contre l'ordinateur") : L("À deux, face à face"), onBack: { app.route = .hub }) {
                Pill(text: "\(game.scoreA) – \(game.scoreB)", color: Theme.card)
            }
            .padding(.horizontal, 16)

            GeometryReader { proxy in
                let size = proxy.size
                // La charnière du Duo coupe le terrain en deux. Sans charnière, on joue dans la longueur.
                let alongX = hingePresent ? size.width < size.height : size.width > size.height
                let scale = alongX ? size.width : size.height
                let across = alongX ? size.height / size.width : size.width / size.height

                ZStack {
                    HockeyTable(game: game, alongX: alongX, scale: scale)

                    // Deux zones tactiles indépendantes : les deux joueurs jouent en même temps.
                    ForEach(0..<2, id: \.self) { player in
                        let rect = halfRect(player: player, size: size, alongX: alongX)
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let p = CGPoint(x: rect.minX + value.location.x, y: rect.minY + value.location.y)
                                        game.touch(player: player, at: toField(p, alongX: alongX, scale: scale))
                                    }
                                    .onEnded { _ in game.touch(player: player, at: nil) }
                            )
                    }

                    if game.phase == .menu || game.phase == .over {
                        menu
                    }
                }
                .onAppear { game.width = Double(across) }
                .onChange(of: size) { _, newSize in
                    let ax = hingePresent ? newSize.width < newSize.height : newSize.width > newSize.height
                    game.width = Double(ax ? newSize.height / newSize.width : newSize.width / newSize.height)
                }
            }
        }
        .padding(.top, 8)
        .onHingeAngle { degrees in
            if degrees != nil { hingePresent = true }
        }
        .onReceive(ticker) { _ in game.tick(dt: 1.0 / 60.0) }
    }

    private func halfRect(player: Int, size: CGSize, alongX: Bool) -> CGRect {
        if alongX {
            return player == 0 ? CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
                               : CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
        }
        return player == 0 ? CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
                           : CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
    }

    private func toField(_ p: CGPoint, alongX: Bool, scale: CGFloat) -> HVec {
        alongX ? HVec(u: Double(p.x / scale), v: Double(p.y / scale))
               : HVec(u: Double(1 - p.y / scale), v: Double(p.x / scale))
    }

    private var menu: some View {
        VStack(spacing: 14) {
            if game.phase == .over {
                Text(game.solo
                     ? (game.scoreA > game.scoreB ? L("Tu as gagné !") : L("L'ordinateur gagne"))
                     : (game.scoreA > game.scoreB ? L("Le joueur rouge gagne !") : L("Le joueur bleu gagne !")))
                    .font(.plie(30))
                Text("\(game.scoreA) – \(game.scoreB)")
                    .font(.plie(22, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                ShareResultButton(game: L("AIR HOCKEY"), result: "\(game.scoreA) – \(game.scoreB)", accent: Theme.hockeyB)
            } else {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.hockeyB)
                Text(L("Le premier à 7 buts gagne"))
                    .font(.plie(22))
                Text(hingePresent
                     ? L("À deux : pose ton iPhone Duo ouvert à plat entre vous. La charnière sert de ligne médiane, chacun défend sa moitié.")
                     : L("À deux : posez le téléphone à plat entre vous, chacun défend sa moitié."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button(L("Solo")) { game.start(solo: true) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.hockeyA))
                Button(L("À deux")) { game.start(solo: false) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.hockeyB, textColor: Theme.ink))
            }
            .frame(maxWidth: 360)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 460)
        .winCard(accent: Theme.laser)
        .padding(20)
    }
}

struct HockeyTable: View {
    let game: HockeyGame
    let alongX: Bool
    let scale: CGFloat

    var body: some View {
        let puck = game.puck
        let a = game.malletA
        let b = game.malletB
        let scoreA = game.scoreA
        let scoreB = game.scoreB
        let goalFlash = game.phase == .goal
        let width = game.width
        let gw = game.goalWidth
        let trail = game.trail
        let impact = game.impact
        let now = game.time
        let notice = game.time - game.noticeAt < 1.1

        Canvas { context, size in
            func sp(_ u: Double, _ v: Double) -> CGPoint {
                alongX ? CGPoint(x: CGFloat(u) * scale, y: CGFloat(v) * scale)
                       : CGPoint(x: CGFloat(v) * scale, y: CGFloat(1 - u) * scale)
            }
            func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

            // Table néon : fond sombre, trous d'air, bandes lumineuses
            let table = CGRect(origin: .zero, size: size)
            let tablePath = Path(roundedRect: table, cornerRadius: 18)
            context.fill(tablePath, with: .linearGradient(Gradient(colors: [Color(hex: 0x0B1440), Color(hex: 0x070B26)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.fill(tablePath, with: .radialGradient(Gradient(colors: [Color(hex: 0x2A3CFF).opacity(0.18), .clear]),
                                                         center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                                                         endRadius: max(size.width, size.height) * 0.6))
            var holes = Path()
            let gap: CGFloat = 18
            var y: CGFloat = gap / 2
            while y < size.height {
                var x: CGFloat = gap / 2
                while x < size.width {
                    holes.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += gap
                }
                y += gap
            }
            context.fill(holes, with: .color(.white.opacity(0.07)))
            func neon(_ path: Path, _ color: Color, _ width: CGFloat, dash: [CGFloat] = []) {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: width * 2))
                    glow.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: width * 2, lineCap: .round, dash: dash))
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
                context.stroke(path, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: max(1, width * 0.3), lineCap: .round, dash: dash))
            }
            neon(Path(roundedRect: table.insetBy(dx: 4, dy: 4), cornerRadius: 15), Color(hex: 0x7B5CFF), 3)

            // Ligne médiane (la charnière) et rond central
            var mid = Path()
            mid.move(to: sp(0.5, 0))
            mid.addLine(to: sp(0.5, width))
            neon(mid, Color(hex: 0xFF4A5A), 2.5, dash: [10, 8])
            neon(disc(sp(0.5, width / 2), scale * 0.14), Color(hex: 0xFF4A5A).opacity(0.8), 2)

            // Buts
            for (u, color) in [(0.0, Theme.hockeyA), (1.0, Theme.hockeyB)] {
                var g = Path()
                g.move(to: sp(u, width / 2 - gw / 2))
                g.addLine(to: sp(u, width / 2 + gw / 2))
                neon(g, color, 7)
                neon(disc(sp(u, width / 2), scale * CGFloat(gw / 2)), color.opacity(0.5), 1.5)
            }

            // Scores, chacun tourné vers son joueur
            for (player, score) in [(0, scoreA), (1, scoreB)] {
                var c = context
                let center = sp(player == 0 ? 0.32 : 0.68, width / 2)
                c.translateBy(x: center.x, y: center.y)
                let angle: Double = alongX ? (player == 0 ? 90 : -90) : (player == 0 ? 0 : 180)
                c.rotate(by: .degrees(angle))
                c.draw(Text("\(score)").font(.plie(scale * 0.14)).foregroundColor(.white.opacity(0.18)), at: .zero)
            }

            // Maillets et palet
            let pr = CGFloat(HockeyGame.puckR) * scale
            // Traînée du palet
            if trail.count > 1 {
                for (i, p) in trail.enumerated() {
                    let f = CGFloat(i + 1) / CGFloat(trail.count)
                    context.fill(disc(sp(p.u, p.v), pr * (0.4 + 0.6 * f)), with: .color(Theme.laser.opacity(0.22 * Double(f))))
                }
            }
            // Onde de choc
            if let impact {
                let age = now - impact.time
                if age < 0.35 {
                    let k = CGFloat(age / 0.35)
                    context.stroke(disc(sp(impact.at.u, impact.at.v), pr * (1 + 2.2 * k)),
                                   with: .color(.white.opacity(0.6 * Double(1 - k))), lineWidth: 2)
                }
            }
            for (m, color) in [(a, Theme.hockeyA), (b, Theme.hockeyB)] {
                let c = sp(m.u, m.v)
                let r = CGFloat(HockeyGame.malletR) * scale
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: r * 0.5))
                    glow.fill(disc(c, r * 1.15), with: .color(color.opacity(0.6)))
                }
                Draw.shadedBall(&context, center: c, radius: r, color: color)
                context.fill(disc(c, r * 0.5), with: .radialGradient(Gradient(colors: [.white.opacity(0.7), color]),
                                                                    center: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.15),
                                                                    startRadius: 0, endRadius: r * 0.5))
                context.stroke(disc(c, r), with: .color(.white.opacity(0.55)), lineWidth: 1.5)
            }
            let pc = sp(puck.u, puck.v)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: pr * 0.6))
                glow.fill(disc(pc, pr * 1.3), with: .color(Theme.laser.opacity(goalFlash ? 0.9 : 0.55)))
            }
            context.fill(disc(pc, pr), with: .radialGradient(Gradient(colors: [Color(hex: 0x3A3F55), Color(hex: 0x0B0C14)]),
                                                            center: CGPoint(x: pc.x - pr * 0.3, y: pc.y - pr * 0.3),
                                                            startRadius: 0, endRadius: pr * 1.3))
            context.stroke(disc(pc, pr), with: .color(Theme.laser.opacity(goalFlash ? 1 : 0.85)), lineWidth: goalFlash ? 4 : 2)

            if notice && !goalFlash {
                let at = CGPoint(x: size.width / 2, y: size.height / 2 - scale * 0.12)
                context.draw(Text(L("Remise en jeu")).font(.plie(scale * 0.06)).foregroundColor(.white.opacity(0.85)), at: at)
            }
            if goalFlash {
                let at = CGPoint(x: size.width / 2, y: size.height / 2)
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 12))
                    glow.draw(Text(L("BUT !")).font(.plie(scale * 0.12)).foregroundColor(Theme.paint), at: at)
                }
                context.draw(Text(L("BUT !")).font(.plie(scale * 0.12)).foregroundColor(.white), at: at)
            }
        }
        .accessibilityLabel(L("Table d'air hockey, \(scoreA) à \(scoreB)"))
    }
}
