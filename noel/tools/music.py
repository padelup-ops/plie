"""ALLÔ PÈRE NOËL : la musique de Noël de l'app, arrangée ici note par note (chants du domaine public) puis jouée
avec une banque de sons libre (FluidR3_GM, licence MIT) par fluidsynth.

 - music-home : pour l'accueil et la préparation. Pot-pourri doux et chaleureux : « We Wish You a Merry Christmas »
   (trad. anglais), « Deck the Halls » (trad. gallois), « Jingle Bells » (J. Pierpont, 1857). Célesta, flûte, cordes,
   harpe, pizzicati et grelots.
 - music-call : sous la voix du Père Noël. « Douce nuit » (F. Gruber, 1818), célesta et harpe sur un tapis de cordes,
   avec le feu qui crépite dans la cheminée.

Usage : python3 music.py <dossier de sortie>  (il faut fluidsynth, la banque FluidR3_GM et ffmpeg)
"""
import os
import struct
import subprocess
import sys
import wave

import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SF2 = next((p for p in ("/usr/share/sounds/sf2/FluidR3_GM.sf2", "/usr/share/soundfonts/FluidR3_GM.sf2") if os.path.exists(p)), None)
TPQ = 480
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(n):
    """« F#4 » -> 66"""
    name, octave = n[:-1], int(n[-1])
    v = NOTE[name[0]] + (1 if "#" in name else 0) - (1 if name.endswith("b") and len(name) > 1 else 0)
    return 12 * (octave + 1) + v


CHORDS = {  # notes du tapis de cordes (autour du do 4) et basse
    "C": (["C4", "E4", "G4"], "C2"), "G": (["B3", "D4", "G4"], "G2"), "D": (["A3", "D4", "F#4"], "D2"),
    "D7": (["A3", "C4", "F#4"], "D2"), "A": (["A3", "C#4", "E4"], "A2"), "A7": (["G3", "C#4", "E4"], "A2"),
    "B7": (["A3", "D#4", "F#4"], "B2"), "Em": (["B3", "E4", "G4"], "E2"), "F": (["A3", "C4", "F4"], "F2"),
    "G7": (["B3", "D4", "F4"], "G2"), "Am": (["A3", "C4", "E4"], "A2"),
}


class Song:
    def __init__(self):
        self.events = []  # (tick, order, bytes)

    def note(self, ch, n, start, dur, vel):
        t0, t1 = int(start * TPQ), int((start + dur) * TPQ) - 8
        self.events.append((t0, 1, bytes([0x90 | ch, midi(n) if isinstance(n, str) else n, vel])))
        self.events.append((max(t0 + 1, t1), 0, bytes([0x80 | ch, midi(n) if isinstance(n, str) else n, 0])))

    def program(self, ch, prog, at=0):
        self.events.append((int(at * TPQ), 0, bytes([0xC0 | ch, prog])))

    def cc(self, ch, ctl, val, at=0):
        self.events.append((int(at * TPQ), 0, bytes([0xB0 | ch, ctl, val])))

    def tempo(self, bpm, at=0):
        us = int(60_000_000 / bpm)
        self.events.append((int(at * TPQ), 0, b"\xff\x51\x03" + us.to_bytes(3, "big")))

    def save(self, path):
        def vlq(n):
            out = [n & 0x7F]
            n >>= 7
            while n:
                out.append((n & 0x7F) | 0x80)
                n >>= 7
            return bytes(reversed(out))
        data, last = b"", 0
        for t, _, ev in sorted(self.events, key=lambda e: (e[0], e[1])):
            data += vlq(t - last) + ev
            last = t
        data += vlq(TPQ * 2) + b"\xff\x2f\x00"
        with open(path, "wb") as f:
            f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, TPQ))
            f.write(b"MTrk" + struct.pack(">I", len(data)) + data)


def section(s, start, melody, chords, beats_per_bar, mel_ch, harp=True, bells=False, mel_vel=70, octave_up=False):
    """Pose une mélodie (liste de (note, durée en noires)), ses accords (un par mesure) et l'accompagnement."""
    t = start
    for n, d in melody:
        if n != "R":
            s.note(mel_ch, n, t, d * 0.98, mel_vel)
            if octave_up:
                s.note(0, midi(n) + 12, t, d * 0.9, int(mel_vel * 0.55))
        t += d
    for i, c in enumerate(chords):
        bar = start + i * beats_per_bar
        pad, bass = CHORDS[c]
        for p in pad:
            s.note(2, p, bar, beats_per_bar * 0.98, 44)
        s.note(3, bass, bar, beats_per_bar * 0.6, 58)
        if beats_per_bar == 4:
            s.note(3, bass, bar + 2, 1.6, 48)
        if harp:
            arp = [pad[0], pad[1], pad[2], midi(pad[0]) + 12, pad[2], pad[1]]
            step = 1.0 if beats_per_bar == 6 else 0.5      # en 6/8 lent : une note par croche
            for k in range(int(beats_per_bar / step)):
                s.note(4, arp[k % len(arp)], bar + k * step, 2.4 * step, 34)
        if bells:
            for k in range(beats_per_bar):
                s.note(9, 83, bar + k, 0.2, 38 if k % 2 else 52)
    return t


