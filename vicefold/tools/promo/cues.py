"""VICEFOLD promo video: one timeline for the picture and the sound (96 BPM, a bar is 2.5 s).

One idea per scene, and time to read it: a scene lasts a bar and a half or two bars.
"""
BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
SCENES = [
    ("hook", 0, 2.5), ("intro", 2.5, 6.25), ("map", 6.25, 11.25), ("missions", 11.25, 16.25), ("spoiler", 16.25, 20.0),
    ("tracker", 20.0, 25.0), ("eggs", 25.0, 28.75), ("cheats", 28.75, 32.5), ("community", 32.5, 36.25),
    ("widgets", 36.25, 40.0), ("devices", 40.0, 45.0), ("trust", 45.0, 50.0), ("end", 50.0, 57.5),
]
DURATION = 57.5
# Moments the sound follows (seconds from the start), all on beats.
SPOILER = 17.5                        # the later chapters blur
RING_START, RING_FULL = 20.9, 23.125  # the 100% ring fills, and lands on a beat
CHEAT_KEYS = [29.0625 + i * BEAT / 2 for i in range(10)]   # the buttons of a cheat code, on eighth notes
UNFOLD = 40.625                       # the iPhone Duo opens
TRUST_LINES = [45.0, 45.625, 46.25]
TRUST_CARDS = [47.5, 48.125]
END_ICON = 50.0
END_CTA = 52.5
