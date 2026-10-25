import SwiftUI

extension Theme {
    static let boite = Color(hex: 0xE0A86A)
}

// MARK: - LA BOÎTE
//
// Le Duo fermé, c'est une boîte mystère : l'indice est écrit sur le couvercle (écran extérieur).
// On ouvre le Duo : dedans, la serrure (écran intérieur). Un seul côté à la fois !
// Il faut retenir l'indice, ou refermer pour le relire… et chaque coup d'œil coûte une étoile.

enum BoiteKind {
    /// Le code est écrit sur le couvercle.
    case code
    /// Des couleurs à toucher dans l'ordre.
    case colors
    /// Le couvercle donne la légende (☀️ = 4), la serrure montre les symboles.
    case symbols
    /// Une grille de cases allumées à recopier.
    case grid
    /// Des objets à compter dehors, dans l'ordre demandé dedans.
    case count
}

enum BoiteTwist {
    case none
    /// Le code (ou les couleurs) à entrer à l'envers.
    case reversed
    /// Vu de l'intérieur, gauche et droite sont inversées.
    case mirror
    /// Les couleurs sont éparpillées, avec leur numéro d'ordre.
    case scattered
}

struct BoiteLevel {
    let kind: BoiteKind
    /// Longueur du code, nombre de couleurs, de symboles à décoder, de cases allumées, ou sortes d'objets.
    let size: Int
    /// Taille de la légende (symboles), côté de la grille, ou nombre maximum d'objets d'une sorte.
    let extra: Int
    let twist: BoiteTwist
    /// Nombre de coups d'œil (et d'erreurs) pour 3 étoiles.
    let par: Int

    static let all: [BoiteLevel] = [
        BoiteLevel(kind: .code, size: 3, extra: 0, twist: .none, par: 1),
        BoiteLevel(kind: .colors, size: 4, extra: 0, twist: .none, par: 1),
        BoiteLevel(kind: .code, size: 4, extra: 0, twist: .none, par: 1),
        BoiteLevel(kind: .symbols, size: 3, extra: 3, twist: .none, par: 2),
        BoiteLevel(kind: .grid, size: 3, extra: 3, twist: .none, par: 1),
        BoiteLevel(kind: .count, size: 2, extra: 4, twist: .none, par: 1),
        BoiteLevel(kind: .colors, size: 5, extra: 0, twist: .scattered, par: 1),
        BoiteLevel(kind: .code, size: 5, extra: 0, twist: .none, par: 1),
        BoiteLevel(kind: .symbols, size: 3, extra: 4, twist: .none, par: 2),
        BoiteLevel(kind: .grid, size: 4, extra: 3, twist: .mirror, par: 1),
        BoiteLevel(kind: .count, size: 3, extra: 5, twist: .none, par: 2),
        BoiteLevel(kind: .code, size: 4, extra: 0, twist: .reversed, par: 1),
        // Avec le Pass
        BoiteLevel(kind: .colors, size: 6, extra: 0, twist: .scattered, par: 2),
        BoiteLevel(kind: .symbols, size: 4, extra: 5, twist: .none, par: 2),
        BoiteLevel(kind: .grid, size: 5, extra: 4, twist: .none, par: 1),
        BoiteLevel(kind: .count, size: 3, extra: 7, twist: .none, par: 2),
        BoiteLevel(kind: .code, size: 6, extra: 0, twist: .none, par: 1),
        BoiteLevel(kind: .colors, size: 6, extra: 0, twist: .reversed, par: 2),
        BoiteLevel(kind: .grid, size: 6, extra: 4, twist: .mirror, par: 2),
        BoiteLevel(kind: .symbols, size: 5, extra: 6, twist: .none, par: 3),
        BoiteLevel(kind: .count, size: 4, extra: 6, twist: .none, par: 2),
        BoiteLevel(kind: .code, size: 7, extra: 0, twist: .none, par: 2),
        BoiteLevel(kind: .colors, size: 7, extra: 0, twist: .scattered, par: 2),
        BoiteLevel(kind: .grid, size: 7, extra: 4, twist: .none, par: 2),
        BoiteLevel(kind: .symbols, size: 5, extra: 7, twist: .none, par: 3),
        BoiteLevel(kind: .count, size: 4, extra: 9, twist: .none, par: 3),
        BoiteLevel(kind: .code, size: 6, extra: 0, twist: .reversed, par: 2),
        BoiteLevel(kind: .grid, size: 8, extra: 5, twist: .mirror, par: 2),
        BoiteLevel(kind: .colors, size: 8, extra: 0, twist: .scattered, par: 3),
        BoiteLevel(kind: .symbols, size: 6, extra: 8, twist: .none, par: 3)
    ]

