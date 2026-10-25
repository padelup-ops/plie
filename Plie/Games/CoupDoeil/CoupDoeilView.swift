import SwiftUI
import Combine

extension Theme {
    static let oeil = Color(hex: 0x4DD4C6)
}

// MARK: - Coup d'œil
//
// Duo ouvert : une image pleine de détails, à mémoriser en quelques secondes.
// Duo fermé : l'écran extérieur pose les questions. On rouvre : l'image revient, avec les réponses.

/// Générateur pseudo-aléatoire à graine : le défi du jour est le même pour tout le monde.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct OeilCell: Equatable {
    let emoji: String
    let tint: Int
}

struct OeilQuestion {
    let prompt: String
    let choices: [String]
    let correct: Int
    /// Cases à montrer au moment de vérifier.
    let cells: [Int]
}

struct OeilRound {
    let cols: Int
    let rows: Int
    let cells: [OeilCell?]
    let framed: Int?
    let questions: [OeilQuestion]
    let seconds: Double

    static let tints: [(UInt32, String)] = [(0xFF8A8A, "rouge"), (0x7FB3FF, "bleu"), (0x8BE08B, "vert"), (0xFFE066, "jaune"), (0xC9A3FF, "violet")]
    static let pools: [[String]] = [
        ["🐶", "🐱", "🐭", "🐰", "🦊", "🐻", "🐼", "🐸", "🐵", "🐔", "🐧", "🐢"],
        ["🍎", "🍌", "🍇", "🍓", "🍊", "🍍", "🥝", "🍒", "🍉", "🥕"],
        ["🚗", "🚌", "🚲", "✈️", "🚀", "⛵️", "🚂", "🚁"],
        ["⚽️", "🎈", "🎁", "🔑", "⏰", "📚", "✏️", "🎸", "🧸", "🎩"]
    ]

    static func colorName(_ i: Int) -> String { L(key: tints[i].1) }

    /// Une manche : plus le niveau monte, plus il y a d'objets et moins de temps.
    static func make(level: Int, seed: UInt64, questionCount: Int = 3) -> OeilRound {
        var rng = SeededRandom(seed: seed)
        let n = max(1, level)
        let (cols, rows): (Int, Int) = n <= 4 ? (3, 3) : (n <= 12 ? (4, 3) : (n <= 24 ? (4, 4) : (n <= 36 ? (5, 4) : (6, 4))))
        let total = cols * rows
        let filled = min(total, max(4, Int(Double(total) * (n <= 4 ? 0.55 : 0.75))))
        // Peu de sortes d'objets : il y a des doubles à compter.
        var pool: [String] = []
        let mix = n < 8 ? 1 : (n < 20 ? 2 : 3)
        for p in pools.shuffled(using: &rng).prefix(mix) { pool += p.shuffled(using: &rng).prefix(n < 8 ? 4 : 5) }
        var cells = [OeilCell?](repeating: nil, count: total)
        for index in Array(0..<total).shuffled(using: &rng).prefix(filled) {
            cells[index] = OeilCell(emoji: pool.randomElement(using: &rng) ?? "🍎", tint: Int.random(in: 0..<tints.count, using: &rng))
        }
        let used = cells.indices.filter { cells[$0] != nil }
        let framed = n >= 3 ? used.randomElement(using: &rng) : nil

        var questions: [OeilQuestion] = []
        var kinds = [0, 1, 2, 3, 4].shuffled(using: &rng)
        if framed == nil { kinds.removeAll { $0 == 2 } }
        if n < 6 { kinds.removeAll { $0 == 3 } }
        var attempts = 0
        while questions.count < questionCount && attempts < 40 {
            attempts += 1
            let kind = kinds[attempts % kinds.count]
            if let q = question(kind: kind, cells: cells, cols: cols, rows: rows, framed: framed, pool: pool, rng: &rng),
               !questions.contains(where: { $0.prompt == q.prompt }) {
                questions.append(q)
            }
        }
        let seconds = max(4, 10 - Double(n) * 0.12)
        return OeilRound(cols: cols, rows: rows, cells: cells, framed: framed, questions: questions, seconds: seconds)
    }

