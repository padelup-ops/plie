"""VICEFOLD : vérifie les traductions de l'interface (Shared/*.lproj/Localizable.strings).

Usage : python3 l10n.py            → liste ce qui manque (code de sortie 1 s'il manque une traduction)
        python3 l10n.py --candidates → liste aussi les textes du code Swift absents des traductions (à relire à la main)

1. Les cinq traductions (fr, es, de, it, pt-BR) doivent avoir exactement les mêmes clés.
2. Chaque texte passé à l'interface dans le code Swift (Text("…"), Label("…"), String(localized: "…"), titres, etc.)
   doit avoir sa clé : « \\(n) places » dans le code correspond à la clé « %lld places » ou « %@ places ».
L'anglais est la langue des clés : en.lproj ne sert qu'à déclarer la langue (une clé absente s'affiche telle quelle).
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LANGS = ["fr", "es", "de", "it", "pt-BR"]
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.M)
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f)")
# Les appels dont le premier texte est affiché (et donc traduit).
CALLS = (r"Text|Label|Button|Toggle|Picker|Section|Stepper|TextField|LabeledContent|Link|Menu|Tab|String\(localized:|"
         r"navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert|SectionTitle\(title:|"
         r"VFEmptyState\([^\n]*?title:|EmptyDetail\([^\n]*?text:|message:|action:|stub:|title:|text:|kicker:|prompt: Text|"
         r"configurationDisplayName|description|hint|stat|mini|caption|point|proPerk|linkRow\([^\n]*?title:")
LITERAL = r'"((?:[^"\\\n]|\\.)*)"'


def entries(lang):
    path = os.path.join(ROOT, "Shared", f"{lang}.lproj", "Localizable.strings")
    return dict(ENTRY.findall(open(path, encoding="utf-8").read()))


def shape(key):
    """La clé sans ses variables : « %lld places » et « \\(n) places » donnent la même forme."""
    k = SPEC.sub("\x00", key)
    return k.replace("%%", "%")


def swift_literals():
    out = {}
    files = glob.glob(os.path.join(ROOT, "App", "*.swift")) + glob.glob(os.path.join(ROOT, "Shared", "*.swift")) + \
        glob.glob(os.path.join(ROOT, "Widget", "*.swift"))
    for f in sorted(files):
        src = open(f, encoding="utf-8").read()
        for m in re.finditer(r"(?:" + CALLS + r")\s*\(?\s*" + LITERAL, src):
            lit = m.group(1)
            # \(…) → variable (les parenthèses imbriquées d'un niveau suffisent ici)
            lit = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "\x00", lit)
            lit = lit.replace('\\"', '"').replace("\\n", "\n")
            if not re.search(r"[A-Za-zÀ-ÿ]{2}", lit.replace("\x00", "")):
                continue
            out.setdefault(lit, os.path.basename(f))
    return out


def main():
    tables = {l: entries(l) for l in LANGS}
    bad = 0
    ref = set(tables["fr"])
    for l in LANGS[1:]:
        for k in sorted(ref - set(tables[l])):
            print(f"[{l}] clé absente : {k}")
            bad += 1
        for k in sorted(set(tables[l]) - ref):
            print(f"[fr] clé absente (présente en {l}) : {k}")
            bad += 1
    # Les variables d'une traduction doivent être celles de la clé.
    for l in LANGS:
        for k, v in tables[l].items():
            if sorted(SPEC.findall(k)) != sorted(s.replace("1$", "").replace("2$", "") for s in SPEC.findall(v)):
                print(f"[{l}] variables différentes : {k} → {v}")
                bad += 1
    shapes = {shape(k.replace('\\"', '"').replace("\\n", "\n")) for k in ref}
    missing = [(lit, f) for lit, f in swift_literals().items() if lit not in shapes]
    if "--candidates" in sys.argv:
        for lit, f in missing:
            print(f"[code] {f} : {lit.replace(chr(0), '%…')}")
    print(f"{len(ref)} clés, {bad} problème(s), {len(missing)} texte(s) du code sans clé (voir --candidates)")
    sys.exit(1 if bad else 0)


main()
