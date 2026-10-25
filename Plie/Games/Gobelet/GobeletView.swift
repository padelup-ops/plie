import SwiftUI
import Combine

extension Theme {
    static let gobelet = Color(hex: 0xFF7A45)
}

// MARK: - Le gobelet : le Yams avec le Duo
//
// Le Duo fermé, c'est le gobelet : on le secoue (les dés roulent dedans, sur l'écran extérieur).
// On l'ouvre, c'est comme soulever le gobelet : les dés tombent sur le tapis de l'écran intérieur.

enum YamsCategory: Int, CaseIterable, Identifiable {
    case ones = 1, twos, threes, fours, fives, sixes
    case threeKind, fourKind, fullHouse, smallStraight, largeStraight, yams, chance

    var id: Int { rawValue }
    var isUpper: Bool { rawValue <= 6 }

    var name: String {
        switch self {
        case .ones: return L("As")
        case .twos: return L("Deux")
        case .threes: return L("Trois")
        case .fours: return L("Quatre")
        case .fives: return L("Cinq")
        case .sixes: return L("Six")
        case .threeKind: return L("Brelan")
        case .fourKind: return L("Carré")
        case .fullHouse: return L("Full")
        case .smallStraight: return L("Petite suite")
        case .largeStraight: return L("Grande suite")
        case .yams: return L("Yams")
        case .chance: return L("Chance")
        }
    }

    var hint: String {
        switch self {
        case .ones, .twos, .threes, .fours, .fives, .sixes: return L("Total des \(rawValue)")
        case .threeKind: return L("3 dés pareils : total des dés")
        case .fourKind: return L("4 dés pareils : total des dés")
        case .fullHouse: return L("3 pareils + 2 pareils : 25")
        case .smallStraight: return L("4 qui se suivent : 30")
        case .largeStraight: return L("5 qui se suivent : 40")
        case .yams: return L("5 dés pareils : 50")
        case .chance: return L("Total des dés")
        }
    }

    func score(_ dice: [Int]) -> Int {
        guard dice.count == 5, !dice.contains(0) else { return 0 }
        let total = dice.reduce(0, +)
        var counts = [Int](repeating: 0, count: 7)
        for d in dice { counts[d] += 1 }
        let set = Set(dice)
        switch self {
        case .ones, .twos, .threes, .fours, .fives, .sixes:
            return counts[rawValue] * rawValue
        case .threeKind: return counts.contains { $0 >= 3 } ? total : 0
        case .fourKind: return counts.contains { $0 >= 4 } ? total : 0
        case .fullHouse:
            let used = counts.filter { $0 > 0 }.sorted()
            return used == [2, 3] ? 25 : 0
        case .smallStraight:
            let runs: [Set<Int>] = [[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]]
            return runs.contains { $0.isSubset(of: set) } ? 30 : 0
        case .largeStraight:
            return set == [1, 2, 3, 4, 5] || set == [2, 3, 4, 5, 6] ? 40 : 0
        case .yams: return counts.contains(5) ? 50 : 0
        case .chance: return total
        }
    }
}

@Observable
final class GobeletGame {
    enum Phase: Equatable {
        /// Choix du nombre de joueurs.
        case menu
        /// Il faut secouer le gobelet (Duo fermé) ou toucher « Lancer ».
        case needRoll
        /// Le Duo est fermé, on secoue.
        case shaking
        /// Les dés ont roulé sous le gobelet : on ouvre pour voir.
        case hidden
        /// Les dés sont sur le tapis : garder, relancer ou marquer.
        case choosing
        case over
    }

    struct Player: Identifiable {
        let id: Int
        let name: String
        var scores: [YamsCategory: Int] = [:]

        var upper: Int { YamsCategory.allCases.filter(\.isUpper).compactMap { scores[$0] }.reduce(0, +) }
        var bonus: Int { upper >= 63 ? 35 : 0 }
        var total: Int { scores.values.reduce(0, +) + bonus }
        var done: Bool { scores.count == YamsCategory.allCases.count }
    }

