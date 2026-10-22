import SwiftUI
import Combine

extension Theme {
    static let darts = Color(hex: 0xE84C5A)
}

// MARK: - Cible

enum Dartboard {
    /// Ordre des numéros dans le sens des aiguilles d'une montre, en partant du haut.
    static let numbers = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    // Rayons relatifs (1 = bord de la zone qui compte)
    static let bull = 0.05
    static let outerBull = 0.11
    static let tripleIn = 0.55
    static let tripleOut = 0.62
    static let doubleIn = 0.93

    /// Points pour un impact (x à droite, y vers le haut, en rayons de cible).
    static func score(x: Double, y: Double) -> (points: Int, label: String) {
        let r = (x * x + y * y).squareRoot()
        if r > 1 { return (0, L("Raté")) }
        if r < bull { return (50, L("Mille !")) }
        if r < outerBull { return (25, "25") }
        var phi = atan2(x, y)
        if phi < 0 { phi += 2 * .pi }
        let sector = Int((phi + .pi / 20) / (2 * .pi / 20)) % 20
        let n = numbers[sector]
        if r >= tripleIn && r < tripleOut { return (n * 3, L("Triple \(n)")) }
        if r >= doubleIn { return (n * 2, L("Double \(n)")) }
        return (n, "\(n)")
    }
}

// MARK: - Partie

@Observable
final class DartsGame {
    enum Phase: Equatable {
        case menu, playing, over
    }