    private static func shuffledChoices(_ right: String, _ wrong: [String], rng: inout SeededRandom) -> (choices: [String], correct: Int) {
        var all = [right]
        for w in wrong where !all.contains(w) && all.count < 3 { all.append(w) }
        let shuffled = all.shuffled(using: &rng)
        return (shuffled, shuffled.firstIndex(of: right) ?? 0)
    }

    private static func question(kind: Int, cells: [OeilCell?], cols: Int, rows: Int, framed: Int?, pool: [String],
                                 rng: inout SeededRandom) -> OeilQuestion? {
        let present = cells.compactMap { $0?.emoji }
        // Toujours dans le même ordre (un Set change d'ordre d'un lancement à l'autre).
        let unique = Array(Set(present)).sorted()
        switch kind {
        case 0:
            // Combien de… ?
            guard let e = unique.randomElement(using: &rng) else { return nil }
            let count = present.filter { $0 == e }.count
            let c = shuffledChoices("\(count)", ["\(count + 1)", "\(max(0, count - 1))", "\(count + 2)"], rng: &rng)
            return OeilQuestion(prompt: L("Combien de \(e) ?"), choices: c.choices, correct: c.correct,
                                cells: cells.indices.filter { cells[$0]?.emoji == e })
        case 1:
            // Y avait-il… ?
            let absent = pool.filter { !unique.contains($0) }
            let askPresent = absent.isEmpty || Bool.random(using: &rng)
            guard let e = askPresent ? unique.randomElement(using: &rng) : absent.randomElement(using: &rng) else { return nil }
            return OeilQuestion(prompt: L("Y avait-il \(e) ?"), choices: [L("Oui"), L("Non")], correct: askPresent ? 0 : 1,
                                cells: cells.indices.filter { cells[$0]?.emoji == e })
        case 2:
            // Le cadre doré
            guard let f = framed, let e = cells[f]?.emoji else { return nil }
            let others = pool.filter { $0 != e }.shuffled(using: &rng)
            let c = shuffledChoices(e, others, rng: &rng)
            return OeilQuestion(prompt: L("Qu'y avait-il dans le cadre doré ?"), choices: c.choices, correct: c.correct, cells: [f])
        case 3:
            // La couleur d'une case
            let singles = unique.filter { e in present.filter { $0 == e }.count == 1 }
            guard let e = singles.randomElement(using: &rng), let i = cells.firstIndex(where: { $0?.emoji == e }), let cell = cells[i] else { return nil }
            let wrong = (0..<tints.count).filter { $0 != cell.tint }.shuffled(using: &rng).map { colorName($0) }
            let c = shuffledChoices(colorName(cell.tint), wrong, rng: &rng)
            return OeilQuestion(prompt: L("De quelle couleur était la case de \(e) ?"), choices: c.choices, correct: c.correct, cells: [i])
        default:
            // Un coin
            let corners: [(Int, String)] = [(0, L("en haut à gauche")), (cols - 1, L("en haut à droite")),
                                             ((rows - 1) * cols, L("en bas à gauche")), (rows * cols - 1, L("en bas à droite"))]
            guard let corner = corners.filter({ cells[$0.0] != nil }).randomElement(using: &rng), let e = cells[corner.0]?.emoji else { return nil }
            let c = shuffledChoices(e, pool.filter { $0 != e }.shuffled(using: &rng), rng: &rng)
            return OeilQuestion(prompt: L("Qu'y avait-il \(corner.1) ?"), choices: c.choices, correct: c.correct, cells: [corner.0])
        }
    }
}

@Observable
final class CoupDoeilGame {
    enum Phase: Equatable {
        case menu, memorize, hide, quiz, check
    }

