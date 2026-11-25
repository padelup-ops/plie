#!/usr/bin/env python3
# Allô Père Noël — voix originale (aucune personne réelle), via le moteur headless
# VoxCPM2 de VoiceStudio (backend/engines/voxcpm2_subprocess/main.py).
#
#   python3 noel/tools/voice.py
#
# Reprend là où il s'est arrêté : un .m4a déjà écrit n'est pas refait.
# Licence des poids : Apache-2.0 (openbmb/VoxCPM2). VoiceStudio lui-même est en AGPL-3.0 ;
# il n'est pas embarqué dans l'app, seuls les fichiers audio le sont.

import base64, hashlib, json, os, re, struct, subprocess, sys, time
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
SCRIPTS = ROOT / "Resources" / "Scripts"
VOICE = ROOT / "Resources" / "Audio" / "voice"
INDEX = VOICE / "voice-index.json"
MONOLOGUE = ROOT / "Resources" / "Audio" / "santa-accueil.m4a"
REFERENCE = ROOT / "ai" / "santa-reference.wav"
SPEC = ROOT / "Resources" / "Video" / "SPEC.txt"
VS = Path(os.environ.get("VOICESTUDIO_ROOT", "/home/ubuntu/VoiceStudio"))
SIDECAR = VS / "backend" / "engines" / "voxcpm2_subprocess" / "main.py"
ORDER = ["kind", "curious", "brave", "funny", "sporty", "dreamer", "creative", "caring", "adventurous"]
LANGS = ["fr", "en", "es", "de", "it", "pt"]
DESIGN = (
    "A warm, deep, jolly elderly man around seventy, Santa Claus, low chest voice, "
    "slow merry smile, kind and gentle, slight soft rasp of age, round comforting storyteller, "
    "never scary, never shouting"
)
INSTRUCT = "warm, deep, jolly elderly man, slow smile, kind, gentle, not scary"
DESIGN_TEXT = "Ho, ho, ho ! Bonjour, mon enfant. C'est moi, le Père Noël, et je te parle depuis mon atelier, au pôle Nord."
MONOLOGUES = [
    "Ho, ho, ho ! Bonjour ! C'est moi, le Père Noël. Je t'appelle depuis mon atelier, au pôle Nord. J'ai une surprise rien que pour toi. Joyeux Noël !",
    "Ho, ho, ho ! Bonjour ! C'est moi, le Père Noël. Je t'appelle depuis le pôle Nord. J'ai une surprise pour toi. Joyeux Noël !",
    "Ho, ho, ho ! Bonjour ! C'est moi, le Père Noël. Je t'appelle depuis mon atelier, au pôle Nord. Les lutins ont presque fini les cadeaux, et j'ai une surprise pour toi. Joyeux Noël !",
]
STEPS = int(os.environ.get("SANTA_STEPS", "6"))
CFG = 2.0
SEED = 20251225

def strip_name(template: str, lang: str) -> str:
    s = template.replace("{name}", "")
    s = re.sub(r"[ \t]{2,}", " ", s)
    s = re.sub(r",\s*,", ", ", s)
    if lang == "fr":
        s = re.sub(r",\s*([!?…])", r" \1", s)
    else:
        s = re.sub(r",\s*([!?…])", r"\1", s)
    s = re.sub(r",\s*\.", ".", s)
    s = re.sub(r"[ \t]{2,}", " ", s)
    s = re.sub(r"\s+,", ",", s)
    return s.strip()

def split_quality(text: str):
    before, after = text.split("{quality}", 1)
    before = before.strip()
    after = after.strip()
    after = re.sub(r"^[.]\s*", "", after)
    after = re.sub(r"^,\s*", "", after).strip()
    return before, after

def phrases(book):
    found = []
    for plural in (False, True):
        join = book["qualityJoin"][1] if plural and len(book["qualityJoin"]) > 1 else book["qualityJoin"][0]
        for size in (1, 2):
            for comb in combinations(ORDER, size):
                parts = []
                for key in comb:
                    arr = book["qualities"][key]
                    parts.append(arr[1] if plural and len(arr) > 1 else arr[0])
                found.append(join.join(parts))
    return found

