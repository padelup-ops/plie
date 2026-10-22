"""Sons de Plié : timbres doux (marimba, kalimba, cloches, bois) avec un peu de réverbération.

Usage : python3 sound_design.py   (écrit ../Plie/Sounds/*.wav et ../Plie/Sounds/ambient.m4a)
"""
import math
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = "../Plie/Sounds"
rng = np.random.default_rng(20261022)

# Gamme pentatonique (do majeur) : tout sonne bien ensemble.
NOTE = {n: 440.0 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, attack=0.004, decay=3.0):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-decay * t)


def fade_out(x, ms=30):
    n = min(len(x), int(SR * ms / 1000))
    if n:
        x[-n:] *= np.linspace(1, 0, n)
    return x


def lowpass(x, cutoff):
    # filtre passe-bas d'ordre 1, appliqué deux fois (pente douce)
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        prev = 0.0
        for i in range(len(x)):
            prev = (1 - a) * x[i] + a * prev
            y[i] = prev
        x = y.copy()
    return x


def lowpass_fast(x, cutoff):
    from scipy.signal import butter, lfilter
    b, a = butter(2, cutoff / (SR / 2), btype="low")
    return lfilter(b, a, x)


def bandpass(x, lo, hi):
    from scipy.signal import butter, lfilter
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def mix(*parts):
    """parts : (signal, départ en s, gain)."""
    end = max(int(start * SR) + len(sig) for sig, start, _ in parts)
    out = np.zeros(end)
    for sig, start, gain in parts:
        s = int(start * SR)
        out[s:s + len(sig)] += sig * gain
    return out


def reverb(x, size=0.9, wet=0.22, damp=5000):
    """Réverbération par convolution avec un bruit qui décroît (salle douce)."""
    n = int(SR * size)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * size / 6))
    ir = lowpass_fast(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2))
    from scipy.signal import fftconvolve
    tail = fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return dry * (1 - wet) + tail * wet


# ------------------------------------------------------------------ instruments

def marimba(f, dur=0.9, bright=1.0):
    t = t_axis(dur)
    sig = np.sin(2 * np.pi * f * t) * np.exp(-5 * t)
    sig += 0.35 * bright * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-14 * t)
    sig += 0.12 * bright * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-30 * t)
    return sig * np.clip(t / 0.002, 0, 1)


def kalimba(f, dur=1.2):
    t = t_axis(dur)
    sig = np.sin(2 * np.pi * f * t) * np.exp(-3.2 * t)
    sig += 0.22 * np.sin(2 * np.pi * f * 5.95 * t) * np.exp(-12 * t)
    sig += 0.08 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-6 * t)
    return sig * np.clip(t / 0.003, 0, 1)


def bell(f, dur=2.0, decay=2.2):
    t = t_axis(dur)
    partials = [(1, 1.0, 1.0), (2.0, 0.5, 1.3), (2.76, 0.4, 1.8), (5.4, 0.18, 3.0), (8.93, 0.08, 4.5)]
    sig = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-decay * k * t) for r, a, k in partials)
    return sig * np.clip(t / 0.003, 0, 1)


def wood(f=900, dur=0.12, body=1.0):
    """Petit choc de bois : bruit filtré + résonance."""
    n = int(SR * dur)
    t = t_axis(dur)
    noise = rng.standard_normal(n) * np.exp(-90 * t)
    noise = bandpass(noise, f * 0.6, f * 1.8)
    tone = np.sin(2 * np.pi * f * t) * np.exp(-55 * t) * 0.6 * body
    tone += np.sin(2 * np.pi * f * 0.5 * t) * np.exp(-40 * t) * 0.4 * body
    return noise * 0.8 + tone


def whoosh(dur=0.35, lo=500, hi=3500, up=False):
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    chunks = 24
    for i in range(chunks):
        a, b = i * n // chunks, (i + 1) * n // chunks
        p = i / (chunks - 1)
        center = lo + (hi - lo) * (p if up else 1 - p)
        out[a:b] = bandpass(noise, center * 0.7, min(center * 1.4, SR / 2 - 100))[a:b]
    shape = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return out * shape


def thump(f0=160, f1=60, dur=0.25):
    t = t_axis(dur)
    freq = f1 + (f0 - f1) * np.exp(-18 * t)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-14 * t)


def pad(freqs, dur, attack=1.5, release=2.0, cutoff=1800):
    t = t_axis(dur)
    sig = np.zeros_like(t)
    for f in freqs:
        for detune in (-0.12, 0.0, 0.11):
            ff = f * 2 ** (detune / 12)
            # onde riche douce : quelques harmoniques décroissantes
            for h, amp in ((1, 1.0), (2, 0.35), (3, 0.18), (4, 0.08)):
                sig += amp * np.sin(2 * np.pi * ff * h * t + rng.uniform(0, 6.28))
    sig = lowpass_fast(sig, cutoff)
    shape = np.minimum(np.clip(t / attack, 0, 1), np.clip((dur - t) / release, 0, 1))
    return sig * shape


