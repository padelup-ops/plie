"""Rend le film du guide : python3 render.py SORTIE.mp4 [instants…]
Sans instants : toutes les images (30 par seconde), la bande-son, puis l'assemblage avec ffmpeg.
Avec des instants (en secondes) : seulement ces images, dans DOSSIER_DE_SORTIE/essais, pour vérifier un plan."""
import os, subprocess, sys, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FPS, DURATION, SR = 30, 39.5, 44100
BEAT = 0.625                      # 96 battements par minute : une étape dure 4 temps
STEPS_AT, STEP = 8.75, 2.5


def frames(folder, times):
    """Les images sont prises par frames.js (Playwright pour Node)."""
    subprocess.run(["node", os.path.join(HERE, "frames.js"), folder] + [str(t) for t in times], check=True)


def tone(freq, dur, kind="sine"):
    t = np.arange(int(dur * SR)) / SR
    if kind == "sine":
        return np.sin(2 * np.pi * freq * t)
    return sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 7)) * 0.6   # timbre plus riche


def env(n, attack, release):
    e = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r) ** 2
    return e


def soundtrack(path):
    """Musique originale : nappe d'accords, arpège, grosse caisse douce, et un « pop » à chaque étape."""
    n = int(DURATION * SR)
    mix = np.zeros(n)

    def put(sig, at, gain):
        i = int(at * SR)
        if i >= n:
            return
        j = min(n, i + len(sig))
        mix[i:j] += sig[: j - i] * gain

    note = lambda semis: 220.0 * 2 ** (semis / 12)          # la3 = 0
    chords = [[0, 3, 7], [-4, 0, 3], [-9, -5, 0], [-2, 2, 5]]  # la mineur, fa, do, sol
    bar = 4 * BEAT
    for k in range(int(DURATION / bar) + 1):
        chord = chords[k % 4]
        at = k * bar
        for s in chord:                                       # nappe
            sig = tone(note(s) / 2, bar * 1.05) + 0.5 * tone(note(s), bar * 1.05)
            put(sig * env(len(sig), 0.4, 0.6), at, 0.045)
        if at >= 5:                                           # arpège dès le deuxième plan
            for e in range(8):
                s = chord[e % 3] + (12 if e % 4 == 3 else 0)
                sig = tone(note(s), 0.28, "rich")
                put(sig * env(len(sig), 0.005, 0.24), at + e * BEAT / 2, 0.035)
        if STEPS_AT <= at < 32.5:                             # grosse caisse pendant les étapes
            for bt in range(4):
                t = np.arange(int(0.22 * SR)) / SR
                kick = np.sin(2 * np.pi * (48 * t + 60 * (1 - np.exp(-t * 28)) / 28)) * np.exp(-t * 16)
                put(kick, at + bt * BEAT, 0.32)
    for i in range(8):                                        # le « pop » de chaque étape
        sig = tone(note(12 + [0, 3, 7, 12][i % 4]), 0.16) * env(int(0.16 * SR), 0.003, 0.14)
        put(sig, STEPS_AT + i * STEP + 0.15, 0.16)
    final = sum(tone(note(s), 4.5) for s in (0, 7, 12, 16))   # accord final qui s'éteint
    put(final * env(len(final), 0.02, 4.0), 33.9, 0.05)
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)
    mix[: int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))
    mix = np.tanh(mix * 1.6) * 0.8
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((mix * 32767).astype("<i2").tobytes())


def main():
    out = os.path.abspath(sys.argv[1])
    work = os.path.join(os.path.dirname(out), "film-travail")
    if len(sys.argv) > 2:
        frames(os.path.join(work, "essais"), [float(t) for t in sys.argv[2:]])
        return
    frames(os.path.join(work, "images"), ["tout"])
    soundtrack(os.path.join(work, "son.wav"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(work, "images", "f%05d.jpg"),
                    "-i", os.path.join(work, "son.wav"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "21", "-preset", "slow",
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", "-shortest", out], check=True)
    print(out, os.path.getsize(out) // 1024, "Ko")


if __name__ == "__main__":
    main()
