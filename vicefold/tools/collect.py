"""VICEFOLD : rassemble les captures du simulateur (branches ci-vicefold-shots-*) pour compose.py.

Usage : python3 collect.py <brutes>
Écrit <brutes>/<appareil>-<lang>/NN-<écran>.png (appareil : duo, iphone, ipad) et <brutes>/cover-<lang>/NN-<écran>.png
(l'écran extérieur du Duo fermé).
"""
import os
import subprocess
import sys

RAW = sys.argv[1]
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SETS = [
    # (branche, dossier, suffixe du fichier : -dprimary-1 = écran intérieur du Duo, -dprimary = écran principal)
    ("ci-vicefold-shots-{l}", "duo-{l}", "-dprimary-1.png"),
    ("ci-vicefold-shots-{l}-iphone17promax", "iphone-{l}", "-dprimary.png"),
    ("ci-vicefold-shots-{l}-ipadpro13", "ipad-{l}", "-dprimary.png"),
    ("ci-vicefold-shots-{l}-closed", "cover-{l}", "-dprimary.png"),
]


def git(*a, binary=False):
    return subprocess.run(["git", "-C", REPO, *a], check=True, capture_output=True, text=not binary).stdout


for lang in ("en", "fr"):
    for branch, folder, suffix in SETS:
        b = branch.format(l=lang)
        try:
            git("fetch", "-q", "origin", b)
        except subprocess.CalledProcessError:
            print("pas de branche", b)
            continue
        names = [n for n in git("ls-tree", "--name-only", f"origin/{b}").split("\n") if n.endswith(suffix)]
        if suffix == "-dprimary.png":
            names = [n for n in names if not n.endswith("-dprimary-1.png")]
        d = os.path.join(RAW, folder.format(l=lang))
        os.makedirs(d, exist_ok=True)
        for n in names:
            with open(os.path.join(d, n.replace(suffix, ".png")), "wb") as f:
                f.write(git("show", f"origin/{b}:{n}", binary=True))
        print(b, "→", d, len(names))
