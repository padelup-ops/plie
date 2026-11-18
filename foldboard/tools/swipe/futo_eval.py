"""Mesure le décodage du glisser avec les modèles FUTO Swipe (licence FUTO Model Weights 1.0) sur de vrais swipes.

Les modèles transforment le tracé en probabilités de touches (CTC, 32 pas, une classe par touche + « vide ») ;
on cherche ensuite les mots de NOTRE liste (words-en.txt / words-fr.txt) avec une recherche en faisceau guidée
par un arbre des mots, plus un petit bonus pour les mots fréquents. Même mesure que le banc d'essai du clavier
(top 1, top 4, mots de la liste) pour comparer avec le moteur actuel.

python3 futo_eval.py MODEL.pte SWIPES.jsonl LAYOUT.json WORDS.txt [limite]
"""
import json, math, sys, time, unicodedata
import numpy as np


def fold(s):
    s = s.lower().replace("œ", "oe").replace("æ", "ae").replace("’", "'")
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def resample(points, n=64):
    """Comme l'exemple de FUTO : d'abord sur une horloge régulière à 60 Hz (si on a les temps), puis 64 points."""
    p = np.array([[q[0], q[1]] for q in points], dtype=np.float64)
    t = np.array([q[2] if len(q) > 2 else i for i, q in enumerate(points)], dtype=np.float64)
    if len(p) == 1:
        return np.repeat(p, n, axis=0)
    if t[-1] > t[0]:
        # temps strictement croissants
        t = np.maximum.accumulate(t)
        keep = np.concatenate([[True], np.diff(t) > 0])
        p, t = p[keep], t[keep]
        if len(p) >= 2:
            grid = np.arange(t[0], t[-1] + 1e-9, 1000.0 / 60.0)
            if len(grid) >= 2:
                p = np.stack([np.interp(grid, t, p[:, 0]), np.interp(grid, t, p[:, 1])], 1)
    s = np.linspace(0, len(p) - 1, n)
    i0 = np.floor(s).astype(int)
    i1 = np.minimum(i0 + 1, len(p) - 1)
    f = (s - i0)[:, None]
    return p[i0] * (1 - f) + p[i1] * f


class Trie:
    __slots__ = ("kids", "words")

    def __init__(self):
        self.kids = {}
        self.words = []


def build_trie(words, key_of):
    root = Trie()
    for rank, w in enumerate(words):
        f = fold(w)
        seq = []
        for c in f:
            k = key_of.get(c)
            if k is None:
                seq = None
                break
            if not seq or seq[-1] != k:   # les lettres doublées ne se voient pas dans un tracé
                seq.append(k)
        if not seq:
            continue
        node = root
        for k in seq:
            node = node.kids.setdefault(k, Trie())
        node.words.append(rank)
    return root


def logsumexp(a, b):
    if a == -math.inf:
        return b
    if b == -math.inf:
        return a
    m = max(a, b)
    return m + math.log(math.exp(a - m) + math.exp(b - m))


def beam_search(logp, root, blank, beam=64, prune=-9.0):
    """Recherche en faisceau CTC limitée aux préfixes de mots (arbre). logp : [T, classes] en log-probabilités."""
    # faisceau : noeud -> (p_vide, p_non_vide, dernière touche)
    beams = {id(root): (root, 0.0, -math.inf, None)}
    for t in range(logp.shape[0]):
        row = logp[t]
        cand_keys = [int(k) for k in np.nonzero(row > prune)[0] if k != blank]
        nb = {}

        def add(node, pb, pnb, last):
            key = id(node)
            if key in nb:
                o = nb[key]
                nb[key] = (node, logsumexp(o[1], pb), logsumexp(o[2], pnb), last)
            else:
                nb[key] = (node, pb, pnb, last)

        for node, pb, pnb, last in beams.values():
            tot = logsumexp(pb, pnb)
            # vide : on reste sur le même préfixe
            add(node, tot + row[blank], -math.inf, last)
            # même touche répétée sans vide : on reste aussi
            if last is not None:
                add(node, -math.inf, pnb + row[last], last)
            for k in cand_keys:
                child = node.kids.get(k)
                if child is None:
                    continue
                if k == last:
                    # une nouvelle occurrence de la même touche demande un vide entre les deux
                    add(child, -math.inf, pb + row[k], k)
                else:
                    add(child, -math.inf, tot + row[k], k)
        beams = dict(sorted(nb.items(), key=lambda kv: -logsumexp(kv[1][1], kv[1][2]))[:beam])
    out = []
    for node, pb, pnb, last in beams.values():
        if node.words:
            out.append((logsumexp(pb, pnb), node.words))
    return out