# ------------------------------------------------------------------ écriture

def write(name, x, gain=0.8, rev=None):
    if rev:
        x = reverb(x, *rev)
    x = x - np.mean(x)
    peak = np.max(np.abs(x)) or 1
    x = fade_out(x / peak * gain)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def sounds():
    os.makedirs(OUT, exist_ok=True)
    C5, E5, G5, A5, C6, D5, E6, G6 = hz("C", 5), hz("E", 5), hz("G", 5), hz("A", 5), hz("C", 6), hz("D", 5), hz("E", 6), hz("G", 6)
    C4, G4, A4, E4, D4, C3, G3 = hz("C", 4), hz("G", 4), hz("A", 4), hz("E", 4), hz("D", 4), hz("C", 3), hz("G", 3)

    # Interface et petits gestes
    write("notch", wood(1500, 0.07, 0.6), 0.55)                       # petit tic de bois
    write("decoy", wood(2100, 0.08, 0.8), 0.6)                        # tic plus clair (faux cran)
    write("clunk", mix((wood(520, 0.18, 1.2), 0, 1), (thump(220, 90, 0.2), 0, 0.6)), 0.85, (0.4, 0.12, 4000))
    write("lock", mix((bell(G5, 1.2), 0, 0.7), (wood(800, 0.08), 0, 0.5)), 0.75, (0.9, 0.25, 6000))
    write("wrong", mix((marimba(E4, 0.5, 0.6), 0, 1), (marimba(C4, 0.7, 0.6), 0.12, 1)), 0.7, (0.6, 0.15, 3000))
    write("go", mix((kalimba(G4, 0.6), 0, 1), (kalimba(C5, 0.9), 0.11, 1)), 0.75, (0.8, 0.2, 6000))
    write("stop", mix((bell(C4, 2.2, 1.6), 0, 1), (thump(120, 50, 0.4), 0, 0.5)), 0.8, (1.2, 0.3, 4000))
    write("caught", mix((marimba(A4, 0.4), 0, 1), (marimba(E4, 0.6), 0.14, 1)), 0.75, (0.6, 0.2, 5000))

    # Succès
    write("win", mix(*[(marimba(f, 1.2), i * 0.09, 1) for i, f in enumerate([C5, E5, G5, C6])],
                     (bell(C6, 1.8), 0.3, 0.35)), 0.8, (1.2, 0.28, 7000))
    write("vault", mix((thump(140, 55, 0.5), 0, 0.7),
                       *[(kalimba(f, 1.4), 0.15 + i * 0.1, 1) for i, f in enumerate([C5, E5, G5, A5, C6])],
                       (bell(E6, 2.0), 0.6, 0.3)), 0.8, (1.4, 0.3, 7000))
    write("beam", mix((bell(E6, 1.0, 3.5), 0, 0.6), (bell(G6, 1.0, 3.5), 0.05, 0.4)), 0.55, (0.9, 0.3, 9000))
    write("splat", mix((lowpass_fast(rng.standard_normal(int(SR * 0.18)) * np.exp(-25 * t_axis(0.18)), 900), 0, 1),
                       (thump(110, 60, 0.2), 0, 0.7)), 0.7, (0.4, 0.12, 3000))

    # Nouveaux effets
    write("whoosh", whoosh(0.32, 600, 3200), 0.45)
    write("swish", mix((whoosh(0.28, 4000, 1500), 0, 1), (bell(G6, 0.8, 4), 0.12, 0.35)), 0.6, (0.7, 0.2, 9000))
    write("thud", mix((wood(380, 0.16, 1.4), 0, 1), (thump(180, 80, 0.15), 0, 0.5)), 0.75, (0.3, 0.1, 3000))
    write("pop", mix((kalimba(C6, 0.35), 0, 1), (kalimba(G6, 0.3), 0.04, 0.6)), 0.6, (0.5, 0.2, 9000))
    write("puck", wood(1300, 0.06, 0.9), 0.6)
    write("goal", mix(*[(marimba(f, 1.0), i * 0.08, 1) for i, f in enumerate([G4, C5, E5, G5])],
                      (whoosh(0.5, 900, 2600, up=True), 0, 0.25)), 0.8, (1.0, 0.28, 7000))
    write("bloom", mix(*[(bell(f, 2.6, 1.4), i * 0.12, 0.8) for i, f in enumerate([C5, E5, G5, D5 * 2])]), 0.7, (1.6, 0.35, 8000))


