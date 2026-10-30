import SwiftUI

// MARK: - CALCUL AUX DOIGTS
//
// Pour les enfants. Le calcul s'affiche sur l'écran extérieur ; l'enfant répond en levant ses doigts
// devant la caméra du dos, sans rien toucher. L'adulte tient le Duo ouvert et suit sur l'écran intérieur.
// Seul : le téléphone posé face à l'enfant, il montre ses doigts à la caméra de devant.

@Observable
final class DoigtsGame {
    enum Mode { case duo, solo }

    enum Level: Int, CaseIterable, Identifiable {
        case count, add, sub
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .count: return L("Compter")
            case .add: return L("Additions")
            case .sub: return L("Soustractions")
            }
        }

        var detail: String {
            switch self {
            case .count: return L("Compte les dessins et montre autant de doigts.")
            case .add: return L("3 + 2 : montre le résultat avec tes doigts.")
            case .sub: return L("7 − 3 : montre ce qu'il reste avec tes doigts.")
            }
        }

        var symbol: String {
            switch self {
            case .count: return "hand.raised.fingers.spread.fill"
            case .add: return "plus"
            case .sub: return "minus"
            }
        }
    }

    struct Question: Equatable {
        var a: Int
        var b: Int
        var level: Level
        /// Pour « Compter » : le dessin à compter.
        var item: String

        var answer: Int {
            switch level {
            case .count: return a
            case .add: return a + b
            case .sub: return a - b
            }
        }

        var text: String {
            switch level {
            case .count: return L("Combien ?")
            case .add: return "\(a) + \(b)"
            case .sub: return "\(a) − \(b)"
            }
        }
    }

    enum Phase: Equatable { case menu, question, right, over }

    static let count = 10
    private static let items = ["🍎", "⭐️", "🐟", "🌸", "🚗", "🎈", "🐞", "🍓", "🦆", "⚽️"]

    private(set) var phase: Phase = .menu
    private(set) var mode: Mode = .duo
    private(set) var level: Level = .count
    private(set) var questions: [Question] = []
    private(set) var index = 0
    private(set) var found = 0
    /// Doigts vus en ce moment (nil : pas de main).
    private(set) var live: Int?
    /// 0 à 1 : la bonne réponse est tenue depuis assez longtemps.
    private(set) var hold: Double = 0
    private(set) var started = Date()
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var window = ReadingWindow<Int>()
    @ObservationIgnored private var holdSince: Date?
    @ObservationIgnored private let timeline = GestesTimeline()
    private static let holdTime: TimeInterval = 0.7

    var question: Question? { questions.indices.contains(index) ? questions[index] : nil }

    var stars: Int {
        if found >= 9 { return 3 }
        if found >= 6 { return 2 }
        return found >= 1 ? 1 : 0
    }

    func start(_ level: Level, mode: Mode) {
        timeline.cancel()
        self.level = level
        self.mode = mode
        questions = Self.makeQuestions(level)
        index = 0
        found = 0
        started = Date()
        ask()
    }

    func backToMenu() {
        timeline.cancel()
        phase = .menu
    }

    private func ask() {
        window.reset()
        holdSince = nil
        hold = 0
        phase = .question
        SoundPlayer.shared.play(.pop, volume: 0.6)
    }

    /// Les mains vues par la caméra : on additionne les doigts des deux mains.
    func receive(_ hands: [HandReading]) {
        let total: Int? = hands.isEmpty ? nil : hands.reduce(0) { $0 + $1.fingers }
        live = total
        guard phase == .question, let question else { return }
        if let total { window.add(total) }
        // La bonne réponse doit être montrée un petit moment, pas sur une seule image.
        if total != nil, let best = window.mostFrequent(), best.value == question.answer,
           best.share >= 0.7, window.count >= 3 {
            let since = holdSince ?? Date()
            holdSince = since
            hold = min(1, Date().timeIntervalSince(since) / Self.holdTime)
            if hold >= 1 { right() }
        } else {
            holdSince = nil
            hold = 0
        }
    }

    /// L'adulte valide à la main, si la caméra a du mal à compter.
    func right() {
        guard phase == .question else { return }
        found += 1
        phase = .right
        SoundPlayer.shared.play(.chime, volume: 0.8)
        Haptics.correct(subtle: false)
        timeline.after(1.3) { [weak self] in self?.next() }
    }

    func skip() {
        guard phase == .question else { return }
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        next()
    }

    private func next() {
        if index + 1 >= questions.count {
            duration = Date().timeIntervalSince(started)
            phase = .over
            SoundPlayer.shared.play(found >= 6 ? .applause : .win, volume: 0.8)
            return
        }
        index += 1
        ask()
    }

    private static func makeQuestions(_ level: Level) -> [Question] {
        var list: [Question] = []
        var lastAnswer = -1
        while list.count < count {
            let q: Question
            let item = items.randomElement() ?? "🍎"
            switch level {
            case .count:
                q = Question(a: Int.random(in: 1...10), b: 0, level: level, item: item)
            case .add:
                let total = Int.random(in: 2...10)
                let a = Int.random(in: 1..<total)
                q = Question(a: a, b: total - a, level: level, item: item)
            case .sub:
                let a = Int.random(in: 2...10)
                let b = Int.random(in: 1..<a)
                q = Question(a: a, b: b, level: level, item: item)
            }
            // Pas deux fois de suite la même réponse.
            guard q.answer != lastAnswer else { continue }
            lastAnswer = q.answer
            list.append(q)
        }
        return list
    }
}