    struct Dart: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let points: Int
        let label: String
        var t: Double = 0
    }

    static let dartsPerVolley = 3
    static let flightTime = 0.28
    static let idealPower = 2.4

    private(set) var phase: Phase = .menu
    private(set) var players = 1
    private(set) var volleys = 10
    private(set) var current = 0
    private(set) var volley = 1
    private(set) var scores: [Int] = [0, 0]
    private(set) var darts: [Dart] = []
    private(set) var volleyPoints = 0
    private(set) var pause: Double = 0
    private(set) var message: String?

    var throwsLeft: Int { Self.dartsPerVolley - darts.count }

    func start(players: Int) {
        self.players = players
        volleys = players == 1 ? 10 : 8
        current = 0
        volley = 1
        scores = [0, 0]
        darts = []
        volleyPoints = 0
        pause = 0
        message = nil
        phase = .playing
        SoundPlayer.shared.play(.go)
    }

    func throwDart(velocity: CGSize, size: CGSize) {
        guard phase == .playing, pause <= 0, darts.count < Self.dartsPerVolley,
              darts.last.map({ $0.t >= Self.flightTime }) ?? true,
              size.width > 0, size.height > 0 else { return }
        let power = -Double(velocity.height) / Double(size.height)
        guard power > 0.5 else { return }
        // Visée : le côté vient du geste, la hauteur de la force. Un peu de tremblement de la main.
        let x = Double(velocity.width) / Double(size.width) * 0.55 + gaussian() * 0.07
        let y = (power / Self.idealPower - 1) * 1.7 + gaussian() * 0.07
        let hit = Dartboard.score(x: x, y: y)
        darts.append(Dart(x: x, y: y, points: hit.points, label: hit.label))
        Haptics.tap()
    }

    func tick(dt: Double) {
        guard phase == .playing else { return }
        if pause > 0 {
            pause -= dt
            if pause <= 0 { nextTurn() }
            return
        }
        for i in darts.indices where darts[i].t < Self.flightTime {
            darts[i].t += dt
            if darts[i].t >= Self.flightTime {
                let d = darts[i]
                scores[current] += d.points
                volleyPoints += d.points
                message = d.points == 0 ? L("Raté") : "\(d.label) · +\(d.points)"
                if d.points >= 50 { Haptics.success(); SoundPlayer.shared.play(.vault, volume: 0.6) }
                else if d.points > 0 { Haptics.correct(subtle: true); SoundPlayer.shared.play(.clunk, volume: 0.6) }
                else { SoundPlayer.shared.play(.wrong, volume: 0.4) }
                if darts.count == Self.dartsPerVolley {
                    pause = 1.1
                    message = L("Volée : \(volleyPoints) points")
                }
            }
        }
    }

    private func nextTurn() {
        darts = []
        volleyPoints = 0
        message = nil
        if players == 2 && current == 0 {
            current = 1
            return
        }
        current = 0
        if volley >= volleys {
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
            Haptics.success()
        } else {
            volley += 1
        }
    }

    private func gaussian() -> Double {
        let u1 = Double.random(in: 0.0001...1)
        let u2 = Double.random(in: 0...1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

// MARK: - Écran

struct FlechettesView: View {
    @Environment(AppState.self) private var app
    @State private var game = DartsGame()

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            GameHeader(title: L("FLÉCHETTES"), subtitle: headerText, onBack: { app.route = .hub }) {
                if game.phase == .playing {
                    Pill(text: L("Volée \(game.volley)/\(game.volleys)"), color: Theme.card)
                }
            }
            .padding(.horizontal, 16)

            GeometryReader { proxy in
                ZStack {
                    DartsScene(game: game)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onEnded { value in game.throwDart(velocity: value.velocity, size: proxy.size) }
                        )
                    if game.phase != .playing {
                        overlay
                    }
                }
            }
        }
        .padding(.top, 8)
        .onReceive(ticker) { _ in
            let wasPlaying = game.phase == .playing
            game.tick(dt: 1.0 / 60.0)
            if wasPlaying && game.phase == .over && game.players == 1 {
                app.recordFlechettes(game.scores[0])
            }
        }
    }

    private var headerText: String {
        switch game.phase {
        case .playing:
            return game.players == 2
                ? L("Joueur \(game.current + 1) · \(game.scores[0]) – \(game.scores[1])")
                : L("\(game.scores[0]) points · record \(app.flechettesBest)")
        default:
            return L("Record solo : \(app.flechettesBest) points")
        }
    }

    private var overlay: some View {
        VStack(spacing: 14) {
            if game.phase == .over {
                if game.players == 2 {
                    let a = game.scores[0]
                    let b = game.scores[1]
                    Text(a == b ? L("Égalité !") : L("Joueur \(a > b ? 1 : 2) gagne !"))
                        .font(.plie(30))
                    Text("\(a) – \(b)")
                        .font(.plie(22, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text(L("Partie terminée"))
                        .font(.plie(30))
                    Text(L("\(game.scores[0]) points en 10 volées"))
                        .font(.plie(18, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Image(systemName: "scope")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.darts)
                Text(L("Lance d'un glissé vers le haut"))
                    .font(.plie(22))
                    .multilineTextAlignment(.center)
                Text(L("Le côté vient de la direction du geste, la hauteur de sa force. Sur iPhone Duo, plie-le en L en paysage : la cible se dresse devant toi."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button(L("Solo")) { game.start(players: 1) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.darts))
                Button(L("À deux")) { game.start(players: 2) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.cardHigh))
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

struct DartsScene: View {
    let game: DartsGame

    var body: some View {
        let darts = game.darts
        let message = game.message
        let left = game.throwsLeft
        let playing = game.phase == .playing

        Canvas { context, size in
            let w = size.width
            let h = size.height
            let fold = h * 0.5

            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: fold)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x231A2E), Color(hex: 0x332540)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: fold)))
            context.fill(Path(CGRect(x: 0, y: fold, width: w, height: h - fold)), with: .color(Color(hex: 0x17131F)))
            context.stroke(Path(CGRect(x: 0, y: fold - 0.5, width: w, height: 1)), with: .color(.white.opacity(0.08)), lineWidth: 1)

            // Cible
            let center = CGPoint(x: w / 2, y: fold * 0.52)
            let R = min(fold * 0.4, w * 0.36)
            let outer = R * 1.16
            context.fill(Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)),
                         with: .color(Color(hex: 0x111111)))
            let sector = 2 * Double.pi / 20
            for i in 0..<20 {
                let a0 = -Double.pi / 2 - sector / 2 + Double(i) * sector
                let a1 = a0 + sector
                let even = i % 2 == 0
                func ring(_ r0: Double, _ r1: Double) -> Path {
                    var p = Path()
                    p.addArc(center: center, radius: R * r1, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                    p.addArc(center: center, radius: R * r0, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                    p.closeSubpath()
                    return p
                }
                let plain = even ? Color(hex: 0x1C1C1C) : Color(hex: 0xEFE3C8)
                let accent = even ? Color(hex: 0xD8343F) : Color(hex: 0x1E8B4E)
                context.fill(ring(Dartboard.outerBull, Dartboard.tripleIn), with: .color(plain))
                context.fill(ring(Dartboard.tripleIn, Dartboard.tripleOut), with: .color(accent))
                context.fill(ring(Dartboard.tripleOut, Dartboard.doubleIn), with: .color(plain))
                context.fill(ring(Dartboard.doubleIn, 1), with: .color(accent))
                let mid = (a0 + a1) / 2
                let label = CGPoint(x: center.x + CGFloat(cos(mid)) * R * 1.08, y: center.y + CGFloat(sin(mid)) * R * 1.08)
                context.draw(Text("\(Dartboard.numbers[i])").font(.system(size: max(8, R * 0.09), weight: .bold, design: .rounded)).foregroundColor(.white),
                             at: label)
            }
            let ob = R * Dartboard.outerBull
            context.fill(Path(ellipseIn: CGRect(x: center.x - ob, y: center.y - ob, width: ob * 2, height: ob * 2)), with: .color(Color(hex: 0x1E8B4E)))
            let b = R * Dartboard.bull
            context.fill(Path(ellipseIn: CGRect(x: center.x - b, y: center.y - b, width: b * 2, height: b * 2)), with: .color(Color(hex: 0xD8343F)))

            // Fléchettes
            for d in darts {
                let s = min(1, d.t / DartsGame.flightTime)
                let target = CGPoint(x: center.x + CGFloat(d.x) * R, y: center.y - CGFloat(d.y) * R)
                let start = CGPoint(x: w / 2, y: h * 0.85)
                let p = CGPoint(x: start.x + (target.x - start.x) * CGFloat(s), y: start.y + (target.y - start.y) * CGFloat(s))
                let len = (s < 1 ? 46 : 22) * (1 - 0.5 * CGFloat(s))
                var shaft = Path()
                shaft.move(to: p)
                shaft.addLine(to: CGPoint(x: p.x, y: p.y + len))
                context.stroke(shaft, with: .color(Color(hex: 0xC9CED9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                var flight = Path()
                flight.move(to: CGPoint(x: p.x, y: p.y + len))
                flight.addLine(to: CGPoint(x: p.x - 7, y: p.y + len + 10))
                flight.addLine(to: CGPoint(x: p.x + 7, y: p.y + len + 10))
                flight.closeSubpath()
                context.fill(flight, with: .color(Theme.darts))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
            }

            // Fléchettes restantes, en bas
            if playing {
                for i in 0..<max(0, left) {
                    let x = w / 2 + CGFloat(i - 1) * 34
                    var shaft = Path()
                    shaft.move(to: CGPoint(x: x, y: h * 0.78))
                    shaft.addLine(to: CGPoint(x: x, y: h * 0.78 + 46))
                    context.stroke(shaft, with: .color(Color(hex: 0xC9CED9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    var flight = Path()
                    flight.move(to: CGPoint(x: x, y: h * 0.78 + 46))
                    flight.addLine(to: CGPoint(x: x - 8, y: h * 0.78 + 58))
                    flight.addLine(to: CGPoint(x: x + 8, y: h * 0.78 + 58))
                    flight.closeSubpath()
                    context.fill(flight, with: .color(Theme.darts))
                }
            }

            if let message {
                context.draw(Text(message).font(.plie(24)).foregroundColor(.white),
                             at: CGPoint(x: w / 2, y: fold + (h - fold) * 0.18))
            }
        }
        .accessibilityLabel(L("Cible de fléchettes"))
    }
}
