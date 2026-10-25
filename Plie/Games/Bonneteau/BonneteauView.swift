import SwiftUI
import Combine

extension Theme {
    static let bonneteau = Color(hex: 0xFF7A59)
}

// MARK: - BONNETEAU
//
// À deux, Duo ouvert comme un livre entre les joueurs : celui qui a l'écran intérieur cache la boule
// sous un gobelet et mélange ; en face, l'autre suit tout sur l'écran extérieur, puis dit un numéro.
// Ensuite on retourne le Duo et on inverse les rôles. Seul : l'ordinateur mélange de plus en plus vite.

@Observable
final class BonneteauGame {
    enum Mode: Equatable { case duo, solo }
    enum Phase: Equatable { case menu, hide, shuffle, guess, reveal, over }

    private(set) var phase: Phase = .menu
    private(set) var mode: Mode = .duo
    private(set) var cupCount = 3
    /// Position (0 à gauche) de chaque gobelet.
    private(set) var slots: [Int] = [0, 1, 2]
    private(set) var ballCup = 0
    private(set) var lifted: Set<Int> = []
    /// Pendant un échange, un gobelet passe devant (vers le haut), l'autre derrière.
    private(set) var arc: [Int: CGFloat] = [:]
    private(set) var selected: Int?
    private(set) var picked: Int?
    private(set) var swapDuration = 0.32
    private(set) var swaps = 0
    // À deux
    private(set) var hider = 0
    private(set) var points = [0, 0]
    private(set) var photo: UIImage?
    static let target = 5
    // Seul
    private(set) var level = 1

    @ObservationIgnored private var queue: [(Int, Int)] = []
    /// Observé (pas @ObservationIgnored) : le bouton « J'ai fini » doit se réactiver dès la fin d'un échange.
    private var busy = false
    /// « J'ai fini » touché pendant un échange : on passe à la suite dès qu'il est terminé.
    @ObservationIgnored private var finishWhenIdle = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var takePhoto: (() -> UIImage?)?

    var guesser: Int { 1 - hider }
    var correct: Bool { picked == ballCup }
    var shuffling: Bool { busy || !queue.isEmpty }

    static func playerName(_ i: Int) -> String { L("Joueur \(i + 1)") }

    // MARK: Parties

    func startDuo() {
        mode = .duo
        points = [0, 0]
        hider = 0
        newRound(cups: 3)
        phase = .hide
    }

    func startSolo() {
        mode = .solo
        level = 1
        soloRound()
    }

    #if DEBUG
    /// Démo : seul, déjà à un niveau rapide.
    func demoSolo(level l: Int) {
        mode = .solo
        level = l
        soloRound()
    }
    #endif

    func backToMenu() {
        generation += 1
        queue = []
        busy = false
        finishWhenIdle = false
        phase = .menu
    }

    private func newRound(cups: Int) {
        generation += 1
        cupCount = cups
        slots = Array(0..<cups)
        lifted = []
        arc = [:]
        selected = nil
        picked = nil
        photo = nil
        swaps = 0
        queue = []
        busy = false
        finishWhenIdle = false
        ballCup = 0
    }

    // MARK: À deux

