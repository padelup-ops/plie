import Foundation

// Tests des moteurs d'échecs et de dames, compilés et lancés sur le Mac de compilation :
//   swiftc -O Plie/Games/Plateau/ChessEngine.swift Plie/Games/Plateau/DraughtsEngine.swift Tests/Engines/main.swift -o engine-tests
//   ./engine-tests                         → tests intégrés
//   ./engine-tests chess 2 < fens.txt      → perft pour chaque position (une par ligne)
//   ./engine-tests draughts 2 < fens.txt

var failures = 0

func check(_ ok: Bool, _ label: String) {
    print((ok ? "OK   " : "ÉCHEC ") + label)
    if !ok { failures += 1 }
}

let args = CommandLine.arguments
if args.count >= 3 {
    let depth = Int(args[2]) ?? 1
    while let line = readLine() {
        let fen = line.trimmingCharacters(in: .whitespaces)
        if fen.isEmpty { continue }
        if args[1] == "chess" {
            if let p = ChessPosition(fen: fen) { print(p.perft(depth)) } else { print("FEN?") }
        } else {
            if let p = DraughtsPosition(fen: fen) { print(p.perft(depth)) } else { print("FEN?") }
        }
    }
    exit(0)
}

let t0 = Date()

// MARK: Échecs — perft de référence
let chessCases: [(String, [Int])] = [
    (ChessPosition.startFEN, [20, 400, 8902, 197281]),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97862]),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43238]),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467]),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62379]),
    ("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", [46, 2079, 89890]),
]
for (fen, expected) in chessCases {
    guard let p = ChessPosition(fen: fen) else { check(false, "FEN illisible \(fen)"); continue }
    check(p.fen == fen, "FEN aller-retour \(fen)")
    for (i, e) in expected.enumerated() {
        let n = p.perft(i + 1)
        check(n == e, "perft \(i + 1) = \(n) (attendu \(e)) — \(fen)")
    }
}

// MARK: Échecs — notation, fins de partie, ordinateur
let fr = ["C", "F", "T", "D", "R"]
let start = ChessPosition.start
let e4 = start.legalMoves().first { $0.uci == "e2e4" }!
check(start.san(e4, letters: fr) == "e4", "notation e4")
let nf3 = start.legalMoves().first { $0.uci == "g1f3" }!
check(start.san(nf3, letters: fr) == "Cf3", "notation Cf3")

let fool = ChessGameRecord(uciMoves: ["f2f3", "e7e5", "g2g4", "d8h4"])
check(fool.moves.count == 4, "partie du berger inversée : 4 coups joués")
check(fool.ruleResult == .checkmate(winnerWhite: false), "mat du lion : les Noirs gagnent")
let last = ChessGameRecord(uciMoves: ["f2f3", "e7e5", "g2g4"]).position
let qh4 = last.legalMoves().first { $0.uci == "d8h4" }!
check(last.san(qh4, letters: fr) == "Dh4#", "notation Dh4#")

let pat = ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
check(pat.legalMoves().isEmpty && !pat.sideInCheck, "pat détecté")
check(ChessPosition(fen: "8/8/4k3/8/8/2K5/5B2/8 w - - 0 1")!.insufficientMaterial, "roi et fou contre roi : nulle")
check(!ChessPosition(fen: "8/8/4k3/8/8/2K5/5R2/8 w - - 0 1")!.insufficientMaterial, "roi et tour contre roi : pas nulle")

