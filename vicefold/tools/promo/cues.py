"""VICEFOLD promo video: one timeline for the picture and the sound (120 BPM, a bar is 2 s)."""
BPM = 120
BEAT = 60 / BPM
SCENES = [
    ("hook", 0, 2), ("intro", 2, 4), ("map", 4, 8), ("missions", 8, 12), ("tracker", 12, 16),
    ("eggs", 16, 18), ("cheats", 18, 20), ("radio", 20, 22), ("cast", 22, 24), ("community", 24, 26),
    ("widgets", 26, 28), ("devices", 28, 32), ("trust", 32, 36), ("end", 36, 42),
]
DURATION = 42.0
# Moments the sound follows (seconds from the start).
SPOILER = 10.0            # the later chapters blur
RING_START, RING_FULL = 12.6, 15.0   # the 100% ring fills, and lands on a beat
CHEAT_KEYS = [18.25 + i * 0.125 for i in range(10)]   # the buttons of a cheat code, on sixteenth notes
UNFOLD = 28.25            # the iPhone Duo opens
TRUST_LINES = [32.0, 32.5, 33.0]
TRUST_CARDS = [33.5, 34.0, 34.5, 35.0]
END_ICON = 36.0
END_CTA = 37.5
