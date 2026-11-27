"""VICEFOLD promo video: the soundtrack (python3 audio.py <work dir> -> music.wav).

An original West Coast hip-hop instrumental at 96 BPM, written here note by note (F minor: Fm9, Fm9, Dbmaj7, Eb):
a laid-back drum beat, a round synth bass, electric piano chords, muted guitar and the high gliding synth lead of
the genre. Then the sounds of what happens on screen, placed from cues.py. Nothing is sampled or copied from a game
or a record.
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cues as C

SR = 44100
N = int(C.DURATION * SR)
BEAT, BAR = C.BEAT, C.BAR
STEP = BEAT / 4                      # a sixteenth note
SWING = 0.022                        # the off sixteenths come a little late
rng = np.random.default_rng(11)


def ax(dur):
    return np.arange(int(dur * SR)) / SR


def filt(x, kind, fc, order=2):
    fc = np.clip(np.asarray(fc, dtype=float), 20, SR / 2 - 200) / (SR / 2)
    return sosfilt(butter(order, fc, btype=kind, output="sos"), x)


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def at(bar, step=0):
    """Time of a sixteenth in a bar, with the swing."""
    return bar * BAR + step * STEP + (SWING if step % 2 else 0)


class Bus:
    def __init__(self):
        self.l, self.r = np.zeros(N), np.zeros(N)

    def add(self, sig, t, gain=1.0, pan=0.0):
        i = int(round(t * SR))
        if i >= N or i < 0:
            return
        seg = sig[: N - i] * gain
        a = (pan + 1) * np.pi / 4
        self.l[i:i + len(seg)] += seg * np.cos(a) * 1.414
        self.r[i:i + len(seg)] += seg * np.sin(a) * 1.414


# ------------------------------------------------------------------ drums
def kick():
    t = ax(0.45)
    f = 48 + 95 * np.exp(-t * 30)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5)
    click = filt(rng.standard_normal(len(t)), "band", [1500, 5000]) * np.exp(-t * 300) * 0.3
    return np.tanh((body + click) * 1.8)


def snare():
    t = ax(0.3)
    noise = filt(rng.standard_normal(len(t)), "band", [900, 9000]) * np.exp(-t * 17)
    tone = np.sin(2 * np.pi * 200 * t) * np.exp(-t * 28) + 0.4 * np.sin(2 * np.pi * 340 * t) * np.exp(-t * 36)
    return noise * 0.85 + tone * 0.6


def clap():
    t = ax(0.32)
    out = np.zeros(len(t))
    for d in (0.0, 0.011, 0.023):
        i = int(d * SR)
        out[i:] += filt(rng.standard_normal(len(t) - i), "band", [1000, 3600]) * np.exp(-t[: len(t) - i] * (60 if d < 0.02 else 16))
    return out * 0.7


def hat(open_=False):
    t = ax(0.26 if open_ else 0.05)
    return filt(rng.standard_normal(len(t)), "high", 7000) * np.exp(-t * (15 if open_ else 120))


def shaker():
    t = ax(0.06)
    return filt(rng.standard_normal(len(t)), "band", [5000, 11000]) * np.sin(np.pi * t / 0.06) ** 2


def crash():
    t = ax(2.4)
    return filt(rng.standard_normal(len(t)), "high", 4500) * np.exp(-t * 2.2) * np.minimum(1, t / 0.004)


def tom(f=110):
    t = ax(0.4)
    fr = f * (1 + 0.6 * np.exp(-t * 22))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 9)


# ------------------------------------------------------------------ instruments
def bass_note(midi, dur):
    """A round synth bass that slides up into the note."""
    t = ax(dur)
    f = hz(midi) * 2 ** (-2 * np.exp(-t / 0.03) / 12)
    ph = np.cumsum(f) / SR
    sig = (2 * (ph % 1) - 1) * 0.6 + np.sign(np.sin(2 * np.pi * ph)) * 0.3
    sig = filt(sig, "low", 420, 4) * 1.4 + np.sin(2 * np.pi * ph) * 0.9 + np.sin(4 * np.pi * ph) * 0.25
    return sig * np.minimum(1, t / 0.006) * np.exp(-t * 1.6) * np.minimum(1, (dur - t) / 0.03)


def epiano(midi, dur, bright=1.0):
    """An electric piano: a soft tone with a bell on the attack."""
    t = ax(dur + 0.25)
    f = hz(midi)
    index = 1.6 * bright * np.exp(-t * 7) + 0.25
    sig = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t)) + 0.25 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 30)
    env = np.minimum(1, t / 0.004) * np.exp(-t * 2.2) * np.minimum(1, np.maximum(0, (dur + 0.25 - t) / 0.25))
    return sig * env


def chord(notes, dur, bright=1.0):
    out = np.zeros(int((dur + 0.25) * SR))
    for k, n in enumerate(notes):
        e = epiano(n, dur, bright)
        d = int(k * 0.006 * SR)                 # the hand rolls the chord a little
        out[d:d + len(e) - d] += e[: len(out) - d]
    return out / len(notes) * 2.2


def chick(notes, wah):
    """A muted guitar stroke through a wah pedal."""
    t = ax(0.07)
    sig = sum(np.sign(np.sin(2 * np.pi * hz(n) * t)) + 2 * ((t * hz(n)) % 1) - 1 for n in notes) / len(notes)
    sig = filt(sig + rng.standard_normal(len(t)) * 0.3, "band", [wah * 0.75, wah * 1.35], 2)
    return sig * np.exp(-t * 55) * np.minimum(1, t / 0.002)


def lead_line(notes, total):
    """The high gliding lead: one voice that slides from note to note. notes: (start s, length s, midi)."""
    n = int(total * SR)
    pitch = np.full(n, np.nan)
    gate = np.zeros(n)
    for s, d, m in notes:
        a, b = int(s * SR), min(n, int((s + d) * SR))
        pitch[a:] = m
        gate[a:b] = 1
    first = notes[0][2]
    pitch = np.where(np.isnan(pitch), first, pitch)
    k = np.exp(-1 / (0.045 * SR))                       # the glide
    pitch = lfilter([1 - k], [1, -k], pitch, zi=[first * k])[0]
    kg = np.exp(-1 / (0.03 * SR))
    gate = lfilter([1 - kg], [1, -kg], gate)
    t = np.arange(n) / SR
    pitch = pitch + 0.16 * np.sin(2 * np.pi * 5.3 * t)   # vibrato
    ph = np.cumsum(hz(pitch)) / SR
    sig = np.sin(2 * np.pi * ph) + 0.22 * filt(2 * (ph % 1) - 1, "low", 5000) + 0.12 * np.sin(4 * np.pi * ph)
    return sig * gate


def blip(f, dur=0.09, kind="sine"):
    t = ax(dur)
    w = np.sin(2 * np.pi * f * t) if kind == "sine" else filt(np.sign(np.sin(2 * np.pi * f * t)), "low", 6000)
    return w * np.exp(-t * (38 if dur < 0.12 else 14)) * np.minimum(1, t / 0.002)


def bell(f, dur=1.6):
    t = ax(dur)
    parts = [(1, 1.0, 3), (2.0, 0.45, 4), (3.01, 0.25, 6), (4.2, 0.12, 9)]
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-k * t) for r, a, k in parts) * np.minimum(1, t / 0.003)


def whoosh(dur=0.5, lo=300, hi=6000, up=True):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    steps = 28
    for i in range(steps):
        a, b = i * n // steps, (i + 1) * n // steps
        p = i / (steps - 1)
        c = lo * (hi / lo) ** (p if up else 1 - p)
        out[a:b] = filt(noise, "band", [c * 0.7, c * 1.5])[a:b]
    return out * np.sin(np.linspace(0, np.pi, n)) ** 1.6


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return whoosh(dur, 300, 9000, True) * (t / dur) ** 1.5 * 2


# ------------------------------------------------------------------ the track
drums, bass, keys, guitar, lead, fx = Bus(), Bus(), Bus(), Bus(), Bus(), Bus()
CHORDS = [[53, 56, 60, 63, 67], [53, 56, 60, 63, 67], [49, 53, 56, 60, 63], [51, 55, 58, 60, 65]]   # Fm9, Fm9, Dbmaj9, Eb6/9
ROOTS = [41, 41, 37, 39]                                                                           # F2, F2, Db2, Eb2
K, S, CL, H, HO, SH, CR = kick(), snare(), clap(), hat(), hat(True), shaker(), crash()
BARS = int(round(C.DURATION / BAR))
_T = {name: a for name, a, b in C.SCENES}
BREAK = (int(_T["trust"] / BAR), int(_T["trust"] / BAR) + 1)     # "no account, no ads, no tracking": the beat stops
ENDBAR = int(_T["end"] / BAR)
LAST = BARS - 1                                # the last chord rings out

for b in range(BARS):
    ch, root = CHORDS[b % 4], ROOTS[b % 4]
    intro, brk, last = b == 0, b in BREAK, b == LAST
    full = not intro and not brk and not last
    # drums: boom ... boom-boom, clap on two and four
    if full:
        for s in (0, 7, 8, 10) + ((15,) if b % 2 else ()):
            drums.add(K, at(b, s), 0.85 if s in (0, 8) else 0.6)
        for s in (4, 12):
            drums.add(S, at(b, s), 0.45, 0.05)
            drums.add(CL, at(b, s), 0.5, -0.1)
        for s in range(0, 16, 2):
            drums.add(H, at(b, s), 0.13 if s % 4 == 0 else 0.09, 0.25)
        drums.add(HO, at(b, 14 if b % 2 else 6), 0.07, 0.3)
        for s in range(16):
            drums.add(SH, at(b, s), 0.035 if s % 2 else 0.02, -0.35)
        if b % 4 == 3:                          # a small fill into the next four bars
            for i, s in enumerate((13, 14, 15)):
                drums.add(S, at(b, s), 0.18 + 0.07 * i, -0.2 + 0.2 * i)
    # bass: follows the kick, with an octave jump
    if full:
        for s, steps, octave, g in ((0, 6, 0, 1.0), (7, 1, 12, 0.7), (8, 2, 0, 0.95), (10, 3, 0, 0.85), (14, 2, 7 if b % 4 == 3 else 12, 0.6)):
            bass.add(bass_note(root + octave, steps * STEP * 0.95), at(b, s), 0.42 * g)
    elif intro or brk or last:
        bass.add(bass_note(root, BAR * (1.6 if last else 0.98)), at(b, 0), 0.4)
    # electric piano: the chord held softly, then answers off the beat
    if last:
        keys.add(chord(ch + [72], BAR * 1.8, 1.2), at(b, 0), 0.5)
    else:
        keys.add(chord(ch, BEAT * 2.4, 0.5 if intro else 0.9), at(b, 0), 0.34 if not brk else 0.4, -0.2)
        if not intro:
            keys.add(chord(ch[1:], STEP * 2.5, 1.1), at(b, 6), 0.3, 0.3)
            keys.add(chord(ch[1:], STEP * 3, 1.0), at(b, 10), 0.26, -0.3)
            if full:
                keys.add(chord(ch[2:], STEP * 1.5, 1.2), at(b, 15), 0.2, 0.2)
    # muted guitar with a wah
    if full and b >= 2:
        for i, s in enumerate((2, 3, 6, 11, 14)):
            guitar.add(chick([ch[2] + 12, ch[3] + 12, ch[4] + 12], 700 + 900 * ((i + b) % 3) / 2), at(b, s), 0.11, 0.55)

# The lead: a four-bar tune, a variation, and back. Sixteenths in the phrase: (step, length, note).
TUNE_A = [(0, 6, 84), (6, 2, 87), (8, 4, 84), (12, 2, 82), (14, 2, 80), (16, 8, 77), (26, 2, 80), (28, 2, 82), (30, 2, 84),
          (32, 6, 80), (38, 2, 84), (40, 4, 87), (44, 4, 89), (48, 4, 87), (52, 2, 84), (54, 2, 82), (56, 7, 84)]
TUNE_B = [(0, 4, 89), (4, 2, 87), (6, 2, 84), (8, 6, 87), (14, 2, 84), (16, 6, 82), (22, 2, 80), (24, 7, 77),
          (32, 4, 80), (36, 4, 84), (40, 7, 82), (48, 6, 79), (54, 2, 82), (56, 7, 84)]
for start, tune, bars in ((4, TUNE_A, 4), (8, TUNE_B, 4), (12, TUNE_A, 4), (16, TUNE_B, 4), (ENDBAR, TUNE_A, 2)):
    notes = [(s * STEP + (SWING if s % 2 else 0), n * STEP * 0.9, m) for s, n, m in tune if s < bars * 16]
    lead.add(lead_line(notes, bars * BAR), start * BAR, 0.12)

for b in (1, 4, 8, 12, 16, ENDBAR):
    drums.add(CR, at(b, 0), 0.16)
drums.add(K, at(LAST, 0), 1.0)
drums.add(CR, at(LAST, 0), 0.22)
fx.add(riser(1.6), BAR - 1.6, 0.16)                 # into the first beat of the groove
fx.add(riser(2.5), BREAK[1] * BAR, 0.24)            # out of the quiet bars
for i in range(8):                                  # a snare roll back into the groove
    drums.add(S, at(BREAK[1], 14) - (7 - i) * STEP / 2, 0.14 + 0.04 * i, -0.2 + 0.05 * i)


def echo(bus, delay, fb=0.36, mix=0.28):
    d = int(delay * SR)
    for src, dst in ((bus.l.copy(), bus.r), (bus.r.copy(), bus.l)):
        g = mix
        for k in range(1, 4):
            dst[k * d:] += src[:-k * d] * g
            g *= fb


echo(lead, BEAT * 0.75, 0.4, 0.3)
echo(guitar, BEAT * 0.5, 0.25, 0.2)

# ------------------------------------------------------------------ what happens on screen
START = {name: a for name, a, b in C.SCENES}
fx.add(tom(58) * 1.2, 0.0, 0.8)                                 # the first image lands
fx.add(whoosh(0.9, 200, 3000, True), 0.0, 0.18)
for i in range(60):                                             # places appearing on the map
    tt = 0.4 + (START["map"] + 1.0) * rng.uniform() ** 0.9
    fx.add(blip(hz([72, 75, 77, 80, 84][i % 5]), 0.07), tt, 0.06, rng.uniform(-0.7, 0.7))
for name, a, b in C.SCENES[1:]:
    fx.add(whoosh(0.5, 400, 6000, True), a - 0.2, 0.12)
for i, tt in enumerate(C.VOTES):                                # a vote on a rare vehicle
    fx.add(blip(hz(77 + 7 * i), 0.16), tt, 0.2, 0.2)
    fx.add(tom(140), tt, 0.2)
fx.add(whoosh(0.7, 300, 5000, False), C.SPOILER, 0.2)           # the later chapters blur
fx.add(blip(1500, 0.05, "square"), C.SPOILER + 0.4, 0.1)
steps = int((C.RING_FULL - C.RING_START) / STEP)                # the ring fills
for i in range(steps):
    fx.add(blip(hz(65 + i * 1.4), 0.06), C.RING_START + i * STEP, 0.04 + 0.004 * i, 0.3)
for m, g in ((77, 0.2), (80, 0.16), (84, 0.16), (89, 0.12)):
    fx.add(bell(hz(m)), C.RING_FULL, g, 0.2)
for i, tt in enumerate(C.CHEAT_KEYS):                           # a cheat code, button after button
    fx.add(blip(hz([65, 65, 68, 70, 72, 75, 77, 75, 77, 80][i]), 0.09, "square"), tt, 0.12, -0.4 + 0.08 * i)
for i, m in enumerate((77, 84, 89)):
    fx.add(bell(hz(m), 0.9), C.CHEAT_KEYS[-1] + 0.2 + i * 0.06, 0.12)
fx.add(whoosh(1.1, 250, 2500, True), C.UNFOLD, 0.15)            # the Duo opens
fx.add(tom(75), C.UNFOLD + 1.05, 0.45)
for tt in C.TRUST_LINES:                                        # one line per beat
    drums.add(K, tt, 0.9)
    drums.add(CL, tt, 0.35)
for i, tt in enumerate(C.TRUST_CARDS):
    fx.add(blip(hz(77 + [0, 7][i]), 0.18), tt, 0.2, -0.2 + 0.4 * i)
    fx.add(tom(140), tt, 0.22)
for m, g in ((65, 0.16), (72, 0.14), (77, 0.14), (80, 0.1), (84, 0.09)):
    fx.add(bell(hz(m), 2.4), C.END_ICON, g)
fx.add(bell(hz(89), 1.2), C.END_CTA, 0.14)
fx.add(bell(hz(84), 1.2), C.END_CTA, 0.11)


# ------------------------------------------------------------------ mix
def room(bus, wet):
    n = int(1.3 * SR)
    for chn, seed in (("l", 1), ("r", 2)):
        ir = np.random.default_rng(seed).standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.26))
        ir = filt(ir, "low", 6000)
        ir /= np.sqrt(np.sum(ir ** 2))
        x = getattr(bus, chn)
        setattr(bus, chn, x + fftconvolve(x, ir)[:N] * wet)


# A slow tremolo on the electric piano, left to right.
t = np.arange(N) / SR
keys.l *= 1 + 0.22 * np.sin(2 * np.pi * 4.6 * t)
keys.r *= 1 - 0.22 * np.sin(2 * np.pi * 4.6 * t)
room(lead, 0.25)
room(keys, 0.16)
room(fx, 0.2)
room(guitar, 0.12)
L = drums.l * 0.95 + bass.l * 0.9 + keys.l + guitar.l + lead.l + fx.l
R = drums.r * 0.95 + bass.r * 0.9 + keys.r + guitar.r + lead.r + fx.r
gain = np.ones(N)
gain[:int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))
tail = int(1.6 * SR)
gain[-tail:] = np.linspace(1, 0, tail) ** 1.5
mix = np.stack([L, R], axis=1) * gain[:, None]
mix = filt(mix.T, "high", 28).T
mix = np.tanh(mix * 1.15 / np.percentile(np.abs(mix), 99.9))    # glue, and no clipping
mix = mix / np.max(np.abs(mix)) * 0.89
out = os.path.join(sys.argv[1], "music.wav")


def save(x):
    with wave.open(out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def loudness():
    import re
    import subprocess
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", out, "-filter_complex", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s*(-?[\d.]+) LUFS", log)[-1])


# Feeds play everything at about the same level: aim for -14 LUFS, never above -1 dBFS.
save(mix)
now = loudness()
mix = mix * min(10 ** ((-14 - now) / 20), 0.89 / np.max(np.abs(mix)))
save(mix)
print(out, f"{N / SR:.1f} s, {now:.1f} -> {loudness():.1f} LUFS")
