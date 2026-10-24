import SwiftUI

// MARK: - Une leçon

@Observable
final class EcoleLesson {
    enum Feedback: Equatable { case none, right, wrong, reveal }

    private(set) var klass: EcoleClass = .petits
    private(set) var questions: [EcoleQuestion] = []
    private(set) var index = 0
    private(set) var stars = 0
    private(set) var feedback: Feedback = .none
    private(set) var picked: Int?
    private(set) var finished = false
    private(set) var started = false
    var typed = ""
    /// Ce que l'enfant a écrit à la craie, et la lecture en cours.
    private(set) var strokes: [ChalkStroke] = []
    private(set) var reading = false
    private(set) var notice: String?
    @ObservationIgnored private var strokeOpen = false

    @ObservationIgnored private var tries = 0
    @ObservationIgnored private var token = 0
    @ObservationIgnored private let voice = SoleilCaller()

    var question: EcoleQuestion? { index < questions.count ? questions[index] : nil }

    func start(_ c: EcoleClass) {
        klass = c
        questions = EcoleGenerator.lesson(for: c)
        index = 0
        stars = 0
        finished = false
        started = true
        prepare()
    }

    func stop() {
        token += 1
        voice.stop()
        started = false
    }

    private func prepare() {
        tries = 0
        feedback = .none
        picked = nil
        typed = ""
        strokes = []
        strokeOpen = false
        notice = nil
        speak()
    }

    func speak() {
        guard let q = question else { return }
        voice.say(q.speech, rate: 0.46, delay: 0.25)
    }

    func choose(_ i: Int) {
        guard let q = question, feedback == .none || feedback == .wrong else { return }
        picked = i
        check(i == q.correct)
    }

    func typeDigit(_ d: Int) {
        guard feedback == .none || feedback == .wrong else { return }
        if feedback == .wrong {
            // Nouvel essai : on efface l'ancienne réponse tout de suite.
            token += 1
            feedback = .none
            typed = ""
        }
        guard typed.count < 4 else { return }
        typed += "\(d)"
        SoundPlayer.shared.play(.chalk, volume: 0.5)
    }

    func erase() {
        guard !typed.isEmpty else { return }
        typed.removeLast()
    }

    // MARK: Craie

    func addChalk(_ p: CGPoint, newStroke: Bool) {
        guard feedback == .none || feedback == .wrong, !reading else { return }
        notice = nil
        if feedback == .wrong {
            // Nouvel essai : l'ardoise est essuyée.
            token += 1
            feedback = .none
            strokes = []
            typed = ""
            strokeOpen = false
        }
        if !strokeOpen || strokes.isEmpty {
            strokes.append(ChalkStroke(points: [p]))
            strokeOpen = true
        } else if let last = strokes[strokes.count - 1].points.last, hypot(p.x - last.x, p.y - last.y) > 2.5 {
            strokes[strokes.count - 1].points.append(p)
        }
    }

    func endChalkStroke() {
        strokeOpen = false
    }

    func clearChalk() {
        strokes = []
        strokeOpen = false
        notice = nil
    }

    func submitChalk() {
        guard let q = question, let answer = q.keypadAnswer, !strokes.isEmpty, !reading,
              feedback == .none || feedback == .wrong else { return }
        reading = true
        let current = token
        ChalkReader.read(strokes: strokes) { [weak self] readings in
            guard let self, self.token == current else { return }
            self.reading = false
            guard let first = readings.first else {
                self.notice = L("Je n'arrive pas à lire. Écris plus gros, un chiffre à côté de l'autre !")
                self.voice.say(L("Je n'arrive pas à lire. Écris plus gros !"), rate: 0.5)
                return
            }
            let right = readings.contains(answer)
            self.typed = "\(right ? answer : first)"
            self.check(right)
        }
    }

    func submit() {
        guard let q = question, let answer = q.keypadAnswer, !typed.isEmpty, feedback == .none || feedback == .wrong else { return }
        check(Int(typed) == answer)
    }

