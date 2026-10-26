import SwiftUI

extension Theme {
    static let mots = Color(hex: 0xFF5E7E)
    static let motsTeamA = Color(hex: 0xFF5E7E)
    static let motsTeamB = Color(hex: 0x4FB3FF)
}

// MARK: - MOTS INTERDITS
//
// Celui qui fait deviner tient le Duo ouvert comme un livre : lui seul voit le mot et les cinq mots
// interdits. En face, l'écran extérieur montre aux autres le chrono, le score, et chaque mot trouvé.
// La caméra les prend en photo au moment où ils trouvent.

struct MotsFound: Identifiable {
    let id = UUID()
    let word: String
    let photo: UIImage?
}

@Observable
final class MotsGame {
    enum Phase: Equatable { case menu, ready, playing, roundEnd, over }
    enum Mode: Equatable { case teams, together }
    enum Event: Equatable { case found, passed, foul }

    var mode: Mode = .teams
    var duration = 60
    var roundsPerTeam = 3

    private(set) var phase: Phase = .menu
    private(set) var team = 0
    private(set) var roundIndex = 0
    private(set) var scores = [0, 0]
    private(set) var card = MotsCard("", [])
    private(set) var secondsLeft = 60
    private(set) var roundFound: [MotsFound] = []
    private(set) var roundPassed: [String] = []
    private(set) var roundFouls = 0
    /// Le dernier coup (pour l'écran extérieur) : quoi, quel mot, et un numéro pour relancer l'animation.
    private(set) var event: Event?
    private(set) var eventWord = ""
    private(set) var eventCount = 0

    @ObservationIgnored private(set) var timeLeft: Double = 60
    @ObservationIgnored var takePhoto: (() -> UIImage?)?

    var roundScore: Int { roundFound.count - roundFouls }
    var totalRounds: Int { mode == .teams ? roundsPerTeam * 2 : 1 }

    static func teamName(_ t: Int) -> String { t == 0 ? L("Équipe Rose") : L("Équipe Bleue") }
    static func teamColor(_ t: Int) -> Color { t == 0 ? Theme.motsTeamA : Theme.motsTeamB }

    // MARK: Partie

    func start() {
        scores = [0, 0]
        team = 0
        roundIndex = 0
        phase = .ready
    }

    func backToMenu() {
        phase = .menu
    }

    /// Le joueur qui fait deviner a le Duo en main : c'est parti.
    func go() {
        guard phase == .ready else { return }
        roundFound = []
        roundPassed = []
        roundFouls = 0
        event = nil
        timeLeft = Double(duration)
        secondsLeft = duration
        drawCard()
        phase = .playing
        SoundPlayer.shared.play(.go, volume: 0.8)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func tick(_ dt: Double) {
        guard phase == .playing else { return }
        timeLeft -= dt
        let s = max(0, Int(ceil(timeLeft)))
        if s != secondsLeft {
            secondsLeft = s
            if s <= 5 && s > 0 { SoundPlayer.shared.play(.clockTick, volume: 0.9) }
        }
        if timeLeft <= 0 { endRound() }
    }

    func found() {
        guard phase == .playing else { return }
        roundFound.append(MotsFound(word: card.word, photo: takePhoto?()))
        announce(.found)
        SoundPlayer.shared.play(.point, volume: 0.9)
        Haptics.success()
        drawCard()
    }

    func pass() {
        guard phase == .playing else { return }
        roundPassed.append(card.word)
        announce(.passed)
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        Haptics.tap()
        drawCard()
    }

    /// Un mot interdit a été dit : un point de moins, et on change de carte.
    func foul() {
        guard phase == .playing else { return }
        roundFouls += 1
        roundPassed.append(card.word)
        announce(.foul)
        SoundPlayer.shared.play(.buzzer, volume: 0.9)
        Haptics.error()
        drawCard()
    }

    private func announce(_ e: Event) {
        event = e
        eventWord = card.word
        eventCount += 1
    }

    private func endRound() {
        timeLeft = 0
        secondsLeft = 0
        UIApplication.shared.isIdleTimerDisabled = false
        if mode == .teams { scores[team] += roundScore } else { scores[0] = roundScore }
        phase = .roundEnd
        SoundPlayer.shared.play(.buzzer, volume: 0.8)
        Haptics.warning()
    }

    /// Après le bilan de la manche : l'autre équipe, ou la fin.
    func nextRound() {
        guard phase == .roundEnd else { return }
        roundIndex += 1
        if roundIndex >= totalRounds {
            phase = .over
            SoundPlayer.shared.play(.applause, volume: 0.8)
            return
        }
        team = mode == .teams ? roundIndex % 2 : 0
        phase = .ready
    }

    func stopEarly() {
        guard phase == .playing else { return }
        endRound()
    }

    var winnerTeam: Int? {
        guard mode == .teams else { return nil }
        if scores[0] == scores[1] { return nil }
        return scores[0] > scores[1] ? 0 : 1
    }

    // MARK: Les cartes, sans revoir les mêmes de sitôt

    private func drawCard() {
        let cards = MotsCards.current
        guard !cards.isEmpty else { return }
        let lang = Lang.shared.isEnglish ? "en" : "fr"
        let orderKey = "mots.order.\(lang)", posKey = "mots.pos.\(lang)"
        let defaults = UserDefaults.standard
        var order = defaults.array(forKey: orderKey) as? [Int] ?? []
        var pos = defaults.integer(forKey: posKey)
        if order.count != cards.count || pos >= order.count {
            order = Array(0..<cards.count).shuffled()
            pos = 0
        }
        card = cards[order[pos]]
        defaults.set(order, forKey: orderKey)
        defaults.set(pos + 1, forKey: posKey)
    }
}

// MARK: - Écran de celui qui fait deviner

struct MotsView: View {
    @Environment(AppState.self) private var app
    @State private var game = MotsGame()
    @State private var camera = GuessersCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = true
    @State private var outerAvailable = false

