import SwiftUI
import Combine

extension Theme {
    static let panier = Color(hex: 0xFF8A3D)
}

// MARK: - Règles

@Observable
final class PanierGame {
    enum Phase: Equatable {
        case ready, playing, over
    }

    enum Result: Equatable {
        case scored, rim, long, short, wide
    }

    struct Shot {
        var t: Double = 0
        let targetX: Double
        let ratio: Double
        let result: Result
        var counted = false
    }

    static let roundDuration = 60.0
    static let flightTime = 0.62
    static let afterTime = 0.45
    static let idealPower = 2.8
    static let hoopHalf = 0.075
    static let ballHalf = 0.03

    private(set) var phase: Phase = .ready
    private(set) var timeLeft = roundDuration
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var shots = 0
    private(set) var made = 0
    private(set) var hoopX = 0.5
    private(set) var shot: Shot?
    private(set) var clock: Double = 0
    private(set) var lastText: String?
    private(set) var newRecord = false

    var onFire: Bool { streak >= 3 }

    func start() {
        phase = .playing
        timeLeft = Self.roundDuration
        score = 0
        streak = 0
        shots = 0
        made = 0
        hoopX = 0.5
        shot = nil
        lastText = nil
        newRecord = false
        clock = 0
        SoundPlayer.shared.play(.go)
    }

    /// Lancer : vitesse du glissé en points par seconde, taille de l'écran de jeu.
    func throwBall(velocity: CGSize, size: CGSize) {
        guard phase == .playing, shot == nil, size.height > 0, size.width > 0 else { return }
        let power = -Double(velocity.height) / Double(size.height)
        guard power > 0.6 else { return }
        let targetX = min(1.1, max(-0.1, 0.5 + Double(velocity.width) / Double(size.width) * 0.32))
        let ratio = power / Self.idealPower
        let dx = abs(targetX - hoopX)
        let heightOK = abs(ratio - 1) <= 0.16
        let inside = dx <= Self.hoopHalf - Self.ballHalf + 0.005
        let result: Result
        if heightOK && inside {
            result = .scored
        } else if abs(ratio - 1) <= 0.28 && dx <= Self.hoopHalf + Self.ballHalf + 0.02 {
            result = .rim
        } else if dx > Self.hoopHalf + Self.ballHalf + 0.02 && abs(ratio - 1) <= 0.3 {
            result = .wide
        } else {
            result = ratio > 1 ? .long : .short
        }
        shot = Shot(targetX: targetX, ratio: ratio, result: result)
        shots += 1
        Haptics.tap()
        SoundPlayer.shared.play(.whoosh, volume: 0.7)
    }

    func tick(dt: Double, best: Int) {
        clock += dt
        guard phase == .playing else { return }
        timeLeft = max(0, timeLeft - dt)
        if score >= 8 {
            let speed = min(1.8, 0.6 + Double(score - 8) * 0.06)
            hoopX = 0.5 + 0.28 * sin(clock * speed)
        }
        if var s = shot {
            s.t += dt
            if s.t >= Self.flightTime && !s.counted {
                s.counted = true
                resolve(s.result)
            }
            if s.t >= Self.flightTime + Self.afterTime {
                shot = nil
            } else {
                shot = s
            }
        }
        if timeLeft <= 0 && shot == nil {
            phase = .over
            newRecord = score > best
            SoundPlayer.shared.play(.vault, volume: 0.7)
            Haptics.success()
        }
    }

    private func resolve(_ result: Result) {
        switch result {
        case .scored:
            streak += 1
            made += 1
            let points = streak >= 3 ? 2 : 1
            score += points
            lastText = points == 2 ? L("En feu ! +2") : L("Panier !")
            Haptics.correct(subtle: false)
            SoundPlayer.shared.play(.swish, volume: 0.9)
        case .rim:
            streak = 0
            lastText = L("Sur le cercle…")
            SoundPlayer.shared.play(.clunk, volume: 0.7)
        case .long:
            streak = 0
            lastText = L("Trop fort")
            SoundPlayer.shared.play(.thud, volume: 0.7)
        case .short:
            streak = 0
            lastText = L("Trop court")
        case .wide:
            streak = 0
            lastText = L("À côté")
        }
    }
}

// MARK: - Écran

struct PanierView: View {
    @Environment(AppState.self) private var app
    @State private var game = PanierGame()
    @State private var hingeSeen = false

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            GameHeader(title: L("PANIER"), subtitle: L("Record : \(app.panierBest) points"), onBack: { app.route = .hub }) {
                HStack(spacing: 8) {
                    Pill(text: L("\(game.score) pts"), color: Theme.panier.opacity(0.25), textColor: Theme.panier)
                    Pill(text: L("\(Int(game.timeLeft.rounded(.up))) s"), color: Theme.card)
                }
            }
            .padding(.horizontal, 16)