    static var count: Int { all.count }

    static func of(_ number: Int) -> BoiteLevel {
        all[max(0, min(all.count - 1, number - 1))]
    }

    /// Le trésor caché dans chaque boîte : on les collectionne.
    static let treasures = ["💎", "🧸", "🪀", "🎁", "🪁", "🦆", "🐚", "🔮", "🎲", "🧩",
                            "🪅", "🎺", "🗝️", "🏆", "🦄", "🐙", "🪐", "🌈", "🍩", "🦋",
                            "🎨", "🚀", "👑", "🐉", "🦖", "🍀", "🧭", "📯", "🎩", "⭐️"]
}

/// Les six couleurs de la serrure, chacune avec sa forme (pour qu'on les distingue sans voir les couleurs).
enum BoiteToken {
    static let colors: [UInt32] = [0xFF4D5E, 0xFFC53D, 0x3D8BFF, 0x2FD08C, 0xB06BFF, 0xFF8A2F]
    static let shapes = ["circle.fill", "triangle.fill", "square.fill", "diamond.fill", "star.fill", "heart.fill"]

    static func color(_ i: Int) -> Color { Color(hex: colors[i % colors.count]) }
    static func shape(_ i: Int) -> String { shapes[i % shapes.count] }
    static func name(_ i: Int) -> String {
        [L("rouge rond"), L("jaune triangle"), L("bleu carré"), L("vert losange"), L("violet étoile"), L("orange cœur")][i % 6]
    }

    static let symbols = ["☀️", "🌙", "⭐️", "🍀", "🔥", "💧", "🍄", "🐟", "🎈", "🔔"]
    static let things = ["🍎", "🐞", "🐟", "🍄", "🎈", "🔔", "🍀", "⭐️"]
}

struct BoitePuzzle {
    let level: BoiteLevel
    var digits: [Int] = []
    var colors: [Int] = []
    var spots: [CGPoint] = []
    var legend: [(symbol: Int, digit: Int)] = []
    var sequence: [Int] = []
    var items: [(kind: Int, spot: CGPoint)] = []
    var pattern: Set<Int> = []

    var answerDigits: [Int] = []
    var answerColors: [Int] = []
    var answerGrid: Set<Int> = []

    var side: Int { level.extra }
    var answerLength: Int {
        switch level.kind {
        case .colors: return answerColors.count
        case .grid: return 0
        default: return answerDigits.count
        }
    }

    /// Des positions éparpillées (0…1), une par case d'une grille, avec un peu de désordre.
    static func scatter(_ count: Int, cols: Int, rows: Int) -> [CGPoint] {
        let cells = Array(0..<(cols * rows)).shuffled().prefix(count)
        return cells.map { c in
            let x = (Double(c % cols) + 0.5 + Double.random(in: -0.22...0.22)) / Double(cols)
            let y = (Double(c / cols) + 0.5 + Double.random(in: -0.22...0.22)) / Double(rows)
            return CGPoint(x: x, y: y)
        }
    }

