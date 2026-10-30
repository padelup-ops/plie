import SwiftUI
import UIKit

// MARK: - PAS DE SOURIRE !
//
// Chacun son tour, un joueur se place face à la caméra du dos et doit garder son sérieux.
// Celui qui tient le Duo fait le clown (grimaces, blagues, sons rigolos). Au premier sourire,
// la caméra prend une photo souvenir. Celui qui tient le plus longtemps gagne.

@Observable
final class SourireGame {
    enum Phase: Equatable { case menu, ready(Int), playing, caught, turnOver, over }

    static let maxTime: TimeInterval = 60

    private(set) var phase: Phase = .menu
    var players = 2
    private(set) var current = 0
    private(set) var times: [TimeInterval?] = []
    private(set) var photos: [Int: UIImage] = [:]
    /// Temps tenu par le joueur en cours (il n'avance que si son visage est vu).
    private(set) var elapsed: TimeInterval = 0
    private(set) var faceSeen = false
    private(set) var smiling = false
    private(set) var held = false

    @ObservationIgnored var takePhoto: (() -> UIImage?)?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var smileFrames = 0
    @ObservationIgnored private let timeline = GestesTimeline()

    func name(_ i: Int) -> String { L("Joueur \(i + 1)") }

    var currentName: String { name(current) }

    func start() {
        timeline.cancel()
        times = Array(repeating: nil, count: players)
        photos = [:]
        current = 0
        prepareTurn()
    }

    func backToMenu() {
        timeline.cancel()
        phase = .menu
    }

    private func prepareTurn() {
        elapsed = 0
        held = false
        smileFrames = 0
        lastTick = nil
        phase = .ready(3)
        for i in 0..<3 {
            timeline.after(0.9 * Double(i + 1)) { [weak self] in
                guard let self else { return }
                if i < 2 {
                    self.phase = .ready(2 - i)
                    SoundPlayer.shared.play(.tock, volume: 0.8)
                } else {
                    self.lastTick = nil
                    self.phase = .playing
                    SoundPlayer.shared.play(.go, volume: 0.8)
                    Haptics.correct(subtle: false)
                }
            }
        }
    }

    /// Le visage vu par la caméra (une dizaine de fois par seconde).
    func receive(seen: Bool, smiling: Bool) {
        faceSeen = seen
        self.smiling = smiling
        guard phase == .playing else { return }
        let now = Date()
        // Le chrono n'avance que si le visage est bien face à la caméra : pas de triche en se cachant.
        if let lastTick, seen { elapsed += min(0.3, now.timeIntervalSince(lastTick)) }
        lastTick = now
        smileFrames = seen && smiling ? smileFrames + 1 : 0
        if smileFrames >= 3 {
            caught()
        } else if elapsed >= Self.maxTime {
            finishTurn(held: true)
        }
    }

    /// Le clown peut aussi arrêter le tour à la main, s'il voit un sourire que la caméra a raté.
    func caught() {
        guard phase == .playing else { return }
        if let photo = takePhoto?() { photos[current] = photo }
        SoundPlayer.shared.play(.buzzer, volume: 0.8)
        Haptics.error()
        finishTurn(held: false)
    }

    private func finishTurn(held: Bool) {
        times[current] = min(elapsed, Self.maxTime)
        self.held = held
        phase = held ? .turnOver : .caught
        if held { SoundPlayer.shared.play(.applause, volume: 0.8) }
    }

    func nextTurn() {
        if current + 1 >= players {
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
        } else {
            current += 1
            prepareTurn()
        }
    }

    /// Les joueurs du plus sérieux au moins sérieux.
    var ranking: [(player: Int, time: TimeInterval)] {
        times.enumerated()
            .map { (player: $0.offset, time: $0.element ?? 0) }
            .sorted { $0.time > $1.time }
    }

    var best: TimeInterval { times.compactMap { $0 }.max() ?? 0 }

    static func format(_ t: TimeInterval) -> String {
        String(format: "%.1f s", t)
    }
}

// MARK: - Écran intérieur (le clown)

struct SourireView: View {
    @Environment(AppState.self) private var app
    @State private var game = SourireGame()
    @State private var camera = GestureCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = true
    @State private var outerAvailable = false
    @State private var idea = 0

    private var twoScreens: Bool { outerAvailable && cameraOn }

