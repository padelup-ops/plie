import SwiftUI

extension Theme {
    static let puissance = Color(hex: 0xFFCF33)
    static let p4Red = Color(hex: 0xFF3B5C)
    static let p4Yellow = Color(hex: 0xFFD23D)
    static let p4Plate = Color(hex: 0x1F4FD8)
}

// MARK: - PUISSANCE 4
//
// Duo plié en L : la grille debout sur la moitié haute, et sur la moitié à plat,
// on fait glisser son jeton au-dessus de la colonne avant de le lâcher.

@Observable
final class PuissanceGame {
    enum Phase: Equatable { case menu, playing, over }

    static let cols = 7
    static let rows = 6

    private(set) var phase: Phase = .menu
    /// Index = ligne × 7 + colonne, ligne 0 en bas. 0 vide, 1 rouge, 2 jaune.
    private(set) var grid: [Int] = Array(repeating: 0, count: 42)
    private(set) var turn = 1
    private(set) var winner = 0
    private(set) var winCells: [Int] = []
    private(set) var lastMove: Int?
    private(set) var thinking = false
    private(set) var score = [0, 0, 0]
    var vsComputer = true
    var level = 2
    /// Colonne visée sur le plateau du bas.
    var aim: Int?

    @ObservationIgnored private var starter = 1
    @ObservationIgnored private var generation = 0

    static let computerSide = 2

    func height(_ col: Int) -> Int {
        var h = 0
        while h < Self.rows && grid[h * Self.cols + col] != 0 { h += 1 }
        return h
    }

    var humanTurn: Bool {
        phase == .playing && !thinking && !(vsComputer && turn == Self.computerSide)
    }

    func start() {
        grid = Array(repeating: 0, count: 42)
        winner = 0
        winCells = []
        lastMove = nil
        thinking = false
        aim = nil
        turn = starter
        generation += 1
        phase = .playing
        computerMoveIfNeeded()
    }

    func rematch() {
        starter = starter == 1 ? 2 : 1
        start()
    }

    func backToMenu() {
        generation += 1
        score = [0, 0, 0]
        starter = 1
        phase = .menu
    }

    func humanDrop(_ col: Int) {
        guard humanTurn else { return }
        drop(col)
    }

    private func drop(_ col: Int) {
        let h = height(col)
        guard h < Self.rows else {
            Haptics.warning()
            return
        }
        let index = h * Self.cols + col
        grid[index] = turn
        lastMove = index
        aim = nil
        // Le bruit du jeton qui arrive en bas (la chute dure un peu plus si la colonne est vide).
        let fall = 0.18 + 0.05 * Double(Self.rows - h)
        DispatchQueue.main.asyncAfter(deadline: .now() + fall) {
            SoundPlayer.shared.play(.clack, volume: 0.8)
            Haptics.tap()
        }
        if let cells = Self.winningCells(grid, at: index) {
            winCells = cells
            finish(turn)
            return
        }
        if !grid.contains(0) {
            finish(3)
            return
        }
        turn = turn == 1 ? 2 : 1
        computerMoveIfNeeded()
    }

    private func finish(_ w: Int) {
        winner = w
        score[w == 3 ? 2 : w - 1] += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.phase = .over
            if w == 3 {
                SoundPlayer.shared.play(.thud, volume: 0.7)
            } else if self.vsComputer && w == Self.computerSide {
                SoundPlayer.shared.play(.wrong, volume: 0.7)
                Haptics.error()
            } else {
                SoundPlayer.shared.play(.win, volume: 0.8)
                Haptics.success()
            }
        }
        thinking = true
    }

    /// Les 4 jetons alignés qui passent par cette case, s'il y en a.
    static func winningCells(_ g: [Int], at index: Int) -> [Int]? {
        let p = g[index]
        guard p != 0 else { return nil }
        let r0 = index / cols, c0 = index % cols
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var cells = [index]
            for sign in [1, -1] {
                var r = r0 + dr * sign, c = c0 + dc * sign
                while r >= 0 && r < rows && c >= 0 && c < cols && g[r * cols + c] == p {
                    cells.append(r * cols + c)
                    r += dr * sign
                    c += dc * sign
                }
            }
            if cells.count >= 4 { return cells }
        }
        return nil
    }

    private func computerMoveIfNeeded() {
        guard vsComputer, turn == Self.computerSide, phase == .playing else { return }
        thinking = true
        let gen = generation
        let snapshot = grid
        let level = self.level
        DispatchQueue.global(qos: .userInitiated).async {
            let col = PuissanceAI.choose(snapshot, me: Self.computerSide, level: level)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.generation == gen, self.phase == .playing else { return }
                self.thinking = false
                if let col { self.drop(col) }
            }
        }
    }
}

