"""Génère Plie/Games/Plateau/ChessPieceArt.swift à partir des dessins de pieces.py."""
import re
from pieces import PIECES

ORDER = {"pawn": 1, "knight": 2, "bishop": 3, "rook": 4, "queen": 5, "king": 6}


def path_cmds(d):
    toks = re.findall(r"[MLCZ]|-?\d+(?:\.\d+)?", d)
    out, i, cmd = [], 0, None
    while i < len(toks):
        t = toks[i]
        if t in "MLCZ":
            cmd = t
            i += 1
            if cmd == "Z":
                out.append("p.closeSubpath()")
            continue
        if cmd == "M":
            out.append(f"p.move(to: pt({toks[i]}, {toks[i+1]}))"); i += 2; cmd = "L"
        elif cmd == "L":
            out.append(f"p.addLine(to: pt({toks[i]}, {toks[i+1]}))"); i += 2
        elif cmd == "C":
            a = toks[i:i+6]
            out.append(f"p.addCurve(to: pt({a[4]}, {a[5]}), control1: pt({a[0]}, {a[1]}), control2: pt({a[2]}, {a[3]}))"); i += 6
    return out


def shape_cmds(s):
    k = s[0]
    if k == "rr":
        _, x0, y0, x1, y1, r = s
        return [f"p.addRoundedRect(in: rect({x0}, {y0}, {x1}, {y1}), cornerSize: CGSize(width: {r} * k, height: {r} * k))"]
    if k == "c":
        _, cx, cy, r = s
        return [f"p.addEllipse(in: rect({cx - r}, {cy - r}, {cx + r}, {cy + r}))"]
    if k == "e":
        _, cx, cy, rx, ry = s
        return [f"p.addEllipse(in: rect({cx - rx}, {cy - ry}, {cx + rx}, {cy + ry}))"]
    return path_cmds(s[1])


def body(lines, indent="            "):
    return "\n".join(indent + l for l in lines)


cases_shape, cases_detail, cases_dots = [], [], []
for name, art in PIECES.items():
    n = ORDER[name]
    sl = []
    for s in art["shapes"]:
        sl += shape_cmds(s)
    cases_shape.append(f"        case {n}:\n{body(sl)}")
    dl, dots = [], []
    for d in art["details"]:
        if d[0] == "ln":
            dl += [f"p.move(to: pt({d[1]}, {d[2]}))", f"p.addLine(to: pt({d[3]}, {d[4]}))"]
        elif d[0] == "dp":
            dl += path_cmds(d[1])
        elif d[0] == "dc":
            dots.append(f"p.addEllipse(in: rect({d[1] - d[3]}, {d[2] - d[3]}, {d[1] + d[3]}, {d[2] + d[3]}))")
    if dl:
        cases_detail.append(f"        case {n}:\n{body(dl)}")
    if dots:
        cases_dots.append(f"        case {n}:\n{body(dots)}")

swift = f'''import SwiftUI

// Fichier généré par tools/chess_art.py : dessins des pièces d'échecs dans une boîte de 100 × 100.

private struct ArtSpace {{
    let r: CGRect
    var k: CGFloat {{ r.width / 100 }}
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ CGPoint(x: r.minX + x * k, y: r.minY + y * k) }}
    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {{
        CGRect(x: r.minX + x0 * k, y: r.minY + y0 * k, width: (x1 - x0) * k, height: (y1 - y0) * k)
    }}
}}

/// Silhouette d'une pièce (1 pion … 6 roi).
struct ChessPieceShape: Shape {{
    let type: Int8

    func path(in r: CGRect) -> Path {{
        let a = ArtSpace(r: r)
        let k = a.k
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ a.pt(x, y) }}
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {{ a.rect(x0, y0, x1, y1) }}
        _ = k
        var p = Path()
        switch type {{
{chr(10).join(cases_shape)}
        default:
            break
        }}
        return p
    }}
}}

/// Traits de détail (bandeaux, fente du fou, crinière).
struct ChessPieceDetail: Shape {{
    let type: Int8

    func path(in r: CGRect) -> Path {{
        let a = ArtSpace(r: r)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ a.pt(x, y) }}
        var p = Path()
        switch type {{
{chr(10).join(cases_detail)}
        default:
            break
        }}
        return p
    }}
}}

/// Petits points pleins (œil et naseau du cavalier).
struct ChessPieceDots: Shape {{
    let type: Int8

    func path(in r: CGRect) -> Path {{
        let a = ArtSpace(r: r)
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {{ a.rect(x0, y0, x1, y1) }}
        var p = Path()
        switch type {{
{chr(10).join(cases_dots)}
        default:
            break
        }}
        return p
    }}
}}
'''
open("/home/claude/plie/Plie/Games/Plateau/ChessPieceArt.swift", "w").write(swift)
print(swift[:1500])
