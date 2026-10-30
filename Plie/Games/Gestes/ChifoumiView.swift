import SwiftUI

// MARK: - CHIFOUMI
//
// À deux : celui qui tient le Duo choisit en secret sur l'écran intérieur. En face, l'autre voit le décompte
// « Chi… Fou… MI ! » sur l'écran extérieur et montre sa main à la caméra du dos : pierre, feuille ou ciseaux.
// Seul : on montre sa main à la caméra de devant, contre le téléphone.

@Observable
final class ChifoumiGame {
    enum Mode { case duo, solo }
    enum Phase: Equatable { case menu, ready, chant(Int), shoot, reveal, over }
    enum Outcome { case inner, camera, tie, unseen, late }

    private(set) var phase: Phase = .menu
    private(set) var mode: Mode = .duo
    var target = 3
    /// [0] : le côté écran intérieur (celui qui tient le Duo, ou le téléphone en solo).
    /// [1] : le côté caméra (la personne en face, ou toi en solo).
    private(set) var scores = [0, 0]
    /// Duo : le choix secret de celui qui tient le Duo. Solo : le choix du téléphone (tiré au « MI ! »).
    var innerPick: HandReading.Shape?
    /// La main vue par la caméra au « MI ! ».
    private(set) var cameraPick: HandReading.Shape?
    private(set) var outcome: Outcome?
    /// Ce que la caméra voit en ce moment (pour aider à placer sa main).
    private(set) var live: HandReading.Shape?
    private(set) var round = 0

    @ObservationIgnored private var window = ReadingWindow<HandReading.Shape>()
    @ObservationIgnored private let timeline = GestesTimeline()

    static let beats = 3

    func beat(_ i: Int) -> String {
        switch i {
        case 0: return L("Chi…")
        case 1: return L("Fou…")
        default: return L("MI !")
        }
    }

    var innerName: String { mode == .duo ? L("Toi") : L("Téléphone") }
    var cameraName: String { mode == .duo ? L("En face") : L("Toi") }

    func start(_ mode: Mode) {
        self.mode = mode
        scores = [0, 0]
        round = 0
        nextRound()
    }

    func backToMenu() {
        timeline.cancel()
        phase = .menu
    }

    func nextRound() {
        timeline.cancel()
        round += 1
        innerPick = nil
        cameraPick = nil
        outcome = nil
        window.reset()
        phase = .ready
        for i in 0..<Self.beats {
            timeline.after(0.9 + 0.75 * Double(i)) { [weak self] in
                guard let self else { return }
                if i < Self.beats - 1 {
                    self.phase = .chant(i)
                    SoundPlayer.shared.play(.tock, volume: 0.8)
                    Haptics.tap()
                } else {
                    self.window.reset()
                    self.phase = .shoot
                    SoundPlayer.shared.play(.go, volume: 0.8)
                    Haptics.correct(subtle: false)
                }
            }
        }
        // Une seconde pour montrer sa main bien en face de la caméra.
        timeline.after(0.9 + 0.75 * Double(Self.beats - 1) + 1.1) { [weak self] in self?.resolve() }
    }

    /// Les mains vues par la caméra (environ dix fois par seconde).
    func receive(_ hands: [HandReading]) {
        let shape = hands.compactMap(\.shape).first
        live = shape
        if phase == .shoot, let shape { window.add(shape) }
    }

    private func resolve() {
        guard phase == .shoot else { return }
        if mode == .solo { innerPick = HandReading.Shape.allCases.randomElement() }
        guard let seen = window.mostFrequent()?.value else {
            outcome = .unseen
            phase = .reveal
            SoundPlayer.shared.play(.wrong, volume: 0.6)
            timeline.after(2.2) { [weak self] in self?.nextRound() }
            return
        }
        cameraPick = seen
        guard let inner = innerPick else {
            outcome = .late
            phase = .reveal
            SoundPlayer.shared.play(.wrong, volume: 0.6)
            timeline.after(2.4) { [weak self] in self?.nextRound() }
            return
        }
        if inner == seen {
            outcome = .tie
            SoundPlayer.shared.play(.pop, volume: 0.7)
        } else if inner.beats(seen) {
            outcome = .inner
            scores[0] += 1
            SoundPlayer.shared.play(.point, volume: 0.8)
        } else {
            outcome = .camera
            scores[1] += 1
            SoundPlayer.shared.play(.point, volume: 0.8)
        }
        phase = .reveal
        timeline.after(2.6) { [weak self] in
            guard let self else { return }
            if self.scores.max() ?? 0 >= self.target {
                self.phase = .over
                SoundPlayer.shared.play(.win, volume: 0.8)
            } else {
                self.nextRound()
            }
        }
    }

