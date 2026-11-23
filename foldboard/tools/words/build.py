#!/usr/bin/env python3
"""Foldboard : les listes de mots (words-fr.txt, words-en.txt) agrandies à N mots, et les listes de vraies fautes
pour le banc d'essai.

Mots : FrequencyWords 2018 (Hermit Dave, CC BY-SA 4.0). Les 30 000 premiers restent ceux d'avant (même ordre :
le classement des corrections ne bouge pas) ; on ajoute ensuite les mots suivants de la liste complète, dans
l'ordre de fréquence, en lettres seulement, vus au moins MIN fois, sans les grossièretés.

Fautes (banc d'essai seulement, rien n'est livré dans l'app) :
- anglais : la liste « Lists of common misspellings/For machines » de Wikipédia (CC BY-SA) et le dictionnaire de
  codespell (CC BY-SA 3.0) : « faute->mot » ;
- français : la liste des fautes courantes de Wikipédia en français, et les accents oubliés (chaque mot accentué
  courant tapé sans ses accents, quand la forme sans accents n'existe pas).
Usage : build.py <dossier de sortie> <fr_full.txt> <en_full.txt> <N> [wiki-en.txt] [codespell.txt] [wiki-fr.txt]
"""
import re, sys, unicodedata

out, frfull, enfull, N = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
extra = sys.argv[5:]
MIN = 3
BLOCK = set("""nigger nigga faggot fag retard retarded tranny chink spic kike wetback cunt
nègre negre bougnoule youpin pédé pede tarlouze enculé encule salope pute bite chatte connasse""".split())
LETTERS = re.compile(r"^[a-zàâäçéèêëîïôöùûüÿœæñáíóú'’-]+$")

def strip(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

def grow(code, full):
    base = [l.strip() for l in open(f"Shared/words-{code}.txt", encoding="utf-8") if l.strip()]
    have = set(base)
    words = list(base)
    for line in open(full, encoding="utf-8"):
        parts = line.split()
        if len(parts) != 2: continue
        w, n = parts[0], int(parts[1])
        if n < MIN: break
        if w in have or w in BLOCK or len(w) < 2 or len(w) > 24: continue
        if not LETTERS.match(w) or w.startswith(("'", "’", "-")) or w.endswith(("'", "’", "-")): continue
        words.append(w); have.add(w)
        if len(words) >= N: break
    with open(f"{out}/words-{code}.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(words) + "\n")
    print(code, len(base), "→", len(words))
    return words

fr = grow("fr", frfull)
en = grow("en", enfull)
frset, enset = set(fr), set(en)

def pairs_from_arrow(path, vocab, limit=60000):
    res = []
    for line in open(path, encoding="utf-8", errors="ignore"):
        m = re.match(r"^\s*([A-Za-z'’]+)\s*->\s*([A-Za-z'’ ]+?)\s*(?:,.*)?$", line.strip())
        if not m: continue
        wrong, right = m.group(1).lower(), m.group(2).strip().lower()
        if " " in right or wrong == right: continue
        if right in vocab and wrong not in vocab:
            res.append((wrong, right))
    return res

typos_en, typos_fr = [], []
for p in extra:
    name = p.split("/")[-1]
    if name.startswith(("wiki-en", "codespell")):
        typos_en += pairs_from_arrow(p, enset)
    elif name.startswith("wiki-fr"):
        txt = open(p, encoding="utf-8", errors="ignore").read()
        # Lignes de la forme « * faute → correct » ou « faute : correct » (formats variés selon les sections).
        for m in re.finditer(r"^\*+\s*(?:\[\[)?([^\]\n:→>|]+?)(?:\]\])?\s*(?:→|->|:)\s*(?:\[\[)?([^\]\n,;(|]+?)(?:\]\])?\s*$", txt, re.M):
            wrong, right = m.group(1).strip().lower(), m.group(2).strip().lower()
            if " " in wrong or " " in right or wrong == right: continue
            if right in frset and wrong not in frset and LETTERS.match(wrong): typos_fr.append((wrong, right))

# Accents oubliés : « derniere » → « dernière » (les 20 000 mots les plus courants).
for w in fr[:20000]:
    s = strip(w)
    if s != w and s not in frset and len(w) >= 3:
        typos_fr.append((s, w))

def dedupe(ps):
    seen, outp = set(), []
    for a, b in ps:
        if a in seen: continue
        seen.add(a); outp.append((a, b))
    return outp

for code, ps in (("en", dedupe(typos_en)), ("fr", dedupe(typos_fr))):
    with open(f"{out}/typos-{code}.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(f"{a}->{b}" for a, b in ps) + "\n")
    print("typos", code, len(ps))