    private(set) var phase: Phase = .menu
    private(set) var players: [Player] = []
    private(set) var current = 0
    private(set) var dice = [0, 0, 0, 0, 0]
    private(set) var held = [false, false, false, false, false]
    private(set) var rollsLeft = 3
    private(set) var rollID = 0
    private(set) var shakeEnergy: Double = 0
    private(set) var isClosed = false
    private(set) var hasHinge = false
    private(set) var lastShake: Double = 0

    @ObservationIgnored private var lastRattle = Date.distantPast

    var player: Player? { players.indices.contains(current) ? players[current] : nil }
    var canReroll: Bool { phase == .choosing && rollsLeft > 0 && held.contains(false) }

    func start(count: Int) {
        players = (0..<count).map { i in Player(id: i, name: count == 1 ? L("Toi") : L("Joueur \(i + 1)")) }
        current = 0
        beginTurn()
        SoundPlayer.shared.play(.go, volume: 0.6)
    }

    func backToMenu() {
        phase = .menu
    }

    private func beginTurn() {
        rollsLeft = 3
        held = [false, false, false, false, false]
        dice = [0, 0, 0, 0, 0]
        shakeEnergy = 0
        phase = isClosed ? .shaking : .needRoll
    }

    // MARK: Le gobelet

    /// Le Duo s'ouvre ou se ferme.
    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        if closed {
            if phase == .needRoll { phase = .shaking; shakeEnergy = 0 }
        } else {
            switch phase {
            case .shaking:
                // Ouvert après avoir un peu secoué : les dés roulent quand même.
                if shakeEnergy > 0.6 { roll(); reveal() } else { phase = .needRoll }
            case .hidden:
                reveal()
            default:
                break
            }
        }
    }

    /// Secousses du téléphone (en g).
    func shake(_ force: Double) {
        lastShake = force
        guard force > 0.45 else { return }
        if phase == .needRoll && !hasHinge {
            // Téléphone sans charnière : on secoue directement.
            shakeEnergy += force * 0.08
            rattle(force)
            if shakeEnergy > 1.6 { roll(); reveal() }
            return
        }
        guard phase == .shaking || phase == .hidden else { return }
        shakeEnergy += force * 0.08
        rattle(force)
        if phase == .shaking && shakeEnergy > 1.6 {
            roll()
            phase = .hidden
            Haptics.success()
        }
    }

    private func rattle(_ force: Double) {
        guard Date().timeIntervalSince(lastRattle) > 0.12 else { return }
        lastRattle = Date()
        SoundPlayer.shared.play(.rattle, volume: Float(min(1, 0.35 + force * 0.4)))
        Haptics.tap()
    }

    /// Bouton « Lancer » (sans secouer).
    func rollNow() {
        guard phase == .needRoll || phase == .shaking else { return }
        roll()
        reveal()
    }

    private func roll() {
        guard rollsLeft > 0 else { return }
        for i in 0..<5 where !held[i] {
            dice[i] = Int.random(in: 1...6)
        }
        rollsLeft -= 1
    }

    private func reveal() {
        phase = .choosing
        rollID += 1
        shakeEnergy = 0
        SoundPlayer.shared.play(.diceLand, volume: 0.9)
        if dice.allSatisfy({ $0 == dice[0] }) && dice[0] > 0 {
            SoundPlayer.shared.play(.applause, volume: 0.8)
        }
    }

    func toggleHold(_ i: Int) {
        guard phase == .choosing, rollsLeft > 0, dice[i] > 0 else { return }
        held[i].toggle()
        SoundPlayer.shared.play(.pieceMove, volume: 0.5)
        Haptics.tap()
    }

    func reroll() {
        guard canReroll else { return }
        shakeEnergy = 0
        phase = isClosed ? .shaking : .needRoll
    }

    // MARK: Marquer

    func canScore(_ c: YamsCategory) -> Bool {
        phase == .choosing && player?.scores[c] == nil
    }

    func record(_ c: YamsCategory) {
        guard canScore(c) else { return }
        let points = c.score(dice)
        players[current].scores[c] = points
        SoundPlayer.shared.play(points > 0 ? .point : .wrong, volume: points > 0 ? 0.7 : 0.4)
        if points > 0 { Haptics.correct(subtle: false) }
        if players.allSatisfy(\.done) {
            phase = .over
            SoundPlayer.shared.play(.win, volume: 0.8)
            SoundPlayer.shared.play(.applause, volume: 0.8)
            Haptics.success()
            return
        }
        current = (current + 1) % players.count
        beginTurn()
    }

    var winner: Player? { players.max { $0.total < $1.total } }
}

