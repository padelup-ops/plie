import SwiftUI

extension Theme {
    static let morpion = Color(hex: 0xFF6FD8)
    static let neonX = Color(hex: 0x21F3FF)
    static let neonO = Color(hex: 0xFF2BD6)
}

// MARK: - MORPION
//
// Duo ouvert à plat entre deux joueurs, ou seul contre l'ordinateur.
// Deux règles : le morpion classique (3 × 3), et le super morpion (9 petites grilles) :
// la case où tu joues décide dans quelle petite grille l'autre doit jouer.

enum MorpionMode: Equatable {
    case classic
    case ultimate
}

@Observable
final class MorpionGame {
    enum Phase: Equatable { case menu, playing, over }

    static let lines: [[Int]] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    private(set) var phase: Phase = .menu
    var mode: MorpionMode = .classic
    var vsComputer = true
    var level = 2
    private(set) var cells: [Int] = Array(repeating: 0, count: 9)
    /// Super morpion : 0 en jeu, 1 ou 2 gagnée, 3 pleine sans gagnant.
    private(set) var boards: [Int] = Array(repeating: 0, count: 9)
    /// Super morpion : la petite grille où il faut jouer (nil = au choix).
    private(set) var forced: Int?
    private(set) var turn = 1
    private(set) var winner = 0
    private(set) var winLine: [Int] = []
    private(set) var lastMove: Int?
    /// Victoires de X, de O, et matchs nuls, depuis le début de la série.
    private(set) var score = [0, 0, 0]
    private(set) var thinking = false

    @ObservationIgnored private var starter = 1
    @ObservationIgnored private var generation = 0

    static let computerSide = 2

    static func lineWinner(_ v: [Int]) -> (winner: Int, line: [Int])? {
        for line in lines {
            let a = v[line[0]]
            if a != 0 && a != 3 && a == v[line[1]] && a == v[line[2]] { return (a, line) }
        }
        return nil
    }

    func start() {
        let count = mode == .classic ? 9 : 81
        cells = Array(repeating: 0, count: count)
        boards = Array(repeating: 0, count: 9)
        forced = nil
        winner = 0
        winLine = []
        lastMove = nil
        thinking = false
        turn = starter
        generation += 1
        phase = .playing
        computerMoveIfNeeded()
    }

    /// Nouvelle partie : l'autre joueur commence.
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

    var legalMoves: [Int] {
        MorpionAI.legal(mode: mode, cells: cells, boards: boards, forced: forced)
    }

    var humanTurn: Bool {
        phase == .playing && !thinking && !(vsComputer && turn == Self.computerSide)
    }

    func tap(_ i: Int) {
        guard humanTurn, legalMoves.contains(i) else { return }
        play(i)
    }

    private func play(_ i: Int) {
        cells[i] = turn
        lastMove = i
        SoundPlayer.shared.play(turn == 1 ? .pok : .tock, volume: 0.7)
        Haptics.tap()
        if mode == .classic {
            if let r = Self.lineWinner(cells) { finish(r.winner, r.line); return }
            if !cells.contains(0) { finish(3, []); return }
        } else {
            let b = i / 9, l = i % 9
            let local = Array(cells[(b * 9)..<(b * 9 + 9)])
            if let r = Self.lineWinner(local) {
                boards[b] = r.winner
                SoundPlayer.shared.play(.chime, volume: 0.6)
            } else if !local.contains(0) {
                boards[b] = 3
            }
            if let r = Self.lineWinner(boards) { finish(r.winner, r.line); return }
            forced = boards[l] == 0 ? l : nil
            if legalMoves.isEmpty { finish(3, []); return }
        }
        turn = turn == 1 ? 2 : 1
        computerMoveIfNeeded()
    }

