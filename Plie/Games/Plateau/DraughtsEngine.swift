import Foundation

// MARK: - Dames internationales (10 × 10)
//
// Cases : index = rangée × 10 + colonne, rangée 0 en haut (côté Noirs), rangée 9 en bas (côté Blancs).
// Seules les cases foncées servent : (rangée + colonne) impaire. Numérotation officielle 1 à 50 :
// de gauche à droite, de haut en bas. Pièces : 1 pion blanc, 2 dame blanche, -1 pion noir, -2 dame noire.
// Règles : prise obligatoire et majoritaire, pions qui prennent en avant et en arrière, dames volantes,
// pièces prises retirées en fin de rafle (on ne saute pas deux fois la même), promotion seulement
// si le pion termine son coup sur la dernière rangée. Fichier sans dépendance : testé seul (perft).

struct DraughtsMove: Hashable {
    /// Cases visitées, de la case de départ à la case d'arrivée.
    let path: [Int]
    /// Cases des pièces prises, dans l'ordre de la rafle.
    let captures: [Int]

    var from: Int { path[0] }
    var to: Int { path[path.count - 1] }

    /// Notation officielle : « 32-28 » ou « 28x19x10 ».
    var notation: String {
        if captures.isEmpty {
            return "\(DraughtsPosition.number(of: from))-\(DraughtsPosition.number(of: to))"
        }
        return path.map { "\(DraughtsPosition.number(of: $0))" }.joined(separator: "x")
    }
}

struct DraughtsPosition: Equatable {
    var board: [Int8]
    var whiteToMove: Bool

    static let size = 10
    static let darkCells: [Int] = (0..<100).filter { ($0 / 10 + $0 % 10) % 2 == 1 }
    static let directions = [(-1, -1), (-1, 1), (1, -1), (1, 1)]

    static let start: DraughtsPosition = {
        var b = [Int8](repeating: 0, count: 100)
        for cell in darkCells {
            let row = cell / 10
            if row <= 3 { b[cell] = -1 }
            if row >= 6 { b[cell] = 1 }
        }
        return DraughtsPosition(board: b, whiteToMove: true)
    }()

    init(board: [Int8], whiteToMove: Bool) {
        self.board = board
        self.whiteToMove = whiteToMove
    }

    /// Numéro officiel (1 à 50) d'une case foncée.
    static func number(of cell: Int) -> Int {
        (cell / 10) * 5 + (cell % 10) / 2 + 1
    }

    static func cell(ofNumber n: Int) -> Int {
        let row = (n - 1) / 5
        let k = (n - 1) % 5
        let col = row % 2 == 0 ? 2 * k + 1 : 2 * k
        return row * 10 + col
    }

    // MARK: FEN (format PDN : « W:W31-50:B1-20 », K devant une dame)

    init?(fen: String) {
        var b = [Int8](repeating: 0, count: 100)
        let parts = fen.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let turn = parts.first, turn == "W" || turn == "B" else { return nil }
        for part in parts.dropFirst() {
            guard let side = part.first, side == "W" || side == "B" else { continue }
            let sign: Int8 = side == "W" ? 1 : -1
            for item in part.dropFirst().split(separator: ",") {
                var s = String(item)
                var king = false
                if s.hasPrefix("K") { king = true; s.removeFirst() }
                let range = s.split(separator: "-").compactMap { Int($0) }
                guard let lo = range.first else { continue }
                let hi = range.count > 1 ? range[1] : lo
                guard lo >= 1, hi <= 50, lo <= hi else { return nil }
                for n in lo...hi { b[Self.cell(ofNumber: n)] = sign * (king ? 2 : 1) }
            }
        }
        board = b
        whiteToMove = turn == "W"
    }

    var fen: String {
        func list(_ sign: Int8) -> String {
            Self.darkCells.compactMap { cell -> String? in
                let v = board[cell]
                guard v * sign > 0 else { return nil }
                return (abs(v) == 2 ? "K" : "") + "\(Self.number(of: cell))"
            }.joined(separator: ",")
        }
        return "\(whiteToMove ? "W" : "B"):W\(list(1)):B\(list(-1))"
    }

    var key: String {
        String(board.map { Character(UnicodeScalar(UInt8(Int(70 + $0)))) }) + (whiteToMove ? "w" : "b")
    }

    @inline(__always) static func inside(_ r: Int, _ c: Int) -> Bool {
        r >= 0 && r < 10 && c >= 0 && c < 10
    }

    // MARK: Coups