    private var twoScreens: Bool { outerAvailable && cameraOn }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A0B1F), Color(hex: 0x0E1020)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch game.phase {
            case .menu: menu
            case .ready: ready
            case .playing: playing
            case .roundEnd: roundEnd
            case .over: over
            }
        }
        .foregroundStyle(.white)
        .onFrame(step: 1.0 / 30.0) { dt in game.tick(dt) }
        .onAppear {
            game.takePhoto = { [camera] in camera.snapshot() }
            camera.start { ok in cameraOn = ok }
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .roundEnd { app.recordMots(found: game.roundFound.count) }
        }
        // En face, les autres voient le chrono, le score et chaque mot trouvé.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            MotsOuterView(game: game)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .mots)
            Spacer()
            if game.phase == .playing {
                Text("\(game.roundScore)")
                    .font(.plie(22))
                    .foregroundStyle(Theme.go)
                    .accessibilityLabel(L("Score de la manche : \(game.roundScore)"))
                MotsTimer(seconds: game.secondsLeft, total: game.duration, color: MotsGame.teamColor(game.team))
                    .frame(width: 52, height: 52)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Text(verbatim: "🤐").font(.system(size: 60)).accessibilityHidden(true)
                Text(L("MOTS INTERDITS"))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(L("Fais deviner un mot sans dire les cinq mots interdits. Tiens le Duo ouvert comme un livre : toi seul vois la carte, les autres voient le chrono et le score sur l'écran extérieur."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                Label(twoScreens ? L("Écran extérieur prêt : les autres y verront le chrono") : L("Sans écran extérieur : garde la carte pour toi, et annonce le temps"),
                      systemImage: twoScreens ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(twoScreens ? Theme.go : Theme.gold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Picker(L("Mode"), selection: $game.mode) {
                    Text(L("Deux équipes")).tag(MotsGame.Mode.teams)
                    Text(L("Tous ensemble")).tag(MotsGame.Mode.together)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Picker(L("Durée"), selection: $game.duration) {
                    Text(L("45 s")).tag(45)
                    Text(L("60 s")).tag(60)
                    Text(L("90 s")).tag(90)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                if game.mode == .teams {
                    Picker(L("Manches"), selection: $game.roundsPerTeam) {
                        Text(L("2 manches chacune")).tag(2)
                        Text(L("3 manches chacune")).tag(3)
                        Text(L("4 manches chacune")).tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                }

                Button {
                    game.start()
                } label: {
                    Label(L("Jouer"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.mots, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)

                if app.motsBest > 0 {
                    Text(L("Record : \(app.motsBest) mots en une manche"))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Avant la manche

    private var ready: some View {
        VStack(spacing: 18) {
            header
            Spacer()
            if game.mode == .teams {
                Text(MotsGame.teamName(game.team))
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(MotsGame.teamColor(game.team))
                Text(L("Manche \(game.roundIndex / 2 + 1) sur \(game.roundsPerTeam)"))
                    .font(.plie(17, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            Image(systemName: "book.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Theme.mots)
            Text(L("Un joueur prend le Duo, ouvert comme un livre, l'écran extérieur tourné vers son équipe."))
                .font(.plie(19, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
            Text(L("Pas de geste, pas de traduction, pas de « ça commence par… » !"))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
            if game.mode == .teams {
                scoreLine
            }
            Spacer()
            Button {
                game.go()
            } label: {
                Label(L("Je fais deviner !"), systemImage: "play.fill")
            }
            .buttonStyle(ChunkyButtonStyle(color: MotsGame.teamColor(game.team), textColor: Theme.ink, height: 64))
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var scoreLine: some View {
        HStack(spacing: 18) {
            ForEach(0..<2, id: \.self) { t in
                VStack(spacing: 2) {
                    Text("\(game.scores[t])").font(.plie(30)).foregroundStyle(MotsGame.teamColor(t))
                    Text(MotsGame.teamName(t)).font(.plie(13, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: Pendant la manche

    private var playing: some View {
        VStack(spacing: 14) {
            header
            MotsCardView(card: game.card)
                .id(game.eventCount)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .padding(.horizontal, 18)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { game.pass() }
                } label: {
                    Label(L("Passer"), systemImage: "forward.fill")
                }
                .buttonStyle(GhostButtonStyle())
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { game.foul() }
                } label: {
                    Label(L("Mot interdit"), systemImage: "hand.raised.fill")
                        .font(.plie(16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.stop))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 18)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { game.found() }
            } label: {
                Label(L("Trouvé !"), systemImage: "checkmark")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.go, textColor: Theme.ink, height: 70))
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: Bilan de la manche

    private var roundEnd: some View {
        VStack(spacing: 12) {
            header
            Text(L("Temps écoulé !"))
                .font(.system(size: 32, weight: .black, design: .rounded))
            Text(L("\(game.roundFound.count) trouvé\(game.roundFound.count > 1 ? "s" : "") · \(game.roundFouls) faute\(game.roundFouls > 1 ? "s" : "") · \(game.roundScore) point\(abs(game.roundScore) > 1 ? "s" : "")"))
                .font(.plie(18, weight: .bold))
                .foregroundStyle(MotsGame.teamColor(game.team))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(game.roundFound) { f in
                        VStack(spacing: 6) {
                            if let photo = f.photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Text(f.word)
                                .font(.plie(16, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.go.opacity(0.18)))
                    }
                }
                .padding(.horizontal, 16)
                if !game.roundPassed.isEmpty {
                    Text(L("Pas trouvés : \(game.roundPassed.joined(separator: ", "))"))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            Button {
                game.nextRound()
            } label: {
                Label(game.roundIndex + 1 >= game.totalRounds ? L("Voir le résultat") : L("Manche suivante"), systemImage: "arrow.right")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.mots, textColor: Theme.ink, height: 58))
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: Fin

    private var over: some View {
        VStack(spacing: 16) {
            header
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.gold)
            if game.mode == .teams {
                if let w = game.winnerTeam {
                    Text(L("\(MotsGame.teamName(w)) gagne !"))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(MotsGame.teamColor(w))
                        .multilineTextAlignment(.center)
                } else {
                    Text(L("Égalité parfaite !"))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                }
                scoreLine
            } else {
                Text(L("\(game.scores[0]) point\(abs(game.scores[0]) > 1 ? "s" : "") ensemble"))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                Text(L("Record : \(app.motsBest) mots en une manche"))
                    .font(.plie(17, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            ShareResultButton(game: L("MOTS INTERDITS"),
                              result: game.mode == .teams ? "\(game.scores[0]) – \(game.scores[1])" : L("\(game.scores[0]) points"),
                              accent: Theme.mots)
                .frame(maxWidth: 380)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    game.start()
                } label: {
                    Label(L("Rejouer"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.mots, textColor: Theme.ink, height: 56))
                Button(L("Réglages")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 150)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

/// La carte : le mot en grand, les mots interdits en dessous.
struct MotsCardView: View {
    let card: MotsCard

    var body: some View {
        VStack(spacing: 0) {
            Text(card.word.uppercased())
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 92)
                .padding(.horizontal, 16)
                .background(Theme.mots)
            VStack(spacing: 8) {
                ForEach(card.banned, id: \.self) { w in
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.stop)
                        Text(w)
                            .font(.plie(21, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(Color(hex: 0xFFF6EC))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        .frame(maxWidth: 460)
        .accessibilityElement(children: .combine)
    }
}

/// Le chrono rond.
struct MotsTimer: View {
    let seconds: Int
    let total: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(seconds) / CGFloat(max(1, total)))
                .stroke(seconds <= 10 ? Theme.coral : color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: seconds)
            Text("\(seconds)")
                .font(.plie(18))
                .monospacedDigit()
                .foregroundStyle(seconds <= 10 ? Theme.coral : .white)
        }
        .accessibilityLabel(L("\(seconds) secondes"))
    }
}

// MARK: - Écran extérieur : ce que voient ceux qui devinent

struct MotsOuterView: View {
    let game: MotsGame

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A0B1F), Color(hex: 0x0E1020)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            content
                .padding(20)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch game.phase {
        case .menu:
            VStack(spacing: 12) {
                Text(verbatim: "🤐").font(.system(size: 70))
                Text(L("MOTS INTERDITS")).font(.system(size: 34, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
            }
        case .ready:
            VStack(spacing: 14) {
                Text(game.mode == .teams ? MotsGame.teamName(game.team) : L("Tous ensemble"))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(MotsGame.teamColor(game.team))
                    .multilineTextAlignment(.center)
                Text(L("Préparez-vous à deviner !"))
                    .font(.plie(24))
            }
        case .playing:
            VStack(spacing: 18) {
                Text(game.mode == .teams ? MotsGame.teamName(game.team) : L("Devinez !"))
                    .font(.plie(24))
                    .foregroundStyle(MotsGame.teamColor(game.team))
                MotsTimer(seconds: game.secondsLeft, total: game.duration, color: MotsGame.teamColor(game.team))
                    .frame(width: 170, height: 170)
                    .scaleEffect(1.0)
                eventBanner
                    .id(game.eventCount)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.eventCount)
                Text(L("\(game.roundFound.count) trouvé\(game.roundFound.count > 1 ? "s" : "")"))
                    .font(.plie(26))
                    .foregroundStyle(Theme.go)
            }
        case .roundEnd:
            VStack(spacing: 14) {
                Text(L("Temps écoulé !")).font(.system(size: 40, weight: .black, design: .rounded))
                Text(L("\(game.roundScore) point\(abs(game.roundScore) > 1 ? "s" : "")"))
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(MotsGame.teamColor(game.team))
            }
        case .over:
            VStack(spacing: 14) {
                Image(systemName: "trophy.fill").font(.system(size: 60, weight: .bold)).foregroundStyle(Theme.gold)
                if let w = game.winnerTeam {
                    Text(L("\(MotsGame.teamName(w)) gagne !"))
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(MotsGame.teamColor(w))
                        .multilineTextAlignment(.center)
                } else if game.mode == .teams {
                    Text(L("Égalité parfaite !")).font(.system(size: 38, weight: .black, design: .rounded))
                } else {
                    Text(L("\(game.scores[0]) point\(abs(game.scores[0]) > 1 ? "s" : "") ensemble"))
                        .font(.system(size: 38, weight: .black, design: .rounded))
                }
                if game.mode == .teams {
                    Text("\(game.scores[0]) – \(game.scores[1])").font(.plie(34))
                }
            }
        }
    }

    @ViewBuilder
    private var eventBanner: some View {
        switch game.event {
        case .found:
            VStack(spacing: 4) {
                Text(L("TROUVÉ !")).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Theme.go)
                Text(game.eventWord).font(.plie(32)).lineLimit(1).minimumScaleFactor(0.5)
            }
        case .passed:
            VStack(spacing: 4) {
                Text(L("PASSÉ")).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Theme.muted)
                Text(game.eventWord).font(.plie(28)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.5)
            }
        case .foul:
            VStack(spacing: 4) {
                Text(L("MOT INTERDIT !")).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Theme.stop)
                Text(L("−1 point")).font(.plie(24))
            }
        case nil:
            Text(L("Écoutez bien…"))
                .font(.plie(26))
                .foregroundStyle(Theme.muted)
        }
    }
}