    private func finish(_ w: Int, _ line: [Int]) {
        winner = w
        winLine = line
        score[w == 3 ? 2 : w - 1] += 1
        phase = .over
        if w == 3 {
            SoundPlayer.shared.play(.thud, volume: 0.7)
        } else if vsComputer && w == Self.computerSide {
            SoundPlayer.shared.play(.wrong, volume: 0.7)
            Haptics.error()
        } else {
            SoundPlayer.shared.play(.win, volume: 0.8)
            Haptics.success()
        }
    }

    private func computerMoveIfNeeded() {
        guard vsComputer, turn == Self.computerSide, phase == .playing else { return }
        thinking = true
        let gen = generation
        let state = MorpionAI.State(mode: mode, cells: cells, boards: boards, forced: forced, me: Self.computerSide)
        let level = self.level
        // Le calcul se fait en arrière-plan : l'écran reste fluide.
        DispatchQueue.global(qos: .userInitiated).async {
            let move = MorpionAI.choose(state, level: level)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.generation == gen, self.phase == .playing else { return }
                self.thinking = false
                if let move { self.play(move) }
            }
        }
    }
}

// MARK: - L'ordinateur

enum MorpionAI {
    struct State {
        let mode: MorpionMode
        let cells: [Int]
        let boards: [Int]
        let forced: Int?
        let me: Int
    }

    static func legal(mode: MorpionMode, cells: [Int], boards: [Int], forced: Int?) -> [Int] {
        if mode == .classic { return cells.indices.filter { cells[$0] == 0 } }
        var result: [Int] = []
        for b in 0..<9 where boards[b] == 0 && (forced == nil || forced == b) {
            for l in 0..<9 where cells[b * 9 + l] == 0 { result.append(b * 9 + l) }
        }
        return result
    }

    static func choose(_ s: State, level: Int) -> Int? {
        s.mode == .classic ? classic(s.cells, me: s.me, level: level) : ultimate(s, level: level)
    }

    static func winningMove(_ cells: [Int], for p: Int) -> Int? {
        for line in MorpionGame.lines {
            let mine = line.filter { cells[$0] == p }.count
            if mine == 2, let empty = line.first(where: { cells[$0] == 0 }) { return empty }
        }
        return nil
    }

    static func classic(_ cells: [Int], me: Int, level: Int) -> Int? {
        let free = cells.indices.filter { cells[$0] == 0 }
        guard !free.isEmpty else { return nil }
        if level == 1 && Double.random(in: 0..<1) < 0.55 { return free.randomElement() }
        if let w = winningMove(cells, for: me) { return w }
        if let b = winningMove(cells, for: 3 - me) { return b }
        if level >= 3 { return bestMinimax(cells, me: me) }
        if level == 2 && Double.random(in: 0..<1) < 0.25 { return free.randomElement() }
        if cells[4] == 0 { return 4 }
        return [0, 2, 6, 8].filter { cells[$0] == 0 }.randomElement() ?? free.randomElement()
    }

    private static func minimax(_ cells: inout [Int], turn: Int, me: Int, depth: Int) -> Int {
        if let r = MorpionGame.lineWinner(cells) { return r.winner == me ? 10 - depth : depth - 10 }
        if !cells.contains(0) { return 0 }
        var best = turn == me ? Int.min : Int.max
        for i in 0..<9 where cells[i] == 0 {
            cells[i] = turn
            let v = minimax(&cells, turn: 3 - turn, me: me, depth: depth + 1)
            cells[i] = 0
            best = turn == me ? max(best, v) : min(best, v)
        }
        return best
    }

    private static func bestMinimax(_ cells: [Int], me: Int) -> Int? {
        var c = cells
        var bestValue = Int.min
        var moves: [Int] = []
        for i in 0..<9 where c[i] == 0 {
            c[i] = me
            let v = minimax(&c, turn: 3 - me, me: me, depth: 1)
            c[i] = 0
            if v > bestValue { bestValue = v; moves = [i] } else if v == bestValue { moves.append(i) }
        }
        return moves.randomElement()
    }