def ambient():
    """Boucle d'ambiance de 48 s : nappe douce + kalimba pentatonique, raccord sans coupure."""
    bpm = 80
    beat = 60 / bpm
    bars = 16
    bar = beat * 4
    total = bars * bar  # 48 s
    chords = [
        [hz("C", 3), hz("G", 3), hz("E", 4), hz("B", 4)],   # Cmaj7
        [hz("A", 2), hz("E", 3), hz("C", 4), hz("G", 4)],   # Am7
        [hz("F", 2), hz("C", 3), hz("A", 3), hz("E", 4)],   # Fmaj7
        [hz("G", 2), hz("D", 3), hz("B", 3), hz("E", 4)],   # G6
    ]
    tail = 4.0
    out = np.zeros(int(SR * (total + tail)))
    for i in range(bars // 2):
        chord = chords[i % 4]
        p = pad(chord, bar * 2 + 2.0, attack=1.6, release=2.2, cutoff=1400)
        s = int(i * bar * 2 * SR)
        out[s:s + len(p)] += p * 0.05
    scale = [hz(n, o) for o, names in ((4, "C D E G A"), (5, "C D E G A")) for n in names.split()]
    arng = np.random.default_rng(7)
    step = beat / 2
    for k in range(int(total / step)):
        if arng.random() < 0.38:
            f = scale[arng.integers(0, len(scale))]
            note = kalimba(f, 1.6) * arng.uniform(0.05, 0.1)
            s = int(k * step * SR)
            out[s:s + len(note)] += note[: len(out) - s]
            # écho
            e = int((k * step + beat * 0.75) * SR)
            if e < len(out):
                out[e:e + len(note)] += note[: len(out) - e] * 0.35
    out = reverb(out, 2.2, 0.35, 5000)[: len(out)]
    # raccord : la queue revient au début
    loop = out[: int(SR * total)].copy()
    tail_part = out[int(SR * total):]
    loop[: len(tail_part)] += tail_part
    loop = loop / (np.max(np.abs(loop)) or 1) * 0.7
    wav = os.path.join(OUT, "ambient_tmp.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(loop, -1, 1) * 32767).astype("<i2").tobytes())
    m4a = os.path.join(OUT, "ambient.m4a")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "96k", m4a], check=True)
    os.remove(wav)


def filet_sounds():
    """Ping-pong : rebond sur la table, frappe de raquette, smash, filet, applaudissements."""
    C5, E5, G5, C6 = hz("C", 5), hz("E", 5), hz("G", 5), hz("C", 6)
    # Rebond : petit « toc » clair et creux (la balle) + la résonance de la table
    t = t_axis(0.12)
    table = np.sin(2 * np.pi * 1150 * t) * np.exp(-60 * t) * 0.5 + np.sin(2 * np.pi * 620 * t) * np.exp(-45 * t) * 0.35
    write("tock", mix((wood(3200, 0.05, 0.4), 0, 0.7), (table, 0, 1)), 0.7, (0.35, 0.12, 6000))
    # Frappe : « pok » de caoutchouc, plus rond
    t = t_axis(0.14)
    rubber = np.sin(2 * np.pi * 760 * t) * np.exp(-38 * t) + 0.4 * np.sin(2 * np.pi * 1520 * t) * np.exp(-60 * t)
    write("pok", mix((rubber, 0, 1), (wood(1900, 0.06, 0.5), 0, 0.5), (thump(320, 160, 0.08), 0, 0.4)), 0.75, (0.4, 0.14, 6000))
    # Smash : frappe sèche + souffle
    write("smash", mix((rubber, 0, 1), (wood(2400, 0.07, 0.9), 0, 0.8), (thump(260, 90, 0.12), 0, 0.7),
                       (whoosh(0.3, 800, 4200, up=True), 0.01, 0.55)), 0.85, (0.5, 0.16, 7000))
    # Filet : frottement doux et mat
    n = int(SR * 0.22)
    rustle = bandpass(rng.standard_normal(n), 350, 1400) * np.exp(-16 * t_axis(0.22))
    write("net", mix((rustle, 0, 1), (thump(140, 70, 0.18), 0, 0.6)), 0.6, (0.3, 0.1, 3000))
    # Point gagné : deux notes claires
    write("point", mix((kalimba(E5, 0.5), 0, 1), (kalimba(C6, 0.8), 0.09, 1), (bell(G5 * 2, 0.9, 4), 0.12, 0.2)), 0.6, (0.9, 0.24, 8000))
    # Applaudissements : des centaines de petits claquements
    dur = 1.8
    out = np.zeros(int(SR * dur))
    clap_n = int(SR * 0.03)
    for _ in range(420):
        start = rng.beta(1.6, 3.2) * (dur - 0.05)
        i = int(start * SR)
        burst = rng.standard_normal(clap_n) * np.exp(-np.arange(clap_n) / (SR * 0.006))
        out[i:i + clap_n] += burst * rng.uniform(0.3, 1.0)
    out = bandpass(out, 700, 5200)
    out *= np.clip(t_axis(dur) / 0.08, 0, 1) * np.clip((dur - t_axis(dur)) / 0.9, 0, 1)
    write("applause", out, 0.5, (1.0, 0.25, 6000))


if __name__ == "__main__":
    sounds()
    ambient()
    filet_sounds()
    print("sons écrits")