    private static let ideas = [
        "Fais ta plus belle grimace.",
        "Imite une poule qui a perdu son œuf.",
        "Raconte ta journée avec une voix de robot.",
        "Fais semblant de manger un citron.",
        "Danse sans musique, très sérieusement.",
        "Imite le prof ou le chef le plus sévère que tu connais.",
        "Fais le bruit d'un dinosaure qui éternue.",
        "Raconte une blague… très, très lentement.",
        "Parle comme un présentateur de journal télé.",
        "Fais semblant d'être une statue qui a envie d'éternuer.",
        "Chante une chanson avec la bouche fermée.",
        "Imite un chat qui voit un concombre."
    ]

    var body: some View {
        GestesScreen {
            switch game.phase {
            case .menu: menu
            case .over: over
            default: play
            }
        }
        .onAppear {
            camera.detectsHands = false
            camera.detectsSmile = true
            camera.onFace = { [game] seen, smiling in game.receive(seen: seen, smiling: smiling) }
            game.takePhoto = { [camera] in camera.snapshot() }
            camera.start(position: .back) { ok in cameraOn = ok }
        }
        .onDisappear {
            camera.stop()
            game.backToMenu()
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordSourire(best: game.best) }
        }
        // En face, celui qui garde son sérieux voit le chrono sur l'écran extérieur.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            SourireOuterView(game: game)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .sourire)
            Spacer()
            if game.phase != .menu && game.phase != .over {
                Text(game.players > 1 ? L("\(game.currentName) · \(game.current + 1)/\(game.players)") : game.currentName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(Theme.sourire.paperTone()))
            }
        }
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                Text(verbatim: "😐")
                    .font(.system(size: 60))
                    .accessibilityHidden(true)
                Text(L("PAS DE SOURIRE !")).font(.paperTitle(38)).multilineTextAlignment(.center)
                Text(L("Chacun son tour, un joueur regarde la caméra et garde son sérieux. Toi, fais-le craquer ! Au premier sourire, la caméra le prend en photo."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                VStack(spacing: 8) {
                    Text(L("Joueurs sérieux"))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Picker(L("Joueurs sérieux"), selection: $game.players) {
                        ForEach(1...6, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                }

                Button(L("C'est parti")) { game.start() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.sourire, textColor: Paper.ink))
                    .frame(maxWidth: 420)

                Text(twoScreens ? L("Ouvre le Duo comme un livre : le joueur sérieux voit son chrono sur l'écran extérieur.")
                                : L("Tourne le dos du téléphone vers le joueur sérieux : la caméra regarde son visage."))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Text(L("Le sourire est repéré directement sur le téléphone. Les photos restent dans la partie et disparaissent ensuite."))
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Un tour

    private var play: some View {
        VStack(spacing: 14) {
            header
            switch game.phase {
            case .ready(let n):
                Text(L("\(game.currentName), regarde la caméra…"))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(verbatim: "\(n)")
                    .font(.paperTitle(80))
                    .contentTransition(.numericText())
            case .playing:
                Text(SourireGame.format(game.elapsed))
                    .font(.paperTitle(64))
                    .monospacedDigit()
                Text(game.faceSeen ? (game.smiling ? L("Presque un sourire…") : L("Toujours sérieux. Fais-le craquer !"))
                                   : L("Je ne vois pas son visage : le chrono attend."))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
            case .caught, .turnOver:
                turnResult
            default:
                EmptyView()
            }

            if game.phase != .caught && game.phase != .turnOver {
                GestesCameraCard(session: camera.session, ready: cameraOn,
                                 label: game.faceSeen ? (game.smiling ? "😄" : "😐") : L("Visage pas vu"),
                                 height: 170)
            }

            if game.phase == .playing {
                clownTools
            } else if game.phase == .caught || game.phase == .turnOver {
                Button(game.current + 1 >= game.players ? L("Voir le classement") : L("Joueur suivant")) {
                    game.nextTurn()
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sourire, textColor: Paper.ink))
                .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    /// Des idées et des sons pour faire rire.
    private var clownTools: some View {
        VStack(spacing: 10) {
            Button {
                idea = (idea + 1) % Self.ideas.count
                Haptics.tap()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                    Text(L(key: Self.ideas[idea]))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Paper.sheet))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint(L("Une autre idée"))

            HStack(spacing: 10) {
                soundButton("🦁", .roar, L("Rugir"))
                soundButton("💥", .boom, L("Boum"))
                soundButton("😋", .chomp, L("Croc"))
                soundButton("📯", .buzzer, L("Pouet"))
                soundButton("👏", .applause, L("Bravo"))
            }

            Button(L("Il a souri !")) { game.caught() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: 520)
    }

    private func soundButton(_ emoji: String, _ effect: SoundPlayer.Effect, _ label: String) -> some View {
        Button {
            SoundPlayer.shared.play(effect)
        } label: {
            Text(verbatim: emoji)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sourire.paperTone().opacity(0.6)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var turnResult: some View {
        VStack(spacing: 10) {
            if let photo = game.photos[game.current] {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .rotationEffect(.degrees(-3))
                    .shadow(color: Paper.shadow.opacity(0.25), radius: 10, y: 6)
                    .accessibilityLabel(L("La photo du sourire"))
            } else {
                Text(verbatim: game.held ? "🗿" : "😄").font(.system(size: 80))
            }
            Text(game.held ? L("Imbattable ! \(game.currentName) a tenu \(Int(SourireGame.maxTime)) secondes.")
                           : L("\(game.currentName) a souri après \(SourireGame.format(game.times[game.current] ?? 0)) !"))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Fin

    private var over: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                VStack(spacing: 14) {
                    WinIcon(systemName: "face.dashed.fill", color: Theme.sourire.paperTone())
                    if let first = game.ranking.first {
                        Text(game.players == 1 ? L("Tu as tenu \(SourireGame.format(first.time)) !")
                                               : L("\(game.name(first.player)) est le plus sérieux !"))
                            .font(.paperTitle(28))
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(game.ranking.enumerated()), id: \.offset) { rank, entry in
                            HStack(spacing: 12) {
                                Text(verbatim: "\(rank + 1)")
                                    .font(.plie(18))
                                    .frame(width: 28)
                                if let photo = game.photos[entry.player] {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        .accessibilityHidden(true)
                                } else {
                                    Text(verbatim: "🗿").font(.system(size: 28)).frame(width: 40)
                                }
                                Text(game.name(entry.player))
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                Spacer()
                                Text(SourireGame.format(entry.time))
                                    .font(.plie(18))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(rank == 0 ? Theme.sourire.paperTone().opacity(0.7) : Paper.sheet))
                        }
                    }
                    Button(L("Rejouer")) { game.start() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.sourire, textColor: Paper.ink))
                    Button(L("Menu")) { game.backToMenu() }
                        .buttonStyle(GhostButtonStyle())
                }
                .padding(24)
                .winCard(accent: Theme.sourire.paperTone())
                .frame(maxWidth: 480)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Écran extérieur (le joueur sérieux)

struct SourireOuterView: View {
    let game: SourireGame

    var body: some View {
        GestesOuterScreen {
            VStack(spacing: 16) {
                switch game.phase {
                case .menu:
                    Text(verbatim: "😐").font(.system(size: 90))
                    Text(L("PAS DE SOURIRE !")).font(.paperTitle(44))
                    Text(L("Prépare ton visage le plus sérieux…"))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                case .ready(let n):
                    Text(L("\(game.currentName), à toi !")).font(.paperTitle(36))
                    Text(verbatim: "\(n)").font(.paperTitle(120))
                    Text(L("Regarde la caméra et ne souris pas."))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                case .playing:
                    Text(L("Ne souris pas !")).font(.paperTitle(40))
                    Text(SourireGame.format(game.elapsed))
                        .font(.paperTitle(100))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    if !game.faceSeen {
                        Text(L("Regarde la caméra : le chrono attend."))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.stop)
                    }
                case .caught:
                    if let photo = game.photos[game.current] {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .rotationEffect(.degrees(3))
                    }
                    Text(L("Tu as souri !")).font(.paperTitle(50))
                    Text(SourireGame.format(game.times[game.current] ?? 0))
                        .font(.plie(40))
                        .monospacedDigit()
                case .turnOver:
                    Text(verbatim: "🗿").font(.system(size: 100))
                    Text(L("Imbattable !")).font(.paperTitle(56))
                case .over:
                    if let first = game.ranking.first {
                        Text(verbatim: "🏆").font(.system(size: 90))
                        Text(L("\(game.name(first.player)) gagne !")).font(.paperTitle(48))
                        Text(SourireGame.format(first.time)).font(.plie(40)).monospacedDigit()
                    }
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}