def plan():
    recipes = {}
    rank = {}
    def keep(text, lang):
        if not text:
            return
        rank[text] = min(rank.get(text, 9), LANGS.index(lang))
    for lang in LANGS:
        book = json.loads((SCRIPTS / f"{lang}.json").read_text())
        recipes[lang] = {}
        seen = set()
        def consider(template):
            if template in seen:
                return
            seen.add(template)
            if "{anecdote}" in template or "{gift" in template:
                recipes[lang][template] = {"kind": "device"}
                return
            if "{" not in template:
                keep(template, lang)
                return
            if "{age}" in template and "{quality}" not in template and "{name}" not in template:
                recipes[lang][template] = {"kind": "filled"}
                for age in range(3, 11):
                    keep(template.replace("{age}", str(age)), lang)
                return
            stripped = strip_name(template, lang)
            if "{quality}" in stripped:
                before, after = split_quality(stripped)
                rec = {"kind": "quality", "before": before}
                if after:
                    rec["after"] = after
                recipes[lang][template] = rec
                keep(before, lang)
                keep(after, lang)
                return
            if "{" in stripped:
                raise SystemExit(f"modèle non géré ({lang}) : {stripped}")
            recipes[lang][template] = {"kind": "line", "key": stripped}
            keep(stripped, lang)
        for steps in list(book["scenarios"].values()) + list(book["blocks"].values()):
            for step in steps:
                for line in step.get("say") or []:
                    consider(line)
        for phrase in phrases(book):
            keep(phrase, lang)
    clips = sorted(rank, key=lambda t: (rank[t], 0 if len(t) > 45 else 1, t))
    return recipes, clips

def fname(text: str) -> str:
    return "vf-" + hashlib.sha256(text.encode()).hexdigest()[:12] + ".m4a"

class Sidecar:
    def __init__(self):
        env = os.environ.copy()
        env["OMNIVOICE_VOXCPM_DEVICE"] = "cpu"
        env["OMNIVOICE_VOXCPM_MODEL"] = "openbmb/VoxCPM2"
        env["TOKENIZERS_PARALLELISM"] = "false"
        self.proc = subprocess.Popen(
            [sys.executable, str(SIDECAR)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, bufsize=0,
        )
        self.log = open("/tmp/santa-voice-sidecar.log", "w")
        import threading
        def drain():
            for line in self.proc.stderr:
                self.log.write(line.decode("utf-8", "replace"))
                self.log.flush()
        threading.Thread(target=drain, daemon=True).start()
        ready = self.recv()
        if not ready or ready.get("op") != "ready":
            raise SystemExit(f"sidecar pas prêt : {ready}")
        print("sidecar", ready, flush=True)

    def send(self, obj):
        body = json.dumps(obj).encode()
        self.proc.stdin.write(struct.pack("!I", len(body)))
        self.proc.stdin.write(body)
        self.proc.stdin.flush()

    def recv(self):
        header = self.proc.stdout.read(4)
        if len(header) < 4:
            return None
        n = struct.unpack("!I", header)[0]
        body = b""
        while len(body) < n:
            chunk = self.proc.stdout.read(n - len(body))
            if not chunk:
                return None
            body += chunk
        return json.loads(body)

    def synthesize(self, text, **options):
        msg = {"op": "synthesize", "text": text, "num_step": STEPS, "guidance_scale": CFG}
        msg.update(options)
        self.send(msg)
        while True:
            frame = self.recv()
            if frame is None:
                err = self.proc.stderr.read() if self.proc.poll() is not None else b""
                raise SystemExit("sidecar arrêté : " + err.decode("utf-8", "replace")[-2000:])
            if frame.get("op") == "audio":
                return frame
            if frame.get("op") == "error":
                raise RuntimeError(frame.get("message") + "\n" + frame.get("traceback", "")[-2000:])
            if frame.get("op") == "progress":
                print("  …", frame.get("stage"), frame.get("percent"), flush=True)

    def close(self):
        try:
            self.send({"op": "shutdown"})
        except Exception:
            pass
        self.proc.terminate()

def pcm_to_wav(frame, path: Path):
    import numpy as np, soundfile as sf
    pcm = base64.b64decode(frame["audio_pcm_b64"])
    audio = np.frombuffer(pcm, dtype="<i2").astype("float32") / 32768.0
    sr = int(frame["sample_rate"])
    sf.write(path, audio, sr)
    peak = float(np.max(np.abs(audio))) if len(audio) else 0
    return len(audio) / sr, peak

def to_m4a(wav: Path, m4a: Path):
    af = (
        "silenceremove=start_periods=1:start_threshold=0.02:start_silence=0.04,"
        "areverse,silenceremove=start_periods=1:start_threshold=0.02:start_silence=0.06,areverse,"
        "loudnorm=I=-16:TP=-1.5:LRA=11,"
        "areverse,afade=t=in:st=0:d=0.02,areverse,afade=t=in:st=0:d=0.012"
    )
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-af", af, "-ar", "44100", "-ac", "1", "-c:a", "aac", "-b:a", "128k", str(m4a)],
        check=True,
    )

def duration(path: Path) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        text=True,
    )
    return float(out.strip())