// MARK: - L'ordinateur (recherche avec élagage alpha-bêta)

enum PuissanceAI {
    static let order = [3, 2, 4, 1, 5, 0, 6]

    /// Toutes les fenêtres de 4 cases alignées.
    static let windows: [[Int]] = {
        var list: [[Int]] = []
        let C = PuissanceGame.cols, R = PuissanceGame.rows
        for r in 0..<R {
            for c in 0..<C {
                for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                    let er = r + dr * 3, ec = c + dc * 3
                    if er >= 0 && er < R && ec >= 0 && ec < C {
                        list.append((0..<4).map { (r + dr * $0) * C + (c + dc * $0) })
                    }
                }
            }
        }
        return list
    }()

    struct Board {
        var cells: [Int]
        var heights: [Int]

        init(_ grid: [Int]) {
            cells = grid
            heights = (0..<PuissanceGame.cols).map { c in
                var h = 0
                while h < PuissanceGame.rows && grid[h * PuissanceGame.cols + c] != 0 { h += 1 }
                return h
            }
        }

        mutating func play(_ c: Int, _ p: Int) -> Int {
            let i = heights[c] * PuissanceGame.cols + c
            cells[i] = p
            heights[c] += 1
            return i
        }

        mutating func undo(_ c: Int) {
            heights[c] -= 1
            cells[heights[c] * PuissanceGame.cols + c] = 0
        }
    }

    static func evaluate(_ b: Board, _ me: Int) -> Int {
        let them = 3 - me
        var score = 0
        for r in 0..<PuissanceGame.rows where b.cells[r * PuissanceGame.cols + 3] == me { score += 3 }
        for w in windows {
            var mine = 0, theirs = 0
            for i in w {
                let v = b.cells[i]
                if v == me { mine += 1 } else if v == them { theirs += 1 }
            }
            if theirs == 0 {
                if mine == 3 { score += 6 } else if mine == 2 { score += 2 }
            } else if mine == 0 {
                if theirs == 3 { score -= 8 } else if theirs == 2 { score -= 2 }
            }
        }
        return score
    }

    static func negamax(_ b: inout Board, depth: Int, alpha: Int, beta: Int, p: Int) -> Int {
        if depth == 0 { return evaluate(b, p) }
        var alpha = alpha
        var best = -1_000_000
        var moved = false
        for c in order where b.heights[c] < PuissanceGame.rows {
            moved = true
            let i = b.play(c, p)
            let value: Int
            if PuissanceGame.winningCells(b.cells, at: i) != nil {
                value = 100_000 + depth
            } else {
                value = -negamax(&b, depth: depth - 1, alpha: -beta, beta: -alpha, p: 3 - p)
            }
            b.undo(c)
            if value > best { best = value }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return moved ? best : 0
    }

    static func choose(_ grid: [Int], me: Int, level: Int) -> Int? {
        var b = Board(grid)
        let legal = order.filter { b.heights[$0] < PuissanceGame.rows }
        guard !legal.isEmpty else { return nil }
        // Gagner tout de suite, sinon bloquer
        for c in legal {
            let i = b.play(c, me)
            let wins = PuissanceGame.winningCells(b.cells, at: i) != nil
            b.undo(c)
            if wins { return c }
        }
        for c in legal {
            let i = b.play(c, 3 - me)
            let wins = PuissanceGame.winningCells(b.cells, at: i) != nil
            b.undo(c)
            if wins && (level > 1 || Double.random(in: 0..<1) < 0.7) { return c }
        }
        if level == 1 {
            return Double.random(in: 0..<1) < 0.5 ? legal.randomElement() : legal.first
        }
        let depth = level == 2 ? 4 : 6
        var bestValue = -1_000_000
        var bestCols: [Int] = []
        for c in legal {
            _ = b.play(c, me)
            let v = -negamax(&b, depth: depth - 1, alpha: -1_000_000, beta: 1_000_000, p: 3 - me)
            b.undo(c)
            if v > bestValue { bestValue = v; bestCols = [c] } else if v == bestValue { bestCols.append(c) }
        }
        return bestCols.randomElement()
    }
}