    func legalMoves() -> [DraughtsMove] {
        let us: Int8 = whiteToMove ? 1 : -1
        var captures: [DraughtsMove] = []
        for cell in Self.darkCells where board[cell] * us > 0 {
            if abs(board[cell]) == 2 {
                kingCaptures(start: cell, cur: cell, path: [cell], taken: [], us: us, out: &captures)
            } else {
                manCaptures(start: cell, cur: cell, path: [cell], taken: [], us: us, out: &captures)
            }
        }
        if !captures.isEmpty {
            let best = captures.map(\.captures.count).max() ?? 0
            var seen = Set<String>()
            var result: [DraughtsMove] = []
            for m in captures where m.captures.count == best {
                let id = "\(m.from)-\(m.to)-\(m.captures.sorted())"
                if seen.insert(id).inserted { result.append(m) }
            }
            return result
        }
        var moves: [DraughtsMove] = []
        for cell in Self.darkCells where board[cell] * us > 0 {
            let r = cell / 10, c = cell % 10
            if abs(board[cell]) == 2 {
                for (dr, dc) in Self.directions {
                    var nr = r + dr, nc = c + dc
                    while Self.inside(nr, nc) && board[nr * 10 + nc] == 0 {
                        moves.append(DraughtsMove(path: [cell, nr * 10 + nc], captures: []))
                        nr += dr
                        nc += dc
                    }
                }
            } else {
                let dr = whiteToMove ? -1 : 1
                for dc in [-1, 1] {
                    let nr = r + dr, nc = c + dc
                    if Self.inside(nr, nc) && board[nr * 10 + nc] == 0 {
                        moves.append(DraughtsMove(path: [cell, nr * 10 + nc], captures: []))
                    }
                }
            }
        }
        return moves
    }

    /// Une case est libre pendant la rafle si elle est vide, ou si c'est la case de départ de la pièce.
    @inline(__always) private func free(_ cell: Int, start: Int) -> Bool {
        board[cell] == 0 || cell == start
    }

    private func manCaptures(start: Int, cur: Int, path: [Int], taken: [Int], us: Int8, out: inout [DraughtsMove]) {
        let r = cur / 10, c = cur % 10
        var extended = false
        for (dr, dc) in Self.directions {
            let mr = r + dr, mc = c + dc
            let lr = r + 2 * dr, lc = c + 2 * dc
            guard Self.inside(lr, lc) else { continue }
            let mid = mr * 10 + mc, land = lr * 10 + lc
            if board[mid] * us < 0 && !taken.contains(mid) && free(land, start: start) {
                extended = true
                manCaptures(start: start, cur: land, path: path + [land], taken: taken + [mid], us: us, out: &out)
            }
        }
        if !extended && !taken.isEmpty {
            out.append(DraughtsMove(path: path, captures: taken))
        }
    }

    private func kingCaptures(start: Int, cur: Int, path: [Int], taken: [Int], us: Int8, out: inout [DraughtsMove]) {
        let r = cur / 10, c = cur % 10
        var extended = false
        for (dr, dc) in Self.directions {
            var nr = r + dr, nc = c + dc
            while Self.inside(nr, nc) && free(nr * 10 + nc, start: start) {
                nr += dr
                nc += dc
            }
            guard Self.inside(nr, nc) else { continue }
            let victim = nr * 10 + nc
            guard board[victim] * us < 0, !taken.contains(victim) else { continue }
            var lr = nr + dr, lc = nc + dc
            while Self.inside(lr, lc) && free(lr * 10 + lc, start: start) {
                extended = true
                let land = lr * 10 + lc
                kingCaptures(start: start, cur: land, path: path + [land], taken: taken + [victim], us: us, out: &out)
                lr += dr
                lc += dc
            }
        }
        if !extended && !taken.isEmpty {
            out.append(DraughtsMove(path: path, captures: taken))
        }
    }

    /// Le pion qui termine son coup sur la dernière rangée devient dame.
    func promotes(_ m: DraughtsMove) -> Bool {
        let piece = board[m.from]
        guard abs(piece) == 1 else { return false }
        let row = m.to / 10
        return piece > 0 ? row == 0 : row == 9
    }

    func making(_ m: DraughtsMove) -> DraughtsPosition {
        var n = self
        let piece = board[m.from]
        n.board[m.from] = 0
        for cell in m.captures { n.board[cell] = 0 }
        n.board[m.to] = promotes(m) ? piece * 2 : piece
        n.whiteToMove.toggle()
        return n
    }

    func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = legalMoves()
        if depth == 1 { return moves.count }
        return moves.reduce(0) { $0 + making($1).perft(depth - 1) }
    }

    func count(white: Bool) -> (men: Int, kings: Int) {
        var men = 0, kings = 0
        for v in board where white ? v > 0 : v < 0 {
            if abs(v) == 2 { kings += 1 } else { men += 1 }
        }
        return (men, kings)
    }
}

// MARK: - Partie

enum DraughtsResult: Equatable {
    case win(white: Bool)
    case repetition
    case kingMoves
    case resignation(winnerWhite: Bool)
    case timeout(winnerWhite: Bool)
    case agreement

    var winnerWhite: Bool? {
        switch self {
        case .win(let w): return w
        case .resignation(let w), .timeout(let w): return w
        default: return nil
        }
    }
}