def main():
    model_path, swipes_path, layout_path, words_path = sys.argv[1:5]
    limit = int(sys.argv[5]) if len(sys.argv) > 5 else 2000
    from executorch.runtime import Runtime
    import torch

    rt = Runtime.get()
    prog = rt.load_program(model_path)
    meth = prog.load_method("forward")

    layout = json.load(open(layout_path))
    keys = [k for k in layout["keys"]]
    key_of = {fold(k["letter"]): i for i, k in enumerate(keys)}
    kx = np.zeros((1, 64, 2), dtype=np.float32)
    mask = np.zeros((1, 64), dtype=bool)
    for i, k in enumerate(keys):
        kx[0, i] = [k["cx"], k["cy"]]
        mask[0, i] = True
    words = [w for w in open(words_path, encoding="utf-8").read().split("\n") if w]
    folded_set = set(fold(w) for w in words)
    root = build_trie(words, key_of)
    blank = 64

    results = {lam: [0, 0, 0, 0, 0] for lam in (0.0, 0.15, 0.3, 0.5)}   # n, top1, top4, connus, connus_top1
    n_in = 0
    misses = []
    t0 = time.time()
    n = 0
    for line in open(swipes_path, encoding="utf-8"):
        if n >= limit:
            break
        d = json.loads(line)
        target = fold(d["w"].strip(".,;:!?\"()«»"))
        if len(target) < 2 or not all(c.isalpha() for c in target):
            continue
        pts = d["p"]
        if len(pts) < 2:
            continue
        feat = resample(pts).T[None].astype(np.float32)     # [1, 2, 64]
        out = meth.execute([torch.from_numpy(feat), torch.from_numpy(kx), torch.from_numpy(mask)])
        logp = out[0][0].detach().numpy().astype(np.float64)   # [32, 65]
        hyps = beam_search(logp, root, blank)
        n += 1
        inside = target in folded_set
        n_in += inside
        for lam, r in results.items():
            scored = []
            for s, ranks in hyps:
                best = min(ranks)
                scored.append((s - lam * math.log(best + 30), best))
            scored.sort(key=lambda x: -x[0])
            top = []
            for _, rk in scored:
                f = fold(words[rk])
                if f not in top:
                    top.append(f)
                if len(top) == 4:
                    break
            r[0] += 1
            r[1] += top[:1] == [target]
            r[2] += target in top
            r[3] += inside
            r[4] += inside and top[:1] == [target]
            if lam == 0.3 and inside and top[:1] != [target] and len(misses) < 25:
                misses.append(f"{target}→{top[0] if top else '-'}")
    dt = time.time() - t0
    for lam, (cnt, t1, t4, ins, in1) in results.items():
        print(f"RESULT futo λ={lam} top1 {100 * t1 / max(1, cnt):.1f} % top4 {100 * t4 / max(1, cnt):.1f} % "
              f"connus_top1 {100 * in1 / max(1, ins):.1f} % (sur {cnt}, {ins} connus)")
    print("ratés:", ", ".join(misses))
    print(f"durée {dt:.1f} s, {1000 * dt / max(1, n):.1f} ms par swipe")


if __name__ == "__main__":
    main()