// MARK: - Écran

struct GobeletView: View {
    @Environment(AppState.self) private var app
    @State private var game = GobeletGame()
    @State private var motion = MotionSensor()
    @State private var recorded = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(hex: 0x3A1410), Color(hex: 0x1A0907)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                switch game.phase {
                case .menu:
                    menu
                case .over:
                    results
                default:
                    if game.isClosed {
                        CupView(game: game)
                    } else {
                        table(proxy: proxy)
                    }
                }
            }
        }
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onAppear {
            motion.onReading = { reading in game.shake(reading.shake) }
            motion.start(hz: 40)
        }
        .onDisappear { motion.stop() }
        .onChange(of: game.phase) { _, phase in
            if phase == .over && !recorded, let best = game.players.map(\.total).max() {
                recorded = true
                app.recordGobelet(best: game.players.count == 1 ? best : 0)
            }
        }
    }

    // MARK: Choix des joueurs

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                DieView(value: 5, held: false, rollID: 0, index: 0, size: 70)
                    .rotationEffect(.degrees(-12))
                    .padding(.top, 10)
                Text(L("Le gobelet"))
                    .font(.plie(32))
                Text(game.hasHinge || DuoSupport.apisAvailable
                     ? L("Ton Duo fermé est le gobelet : secoue-le, puis ouvre-le pour découvrir les dés. Fais les meilleures combinaisons en 13 tours.")
                     : L("Secoue le téléphone pour lancer les dés, garde les bons, et fais les meilleures combinaisons en 13 tours."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if app.gobeletBest > 0 {
                    Label(L("Record en solo : \(app.gobeletBest) points"), systemImage: "trophy.fill")
                        .font(.plie(15, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                Text(L("Combien de joueurs ?"))
                    .font(.plie(17, weight: .bold))
                    .padding(.top, 6)
                HStack(spacing: 10) {
                    ForEach(1...4, id: \.self) { n in
                        Button {
                            recorded = false
                            game.start(count: n)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: n == 1 ? "person.fill" : (n == 2 ? "person.2.fill" : "person.3.fill"))
                                    .font(.system(size: 22, weight: .bold))
                                Text("\(n)").font(.plie(24))
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                            .background(FoldedPaper(color: Theme.gobelet, cornerRadius: 20))
                            .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(n == 1 ? L("Seul") : L("\(n) joueurs"))
                    }
                }
                .frame(maxWidth: 460)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu || game.phase == .over { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .gobelet)
            Spacer()
            if let p = game.player, game.phase != .menu, game.phase != .over {
                Pill(text: L("\(p.name) · \(p.total) pts"), color: Theme.gobelet.opacity(0.25), textColor: Theme.gobelet)
            }
        }
    }

    // MARK: Le tapis (écran intérieur)

    private func table(proxy: GeometryProxy) -> some View {
        let wide = proxy.size.width > proxy.size.height * 1.1
        return VStack(spacing: 12) {
            header
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    tray.frame(maxWidth: .infinity)
                    ScoreSheet2(game: game).frame(width: min(420, proxy.size.width * 0.46))
                }
            } else {
                tray
                ScoreSheet2(game: game)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private var tray: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x1F8A5B), Color(hex: 0x0F5236)], center: .center, startRadius: 10, endRadius: 360))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(hex: 0x6B3A1F), lineWidth: 10)
                if game.phase == .choosing || game.dice.contains(where: { $0 > 0 }) {
                    HStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { i in
                            Button {
                                game.toggleHold(i)
                            } label: {
                                DieView(value: game.dice[i], held: game.held[i], rollID: game.rollID, index: i, size: 58)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(game.held[i] ? L("Dé \(i + 1) : \(game.dice[i]), gardé") : L("Dé \(i + 1) : \(game.dice[i])"))
                            .accessibilityHint(L("Touche pour garder ou relâcher ce dé"))
                        }
                    }
                    .padding(.vertical, 26)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "dice.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(L("Les dés sont dans le gobelet"))
                            .font(.plie(16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.vertical, 30)
                }
            }
            .frame(minHeight: 150)

            Text(prompt)
                .font(.plie(17, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 10) {
                if game.phase == .needRoll {
                    Button {
                        game.rollNow()
                    } label: {
                        Label(L("Lancer"), systemImage: "dice.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gobelet, textColor: Theme.ink, height: 56))
                } else if game.phase == .choosing {
                    Button {
                        game.reroll()
                    } label: {
                        Label(L("Relancer (\(game.rollsLeft))"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gobelet, textColor: Theme.ink, height: 56))
                    .disabled(!game.canReroll)
                    .opacity(game.canReroll ? 1 : 0.4)
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private var prompt: String {
        switch game.phase {
        case .needRoll:
            if game.hasHinge {
                return game.rollsLeft == 3 ? L("Ferme ton Duo et secoue le gobelet !") : L("Ferme le Duo et secoue pour relancer les dés libres")
            }
            return L("Secoue le téléphone, ou touche « Lancer »")
        case .choosing:
            return game.rollsLeft > 0
                ? L("Touche les dés à garder, puis relance. Ou marque tes points dans le tableau.")
                : L("Plus de lancer : choisis une case du tableau.")
        default:
            return ""
        }
    }

    // MARK: Fin de partie

    private var results: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                WinIcon(systemName: "trophy.fill", color: Theme.gold)
                if game.players.count == 1, let p = game.player {
                    Text(L("\(p.total) points"))
                        .font(.plie(40))
                    if p.bonus > 0 {
                        Text(L("Bonus de 35 points gagné !")).font(.plie(16, weight: .bold)).foregroundStyle(Theme.gold)
                    }
                    ShareResultButton(game: L("GOBELET"), result: L("\(p.total) points au Yams"), accent: Theme.gobelet)
                } else if let w = game.winner {
                    Text(L("\(w.name) gagne !"))
                        .font(.plie(34))
                    ForEach(game.players.sorted { $0.total > $1.total }) { p in
                        HStack {
                            Text(p.name).font(.plie(18, weight: .bold))
                            Spacer()
                            Text("\(p.total)").font(.plie(20))
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(p.id == w.id ? 0.18 : 0.07)))
                    }
                    .frame(maxWidth: 420)
                }
                Button(L("Rejouer")) {
                    recorded = false
                    game.start(count: max(1, game.players.count))
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gobelet, textColor: Theme.ink))
                .frame(maxWidth: 420)
                Button(L("Changer le nombre de joueurs")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 420)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) { ConfettiView().frame(height: 500).allowsHitTesting(false) }
    }
}

// MARK: - Le gobelet (écran extérieur, Duo fermé)

struct CupView: View {
    let game: GobeletGame

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let wobble = min(1, game.lastShake * 1.5)
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    // Le gobelet en cuir, qui tremble quand on secoue
                    CupShape()
                        .fill(LinearGradient(colors: [Color(hex: 0x8A3A22), Color(hex: 0x4A1A0E)], startPoint: .leading, endPoint: .trailing))
                        .overlay(CupShape().stroke(Color(hex: 0xD9A066), lineWidth: 3))
                        .frame(width: 170, height: 200)
                    Text(verbatim: "🎲")
                        .font(.system(size: 44))
                        .offset(y: 20)
                        .opacity(0.9)
                        .accessibilityHidden(true)
                }
                .rotationEffect(.degrees(sin(t * 38) * 9 * wobble))
                .offset(x: CGFloat(sin(t * 31) * 10 * wobble), y: CGFloat(cos(t * 27) * 6 * wobble))

                Text(game.phase == .hidden ? L("Ouvre le Duo pour soulever le gobelet !") : L("Secoue !"))
                    .font(.plie(28))
                    .multilineTextAlignment(.center)
                if game.phase == .shaking {
                    ProgressView(value: min(1, game.shakeEnergy / 1.6))
                        .tint(Theme.gobelet)
                        .frame(maxWidth: 220)
                    Button(L("Lancer sans secouer")) { game.rollNow() }
                        .buttonStyle(GhostButtonStyle())
                        .frame(maxWidth: 260)
                }
                if let p = game.player {
                    Text(L("\(p.name) · lancer \(4 - game.rollsLeft) sur 3"))
                        .font(.plie(15, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * 0.12
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.06))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.06), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.06))
        p.closeSubpath()
        return p
    }
}

