"""UNLOCKED : fabrique les messages vocaux avec des voix de synthèse neuronales, puis leur donne un son de téléphone.

Français : Piper (voix rhasspy/piper-voices). Anglais : Kokoro (Apache 2.0), Piper si Kokoro échoue.
Lit les messages dans NinaStory.swift ; écrit Voices/vm_<id>_<fr|en>.m4a.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "Unlocked", "NinaStory.swift")
OUT = os.environ.get("OUT", "voices-out")
MODELS = os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "piper")
os.makedirs(OUT, exist_ok=True)
os.makedirs(MODELS, exist_ok=True)

# Qui parle avec quelle voix (modèle Piper, numéro de locuteur ; voix Kokoro)
FR = {"maman": ("fr_FR-upmc-medium", 0), "lea": ("fr_FR-siwis-medium", None), "h": ("fr_FR-tom-medium", None), "samir": ("fr_FR-upmc-medium", 1)}
EN = {"maman": "af_sarah", "lea": "af_heart", "h": "am_onyx", "samir": "am_michael"}
EN_PIPER = {"maman": ("en_US-hfc_female-medium", None), "lea": ("en_US-lessac-high", None), "h": ("en_US-ryan-high", None), "samir": ("en_US-joe-medium", None)}
# Un peu plus lent que la voix par défaut : un vrai message laissé au téléphone
SPEED = {"maman": 1.12, "lea": 1.04, "h": 1.15, "samir": 1.0}

text = open(STORY, encoding="utf-8").read()
items = []
for m in re.finditer(r'Voicemail\(id: "(\w+)", contact: "(\w+)".*?transcript: T\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)', text, re.S):
    vid, who, fr, en = m.groups()
    items.append((vid, who, fr.replace('\\"', '"'), en.replace('\\"', '"')))
print(len(items), "messages vocaux")


def piper_model(name):
    lang = name.split("-")[0]
    family, voice, quality = lang.split("_")[0], name.split("-")[1], name.split("-")[2]
    base = f"https://huggingface.co/rhasspy/piper-voices/resolve/main/{family}/{lang}/{voice}/{quality}/{name}"
    path = os.path.join(MODELS, name + ".onnx")
    for ext in (".onnx", ".onnx.json"):
        if not os.path.exists(path.replace(".onnx", ext)):
            urllib.request.urlretrieve(base + ext, path.replace(".onnx", ext))
    return path


def piper(name, speaker, speed, line, wav):
    cmd = ["piper", "--model", piper_model(name), "--output_file", wav, "--length_scale", str(speed),
           "--noise_scale", "0.6", "--noise_w", "0.85", "--sentence_silence", "0.35"]
    if speaker is not None:
        cmd += ["--speaker", str(speaker)]
    subprocess.run(cmd, input=line.encode(), check=True, capture_output=True)


kokoro = None
def kokoro_say(voice, speed, line, wav):
    global kokoro
    import numpy as np
    import soundfile as sf
    from kokoro import KPipeline
    if kokoro is None:
        kokoro = KPipeline(lang_code="a")
    parts = [a for _, _, a in kokoro(line, voice=voice, speed=1 / speed)]
    sf.write(wav, np.concatenate(parts), 24000)


def phone(wav, out):
    """Le son d'une messagerie : bande étroite, un peu compressé, un léger souffle."""
    af = ("highpass=f=300,lowpass=f=3400,acompressor=threshold=-20dB:ratio=3:attack=5:release=80,"
          "volume=1.6,apad=pad_dur=0.6,adelay=350|350")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                    "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.006:sample_rate=24000",
                    "-filter_complex", f"[0:a]{af}[v];[v][1:a]amix=inputs=2:duration=first:weights=1 1[m]",
                    "-map", "[m]", "-ac", "1", "-ar", "24000", "-c:a", "aac", "-b:a", "64k", out], check=True)


report = []
for vid, who, fr, en in items:
    for lang, line in (("fr", fr), ("en", en)):
        wav = os.path.join(OUT, f"{vid}_{lang}.wav")
        try:
            if lang == "fr":
                name, spk = FR.get(who, FR["lea"])
                piper(name, spk, SPEED.get(who, 1.05), line, wav)
                engine = name
            else:
                try:
                    kokoro_say(EN.get(who, "af_heart"), SPEED.get(who, 1.05), line, wav)
                    engine = "kokoro " + EN.get(who, "af_heart")
                except Exception as e:
                    print("kokoro indisponible :", e)
                    name, spk = EN_PIPER.get(who, EN_PIPER["lea"])
                    piper(name, spk, SPEED.get(who, 1.05), line, wav)
                    engine = name
            phone(wav, os.path.join(OUT, f"vm_{vid}_{lang}.m4a"))
            os.remove(wav)
            report.append(f"ok    vm_{vid}_{lang}.m4a  ({who}, {engine})")
        except Exception as e:
            report.append(f"ÉCHEC vm_{vid}_{lang} : {e}")
print("\n".join(report))
open(os.path.join(OUT, "voix.txt"), "w").write("\n".join(report) + "\n")
sys.exit(1 if any(r.startswith("ÉCHEC") for r in report) else 0)
