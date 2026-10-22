import Foundation

// MARK: - Échecs : règles complètes
//
// Cases numérotées de 0 à 63 : index = rangée × 8 + colonne, rangée 0 = la rangée 1 des Blancs.
// Pièces : signe = couleur (positif = Blancs), valeur absolue = 1 pion, 2 cavalier, 3 fou,
// 4 tour, 5 dame, 6 roi. Ce fichier n'utilise que Foundation : il est testé seul sur le Mac
// de compilation (comptage de coups « perft » sur des positions de référence).

enum ChessPiece {
    static let pawn: Int8 = 1
    static let knight: Int8 = 2
    static let bishop: Int8 = 3
    static let rook: Int8 = 4
    static let queen: Int8 = 5
    static let king: Int8 = 6
}

struct ChessMove: Hashable {
    static let capture: UInt8 = 1
    static let enPassant: UInt8 = 2
    static let castle: UInt8 = 4
    static let doublePush: UInt8 = 8

    let from: Int
    let to: Int
    var promotion: Int8 = 0
    var flags: UInt8 = 0

    var isCapture: Bool { flags & Self.capture != 0 }
    var isCastle: Bool { flags & Self.castle != 0 }
    var isEnPassant: Bool { flags & Self.enPassant != 0 }

    /// Notation « e2e4 », « e7e8q ».
    var uci: String {
        var s = ChessPosition.squareName(from) + ChessPosition.squareName(to)
        if promotion != 0 { s += ["", "", "n", "b", "r", "q"][Int(promotion)] }
        return s
    }
}

struct ChessPosition: Equatable {
    var board: [Int8]
    var whiteToMove: Bool
    /// 1 = petit roque blanc, 2 = grand roque blanc, 4 = petit roque noir, 8 = grand roque noir.
    var castling: UInt8
    var epSquare: Int
    var halfmove: Int
    var fullmove: Int

    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let start = ChessPosition(fen: startFEN)!

    static func file(_ sq: Int) -> Int { sq & 7 }
    static func rank(_ sq: Int) -> Int { sq >> 3 }

    static func squareName(_ sq: Int) -> String {
        let files = Array("abcdefgh")
        return "\(files[file(sq)])\(rank(sq) + 1)"
    }

    static func square(named name: String) -> Int? {
        let chars = Array(name)
        guard chars.count == 2, let f = "abcdefgh".firstIndex(of: chars[0]),
              let r = Int(String(chars[1])), (1...8).contains(r) else { return nil }
        return (r - 1) * 8 + "abcdefgh".distance(from: "abcdefgh".startIndex, to: f)
    }

    // MARK: FEN

    init?(fen: String) {
        let parts = fen.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        var cells = [Int8](repeating: 0, count: 64)
        let rows = parts[0].split(separator: "/")
        guard rows.count == 8 else { return nil }
        for (i, row) in rows.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in row {
                if let n = ch.wholeNumberValue {
                    file += n
                } else {
                    guard file < 8 else { return nil }
                    let lower = Character(ch.lowercased())
                    guard let type = "pnbrqk".firstIndex(of: lower) else { return nil }
                    let value = Int8("pnbrqk".distance(from: "pnbrqk".startIndex, to: type) + 1)
                    cells[rank * 8 + file] = ch.isUppercase ? value : -value
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        board = cells
        whiteToMove = parts[1] == "w"
        castling = 0
        if parts.count > 2 {
            for ch in parts[2] {
                switch ch {
                case "K": castling |= 1
                case "Q": castling |= 2
                case "k": castling |= 4
                case "q": castling |= 8
                default: break
                }
            }
        }
        epSquare = parts.count > 3 ? (Self.square(named: parts[3]) ?? -1) : -1
        halfmove = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        fullmove = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                let p = board[rank * 8 + file]
                if p == 0 {
                    empty += 1
                } else {
                    if empty > 0 { row += "\(empty)"; empty = 0 }
                    let ch = Array("pnbrqk")[Int(abs(p)) - 1]
                    row += p > 0 ? ch.uppercased() : String(ch)
                }
            }
            if empty > 0 { row += "\(empty)" }
            rows.append(row)
        }
        var c = ""
        if castling & 1 != 0 { c += "K" }
        if castling & 2 != 0 { c += "Q" }
        if castling & 4 != 0 { c += "k" }
        if castling & 8 != 0 { c += "q" }
        if c.isEmpty { c = "-" }
        let ep = epSquare >= 0 ? Self.squareName(epSquare) : "-"
        return "\(rows.joined(separator: "/")) \(whiteToMove ? "w" : "b") \(c) \(ep) \(halfmove) \(fullmove)"
    }