// MARK: - Écran

struct PuissanceView: View {
    @Environment(AppState.self) private var app
    @State private var game = PuissanceGame()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1440), Color(hex: 0x050A22)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch game.phase {
            case .menu:
                menu
            case .playing, .over:
                table
            }
        }
        .foregroundStyle(.white)
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordPuissance(won: game.vsComputer && game.winner == 1) }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("puissance", [(0.0, { game.vsComputer = false; game.start() })])
            Demo.every("puissance", 0.55, from: 0.6, until: 10) {
                guard game.humanTurn, let c = PuissanceAI.choose(game.grid, me: game.turn, level: 2) else { return }
                game.humanDrop(c)
            }
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .puissance)
            Spacer()
            if game.phase != .menu {
                HStack(spacing: 12) {
                    Label("\(game.score[0])", systemImage: "circle.fill").foregroundStyle(Theme.p4Red)
                    Label("\(game.score[1])", systemImage: "circle.fill").foregroundStyle(Theme.p4Yellow)
                }
                .font(.plie(17))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Score : rouge \(game.score[0]), jaune \(game.score[1])"))
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
                PuissanceLogo()
                    .frame(width: 180, height: 140)
                Text(L("PUISSANCE 4")).font(.plie(40))
                Text(L("Aligne 4 jetons de ta couleur : en ligne, en colonne ou en diagonale. Plie le Duo en L : la grille debout, et tu lâches tes jetons depuis la moitié posée sur la table."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Picker(L("Adversaire"), selection: Binding(get: { game.vsComputer }, set: { game.vsComputer = $0 })) {
                    Text(L("Contre l'ordi")).tag(true)
                    Text(L("À deux")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                if game.vsComputer {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { l in
                            Button {
                                game.level = l
                            } label: {
                                Text(BoardOpponent.levelName(l))
                                    .font(.plie(15, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Capsule().fill(game.level == l ? Theme.puissance : Color.white.opacity(0.1)))
                                    .foregroundStyle(game.level == l ? Theme.ink : .white)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityAddTraits(game.level == l ? [.isSelected] : [])
                        }
                    }
                    .frame(maxWidth: 420)
                }
                Button {
                    game.start()
                } label: {
                    Label(L("Jouer"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.puissance, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: La table : grille en haut, lanceur en bas

    private var statusText: String {
        if game.phase == .over || game.winner != 0 {
            switch game.winner {
            case 3: return L("Match nul !")
            case PuissanceGame.computerSide where game.vsComputer: return L("L'ordinateur gagne")
            case 1: return game.vsComputer ? L("Tu as gagné !") : L("Rouge gagne !")
            default: return L("Jaune gagne !")
            }
        }
        if game.thinking { return L("L'ordinateur réfléchit…") }
        if game.vsComputer { return L("À toi : glisse ton jeton, puis lâche-le") }
        return game.turn == 1 ? L("Au tour de Rouge") : L("Au tour de Jaune")
    }

    private var table: some View {
        GeometryReader { proxy in
            let half = proxy.size.height / 2
            VStack(spacing: 0) {
                // Moitié haute (debout) : la grille
                VStack(spacing: 6) {
                    header
                        .padding(.top, proxy.safeAreaInsets.top)
                    PuissanceGrid(game: game)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .frame(height: half)
                // Moitié basse (à plat) : le lanceur
                PuissanceLauncher(game: game, status: statusText)
                    .padding(.bottom, proxy.safeAreaInsets.bottom)
                    .frame(height: half)
            }
        }
        // La charnière est au milieu de tout l'écran : on compte aussi les marges du haut et du bas.
        .ignoresSafeArea()
    }
}

// MARK: - La grille

struct PuissanceGrid: View {
    let game: PuissanceGame

    var body: some View {
        GeometryReader { g in
            let cell = min(g.size.width / CGFloat(PuissanceGame.cols), g.size.height / CGFloat(PuissanceGame.rows + 1))
            let w = cell * CGFloat(PuissanceGame.cols)
            let h = cell * CGFloat(PuissanceGame.rows)
            let top = cell // une rangée au-dessus pour viser
            ZStack(alignment: .topLeading) {
                // Le jeton qui vise, au-dessus de la grille
                if let aim = game.aim, game.humanTurn {
                    PuissanceToken(color: game.turn == 1 ? Theme.p4Red : Theme.p4Yellow)
                        .frame(width: cell * 0.82, height: cell * 0.82)
                        .position(x: (CGFloat(aim) + 0.5) * cell, y: top * 0.5)
                        .opacity(0.9)
                        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: aim)
                }
                // Les jetons posés (ils tombent derrière la plaque)
                ForEach(0..<42, id: \.self) { i in
                    if game.grid[i] != 0 {
                        let r = i / PuissanceGame.cols, c = i % PuissanceGame.cols
                        let y = top + (CGFloat(PuissanceGame.rows - 1 - r) + 0.5) * cell
                        PuissanceFallingToken(color: game.grid[i] == 1 ? Theme.p4Red : Theme.p4Yellow, fall: y)
                            .frame(width: cell * 0.82, height: cell * 0.82)
                            .position(x: (CGFloat(c) + 0.5) * cell, y: y)
                    }
                }
                PuissancePlate(cols: PuissanceGame.cols, rows: PuissanceGame.rows)
                    .frame(width: w, height: h)
                    .offset(y: top)
                    .allowsHitTesting(false)
                // Les 4 jetons gagnants
                ForEach(game.winCells, id: \.self) { i in
                    let r = i / PuissanceGame.cols, c = i % PuissanceGame.cols
                    PuissanceWinRing()
                        .frame(width: cell * 0.86, height: cell * 0.86)
                        .position(x: (CGFloat(c) + 0.5) * cell, y: top + (CGFloat(PuissanceGame.rows - 1 - r) + 0.5) * cell)
                }
            }
            .frame(width: w, height: h + top)
            .contentShape(Rectangle())
            // Toucher directement une colonne de la grille marche aussi.
            .onTapGesture { location in
                let c = Int(location.x / cell)
                if c >= 0 && c < PuissanceGame.cols { game.humanDrop(c) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Grille de Puissance 4"))
    }
}

/// La plaque bleue percée de trous : les jetons passent derrière.
struct PuissancePlate: View {
    let cols: Int
    let rows: Int

    var body: some View {
        Canvas { context, size in
            let cell = size.width / CGFloat(cols)
            var plate = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cell * 0.18)
            for r in 0..<rows {
                for c in 0..<cols {
                    let rr = cell * 0.41
                    plate.addEllipse(in: CGRect(x: (CGFloat(c) + 0.5) * cell - rr, y: (CGFloat(r) + 0.5) * cell - rr, width: rr * 2, height: rr * 2))
                }
            }
            context.fill(plate, with: .linearGradient(Gradient(colors: [Color(hex: 0x3D74FF), Theme.p4Plate, Color(hex: 0x123AA8)]),
                                                      startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)),
                         style: FillStyle(eoFill: true))
            // Petit reflet sur le bord de chaque trou
            var rims = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    let rr = cell * 0.41
                    rims.addArc(center: CGPoint(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell), radius: rr,
                                startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                }
            }
            context.stroke(rims, with: .color(.black.opacity(0.35)), lineWidth: max(1.5, cell * 0.05))
        }
    }
}

struct PuissanceToken: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.black.opacity(0.18), lineWidth: 3).padding(6)
        }
        .compositingGroup()
    }
}

/// Un jeton qui tombe du haut de la colonne et rebondit en arrivant.
struct PuissanceFallingToken: View {
    let color: Color
    let fall: CGFloat
    @State private var landed = false

    var body: some View {
        PuissanceToken(color: color)
            .offset(y: landed ? 0 : -fall)
            .onAppear {
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 16)) { landed = true }
            }
    }
}

struct PuissanceWinRing: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 5)
            .scaleEffect(pulse ? 1.08 : 0.92)
            .opacity(pulse ? 1 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Le lanceur (moitié du bas)

struct PuissanceLauncher: View {
    let game: PuissanceGame
    let status: String
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width - 24, (g.size.height - 120) * CGFloat(PuissanceGame.cols) / 1.6)
            let col = w / CGFloat(PuissanceGame.cols)
            VStack(spacing: 14) {
                Text(status)
                    .font(.plie(19))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                if game.phase == .over {
                    HStack(spacing: 12) {
                        Button {
                            game.rematch()
                        } label: {
                            Label(L("Rejouer"), systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.puissance, textColor: Theme.ink, height: 54))
                        Button(L("Réglages")) { game.backToMenu() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 16)
                } else {
                    // Les 7 rampes : on glisse le jeton, on lâche pour le faire tomber.
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(0..<PuissanceGame.cols, id: \.self) { c in
                                let full = game.height(c) >= PuissanceGame.rows
                                RoundedRectangle(cornerRadius: col * 0.25, style: .continuous)
                                    .fill(game.aim == c ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                                    .overlay(
                                        Image(systemName: "arrowtriangle.up.fill")
                                            .font(.system(size: col * 0.3, weight: .bold))
                                            .foregroundStyle(.white.opacity(full ? 0.1 : 0.35))
                                    )
                                    .padding(3)
                                    .accessibilityElement()
                                    .accessibilityLabel(L("Colonne \(c + 1)"))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { game.humanDrop(c) }
                            }
                        }
                        if game.humanTurn, let aim = game.aim {
                            PuissanceToken(color: game.turn == 1 ? Theme.p4Red : Theme.p4Yellow)
                                .frame(width: col * 0.8, height: col * 0.8)
                                .position(x: (CGFloat(aim) + 0.5) * col, y: col * 0.8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: w, height: max(col * 1.6, 80))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard game.humanTurn else { return }
                                let c = min(PuissanceGame.cols - 1, max(0, Int(v.location.x / col)))
                                if game.aim != c {
                                    game.aim = c
                                    Haptics.tap()
                                }
                                dragging = true
                            }
                            .onEnded { v in
                                guard game.humanTurn else { return }
                                let c = min(PuissanceGame.cols - 1, max(0, Int(v.location.x / col)))
                                dragging = false
                                game.humanDrop(c)
                            }
                    )
                    .opacity(game.humanTurn ? 1 : 0.4)
                    Text(game.humanTurn ? L("Glisse le doigt pour viser, lâche pour faire tomber le jeton.") : " ")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(colors: [Color(hex: 0x14204F), Color(hex: 0x0A1230)], startPoint: .top, endPoint: .bottom)
                .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 2), alignment: .top)
                .ignoresSafeArea()
        )
    }
}

/// Petit dessin pour le menu : la grille et deux jetons.
struct PuissanceLogo: View {
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                PuissanceToken(color: Theme.p4Red).frame(width: 46, height: 46)
                PuissanceToken(color: Theme.p4Yellow).frame(width: 46, height: 46)
                PuissanceToken(color: Theme.p4Red).frame(width: 46, height: 46)
            }
            .offset(y: 53)
            PuissancePlate(cols: 3, rows: 2)
                .frame(width: 162, height: 108)
                .offset(y: 26)
        }
        .accessibilityHidden(true)
    }
}
