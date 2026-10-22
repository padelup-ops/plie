"""Compare les moteurs Swift (binaire engine-tests) avec python-chess et pydraughts sur des positions au hasard.

Usage (sur le Mac de compilation) : python3 tools/engine_crosscheck.py ./engine-tests
"""
import random
import subprocess
import sys

binary = sys.argv[1]
random.seed(20261023)
failures = 0


def swift_perft(game, depth, fens):
    out = subprocess.run([binary, game, str(depth)], input="\n".join(fens) + "\n", capture_output=True, text=True, timeout=1800)
    return out.stdout.split()


# ---------------------------------------------------------------- échecs
try:
    import chess

    def perft(board, depth):
        if depth == 0:
            return 1
        if depth == 1:
            return board.legal_moves.count()
        total = 0
        for m in board.legal_moves:
            board.push(m)
            total += perft(board, depth - 1)
            board.pop()
        return total

    fens = []
    for _ in range(400):
        b = chess.Board()
        for _ in range(random.randint(0, 120)):
            moves = list(b.legal_moves)
            if not moves:
                break
            # Un peu plus de prises et de promotions que le hasard pur, pour couvrir les cas rares.
            captures = [m for m in moves if b.is_capture(m) or m.promotion]
            b.push(random.choice(captures if captures and random.random() < 0.4 else moves))
        if not b.is_game_over():
            fens.append(b.fen())
    expected = [str(perft(chess.Board(f), 2)) for f in fens]
    got = swift_perft("chess", 2, fens)
    bad = [(f, e, g) for f, e, g in zip(fens, expected, got) if e != g]
    print(f"échecs : {len(fens)} positions au hasard, {len(bad)} écart(s) de perft 2")
    for f, e, g in bad[:10]:
        print(f"  ÉCART {f} : python-chess {e}, Swift {g}")
    failures += len(bad) + (0 if len(got) == len(fens) else 1)
except ImportError:
    print("python-chess indisponible : vérification croisée des échecs sautée")

# ---------------------------------------------------------------- dames (informatif)
try:
    from draughts import Board

    def legal(board):
        return board.legal_moves() if callable(board.legal_moves) else board.legal_moves

    def key(m):
        caps = getattr(m, "captures", None)
        steps = getattr(m, "steps_move", None) or getattr(m, "board_move", None)
        if steps and len(steps) >= 2:
            return (steps[0], steps[-1], tuple(sorted(caps or [])))
        return str(getattr(m, "pdn_move", m))

    fens, counts = [], []
    for _ in range(200):
        b = Board(variant="standard")
        for _ in range(random.randint(0, 70)):
            moves = legal(b)
            if not moves:
                break
            b.push(random.choice(moves))
        moves = legal(b)
        if moves:
            fens.append(b.fen)
            counts.append(str(len({key(m) for m in moves})))
    got = swift_perft("draughts", 1, fens)
    bad = [(f, e, g) for f, e, g in zip(fens, counts, got) if e != g]
    print(f"dames : {len(fens)} positions au hasard, {len(bad)} écart(s) du nombre de coups (informatif)")
    for f, e, g in bad[:10]:
        print(f"  ÉCART {f} : pydraughts {e}, Swift {g}")
except Exception as error:  # l'API de pydraughts varie selon les versions
    print(f"pydraughts indisponible ou incompatible : {error!r}")

sys.exit(1 if failures else 0)
