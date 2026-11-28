"""PEEKACLAW : fabrique les bruitages et la petite musique (fichiers WAV dans Pince/Sounds).

    python3 pince/tools/sounds.py

Tout est calculé : aucun échantillon venu d'ailleurs.
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Pince", "Sounds")


def t(seconds, rate=RATE):
    return np.arange(int(seconds * rate)) / rate


def save(name, samples, rate=RATE, peak=0.85):
    samples = np.asarray(samples, dtype=np.float64)
    top = np.max(np.abs(samples)) or 1.0
    data = (samples / top * peak * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(data.tobytes())


def bell(freq, seconds, rate=RATE, decay=5.0):
    """Une note de boîte à musique : une fondamentale et deux harmoniques qui s'éteignent vite."""
    x = t(seconds, rate)
    tone = np.sin(2 * np.pi * freq * x) + 0.35 * np.sin(2 * np.pi * freq * 2.0 * x) * np.exp(-x * 9) \
        + 0.18 * np.sin(2 * np.pi * freq * 3.01 * x) * np.exp(-x * 14)
    attack = np.minimum(1, x / 0.004)
    return tone * attack * np.exp(-x * decay)


def mix(length, parts):
    out = np.zeros(length)
    for start, samples in parts:
        end = min(length, start + len(samples))
        out[start:end] += samples[: end - start]
    return out


def note(name):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 261.63 * 2 ** (semis / 12)


def pop():
    x = t(0.09)
    return np.sin(2 * np.pi * (520 + 900 * np.exp(-x * 40)) * x) * np.exp(-x * 45)


def coin():
    a, b = bell(note("B5"), 0.09, decay=14), bell(note("E6"), 0.32, decay=11)
    return mix(int(0.4 * RATE), [(0, a), (int(0.07 * RATE), b)])


def clack():
    rng = np.random.default_rng(3)
    x = t(0.06)
    click = (rng.standard_normal(len(x)) * 0.5 + np.sin(2 * np.pi * 1800 * x)) * np.exp(-x * 120)
    return mix(int(0.22 * RATE), [(0, click), (int(0.085 * RATE), click * 0.75)])


def win():
    seq = ["C5", "E5", "G5", "C6", "E6", "G6"]
    parts = [(int(i * 0.085 * RATE), bell(note(n), 0.9, decay=4.5)) for i, n in enumerate(seq)]
    parts.append((int(0.55 * RATE), bell(note("C6"), 1.2, decay=3.2) + bell(note("E6"), 1.2, decay=3.2) + bell(note("G6"), 1.2, decay=3.2)))
    return mix(int(1.9 * RATE), parts)


def aww():
    x = t(0.55)
    freq = 440 * 2 ** (-x * 1.5)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    wobble = 1 + 0.25 * np.sin(2 * np.pi * 9 * x)
    return (np.sin(phase) + 0.3 * np.sin(2 * phase)) * wobble * np.minimum(1, x / 0.02) * np.exp(-x * 3.5)


def plop():
    x = t(0.22)
    freq = 180 + 260 * np.exp(-x * 22)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    return np.sin(phase) * np.exp(-x * 16)


def motor():
    """Un ronron qui boucle sans raccord : toutes les fréquences font un nombre entier de tours en une demi-seconde."""
    x = t(0.5)
    hum = np.sin(2 * np.pi * 110 * x) + 0.5 * np.sin(2 * np.pi * 220 * x) + 0.25 * np.sin(2 * np.pi * 440 * x) \
        + 0.12 * np.sin(2 * np.pi * 660 * x)
    return hum * (1 + 0.3 * np.sin(2 * np.pi * 24 * x))


def music():
    """Une berceuse de boîte à musique, 16 mesures à trois temps, qui boucle."""
    rate = 22050
    beat = 0.36
    bars = [
        ("C4", ["E5", "G5", "E5"]), ("A3", ["C5", "E5", "C5"]), ("F3", ["A4", "C5", "A4"]), ("G3", ["B4", "D5", "G5"]),
        ("C4", ["E5", "G5", "C6"]), ("A3", ["A5", "G5", "E5"]), ("F3", ["F5", "E5", "C5"]), ("G3", ["D5", None, "G4"]),
        ("C4", ["G5", "E5", "G5"]), ("E3", ["B5", "G5", "E5"]), ("F3", ["A5", "F5", "A5"]), ("G3", ["G5", "D5", "B4"]),
        ("A3", ["C6", "A5", "E5"]), ("F3", ["A5", "F5", "C5"]), ("G3", ["B4", "D5", "F5"]), ("C4", ["E5", "C5", None]),
    ]
    total = int(len(bars) * 3 * beat * rate)
    out = np.zeros(total)

    def put(start, samples):
        # Ce qui dépasse la fin revient au début : la boucle ne s'entend pas.
        idx = (start + np.arange(len(samples))) % total
        np.add.at(out, idx, samples)

    for b, (bass, melody) in enumerate(bars):
        start = b * 3 * beat
        put(int(start * rate), bell(note(bass), 2.2, rate, decay=2.2) * 0.55)
        fifth = note(bass) * 1.5
        put(int((start + beat) * rate), bell(fifth, 1.2, rate, decay=3.5) * 0.22)
        put(int((start + 2 * beat) * rate), bell(fifth, 1.2, rate, decay=3.5) * 0.18)
        for i, n in enumerate(melody):
            if n:
                put(int((start + i * beat) * rate), bell(note(n), 1.8, rate, decay=3.0) * 0.8)
    return out, rate


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("pop", pop(), peak=0.6)
    save("coin", coin(), peak=0.6)
    save("clack", clack(), peak=0.6)
    save("win", win(), peak=0.75)
    save("aww", aww(), peak=0.55)
    save("plop", plop(), peak=0.8)
    save("motor", motor(), peak=0.5)
    samples, rate = music()
    save("music", samples, rate=rate, peak=0.7)
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)))