struct DraughtsGameRecord {
    private(set) var positions: [DraughtsPosition] = [DraughtsPosition.start]
    private(set) var moves: [DraughtsMove] = []
    private var keyCounts: [String: Int] = [DraughtsPosition.start.key: 1]
    /// Coups successifs de dames sans prise ni mouvement de pion (25 par camp = nulle).
    private(set) var quietKingMoves = 0

    var position: DraughtsPosition { positions[positions.count - 1] }

    init() {}

    init(notations: [String]) {
        for n in notations {
            guard let m = position.legalMoves().first(where: { $0.notation == n }) else { break }
            play(m)
        }
    }

    mutating func play(_ m: DraughtsMove) {
        let isKing = abs(position.board[m.from]) == 2
        quietKingMoves = (isKing && m.captures.isEmpty) ? quietKingMoves + 1 : 0
        let next = position.making(m)
        moves.append(m)
        positions.append(next)
        keyCounts[next.key, default: 0] += 1
    }

    mutating func undo(_ count: Int = 1) {
        let keep = max(0, moves.count - count)
        self = DraughtsGameRecord(notations: moves.prefix(keep).map(\.notation))
    }

    var ruleResult: DraughtsResult? {
        let p = position
        if p.legalMoves().isEmpty { return .win(white: !p.whiteToMove) }
        if keyCounts[p.key, default: 0] >= 3 { return .repetition }
        if quietKingMoves >= 50 { return .kingMoves }
        return nil
    }
}

// MARK: - Ordinateur

enum DraughtsAI {
    static let win = 100_000

    /// Évaluation du point de vue du camp qui doit jouer.
    static func evaluate(_ p: DraughtsPosition) -> Int {
        var score = 0
        var whiteMen = 0, blackMen = 0
        for cell in DraughtsPosition.darkCells {
            let v = p.board[cell]
            guard v != 0 else { continue }
            let row = cell / 10, col = cell % 10
            var s: Int
            if abs(v) == 2 {
                s = 330
            } else {
                let advance = v > 0 ? 9 - row : row
                s = 100 + advance * 4
                if v > 0 { whiteMen += 1 } else { blackMen += 1 }
                if (v > 0 && row == 9) || (v < 0 && row == 0) { s += 6 }   // garder la rangée de fond
            }
            if (3...6).contains(col) && (3...6).contains(row) { s += 7 }   // le centre
            if col == 0 || col == 9 { s -= 4 }                              // les bords bloquent
            score += v > 0 ? s : -s
        }
        _ = whiteMen + blackMen
        return p.whiteToMove ? score : -score
    }

    final class Search {
        let deadline: Date
        var nodes = 0
        var aborted = false
        let noise: Int

        init(deadline: Date, noise: Int) {
            self.deadline = deadline
            self.noise = noise
        }

        func negamax(_ p: DraughtsPosition, depth: Int, _ alpha: Int, _ beta: Int, ply: Int) -> Int {
            nodes += 1
            if nodes & 511 == 0 && Date() > deadline { aborted = true }
            if aborted { return 0 }
            let moves = p.legalMoves()
            if moves.isEmpty { return -DraughtsAI.win + ply }
            // Tant qu'il y a des prises, on prolonge un peu la recherche (pas d'horizon au milieu d'un échange).
            let forced = !moves[0].captures.isEmpty
            if depth <= 0 && (!forced || ply > 24) { return DraughtsAI.evaluate(p) }
            var alpha = alpha
            var best = -DraughtsAI.win
            let ordered = moves.sorted { $0.captures.count > $1.captures.count }
            for m in ordered {
                let v = -negamax(p.making(m), depth: depth - 1, -beta, -alpha, ply: ply + 1)
                if aborted { return 0 }
                if v > best { best = v }
                if v > alpha { alpha = v }
                if alpha >= beta { break }
            }
            return best
        }
    }

    static func bestMove(_ p: DraughtsPosition, maxDepth: Int, seconds: Double, noise: Int = 0) -> DraughtsMove? {
        let legal = p.legalMoves()
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return legal[0] }
        let search = Search(deadline: Date().addingTimeInterval(seconds), noise: noise)
        var best = legal[0]
        var order = legal
        for depth in 1...max(1, maxDepth) {
            var alpha = -win - 1
            var bestHere: DraughtsMove?
            for m in order {
                var v = -search.negamax(p.making(m), depth: depth - 1, -win - 1, -alpha, ply: 1)
                if search.aborted { break }
                if noise > 0 { v += Int.random(in: -noise...noise) }
                if bestHere == nil || v > alpha {
                    alpha = v
                    bestHere = m
                }
            }
            if search.aborted { break }
            if let bestHere {
                best = bestHere
                order = [bestHere] + order.filter { $0 != bestHere }
            }
        }
        return best
    }
}