    /// Clé pour repérer les positions répétées.
    var repetitionKey: String {
        var s = String(board.map { Character(UnicodeScalar(UInt8(Int(65 + $0)))) })
        s += whiteToMove ? "w" : "b"
        s += String(castling)
        // La case de prise en passant ne compte que si une prise est vraiment possible.
        if epSquare >= 0 && legalMoves().contains(where: { $0.isEnPassant }) { s += "e\(epSquare)" }
        return s
    }

    // MARK: Attaques

    static let knightJumps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    static let straights = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    func kingSquare(white: Bool) -> Int {
        let k: Int8 = white ? ChessPiece.king : -ChessPiece.king
        return board.firstIndex(of: k) ?? -1
    }

    /// La case est-elle attaquée par le camp indiqué ?
    func isAttacked(_ sq: Int, byWhite: Bool) -> Bool {
        guard sq >= 0 else { return false }
        let f = Self.file(sq), r = Self.rank(sq)
        let s: Int8 = byWhite ? 1 : -1
        // Pions
        let pr = byWhite ? r - 1 : r + 1
        if pr >= 0 && pr < 8 {
            for df in [-1, 1] {
                let pf = f + df
                if pf >= 0 && pf < 8 && board[pr * 8 + pf] == s * ChessPiece.pawn { return true }
            }
        }
        // Cavaliers
        for (df, dr) in Self.knightJumps {
            let nf = f + df, nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && board[nr * 8 + nf] == s * ChessPiece.knight { return true }
        }
        // Roi
        for (df, dr) in Self.kingSteps {
            let nf = f + df, nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 && board[nr * 8 + nf] == s * ChessPiece.king { return true }
        }
        // Lignes : tour et dame ; diagonales : fou et dame
        for (dirs, piece) in [(Self.straights, ChessPiece.rook), (Self.diagonals, ChessPiece.bishop)] {
            for (df, dr) in dirs {
                var nf = f + df, nr = r + dr
                while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    let p = board[nr * 8 + nf]
                    if p != 0 {
                        if p == s * piece || p == s * ChessPiece.queen { return true }
                        break
                    }
                    nf += df
                    nr += dr
                }
            }
        }
        return false
    }

    func inCheck(white: Bool) -> Bool {
        isAttacked(kingSquare(white: white), byWhite: !white)
    }

    var sideInCheck: Bool { inCheck(white: whiteToMove) }

    // MARK: Coups

    func pseudoMoves(capturesOnly: Bool = false) -> [ChessMove] {
        var moves: [ChessMove] = []
        moves.reserveCapacity(48)
        let us: Int8 = whiteToMove ? 1 : -1
        for sq in 0..<64 {
            let p = board[sq]
            guard p * us > 0 else { continue }
            let type = abs(p)
            let f = Self.file(sq), r = Self.rank(sq)
            switch type {
            case ChessPiece.pawn:
                let dir = whiteToMove ? 1 : -1
                let startRank = whiteToMove ? 1 : 6
                let promoRank = whiteToMove ? 7 : 0
                let nr = r + dir
                guard nr >= 0 && nr < 8 else { continue }
                func addPawn(_ to: Int, _ flags: UInt8) {
                    if Self.rank(to) == promoRank {
                        for promo in [ChessPiece.queen, ChessPiece.rook, ChessPiece.bishop, ChessPiece.knight] {
                            moves.append(ChessMove(from: sq, to: to, promotion: promo, flags: flags))
                        }
                    } else {
                        moves.append(ChessMove(from: sq, to: to, flags: flags))
                    }
                }
                let one = nr * 8 + f
                if board[one] == 0 && (!capturesOnly || nr == promoRank) {
                    addPawn(one, 0)
                    if r == startRank && !capturesOnly {
                        let two = (r + 2 * dir) * 8 + f
                        if board[two] == 0 { moves.append(ChessMove(from: sq, to: two, flags: ChessMove.doublePush)) }
                    }
                }
                for df in [-1, 1] {
                    let nf = f + df
                    guard nf >= 0 && nf < 8 else { continue }
                    let to = nr * 8 + nf
                    if board[to] * us < 0 {
                        addPawn(to, ChessMove.capture)
                    } else if to == epSquare {
                        moves.append(ChessMove(from: sq, to: to, flags: ChessMove.capture | ChessMove.enPassant))
                    }
                }
            case ChessPiece.knight, ChessPiece.king:
                let steps = type == ChessPiece.knight ? Self.knightJumps : Self.kingSteps
                for (df, dr) in steps {
                    let nf = f + df, nr = r + dr
                    guard nf >= 0 && nf < 8 && nr >= 0 && nr < 8 else { continue }
                    let to = nr * 8 + nf
                    let target = board[to]
                    if target == 0 {
                        if !capturesOnly { moves.append(ChessMove(from: sq, to: to)) }
                    } else if target * us < 0 {
                        moves.append(ChessMove(from: sq, to: to, flags: ChessMove.capture))
                    }
                }
                if type == ChessPiece.king && !capturesOnly {
                    addCastling(from: sq, into: &moves)
                }
            default:
                let dirs: [(Int, Int)]
                switch type {
                case ChessPiece.bishop: dirs = Self.diagonals
                case ChessPiece.rook: dirs = Self.straights
                default: dirs = Self.diagonals + Self.straights
                }
                for (df, dr) in dirs {
                    var nf = f + df, nr = r + dr
                    while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                        let to = nr * 8 + nf
                        let target = board[to]
                        if target == 0 {
                            if !capturesOnly { moves.append(ChessMove(from: sq, to: to)) }
                        } else {
                            if target * us < 0 { moves.append(ChessMove(from: sq, to: to, flags: ChessMove.capture)) }
                            break
                        }
                        nf += df
                        nr += dr
                    }
                }
            }
        }
        return moves
    }

    private func addCastling(from sq: Int, into moves: inout [ChessMove]) {
        if whiteToMove {
            guard sq == 4 else { return }
            if castling & 1 != 0 && board[5] == 0 && board[6] == 0 && board[7] == ChessPiece.rook
                && !isAttacked(4, byWhite: false) && !isAttacked(5, byWhite: false) && !isAttacked(6, byWhite: false) {
                moves.append(ChessMove(from: 4, to: 6, flags: ChessMove.castle))
            }
            if castling & 2 != 0 && board[3] == 0 && board[2] == 0 && board[1] == 0 && board[0] == ChessPiece.rook
                && !isAttacked(4, byWhite: false) && !isAttacked(3, byWhite: false) && !isAttacked(2, byWhite: false) {
                moves.append(ChessMove(from: 4, to: 2, flags: ChessMove.castle))
            }
        } else {
            guard sq == 60 else { return }
            if castling & 4 != 0 && board[61] == 0 && board[62] == 0 && board[63] == -ChessPiece.rook
                && !isAttacked(60, byWhite: true) && !isAttacked(61, byWhite: true) && !isAttacked(62, byWhite: true) {
                moves.append(ChessMove(from: 60, to: 62, flags: ChessMove.castle))
            }
            if castling & 8 != 0 && board[59] == 0 && board[58] == 0 && board[57] == 0 && board[56] == -ChessPiece.rook
                && !isAttacked(60, byWhite: true) && !isAttacked(59, byWhite: true) && !isAttacked(58, byWhite: true) {
                moves.append(ChessMove(from: 60, to: 58, flags: ChessMove.castle))
            }
        }
    }

    func making(_ m: ChessMove) -> ChessPosition {
        var n = self
        let piece = board[m.from]
        let white = whiteToMove
        let captured = board[m.to]
        n.board[m.to] = m.promotion != 0 ? (white ? m.promotion : -m.promotion) : piece
        n.board[m.from] = 0
        if m.isEnPassant {
            n.board[m.to + (white ? -8 : 8)] = 0
        }
        if m.isCastle {
            if m.to == m.from + 2 {
                n.board[m.from + 1] = n.board[m.from + 3]
                n.board[m.from + 3] = 0
            } else {
                n.board[m.from - 1] = n.board[m.from - 4]
                n.board[m.from - 4] = 0
            }
        }
        if abs(piece) == ChessPiece.king {
            n.castling &= white ? ~UInt8(3) : ~UInt8(12)
        }
        for sq in [m.from, m.to] {
            switch sq {
            case 0: n.castling &= ~UInt8(2)
            case 7: n.castling &= ~UInt8(1)
            case 56: n.castling &= ~UInt8(8)
            case 63: n.castling &= ~UInt8(4)
            default: break
            }
        }
        n.epSquare = m.flags & ChessMove.doublePush != 0 ? (m.from + m.to) / 2 : -1
        n.halfmove = (abs(piece) == ChessPiece.pawn || captured != 0 || m.isEnPassant) ? 0 : halfmove + 1
        if !white { n.fullmove += 1 }
        n.whiteToMove = !white
        return n
    }

    func legalMoves() -> [ChessMove] {
        pseudoMoves().filter { m in
            let n = making(m)
            return !n.inCheck(white: whiteToMove)
        }
    }

    func perft(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = legalMoves()
        if depth == 1 { return moves.count }
        var total = 0
        for m in moves { total += making(m).perft(depth - 1) }
        return total
    }

    /// Matériel insuffisant pour mater : roi seul, ou roi et une pièce mineure, de chaque côté.
    var insufficientMaterial: Bool {
        var minors: [(Int8, Int)] = []
        for sq in 0..<64 {
            let t = abs(board[sq])
            switch t {
            case 0, ChessPiece.king: continue
            case ChessPiece.knight, ChessPiece.bishop: minors.append((board[sq], sq))
            default: return false
            }
        }
        if minors.count <= 1 { return true }
        // Deux fous de même couleur de case, un de chaque camp.
        if minors.count == 2, minors.allSatisfy({ abs($0.0) == ChessPiece.bishop }), minors[0].0 != minors[1].0 {
            let c0 = (Self.file(minors[0].1) + Self.rank(minors[0].1)) % 2
            let c1 = (Self.file(minors[1].1) + Self.rank(minors[1].1)) % 2
            return c0 == c1
        }
        return false
    }

    /// Le camp a-t-il encore de quoi mater (pour la chute du drapeau) ?
    func hasMatingMaterial(white: Bool) -> Bool {
        var minors = 0
        for p in board where white ? p > 0 : p < 0 {
            switch abs(p) {
            case ChessPiece.pawn, ChessPiece.rook, ChessPiece.queen: return true
            case ChessPiece.knight, ChessPiece.bishop: minors += 1
            default: break
            }
        }
        return minors >= 2
    }

    // MARK: Notation

    /// Notation algébrique (« Cf3 », « exd5 », « O-O », « e8=D+ »), avec les lettres de pièces
    /// de la langue : [cavalier, fou, tour, dame, roi].
    func san(_ m: ChessMove, letters: [String]) -> String {
        let piece = abs(board[m.from])
        var s: String
        if m.isCastle {
            s = m.to > m.from ? "O-O" : "O-O-O"
        } else if piece == ChessPiece.pawn {
            s = m.isCapture ? String(Array("abcdefgh")[Self.file(m.from)]) + "x" : ""
            s += Self.squareName(m.to)
            if m.promotion != 0 { s += "=" + letters[Int(m.promotion) - 2] }
        } else {
            s = letters[Int(piece) - 2]
            let others = legalMoves().filter { $0.to == m.to && $0.from != m.from && abs(board[$0.from]) == piece }
            if !others.isEmpty {
                let sameFile = others.contains { Self.file($0.from) == Self.file(m.from) }
                let sameRank = others.contains { Self.rank($0.from) == Self.rank(m.from) }
                let name = Self.squareName(m.from)
                if !sameFile {
                    s += String(name.first!)
                } else if !sameRank {
                    s += String(name.last!)
                } else {
                    s += name
                }
            }
            if m.isCapture { s += "x" }
            s += Self.squareName(m.to)
        }
        let next = making(m)
        if next.sideInCheck {
            s += next.legalMoves().isEmpty ? "#" : "+"
        }
        return s
    }
}