// MARK: - Un dé

struct DieView: View {
    let value: Int
    let held: Bool
    let rollID: Int
    let index: Int
    let size: CGFloat
    @State private var spin: Double = 0
    @State private var drop: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFDF6), Color(hex: 0xE8E0CC)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.4), radius: 4, x: 2, y: 4)
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .strokeBorder(held ? Theme.gold : Color.black.opacity(0.08), lineWidth: held ? 4 : 1)
            Canvas { context, s in
                for (x, y) in DieView.pips(value) {
                    let r = s.width * 0.09
                    let c = CGPoint(x: s.width * x, y: s.height * y)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(value == 1 ? Color(hex: 0xD62828) : Color(hex: 0x1A1A1A)))
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if held {
                Text(L("GARDÉ"))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.gold))
                    .foregroundStyle(Theme.ink)
                    .offset(y: 12)
            }
        }
        .rotationEffect(.degrees(spin))
        .offset(drop)
        .offset(y: held ? 10 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: held)
        .onChange(of: rollID) { _, _ in
            guard !held else { return }
            spin = Double.random(in: 200...560) * (Bool.random() ? 1 : -1)
            drop = CGSize(width: CGFloat.random(in: -40...40), height: CGFloat.random(in: -120 ... -60))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(Double(index) * 0.05)) {
                spin = Double.random(in: -8...8)
                drop = .zero
            }
        }
    }

    static func pips(_ v: Int) -> [(CGFloat, CGFloat)] {
        let a: CGFloat = 0.27, m: CGFloat = 0.5, b: CGFloat = 0.73
        switch v {
        case 1: return [(m, m)]
        case 2: return [(a, a), (b, b)]
        case 3: return [(a, a), (m, m), (b, b)]
        case 4: return [(a, a), (b, a), (a, b), (b, b)]
        case 5: return [(a, a), (b, a), (m, m), (a, b), (b, b)]
        case 6: return [(a, a), (b, a), (a, m), (b, m), (a, b), (b, b)]
        default: return []
        }
    }
}