    private func check(_ right: Bool) {
        token += 1
        let current = token
        if right {
            if tries == 0 { stars += 1 }
            feedback = .right
            SoundPlayer.shared.play(.bell, volume: 0.7)
            Haptics.success()
            voice.say([L("Bravo !"), L("Super !"), L("Génial !"), L("Très bien !")].randomElement() ?? L("Bravo !"), rate: 0.5)
            after(1.5, current) { self.next() }
        } else if tries == 0 {
            tries = 1
            feedback = .wrong
            SoundPlayer.shared.play(.wrong, volume: 0.35)
            Haptics.warning()
            voice.say(L("Presque ! Essaie encore."), rate: 0.5)
            after(1.3, current) {
                if self.feedback == .wrong {
                    self.feedback = .none
                    self.picked = nil
                    self.typed = ""
                    self.strokes = []
                }
            }
        } else {
            feedback = .reveal
            SoundPlayer.shared.play(.wrong, volume: 0.3)
            voice.say(question?.explanation ?? "", rate: 0.46)
            after(3.2, current) { self.next() }
        }
    }

    private func after(_ seconds: Double, _ current: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.token == current else { return }
            action()
        }
    }

    private func next() {
        index += 1
        if index >= questions.count {
            finished = true
            feedback = .none
            SoundPlayer.shared.play(.applause, volume: 0.7)
            SoundPlayer.shared.play(.win, volume: 0.7)
            voice.say(L("Leçon finie ! Tu as \(stars) étoiles sur 10."), rate: 0.48)
        } else {
            prepare()
        }
    }
}

// MARK: - Écran