// MARK: - Partie

enum ChessResult: Equatable {
    case checkmate(winnerWhite: Bool)
    case stalemate
    case fiftyMoves
    case repetition
    case insufficient
    case timeout(winnerWhite: Bool)
    case timeoutDraw
    case resignation(winnerWhite: Bool)
    case agreement

    var winnerWhite: Bool? {
        switch self {
        case .checkmate(let w), .timeout(let w), .resignation(let w): return w
        default: return nil
        }
    }
}

/// Une partie : la position de départ, les coups joués, les positions successives.
struct ChessGameRecord {
    private(set) var positions: [ChessPosition] = [ChessPosition.start]
    private(set) var moves: [ChessMove] = []
    private var keyCounts: [String: Int] = [ChessPosition.start.repetitionKey: 1]

    var position: ChessPosition { positions[positions.count - 1] }

    init() {}

    init(uciMoves: [String]) {
        for u in uciMoves {
            guard let m = position.legalMoves().first(where: { $0.uci == u }) else { break }
            play(m)
        }
    }

    mutating func play(_ m: ChessMove) {
        let next = position.making(m)
        moves.append(m)
        positions.append(next)
        keyCounts[next.repetitionKey, default: 0] += 1
    }

    /// Annule les `count` derniers coups.
    mutating func undo(_ count: Int = 1) {
        let keep = max(0, moves.count - count)
        self = ChessGameRecord(uciMoves: moves.prefix(keep).map(\.uci))
    }