// MARK: - Écran intérieur

struct DoigtsView: View {
    @Environment(AppState.self) private var app
    @State private var game = DoigtsGame()
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
            if phase == .over { app.recordDoigts(level: game.level.rawValue, stars: game.stars) }
        }
        // L'enfant, en face, voit le calcul sur l'écran extérieur.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            DoigtsOuterView(game: game)
        }
    }

    private func start(_ level: DoigtsGame.Level, solo: Bool) {
        camera.switchTo(solo ? .front : .back) { ok in cameraOn = ok }
        outerEnabled = !solo
        game.start(level, mode: solo ? .solo : .duo)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .doigts)
            Spacer()
            if game.phase != .menu {
                GestesScore(name: L("Trouvés"), points: game.found, color: Theme.doigts)
            }
        }
    }

    // MARK: Menu

    @State private var solo = false

    private var menu: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Text(verbatim: "🖐️")
                    .font(.system(size: 54))
                    .accessibilityHidden(true)
                Text(L("CALCUL AUX DOIGTS")).font(.paperTitle(34)).multilineTextAlignment(.center)
                Text(L("Le calcul s'affiche, l'enfant lève ses doigts devant la caméra. Pas besoin de toucher l'écran."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                Picker(L("Comment"), selection: $solo) {
                    Text(L("Avec un adulte")).tag(false)
                    Text(L("Tout seul")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)

                Text(solo ? L("Pose le téléphone face à toi : la caméra de devant regarde tes doigts.")
                          : (twoScreens ? L("Ouvre le Duo comme un livre : l'enfant voit le calcul sur l'écran extérieur et répond à la caméra du dos.")
                                        : L("Tourne le dos du téléphone vers l'enfant : il montre ses doigts à la caméra.")))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Paper.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                ForEach(DoigtsGame.Level.allCases) { level in
                    GestesModeButton(symbol: level.symbol, title: level.title + stars(for: level),
                                     detail: level.detail, color: Theme.doigts) {
                        start(level, solo: solo)
                    }
                }

                Text(L("Jusqu'à 10 : avec les deux mains. La caméra compte les doigts directement sur le téléphone. Rien n'est enregistré."))
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

    private func stars(for level: DoigtsGame.Level) -> String {
        guard let n = app.doigtsStars[level.rawValue], n > 0 else { return "" }
        return "  " + String(repeating: "★", count: n)
    }

    // MARK: La partie

    private var play: some View {
        VStack(spacing: 14) {
            header
            Text(L("Question \(game.index + 1) sur \(DoigtsGame.count)"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Paper.inkSoft)
            if let q = game.question {
                DoigtsQuestionView(question: q, big: game.mode == .solo || !twoScreens)
                    .frame(maxHeight: game.mode == .solo ? 200 : 150)
                if game.mode == .duo {
                    Text(L("Réponse : \(q.answer)"))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Paper.inkSoft)
                }
            }
            GestesCameraCard(session: camera.session, ready: cameraOn, label: liveLabel,
                             height: game.mode == .solo ? 200 : 170)
                .overlay(alignment: .top) { holdBar }
            if game.phase == .right {
                Text(L("Bravo !"))
                    .font(.paperTitle(40))
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 12) {
                    Button(L("Passer")) { game.skip() }
                        .buttonStyle(GhostButtonStyle())
                    if game.mode == .duo {
                        Button(L("C'est juste")) { game.right() }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.doigts, textColor: Paper.ink, height: 52))
                    }
                }
                .frame(maxWidth: 460)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.phase)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var liveLabel: String {
        guard let n = game.live else { return L("Montre tes mains à la caméra") }
        return n == 1 ? L("Je vois 1 doigt") : L("Je vois \(n) doigts")
    }

    private var holdBar: some View {
        GeometryReader { g in
            Capsule()
                .fill(Theme.doigts)
                .frame(width: g.size.width * game.hold, height: 6)
                .animation(.easeOut(duration: 0.1), value: game.hold)
        }
        .frame(height: 6)
        .padding(10)
        .accessibilityHidden(true)
    }

    // MARK: Fin

    private var over: some View {
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                WinIcon(systemName: "hand.raised.fill", color: Theme.doigts.paperTone())
                Text(L("\(game.found) sur \(DoigtsGame.count) !"))
                    .font(.paperTitle(34))
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < game.stars ? "star.fill" : "star")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(i < game.stars ? Theme.star : Theme.emptyStar)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(L("\(game.stars) étoiles sur 3"))
                Text(L("En \(Int(game.duration.rounded())) secondes"))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Paper.inkSoft)
                Button(L("Rejouer")) { game.start(game.level, mode: game.mode) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.doigts, textColor: Paper.ink))
                Button(L("Menu")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(24)
            .winCard(accent: Theme.doigts.paperTone())
            .frame(maxWidth: 460)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Le calcul, ou les dessins à compter.
struct DoigtsQuestionView: View {
    let question: DoigtsGame.Question
    var big = false

    var body: some View {
        if question.level == .count {
            VStack(spacing: 6) {
                // Deux rangées de 5 au plus, comme les doigts des deux mains.
                let rows = question.a > 5 ? [5, question.a - 5] : [question.a]
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<rows[r], id: \.self) { _ in
                            Text(verbatim: question.item).font(.system(size: big ? 46 : 34))
                        }
                    }
                }
            }
            .minimumScaleFactor(0.4)
            .accessibilityElement()
            .accessibilityLabel(L("\(question.a) dessins à compter"))
        } else {
            Text(question.text)
                .font(.paperTitle(big ? 84 : 64))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

// MARK: - Écran extérieur (l'enfant)

struct DoigtsOuterView: View {
    let game: DoigtsGame

    var body: some View {
        GestesOuterScreen {
            VStack(spacing: 16) {
                switch game.phase {
                case .menu:
                    Text(verbatim: "🖐️").font(.system(size: 80))
                    Text(L("Prépare tes doigts !"))
                        .font(.paperTitle(40))
                case .question, .right:
                    if let q = game.question {
                        DoigtsQuestionView(question: q, big: true)
                            .frame(maxHeight: 260)
                    }
                    if game.phase == .right {
                        Text(L("Bravo !"))
                            .font(.paperTitle(60))
                            .foregroundStyle(Theme.go)
                    } else {
                        Text(live)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .opacity(0.8)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.08))
                                Capsule().fill(Theme.doigts).frame(width: g.size.width * game.hold)
                            }
                        }
                        .frame(width: 240, height: 10)
                    }
                    Text(L("Question \(game.index + 1) sur \(DoigtsGame.count)"))
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .opacity(0.6)
                case .over:
                    Text(verbatim: "🎉").font(.system(size: 80))
                    Text(L("\(game.found) sur \(DoigtsGame.count) !"))
                        .font(.paperTitle(56))
                    Text(String(repeating: "★", count: game.stars))
                        .font(.system(size: 50))
                        .foregroundStyle(Theme.star)
                }
            }
            .multilineTextAlignment(.center)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: game.phase)
        }
    }

    private var live: String {
        guard let n = game.live else { return L("Montre tes doigts à la caméra") }
        return n == 1 ? L("1 doigt") : L("\(n) doigts")
    }
}