            GeometryReader { proxy in
                ZStack {
                    PanierScene(game: game)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onEnded { value in
                                    game.throwBall(velocity: value.velocity, size: proxy.size)
                                }
                        )
                    if game.phase != .playing {
                        overlay
                    }
                }
            }
        }
        .padding(.top, 8)
        .onHingeAngle { degrees in
            if degrees != nil { hingeSeen = true }
        }
        .onReceive(ticker) { _ in
            let wasPlaying = game.phase == .playing
            game.tick(dt: 1.0 / 60.0, best: app.panierBest)
            if wasPlaying && game.phase == .over {
                app.recordPanier(game.score)
            }
        }
    }

    private var overlay: some View {
        VStack(spacing: 14) {
            if game.phase == .over {
                Text(game.newRecord ? L("Nouveau record !") : L("Temps écoulé"))
                    .font(.plie(30))
                Text(L("\(game.score) points · \(game.made) / \(game.shots) paniers"))
                    .font(.plie(18, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                ShareResultButton(game: L("PANIER"), result: L("\(game.score) points en 60 secondes"), accent: Theme.panier)
            } else {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.panier)
                Text(L("60 secondes, un maximum de paniers"))
                    .font(.plie(22))
                    .multilineTextAlignment(.center)
                Text(hingeSeen
                     ? L("Tourne ton iPhone Duo en paysage et plie-le en L : le panier se dresse devant toi. Lance d'un glissé vers le haut.")
                     : L("Lance d'un glissé vers le haut. Trois paniers d'affilée : chaque panier vaut 2 points."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Button(game.phase == .over ? L("Rejouer") : L("Jouer")) { game.start() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.panier, textColor: Theme.ink))
                .frame(maxWidth: 320)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 460)
        .winCard(accent: Theme.panier)
        .padding(20)
    }
}

/// Moitié haute : le panneau et le cercle. Moitié basse : le terrain et le ballon.
struct PanierScene: View {
    let game: PanierGame

    var body: some View {
        let hoopX = game.hoopX
        let shot = game.shot
        let onFire = game.onFire
        let text = game.lastText
        let clock = game.clock

        Canvas { context, size in
            let w = size.width
            let h = size.height
            let fold = h * 0.5

            // Salle : mur sombre, projecteurs et public
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: fold)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x0E1230), Color(hex: 0x232A58)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: fold)))
            context.drawLayer { lights in
                lights.addFilter(.blur(radius: w * 0.05))
                for k in 0..<3 {
                    let lx = w * (0.2 + 0.3 * CGFloat(k))
                    var cone = Path()
                    cone.move(to: CGPoint(x: lx - w * 0.02, y: 0))
                    cone.addLine(to: CGPoint(x: lx + w * 0.02, y: 0))
                    cone.addLine(to: CGPoint(x: lx + w * 0.14, y: fold))
                    cone.addLine(to: CGPoint(x: lx - w * 0.14, y: fold))
                    cone.closeSubpath()
                    let flicker = 0.08 + 0.03 * sin(clock * 0.8 + Double(k) * 2)
                    lights.fill(cone, with: .color(Color(hex: 0xFFE7B0).opacity(flicker)))
                }
            }
            for i in 0..<60 {
                let px = CGFloat(Draw.hash(i, 21)) * w
                let py = fold * (0.8 + 0.17 * CGFloat(Draw.hash(i, 22)))
                let pr = w * (0.012 + 0.008 * CGFloat(Draw.hash(i, 23)))
                let bounce = onFire ? CGFloat(abs(sin(clock * 8 + Double(i)))) * pr * 0.8 : 0
                context.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr - bounce, width: pr * 2, height: pr * 2.4)),
                             with: .color(Color(hex: 0x3A4378).opacity(0.7)))
            }
            // Parquet : lames claires et sombres, reflet des projecteurs
            context.fill(Path(CGRect(x: 0, y: fold, width: w, height: h - fold)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x8F5F35), Color(hex: 0xD49A5E)]),
                                               startPoint: CGPoint(x: 0, y: fold), endPoint: CGPoint(x: 0, y: h)))
            for i in 0..<12 {
                let x0 = w * CGFloat(i) / 12
                let x1 = w * CGFloat(i + 1) / 12
                var plank = Path()
                plank.move(to: CGPoint(x: w / 2 + (x0 - w / 2) * 0.55, y: fold))
                plank.addLine(to: CGPoint(x: w / 2 + (x1 - w / 2) * 0.55, y: fold))
                plank.addLine(to: CGPoint(x: x1, y: h))
                plank.addLine(to: CGPoint(x: x0, y: h))
                plank.closeSubpath()
                context.fill(plank, with: .color((i % 2 == 0 ? Color.white : Color.black).opacity(0.04 + 0.03 * Draw.hash(i, 4))))
            }
            context.fill(Path(ellipseIn: CGRect(x: w * 0.15, y: fold + (h - fold) * 0.1, width: w * 0.7, height: (h - fold) * 0.5)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .clear]),
                                               center: CGPoint(x: w / 2, y: fold + (h - fold) * 0.35), startRadius: 0, endRadius: w * 0.4))
            // Lignes du terrain en perspective
            for i in 0...6 {
                let x = w * CGFloat(i) / 6
                var l = Path()
                l.move(to: CGPoint(x: w / 2 + (x - w / 2) * 0.55, y: fold))
                l.addLine(to: CGPoint(x: x, y: h))
                context.stroke(l, with: .color(.black.opacity(0.1)), lineWidth: 1)
            }
            var key = Path()
            key.addArc(center: CGPoint(x: w / 2, y: h), radius: w * 0.28, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            context.stroke(key, with: .color(.white.opacity(0.35)), lineWidth: 2)
            context.stroke(Path(CGRect(x: 0, y: fold - 0.5, width: w, height: 1)), with: .color(.white.opacity(0.08)), lineWidth: 1)

            // Panneau
            let cx = w * hoopX
            let board = CGRect(x: cx - w * 0.17, y: fold * 0.18, width: w * 0.34, height: fold * 0.5)
            context.fill(Path(roundedRect: board.offsetBy(dx: 0, dy: 6), cornerRadius: 6), with: .color(.black.opacity(0.3)))
            context.fill(Path(roundedRect: board, cornerRadius: 6),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0.96), Color(hex: 0xDDE6F5).opacity(0.9)]),
                                               startPoint: CGPoint(x: board.minX, y: board.minY), endPoint: CGPoint(x: board.maxX, y: board.maxY)))
            var glare = Path()
            glare.move(to: CGPoint(x: board.minX + board.width * 0.55, y: board.minY))
            glare.addLine(to: CGPoint(x: board.minX + board.width * 0.75, y: board.minY))
            glare.addLine(to: CGPoint(x: board.minX + board.width * 0.45, y: board.maxY))
            glare.addLine(to: CGPoint(x: board.minX + board.width * 0.25, y: board.maxY))
            glare.closeSubpath()
            context.fill(glare, with: .color(.white.opacity(0.35)))
            context.stroke(Path(roundedRect: board.insetBy(dx: 3, dy: 3), cornerRadius: 4), with: .color(Theme.panier), lineWidth: 3)
            let square = CGRect(x: cx - w * 0.06, y: board.maxY - fold * 0.2, width: w * 0.12, height: fold * 0.15)
            context.stroke(Path(square), with: .color(Theme.panier), lineWidth: 3)

            // Filet (derrière le ballon qui marque)
            let rimY = board.maxY + fold * 0.02
            let rimW = w * PanierGame.hoopHalf * 2
            let netH = fold * 0.16
            // Filet en losanges : il se balance juste après un panier
            let swing: CGFloat = {
                guard let shot, shot.result == .scored, shot.t > PanierGame.flightTime else { return 0 }
                let after = shot.t - PanierGame.flightTime
                return CGFloat(sin(after * 18) * exp(-after * 4)) * rimW * 0.08
            }()
            func netPoint(_ i: Int, _ row: Int) -> CGPoint {
                let f = CGFloat(row) / 4
                let half = rimW / 2 * (1 - 0.36 * f)
                let x = cx - half + 2 * half * CGFloat(i) / 8 + swing * f * (CGFloat(i % 2) * 2 - 1)
                return CGPoint(x: x, y: rimY + netH * f * (1 + 0.15 * abs(swing) / max(1, rimW * 0.08)))
            }
            var net = Path()
            for row in 0..<4 {
                for i in 0...8 {
                    let a = netPoint(i, row)
                    if i < 8 { net.move(to: a); net.addLine(to: netPoint(i + 1, row + 1)) }
                    if i > 0 { net.move(to: a); net.addLine(to: netPoint(i - 1, row + 1)) }
                }
            }
            context.stroke(net, with: .color(.white.opacity(0.75)), lineWidth: 1.1)

            // Ballon
            if let shot {
                let s = min(1, shot.t / PanierGame.flightTime)
                let after = max(0, shot.t - PanierGame.flightTime) / PanierGame.afterTime
                let startY = h * 0.82
                let endY = rimY - CGFloat(shot.ratio - 1) * fold * 0.9
                var x = w * CGFloat(0.5 + (shot.targetX - 0.5) * s)
                var y = startY + (endY - startY) * CGFloat(s) - CGFloat(4 * s * (1 - s)) * h * 0.22 * CGFloat(min(1.4, shot.ratio))
                var r = w * 0.07 * CGFloat(1 - 0.55 * s)
                if s >= 1 {
                    switch shot.result {
                    case .scored:
                        y = rimY + CGFloat(after) * netH * 1.4
                    case .rim:
                        x += CGFloat(after) * w * 0.12 * (shot.targetX >= hoopX ? 1 : -1)
                        y = rimY - CGFloat(sin(after * .pi)) * fold * 0.12 + CGFloat(after) * fold * 0.3
                    case .long:
                        y = endY + CGFloat(after * after) * fold * 0.8
                    case .short, .wide:
                        y = endY + CGFloat(after * after) * fold * 1.2
                    }
                    r = w * 0.07 * 0.45
                }
                let ball = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.opacity = s >= 1 ? max(0, 1 - after * 0.8) : 1
                if onFire {
                    context.drawLayer { flame in
                        flame.addFilter(.blur(radius: r * 0.5))
                        flame.fill(Path(ellipseIn: ball.insetBy(dx: -r * 0.4, dy: -r * 0.4).offsetBy(dx: 0, dy: r * 0.5)),
                                   with: .color(Color(hex: 0xFF5C2A).opacity(0.6)))
                    }
                }
                PanierScene.basketball(&context, center: CGPoint(x: x, y: y), radius: r, spin: shot.t * 9)
                context.opacity = 1
            } else {
                let r = w * 0.07
                let bob = CGFloat(sin(clock * 3)) * 3
                let ball = CGRect(x: w / 2 - r, y: h * 0.82 - r + bob, width: r * 2, height: r * 2)
                // Ombre au sol
                context.fill(Path(ellipseIn: CGRect(x: w / 2 - r * 0.9, y: h * 0.82 + r * 0.85, width: r * 1.8, height: r * 0.4)),
                             with: .color(.black.opacity(0.25 - Double(bob) * 0.02)))
                if onFire {
                    context.drawLayer { flame in
                        flame.addFilter(.blur(radius: 10))
                        let flick = CGFloat(sin(clock * 20)) * 3
                        flame.fill(Path(ellipseIn: ball.insetBy(dx: -10, dy: -14 - flick).offsetBy(dx: 0, dy: -6)),
                                   with: .color(Color(hex: 0xFF5C2A).opacity(0.55)))
                        flame.fill(Path(ellipseIn: ball.insetBy(dx: -2, dy: -6).offsetBy(dx: 0, dy: -8)),
                                   with: .color(Color(hex: 0xFFC53D).opacity(0.45)))
                    }
                }
                PanierScene.basketball(&context, center: CGPoint(x: ball.midX, y: ball.midY), radius: r, spin: 0)
            }

            // Cercle (devant)
            let rim = Path(ellipseIn: CGRect(x: cx - rimW / 2, y: rimY - 5, width: rimW, height: 10))
            context.stroke(rim.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.35)), lineWidth: 4)
            context.stroke(rim, with: .linearGradient(Gradient(colors: [Color(hex: 0xFF7A4A), Color(hex: 0xD8341A), Color(hex: 0xFF7A4A)]),
                                                     startPoint: CGPoint(x: cx - rimW / 2, y: rimY), endPoint: CGPoint(x: cx + rimW / 2, y: rimY)),
                           lineWidth: 4)

            if let text, shot != nil {
                let at = CGPoint(x: w / 2, y: fold + (h - fold) * 0.28)
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 8))
                    glow.draw(Text(text).font(.plie(26)).foregroundColor(Theme.panier), at: at)
                }
                context.draw(Text(text).font(.plie(26)).foregroundColor(.white), at: at)
            }
        }
        .accessibilityLabel(L("Terrain de basket"))
    }

    /// Ballon de basket ombré, avec ses coutures.
    static func basketball(_ context: inout GraphicsContext, center: CGPoint, radius r: CGFloat, spin: Double) {
        Draw.shadedBall(&context, center: center, radius: r, color: Color(hex: 0xF07A2A), highlight: Color(hex: 0xFFC78A))
        var c = context
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(spin))
        c.clip(to: Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)))
        var seams = Path()
        seams.move(to: CGPoint(x: -r, y: 0)); seams.addLine(to: CGPoint(x: r, y: 0))
        seams.move(to: CGPoint(x: 0, y: -r)); seams.addLine(to: CGPoint(x: 0, y: r))
        seams.move(to: CGPoint(x: -r * 0.62, y: -r * 0.8))
        seams.addQuadCurve(to: CGPoint(x: -r * 0.62, y: r * 0.8), control: CGPoint(x: -r * 0.05, y: 0))
        seams.move(to: CGPoint(x: r * 0.62, y: -r * 0.8))
        seams.addQuadCurve(to: CGPoint(x: r * 0.62, y: r * 0.8), control: CGPoint(x: r * 0.05, y: 0))
        c.stroke(seams, with: .color(Color(hex: 0x3A1A08).opacity(0.75)), lineWidth: max(1, r * 0.07))
    }
}