    static func make(_ level: BoiteLevel) -> BoitePuzzle {
        var p = BoitePuzzle(level: level)
        switch level.kind {
        case .code:
            repeat {
                p.digits = (0..<level.size).map { _ in Int.random(in: 0...9) }
            } while Set(p.digits).count < min(3, level.size)
            p.answerDigits = level.twist == .reversed ? p.digits.reversed() : p.digits
        case .colors:
            var list: [Int] = []
            if level.size <= 6 {
                list = Array(Array(0..<6).shuffled().prefix(level.size))
            } else {
                while list.count < level.size {
                    let c = Int.random(in: 0..<6)
                    if list.last != c { list.append(c) }
                }
            }
            p.colors = list
            if level.twist == .scattered { p.spots = scatter(level.size, cols: 4, rows: 3) }
            p.answerColors = level.twist == .reversed ? list.reversed() : list
        case .symbols:
            let symbols = Array(Array(0..<BoiteToken.symbols.count).shuffled().prefix(level.extra))
            let values = Array(Array(1...9).shuffled().prefix(level.extra))
            p.legend = zip(symbols, values).map { (symbol: $0.0, digit: $0.1) }
            repeat {
                p.sequence = (0..<level.size).map { _ in Int.random(in: 0..<level.extra) }
            } while Set(p.sequence).count < min(2, level.extra)
            p.answerDigits = p.sequence.map { p.legend[$0].digit }
        case .grid:
            let total = level.extra * level.extra
            p.pattern = Set(Array(0..<total).shuffled().prefix(level.size))
            if level.twist == .mirror {
                let s = level.extra
                p.answerGrid = Set(p.pattern.map { cell in (cell / s) * s + (s - 1 - cell % s) })
            } else {
                p.answerGrid = p.pattern
            }
        case .count:
            let kinds = Array(Array(0..<BoiteToken.things.count).shuffled().prefix(level.size))
            var counts = kinds.map { _ in Int.random(in: 1...level.extra) }
            // Pas deux fois le même nombre : on doit vraiment compter chaque sorte.
            if Set(counts).count < counts.count && level.extra >= level.size {
                counts = Array(Array(1...level.extra).shuffled().prefix(level.size))
            }
            let total = counts.reduce(0, +)
            let spots = scatter(total, cols: 7, rows: 7)
            var k = 0
            for (i, kind) in kinds.enumerated() {
                for _ in 0..<counts[i] {
                    p.items.append((kind: kind, spot: spots[k]))
                    k += 1
                }
            }
            // Dedans, l'ordre des sortes est mélangé.
            let order = Array(Array(0..<kinds.count).shuffled())
            p.sequence = order.map { kinds[$0] }
            p.answerDigits = order.map { counts[$0] }
        }
        return p
    }
}

// MARK: - La partie

@Observable
final class BoiteGame {
    enum Phase { case menu, playing, solved }

    private(set) var phase: Phase = .menu
    private(set) var number = 1
    private(set) var puzzle = BoitePuzzle.make(BoiteLevel.all[0])
    private(set) var isClosed = false
    private(set) var hasHinge = false
    private(set) var seenOutside = false
    private(set) var looks = 0
    private(set) var wrong = 0
    private(set) var entryDigits: [Int] = []
    private(set) var entryColors: [Int] = []
    private(set) var entryGrid: Set<Int> = []
    private(set) var shakes = 0
    private(set) var stars = 0

    var level: BoiteLevel { puzzle.level }

    func start(_ n: Int) {
        number = n
        puzzle = BoitePuzzle.make(BoiteLevel.of(n))
        looks = 0
        wrong = 0
        entryDigits = []
        entryColors = []
        entryGrid = []
        stars = 0
        seenOutside = false
        if !hasHinge { isClosed = true }
        phase = .playing
        if isClosed {
            looks = 1
            seenOutside = true
        }
        SoundPlayer.shared.play(.thud, volume: 0.7)
    }

    func backToMenu() {
        phase = .menu
    }

