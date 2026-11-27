"""VICEFOLD promo video: the soundtrack (python3 audio.py <work dir> -> music.wav).

An original synth track at 120 BPM written here, note by note (A minor: Am, F, C, G), plus the sounds of what happens
on screen, all placed from cues.py. Nothing is sampled from a game or a record.
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cues as C

SR = 44100
N = int(C.DURATION * SR)
BEAT, BAR = C.BEAT, 4 * C.BEAT
rng = np.random.default_rng(6)


def ax(dur):
    return np.arange(int(dur * SR)) / SR


def filt(x, kind, fc, order=2):
    fc = np.clip(np.asarray(fc, dtype=float), 20, SR / 2 - 200) / (SR / 2)
    return sosfilt(butter(order, fc, btype=kind, output="sos"), x)


def hz(semi):
    """Semitones from A4."""
    return 440 * 2 ** (semi / 12)


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


def saw(f, dur, voices=(0.0,), phase=None):
    t = ax(dur)
    out = np.zeros_like(t)
    for d in voices:
        ph = rng.uniform(0, 1) if phase is None else phase
        out += 2 * ((t * f * 2 ** (d / 12) + ph) % 1) - 1
    return out / len(voices)


# ------------------------------------------------------------------ drums
def kick():
    t = ax(0.42)
    f = 46 + 110 * np.exp(-t * 28)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    click = filt(rng.standard_normal(len(t)), "high", 2500) * np.exp(-t * 400) * 0.25
    return np.tanh((body + click) * 1.6)


def snare():
    t = ax(0.34)
    noise = filt(rng.standard_normal(len(t)), "band", [220, 9000])
    gate = np.where(t < 0.2, 1.0, np.exp(-(t - 0.2) * 60))      # the 80s gated tail
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 26) + 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-t * 34)
    return (noise * (np.exp(-t * 20) * 0.9 + 0.28) * gate + tone * 0.7) * 0.9


def hat(open_=False):
    t = ax(0.2 if open_ else 0.06)
    return filt(rng.standard_normal(len(t)), "high", 7500) * np.exp(-t * (22 if open_ else 110))


def crash():
    t = ax(2.2)
    return filt(rng.standard_normal(len(t)), "high", 4500) * np.exp(-t * 2.4) * np.minimum(1, t / 0.004)


def tom(f=110):
    t = ax(0.4)
    fr = f * (1 + 0.6 * np.exp(-t * 22))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 9)


# ------------------------------------------------------------------ synths
def bass_note(f, dur):
    t = ax(dur)
    sig = saw(f, dur, (0.0,), 0.0) * 0.7 + np.sign(np.sin(2 * np.pi * f * t)) * 0.35 + np.sin(2 * np.pi * f * t) * 0.8
    sig = filt(sig, "low", 520, 4)
    return sig * np.minimum(1, t / 0.004) * np.exp(-t * 2.6) * np.minimum(1, (dur - t) / 0.02)


def pad_chord(freqs, dur, cutoff):
    t = ax(dur)
    sig = sum(saw(f, dur, (-0.14, 0.0, 0.13)) for f in freqs) / len(freqs)
    sig = filt(sig, "low", cutoff, 2)
    return sig * np.minimum(1, t / 0.12) * np.minimum(1, (dur - t) / 0.25)


def pluck(f, dur=0.32, bright=1.0):
    t = ax(dur)
    sig = saw(f, dur, (-0.07, 0.07))
    lo = filt(sig, "low", 900)
    hi = filt(sig, "low", 5200 * bright)
    env = np.exp(-t * 16)
    return (lo * (1 - env) + hi * env) * np.exp(-t * 9) * np.minimum(1, t / 0.002)


def lead_note(f, dur):
    t = ax(dur + 0.12)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.25)
    ph = np.cumsum(f * vib) / SR
    sig = (2 * (ph % 1) - 1) * 0.6 + np.sign(np.sin(2 * np.pi * ph * 1.003)) * 0.3
    sig = filt(sig, "low", 3600, 2)
    return sig * np.minimum(1, t / 0.012) * np.minimum(1, np.maximum(0, (dur + 0.12 - t) / 0.12))


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
    noise = whoosh(dur, 300, 9000, True) * (t / dur) ** 1.5 * 2
    tone = np.sin(2 * np.pi * np.cumsum(180 * 2 ** (2 * t / dur)) / SR) * (t / dur) ** 2 * 0.25
    return noise + tone


# ------------------------------------------------------------------ the track
drums, bass, pad, arp, lead, fx = Bus(), Bus(), Bus(), Bus(), Bus(), Bus()
CHORDS = [[0, 3, 7], [-4, 0, 3], [3, 7, 10], [-2, 2, 5]]     # Am, F, C, G (semitones from A)
ROOTS = [-24, -28, -21, -26]                                  # A2, F2, C3, G2 ... one octave lower when played
K, S, H, HO, CR = kick(), snare(), hat(), hat(True), crash()
BARS = int(C.DURATION / BAR)
BREAK = (16, 17)                 # bars 32-36 s: the "no account, no ads" breath
# 8 eighth notes a bar; None is a rest. A small tune that comes back every four bars.
TUNE = [[(19, 2), (24, 1), (22, 1), (19, 2), (15, 2)], [(17, 3), (15, 1), (12, 4)],
        [(19, 2), (22, 1), (19, 1), (17, 2), (15, 2)], [(17, 3), (14, 1), (17, 4)]]

for b in range(BARS):
    t0 = b * BAR
    ch, root = CHORDS[b % 4], ROOTS[b % 4]
    intro, brk, last = b < 2, b in BREAK, b == BARS - 1
    full = not intro and not brk and not last
    # drums
    if full or b == 1:
        for q in range(4):
            drums.add(K, t0 + q * BEAT, 0.78)
            if full and q in (1, 3):
                drums.add(S, t0 + q * BEAT, 0.5, 0.05)
        if full:
            for e in range(8):
                drums.add(HO if e % 2 else H, t0 + e * BEAT / 2, 0.11 if e % 2 else 0.07, -0.25 if e % 2 else 0.25)
            for s16 in (3, 7, 11, 15):
                drums.add(H, t0 + s16 * BEAT / 4, 0.035, 0.3)
    # a snare roll into every fourth bar and out of the quiet bars
    if (b % 4 == 3 and full) or b == 1 or b == BREAK[1]:
        for i in range(8):
            drums.add(S, t0 + BAR - BEAT + i * BEAT / 8, 0.16 + 0.05 * i, -0.2 + 0.05 * i)
    # bass: eighth notes, root and octave
    if full:
        for e in range(8):
            octv = 12 if e in (3, 6) else 0
            bass.add(bass_note(hz(root + octv), BEAT / 2 * 0.95), t0 + e * BEAT / 2, 0.38)
    elif intro or last:
        bass.add(bass_note(hz(root), BAR * 0.98) * 0.9, t0, 0.34)
    # pad: it opens during the first two bars
    cutoff = 1000 + 800 * b if intro else (1700 if brk else 2400)
    pad.add(pad_chord([hz(n - 12) for n in ch] + [hz(ch[0])], BAR * (2.0 if last else 1.02), cutoff), t0, 0.3 if not last else 0.36)
    # arpeggio in sixteenth notes
    if not last:
        order = [0, 1, 2, 1, 0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1]
        for i in range(16):
            n = ch[order[i]] + (12 if i % 8 >= 4 else 0)
            g = (0.12 if intro else 0.14 if brk else 0.17) * (1.0 if i % 4 == 0 else 0.75)
            arp.add(pluck(hz(n), 0.3, 0.65 + 0.3 * b if intro else 1.0), t0 + i * BEAT / 4, g, -0.5 if i % 2 else 0.5)
    # the tune
    if (4 <= b < BREAK[0]) or b in (18, 19):
        t = t0
        for semi, eighths in TUNE[b % 4]:
            lead.add(lead_note(hz(semi), eighths * BEAT / 2 * 0.92), t, 0.2)
            t += eighths * BEAT / 2

for t in (2.0, 4.0, 12.0, 20.0, 28.0, 36.0):
    drums.add(CR, t, 0.2 if t != 36.0 else 0.3)
drums.add(K, 36.0, 1.0)
drums.add(K, 40.0, 1.0)
drums.add(CR, 40.0, 0.22)
fx.add(riser(2.0), 2.0, 0.2)
fx.add(riser(2.0), 34.0, 0.26)

# echo for the arpeggio and the tune (dotted eighth, left then right)
def echo(bus, delay=0.375, fb=0.38, mix=0.32):
    d = int(delay * SR)
    for src, dst in ((bus.l.copy(), bus.r), (bus.r.copy(), bus.l)):
        g = mix
        for k in range(1, 4):
            dst[k * d:] += src[:-k * d] * g if k * d < N else 0
            g *= fb


echo(arp)
echo(lead, 0.375, 0.4, 0.3)

# the kick pushes the rest down a little on every beat (the "pump")
t = np.arange(N) / SR
pump = 1 - 0.55 * np.exp(-((t % BEAT) / 0.11))
on = np.zeros(N)
for b in range(BARS):
    if 2 <= b < BREAK[0] or b in (18, 19):
        on[int(b * BAR * SR):int((b + 1) * BAR * SR)] = 1
pump = 1 - (1 - pump) * on
for bus in (bass, pad, arp):
    bus.l *= pump
    bus.r *= pump

# ------------------------------------------------------------------ what happens on screen
fx.add(tom(60) * 1.2, 0.0, 0.8)                                 # the first image lands
fx.add(whoosh(0.9, 200, 3000, True), 0.0, 0.2)
for semi, g in ((0, 0.14), (7, 0.1), (12, 0.1), (19, 0.07)):
    fx.add(bell(hz(semi), 2.0), 0.02, g)
for i in range(46):                                             # places appearing on the map
    tt = 0.4 + 3.2 * rng.uniform() ** 0.9
    fx.add(blip(hz([12, 15, 19, 24, 27][i % 5]), 0.07), tt, 0.085, rng.uniform(-0.7, 0.7))
for name, a, b in C.SCENES[1:]:
    fx.add(whoosh(0.42, 400, 7000, True), a - 0.16, 0.17, 0.0)
fx.add(whoosh(0.6, 300, 5000, False), C.SPOILER, 0.22)          # the later chapters blur
fx.add(blip(1500, 0.05, "square"), C.SPOILER + 0.32, 0.12)
steps = int((C.RING_FULL - C.RING_START) / (BEAT / 4))          # the ring fills
for i in range(steps):
    fx.add(blip(hz(-12 + i * 1.3), 0.06), C.RING_START + i * BEAT / 4, 0.05 + 0.004 * i, 0.3)
for semi, g in ((12, 0.2), (16, 0.16), (19, 0.16), (24, 0.12)):
    fx.add(bell(hz(semi)), C.RING_FULL, g, 0.2)
for i, tt in enumerate(C.CHEAT_KEYS):                           # a cheat code, button after button
    fx.add(blip(hz([0, 0, 3, 5, 7, 10, 12, 10, 12, 15][i] + 12), 0.08, "square"), tt, 0.13, -0.4 + 0.08 * i)
for i, semi in enumerate((12, 19, 24)):
    fx.add(bell(hz(semi), 0.9), C.CHEAT_KEYS[-1] + 0.14 + i * 0.05, 0.13)
fx.add(filt(rng.standard_normal(int(0.22 * SR)), "band", [900, 4200]) * np.linspace(1, 0, int(0.22 * SR)), 20.0, 0.1)   # the radio turns on
fx.add(whoosh(0.9, 250, 2500, True), C.UNFOLD, 0.16)            # the Duo opens
fx.add(tom(75), C.UNFOLD + 0.86, 0.5)
for tt in C.TRUST_LINES:
    fx.add(tom(70) * 1.1, tt, 0.75)
    fx.add(S, tt, 0.3)
for i, tt in enumerate(C.TRUST_CARDS):
    fx.add(blip(hz(12 + [0, 3, 7, 12][i]), 0.16), tt, 0.22, -0.3 + 0.2 * i)
    fx.add(tom(140), tt, 0.25)
for semi, g in ((0, 0.2), (7, 0.16), (12, 0.16), (15, 0.12), (19, 0.1)):
    fx.add(bell(hz(semi), 2.4), C.END_ICON, g)
fx.add(bell(hz(24), 1.2), C.END_CTA, 0.16)
fx.add(bell(hz(19), 1.2), C.END_CTA, 0.12)

# ------------------------------------------------------------------ mix
def room(bus, wet):
    n = int(1.3 * SR)
    for ch, seed in (("l", 1), ("r", 2)):
        ir = np.random.default_rng(seed).standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.26))
        ir = filt(ir, "low", 6000)
        ir /= np.sqrt(np.sum(ir ** 2))
        x = getattr(bus, ch)
        setattr(bus, ch, x + fftconvolve(x, ir)[:N] * wet)


room(lead, 0.22)
room(arp, 0.12)
room(fx, 0.2)
room(pad, 0.15)
L = drums.l * 0.9 + bass.l * 0.9 + pad.l + arp.l + lead.l + fx.l
R = drums.r * 0.9 + bass.r * 0.9 + pad.r + arp.r + lead.r + fx.r
gain = np.ones(N)
gain[:int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))
tail = int(1.4 * SR)
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