    /// Super morpion : chaque coup reçoit une note (gagner une grille, bloquer, ne pas envoyer l'autre au bon endroit…).
    static func ultimate(_ s: State, level: Int) -> Int? {
        let moves = legal(mode: .ultimate, cells: s.cells, boards: s.boards, forced: s.forced)
        guard !moves.isEmpty else { return nil }
        let me = s.me, them = 3 - me
        let noise = level == 1 ? 40.0 : (level == 2 ? 10.0 : 1.5)
        var best: Int?
        var bestScore = -Double.infinity
        for m in moves {
            let b = m / 9, l = m % 9
            var score = 0.0
            var cells = s.cells
            cells[m] = me
            var boards = s.boards
            let local = Array(cells[(b * 9)..<(b * 9 + 9)])
            if let r = MorpionGame.lineWinner(local), r.winner == me {
                boards[b] = me
                score += 25
                if let g = MorpionGame.lineWinner(boards), g.winner == me { score += 1000 }
            } else if !local.contains(0) {
                boards[b] = 3
            }
            // Bloquer une petite grille que l'autre allait gagner
            var blocked = Array(s.cells[(b * 9)..<(b * 9 + 9)])
            blocked[l] = them
            if let r = MorpionGame.lineWinner(blocked), r.winner == them { score += 14 }
            // Où envoie-t-on l'adversaire ?
            if boards[l] == 0 {
                let next = Array(cells[(l * 9)..<(l * 9 + 9)])
                if winningMove(next, for: them) != nil {
                    score -= 20
                    var test = boards
                    test[l] = them
                    if let g = MorpionGame.lineWinner(test), g.winner == them { score -= 600 }
                }
            } else {
                score -= 12
            }
            if l == 4 { score += 3 } else if [0, 2, 6, 8].contains(l) { score += 1.5 }
            if b == 4 { score += 2 }
            score += Double.random(in: 0..<noise)
            if score > bestScore { bestScore = score; best = m }
        }
        return best
    }
}

// MARK: - Écran

struct MorpionView: View {
    @Environment(AppState.self) private var app
    @State private var game = MorpionGame()
    @State private var showResult = false