    #if DEBUG
    /// Démo : la première boîte, avec un code joli à filmer.
    func demoStart() {
        start(1)
        var p = BoitePuzzle(level: BoiteLevel.all[0])
        p.digits = [4, 7, 2]
        p.answerDigits = [4, 7, 2]
        puzzle = p
    }
    #endif

    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        guard phase == .playing else { return }
        if closed {
            looks += 1
            seenOutside = true
            SoundPlayer.shared.play(.thud, volume: 0.6)
        } else if seenOutside {
            SoundPlayer.shared.play(.clunk, volume: 0.6)
        }
        Haptics.tap()
    }

    /// Sans charnière : on retourne la boîte avec un bouton.
    func flip() {
        setClosed(!isClosed, fromHinge: false)
    }

    // MARK: Saisie

    func pressDigit(_ d: Int) {
        guard phase == .playing, entryDigits.count < puzzle.answerDigits.count else { return }
        entryDigits.append(d)
        SoundPlayer.shared.play(.notch, volume: 0.8)
        Haptics.tap()
        if entryDigits.count == puzzle.answerDigits.count { check(entryDigits == puzzle.answerDigits) }
    }

    func deleteDigit() {
        guard !entryDigits.isEmpty else { return }
        entryDigits.removeLast()
    }

    func pressColor(_ c: Int) {
        guard phase == .playing, entryColors.count < puzzle.answerColors.count else { return }
        entryColors.append(c)
        SoundPlayer.shared.play(.notch, volume: 0.8)
        Haptics.tap()
        if entryColors.count == puzzle.answerColors.count { check(entryColors == puzzle.answerColors) }
    }

    func deleteColor() {
        guard !entryColors.isEmpty else { return }
        entryColors.removeLast()
    }

    func toggle(_ cell: Int) {
        guard phase == .playing else { return }
        if entryGrid.contains(cell) { entryGrid.remove(cell) } else { entryGrid.insert(cell) }
        SoundPlayer.shared.play(.notch, volume: 0.7)
        Haptics.tap()
    }

    func submitGrid() {
        guard phase == .playing, !entryGrid.isEmpty else { return }
        check(entryGrid == puzzle.answerGrid)
    }

    private func check(_ ok: Bool) {
        if ok {
            let cost = looks + wrong
            stars = cost <= level.par ? 3 : (cost <= level.par + 2 ? 2 : 1)
            phase = .solved
            SoundPlayer.shared.play(.vault)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { SoundPlayer.shared.play(.win, volume: 0.8) }
            Haptics.success()
        } else {
            wrong += 1
            shakes += 1
            SoundPlayer.shared.play(.wrong)
            Haptics.error()
            let delay = 0.45
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.phase == .playing else { return }
                self.entryDigits = []
                self.entryColors = []
            }
        }
    }
}

// MARK: - Écran