    /// Résultat imposé par les règles (mat, pat, nulles automatiques), sinon nil.
    var ruleResult: ChessResult? {
        let p = position
        if p.legalMoves().isEmpty {
            return p.sideInCheck ? .checkmate(winnerWhite: !p.whiteToMove) : .stalemate
        }
        if p.insufficientMaterial { return .insufficient }
        if p.halfmove >= 100 { return .fiftyMoves }
        if keyCounts[p.repetitionKey, default: 0] >= 3 { return .repetition }
        return nil
    }
}

// MARK: - Ordinateur

enum ChessAI {
    static let values: [Int] = [0, 100, 320, 330, 500, 900, 0]

    /// Bonus de placement, du point de vue des Blancs (rangée 0 = première rangée blanche).
    static func placement(_ type: Int8, file: Int, rank: Int, endgame: Bool) -> Int {
        let cf = abs(Double(file) - 3.5), cr = abs(Double(rank) - 3.5)
        let center = max(cf, cr)               // 0,5 au centre … 3,5 au bord
        switch type {
        case ChessPiece.pawn:
            var v = rank * (endgame ? 12 : 6)
            if (file == 3 || file == 4) && (rank == 3 || rank == 4) { v += 18 }
            if (file == 3 || file == 4) && rank == 1 { v -= 10 }
            return v
        case ChessPiece.knight:
            return Int(30 - 12 * center)
        case ChessPiece.bishop:
            return Int(12 - 5 * center) + (rank == 0 ? -10 : 0)
        case ChessPiece.rook:
            return (rank == 6 ? 18 : 0) + ((file == 3 || file == 4) ? 6 : 0)
        case ChessPiece.queen:
            return Int(6 - 2 * center)
        default:
            if endgame { return Int(24 - 10 * center) }
            if rank == 0 && (file <= 2 || file >= 6) { return 22 }
            return -12 * rank - (file >= 3 && file <= 4 ? 8 : 0)
        }
    }

