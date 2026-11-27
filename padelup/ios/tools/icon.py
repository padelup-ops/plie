"""PADELUP NEO : l'icône, épurée. Fond bleu PadelUp (#094A73), terrain de padel vu du dessus au trait blanc,
une balle jaune. À plat : ni dégradé ni halo. Usage : python3 tools/icon.py"""
import math
import os

from PIL import Image, ImageDraw

S = 2048
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'App', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')
BLUE, WHITE, BALL = (9, 74, 115), (255, 255, 255), (217, 242, 74)

img = Image.new('RGB', (S, S), BLUE)
d = ImageDraw.Draw(img)
W = int(S * 0.026)

# terrain vu du dessus (20 m x 10 m), légèrement décalé vers la gauche pour laisser respirer la balle
cw, ch = S * 0.36, S * 0.66
x0, y0 = S * 0.5 - cw / 2 - S * 0.04, S * 0.5 - ch / 2
x1, y1 = x0 + cw, y0 + ch
d.rounded_rectangle([x0, y0, x1, y1], radius=S * 0.03, outline=WHITE, width=W)
net = (y0 + y1) / 2
d.line([x0 - S * 0.03, net, x1 + S * 0.03, net], fill=WHITE, width=int(W * 1.6))
service = ch / 2 * 0.695
for y in (net - service, net + service):
    d.line([x0, y, x1, y], fill=WHITE, width=W)
cx = (x0 + x1) / 2
d.line([cx, net - service, cx, net + service], fill=WHITE, width=W)

# la balle, coutures découpées au contour de la balle
bx, by, br = x1 + S * 0.02, y0 + S * 0.12, S * 0.105
d.ellipse([bx - br - S * 0.02, by - br - S * 0.02, bx + br + S * 0.02, by + br + S * 0.02], fill=BLUE)
ball = Image.new('RGB', (S, S), BALL)
bd = ImageDraw.Draw(ball)
seam = int(S * 0.016)
bd.arc([bx - br * 1.75, by - br * 0.95, bx - br * 0.18, by + br * 0.95], start=-60, end=60, fill=WHITE, width=seam)
bd.arc([bx + br * 0.18, by - br * 0.95, bx + br * 1.75, by + br * 0.95], start=120, end=240, fill=WHITE, width=seam)
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).ellipse([bx - br, by - br, bx + br, by + br], fill=255)
img.paste(ball, (0, 0), mask)

img = img.resize((1024, 1024), Image.LANCZOS)
img.save(OUT, optimize=True)
print('icône écrite :', OUT)