def home():
    s = Song()
    s.tempo(96)
    s.program(0, 8)    # célesta (doublure)
    s.program(1, 8)    # mélodie : célesta, puis flûte
    s.program(2, 48)   # cordes
    s.program(3, 45)   # pizzicati
    s.program(4, 46)   # harpe
    for ch, vol in ((0, 70), (1, 100), (2, 70), (3, 80), (4, 64)):
        s.cc(ch, 7, vol); s.cc(ch, 91, 90); s.cc(ch, 93, 40)
    t = 1.0
    # « We Wish You a Merry Christmas », 3/4, sol majeur (levée de ré)
    wish = [("G4", 1), ("G4", .5), ("A4", .5), ("G4", .5), ("F#4", .5), ("E4", 1), ("E4", 1), ("E4", 1),
            ("A4", 1), ("A4", .5), ("B4", .5), ("A4", .5), ("G4", .5), ("F#4", 1), ("D4", 1), ("D4", 1),
            ("B4", 1), ("B4", .5), ("C5", .5), ("B4", .5), ("A4", .5), ("G4", 1), ("E4", 1), ("D4", .5), ("D4", .5),
            ("E4", 1), ("A4", 1), ("F#4", 1), ("G4", 2), ("D4", 1)]
    wish_chords = ["G", "C", "A7", "D", "B7", "Em", "C", "G"]
    s.note(1, "D4", t - 1, 0.95, 66)
    for rep in range(2):
        t = section(s, t, wish, wish_chords, 3, 1, mel_vel=72 if rep == 0 else 64)
    t += 0  # la dernière levée sert d'élan vers la suite
    # « Deck the Halls », 4/4, à la flûte
    s.tempo(92, at=t)
    s.program(1, 73, at=t - 0.1)
    deck = [("D5", 1.5), ("C5", .5), ("B4", 1), ("A4", 1), ("G4", 1), ("A4", 1), ("B4", 1), ("G4", 1),
            ("A4", .5), ("B4", .5), ("C5", .5), ("A4", .5), ("B4", 1.5), ("A4", .5), ("G4", 1), ("F#4", 1), ("G4", 2)]
    deck2 = [("A4", 1.5), ("B4", .5), ("C5", 1), ("A4", 1), ("B4", 1.5), ("C5", .5), ("D5", 1), ("A4", 1),
             ("B4", .5), ("C#5", .5), ("D5", 1), ("E5", .5), ("F#5", .5), ("G5", 1), ("F#5", 1), ("E5", 1), ("D5", 2),
             ("D5", 1.5), ("C5", .5), ("B4", 1), ("A4", 1), ("G4", 1), ("A4", 1), ("B4", 1), ("G4", 1),
             ("E5", .5), ("E5", .5), ("E5", .5), ("E5", .5), ("D5", 1.5), ("C5", .5), ("B4", 1), ("A4", 1), ("G4", 2)]
    t = section(s, t, deck + deck, ["G", "G", "D", "G", "G", "G", "D", "G"], 4, 1, octave_up=True, mel_vel=66)
    t = section(s, t, deck2, ["D", "G", "A", "D", "G", "C", "C", "G"], 4, 1, octave_up=True, mel_vel=66)
    # « Jingle Bells » (refrain), 4/4, célesta et grelots, sans se presser
    s.tempo(100, at=t)
    s.program(1, 8, at=t - 0.1)
    jingle = [("B4", 1), ("B4", 1), ("B4", 2), ("B4", 1), ("B4", 1), ("B4", 2), ("B4", 1), ("D5", 1), ("G4", 1.5), ("A4", .5),
              ("B4", 4), ("C5", 1), ("C5", 1), ("C5", 1.5), ("C5", .5), ("C5", 1), ("B4", 1), ("B4", 1), ("B4", .5), ("B4", .5),
              ("B4", 1), ("A4", 1), ("A4", 1), ("B4", 1), ("A4", 2), ("D5", 2),
              ("B4", 1), ("B4", 1), ("B4", 2), ("B4", 1), ("B4", 1), ("B4", 2), ("B4", 1), ("D5", 1), ("G4", 1.5), ("A4", .5),
              ("B4", 4), ("C5", 1), ("C5", 1), ("C5", 1.5), ("C5", .5), ("C5", 1), ("B4", 1), ("B4", 1), ("B4", .5), ("B4", .5),
              ("D5", 1), ("D5", 1), ("C5", 1), ("A4", 1), ("G4", 4)]
    t = section(s, t, jingle, ["G", "G", "G", "G", "C", "G", "A7", "D", "G", "G", "G", "G", "C", "G", "D7", "G"], 4, 1,
                bells=True, mel_vel=70)
    s.note(9, 81, t, 2, 40)  # triangle final
    return s, t + 3


