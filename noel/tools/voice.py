#!/usr/bin/env python3
# Allô Père Noël — la voix du Père Noël, enregistrée d'avance.
#
# Chaque réplique fixe des scénarios, chaque message du calendrier de l'Avent et, pour chaque prénom de la banque,
# « Ho, ho, ho ! Bonjour <prénom> ! » et « Joyeux Noël, <prénom> ! » : un fichier AAC par phrase, dans
# noel/Resources/Audio/voice/<langue>/<identifiant>.m4a. L'app retrouve le fichier en recalculant l'identifiant
# (SHA-256 de « langue|clé », voir VoiceLibrary dans App/Voice.swift) : pas d'index à tenir à jour.
#
# La voix : Chatterbox Multilingual (MIT), calée sur un Père Noël de dessin animé fabriqué avec Kokoro `am_santa`
# (Apache 2.0). Aucune voix de personne réelle. Chaque fichier est réécouté par un modèle de transcription
# (faster-whisper) : le texte entendu doit ressembler au texte voulu et la durée être plausible, sinon on recommence
# avec un autre tirage.
#
#   voice.py plan                       ce qu'il y a à dire, par langue
#   voice.py check                      ce qui manque dans Resources/Audio/voice
#   voice.py gen --lang fr --shard 0/6 --out out      (dans GitHub Actions : .github/workflows/noel-voice.yml)
#   voice.py pilot --lang fr --out out  quelques phrases avec plusieurs réglages, pour choisir

import argparse, difflib, hashlib, json, os, re, subprocess, sys, time, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "Resources" / "Scripts"
ADVENT = ROOT / "Resources" / "Advent" / "messages.json"
VOICE = ROOT / "Resources" / "Audio" / "voice"
NAMES = ROOT / "tools" / "names"
REF = ROOT / "ai" / "santa-voice-ref.wav"
LANGS = ["fr", "en", "es", "de", "it", "pt"]
QUALITIES = ["kind", "curious", "brave", "funny", "sporty", "dreamer", "creative", "caring", "adventurous"]
AGES = range(3, 11)

REF_TEXT = ("Ho, ho, ho! Merry Christmas! Oh, what a wonderful night it is here at the North Pole. "
            "The elves are singing, the reindeer are ready, and I have a big bag full of surprises. "
            "Now, tell me, have you been good this year? Ho, ho, ho!")

# Réglages retenus après l'essai (voice.py pilot) : entrain marqué ; hors anglais, cfg à 0 pour que la voix de
# référence (anglaise) ne donne pas son accent aux autres langues.
SETTINGS = {
    "en": dict(exaggeration=0.8, cfg_weight=0.3, temperature=0.75),
    "*": dict(exaggeration=0.8, cfg_weight=0.0, temperature=0.75),
}


def norm_name(s: str) -> str:
    """Le prénom tel que l'app le cherche : sans accents, en minuscules, espaces simples."""
    s = unicodedata.normalize("NFD", s.replace("_", " "))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", s.lower()).strip()


def clip_id(lang: str, key: str) -> str:
    return hashlib.sha256(f"{lang}|{key}".encode("utf-8")).hexdigest()[:20]


def names(lang: str):
    seen, out = set(), []
    for raw in (NAMES / f"{lang}.txt").read_text(encoding="utf-8").split():
        name = raw.replace("_", " ")
        k = norm_name(name)
        if k and k not in seen:
            seen.add(k)
            out.append(name)
    return out


def plan(lang: str):
    book = json.loads((SCRIPTS / f"{lang}.json").read_text(encoding="utf-8"))
    items, seen = [], set()

    def add(key, text, kind):
        if key in seen:
            return
        seen.add(key)
        items.append(dict(id=clip_id(lang, key), key=key, text=text, kind=kind))

    def line(text):
        add("line|" + text, text, "line")

    def expand(say):
        # Les mêmes combinaisons que l'app (ScriptBuilder) : la phrase et la qualité au singulier, puis au pluriel.
        for plural in (False, True):
            tpl = say[1] if plural and len(say) > 1 else say[0]
            texts = [tpl]
            if "{age}" in tpl:
                texts = [tpl.replace("{age}", str(a)) for a in AGES]
            for slot in ("{q1}", "{q2}"):
                if slot in tpl:
                    forms = [book["qualities"][q] for q in QUALITIES]
                    texts = [t.replace(slot, f[1] if plural and len(f) > 1 else f[0]) for t in texts for f in forms]
            for t in texts:
                assert "{" not in t, t
                line(t)

    for steps in list(book["scenarios"].values()) + list(book["blocks"].values()):
        for step in steps:
            if step.get("say"):
                expand(step["say"])
    for k in ("helloAnyone", "byeAnyone"):
        line(book[k])
    for t in book["helloAfterElf"]:
        line(t)
    for t in json.loads(ADVENT.read_text(encoding="utf-8"))[lang]:
        line(t)
    for name in names(lang):
        add("hello|" + norm_name(name), book["hello"].replace("{name}", name), "hello")
        add("bye|" + norm_name(name), book["bye"].replace("{name}", name), "bye")
    return items