    /// Évaluation du point de vue du camp qui doit jouer.
    static func evaluate(_ p: ChessPosition) -> Int {
        var score = 0
        var heavy = 0
        for v in p.board where abs(v) == ChessPiece.queen || abs(v) == ChessPiece.rook { heavy += Int(abs(v)) }
        let endgame = heavy <= 9
        for sq in 0..<64 {
            let v = p.board[sq]
            guard v != 0 else { continue }
            let t = abs(v)
            let file = ChessPosition.file(sq)
            let rank = v > 0 ? ChessPosition.rank(sq) : 7 - ChessPosition.rank(sq)
            let s = values[Int(t)] + placement(t, file: file, rank: rank, endgame: endgame)
            score += v > 0 ? s : -s
        }
        return p.whiteToMove ? score : -score
    }

    static let mate = 100_000

    final class Search {
        let deadline: Date
        var nodes = 0
        var aborted = false
        let noise: Int

        init(deadline: Date, noise: Int) {
            self.deadline = deadline
            self.noise = noise
        }

        func ordered(_ moves: [ChessMove], _ p: ChessPosition, first: ChessMove? = nil) -> [ChessMove] {
            moves.sorted { a, b in
                if let first {
                    if a == first { return true }
                    if b == first { return false }
                }
                return score(a, p) > score(b, p)
            }
        }