// MARK: - La feuille de marque

struct ScoreSheet2: View {
    let game: GobeletGame

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                HStack {
                    Text(L("Combinaison")).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(game.players) { p in
                        Text(game.players.count == 1 ? L("Points") : p.name)
                            .frame(width: 64)
                            .foregroundStyle(p.id == game.current ? Theme.gobelet : .white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .font(.plie(13, weight: .heavy))
                .padding(.horizontal, 10)

                ForEach(YamsCategory.allCases) { c in
                    row(c)
                    if c == .sixes { bonusRow }
                }
                HStack {
                    Text(L("Total")).font(.plie(16, weight: .heavy)).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(game.players) { p in
                        Text("\(p.total)").font(.plie(17)).frame(width: 64)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.12)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.3)))
    }

    private func row(_ c: YamsCategory) -> some View {
        let available = game.canScore(c)
        let potential = c.score(game.dice)
        return Button {
            game.record(c)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.name).font(.plie(15, weight: .bold))
                    Text(c.hint).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(game.players) { p in
                    Group {
                        if let s = p.scores[c] {
                            Text("\(s)").font(.plie(16)).foregroundStyle(.white)
                        } else if p.id == game.current && available {
                            Text("\(potential)").font(.plie(16)).foregroundStyle(potential > 0 ? Theme.gobelet : .white.opacity(0.35))
                        } else {
                            Text(verbatim: "–").foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    .frame(width: 64)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(available ? Theme.gobelet.opacity(0.12) : Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel(available ? L("\(c.name), \(potential) points") : c.name)
    }

    private var bonusRow: some View {
        HStack {
            Text(L("Bonus (63 en haut)")).font(.plie(13, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(game.players) { p in
                Text(p.bonus > 0 ? "35" : "\(p.upper)/63").font(.plie(13, weight: .bold)).frame(width: 64)
                    .foregroundStyle(p.bonus > 0 ? Theme.gold : Theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
}