    /// La phrase du résultat, vue depuis l'écran intérieur.
    var resultText: String {
        guard let outcome else { return "" }
        switch outcome {
        case .unseen: return L("Main pas vue ! Montre-la bien à la caméra. On rejoue.")
        case .late: return L("Il fallait choisir avant « MI ! ». On rejoue.")
        case .tie: return L("Égalité ! On rejoue la manche.")
        case .inner, .camera:
            guard let a = innerPick, let b = cameraPick else { return "" }
            let winner = outcome == .inner ? a : b
            let loser = outcome == .inner ? b : a
            let point: String
            switch (mode, outcome) {
            case (.duo, .inner), (.solo, .camera): point = L("Point pour toi !")
            case (.duo, _): point = L("Point pour l'autre !")
            default: point = L("Point pour le téléphone !")
            }
            return L("\(winner.name) bat \(loser.name.lowercased()).") + " " + point
        }
    }

    /// Le titre de fin, vu depuis l'écran intérieur.
    var overTitle: String {
        let innerWon = scores[0] > scores[1]
        switch mode {
        case .duo: return innerWon ? L("Tu as gagné !") : L("La personne en face gagne !")
        case .solo: return innerWon ? L("Le téléphone gagne !") : L("Tu as gagné !")
        }
    }
}

// MARK: - Écran intérieur

struct ChifoumiView: View {
    @Environment(AppState.self) private var app
    @State private var game = ChifoumiGame()
    @State private var camera = GestureCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = true
    @State private var outerAvailable = false

    private var twoScreens: Bool { outerAvailable && cameraOn }