    private(set) var phase: Phase = .menu
    private(set) var round: OeilRound?
    private(set) var level = 1
    private(set) var daily = false
    private(set) var questionIndex = 0
    private(set) var answers: [Int] = []
    @ObservationIgnored private(set) var timeLeft: Double = 0
    /// Le temps affiché, arrondi au dixième : l'image n'est pas redessinée à chaque image.
    private(set) var shownTime: Double = 0
    private(set) var isClosed = false
    private(set) var hasHinge = false

    var correctCount: Int {
        guard let round else { return 0 }
        return zip(answers, round.questions).filter { $0.0 == $0.1.correct }.count
    }

    var stars: Int {
        guard let round, !round.questions.isEmpty else { return 0 }
        let ratio = Double(correctCount) / Double(round.questions.count)
        return ratio >= 1 ? 3 : (ratio >= 0.6 ? 2 : (ratio > 0 ? 1 : 0))
    }

    static func todaySeed() -> UInt64 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return UInt64((c.year ?? 2026) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1))
    }

    static var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    func play(level: Int) {
        self.level = level
        daily = false
        begin(OeilRound.make(level: level, seed: UInt64(level) &* 7919 &+ UInt64.random(in: 0...999_999)))
    }

    func playDaily() {
        level = 22
        daily = true
        begin(OeilRound.make(level: 22, seed: Self.todaySeed(), questionCount: 5))
    }

    private func begin(_ r: OeilRound) {
        round = r
        answers = []
        questionIndex = 0
        timeLeft = r.seconds
        shownTime = r.seconds
        phase = .memorize
        SoundPlayer.shared.play(.go, volume: 0.5)
    }

    func backToMenu() { phase = .menu }

    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        if closed && phase == .hide { phase = .quiz; SoundPlayer.shared.play(.whoosh, volume: 0.5) }
        if closed && phase == .memorize { phase = .quiz }
    }

    /// Sans fermer le Duo : les questions s'affichent ici.
    func answerHere() {
        if phase == .hide { phase = .quiz }
    }

    func tick(dt: Double) {
        guard phase == .memorize else { return }
        timeLeft -= dt
        let rounded = (max(0, timeLeft) * 10).rounded(.up) / 10
        if rounded != shownTime { shownTime = rounded }
        if timeLeft <= 0 {
            phase = hasHinge ? .hide : .quiz
            SoundPlayer.shared.play(.stop, volume: 0.5)
            Haptics.warning()
        }
    }

    func answer(_ choice: Int) {
        guard phase == .quiz, let round else { return }
        answers.append(choice)
        let right = choice == round.questions[questionIndex].correct
        SoundPlayer.shared.play(right ? .chime : .wrong, volume: right ? 0.6 : 0.4)
        if right { Haptics.correct(subtle: true) } else { Haptics.warning() }
        if questionIndex + 1 < round.questions.count {
            questionIndex += 1
        } else {
            phase = .check
            SoundPlayer.shared.play(stars == 3 ? .win : .bloom, volume: 0.7)
        }
    }
}

// MARK: - Écran

