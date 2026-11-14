"""Construit le modèle de langue de Foldboard (français, anglais) à partir des corpus de Leipzig (CC BY 4.0).

Sortie : foldboard/Shared/lm-<lang>.bin, lu par KBLanguageModel (Shared/LanguageModel.swift), en mémoire projetée.

Format (petit-boutiste) :
  "FBLM" · u32 version=1 · u32 V · u32 nBi · u32 nCtx · u32 nTri
  vocabulaire : V × (u8 longueur, octets UTF-8)         (id 0 = "<s>", début de phrase)
  unigrammes  : V × u8                                   (score = -ln p × 12, plafonné à 255)
  bigrammes   : (V+1) × u32 décalages · nBi × u16 id · nBi × u8 score   (p(w | w1))
  trigrammes  : nCtx × u32 clé (w1<<16 | w2), triée · (nCtx+1) × u32 décalages · nTri × u16 id · nTri × u8 score
"""
import collections, io, math, os, re, struct, sys, tarfile, urllib.request

LANG = sys.argv[1]            # fr | en
CODE = {"fr": "fra", "en": "eng"}[LANG]
OUT = sys.argv[2]
V_MAX = 60000
SCALE = 12.0

# Les corpus à essayer (le premier qui répond, par genre) : du web (proche de ce qu'on écrit), puis de l'actualité.
def candidates():
    for kind in ("web", "news", "mixed", "wikipedia"):
        for year in range(2024, 2010, -1):
            for size in ("1M", "300K"):
                yield kind, f"https://downloads.wortschatz-leipzig.de/corpora/{CODE}_{kind}_{year}_{size}.tar.gz"