def missing(lang: str):
    return [it for it in plan(lang) if not (VOICE / lang / f"{it['id']}.m4a").is_file()]


# ---------------------------------------------------------------------------------------------------------------
# Son

def letters(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = re.sub(r"[^a-z0-9ß ]+", " ", s)
    # Les rires (« ho, ho, ho », « jo, jo, jo », « oh, oh, oh ») s'écrivent de dix façons : on ne les compare pas.
    words = [w for w in s.split() if w not in ("ho", "jo", "oh", "hoho", "hohoho", "ah", "o", "ha")]
    return " ".join(words)


def similarity(want: str, heard: str) -> float:
    a, b = letters(want), letters(heard)
    if not a:
        return 1.0 if len(b) < 12 else 0.5
    return difflib.SequenceMatcher(None, a, b).ratio()


def duration_ok(text: str, seconds: float) -> bool:
    n = len(letters(text).replace(" ", "")) + 3 * len(re.findall(r"\b(?:[HhJj]o|[Oo]h)\b", text))
    return 0.04 * n + 0.35 <= seconds <= 0.17 * n + 2.2


def trim_and_level(w, sr):
    """Coupe les silences du début et de la fin, met la voix au même niveau partout, sans saturer."""
    import numpy as np
    w = np.asarray(w, dtype=np.float32)
    if len(w) < sr // 10:
        return w
    frame = sr // 50
    n = len(w) // frame
    rms = np.sqrt((w[: n * frame].reshape(n, frame) ** 2).mean(axis=1) + 1e-12)
    loud = np.where(rms > max(0.004, rms.max() * 0.03))[0]
    if len(loud) == 0:
        return w[:0]
    a = max(0, loud[0] * frame - int(0.06 * sr))
    b = min(len(w), (loud[-1] + 1) * frame + int(0.14 * sr))
    w = w[a:b].copy()
    voiced = rms[loud[0]: loud[-1] + 1]
    level = float(np.sqrt((voiced[voiced > voiced.max() * 0.1] ** 2).mean()))
    w *= 0.09 / max(level, 1e-4)
    w = np.tanh(w * 1.15) / 1.15
    fade = int(0.012 * sr)
    w[:fade] *= np.linspace(0, 1, fade)
    w[-fade:] *= np.linspace(1, 0, fade)
    return w


def longest_gap(w, sr) -> float:
    import numpy as np
    frame = sr // 50
    n = len(w) // frame
    if n == 0:
        return 0.0
    rms = np.sqrt((w[: n * frame].reshape(n, frame) ** 2).mean(axis=1) + 1e-12)
    quiet = rms < max(0.003, rms.max() * 0.02)
    best = run = 0
    for q in quiet:
        run = run + 1 if q else 0
        best = max(best, run)
    return best * frame / sr


def encode(w, sr, path: Path):
    import soundfile as sf
    tmp = path.with_suffix(".wav")
    sf.write(tmp, w, sr)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(tmp), "-ar", "24000", "-ac", "1", "-c:a", "aac", "-b:a", "40k",
                    "-movflags", "+faststart", str(path)], check=True)
    tmp.unlink()


class Studio:
    def __init__(self, ref: Path, whisper="small"):
        import torch
        self.torch = torch
        _load = torch.load

        def _cpu_load(*a, **k):
            k.setdefault("map_location", "cpu")
            return _load(*a, **k)
        torch.load = _cpu_load
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        t = time.time()
        self.tts = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
        self.sr = self.tts.sr
        self.ref = str(ref)
        self.prepared = None
        from faster_whisper import WhisperModel
        self.asr = WhisperModel(whisper, device="cpu", compute_type="int8")
        print(f"modèles chargés en {time.time() - t:.0f} s, {torch.get_num_threads()} fils", flush=True)

    def say(self, text, lang, seed, exaggeration, cfg_weight, temperature):
        self.torch.manual_seed(seed)
        kw = dict(language_id=lang, exaggeration=exaggeration, cfg_weight=cfg_weight, temperature=temperature)
        # La voix de référence n'est analysée qu'une fois, pas à chaque phrase.
        if self.prepared != exaggeration:
            try:
                self.tts.prepare_conditionals(self.ref, exaggeration=exaggeration)
                self.prepared = exaggeration
            except Exception as e:  # ancienne version : on passe la référence à chaque fois
                print("prepare_conditionals indisponible :", e, flush=True)
                self.prepared = None
        if self.prepared == exaggeration:
            wav = self.tts.generate(text, **kw)
        else:
            wav = self.tts.generate(text, audio_prompt_path=self.ref, **kw)
        return wav.squeeze().cpu().numpy()

    def hear(self, path, lang=None):
        segs, info = self.asr.transcribe(str(path), language=lang, beam_size=1, vad_filter=False,
                                         condition_on_previous_text=False)
        return " ".join(s.text.strip() for s in segs).strip(), info