def write_index(recipes, clips_map, extra):
    doc = {
        "engine": "VoiceStudio voxcpm2 sidecar",
        "model": "openbmb/VoxCPM2",
        "license": "Apache-2.0",
        "design": DESIGN,
        "instruct": INSTRUCT,
        "steps": STEPS,
        "cfg": CFG,
        "seed": SEED,
        "loudness": "-16 LUFS",
        "format": "AAC 128 kbps mono 44100 Hz",
        "monologue": MONOLOGUES[0],
        **extra,
        "clips": clips_map,
        "recipes": recipes,
    }
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path("/tmp/voice-index.json.tmp")
    tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    tmp.replace(INDEX)

def main():
    if not SIDECAR.is_file():
        raise SystemExit(f"VoiceStudio introuvable : {SIDECAR}")
    recipes, clips = plan()
    names = [fname(t) for t in clips]
    if len(names) != len(set(names)):
        raise SystemExit("collision de noms de fichiers")
    clips_map = {}
    if INDEX.is_file():
        old = json.loads(INDEX.read_text())
        clips_map = old.get("clips") or {}
    print(f"{len(clips)} répliques, {len(clips_map)} déjà dans l'index", flush=True)
    write_index(recipes, clips_map, {})
    side = Sidecar()
    try:
        if not REFERENCE.is_file() or REFERENCE.stat().st_size < 1000:
            REFERENCE.parent.mkdir(parents=True, exist_ok=True)
            for seed in (SEED, 7, 11, 42):
                t0 = time.time()
                frame = side.synthesize(DESIGN_TEXT, description=DESIGN, seed=seed)
                dur, peak = pcm_to_wav(frame, REFERENCE)
                print(f"design seed {seed} : {dur:.1f}s crête {peak:.2f} en {time.time()-t0:.0f}s", flush=True)
                if 3.5 <= dur <= 16 and peak > 0.05:
                    break
            else:
                raise SystemExit("la voix dessinée n'est pas utilisable")
        ref = str(REFERENCE)
        # Monologue, ajusté pour tenir 10 à 15 secondes.
        chosen = None
        if MONOLOGUE.is_file() and MONOLOGUE.stat().st_size > 1000:
            dur = duration(MONOLOGUE)
            if 10 <= dur <= 15.4:
                chosen = (json.loads(INDEX.read_text()).get("monologue", MONOLOGUES[0]), dur)
                print(f"monologue déjà là : {dur:.1f}s", flush=True)
        if chosen is None:
            for text in MONOLOGUES:
                wav = Path("/tmp/santa-monologue.wav")
                t0 = time.time()
                frame = side.synthesize(text, ref_audio=ref, instruct=INSTRUCT, seed=SEED)
                pcm_to_wav(frame, wav)
                to_m4a(wav, MONOLOGUE)
                dur = duration(MONOLOGUE)
                print(f"monologue {dur:.1f}s en {time.time()-t0:.0f}s : {text}", flush=True)
                chosen = (text, dur)
                if 10 <= dur <= 15.4:
                    break
        if chosen and SPEC.is_file():
            spec = SPEC.read_text()
            spec = re.sub(r"(?s)Monologue \(français\)\n  .+\n?", "Monologue (français)\n  " + chosen[0] + "\n", spec)
            SPEC.write_text(spec)
            # le champ monologue de l'index suit le texte retenu
            global_monologue = chosen[0]
        else:
            global_monologue = MONOLOGUES[0]
        done = 0
        t_batch = time.time()
        for i, text in enumerate(clips, 1):
            name = fname(text)
            dest = VOICE / name
            if dest.is_file() and dest.stat().st_size > 800 and clips_map.get(text) == name:
                done += 1
                continue
            wav = Path("/tmp/santa-line.wav")
            t0 = time.time()
            seed = SEED + (int(hashlib.sha256(text.encode()).hexdigest()[:6], 16) % 10000)
            frame = side.synthesize(text, ref_audio=ref, instruct=INSTRUCT, seed=seed)
            dur, peak = pcm_to_wav(frame, wav)
            if dur < 0.25 or peak < 0.02:
                frame = side.synthesize(text, ref_audio=ref, instruct=INSTRUCT, seed=seed + 1)
                dur, peak = pcm_to_wav(frame, wav)
            to_m4a(wav, dest)
            clips_map[text] = name
            done += 1
            elapsed = time.time() - t0
            spent = time.time() - t_batch
            left = len(clips) - i
            eta = (spent / max(1, done)) * left
            print(f"[{i}/{len(clips)}] {dur:.1f}s audio, {elapsed:.0f}s, ETA {eta/60:.0f} min — {text[:70]}", flush=True)
            if done % 5 == 0:
                write_index(recipes, clips_map, {"monologue": global_monologue})
        write_index(recipes, clips_map, {"monologue": global_monologue})
        print(f"terminé : {done} fichiers", flush=True)
    finally:
        side.close()

if __name__ == "__main__":
    main()