        private func score(_ m: ChessMove, _ p: ChessPosition) -> Int {
            var s = 0
            if m.isCapture {
                let victim = m.isEnPassant ? 1 : Int(abs(p.board[m.to]))
                s += 10 * ChessAI.values[victim] - ChessAI.values[Int(abs(p.board[m.from]))] / 10 + 10_000
            }
            if m.promotion != 0 { s += 9_000 }
            return s
        }

        func quiesce(_ p: ChessPosition, _ alpha: Int, _ beta: Int, _ ply: Int) -> Int {
            nodes += 1
            var alpha = alpha
            let stand = ChessAI.evaluate(p)
            if stand >= beta { return stand }
            if stand > alpha { alpha = stand }
            if ply > 8 { return stand }
            for m in ordered(p.pseudoMoves(capturesOnly: true), p) {
                let n = p.making(m)
                if n.inCheck(white: p.whiteToMove) { continue }
                let v = -quiesce(n, -beta, -alpha, ply + 1)
                if v >= beta { return v }
                if v > alpha { alpha = v }
            }
            return alpha
        }

        func negamax(_ p: ChessPosition, depth: Int, _ alpha: Int, _ beta: Int, ply: Int) -> Int {
            nodes += 1
            if nodes & 1023 == 0 && Date() > deadline { aborted = true }
            if aborted { return 0 }
            if depth <= 0 { return quiesce(p, alpha, beta, 0) }
            var alpha = alpha
            var best = -ChessAI.mate
            var any = false
            for m in ordered(p.pseudoMoves(), p) {
                let n = p.making(m)
                if n.inCheck(white: p.whiteToMove) { continue }
                any = true
                let v = -negamax(n, depth: depth - 1, -beta, -alpha, ply: ply + 1)
                if aborted { return 0 }
                if v > best { best = v }
                if v > alpha { alpha = v }
                if alpha >= beta { break }
            }
            if !any { return p.sideInCheck ? -ChessAI.mate + ply : 0 }
            return best
        }

        func root(_ p: ChessPosition, depth: Int, moves: [ChessMove]) -> (ChessMove, Int)? {
            var alpha = -ChessAI.mate - 1
            var bestMove: ChessMove?
            for m in moves {
                let n = p.making(m)
                var v = -negamax(n, depth: depth - 1, -ChessAI.mate - 1, -alpha, ply: 1)
                if aborted { return nil }
                if noise > 0 { v += Int.random(in: -noise...noise) }
                if bestMove == nil || v > alpha {
                    alpha = v
                    bestMove = m
                }
            }
            guard let bestMove else { return nil }
            return (bestMove, alpha)
        }
    }

    /// Meilleur coup trouvé : approfondissement progressif jusqu'à `maxDepth`, dans le temps donné.
    static func bestMove(_ p: ChessPosition, maxDepth: Int, seconds: Double, noise: Int = 0) -> ChessMove? {
        let legal = p.legalMoves()
        guard !legal.isEmpty else { return nil }
        if legal.count == 1 { return legal[0] }
        let search = Search(deadline: Date().addingTimeInterval(seconds), noise: noise)
        var best: ChessMove = search.ordered(legal, p)[0]
        for depth in 1...max(1, maxDepth) {
            guard let (m, _) = search.root(p, depth: depth, moves: search.ordered(legal, p, first: best)) else { break }
            best = m
        }
        return best
    }
}
