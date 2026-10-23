"""Bande-son de la vidéo : musique originale à 120 BPM et bruitages du jeu, calés sur cues.py."""
import os, subprocess, sys, wave
import numpy as np
sys.path.insert(0, "/home/claude/plie/tools")
import sound_design as S
import cues as C

SR = 44100
N = int(C.DURATION * SR)
SOUNDS = "/home/claude/plie/Plie/Sounds"
mixL = np.zeros(N)
mixR = np.zeros(N)
rng = np.random.default_rng(7)


def load(name):
    path = os.path.join(SOUNDS, name)
    if name.endswith(".m4a"):
        tmp = "/tmp/claude-0/-home-claude/263165a2-43b9-5e92-82f6-500183c97a8a/scratchpad/video/_tmp.wav"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), tmp], check=True)
        path = tmp
    with wave.open(path) as w:
        d = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768
        if w.getnchannels() == 2:
            d = d.reshape(-1, 2).mean(axis=1)
    return d


def place(sig, t, gain=1.0, pan=0.0, music=False):
    i = int(t * SR)
    if i >= N:
        return
    seg = sig[: N - i] * gain
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    mixL[i:i + len(seg)] += seg * l * 1.414
    mixR[i:i + len(seg)] += seg * r * 1.414


# ---------------------------------------------------------------- musique
beat = 0.5
C4 = 261.63
chords = [[0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]]          # do, la m, fa, sol
roots = [0, -3, -7, -5]


def f(semi, octave=0):
    return C4 * 2 ** (semi / 12 + octave)


def music_gain(t):
    if t < 2.8:
        return 0.55
    if 8.8 <= t < 11.8:
        return 0.38          # le piano passe devant
    if t > 24.0:
        return max(0, 25.0 - t)
    return 1.0


def kick():
    return S.thump(160, 48, 0.32) * 1.0


def clap():
    n = int(0.18 * SR)
    noise = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.035))
    return S.bandpass(noise, 900, 6000) * 0.9


def hat():
    n = int(0.05 * SR)
    noise = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.008))
    return S.bandpass(noise, 6000, 15000)


def bass(freq, dur):
    t = S.t_axis(dur)
    sig = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2 * t) + 0.15 * np.sign(np.sin(2 * np.pi * freq * t))
    sig = S.lowpass_fast(sig, 600)
    return sig * np.minimum(1, t / 0.005) * np.exp(-t * 2.2)


K, CL, HT = kick(), clap(), hat()
bars = int(C.DURATION / (4 * beat)) + 1
for bar in range(bars):
    t0 = bar * 4 * beat
    ch = chords[bar % 4]
    root = roots[bar % 4]
    intro = t0 < 2.8
    for b in range(4):
        tb = t0 + b * beat
        if tb >= C.DURATION:
            break
        g = music_gain(tb)
        if not intro or tb > 2.0:
            place(K, tb, 0.55 * g)
        if not intro and b in (1, 3):
            place(CL, tb, 0.22 * g, 0.1)
        if not intro:
            place(HT, tb + beat / 2, 0.10 * g, -0.3)
            place(HT, tb + beat * 0.75, 0.05 * g, 0.3)
    if not intro:
        place(bass(f(root, -2), 0.9), t0, 0.38 * music_gain(t0))
        place(bass(f(root, -2), 0.6), t0 + 1.5 * beat, 0.30 * music_gain(t0))
        place(bass(f(root, -2), 0.6), t0 + 2.5 * beat, 0.30 * music_gain(t0))
    # nappe
    pad = S.pad([f(n, -1) for n in ch], 2.2, attack=0.3, release=0.6, cutoff=1600)
    place(pad / (np.max(np.abs(pad)) or 1), t0, 0.12 * music_gain(t0))
    # arpège de kalimba (sauf pendant le piano)
    for k in range(8):
        tk = t0 + k * beat / 2
        if tk >= C.DURATION or 8.8 <= tk < 11.8:
            continue
        if intro and k % 2:
            continue
        note = ch[[0, 1, 2, 1, 2, 0, 1, 2][k]] + (12 if k >= 4 else 0)
        place(S.kalimba(f(note, 1), 0.6), tk, 0.16 * music_gain(tk), [-0.4, 0.4][k % 2])

# montée avant le premier temps fort
place(S.whoosh(1.2, 400, 5000, up=True), 1.6, 0.22)

# ---------------------------------------------------------------- bruitages
sfx = {n: load(n + ".wav") for n in ["whoosh", "clunk", "beam", "pieceMove", "tock", "pok", "smash", "puck", "goal", "bloom", "pop", "win", "applause", "swish"]}
place(sfx["whoosh"], 0.3, 0.5)
place(sfx["clunk"], 1.6, 0.6)
for s, a, b in C.SCENES[1:]:
    place(sfx["whoosh"], a - 0.12, 0.38)
for t in C.RAYON_HITS:
    place(sfx["beam"], t - 0.05, 0.75)
for t, uci in C.CHESS_MOVES:
    place(sfx["pieceMove"], t + 0.3, 0.9)
for t, m in C.PIANO:
    note = load(f"piano{m}.m4a")[: int(0.9 * SR)]
    note[-int(0.15 * SR):] *= np.linspace(1, 0, int(0.15 * SR))
    place(note, t, 1.1)
for t, x, v, z, snd in C.FILET:
    if snd:
        place(sfx[snd], t, 0.85, (x - 0.5) * 0.8)
for t, x, v, snd in C.HOCKEY:
    place(sfx[snd], t, 0.9 if snd == "puck" else 0.8, (x - 0.5) * 0.8)
place(sfx["applause"], C.HOCKEY[-1][0] + 0.1, 0.35)
place(sfx["whoosh"], 16.75, 0.4)
place(sfx["clunk"], C.FERME_CLOSE, 0.7)
place(sfx["bloom"], C.FERME_BLOOM - 0.2, 0.8)
for i, t in enumerate(C.GRID_POPS):
    place(sfx["pop"], t, 0.45 + 0.03 * (i % 4), [-0.5, 0, 0.5][i % 3])
place(sfx["swish"], 21.65, 0.5)
place(sfx["win"], C.END_WIN, 0.8)
place(sfx["applause"], C.END_WIN + 0.2, 0.3)
# accord final
for n in [0, 4, 7, 12]:
    place(S.bell(f(n, 1), 2.5, 1.6), 22.0, 0.12)

stereo = np.stack([mixL, mixR], axis=1)
stereo = np.tanh(stereo * 1.2) / np.tanh(1.2)            # limiteur doux
stereo /= np.max(np.abs(stereo)) or 1
stereo *= 0.89
fade = int(0.6 * SR)
stereo[-fade:] *= np.linspace(1, 0, fade)[:, None]
with wave.open("soundtrack.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
print("bande-son écrite", stereo.shape[0] / SR, "s")