    var body: some View {
        GestesScreen {
            switch game.phase {
            case .menu: menu
            case .over: over
            default: play
            }
        }
        .onAppear {
            camera.detectsHands = true
            camera.onHands = { [game] hands in game.receive(hands) }
            camera.start(position: .back) { ok in cameraOn = ok }
        }
        .onDisappear {
            camera.stop()
            game.backToMenu()
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordChifoumi() }
        }
        // En face, l'autre joueur suit le décompte et le résultat sur l'écran extérieur.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            ChifoumiOuterView(game: game)
        }
    }

    private func start(_ mode: ChifoumiGame.Mode) {
        // À deux, la caméra du dos regarde la personne en face. Seul, celle de devant te regarde.
        camera.switchTo(mode == .duo ? .back : .front) { ok in cameraOn = ok }
        outerEnabled = mode == .duo
        game.start(mode)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .chifoumi)
            Spacer()
            if game.phase != .menu {
                GestesScore(name: game.innerName, points: game.scores[0], color: Theme.chifoumi)
                GestesScore(name: game.cameraName, points: game.scores[1], color: Theme.sun)
            }
        }
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                Text(verbatim: "✊ ✋ ✌️")
                    .font(.system(size: 54))
                    .accessibilityHidden(true)
                Text(L("CHIFOUMI")).font(.paperTitle(40))
                Text(L("Pierre, feuille, ciseaux… sans toucher l'écran : la caméra lit ta main."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                GestesModeButton(symbol: "person.2.fill", title: L("À deux"),
                                 detail: twoScreens ? L("Ouvre le Duo comme un livre : tu choisis en secret, et en face, on montre sa main à la caméra du dos.")
                                                    : L("Tourne le dos du téléphone vers l'autre joueur : tu choisis en secret, il montre sa main à la caméra."),
                                 color: Theme.chifoumi) { start(.duo) }
                GestesModeButton(symbol: "iphone", title: L("Contre le téléphone"),
                                 detail: L("Montre ta main à la caméra de devant au « MI ! ». Le téléphone choisit au même moment."),
                                 color: Theme.sun) { start(.solo) }

                Picker(L("Manches"), selection: $game.target) {
                    Text(L("En 3 points")).tag(3)
                    Text(L("En 5 points")).tag(5)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Text(L("La caméra reconnaît la main directement sur le téléphone. Rien n'est enregistré."))
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

    // MARK: La partie

    private var bigText: String {
        switch game.phase {
        case .ready: return game.mode == .duo ? L("Choisis en secret !") : L("Prépare ta main…")
        case .chant(let i): return game.beat(i)
        case .shoot: return game.beat(ChifoumiGame.beats - 1)
        default: return ""
        }
    }

    private var play: some View {
        VStack(spacing: 14) {
            header
            Text(L("Manche \(game.round)"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Paper.inkSoft)
            if game.phase == .reveal {
                reveal
            } else {
                Text(bigText)
                    .font(.paperTitle(game.phase == .shoot ? 64 : 48))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(height: 76)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: bigText)
            }
            GestesCameraCard(session: camera.session, ready: cameraOn,
                             label: game.live.map { L("Je vois : \($0.emoji) \($0.name)") } ?? L("Montre une main à la caméra"),
                             height: game.mode == .duo ? 150 : 230)
            if game.mode == .duo {
                picks
            } else {
                Text(L("Montre pierre ✊, feuille ✋ ou ciseaux ✌️ au « MI ! », et garde la main immobile une seconde."))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    /// Les trois choix secrets de celui qui tient le Duo.
    private var picks: some View {
        let open = game.phase != .reveal
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(HandReading.Shape.allCases, id: \.self) { shape in
                    Button {
                        game.innerPick = shape
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 4) {
                            Text(verbatim: shape.emoji).font(.system(size: 44))
                            Text(shape.name).font(.system(.footnote, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(game.innerPick == shape ? Theme.chifoumi.paperTone() : Paper.sheet)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(game.innerPick == shape ? Paper.ink : Paper.shadow.opacity(0.12),
                                              lineWidth: game.innerPick == shape ? 2.5 : 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!open)
                    .accessibilityAddTraits(game.innerPick == shape ? .isSelected : [])
                }
            }
            Text(game.innerPick == nil ? L("Choisis avant « MI ! » : l'autre ne voit pas ton écran.")
                                       : L("Choisi ! Tu peux encore changer avant « MI ! »."))
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Paper.inkSoft)
        }
    }

    private var reveal: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                hand(game.innerPick, name: game.innerName)
                Text(verbatim: "vs")
                    .font(.plie(20))
                    .foregroundStyle(Paper.inkSoft)
                hand(game.cameraPick, name: game.cameraName)
            }
            Text(game.resultText)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 76)
        .transition(.scale.combined(with: .opacity))
    }

    private func hand(_ shape: HandReading.Shape?, name: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: shape?.emoji ?? "❔").font(.system(size: 56))
            Text(name).font(.system(.footnote, design: .rounded, weight: .bold))
        }
    }

    // MARK: Fin

    private var over: some View {
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                WinIcon(systemName: "trophy.fill", color: Theme.chifoumi.paperTone())
                Text(game.overTitle)
                    .font(.paperTitle(30))
                    .multilineTextAlignment(.center)
                Text("\(game.scores[0]) – \(game.scores[1])")
                    .font(.plie(28))
                    .monospacedDigit()
                Button(L("Rejouer")) { game.start(game.mode) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.chifoumi, textColor: Paper.ink))
                Button(L("Menu")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(24)
            .winCard(accent: Theme.chifoumi.paperTone())
            .frame(maxWidth: 460)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Écran extérieur (la personne en face)

struct ChifoumiOuterView: View {
    let game: ChifoumiGame

    var body: some View {
        GestesOuterScreen {
            VStack(spacing: 14) {
                switch game.phase {
                case .menu:
                    Text(verbatim: "✊ ✋ ✌️").font(.system(size: 64))
                    Text(L("CHIFOUMI")).font(.paperTitle(40))
                    Text(L("Prépare ta main : tu joueras devant la caméra."))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                case .ready:
                    Text(L("Prépare ta main…")).font(.paperTitle(40)).multilineTextAlignment(.center)
                    liveLine
                case .chant(let i):
                    Text(game.beat(i)).font(.paperTitle(88)).minimumScaleFactor(0.5)
                    liveLine
                case .shoot:
                    Text(game.beat(ChifoumiGame.beats - 1)).font(.paperTitle(110)).minimumScaleFactor(0.5)
                    Text(L("Montre ta main !")).font(.system(.title2, design: .rounded, weight: .bold))
                case .reveal:
                    HStack(spacing: 30) {
                        VStack {
                            Text(verbatim: game.cameraPick?.emoji ?? "❔").font(.system(size: 84))
                            Text(L("Toi")).font(.system(.title3, design: .rounded, weight: .bold))
                        }
                        VStack {
                            Text(verbatim: game.innerPick?.emoji ?? "❔").font(.system(size: 84))
                            Text(L("L'autre")).font(.system(.title3, design: .rounded, weight: .bold))
                        }
                    }
                    Text(outerResult).font(.paperTitle(36)).multilineTextAlignment(.center)
                case .over:
                    Text(game.scores[1] > game.scores[0] ? L("Tu as gagné !") : L("L'autre a gagné !"))
                        .font(.paperTitle(48))
                        .multilineTextAlignment(.center)
                }
                if game.phase != .menu {
                    Text(L("Toi \(game.scores[1]) · \(game.scores[0]) L'autre"))
                        .font(.plie(26))
                        .monospacedDigit()
                        .padding(.top, 6)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private var liveLine: some View {
        Text(game.live.map { L("La caméra voit : \($0.emoji)") } ?? L("Place ta main face à la caméra"))
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .opacity(0.75)
    }

    private var outerResult: String {
        switch game.outcome {
        case .camera: return L("Gagné !")
        case .inner: return L("Perdu…")
        case .tie: return L("Égalité !")
        case .unseen: return L("Main pas vue ! On rejoue.")
        case .late: return L("On rejoue !")
        case .none: return ""
        }
    }
}