def sentences():
    got = set()
    for kind, url in candidates():
        if kind in got:
            continue
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "foldboard-lm"}), timeout=120).read()
        except Exception:
            continue
        print("corpus", url, len(data) // 1_000_000, "Mo", flush=True)
        got.add(kind)
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            for m in t.getmembers():
                if m.name.endswith("-sentences.txt"):
                    for line in t.extractfile(m):
                        parts = line.decode("utf-8", "ignore").rstrip("\n").split("\t", 1)
                        if len(parts) == 2:
                            yield parts[1]
        if len(got) >= 2:
            break
    if not got:
        sys.exit("aucun corpus trouvé")


if LANG == "fr":
    # « l’homme » → « l’ » « homme » : l'élision est un mot à part (le clavier coupe le mot en cours après ’).
    TOKEN = re.compile(r"[^\W\d_]+(?:-[^\W\d_]+)*’?")
else:
    # « don’t », « I’m » : un seul mot.
    TOKEN = re.compile(r"[^\W\d_]+(?:’[^\W\d_]+)*")
SPLIT = re.compile(r"[.!?…]+")


def tokens(sentence):
    s = sentence.replace("'", "’").lower()
    for part in SPLIT.split(s):
        toks = TOKEN.findall(part)
        if toks:
            yield toks


# Phrases de la vie courante (Tatoeba, CC BY 2.0 FR) : des messages, pas de l'actualité. Comptées TATOEBA_WEIGHT fois.
def tatoeba():
    import bz2
    url = f"https://downloads.tatoeba.org/exports/per_language/{CODE}/{CODE}_sentences.tsv.bz2"
    try:
        data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "foldboard-lm"}), timeout=180).read()
    except Exception as e:
        print("tatoeba indisponible", e, flush=True)
        return
    print("tatoeba", url, len(data) // 1_000_000, "Mo", flush=True)
    for line in bz2.decompress(data).decode("utf-8", "ignore").splitlines():
        parts = line.split("\t")
        if len(parts) >= 3:
            yield parts[2]

TW = int(os.environ.get("TATOEBA_WEIGHT", "0"))
uni = collections.Counter()
sents = []
for i, sent in enumerate(sentences()):
    for toks in tokens(sent):
        uni.update(toks)
        sents.append(toks)
if TW > 0:
    n0 = len(sents)
    for sent in tatoeba():
        for toks in tokens(sent):
            for _ in range(TW):
                uni.update(toks)
                sents.append(toks)
    print("tatoeba phrases ajoutées", (len(sents) - n0) // TW, "× poids", TW, flush=True)
print("phrases", len(sents), "mots distincts", len(uni), flush=True)

vocab = ["<s>"] + [w for w, c in uni.most_common(V_MAX - 1) if len(w.encode()) < 64]
ids = {w: i for i, w in enumerate(vocab)}
V = len(vocab)
total = sum(uni[w] for w in vocab[1:]) + len(sents)
uni_counts = [len(sents)] + [uni[w] for w in vocab[1:]]

bi = collections.Counter()
tri = collections.Counter()
for toks in sents:
    seq = [0] + [ids.get(t, -1) for t in toks]
    for a, b in zip(seq, seq[1:]):
        if a >= 0 and b > 0:
            bi[(a << 16) | b] += 1
    for a, b, c in zip(seq, seq[1:], seq[2:]):
        if a >= 0 and b > 0 and c > 0:
            tri[(a << 32) | (b << 16) | c] += 1
del sents
print("bigrammes", len(bi), "trigrammes", len(tri), flush=True)


def q(p):
    return max(0, min(255, int(round(-math.log(max(p, 1e-12)) * SCALE))))


# Bigrammes : les 16 suites les plus fréquentes de chaque mot (vues au moins 2 fois).
ctx1 = collections.Counter()
for k, c in bi.items():
    ctx1[k >> 16] += c
bylist = collections.defaultdict(list)
for k, c in bi.items():
    if c >= 2:
        bylist[k >> 16].append((c, k & 0xFFFF))
bi_off, bi_id, bi_sc = [0], [], []
for w in range(V):
    lst = sorted(bylist.get(w, []), reverse=True)[:16]
    for c, nxt in lst:
        bi_id.append(nxt)
        bi_sc.append(q(c / ctx1[w]))
    bi_off.append(len(bi_id))
del bylist

# Trigrammes : les 300 000 paires de mots les plus fréquentes, leurs 8 meilleures suites (vues au moins 2 fois).
ctx2 = collections.Counter()
for k, c in tri.items():
    ctx2[k >> 16] += c
keep = {k for k, c in ctx2.most_common(300000) if c >= 3}
bylist = collections.defaultdict(list)
for k, c in tri.items():
    if c >= 2 and (k >> 16) in keep:
        bylist[k >> 16].append((c, k & 0xFFFF))
del tri
keys = sorted(bylist)
tri_key, tri_off, tri_id, tri_sc = [], [0], [], []
for k in keys:
    lst = sorted(bylist[k], reverse=True)[:8]
    tri_key.append(k)
    for c, nxt in lst:
        tri_id.append(nxt)
        tri_sc.append(q(c / ctx2[k]))
    tri_off.append(len(tri_id))

with open(OUT, "wb") as f:
    f.write(b"FBLM")
    f.write(struct.pack("<5I", 1, V, len(bi_id), len(tri_key), len(tri_id)))
    for w in vocab:
        b = w.encode()
        f.write(struct.pack("<B", len(b)) + b)
    f.write(bytes(q(c / total) for c in uni_counts))
    f.write(struct.pack(f"<{V + 1}I", *bi_off))
    f.write(struct.pack(f"<{len(bi_id)}H", *bi_id))
    f.write(bytes(bi_sc))
    f.write(struct.pack(f"<{len(tri_key)}I", *tri_key))
    f.write(struct.pack(f"<{len(tri_off)}I", *tri_off))
    f.write(struct.pack(f"<{len(tri_id)}H", *tri_id))
    f.write(bytes(tri_sc))
print("écrit", OUT, os.path.getsize(OUT) // 1000, "Ko", "· V", V, "· bigrammes", len(bi_id), "· contextes", len(tri_key), "· trigrammes", len(tri_id))