def make_reference(path: Path):
    """Le Père Noël de dessin animé de Kokoro (am_santa), en anglais : le timbre que Chatterbox reprend."""
    import numpy as np, soundfile as sf
    from kokoro import KPipeline
    p = KPipeline(lang_code="a")
    parts = [a for _, _, a in p(REF_TEXT, voice="am_santa", speed=0.9)]
    y = np.concatenate([x.numpy() if hasattr(x, "numpy") else x for x in parts]).astype("float32")
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, y, 24000)
    print(f"référence : {len(y) / 24000:.1f} s → {path}", flush=True)


def settings(lang):
    return SETTINGS.get(lang, SETTINGS["*"])


def produce(studio, it, lang, out_dir: Path, tries=5, **override):
    """Une phrase : on garde le premier tirage qui s'entend bien ; sinon le meilleur, marqué « faible »."""
    cfg = dict(settings(lang), **override)
    floor = 0.5 if it["kind"] != "line" else (0.6 if len(letters(it["text"])) < 28 else 0.72)
    best = None
    t0 = time.time()
    for k in range(tries):
        seed = int(it["id"][:8], 16) % 100000 + 7919 * k
        raw = studio.say(it["text"], lang, seed, **cfg)
        w = trim_and_level(raw, studio.sr)
        dur = len(w) / studio.sr
        if dur < 0.25:
            continue
        path = out_dir / f"{it['id']}.try{k}.m4a"
        encode(w, studio.sr, path)
        heard, _ = studio.hear(path, lang)
        score = similarity(it["text"], heard)
        ok = score >= floor and duration_ok(it["text"], dur) and longest_gap(w, studio.sr) < 1.6
        cand = dict(path=path, score=score, dur=dur, heard=heard, ok=ok, tries=k + 1)
        if best is None or (cand["ok"], cand["score"]) > (best["ok"], best["score"]):
            if best:
                best["path"].unlink(missing_ok=True)
            best = cand
        else:
            path.unlink(missing_ok=True)
        if ok:
            break
    if best is None:
        return dict(id=it["id"], key=it["key"], text=it["text"], ok=False, score=0, dur=0, heard="", tries=tries, secs=time.time() - t0)
    final = out_dir / f"{it['id']}.m4a"
    best["path"].rename(final)
    return dict(id=it["id"], key=it["key"], text=it["text"], ok=best["ok"], score=round(best["score"], 3), dur=round(best["dur"], 2),
                heard=best["heard"], tries=best["tries"], secs=round(time.time() - t0, 1))


def ensure_ref(out: Path) -> Path:
    if REF.is_file():
        return REF
    ref = out / "santa-voice-ref.wav"
    if not ref.is_file():
        make_reference(ref)
    return ref


def cmd_gen(a):
    lang = a.lang
    i, n = (int(x) for x in a.shard.split("/"))
    out = Path(a.out)
    todo = sorted(missing(lang), key=lambda it: it["id"])[i::n]
    if a.limit:
        todo = todo[: a.limit]
    print(f"{lang} lot {i}/{n} : {len(todo)} phrases", flush=True)
    good = out / "voice" / lang
    weak = out / "weak" / lang
    good.mkdir(parents=True, exist_ok=True)
    weak.mkdir(parents=True, exist_ok=True)
    report = out / f"report-{lang}-{i}.jsonl"
    if not todo:
        report.write_text("")
        return
    studio = Studio(ensure_ref(out))
    t0 = time.time()
    deadline = t0 + a.minutes * 60
    with report.open("w", encoding="utf-8") as log:
        for k, it in enumerate(todo, 1):
            if time.time() > deadline:
                print(f"temps écoulé : {len(todo) - k + 1} phrases restent pour le prochain passage", flush=True)
                break
            r = produce(studio, it, lang, good)
            if not r["ok"] and (good / f"{it['id']}.m4a").is_file():
                (good / f"{it['id']}.m4a").rename(weak / f"{it['id']}.m4a")
            log.write(json.dumps(r, ensure_ascii=False) + "\n")
            log.flush()
            left = (time.time() - t0) / k * (len(todo) - k) / 60
            print(f"[{k}/{len(todo)}] {'ok ' if r['ok'] else 'FAIBLE'} {r['score']:.2f} {r['dur']:.1f}s essais {r['tries']} "
                  f"({r['secs']:.0f}s, reste {left:.0f} min) {it['text'][:60]} → {r['heard'][:60]}", flush=True)