    /// Celui qui cache touche un gobelet : la boule va dessous (l'autre le voit faire).
    func hideBall(under cup: Int) {
        guard phase == .hide else { return }
        ballCup = cup
        withAnimation(.easeOut(duration: 0.25)) { lifted = [cup] }
        SoundPlayer.shared.play(.pop, volume: 0.6)
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.generation == gen else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.lifted = [] }
            SoundPlayer.shared.play(.thud, volume: 0.6)
            self.phase = .shuffle
        }
    }

    /// Mélange à la main : on touche un gobelet, puis un autre, et ils s'échangent.
    func tapCup(_ cup: Int) {
        switch phase {
        case .hide:
            hideBall(under: cup)
        case .shuffle where mode == .duo:
            if let s = selected {
                selected = nil
                if s != cup { enqueue(s, cup) }
            } else {
                selected = cup
                Haptics.tap()
            }
        case .guess:
            pick(cup)
        default:
            break
        }
    }

    func quickShuffle() {
        guard phase == .shuffle else { return }
        selected = nil
        for _ in 0..<6 { enqueueRandomSwap() }
    }

    func doneShuffling() {
        guard phase == .shuffle, mode == .duo, swaps > 0 || shuffling else { return }
        selected = nil
        if shuffling {
            finishWhenIdle = true
            return
        }
        finishWhenIdle = false
        phase = .guess
        SoundPlayer.shared.play(.go, volume: 0.5)
    }

    func nextRound() {
        guard phase == .reveal else { return }
        if mode == .duo {
            if points.contains(where: { $0 >= Self.target }) {
                phase = .over
                return
            }
            hider = guesser
            newRound(cups: 3)
            phase = .hide
        } else if correct {
            level += 1
            soloRound()
        } else {
            phase = .over
        }
    }

    // MARK: Seul contre l'ordi

    private func soloRound() {
        let cups = level < 6 ? 3 : (level < 12 ? 4 : 5)
        newRound(cups: cups)
        ballCup = Int.random(in: 0..<cups)
        swapDuration = max(0.13, 0.42 - Double(level) * 0.022)
        phase = .hide
        let gen = generation
        withAnimation(.easeOut(duration: 0.25)) { lifted = [ballCup] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.generation == gen else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.lifted = [] }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.phase = .shuffle
                for _ in 0..<(4 + self.level) { self.enqueueRandomSwap() }
            }
        }
    }

    // MARK: Les échanges

    private func enqueueRandomSwap() {
        let a = Int.random(in: 0..<cupCount)
        var b = Int.random(in: 0..<cupCount)
        while b == a { b = Int.random(in: 0..<cupCount) }
        enqueue(a, b)
    }

    private func enqueue(_ a: Int, _ b: Int) {
        queue.append((a, b))
        runQueue()
    }

    private func runQueue() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let (a, b) = queue.removeFirst()
        let d = swapDuration
        let gen = generation
        withAnimation(.easeInOut(duration: d)) {
            let sa = slots[a]
            slots[a] = slots[b]
            slots[b] = sa
        }
        withAnimation(.easeOut(duration: d / 2)) { arc = [a: -1, b: 0.5] }
        SoundPlayer.shared.play(.whoosh, volume: 0.35)
        swaps += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + d / 2) { [weak self] in
            guard let self, self.generation == gen else { return }
            withAnimation(.easeIn(duration: d / 2)) { self.arc = [:] }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 1.05) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.busy = false
            if self.queue.isEmpty {
                if self.mode == .solo && self.phase == .shuffle {
                    self.phase = .guess
                } else if self.finishWhenIdle {
                    self.doneShuffling()
                }
            } else {
                self.runQueue()
            }
        }
    }

    // MARK: Révéler

    private func pick(_ cup: Int) {
        guard phase == .guess else { return }
        picked = cup
        photo = mode == .duo ? takePhoto?() : nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lifted = [cup] }
        phase = .reveal
        if correct {
            SoundPlayer.shared.play(mode == .solo ? .chime : .applause, volume: 0.7)
            Haptics.success()
        } else {
            SoundPlayer.shared.play(.wrong, volume: 0.7)
            Haptics.error()
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.generation == gen else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { _ = self.lifted.insert(self.ballCup) }
            }
        }
        if mode == .duo {
            if correct { points[guesser] += 1 } else { points[hider] += 1 }
        }
    }
}

// MARK: - Écran (intérieur)

struct BonneteauView: View {
    @Environment(AppState.self) private var app
    @State private var game = BonneteauGame()
    @State private var camera = GuessersCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = true
    @State private var outerAvailable = false

    private var twoScreens: Bool { outerAvailable && cameraOn }

