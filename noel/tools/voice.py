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
#   voice.py check                      ce qui manque dans Resources/Audio/voice (et note les langues complètes)
#   voice.py audit --src <dossier>      reprend une fabrication (branche ci-noel-voice) : garde ce qui passe le contrôle
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

# Réglages retenus après l'essai (voice.py pilot, 27 nov.) : entrain marqué (0,8) et cfg 0,3 dans toutes les
# langues. C'est le réglage le mieux reconnu dans chaque langue par le modèle de transcription (0,94 à 1,0 sur les
# phrases longues ; cfg 0 faisait moins bien, et plus lentement).
# La voix de référence (ai/santa-voice-ref.wav) : le Père Noël de Kokoro tel quel (hauteur médiane 154 Hz), celui
# de l'essai. (Un essai rapide avec une référence descendue de deux demi-tons et un modèle de transcription plus petit
# rendait des transcriptions françaises douteuses, « Joyeux » → « Soyul » : on garde ce qui a été vérifié.)
SETTINGS = {
    "*": dict(exaggeration=0.8, cfg_weight=0.3, temperature=0.75),
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
    s = unicodedata.normalize("NFD", s.lower().replace("œ", "oe").replace("æ", "ae"))
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


def duration_ok(it, seconds: float) -> bool:
    if it["kind"] == "hello":
        return 1.2 <= seconds <= 4.2
    if it["kind"] == "bye":
        return 0.8 <= seconds <= 3.2
    text = it["text"]
    n = len(letters(text).replace(" ", "")) + 3 * len(re.findall(r"\b(?:[HhJj]o|[Oo]h)\b", text))
    return 0.04 * n + 0.35 <= seconds <= 0.13 * n + 1.6


# Des mots qu'un Père Noël ne dit pas. Le modèle ajoute parfois un bruit ou un mot en fin de phrase, que la
# transcription entend n'importe comment : au moindre doute, la phrase est refaite.
RUDE = set("""putain merde bordel con conne connard salope chier foutre
fuck fucking shit damn bitch ass asshole crap hell
mierda puta puto joder cono carajo cabron pendejo
scheisse scheiss verdammt arsch fick ficken
cazzo merda stronzo vaffanculo porca puttana
porra caralho bosta foda puta""".split())


def judge(it, heard: str):
    """La phrase entendue est-elle la bonne ? Elle ressemble au texte, rien n'est dit en plus (le modèle répète
    parfois un mot, ou en ajoute un : « Hello, Olivia! Olivia! »), elle finit sur le bon mot, et pour un prénom :
    c'est bien lui qu'on entend à la fin."""
    score = similarity(it["text"], heard)
    want, got = letters(it["text"]).split(), letters(heard).split()
    if not got or any(w in RUDE for w in got if w not in want):
        return 0.0, False
    if it["kind"] == "line":
        floor = 0.8 if len(" ".join(want)) < 28 else 0.86
        end = difflib.SequenceMatcher(None, want[-1], got[-1]).ratio() >= 0.6 if want else True
        return score, score >= floor and len(got) <= len(want) and end
    name = norm_name(it["key"].split("|", 1)[1]).replace("-", " ").split()
    tail = " ".join(got[-len(name):])
    who = difflib.SequenceMatcher(None, " ".join(name), tail).ratio()
    # Le prénom compte double : c'est lui que l'enfant écoute.
    return round((score + 2 * who) / 3, 3), score >= 0.8 and who >= 0.6 and len(got) <= len(want)


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
        # Deux fabrications par machine, deux fils chacune : plus de phrases à l'heure que quatre fils pour une seule.
        threads = int(os.environ.get("VOICE_THREADS", "0"))
        if threads > 0:
            torch.set_num_threads(threads)
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
        self.asr = WhisperModel(whisper, device="cpu", compute_type="int8", cpu_threads=max(1, torch.get_num_threads()))
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
        score, said = judge(it, heard)
        ok = said and duration_ok(it, dur) and longest_gap(w, studio.sr) < 1.2
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


def tasks_of(a):
    """« fr:line en:line fr:name » : quoi fabriquer, dans l'ordre (line : les répliques ; name : les prénoms, du
    plus courant au plus rare). Sans --tasks : tout ce qui manque dans la langue --lang."""
    if not a.tasks:
        return [(a.lang, "all")]
    out = []
    for t in a.tasks.replace(",", " ").split():
        lang, _, kind = t.partition(":")
        assert lang in LANGS and kind in ("", "all", "line", "name"), t
        out.append((lang, kind or "all"))
    return out


def cmd_gen(a):
    i, n = (int(x) for x in a.shard.split("/"))
    out = Path(a.out)
    # Dans l'ordre demandé, et dans chaque langue dans l'ordre du plan : les répliques d'abord, puis les prénoms du
    # plus courant au plus rare. Si le temps manque, ce sont les prénoms les plus rares qui restent pour un prochain
    # passage (le lutin les dit en attendant).
    todo = []
    for lang, kind in tasks_of(a):
        items = [it for it in missing(lang) if kind == "all" or (it["kind"] == "line") == (kind == "line")]
        part = items[i::n]
        if a.limit:
            # Essai rapide : moitié répliques, moitié prénoms.
            half = [it for it in part if it["kind"] == "line"][: a.limit // 2]
            part = half + [it for it in part if it["kind"] != "line"][: a.limit - len(half)]
        print(f"{lang}:{kind} lot {i}/{n} : {len(part)} phrases", flush=True)
        todo += [(lang, it) for it in part]
        (out / "voice" / lang).mkdir(parents=True, exist_ok=True)
        (out / "weak" / lang).mkdir(parents=True, exist_ok=True)
    if not todo:
        return
    studio = Studio(ensure_ref(out))
    t0 = time.time()
    deadline = t0 + a.minutes * 60
    for k, (lang, it) in enumerate(todo, 1):
        if time.time() > deadline:
            print(f"temps écoulé : {len(todo) - k + 1} phrases restent pour le prochain passage", flush=True)
            break
        good, weak = out / "voice" / lang, out / "weak" / lang
        r = produce(studio, it, lang, good, tries=6 if it["kind"] == "line" else 3)
        if not r["ok"] and (good / f"{it['id']}.m4a").is_file():
            (good / f"{it['id']}.m4a").rename(weak / f"{it['id']}.m4a")
        # Le rapport est écrit phrase par phrase : ce qui est fait peut être publié à tout moment.
        with (out / f"report-{lang}-{i}.jsonl").open("a", encoding="utf-8") as log:
            log.write(json.dumps(r, ensure_ascii=False) + "\n")
        left = (time.time() - t0) / k * (len(todo) - k) / 60
        print(f"[{k}/{len(todo)}] {lang} {'ok ' if r['ok'] else 'FAIBLE'} {r['score']:.2f} {r['dur']:.1f}s essais {r['tries']} "
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


def cmd_audit(a):
    """Reprend les rapports d'une fabrication (report*.jsonl, avec ce que la transcription a entendu) et applique le
    contrôle d'aujourd'hui : copie dans Resources/Audio/voice les phrases qui passent, laisse les autres à refaire."""
    import shutil
    src = Path(a.src)
    kept = dropped = 0
    stats = {}
    worst = []
    for lang in LANGS:
        want = {it["id"]: it for it in plan(lang)}
        rows = {}
        for rp in sorted(src.rglob(f"report-{lang}-*.jsonl")):
            for line in rp.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    r = json.loads(line)
                    # Une phrase refaite à un passage suivant : c'est le tirage gardé qui compte.
                    if r["id"] not in rows or r.get("ok"):
                        rows[r["id"]] = r
        ok_n = bad_n = 0
        for id_, r in rows.items():
            it = want.get(id_)
            f = src / "voice" / lang / f"{id_}.m4a"
            if it is None or not f.is_file():
                continue
            score, said = judge(it, r.get("heard", ""))
            good = bool(r.get("ok")) and said and duration_ok(it, r.get("dur", 0))
            if good:
                ok_n += 1
                if not a.dry:
                    (VOICE / lang).mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(f, VOICE / lang / f.name)
            else:
                bad_n += 1
                worst.append(f"{lang} {it['kind']} | {it['text'][:70]} | {r.get('heard', '')[:70]}")
        if not a.dry:
            mark(lang)
        m = missing(lang) if not a.dry else []
        stats[lang] = (ok_n, bad_n, len(m), sum(1 for it in m if it["kind"] == "line"))
        kept += ok_n
        dropped += bad_n
        print(f"{lang}: gardées {ok_n}, écartées {bad_n}, manquent encore {len(m)} dont {stats[lang][3]} répliques")
    print(f"total gardées {kept}, écartées {dropped}")
    for w in worst[: a.show]:
        print("  écartée :", w)


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


def mark(lang: str) -> bool:
    """Une langue n'est servie par la voix enregistrée que si toutes ses répliques y sont : sinon le Père Noël
    changerait de voix au milieu de l'appel. Le fichier « complet.txt » le dit à l'app (les prénoms, eux, peuvent
    manquer : le lutin les dit)."""
    m = missing(lang)
    flag = VOICE / lang / "complet.txt"
    done = not any(it["kind"] == "line" for it in m) and (VOICE / lang).is_dir()
    if done:
        total = sum(1 for it in plan(lang) if it["kind"] == "hello")
        have = total - sum(1 for it in m if it["kind"] == "hello")
        flag.write_text(f"toutes les répliques ; {have} prénoms sur {total}\n", encoding="utf-8")
    else:
        flag.unlink(missing_ok=True)
    return done


def cmd_check(a):
    bad = 0
    for lang in LANGS:
        m = missing(lang)
        mark(lang)
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
    g.add_argument("--lang", default="fr"); g.add_argument("--tasks", default=""); g.add_argument("--shard", default="0/1")
    g.add_argument("--out", default="out")
    g.add_argument("--limit", type=int, default=0); g.add_argument("--minutes", type=float, default=320)
    g.set_defaults(fn=cmd_gen)
    u = sub.add_parser("audit"); u.add_argument("--src", required=True); u.add_argument("--dry", action="store_true")
    u.add_argument("--show", type=int, default=25); u.set_defaults(fn=cmd_audit)
    p = sub.add_parser("pilot"); p.add_argument("--lang", required=True); p.add_argument("--out", default="out"); p.set_defaults(fn=cmd_pilot)
    a = ap.parse_args()
    a.fn(a)