def cmd_pilot(a):
    """Quelques phrases et prénoms, plusieurs réglages : ressemblance au texte, langue reconnue, durée, hauteur."""
    import numpy as np
    lang = a.lang
    out = Path(a.out)
    items = plan(lang)
    lines = [it for it in items if it["kind"] == "line" and 45 < len(it["text"]) < 120][:3]
    lines += [it for it in items if it["kind"] == "line" and len(it["text"]) < 30][:1]
    hello = [it for it in items if it["kind"] == "hello"][:3]
    bye = [it for it in items if it["kind"] == "bye"][3:5]
    studio = Studio(ensure_ref(out))
    rows = []
    for tag, over in (("cfg00-ex80", dict(cfg_weight=0.0, exaggeration=0.8)), ("cfg30-ex80", dict(cfg_weight=0.3, exaggeration=0.8)),
                      ("cfg00-ex55", dict(cfg_weight=0.0, exaggeration=0.55)), ("cfg50-ex60", dict(cfg_weight=0.5, exaggeration=0.6))):
        d = out / "pilot" / lang / tag
        d.mkdir(parents=True, exist_ok=True)
        for it in lines + hello + bye:
            r = produce(studio, it, lang, d, tries=2, **over)
            f = d / f"{it['id']}.m4a"
            prob, f0 = 0.0, 0.0
            if f.is_file():
                _, info = studio.hear(f, None)
                prob = info.language_probability if info.language == lang else 0.0
                try:
                    import librosa
                    y, sr = librosa.load(str(f), sr=16000)
                    p = librosa.yin(y, fmin=55, fmax=350, sr=sr)
                    e = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
                    v = p[: len(e)][e[: len(p)] > e.max() * 0.2]
                    f0 = float(np.median(v)) if len(v) else 0.0
                except Exception as ex:
                    print("hauteur :", ex)
            r.update(tag=tag, lang_prob=round(float(prob), 2), f0=round(f0))
            rows.append(r)
            print(json.dumps(r, ensure_ascii=False), flush=True)
    (out / f"pilot-{lang}.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    print(f"\n== {lang}")
    for tag in sorted({r["tag"] for r in rows}):
        rs = [r for r in rows if r["tag"] == tag]
        print(f"{tag}: ok {sum(r['ok'] for r in rs)}/{len(rs)} ressemblance {np.mean([r['score'] for r in rs]):.2f} "
              f"langue {np.mean([r['lang_prob'] for r in rs]):.2f} hauteur {np.median([r['f0'] for r in rs]):.0f} Hz "
              f"temps {np.mean([r['secs'] for r in rs]):.0f} s/phrase essais {np.mean([r['tries'] for r in rs]):.1f}")


def cmd_plan(a):
    total = 0
    for lang in LANGS:
        items = plan(lang)
        chars = sum(len(it["text"]) for it in items)
        kinds = {k: sum(1 for it in items if it["kind"] == k) for k in ("line", "hello", "bye")}
        ids = {it["id"] for it in items}
        assert len(ids) == len(items), "identifiants en double"
        print(f"{lang}: {len(items)} phrases {kinds}, {chars} caractères (≈ {chars / 14 / 60:.0f} min), manquent {len(missing(lang))}")
        total += len(items)
    print("total", total)


def cmd_check(a):
    bad = 0
    for lang in LANGS:
        m = missing(lang)
        bad += len(m)
        want = {it["id"] for it in plan(lang)}
        extra = [p.name for p in (VOICE / lang).glob("*.m4a") if p.stem not in want] if (VOICE / lang).is_dir() else []
        print(f"{lang}: manquent {len(m)} ({sum(1 for it in m if it['kind'] == 'line')} répliques), en trop {len(extra)}")
        for it in m[:8]:
            print("   ", it["kind"], it["text"][:90])
        if a.prune:
            for name in extra:
                (VOICE / lang / name).unlink()
    sys.exit(1 if bad and a.strict else 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan").set_defaults(fn=cmd_plan)
    c = sub.add_parser("check"); c.add_argument("--strict", action="store_true"); c.add_argument("--prune", action="store_true"); c.set_defaults(fn=cmd_check)
    g = sub.add_parser("gen")
    g.add_argument("--lang", required=True); g.add_argument("--shard", default="0/1"); g.add_argument("--out", default="out")
    g.add_argument("--limit", type=int, default=0); g.add_argument("--minutes", type=float, default=320)
    g.set_defaults(fn=cmd_gen)
    p = sub.add_parser("pilot"); p.add_argument("--lang", required=True); p.add_argument("--out", default="out"); p.set_defaults(fn=cmd_pilot)
    a = ap.parse_args()
    a.fn(a)