    var body: some View {
        ZStack {
            NeonBackdrop()
            switch game.phase {
            case .menu:
                menu
            case .playing, .over:
                board
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            #if DEBUG
            Demo.schedule("morpion", [(0.0, { game.mode = .ultimate; game.vsComputer = false; game.start() })])
            Demo.every("morpion", 0.3, from: 0.5, until: 9) {
                guard game.humanTurn else { return }
                let state = MorpionAI.State(mode: game.mode, cells: game.cells, boards: game.boards, forced: game.forced, me: game.turn)
                if let move = MorpionAI.choose(state, level: 2) { game.tap(move) }
            }
            #endif
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over {
                app.recordMorpion(won: game.vsComputer && game.winner == 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    if game.phase == .over { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showResult = true } }
                }
            } else {
                showResult = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .morpion)
            Spacer()
            if game.phase != .menu {
                scorePill
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var scorePill: some View {
        HStack(spacing: 10) {
            Text(verbatim: "✕ \(game.score[0])").foregroundStyle(Theme.neonX)
            Text(verbatim: "◯ \(game.score[1])").foregroundStyle(Theme.neonO)
            Text(verbatim: "= \(game.score[2])").foregroundStyle(Theme.muted)
        }
        .font(.plie(17))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Score : X \(game.score[0]), O \(game.score[1]), nuls \(game.score[2])"))
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                NeonTitle(text: L("MORPION"))
                    .padding(.top, 6)
                VStack(spacing: 12) {
                    modeCard(.classic, title: L("Classique"), detail: L("3 × 3 : aligne trois symboles."), symbol: "number")
                    modeCard(.ultimate, title: L("Super morpion"), detail: L("9 petites grilles. La case où tu joues envoie l'autre dans la grille du même endroit. Gagne trois grilles alignées !"), symbol: "square.grid.3x3.fill")
                }
                .frame(maxWidth: 520)

                Picker(L("Adversaire"), selection: Binding(get: { game.vsComputer }, set: { game.vsComputer = $0 })) {
                    Text(L("Contre l'ordi")).tag(true)
                    Text(L("À deux, face à face")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if game.vsComputer {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { l in
                            Button {
                                game.level = l
                            } label: {
                                Text(levelName(l))
                                    .font(.plie(15, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Capsule().fill(game.level == l ? Theme.morpion : Color.white.opacity(0.1)))
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
                .buttonStyle(ChunkyButtonStyle(color: Theme.morpion, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    private func levelName(_ l: Int) -> String {
        if l == 3 && game.mode == .classic { return L("Imbattable") }
        return BoardOpponent.levelName(l)
    }

    private func modeCard(_ mode: MorpionMode, title: String, detail: String, symbol: String) -> some View {
        let selected = game.mode == mode
        return Button {
            game.mode = mode
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.plie(19))
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .opacity(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
            }
            .foregroundStyle(selected ? Theme.ink : .white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? Theme.morpion : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Plateau

    private var statusText: String {
        if game.phase == .over {
            switch game.winner {
            case 3: return L("Match nul !")
            case MorpionGame.computerSide where game.vsComputer: return L("L'ordinateur gagne")
            case 1: return game.vsComputer ? L("Tu as gagné !") : L("X gagne !")
            default: return L("O gagne !")
            }
        }
        if game.thinking { return L("L'ordinateur réfléchit…") }
        if game.vsComputer { return L("À toi de jouer") }
        return game.turn == 1 ? L("Au tour de X") : L("Au tour de O")
    }

    private var board: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width - 32, proxy.size.height - 220)
            VStack(spacing: 14) {
                header
                if !game.vsComputer {
                    // Le joueur d'en face lit le tour à l'endroit.
                    status(for: 2)
                        .rotationEffect(.degrees(180))
                }
                Spacer(minLength: 0)
                MorpionBoardView(game: game)
                    .frame(width: max(200, side), height: max(200, side))
                Spacer(minLength: 0)
                status(for: 1)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showResult { result }
            }
        }
    }

    private func status(for seat: Int) -> some View {
        let color = game.phase == .over ? Theme.gold : (game.turn == 1 ? Theme.neonX : Theme.neonO)
        let mine = game.vsComputer || game.phase == .over || game.turn == seat
        return HStack(spacing: 10) {
            if game.phase == .playing {
                Text(verbatim: game.turn == 1 ? "✕" : "◯")
                    .font(.plie(22))
                    .foregroundStyle(color)
            }
            Text(statusText)
                .font(.plie(20))
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(color.opacity(mine ? 0.8 : 0.2), lineWidth: 2))
        .opacity(mine ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.2), value: game.turn)
    }

    private var result: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { showResult = false }
            VStack(spacing: 14) {
                Text(statusText)
                    .font(.paperTitle(32))
                    .multilineTextAlignment(.center)
                scorePill
                Button {
                    game.rematch()
                } label: {
                    Label(L("Rejouer"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.morpion, textColor: Theme.ink, height: 56))
                Button(L("Changer les réglages")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(26)
            .frame(maxWidth: 380)
            .winCard(accent: game.winner == 3 ? Theme.muted : (game.winner == 1 ? Theme.neonX : Theme.neonO))
            .padding(24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// MARK: - La grille

struct MorpionBoardView: View {
    let game: MorpionGame

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                if game.mode == .classic {
                    NeonGridLines(divisions: 3, color: Theme.morpion, width: max(3, s * 0.012))
                    cellsGrid(range: 0..<9, cols: 3, size: s, offset: .zero, cellInset: s * 0.05)
                    if !game.winLine.isEmpty {
                        NeonWinLine(from: center(game.winLine.first ?? 0, cols: 3, size: s),
                                    to: center(game.winLine.last ?? 0, cols: 3, size: s),
                                    color: game.winner == 1 ? Theme.neonX : Theme.neonO, width: s * 0.03)
                    }
                } else {
                    ultimate(size: s)
                }
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func center(_ i: Int, cols: Int, size: CGFloat) -> CGPoint {
        let c = size / CGFloat(cols)
        return CGPoint(x: (CGFloat(i % cols) + 0.5) * c, y: (CGFloat(i / cols) + 0.5) * c)
    }

    private func cellsGrid(range: Range<Int>, cols: Int, size: CGFloat, offset: CGPoint, cellInset: CGFloat) -> some View {
        let c = size / CGFloat(cols)
        let legal = Set(game.humanTurn ? game.legalMoves : [])
        return ForEach(Array(range), id: \.self) { i in
            let local = i - range.lowerBound
            ZStack {
                Color.clear
                if game.cells[i] != 0 {
                    MorpionMark(player: game.cells[i])
                        .padding(cellInset)
                        .opacity(game.lastMove == i || game.phase == .over ? 1 : 0.92)
                }
            }
            .frame(width: c, height: c)
            .contentShape(Rectangle())
            .onTapGesture { game.tap(i) }
            .position(x: offset.x + (CGFloat(local % cols) + 0.5) * c, y: offset.y + (CGFloat(local / cols) + 0.5) * c)
            .accessibilityElement()
            .accessibilityLabel(L("Case \(local + 1)"))
            .accessibilityValue(game.cells[i] == 1 ? "X" : (game.cells[i] == 2 ? "O" : L("vide")))
            .accessibilityAddTraits(legal.contains(i) ? [.isButton] : [])
        }
    }

    @ViewBuilder
    private func ultimate(size s: CGFloat) -> some View {
        let big = s / 3
        let pad = big * 0.07
        ForEach(0..<9, id: \.self) { b in
            let origin = CGPoint(x: CGFloat(b % 3) * big + pad, y: CGFloat(b / 3) * big + pad)
            let inner = big - pad * 2
            let active = game.phase == .playing && game.boards[b] == 0 && (game.forced == nil || game.forced == b)
            ZStack {
                RoundedRectangle(cornerRadius: inner * 0.08, style: .continuous)
                    .fill(active ? (game.turn == 1 ? Theme.neonX : Theme.neonO).opacity(0.12) : Color.clear)
                RoundedRectangle(cornerRadius: inner * 0.08, style: .continuous)
                    .strokeBorder(active ? (game.turn == 1 ? Theme.neonX : Theme.neonO).opacity(0.8) : Color.clear, lineWidth: 2)
                NeonGridLines(divisions: 3, color: Theme.morpion.opacity(0.7), width: max(1.5, s * 0.004))
                    .padding(inner * 0.04)
            }
            .frame(width: inner, height: inner)
            .position(x: origin.x + inner / 2, y: origin.y + inner / 2)
            .allowsHitTesting(false)
        }
        NeonGridLines(divisions: 3, color: Theme.morpion, width: max(3, s * 0.012))
        ForEach(0..<9, id: \.self) { b in
            let origin = CGPoint(x: CGFloat(b % 3) * big + pad, y: CGFloat(b / 3) * big + pad)
            cellsGrid(range: (b * 9)..<(b * 9 + 9), cols: 3, size: big - pad * 2, offset: origin, cellInset: big * 0.035)
                .opacity(game.boards[b] == 0 ? 1 : 0.25)
        }
        // Les petites grilles gagnées : un grand symbole par-dessus
        ForEach(0..<9, id: \.self) { b in
            if game.boards[b] == 1 || game.boards[b] == 2 {
                MorpionMark(player: game.boards[b])
                    .padding(big * 0.12)
                    .frame(width: big, height: big)
                    .position(x: (CGFloat(b % 3) + 0.5) * big, y: (CGFloat(b / 3) + 0.5) * big)
                    .allowsHitTesting(false)
            }
        }
        if !game.winLine.isEmpty {
            NeonWinLine(from: center(game.winLine.first ?? 0, cols: 3, size: s),
                        to: center(game.winLine.last ?? 0, cols: 3, size: s),
                        color: game.winner == 1 ? Theme.neonX : Theme.neonO, width: s * 0.03)
        }
    }
}

// MARK: - Éléments néon

/// Un X ou un O qui se dessine en néon.
struct MorpionMark: View {
    let player: Int
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let lw = max(2.5, s * 0.12)
            let color = player == 1 ? Theme.neonX : Theme.neonO
            let shape = MorpionMarkShape(cross: player == 1)
            ZStack {
                shape.trim(from: 0, to: progress)
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: lw * 2.2, lineCap: .round))
                shape.trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                shape.trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lw * 0.3, lineCap: .round))
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }
}

struct MorpionMarkShape: Shape {
    let cross: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        if cross {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
        }
        return p
    }
}

/// Les lignes d'une grille, en néon (sans les bords).
struct NeonGridLines: View {
    let divisions: Int
    let color: Color
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            var p = Path()
            for k in 1..<divisions {
                let x = size.width * CGFloat(k) / CGFloat(divisions)
                let y = size.height * CGFloat(k) / CGFloat(divisions)
                p.move(to: CGPoint(x: x, y: width))
                p.addLine(to: CGPoint(x: x, y: size.height - width))
                p.move(to: CGPoint(x: width, y: y))
                p.addLine(to: CGPoint(x: size.width - width, y: y))
            }
            context.stroke(p, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: width * 3, lineCap: .round))
            context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            context.stroke(p, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: max(1, width * 0.3), lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Le trait de la victoire, qui se dessine.
struct NeonWinLine: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let width: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        let line = Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }
        ZStack {
            line.trim(from: 0, to: progress).stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round))
            line.trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            line.trim(from: 0, to: progress).stroke(Color.white, style: StrokeStyle(lineWidth: width * 0.35, lineCap: .round))
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeInOut(duration: 0.45)) { progress = 1 } }
    }
}

/// Titre en lettres néon.
struct NeonTitle: View {
    let text: String

    var body: some View {
        ZStack {
            Text(text).foregroundStyle(Theme.neonO.opacity(0.6)).blur(radius: 10)
            Text(text).foregroundStyle(Color.white)
                .shadow(color: Theme.neonX.opacity(0.9), radius: 4)
        }
        .font(.system(size: 46, weight: .black, design: .rounded))
        .tracking(2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Fond sombre façon salle d'arcade : dégradé violet et quadrillage au sol. Dessiné une seule fois.
struct NeonBackdrop: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x07021A), Color(hex: 0x1E0840), Color(hex: 0x0A0218)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let horizon = size.height * 0.72
            var grid = Path()
            for k in -14...14 {
                grid.move(to: CGPoint(x: size.width / 2, y: horizon))
                grid.addLine(to: CGPoint(x: size.width / 2 + CGFloat(k) * size.width * 0.16, y: size.height * 1.1))
            }
            var y = horizon + 6
            var step: CGFloat = 8
            while y < size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                step *= 1.35
                y += step
            }
            context.stroke(grid, with: .color(Theme.neonO.opacity(0.22)), lineWidth: 1.5)
            for i in 0..<40 {
                let x = CGFloat(Draw.hash(i, 71)) * size.width
                let yy = CGFloat(Draw.hash(i, 72)) * horizon * 0.95
                let r = CGFloat(1 + Draw.hash(i, 73) * 1.5)
                context.fill(Path(ellipseIn: CGRect(x: x, y: yy, width: r, height: r)), with: .color(.white.opacity(0.25 + 0.5 * Draw.hash(i, 74))))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
