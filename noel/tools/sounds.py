"""ALLÔ PÈRE NOËL : les sons de l'app, tous synthétisés ici (aucun échantillon) :
sonnerie (boîte à musique + grelots), ambiance de l'atelier (feu qui crépite + « Douce nuit », mélodie de 1818, domaine
public) et l'étincelle de la surprise. Usage : python3 tools/sounds.py Resources/Audio"""
import os, subprocess, sys, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(25)
OUT = sys.argv[1]


def t_axis(d): return np.arange(int(d * SR)) / SR
def hp(x, f, o=2): return sosfilt(butter(o, f, 'high', fs=SR, output='sos'), x)
def lp(x, f, o=2): return sosfilt(butter(o, f, 'low', fs=SR, output='sos'), x)
def bp(x, a, b, o=2): return sosfilt(butter(o, [a, b], 'band', fs=SR, output='sos'), x)

NOTES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
def hz(n):
    sharp = '#' in n
    name, octv = n[0], int(n[-1])
    return 261.63 * 2 ** ((NOTES[name] + (1 if sharp else 0) + 12 * (octv - 4)) / 12)


def musicbox(f, d=1.6, bright=1.0):
    t = t_axis(d)
    x = (np.sin(2 * np.pi * f * t) + 0.35 * bright * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.25)
         + 0.18 * bright * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t / 0.12) + 0.08 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / 0.05))
    env = np.exp(-t / (0.55 if f > 900 else 0.8)) * np.minimum(1, t / 0.003)
    return x * env


def jingle(d=0.35):
    """Un coup de grelots : plusieurs petites cloches métalliques désaccordées."""
    t = t_axis(d)
    out = np.zeros(len(t))
    for k in range(6):
        f = rng.uniform(3200, 6800)
        start = int(rng.uniform(0, 0.05) * SR)
        tt = t[:len(t) - start]
        tone = (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 1.47 * tt)) * np.exp(-tt / rng.uniform(0.05, 0.12))
        out[start:] += tone * rng.uniform(0.5, 1.0)
    noise = hp(rng.standard_normal(len(t)), 5000) * np.exp(-t / 0.04) * 0.4
    return (out / 6 + noise) * np.minimum(1, t / 0.002)


def mix_into(buf, sig, at, g=1.0):
    i = int(at * SR)
    if i >= len(buf): return
    n = min(len(sig), len(buf) - i)
    buf[i:i + n] += sig[:n] * g


def reverb(x, secs=1.6, mix=0.22):
    ir_t = t_axis(secs)
    ir = rng.standard_normal(len(ir_t)) * np.exp(-ir_t / (secs / 4))
    ir = lp(ir, 6000)
    wet = np.convolve(x, ir)[:len(x)]
    wet /= (np.abs(wet).max() or 1)
    return x * (1 - mix) + wet * mix * (np.abs(x).max() or 1)


def save(name, x, stereo_width=0.0):
    x = x / (np.abs(x).max() or 1) * 0.89
    if stereo_width:
        d = int(0.011 * SR)
        r = np.concatenate([np.zeros(d), x[:-d]])
        st = np.stack([x, x * (1 - stereo_width) + r * stereo_width], 1)
    else:
        st = np.stack([x, x], 1)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype('<i2').tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "aac", "-b:a", "160k", os.path.join(OUT, name + ".m4a")], check=True)
    os.remove(wav)
    print(name, round(len(x) / SR, 2), "s")


# --- Sonnerie : deux « dring » magiques par cycle de 4 s, en boucle (douce, jamais stridente)
def ringtone():
    d = 4.0
    buf = np.zeros(int(d * SR))
    arp = ['E5', 'G5', 'B5', 'E6', 'B5', 'G5']
    for ring in (0.0, 1.0):
        for k, n in enumerate(arp):
            mix_into(buf, musicbox(hz(n), 1.4), ring + k * 0.085, 0.55)
        for k in range(4):
            mix_into(buf, jingle(), ring + k * 0.11, 0.35)
    mix_into(buf, musicbox(hz('E4'), 2.0, 0.4), 0.0, 0.25)
    return reverb(buf, 1.2, 0.18)