struct CoupDoeilView: View {
    @Environment(AppState.self) private var app
    @State private var game = CoupDoeilGame()


    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E2A33), Color(hex: 0x07161B)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch game.phase {
            case .menu: menu
            case .memorize: memorize
            case .hide: hide
            case .quiz: quiz
            case .check: check
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onFrame(step: 1.0 / 30.0) { _ in game.tick(dt: 1.0 / 30.0) }
        .onChange(of: game.phase) { _, phase in
            if phase == .check {
                if game.daily {
                    app.recordOeilDaily(day: CoupDoeilGame.todayKey, correct: game.correctCount)
                } else {
                    app.recordOeil(level: game.level, stars: game.stars)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .coupDoeil)
            Spacer()
            if game.phase != .menu {
                Pill(text: game.daily ? L("Défi du jour") : L("Niveau \(game.level)"), color: Theme.oeil.opacity(0.25), textColor: Theme.oeil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                Text(verbatim: "👁️").font(.system(size: 56)).accessibilityHidden(true)
                Text(L("Coup d'œil")).font(.plie(34))
                Text(L("Mémorise l'image sur le grand écran. Ferme le Duo : les questions t'attendent dehors. Rouvre-le pour voir si tu avais raison."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Défi du jour, le même pour tout le monde, et la série de jours
                let doneToday = app.oeilDailyDay == CoupDoeilGame.todayKey
                Button {
                    game.playDaily()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 30, weight: .bold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Défi du jour")).font(.plie(20))
                            Text(doneToday ? L("Fait : \(app.oeilDailyScore) / 5 · série de \(app.oeilStreak) jour\(app.oeilStreak > 1 ? "s" : "")")
                                           : L("5 questions, la même image pour tout le monde"))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .opacity(0.8)
                        }
                        Spacer()
                        if app.oeilStreak > 0 {
                            Label("\(app.oeilStreak)", systemImage: "flame.fill").font(.plie(18))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(18)
                    .background(FoldedPaper(color: Theme.oeil, cornerRadius: 24))
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16)

                SectionTitle(text: L("Les niveaux"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                    ForEach(1...50, id: \.self) { n in
                        let stars = app.oeilStars[n] ?? 0
                        let open = n == 1 || app.oeilStars[n - 1] != nil || app.oeilStars[n] != nil
                        Button {
                            if open { game.play(level: n) }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(n)").font(.plie(20))
                                HStack(spacing: 1) {
                                    ForEach(0..<3, id: \.self) { k in
                                        Image(systemName: k < stars ? "star.fill" : "star")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                }
                                .opacity(open ? 1 : 0)
                                if !open { Image(systemName: "lock.fill").font(.system(size: 11)) }
                            }
                            .frame(width: 64, height: 64)
                            .background(LevelTile(done: stars > 0, accent: Theme.oeil))
                            .foregroundStyle(stars > 0 ? Theme.ink : .white.opacity(open ? 1 : 0.4))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(!open)
                        .accessibilityLabel(open ? L("Niveau \(n), \(stars) étoiles") : L("Niveau \(n), verrouillé"))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Mémoriser (écran intérieur)

    private var memorize: some View {
        VStack(spacing: 12) {
            header
            Text(L("Mémorise tout !")).font(.plie(26))
            ProgressView(value: game.shownTime, total: game.round?.seconds ?? 1)
                .tint(Theme.oeil)
                .frame(maxWidth: 420)
            if let r = game.round {
                OeilGrid(round: r, highlight: [], hidden: false)
                    .padding(16)
            }
            Spacer(minLength: 0)
        }
    }

    private var hide: some View {
        VStack(spacing: 16) {
            header
            Spacer()
            if let r = game.round {
                OeilGrid(round: r, highlight: [], hidden: true)
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 30)
            }
            PostureIcon(posture: .closed, color: Theme.oeil, lineWidth: 4).frame(width: 110, height: 70)
            Text(L("Ferme le Duo !")).font(.plie(30))
            Text(L("Les questions t'attendent sur l'écran extérieur."))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.muted)
            Button(L("Répondre ici")) { game.answerHere() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 280)
            Spacer()
        }
    }

    // MARK: Questions (écran extérieur, Duo fermé)

    private var quiz: some View {
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            if let r = game.round, game.questionIndex < r.questions.count {
                let q = r.questions[game.questionIndex]
                Text(L("Question \(game.questionIndex + 1) / \(r.questions.count)"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.oeil)
                Text(q.prompt)
                    .font(.plie(30))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 20)
                VStack(spacing: 12) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { item in
                        Button {
                            game.answer(item.offset)
                        } label: {
                            Text(item.element)
                                .font(.system(size: item.element.count <= 2 ? 44 : 24, weight: .heavy, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1)))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.oeil.opacity(0.5), lineWidth: 1.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Vérifier (Duo rouvert)

    private var check: some View {
        Group {
            if game.isClosed && game.hasHinge {
                VStack(spacing: 16) {
                    Spacer()
                    PostureIcon(posture: .flat, color: Theme.oeil, lineWidth: 4).frame(width: 110, height: 70)
                    Text(L("Ouvre le Duo pour vérifier !")).font(.plie(28)).multilineTextAlignment(.center)
                    Spacer()
                }
            } else if let r = game.round {
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { k in
                                Image(systemName: k < game.stars ? "star.fill" : "star")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                        Text(L("\(game.correctCount) bonnes réponses sur \(r.questions.count)")).font(.plie(24))
                        OeilGrid(round: r, highlight: Set(r.questions.flatMap(\.cells)), hidden: false)
                            .frame(maxHeight: 360)
                            .padding(.horizontal, 16)
                        VStack(spacing: 8) {
                            ForEach(Array(r.questions.enumerated()), id: \.offset) { item in
                                let given = item.offset < game.answers.count ? game.answers[item.offset] : -1
                                let ok = given == item.element.correct
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(ok ? Theme.go : Theme.stop)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.element.prompt).font(.plie(16, weight: .bold))
                                        Text(L("Réponse : \(item.element.choices[item.element.correct])"))
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                            }
                        }
                        .padding(.horizontal, 16)
                        if game.daily {
                            ShareResultButton(game: L("COUP D'ŒIL"), result: L("Défi du jour : \(game.correctCount) / 5"), accent: Theme.oeil)
                        } else {
                            Button(game.stars > 0 && game.level < 50 ? L("Niveau suivant") : L("Rejouer")) {
                                game.play(level: game.stars > 0 ? min(50, game.level + 1) : game.level)
                            }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.oeil, textColor: Theme.ink))
                            .frame(maxWidth: 380)
                        }
                        Button(L("Les niveaux")) { game.backToMenu() }
                            .buttonStyle(GhostButtonStyle())
                            .frame(maxWidth: 380)
                    }
                    .padding(.bottom, 30)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .top) {
                    if game.stars == 3 { ConfettiView().frame(height: 400).allowsHitTesting(false) }
                }
            }
        }
    }
}

/// L'image à mémoriser : une grille de cases colorées avec des objets.
struct OeilGrid: View {
    let round: OeilRound
    let highlight: Set<Int>
    let hidden: Bool

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let side = min((proxy.size.width - gap * CGFloat(round.cols - 1)) / CGFloat(round.cols),
                           (proxy.size.height - gap * CGFloat(round.rows - 1)) / CGFloat(round.rows))
            VStack(spacing: gap) {
                ForEach(0..<round.rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<round.cols, id: \.self) { c in
                            let i = r * round.cols + c
                            cell(i, side: side)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(CGFloat(round.cols) / CGFloat(round.rows), contentMode: .fit)
        .accessibilityLabel(hidden ? L("Image cachée") : L("Image à mémoriser"))
    }

    @ViewBuilder
    private func cell(_ i: Int, side: CGFloat) -> some View {
        let content = round.cells[i]
        let tint = content.map { Color(hex: OeilRound.tints[$0.tint].0) } ?? Color.white.opacity(0.06)
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                .fill(hidden ? Color.white.opacity(0.08) : tint.opacity(content == nil ? 1 : 0.85))
            if !hidden, let content {
                Text(verbatim: content.emoji).font(.system(size: side * 0.55))
            }
            if hidden {
                Image(systemName: "questionmark").font(.system(size: side * 0.3, weight: .bold)).foregroundStyle(.white.opacity(0.25))
            }
            if !hidden && round.framed == i {
                RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                    .strokeBorder(Theme.gold, lineWidth: max(3, side * 0.07))
            }
            if highlight.contains(i) {
                RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .frame(width: side, height: side)
    }
}
