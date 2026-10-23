"""Chronologie commune à l'image et au son de la vidéo de présentation."""
SCENES = [("hook", 0.0, 2.8), ("rayon", 2.8, 5.6), ("chess", 5.6, 8.8), ("piano", 8.8, 11.8),
          ("filet", 11.8, 14.2), ("hockey", 14.2, 16.6), ("ferme", 16.6, 19.0), ("grid", 19.0, 21.6), ("end", 21.6, 25.0)]
DURATION = 25.0
RAYON_HITS = [3.6, 4.6]
CHESS_MOVES = [(6.15, "e2e4"), (6.75, "e7e5"), (7.35, "g1f3"), (7.95, "b8c6")]
PIANO = [(9.2 + i * 0.22, m) for i, m in enumerate([76, 76, 77, 79, 79, 77, 76, 74, 72, 72, 74])]
# Balle de ping-pong : (temps, x 0-1, v 0-1 sur l'écran entier, hauteur), et le son à cet instant
FILET = [(11.9, 0.55, 0.86, 0.10, "pok"), (12.25, 0.38, 0.30, 0.0, "tock"), (12.55, 0.42, 0.15, 0.12, "pok"),
         (12.9, 0.66, 0.70, 0.0, "tock"), (13.2, 0.62, 0.87, 0.10, "pok"), (13.55, 0.30, 0.28, 0.0, "tock"),
         (13.85, 0.30, 0.14, 0.14, "smash"), (14.2, 0.70, 0.95, 0.30, None)]
# Palet : (temps, x, v) ; chaque point est un choc
HOCKEY = [(14.25, 0.50, 0.70, "puck"), (14.55, 0.95, 0.42, "puck"), (14.85, 0.56, 0.16, "puck"), (15.15, 0.05, 0.36, "puck"),
          (15.5, 0.44, 0.72, "puck"), (15.8, 0.94, 0.48, "puck"), (16.1, 0.55, -0.04, "goal")]
FERME_CLOSE = 17.25
FERME_BLOOM = 18.45
GRID_POPS = [19.25 + i * 0.13 for i in range(13)]
END_WIN = 21.95
