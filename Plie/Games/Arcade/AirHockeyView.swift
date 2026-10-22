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

    @ObservationIgnored private var velA = HVec(u: 0, v: 0)
    @ObservationIgnored private var velB = HVec(u: 0, v: 0)
    @ObservationIgnored private var targetA: HVec?
    @ObservationIgnored private var targetB: HVec?
    @ObservationIgnored private var lastHit: Double = 0
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
        targetA = nil
        targetB = nil
        velA = HVec(u: 0, v: 0)
        velB = HVec(u: 0, v: 0)
    }

    /// Le doigt d'un joueur, en coordonnées du terrain.
    func touch(player: Int, at p: HVec?) {
        if player == 0 { targetA = p } else if !solo { targetB = p }
    }

    func tick(dt: Double) {
        clock += dt
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
        let attacking = puck.u > 0.5 && puckVel.u < 1.2
        var goal: HVec
        if attacking {
            goal = HVec(u: puck.u + 0.06, v: puck.v)
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

        collide(mallet: malletA, vel: velA)
        collide(mallet: malletB, vel: velB)

        let speed = puckVel.length
        if speed > Self.maxSpeed {
            puckVel = puckVel * (Self.maxSpeed / speed)
        }
    }

    private func collide(mallet: HVec, vel: HVec) {
        let d = puck - mallet
        let dist = d.length
        let minDist = Self.malletR + Self.puckR
        guard dist < minDist, dist > 0.0001 else { return }
        let n = d * (1 / dist)
        puck = mallet + n * minDist
        let rel = puckVel - vel
        let vn = rel.dot(n)
        if vn < 0 {
            puckVel = puckVel - n * ((1 + 0.9) * vn)
        }
        if clock - lastHit > 0.08 {
            lastHit = clock
            Haptics.tap()
            SoundPlayer.shared.play(.notch, volume: 0.8)
        }
    }

    private func bump() {
        if clock - lastHit > 0.08 {
            lastHit = clock
            SoundPlayer.shared.play(.notch, volume: 0.4)
        }
    }

    private func scored(by player: Int) {
        if player == 0 { scoreA += 1 } else { scoreB += 1 }
        lastScorer = player
        phase = .goal
        goalTimer = 1.3
        Haptics.success()
        SoundPlayer.shared.play(.caught, volume: 0.7)
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
            GameHeader(title: "AIR HOCKEY", subtitle: game.solo ? "Contre l'ordinateur" : "À deux, face à face", onBack: { app.route = .hub }) {
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
                     ? (game.scoreA > game.scoreB ? "Tu as gagné !" : "L'ordinateur gagne")
                     : "Le joueur \(game.scoreA > game.scoreB ? "rouge" : "bleu") gagne !")
                    .font(.plie(30))
                Text("\(game.scoreA) – \(game.scoreB)")
                    .font(.plie(22, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.hockeyB)
                Text("Le premier à 7 buts gagne")
                    .font(.plie(22))
                Text(hingePresent
                     ? "À deux : pose ton iPhone Duo ouvert à plat entre vous. La charnière sert de ligne médiane, chacun défend sa moitié."
                     : "À deux : posez le téléphone à plat entre vous, chacun défend sa moitié.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Solo") { game.start(solo: true) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.hockeyA))
                Button("À deux") { game.start(solo: false) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.hockeyB, textColor: Theme.ink))
            }
            .frame(maxWidth: 360)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.ink.opacity(0.94)))
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

        Canvas { context, size in
            func sp(_ u: Double, _ v: Double) -> CGPoint {
                alongX ? CGPoint(x: CGFloat(u) * scale, y: CGFloat(v) * scale)
                       : CGPoint(x: CGFloat(v) * scale, y: CGFloat(1 - u) * scale)
            }
            func disc(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

            let table = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: table, cornerRadius: 18),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x123B6E), Color(hex: 0x0D2A52)]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.stroke(Path(roundedRect: table.insetBy(dx: 3, dy: 3), cornerRadius: 16), with: .color(.white.opacity(0.5)), lineWidth: 3)

            // Ligne médiane (la charnière) et rond central
            var mid = Path()
            mid.move(to: sp(0.5, 0))
            mid.addLine(to: sp(0.5, width))
            context.stroke(mid, with: .color(Color(hex: 0xFF4A5A).opacity(0.8)), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            context.stroke(disc(sp(0.5, width / 2), scale * 0.14), with: .color(Color(hex: 0xFF4A5A).opacity(0.6)), lineWidth: 2)

            // Buts
            for (u, color) in [(0.0, Theme.hockeyA), (1.0, Theme.hockeyB)] {
                var g = Path()
                g.move(to: sp(u, width / 2 - gw / 2))
                g.addLine(to: sp(u, width / 2 + gw / 2))
                context.stroke(g, with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                context.stroke(disc(sp(u, width / 2), scale * CGFloat(gw / 2)), with: .color(color.opacity(0.25)), lineWidth: 2)
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
            for (m, color) in [(a, Theme.hockeyA), (b, Theme.hockeyB)] {
                let c = sp(m.u, m.v)
                let r = CGFloat(HockeyGame.malletR) * scale
                context.fill(disc(c, r), with: .color(color))
                context.fill(disc(c, r * 0.55), with: .color(.white.opacity(0.35)))
                context.stroke(disc(c, r), with: .color(.white.opacity(0.6)), lineWidth: 2)
            }
            let pc = sp(puck.u, puck.v)
            let pr = CGFloat(HockeyGame.puckR) * scale
            context.fill(disc(pc, pr), with: .color(Color(hex: 0x111111)))
            context.stroke(disc(pc, pr), with: .color(.white.opacity(goalFlash ? 1 : 0.7)), lineWidth: goalFlash ? 4 : 2)

            if goalFlash {
                let text = Text("BUT !").font(.plie(scale * 0.12)).foregroundColor(.white)
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
        .accessibilityLabel("Table d'air hockey, \(scoreA) à \(scoreB)")
    }
}