var repeated = ChessGameRecord(uciMoves: ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"])
check(repeated.ruleResult == .repetition, "triple répétition")
repeated.undo(2)
check(repeated.moves.count == 6 && repeated.ruleResult == nil, "annuler deux coups")

let promo = ChessPosition(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1")!
check(promo.legalMoves().filter { $0.from == 48 }.count == 4, "promotion : 4 choix")
let castle = ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
check(castle.legalMoves().filter(\.isCastle).count == 2, "deux roques possibles")
let afterCastle = castle.making(castle.legalMoves().first { $0.uci == "e1g1" }!)
check(afterCastle.board[5] == ChessPiece.rook && afterCastle.board[6] == ChessPiece.king && afterCastle.castling == 12, "petit roque : tour en f1")
let ep = ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")!
let epMove = ep.legalMoves().first { $0.isEnPassant }
check(epMove != nil && ep.making(epMove!).board[35] == 0, "prise en passant")

let mateIn1 = ChessPosition(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")!
check(ChessAI.bestMove(mateIn1, maxDepth: 2, seconds: 5)?.uci == "d1d8", "l'ordinateur voit le mat en un")
let freeQueen = ChessPosition(fen: "4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1")!
check(ChessAI.bestMove(freeQueen, maxDepth: 2, seconds: 5)?.uci == "d2d5", "l'ordinateur prend la dame offerte")
let t1 = Date()
let deep = ChessAI.bestMove(ChessPosition.start, maxDepth: 4, seconds: 1.5)
check(deep != nil && Date().timeIntervalSince(t1) < 3, "l'ordinateur répond en moins de 3 s (\(String(format: "%.2f", Date().timeIntervalSince(t1))) s)")

// MARK: Dames
let d0 = DraughtsPosition.start
check(d0.fen == "W:W31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50:B1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20", "dames : position de départ")
check(DraughtsPosition(fen: "W:W31-50:B1-20") == d0, "dames : FEN avec intervalles")
for n in 1...50 { if DraughtsPosition.number(of: DraughtsPosition.cell(ofNumber: n)) != n { check(false, "numérotation \(n)") } }
for (i, e) in [9, 81, 658, 4265, 27117].enumerated() {
    let n = d0.perft(i + 1)
    check(n == e, "dames perft \(i + 1) = \(n) (attendu \(e))")
}
let wold = DraughtsPosition(fen: "W:W25,27,28,30,32,33,34,35,37,38:B12,13,14,16,18,19,21,23,24,26")!
for (i, e) in [6, 12, 30, 73, 215, 590, 1944].enumerated() {
    let n = wold.perft(i + 1)
    check(n == e, "dames Woldouby perft \(i + 1) = \(n) (attendu \(e))")
}
let majority = DraughtsPosition(fen: "W:W32:B19,27,28")!.legalMoves()
check(majority.map(\.notation) == ["32x23x14"], "prise majoritaire : \(majority.map(\.notation))")
let flying = DraughtsPosition(fen: "W:WK46:B28")!.legalMoves()
check(flying.count == 5 && flying.allSatisfy { $0.captures.count == 1 }, "dame volante : 5 cases d'arrivée (\(flying.map(\.notation)))")
let backward = DraughtsPosition(fen: "W:W23:B28")!.legalMoves()
check(backward.map(\.notation) == ["23x32"], "le pion prend en arrière : \(backward.map(\.notation))")
let crown = DraughtsPosition(fen: "W:W6:B40")!
let up = crown.legalMoves().first { DraughtsPosition.number(of: $0.to) == 1 }!
check(abs(crown.making(up).board[up.to]) == 2, "promotion en dame")
// Le pion qui passe par la dernière rangée pendant une rafle et repart en arrière reste un pion.
let through = DraughtsPosition(fen: "W:W12:B8,9")!
let via = through.legalMoves()
check(via.count == 1 && !through.promotes(via[0]), "pas de promotion en passant par la dernière rangée (\(via.map(\.notation)))")
check(DraughtsAI.bestMove(d0, maxDepth: 6, seconds: 1.5) != nil, "l'ordinateur des dames joue")

print(String(format: "Durée : %.1f s", Date().timeIntervalSince(t0)))
print(failures == 0 ? "TOUT EST BON" : "\(failures) ÉCHEC(S)")
exit(failures == 0 ? 0 : 1)
