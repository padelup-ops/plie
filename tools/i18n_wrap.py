"""Entoure les textes visibles par l'utilisateur de L(...) et liste les clés à traduire.

Usage :
  python3 i18n_wrap.py scan   -> affiche les textes qui seraient traduits
  python3 i18n_wrap.py apply  -> modifie les fichiers Swift et écrit i18n_keys.json

Clé = le texte du littéral tel qu'écrit dans le code, chaque \\(...) remplacé par {}.
"""
import glob
import json
import re
import sys

ROOT = "../Plie"
SKIP_FILES = ("RayonLevels.swift", "PliageLevels.swift", "BasculeLevels.swift", "Localization.swift", "EnglishStrings.swift")

EXCLUDE_BEFORE = re.compile(
    r"(systemName:\s*|forKey:\s*|forResource:\s*|withExtension:\s*|NSLog\(\s*|language:\s*|case\s+|"
    r"named:\s*|identifier:\s*|Keys\.\w+\s*=\s*|static let \w+ = |format:\s*|L\(\s*|verbatim:\s*|"
    r"appendingPathComponent\(\s*|UserDefaults[^\n]*\(\s*|contentType:\s*)$")


def scan_literal(src, i):
    """src[i] == '"'. Renvoie (fin exclusive, segments) ; segments = liste de ('lit', texte) / ('interp', (début, fin))."""
    assert src[i] == '"'
    if src.startswith('"""', i):
        end = src.index('"""', i + 3) + 3
        return end, None
    j = i + 1
    segs = []
    buf_start = j
    while True:
        c = src[j]
        if c == "\\" and src[j + 1] == "(":
            segs.append(("lit", src[buf_start:j]))
            k = j + 2
            depth = 1
            while depth:
                ch = src[k]
                if ch == '"':
                    k, _ = scan_literal(src, k)
                    continue
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                k += 1
            segs.append(("interp", (j + 2, k - 1)))
            j = k
            buf_start = j
            continue
        if c == "\\":
            j += 2
            continue
        if c == '"':
            segs.append(("lit", src[buf_start:j]))
            return j + 1, segs
        if c == "\n":
            raise ValueError("chaîne sur plusieurs lignes")
        j += 1


def key_of(segs):
    return "".join(s if kind == "lit" else "{}" for kind, s in segs)


def visible_text(segs):
    return "".join(s for kind, s in segs if kind == "lit")


def should_wrap(segs, before):
    text = re.sub(r"\\.", "", visible_text(segs))
    if not re.search(r"[A-Za-zÀ-ÿœŒ]", text):
        return False
    if "%" in text or "PLIE-CHECK" in text:
        return False
    if EXCLUDE_BEFORE.search(before):
        return False
    if re.fullmatch(r"[a-z0-9._\-:/]+", text):
        return False
    if re.fullmatch(r"[a-z][A-Za-z0-9]*", text):  # identifiants camelCase
        return False
    if text in ("", "s", "x"):
        return False
    return True


def process(src, start=0, end=None, out=None, keys=None, in_interp=False):
    """Copie src[start:end] dans out en entourant les littéraux visibles."""
    if end is None:
        end = len(src)
    i = start
    while i < end:
        c = src[i]
        # commentaires
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = end if j < 0 else j
            out.append(src[i:j])
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i) + 2
            out.append(src[i:j])
            i = j
            continue
        if c == '"':
            lit_end, segs = scan_literal(src, i)
            if segs is None:
                out.append(src[i:lit_end])
                i = lit_end
                continue
            before = src[max(0, i - 60):i]
            # reconstruit le littéral en traitant les interpolations récursivement
            pieces = ['"']
            for kind, s in segs:
                if kind == "lit":
                    pieces.append(s)
                else:
                    a, b = s
                    sub = []
                    process(src, a, b, sub, keys, True)
                    pieces.append("\\(" + "".join(sub) + ")")
            pieces.append('"')
            literal = "".join(pieces)
            if should_wrap(segs, before):
                keys.add(key_of(segs))
                out.append("L(" + literal + ")")
            else:
                out.append(literal)
            i = lit_end
            continue
        out.append(c)
        i += 1
    return out


def main(mode):
    keys = set()
    files = [f for f in sorted(glob.glob(ROOT + "/**/*.swift", recursive=True)) if not f.endswith(SKIP_FILES)]
    for f in files:
        src = open(f).read()
        out = []
        file_keys = set()
        process(src, 0, None, out, file_keys)
        keys |= file_keys
        new = "".join(out)
        if mode == "scan":
            for k in sorted(file_keys):
                print(f"{f.split('/Plie/')[-1]}: {k}")
        elif mode == "apply" and new != src:
            open(f, "w").write(new)
    if mode == "apply":
        json.dump(sorted(keys), open("i18n_keys.json", "w"), ensure_ascii=False, indent=1)
    print(len(keys), "textes", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "scan")