# --- Ambiance de l'atelier : feu qui crépite et « Douce nuit » très doucement, boucle de 28 s environ
SILENT_NIGHT = [('G4', 3), ('A4', 1), ('G4', 2), ('E4', 6), ('G4', 3), ('A4', 1), ('G4', 2), ('E4', 6),
                ('D5', 4), ('D5', 2), ('B4', 6), ('C5', 4), ('C5', 2), ('G4', 6),
                ('A4', 4), ('A4', 2), ('C5', 3), ('B4', 1), ('A4', 2), ('G4', 3), ('A4', 1), ('G4', 2), ('E4', 6),
                ('A4', 4), ('A4', 2), ('C5', 3), ('B4', 1), ('A4', 2), ('G4', 3), ('A4', 1), ('G4', 2), ('E4', 6),
                ('D5', 4), ('D5', 2), ('F5', 3), ('D5', 1), ('B4', 2), ('C5', 6), ('E5', 6),
                ('C5', 3), ('G4', 1), ('E4', 2), ('G4', 3), ('F4', 1), ('D4', 2), ('C4', 12)]
def ambience():
    eighth = 0.27
    total = sum(n for _, n in SILENT_NIGHT) * eighth + 1.5
    buf = np.zeros(int(total * SR))
    t = 0.6
    for n, k in SILENT_NIGHT:
        mix_into(buf, musicbox(hz(n), 2.2, 0.6), t, 0.32)
        t += k * eighth
    # accords discrets à la basse
    for at, n in [(0.6, 'C3'), (6.5, 'C3'), (13.0, 'G2'), (16.2, 'C3'), (19.5, 'F2'), (22.8, 'C3')]:
        mix_into(buf, musicbox(hz(n), 3.0, 0.3), at, 0.16)
    # le feu : souffle grave + crépitements
    rumble = lp(rng.standard_normal(len(buf)), 220) * 0.10
    pops = np.zeros(len(buf))
    for _ in range(int(total * 7)):
        at = rng.uniform(0, total - 0.05)
        c = t_axis(rng.uniform(0.004, 0.02))
        pop = bp(rng.standard_normal(len(c)), 1500, 7000) * np.exp(-c / 0.004) * rng.uniform(0.2, 1.0)
        mix_into(pops, pop, at, 0.5)
    buf = reverb(buf, 2.2, 0.3) + rumble + pops * 0.35
    fade = int(1.2 * SR)                      # boucle sans couture
    buf[:fade] *= np.linspace(0, 1, fade); buf[-fade:] *= np.linspace(1, 0, fade)
    return buf


# --- Étincelle : la surprise de fin (montée de clochettes + grelots)
def sparkle():
    d = 3.4
    buf = np.zeros(int(d * SR))
    seq = ['C6', 'E6', 'G6', 'C7', 'E7', 'G7', 'C8']
    for k, n in enumerate(seq):
        mix_into(buf, musicbox(hz(n), 1.6, 1.2), 0.1 + k * 0.09, 0.45)
    for k in range(10):
        mix_into(buf, jingle(0.3), 0.05 + k * 0.12, 0.22)
    t = t_axis(d)
    shimmer = hp(rng.standard_normal(len(t)), 7000) * np.exp(-((t - 0.8) / 0.7) ** 2) * 0.08
    buf += shimmer
    mix_into(buf, musicbox(hz('C5'), 2.6, 0.5), 0.75, 0.4)
    mix_into(buf, musicbox(hz('G5'), 2.6, 0.5), 0.75, 0.3)
    return reverb(buf, 1.8, 0.28)


save("ringtone", ringtone(), 0.3)
save("ambience", ambience(), 0.5)
save("sparkle", sparkle(), 0.4)
