"""Les deux sons de Clapet : « clap » quand on ferme le Duo, « pop » quand on l'ouvre.

Usage : python3 clapet/tools/sounds.py   (écrit clapet/Clapet/Sounds/clap.wav et pop.wav)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import sound_design as sd  # noqa: E402

sd.OUT = os.path.join(HERE, "..", "Clapet", "Sounds")
os.makedirs(sd.OUT, exist_ok=True)

# Clap : un claquement de bois sec, un petit coup sourd dessous et une pointe de bruit, comme deux mains.
dur = 0.22
t = sd.t_axis(dur)
snap = sd.bandpass(sd.rng.standard_normal(len(t)) * np.exp(-140 * t), 900, 5200)
clap = sd.mix((sd.wood(700, dur, body=0.8), 0, 0.9), (sd.thump(190, 70, dur), 0, 0.7), (snap, 0, 1.1))
sd.write("clap", clap, gain=0.85, rev=(0.5, 0.12, 6000))

# Pop : une petite note ronde qui remonte, comme un bouchon.
dur = 0.18
t = sd.t_axis(dur)
freq = 520 + 520 * (1 - np.exp(-30 * t))
phase = 2 * np.pi * np.cumsum(freq) / sd.SR
pop = np.sin(phase) * np.exp(-26 * t) * np.clip(t / 0.002, 0, 1)
pop = sd.mix((pop, 0, 1.0), (sd.kalimba(sd.hz("G", 5), dur), 0, 0.4))
sd.write("pop", pop, gain=0.6, rev=(0.4, 0.1, 7000))
print("ok", sorted(os.listdir(sd.OUT)))