    var body: some View {
        ZStack {
            BonneteauFelt()
            switch game.phase {
            case .menu: menu
            case .over: over
            default: table
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            game.takePhoto = { [camera] in camera.snapshot() }
            camera.start { ok in cameraOn = ok }
        }
        .onDisappear { camera.stop() }
        .task {
            #if DEBUG
            Demo.schedule("bonneteau", [(0.0, { game.demoSolo(level: 6) })])
            Demo.every("bonneteau", 0.6, from: 1.0, until: 14) {
                if game.phase == .guess { game.tapCup(game.ballCup) }
            }
            #endif
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over {
                if game.mode == .solo { app.recordBonneteau(level: game.level) } else { app.recordBonneteau(level: 0) }
            }
        }
        // En face, celui qui devine suit tout sur l'écran extérieur.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            BonneteauOuterView(game: game)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .bonneteau)
            Spacer()
            if game.phase != .menu {
                if game.mode == .duo {
                    BonneteauScore(game: game)
                } else {
                    Text(L("Niveau \(game.level)"))
                        .font(.plie(17))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
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
                BonneteauCupShape()
                    .fill(LinearGradient(colors: [Color(hex: 0xFF8A5C), Color(hex: 0xC93A2A)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 110, height: 120)
                    .accessibilityHidden(true)
                Text(L("BONNETEAU")).font(.plie(40))
                Text(L("Où est la boule ? Un joueur cache la boule sous un gobelet et mélange, l'autre doit suivre."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                Button {
                    game.startDuo()
                } label: {
                    modeLabel(symbol: "person.2.fill", title: L("À deux, face à face"),
                              detail: twoScreens ? L("Ouvre le Duo comme un livre entre vous : celui qui devine regarde l'écran extérieur.")
                                                 : L("Celui qui cache mélange, l'autre regarde le même écran."))
                }
                .buttonStyle(PressableStyle())

                Button {
                    game.startSolo()
                } label: {
                    modeLabel(symbol: "person.fill", title: L("Seul contre l'ordi"),
                              detail: app.bonneteauBest > 0 ? L("Les gobelets vont de plus en plus vite. Record : niveau \(app.bonneteauBest).")
                                                            : L("Les gobelets vont de plus en plus vite. Jusqu'où iras-tu ?"))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private func modeLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26, weight: .bold)).frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.plie(19))
                Text(detail)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .opacity(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .background(FoldedPaper(color: Theme.bonneteau, cornerRadius: 22))
    }

    // MARK: La table

    private var instruction: String {
        let name = BonneteauGame.playerName(game.hider)
        let other = BonneteauGame.playerName(game.guesser)
        switch (game.mode, game.phase) {
        case (.duo, .hide): return L("\(name), touche un gobelet pour y cacher la boule. \(other) te regarde faire !")
        case (.duo, .shuffle): return L("Touche deux gobelets pour les échanger, aussi vite que tu veux. \(other) doit suivre la boule.")
        case (.duo, .guess): return twoScreens ? L("\(other), dis le numéro du gobelet ! \(name), touche celui qu'il a dit.")
                                               : L("\(other), touche le gobelet où se cache la boule !")
        case (.duo, .reveal): return game.correct ? L("Trouvé ! Un point pour \(other).") : L("Raté ! Un point pour \(name).")
        case (.solo, .hide): return L("Regarde bien où est la boule…")
        case (.solo, .shuffle): return L("Suis-la des yeux !")
        case (.solo, .guess): return L("Où est la boule ? Touche le bon gobelet.")
        case (.solo, .reveal): return game.correct ? L("Bravo ! Prêt pour plus vite ?") : L("Raté…")
        default: return ""
        }
    }

    private var table: some View {
        VStack(spacing: 12) {
            header
            Text(instruction)
                .font(.plie(20))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(minHeight: 60)
                .animation(.easeInOut(duration: 0.2), value: game.phase)
            BonneteauTable(game: game, mirrored: false, interactive: true, numbers: game.mode == .duo && twoScreens)
                .frame(maxWidth: 900)
                .padding(.horizontal, 12)
            controls
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch game.phase {
        case .shuffle where game.mode == .duo:
            HStack(spacing: 12) {
                Button(L("Mélange rapide")) { game.quickShuffle() }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    game.doneShuffling()
                } label: {
                    Label(L("J'ai fini"), systemImage: "checkmark")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bonneteau, textColor: Theme.ink, height: 54))
                .disabled(game.swaps == 0 && !game.shuffling)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 16)
        case .reveal:
            VStack(spacing: 12) {
                if let photo = game.photo {
                    HStack(spacing: 12) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(L("Sa tête au moment de la réponse !"))
                            .font(.plie(15, weight: .bold))
                    }
                }
                Button {
                    game.nextRound()
                } label: {
                    if game.mode == .duo {
                        Label(game.points.contains(where: { $0 >= BonneteauGame.target }) ? L("Voir le gagnant") : L("Tournez le Duo : on inverse !"),
                              systemImage: "arrow.left.arrow.right")
                    } else {
                        Label(game.correct ? L("Niveau suivant") : L("Voir mon score"), systemImage: "arrow.right")
                    }
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bonneteau, textColor: Theme.ink, height: 56))
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 16)
        default:
            Color.clear.frame(height: 56)
        }
    }

    private var over: some View {
        VStack(spacing: 16) {
            header
            Spacer()
            if game.mode == .duo {
                let winner = game.points[0] >= game.points[1] ? 0 : 1
                Text(verbatim: "🏆").font(.system(size: 72)).accessibilityHidden(true)
                Text(L("\(BonneteauGame.playerName(winner)) gagne !")).font(.plie(34))
                Text(verbatim: "\(game.points[0]) – \(game.points[1])").font(.plie(26)).foregroundStyle(Theme.gold)
                Button(L("Revanche")) { game.startDuo() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.bonneteau, textColor: Theme.ink, height: 58))
                    .frame(maxWidth: 360)
            } else {
                Text(verbatim: "🥤").font(.system(size: 72)).accessibilityHidden(true)
                Text(L("Niveau \(game.level)")).font(.plie(34))
                Text(game.level >= app.bonneteauBest ? L("Nouveau record !") : L("Ton record : niveau \(app.bonneteauBest)"))
                    .font(.plie(18, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Button(L("Rejouer")) { game.startSolo() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.bonneteau, textColor: Theme.ink, height: 58))
                    .frame(maxWidth: 360)
            }
            Button(L("Menu")) { game.backToMenu() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 360)
            Spacer()
        }
    }
}

struct BonneteauScore: View {
    let game: BonneteauGame

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(BonneteauGame.playerName(i)).font(.plie(14, weight: .bold))
                    Text(verbatim: "\(game.points[i])").font(.plie(18))
                }
                .foregroundStyle(i == game.hider ? Theme.bonneteau : .white)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
}

// MARK: - Écran extérieur : celui qui devine

struct BonneteauOuterView: View {
    let game: BonneteauGame

    private var line: String {
        let name = BonneteauGame.playerName(game.hider)
        switch game.phase {
        case .hide: return L("\(name) cache la boule… regarde bien !")
        case .shuffle: return L("Suis la boule des yeux !")
        case .guess: return L("Où est la boule ? Dis son numéro !")
        case .reveal: return game.correct ? L("Trouvé !") : L("Raté !")
        case .over: return L("Fin de la partie")
        case .menu: return L("Prêts ?")
        }
    }

    var body: some View {
        ZStack {
            BonneteauFelt()
            VStack(spacing: 14) {
                if game.mode == .duo && game.phase != .menu {
                    BonneteauScore(game: game).padding(.top, 14)
                }
                Text(line)
                    .font(.plie(26))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
                if game.phase != .menu && game.phase != .over {
                    // Vu de l'autre côté de la table : gauche et droite sont inversées.
                    BonneteauTable(game: game, mirrored: true, interactive: false, numbers: true)
                        .padding(.horizontal, 10)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - La table et les gobelets

struct BonneteauTable: View {
    let game: BonneteauGame
    let mirrored: Bool
    let interactive: Bool
    let numbers: Bool

    var body: some View {
        GeometryReader { g in
            let n = game.cupCount
            let spacing = g.size.width / CGFloat(n + 1)
            let cupW = min(spacing * 0.78, g.size.height * 0.62)
            let cupH = cupW * 1.1
            let baseY = g.size.height * 0.72
            ZStack {
                // Les ombres sur le tapis
                ForEach(0..<n, id: \.self) { cup in
                    Ellipse()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: cupW * 0.9, height: cupW * 0.18)
                        .position(x: x(for: cup, spacing: spacing, width: g.size.width), y: baseY + cupH * 0.02)
                }
                // La boule n'existe à l'écran que quand son gobelet est soulevé : pendant les échanges,
                // un gobelet qui passe par-dessus ou rétrécit ne peut donc jamais la laisser voir.
                if game.lifted.contains(game.ballCup) {
                    BonneteauBall()
                        .frame(width: cupW * 0.36, height: cupW * 0.36)
                        .position(x: x(for: game.ballCup, spacing: spacing, width: g.size.width), y: baseY - cupW * 0.2)
                        .transition(.opacity)
                }
                ForEach(0..<n, id: \.self) { cup in
                    let up = game.lifted.contains(cup)
                    let arc = game.arc[cup] ?? 0
                    let isSelected = game.selected == cup
                    let lift: CGFloat = up ? cupH * 0.62 : 0
                    let nudge: CGFloat = isSelected ? 10 : 0
                    let cupY: CGFloat = baseY - cupH / 2 - lift + arc * cupH * 0.28 - nudge
                    let scale: CGFloat = arc < 0 ? 1.08 : (arc > 0 ? 0.94 : 1)
                    BonneteauCup(highlight: isSelected)
                        .frame(width: cupW, height: cupH)
                        .scaleEffect(scale)
                        .position(x: x(for: cup, spacing: spacing, width: g.size.width), y: cupY)
                        .zIndex(arc < 0 ? 2 : 1)
                        .onTapGesture { if interactive { game.tapCup(cup) } }
                        .accessibilityElement()
                        .accessibilityLabel(L("Gobelet \(number(for: cup))"))
                        .accessibilityAddTraits(interactive ? [.isButton] : [])
                    if numbers {
                        Text(verbatim: "\(number(for: cup))")
                            .font(.plie(max(18, cupW * 0.22)))
                            .foregroundStyle(Theme.gold)
                            .position(x: x(for: cup, spacing: spacing, width: g.size.width), y: baseY + cupW * 0.24)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .aspectRatio(2.2, contentMode: .fit)
    }

    /// Le numéro d'un gobelet, compté depuis la gauche de celui qui devine (de l'autre côté de la table).
    private func number(for cup: Int) -> Int {
        game.cupCount - game.slots[cup]
    }

    private func x(for cup: Int, spacing: CGFloat, width: CGFloat) -> CGFloat {
        let raw = spacing * CGFloat(game.slots[cup] + 1)
        return mirrored ? width - raw : raw
    }
}

struct BonneteauCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.06))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.8, y: rect.minY + h * 0.06), control: CGPoint(x: rect.midX, y: rect.minY - h * 0.04))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - h * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - h * 0.08), control: CGPoint(x: rect.midX, y: rect.maxY + h * 0.06))
        p.closeSubpath()
        return p
    }
}

struct BonneteauCup: View {
    let highlight: Bool

    var body: some View {
        ZStack {
            BonneteauCupShape()
                .fill(LinearGradient(colors: [Color(hex: 0xFF9466), Color(hex: 0xE5482F), Color(hex: 0x9E2418)],
                                     startPoint: .leading, endPoint: .trailing))
            // Rayures dorées
            GeometryReader { g in
                let h = g.size.height
                Path { p in
                    for k in [0.3, 0.55] {
                        p.move(to: CGPoint(x: g.size.width * (0.2 - 0.2 * k), y: h * k))
                        p.addLine(to: CGPoint(x: g.size.width * (0.8 + 0.2 * k), y: h * k))
                    }
                }
                .stroke(Color(hex: 0xFFD27A), lineWidth: max(3, h * 0.05))
            }
            .clipShape(BonneteauCupShape())
            // Reflet
            BonneteauCupShape()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center))
            if highlight {
                BonneteauCupShape().stroke(Color.white, lineWidth: 4)
            }
        }
        .compositingGroup()
    }
}

struct BonneteauBall: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white, Color(hex: 0xFFE3A0), Color(hex: 0xE8A000)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 30))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

/// Le tapis de jeu, vert foncé avec une lumière au centre. Dessiné une fois.
struct BonneteauFelt: View {
    var body: some View {
        ZStack {
            Color(hex: 0x0B3B26)
            RadialGradient(colors: [Color(hex: 0x1F7A4D).opacity(0.9), .clear], center: .center, startRadius: 0, endRadius: 520)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
