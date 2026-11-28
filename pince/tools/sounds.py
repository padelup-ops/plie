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


def clicks(seconds, per_second, seed, ring=1800.0, level=1.0):
    """Un train de cliquetis réguliers (les dents d'un engrenage), qui boucle sans raccord."""
    rng = np.random.default_rng(seed)
    n = int(seconds * RATE)
    out = np.zeros(n)
    x = t(0.012)
    one = (rng.standard_normal(len(x)) * 0.6 + np.sin(2 * np.pi * ring * x)) * np.exp(-x * 420)
    count = int(round(seconds * per_second))
    for i in range(count):
        start = int(i * n / count)
        idx = (start + np.arange(len(one))) % n
        out[idx] += one * level * (1.0 if i % 2 == 0 else 0.7)
    return out


def buzz(seconds, freq, harmonics=10, tilt=1.0):
    """Le grognement d'un petit moteur électrique : une dent de scie adoucie."""
    x = t(seconds)
    out = np.zeros(len(x))
    for k in range(1, harmonics + 1):
        out += np.sin(2 * np.pi * freq * k * x + k * 0.7) / (k ** tilt)
    return out


def motor():
    """Le chariot qui se déplace : un servomoteur qui ronronne, avec le cliquetis de sa crémaillère.
    Toutes les fréquences font un nombre entier de tours en une demi-seconde : la boucle ne s'entend pas."""
    x = t(0.5)
    whine = buzz(0.5, 180, harmonics=9, tilt=1.1) * (1 + 0.25 * np.sin(2 * np.pi * 24 * x))
    hum = 0.5 * np.sin(2 * np.pi * 60 * x)
    return whine * 0.55 + hum + clicks(0.5, 24, seed=5, ring=2100, level=0.9)


def winch():
    """Le treuil qui déroule le câble : plus grave, plus lourd, avec un cliquet bien marqué.
    Joué un peu plus vite, il sert aussi à la remontée."""
    x = t(0.5)
    growl = buzz(0.5, 96, harmonics=12, tilt=0.9) * (1 + 0.35 * np.sin(2 * np.pi * 14 * x))
    rumble = 0.7 * np.sin(2 * np.pi * 48 * x)
    return growl * 0.6 + rumble + clicks(0.5, 14, seed=9, ring=1400, level=1.5)


def insert():
    """Une pièce glissée dans la fente : elle tinte contre le métal, roule, puis tombe dans la caisse."""
    ping = lambda f, d, decay: np.sin(2 * np.pi * f * t(d)) * np.exp(-t(d) * decay)
    first = ping(3100, 0.12, 38) + 0.6 * ping(4650, 0.12, 50)
    second = ping(2600, 0.1, 45) + 0.5 * ping(3900, 0.1, 60)
    rng = np.random.default_rng(11)
    x = t(0.09)
    thunk = (np.sin(2 * np.pi * (140 + 90 * np.exp(-x * 30)) * x) + 0.3 * rng.standard_normal(len(x))) * np.exp(-x * 34)
    return mix(int(0.5 * RATE), [(0, first * 0.9), (int(0.1 * RATE), second * 0.7), (int(0.24 * RATE), thunk * 1.2)])


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
    save("motor", motor(), peak=0.6)
    save("winch", winch(), peak=0.7)
    save("insert", insert(), peak=0.7)
    samples, rate = music()
    save("music", samples, rate=rate, peak=0.7)
    for f in sorted(os.listdir(OUT)):
        print(f, os.path.getsize(os.path.join(OUT, f)))