struct EcoleView: View {
    @Environment(AppState.self) private var app
    @State private var lesson = EcoleLesson()
    @State private var recorded = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Duo plié en L (ou téléphone en portrait) : le tableau en haut, l'ardoise en bas.
            // Duo à plat en paysage : le tableau à gauche, l'ardoise à droite.
            let stacked = size.height >= size.width
            let board = stacked ? CGSize(width: size.width, height: size.height / 2) : CGSize(width: size.width / 2, height: size.height)
            let desk = board
            ZStack(alignment: .topLeading) {
                Color(hex: 0x3B2416)
                if lesson.started && !lesson.finished, let q = lesson.question {
                    Group {
                        BlackboardView(lesson: lesson, question: q, safeTop: proxy.safeAreaInsets.top)
                            .frame(width: board.width, height: board.height)
                        DeskView(lesson: lesson, question: q, safeBottom: proxy.safeAreaInsets.bottom)
                            .frame(width: desk.width, height: desk.height)
                            .offset(x: stacked ? 0 : board.width, y: stacked ? board.height : 0)
                    }
                } else {
                    ScrollView {
                        if lesson.finished {
                            report
                        } else {
                            classPicker
                        }
                    }
                    .padding(.top, proxy.safeAreaInsets.top)
                    .frame(width: size.width, height: size.height)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x1F4D3A), Color(hex: 0x173828)], startPoint: .top, endPoint: .bottom)
                    )
                }

                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) {
                        if lesson.started && !lesson.finished {
                            lesson.stop()
                        } else {
                            lesson.stop()
                            app.route = .hub
                        }
                    }
                    HowToButton(game: .ecole)
                }
                .padding(.leading, 14)
                .padding(.top, max(10, proxy.safeAreaInsets.top))
            }
        }
        .ignoresSafeArea()
        .onChange(of: lesson.finished) { _, done in
            if done && !recorded {
                recorded = true
                app.recordEcole(classRaw: lesson.klass.rawValue, stars: lesson.stars)
            }
        }
        .onDisappear { lesson.stop() }
    }

    private var classPicker: some View {
        VStack(spacing: 16) {
            Text(verbatim: "🦉")
                .font(.system(size: 64))
                .padding(.top, 50)
                .accessibilityHidden(true)
            Text(L("L'école de la Chouette"))
                .font(.custom("ChalkboardSE-Bold", size: 34, relativeTo: .largeTitle))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(L("Choisis ta classe. La maîtresse pose 10 questions et les lit à voix haute."))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(EcoleClass.allCases) { c in
                    Button {
                        recorded = false
                        lesson.start(c)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                FoldedPaper(color: c.color, cornerRadius: 18)
                                Image(systemName: c.symbol)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(width: 62, height: 62)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title)
                                    .font(.system(.title2, design: .rounded, weight: .black))
                                Text(c.age)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(c.color)
                                Text(c.topics)
                                    .font(.system(.footnote, design: .rounded, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                                let best = app.ecoleStars[c.rawValue] ?? 0
                                if best > 0 {
                                    Label(L("Record : \(best) / 10"), systemImage: "star.fill")
                                        .font(.system(.caption, design: .rounded, weight: .bold))
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.color.opacity(0.6), lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(L("\(c.title), \(c.age) : \(c.topics)"))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var report: some View {
        VStack(spacing: 16) {
            Text(verbatim: lesson.stars >= 8 ? "🏆" : (lesson.stars >= 5 ? "🌟" : "💪"))
                .font(.system(size: 72))
                .padding(.top, 50)
                .accessibilityHidden(true)
            Text(L("Leçon finie !"))
                .font(.custom("ChalkboardSE-Bold", size: 36, relativeTo: .largeTitle))
            Text(L("\(lesson.stars) étoiles sur 10"))
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.gold)
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    Image(systemName: i < lesson.stars ? "star.fill" : "star")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .accessibilityHidden(true)
            Text(lesson.stars >= 8 ? L("Bravo, tu es un champion !") : (lesson.stars >= 5 ? L("Très bien ! Encore une leçon pour faire mieux ?") : L("Continue, tu vas y arriver !")))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            ShareResultButton(game: L("ÉCOLE"), result: L("\(lesson.stars) étoiles sur 10 en \(lesson.klass.title)"), accent: Theme.ecole)
            Button(L("Nouvelle leçon")) {
                recorded = false
                lesson.start(lesson.klass)
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.ecole, textColor: Theme.ink))
            .frame(maxWidth: 380)
            Button(L("Changer de classe")) { lesson.stop() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 380)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            if lesson.stars >= 5 { ConfettiView().frame(height: 500).allowsHitTesting(false) }
        }
    }
}

// MARK: - Le tableau (moitié haute)

struct BlackboardView: View {
    let lesson: EcoleLesson
    let question: EcoleQuestion
    let safeTop: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let chalk = Color(hex: 0xF4F1E6)
            ZStack {
                // Cadre en bois et ardoise verte
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x8A5A32), Color(hex: 0x5C3A1E)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2F5D46), Color(hex: 0x24493A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(ChalkDust())
                    .padding(12)

                VStack(spacing: h * 0.035) {
                    // Les étoiles collées au tableau
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { i in
                            Image(systemName: i < lesson.stars ? "star.fill" : (i == lesson.index ? "star.circle" : "star"))
                                .font(.system(size: min(22, h * 0.06), weight: .bold))
                                .foregroundStyle(i < lesson.stars ? Theme.gold : chalk.opacity(0.35))
                        }
                    }
                    .accessibilityLabel(L("Question \(lesson.index + 1) sur 10, \(lesson.stars) étoiles"))

                    visual(h: h, chalk: chalk)

                    Text(question.prompt)
                        .font(.custom("ChalkboardSE-Bold", size: min(44, h * 0.11), relativeTo: .title))
                        .foregroundStyle(chalk)
                        .shadow(color: .white.opacity(0.25), radius: 1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(3)
                        .padding(.horizontal, 30)

                    if lesson.feedback == .reveal {
                        Text(question.explanation)
                            .font(.custom("ChalkboardSE-Regular", size: min(26, h * 0.07), relativeTo: .body))
                            .foregroundStyle(Theme.gold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }
                .padding(.top, max(24, safeTop * 0.6))
                .padding(.bottom, 20)

                // La maîtresse chouette et son haut-parleur
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            lesson.speak()
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: "🦉").font(.system(size: min(40, h * 0.1)))
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(chalk)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.25)))
                        }
                        .accessibilityLabel(L("Réécouter la question"))
                    }
                    Spacer()
                }
                .padding(.top, max(20, safeTop))
                .padding(.trailing, 22)

                if lesson.feedback == .right || lesson.feedback == .wrong {
                    Text(lesson.feedback == .right ? L("Bravo !") : L("Presque !"))
                        .font(.custom("ChalkboardSE-Bold", size: min(80, h * 0.22), relativeTo: .largeTitle))
                        .foregroundStyle(lesson.feedback == .right ? Theme.gold : Color(hex: 0xFF8A8A))
                        .rotationEffect(.degrees(-8))
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: lesson.feedback)
        }
    }

    @ViewBuilder
    private func visual(h: CGFloat, chalk: Color) -> some View {
        switch question.visual {
        case .none:
            EmptyView()
        case .picture(let emoji):
            Text(verbatim: emoji)
                .font(.system(size: min(90, h * 0.22)))
                .accessibilityHidden(true)
        case .items(let emoji, let n):
            let cols = min(5, n)
            let rows = Int((Double(n) / 5).rounded(.up))
            VStack(spacing: 4) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<min(cols, n - r * 5), id: \.self) { _ in
                            Text(verbatim: emoji).font(.system(size: min(48, h * 0.11)))
                        }
                    }
                }
            }
            .accessibilityLabel(L("\(n) dessins"))
        case .dots(let a, let b, let subtract):
            let d = min(22, h * 0.06)
            HStack(spacing: 10) {
                dotRow(subtract ? a : a, crossedFrom: subtract ? a - b : nil, d: d, chalk: chalk)
                if !subtract {
                    Text(verbatim: "+").font(.custom("ChalkboardSE-Bold", size: d * 1.6, relativeTo: .title)).foregroundStyle(chalk)
                    dotRow(b, crossedFrom: nil, d: d, chalk: Theme.ecole)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func dotRow(_ n: Int, crossedFrom: Int?, d: CGFloat, chalk: Color) -> some View {
        HStack(spacing: d * 0.35) {
            ForEach(0..<n, id: \.self) { i in
                ZStack {
                    Circle().fill(chalk.opacity(0.9)).frame(width: d, height: d)
                    if let c = crossedFrom, i >= c {
                        Image(systemName: "xmark")
                            .font(.system(size: d * 0.9, weight: .heavy))
                            .foregroundStyle(Color(hex: 0xFF8A8A))
                    }
                }
            }
        }
    }
}

/// Traces de craie sur l'ardoise.
struct ChalkDust: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<40 {
                let x = CGFloat(Draw.hash(i, 41)) * size.width
                let y = CGFloat(Draw.hash(i, 42)) * size.height
                let w = CGFloat(30 + 90 * Draw.hash(i, 43))
                var smear = Path()
                smear.move(to: CGPoint(x: x, y: y))
                smear.addQuadCurve(to: CGPoint(x: x + w, y: y + CGFloat(Draw.hash(i, 44) * 12 - 6)), control: CGPoint(x: x + w / 2, y: y - 8))
                context.stroke(smear, with: .color(.white.opacity(0.035)), lineWidth: CGFloat(4 + 10 * Draw.hash(i, 45)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - L'ardoise (moitié basse)

struct DeskView: View {
    let lesson: EcoleLesson
    let question: EcoleQuestion
    let safeBottom: CGFloat
    /// Écrire à la craie (par défaut) ou taper sur un clavier.
    @AppStorage("ecole.keypad") private var useKeypad = false

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0xC98F55), Color(hex: 0xA8703E)], startPoint: .top, endPoint: .bottom)
                // Veines du bois
                Canvas { context, size in
                    for i in 0..<18 {
                        let y = CGFloat(Draw.hash(i, 51)) * size.height
                        var vein = Path()
                        vein.move(to: CGPoint(x: 0, y: y))
                        vein.addCurve(to: CGPoint(x: size.width, y: y + 10), control1: CGPoint(x: size.width * 0.3, y: y - 8), control2: CGPoint(x: size.width * 0.7, y: y + 14))
                        context.stroke(vein, with: .color(.black.opacity(0.07)), lineWidth: 1.5)
                    }
                }
                if question.keypadAnswer != nil {
                    if useKeypad { keypad(h: h) } else { writing(h: h) }
                } else {
                    choices(h: h)
                }
            }
            .padding(.bottom, 0)
        }
    }

    private func choices(h: CGFloat) -> some View {
        let n = question.choices.count
        let height = min(140, max(64, (h - 60 - safeBottom) / (n > 3 ? 2.4 : 1.3)))
        let columns = n == 4 ? 2 : n
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(1, columns)), spacing: 14) {
            ForEach(Array(question.choices.enumerated()), id: \.offset) { item in
                Button {
                    lesson.choose(item.offset)
                } label: {
                    choiceLabel(item.element, height: height)
                }
                .buttonStyle(PressableStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(borderColor(item.offset), lineWidth: 5)
                )
                .accessibilityLabel(accessibilityText(item.element))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, safeBottom)
        .frame(maxWidth: 760)
    }

    private func borderColor(_ i: Int) -> Color {
        guard lesson.picked == i else {
            return lesson.feedback == .reveal && i == question.correct ? Theme.go : .clear
        }
        switch lesson.feedback {
        case .right: return Theme.go
        case .wrong, .reveal: return Theme.stop
        case .none: return .white
        }
    }

    private func accessibilityText(_ c: EcoleChoice) -> String {
        if !c.label.isEmpty { return c.label }
        switch c.symbol {
        case "circle.fill": return L("rond")
        case "square.fill": return L("carré")
        case "triangle.fill": return L("triangle")
        case "star.fill": return L("étoile")
        case "heart.fill": return L("cœur")
        default: return L("réponse")
        }
    }

    @ViewBuilder
    private func choiceLabel(_ c: EcoleChoice, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            shape.fill(Color(hex: 0xFFF8EA))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 5)
            if let color = c.color {
                VStack(spacing: 6) {
                    Circle().fill(color).frame(width: height * 0.45, height: height * 0.45)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 2))
                    Text(c.label)
                        .font(.system(size: min(26, height * 0.22), weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
            } else if let symbol = c.symbol {
                Image(systemName: symbol)
                    .font(.system(size: height * 0.5, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF6B9A), Color(hex: 0x7B5CFF)], startPoint: .top, endPoint: .bottom))
            } else {
                Text(c.label)
                    .font(.system(size: min(54, height * 0.42), weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: height)
    }

    private func writing(h: CGFloat) -> some View {
        VStack(spacing: 10) {
            ChalkSlate(lesson: lesson)
                .frame(maxWidth: 620)
            if let notice = lesson.notice {
                Text(notice)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
            } else if !lesson.typed.isEmpty && lesson.feedback != .none {
                Text(L("Tu as écrit : \(lesson.typed)"))
                    .font(.custom("ChalkboardSE-Bold", size: 20, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
            }
            HStack(spacing: 12) {
                Button {
                    lesson.clearChalk()
                } label: {
                    Label(L("Effacer"), systemImage: "eraser.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Color(hex: 0xFFB3A7), textColor: Theme.ink, height: 54))
                Button {
                    lesson.submitChalk()
                } label: {
                    Label(L("Valider"), systemImage: "checkmark")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.go, textColor: Theme.ink, height: 54))
                .disabled(lesson.strokes.isEmpty || lesson.reading)
                Button {
                    useKeypad = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xFFF8EA)))
                }
                .accessibilityLabel(L("Utiliser le clavier"))
            }
            .frame(maxWidth: 620)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, max(12, safeBottom))
    }

    private func keypad(h: CGFloat) -> some View {
        let key = min(74, max(44, (h - 120 - safeBottom) / 4.6))
        return VStack(spacing: 10) {
            // L'ardoise où s'écrit la réponse
            Text(lesson.typed.isEmpty ? "?" : lesson.typed)
                .font(.custom("ChalkboardSE-Bold", size: key * 0.75, relativeTo: .largeTitle))
                .foregroundStyle(lesson.feedback == .wrong ? Color(hex: 0xFF8A8A) : (lesson.feedback == .right ? Theme.gold : Color(hex: 0xF4F1E6)))
                .frame(width: key * 3.6, height: key * 1.05)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x2B2F33)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0x8A5A32), lineWidth: 5))
                .accessibilityLabel(lesson.typed.isEmpty ? L("Réponse vide") : L("Réponse : \(lesson.typed)"))
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow {
                        ForEach(1...3, id: \.self) { c in
                            digit(r * 3 + c, size: key)
                        }
                    }
                }
                GridRow {
                    keyButton(symbol: "delete.left.fill", color: Color(hex: 0xFFB3A7), size: key, label: L("Effacer")) { lesson.erase() }
                    digit(0, size: key)
                    keyButton(symbol: "checkmark", color: Theme.go, size: key, label: L("Valider")) { lesson.submit() }
                }
            }
            Button {
                useKeypad = false
            } label: {
                Label(L("Écrire à la craie"), systemImage: "hand.draw.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.bottom, safeBottom)
    }

    private func digit(_ d: Int, size: CGFloat) -> some View {
        Button {
            lesson.typeDigit(d)
        } label: {
            Text("\(d)")
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: size * 1.3, height: size)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFFF8EA)).shadow(color: .black.opacity(0.25), radius: 0, y: 4))
        }
        .buttonStyle(PressableStyle())
    }

    private func keyButton(symbol: String, color: Color, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: size * 1.3, height: size)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color).shadow(color: .black.opacity(0.25), radius: 0, y: 4))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