struct BoiteView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var game = BoiteGame()

    var body: some View {
        ZStack {
            switch game.phase {
            case .menu:
                BoiteMenu(game: game)
            case .playing:
                if game.isClosed {
                    BoiteLidView(game: game)
                } else if !game.seenOutside {
                    closeFirst
                } else {
                    BoiteInsideView(game: game)
                }
            case .solved:
                solved
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .solved { app.recordBoite(game.number, stars: game.stars) }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("boite", [(0.0, { game.demoStart() }), (4.4, { game.pressDigit(4) }),
                                    (4.9, { game.pressDigit(7) }), (5.4, { game.pressDigit(2) })])
            #endif
        }
    }

    private var closeFirst: some View {
        VStack(spacing: 20) {
            HStack {
                IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                Spacer()
                HowToButton(game: .boite)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(Theme.boite)
                .symbolEffect(.bounce, options: .repeating)
                .accessibilityHidden(true)
            Text(L("Ferme ton Duo"))
                .font(.plie(32))
            Text(L("La boîte est fermée, et l'indice est écrit sur son couvercle : l'écran extérieur. Lis-le, puis rouvre pour trouver la serrure."))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoiteWood(dark: true))
    }

    private var solved: some View {
        let treasure = BoiteLevel.treasures[(game.number - 1) % BoiteLevel.treasures.count]
        return ZStack {
            BoiteWood(dark: true)
            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            ScrollView {
                VStack(spacing: 16) {
                    Text(verbatim: treasure)
                        .font(.system(size: 92))
                        .shadow(color: Theme.gold.opacity(0.8), radius: 24)
                        .accessibilityHidden(true)
                    Text(L("Boîte ouverte !"))
                        .font(.plie(34))
                    StarsView(count: game.stars, size: 30)
                    Text(game.looks + game.wrong <= game.level.par
                         ? L("Parfait : tu as tout retenu du premier coup.")
                         : L("Coups d'œil : \(game.looks) · erreurs : \(game.wrong). Pour 3 étoiles : \(game.level.par) coup\(game.level.par > 1 ? "s" : "") d'œil, sans erreur."))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Text(L("Nouveau trésor dans ta collection !"))
                        .font(.plie(16, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    VStack(spacing: 10) {
                        if game.number < BoiteLevel.count {
                            Button {
                                let next = game.number + 1
                                if app.boiteNeedsPass(next, hasPass: store.ownsPass) {
                                    app.showPass = true
                                } else {
                                    game.start(next)
                                }
                            } label: {
                                Label(L("Boîte suivante"), systemImage: "arrow.right")
                            }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.boite, textColor: Theme.ink, height: 58))
                        }
                        Button(L("Rejouer (nouvel indice)")) { game.start(game.number) }
                            .buttonStyle(GhostButtonStyle())
                        Button(L("Toutes les boîtes")) { game.backToMenu() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    .frame(maxWidth: 380)
                }
                .padding(28)
                .winCard(accent: Theme.boite)
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Menu

struct BoiteMenu: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    let game: BoiteGame

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: L("LA BOÎTE"),
                       subtitle: L("\(app.boiteStars.count) / \(BoiteLevel.count) boîtes ouvertes"),
                       onBack: { app.route = .hub }) {
                HowToButton(game: .boite)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 18) {
                    Text(L("Fermée, la boîte montre un indice. Ouverte, sa serrure. Un seul côté à la fois : retiens bien ! Chaque coup d'œil en plus coûte une étoile."))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    collection

                    SectionTitle(text: L("Les boîtes"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(1...BoiteLevel.count, id: \.self) { number in
                            levelButton(number)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .background(BoiteWood(dark: true).opacity(0.6))
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Ta collection de trésors"))
                    .font(.plie(17))
                Spacer()
                Text(verbatim: "\(app.boiteStars.count) / \(BoiteLevel.count)")
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(0..<BoiteLevel.count, id: \.self) { i in
                    let found = app.boiteStars[i + 1] != nil
                    Text(verbatim: found ? BoiteLevel.treasures[i] : "?")
                        .font(found ? Font.system(size: 24) : Font.plie(16, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(found ? 0.15 : 0.3)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(app.boiteStars.count) trésors trouvés sur \(BoiteLevel.count)"))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private func levelButton(_ number: Int) -> some View {
        let done = app.boiteStars[number] != nil
        let needsPass = app.boiteNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.boiteIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                game.start(number)
            }
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    Text(verbatim: done ? BoiteLevel.treasures[(number - 1) % BoiteLevel.treasures.count] : "\(number)")
                        .font(done ? Font.system(size: 26) : Font.plie(24))
                        .foregroundStyle(.white)
                    StarsView(count: app.boiteStars[number] ?? 0, size: 11)
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                    Text(verbatim: "\(number)")
                        .font(.plie(13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(LevelTile(done: done, accent: Theme.boite, cornerRadius: 18))
        }
        .buttonStyle(PressableStyle())
        .disabled(!unlocked && !needsPass)
        .accessibilityLabel(unlocked ? L("Boîte \(number)") : (needsPass ? L("Boîte \(number), avec le Pass") : L("Boîte \(number), verrouillée")))
    }
}

// MARK: - Le couvercle (Duo fermé, écran extérieur)

struct BoiteLidView: View {
    let game: BoiteGame

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                    Spacer()
                    Label("\(game.looks)", systemImage: "eye.fill")
                        .font(.plie(16))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .accessibilityLabel(L("Coups d'œil : \(game.looks)"))
                }
                Text(L("Boîte \(game.number)"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.boite))

                clue
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: 0xFFF4DE))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    )
                    .rotationEffect(.degrees(-1.2))

                Text(game.hasHinge ? L("Retiens l'indice, puis ouvre ton Duo : la serrure est dedans.")
                                   : L("Retiens l'indice, puis ouvre la boîte : la serrure est dedans."))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !game.hasHinge {
                    Button { game.flip() } label: {
                        Label(L("Ouvrir la boîte"), systemImage: "shippingbox.and.arrow.backward.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.boite, textColor: Theme.ink, height: 54))
                    .frame(maxWidth: 360)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, max(10, proxy.safeAreaInsets.top))
            .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
        }
        .background(BoiteWood(dark: false))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var clue: some View {
        let p = game.puzzle
        switch p.level.kind {
        case .code:
            VStack(spacing: 8) {
                Text(L("Le code :"))
                    .font(.plie(18, weight: .bold))
                Text(verbatim: p.digits.map(String.init).joined(separator: " "))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Le code : \(p.digits.map(String.init).joined(separator: ", "))"))
        case .colors:
            if p.level.twist == .scattered {
                GeometryReader { g in
                    ForEach(Array(p.colors.enumerated()), id: \.offset) { item in
                        let spot = p.spots[item.offset]
                        ZStack {
                            Image(systemName: BoiteToken.shape(item.element))
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(BoiteToken.color(item.element))
                            Text(verbatim: "\(item.offset + 1)")
                                .font(.plie(17))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                        }
                        .position(x: spot.x * g.size.width, y: spot.y * g.size.height)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Dans l'ordre : \(p.colors.map(BoiteToken.name).joined(separator: ", "))"))
            } else {
                VStack(spacing: 10) {
                    Text(L("L'ordre des couleurs :"))
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                        ForEach(Array(p.colors.enumerated()), id: \.offset) { item in
                            Image(systemName: BoiteToken.shape(item.element))
                                .font(.system(size: 46, weight: .bold))
                                .foregroundStyle(BoiteToken.color(item.element))
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Dans l'ordre : \(p.colors.map(BoiteToken.name).joined(separator: ", "))"))
            }
        case .symbols:
            VStack(spacing: 10) {
                Text(L("Le décodeur :"))
                    .font(.plie(18, weight: .bold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(p.legend.enumerated()), id: \.offset) { item in
                        HStack(spacing: 6) {
                            Text(verbatim: BoiteToken.symbols[item.element.symbol]).font(.system(size: 34))
                            Text(verbatim: "= \(item.element.digit)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.boite.opacity(0.25)))
                    }
                }
            }
            .foregroundStyle(Theme.ink)
        case .grid:
            VStack(spacing: 10) {
                Text(L("Le motif :"))
                    .font(.plie(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                BoiteGridView(side: p.side, lit: p.pattern, color: Theme.boite, interactive: false) { _ in }
                    .aspectRatio(1, contentMode: .fit)
            }
        case .count:
            VStack(spacing: 6) {
                Text(L("Compte bien :"))
                    .font(.plie(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                GeometryReader { g in
                    ForEach(Array(p.items.enumerated()), id: \.offset) { item in
                        Text(verbatim: BoiteToken.things[item.element.kind])
                            .font(.system(size: min(38, g.size.width / 8)))
                            .rotationEffect(.degrees(Double((item.offset * 37) % 50) - 25))
                            .position(x: item.element.spot.x * g.size.width, y: item.element.spot.y * g.size.height)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Des objets à compter"))
            }
        }
    }
}

// MARK: - L'intérieur (Duo ouvert) : la serrure

struct BoiteInsideView: View {
    let game: BoiteGame

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack(alignment: .top) {
                BoiteWood(dark: true)
                Group {
                    if landscape {
                        HStack(spacing: 40) {
                            question.frame(maxWidth: .infinity, maxHeight: .infinity)
                            input.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 40) {
                            question.frame(maxWidth: .infinity, maxHeight: .infinity)
                            input.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, max(64, proxy.safeAreaInsets.top + 56))
                .padding(.bottom, max(16, proxy.safeAreaInsets.bottom))

                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                    HowToButton(game: .boite)
                    Text(L("Boîte \(game.number)"))
                        .font(.plie(18))
                    Spacer()
                    Label("\(game.looks)", systemImage: "eye.fill")
                        .font(.plie(16))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .accessibilityLabel(L("Coups d'œil : \(game.looks)"))
                    if !game.hasHinge {
                        Button { game.flip() } label: {
                            Label(L("Relire le couvercle"), systemImage: "arrow.uturn.backward")
                                .font(.plie(15, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(Capsule().fill(Theme.boite))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, max(10, proxy.safeAreaInsets.top))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: La question de la serrure

    @ViewBuilder
    private var question: some View {
        let p = game.puzzle
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.boite)
                .accessibilityHidden(true)
            switch p.level.kind {
            case .code:
                prompt(p.level.twist == .reversed ? L("Entre le code du couvercle… à l'envers !") : L("Entre le code écrit sur le couvercle."))
                digitSlots
            case .colors:
                prompt(p.level.twist == .reversed ? L("Touche les couleurs du couvercle… dans l'ordre inverse !")
                       : (p.level.twist == .scattered ? L("Touche les couleurs dans l'ordre de leurs numéros.") : L("Touche les couleurs dans l'ordre du couvercle.")))
                colorSlots
            case .symbols:
                prompt(L("Décode ces symboles avec le décodeur du couvercle."))
                HStack(spacing: 10) {
                    ForEach(Array(p.sequence.enumerated()), id: \.offset) { item in
                        VStack(spacing: 6) {
                            Text(verbatim: BoiteToken.symbols[p.legend[item.element].symbol])
                                .font(.system(size: 40))
                            slot(item.offset < game.entryDigits.count ? "\(game.entryDigits[item.offset])" : nil)
                        }
                    }
                }
                .modifier(BoiteShake(animatableData: CGFloat(game.shakes)))
                .animation(.default, value: game.shakes)
            case .count:
                prompt(L("Combien y en avait-il sur le couvercle ?"))
                HStack(spacing: 12) {
                    ForEach(Array(p.sequence.enumerated()), id: \.offset) { item in
                        VStack(spacing: 6) {
                            Text(verbatim: BoiteToken.things[item.element])
                                .font(.system(size: 40))
                            slot(item.offset < game.entryDigits.count ? "\(game.entryDigits[item.offset])" : nil)
                        }
                    }
                }
                .modifier(BoiteShake(animatableData: CGFloat(game.shakes)))
                .animation(.default, value: game.shakes)
            case .grid:
                prompt(p.level.twist == .mirror
                       ? L("Recopie le motif… mais vu de l'intérieur, la boîte est retournée : la gauche et la droite sont inversées !")
                       : L("Allume les mêmes cases que sur le couvercle."))
                Button { game.submitGrid() } label: {
                    Label(L("Ouvrir"), systemImage: "lock.open.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.boite, textColor: Theme.ink, height: 56))
                .frame(maxWidth: 300)
                .disabled(game.entryGrid.isEmpty)
                if game.wrong > 0 {
                    Text(L("Ce n'est pas ça… referme pour relire le motif ?"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.coral)
                }
            }
        }
        .frame(maxWidth: 480)
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slot(_ text: String?) -> some View {
        Text(verbatim: text ?? " ")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .frame(width: 48, height: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.boite.opacity(text == nil ? 0.4 : 1), lineWidth: 2))
    }

    private var digitSlots: some View {
        HStack(spacing: 8) {
            ForEach(0..<game.puzzle.answerDigits.count, id: \.self) { i in
                slot(i < game.entryDigits.count ? "\(game.entryDigits[i])" : nil)
            }
        }
        .modifier(BoiteShake(animatableData: CGFloat(game.shakes)))
        .animation(.default, value: game.shakes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(game.entryDigits.count) chiffres sur \(game.puzzle.answerDigits.count)"))
    }

    private var colorSlots: some View {
        HStack(spacing: 6) {
            ForEach(0..<game.puzzle.answerColors.count, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.4))
                    if i < game.entryColors.count {
                        Image(systemName: BoiteToken.shape(game.entryColors[i]))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BoiteToken.color(game.entryColors[i]))
                    }
                }
                .frame(width: 40, height: 46)
            }
        }
        .modifier(BoiteShake(animatableData: CGFloat(game.shakes)))
        .animation(.default, value: game.shakes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(game.entryColors.count) couleurs sur \(game.puzzle.answerColors.count)"))
    }

    // MARK: La saisie

    @ViewBuilder
    private var input: some View {
        let p = game.puzzle
        switch p.level.kind {
        case .code, .symbols, .count:
            keypad
        case .colors:
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(0..<6, id: \.self) { c in
                        Button { game.pressColor(c) } label: {
                            Image(systemName: BoiteToken.shape(c))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(BoiteToken.color(c))
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.4)))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(BoiteToken.color(c).opacity(0.6), lineWidth: 2))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(BoiteToken.name(c))
                    }
                }
                Button { game.deleteColor() } label: {
                    Label(L("Effacer"), systemImage: "delete.left.fill")
                }
                .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: 420)
        case .grid:
            BoiteGridView(side: p.side, lit: game.entryGrid, color: Theme.boite, interactive: true) { game.toggle($0) }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 420)
        }
    }

    private var keypad: some View {
        let keys: [Int?] = [1, 2, 3, 4, 5, 6, 7, 8, 9, nil, 0, -1]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<keys.count, id: \.self) { i in
                if let key = keys[i] {
                    Button {
                        if key < 0 { game.deleteDigit() } else { game.pressDigit(key) }
                    } label: {
                        Group {
                            if key < 0 {
                                Image(systemName: "delete.left.fill").font(.system(size: 24, weight: .bold))
                            } else {
                                Text(verbatim: "\(key)").font(.system(size: 32, weight: .black, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x3A2A1E)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.boite.opacity(0.5), lineWidth: 1.5))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(key < 0 ? L("Effacer") : "\(key)")
                } else {
                    Color.clear.frame(minHeight: 64)
                }
            }
        }
        .frame(maxWidth: 380)
    }
}

/// Grille de cases : un motif à lire, ou à recopier en touchant les cases.
struct BoiteGridView: View {
    let side: Int
    let lit: Set<Int>
    let color: Color
    let interactive: Bool
    let onTap: (Int) -> Void

    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 6
            let cell = (min(g.size.width, g.size.height) - gap * CGFloat(side - 1)) / CGFloat(max(1, side))
            VStack(spacing: gap) {
                ForEach(0..<side, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<side, id: \.self) { col in
                            let index = row * side + col
                            let on = lit.contains(index)
                            RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                                .fill(on ? color : Color.black.opacity(interactive ? 0.4 : 0.12))
                                .overlay(RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                                    .strokeBorder(color.opacity(on ? 0 : 0.5), lineWidth: 1.5))
                                .shadow(color: on ? color.opacity(0.6) : .clear, radius: 6)
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture { if interactive { onTap(index) } }
                                .accessibilityElement()
                                .accessibilityLabel(L("Case ligne \(row + 1), colonne \(col + 1)"))
                                .accessibilityValue(on ? L("allumée") : L("éteinte"))
                                .accessibilityAddTraits(interactive ? [.isButton] : [])
                        }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Petit tremblement quand le code est faux.
struct BoiteShake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Fond en bois : clair pour le couvercle, sombre pour l'intérieur de la boîte.
struct BoiteWood: View {
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let base = dark ? Color(hex: 0x2A1C12) : Color(hex: 0xC98F55)
            let line = dark ? Color(hex: 0x3B2817) : Color(hex: 0xB57A43)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            // Veines du bois
            for i in 0..<28 {
                var p = Path()
                let y0 = CGFloat(Draw.hash(i, 11)) * size.height
                p.move(to: CGPoint(x: 0, y: y0))
                var x: CGFloat = 0
                while x < size.width {
                    x += 40
                    let wave = CGFloat(sin(Double(x) / 90 + Double(i))) * 6
                    p.addLine(to: CGPoint(x: x, y: y0 + wave))
                }
                context.stroke(p, with: .color(line.opacity(0.7)), lineWidth: CGFloat(1 + Draw.hash(i, 12) * 2))
            }
            // Coins métalliques
            let r: CGFloat = 26
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                context.fill(Path(ellipseIn: CGRect(x: corner.x - r, y: corner.y - r, width: r * 2, height: r * 2)),
                             with: .color(Color(hex: 0xD9B36A).opacity(dark ? 0.35 : 0.6)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