SILENT_NIGHT = [("G4", 3), ("A4", 1), ("G4", 2), ("E4", 6), ("G4", 3), ("A4", 1), ("G4", 2), ("E4", 6),
                ("D5", 4), ("D5", 2), ("B4", 6), ("C5", 4), ("C5", 2), ("G4", 6),
                ("A4", 4), ("A4", 2), ("C5", 3), ("B4", 1), ("A4", 2), ("G4", 3), ("A4", 1), ("G4", 2), ("E4", 6),
                ("A4", 4), ("A4", 2), ("C5", 3), ("B4", 1), ("A4", 2), ("G4", 3), ("A4", 1), ("G4", 2), ("E4", 6),
                ("D5", 4), ("D5", 2), ("F5", 3), ("D5", 1), ("B4", 2), ("C5", 6), ("E5", 6),
                ("C5", 3), ("G4", 1), ("E4", 2), ("G4", 3), ("F4", 1), ("D4", 2), ("C4", 12)]


def call():
    s = Song()
    s.tempo(150)          # une croche par temps de métronome (6/8 lent)
    s.program(1, 8)       # célesta
    s.program(2, 49)      # cordes douces
    s.program(3, 32)      # contrebasse
    s.program(4, 46)      # harpe
    for ch, vol in ((1, 76), (2, 72), (3, 70), (4, 66)):
        s.cc(ch, 7, vol); s.cc(ch, 91, 100); s.cc(ch, 93, 30)
    mel = [(n, d) for n, d in SILENT_NIGHT]        # durées en croches = en temps à 150
    chords = ["C", "C", "C", "C", "G", "G", "C", "C", "F", "F", "C", "C", "F", "F", "C", "C", "G", "G", "C", "C",
              "C", "G7", "C", "C"]
    t = section(s, 1.0, mel, chords, 6, 1, mel_vel=56)
    return s, t + 6


def render(song_len, song, name, fire=False):
    mid = os.path.join(OUT, name + ".mid")
    wav = os.path.join(OUT, name + "-raw.wav")
    song.save(mid)
    subprocess.run(["fluidsynth", "-ni", "-g", "0.5", "-r", "44100", "-o", "synth.reverb.room-size=0.8",
                    "-o", "synth.reverb.level=0.8", "-o", "synth.reverb.width=1.0", "-F", wav, SF2, mid],
                   check=True, stdout=subprocess.DEVNULL)
    with wave.open(wav) as w:
        sr, ch = w.getframerate(), w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32).reshape(-1, ch) / 32768
    if fire:
        rng = np.random.default_rng(7)
        n = len(x)
        from scipy.signal import butter, sosfilt
        rumble = sosfilt(butter(2, 220, "low", fs=sr, output="sos"), rng.standard_normal(n)) * 0.05
        pops = np.zeros(n)
        bp = butter(2, [1500, 7000], "band", fs=sr, output="sos")
        for _ in range(int(n / sr * 6)):
            at = int(rng.uniform(0, n - 2000))
            c = np.arange(int(rng.uniform(0.004, 0.02) * sr)) / sr
            pop = sosfilt(bp, rng.standard_normal(len(c))) * np.exp(-c / 0.004) * rng.uniform(0.2, 1.0)
            pops[at:at + len(pop)] += pop * 0.12
        x = x + (rumble + pops)[:, None]
    fade = int(1.5 * sr)
    x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    x[: int(0.05 * sr)] *= np.linspace(0, 1, int(0.05 * sr))[:, None]
    x = x / (np.abs(x).max() or 1) * 0.9
    out = os.path.join(OUT, name + ".wav")
    with wave.open(out, "wb") as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", out, "-af", "loudnorm=I=-20:TP=-2", "-ar", "44100",
                    "-c:a", "aac", "-b:a", "160k", os.path.join(OUT, name + ".m4a")], check=True)
    for p in (wav, out):
        os.remove(p)
    print(name, round(len(x) / sr, 1), "s")


if __name__ == "__main__":
    if not SF2:
        sys.exit("FluidR3_GM.sf2 introuvable (paquet fluid-soundfont-gm)")
    os.makedirs(OUT, exist_ok=True)
    s, _ = home()
    render(0, s, "music-home")
    s, _ = call()
    render(0, s, "music-call", fire=True)
