"""VICEFOLD promo video: one timeline for the picture and the sound (96 BPM, a bar is 2.5 s).

One idea per scene, and time to read it: a scene lasts a bar and a half or two bars.
"""
BPM = 96
BEAT = 60 / BPM
BAR = 4 * BEAT
SCENES = [
    ("hook", 0, 2.5), ("intro", 2.5, 6.25), ("map", 6.25, 11.25), ("cars", 11.25, 16.25), ("votes", 16.25, 20.0),
    ("missions", 20.0, 25.0), ("spoiler", 25.0, 28.75), ("tracker", 28.75, 33.75), ("eggs", 33.75, 37.5),
    ("cheats", 37.5, 41.25), ("community", 41.25, 45.0), ("devices", 45.0, 50.0), ("trust", 50.0, 55.0), ("end", 55.0, 62.5),
]
DURATION = 62.5
# Moments the sound follows (seconds from the start), all on beats.
VOTES = [17.5, 18.125]                # "It's here", then the count goes up
SPOILER = 26.25                       # the later chapters blur
RING_START, RING_FULL = 29.65, 31.875  # the 100% ring fills, and lands on a beat
CHEAT_KEYS = [37.8125 + i * BEAT / 2 for i in range(10)]   # the buttons of a cheat code, on eighth notes
UNFOLD = 45.625                       # the iPhone Duo opens
TRUST_LINES = [50.0, 50.625, 51.25]
TRUST_CARDS = [52.5, 53.125]
END_ICON = 55.0
END_CTA = 57.5
