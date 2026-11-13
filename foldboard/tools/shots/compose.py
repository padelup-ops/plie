"""Compose les captures de l'App Store de Foldboard : un titre, puis la vraie capture du simulateur.

Usage : python3 compose.py <dossier des captures brutes> <dossier de sortie>
Entrées : duo-<lang>-0N-<écran>-in.png (écran déplié) et -out.png (écran extérieur).
Sorties : duo-<lang>-N.png (2007×2853, iPhone Duo) et <lang>-N.png (1290×2796, iPhone 6,7").
"""
import base64, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
ROUTES = ["right", "split", "clip", "calib", "themes", "pro"]
# Langue de la capture brute → nom des fichiers de la fiche (pt-BR → pt, comme les fiches pt-BR / pt-PT).
FILE = {"pt-BR": "pt"}
C = {
    "en": [("It comes to the side", "of your hand"), ("Both hands on the Duo?", "It splits in two"), ("Full width on", "the outer screen"),
           ("Everything you copy,", "one tap away"), ("Teach it your thumbs", "in 30 seconds"), ("Colors, fonts,", "sounds and haptics"), ("Free 3-day", "trial")],
    "fr": [("Il vient du côté", "de ta main"), ("À deux mains sur le Duo,", "il se coupe en deux"), ("Pleine largeur sur", "l’écran extérieur"),
           ("Tout ce que tu copies,", "à un toucher"), ("Apprends-lui tes pouces", "en 30 secondes"), ("Couleurs, polices,", "sons et vibrations"), ("Essai gratuit", "de 3 jours")],
    "de": [("Er kommt zur Seite", "deiner Hand"), ("Beide Hände am Duo?", "Er teilt sich in zwei"), ("Volle Breite auf", "dem Außendisplay"),
           ("Alles, was du kopierst,", "mit einem Tippen"), ("Bring ihm deine Daumen bei", "in 30 Sekunden"), ("Farben, Schriften,", "Töne und Haptik"), ("3 Tage", "gratis testen")],
    "es": [("Va al lado", "de tu mano"), ("¿Dos manos en el Duo?", "Se divide en dos"), ("Ancho completo en", "la pantalla exterior"),
           ("Todo lo que copias,", "a un toque"), ("Enséñale tus pulgares", "en 30 segundos"), ("Colores, fuentes,", "sonidos y vibración"), ("Prueba gratis", "de 3 días")],
    "it": [("Va dal lato", "della tua mano"), ("Due mani sul Duo?", "Si divide in due"), ("Larghezza piena sullo", "schermo esterno"),
           ("Tutto ciò che copi,", "a un tocco"), ("Insegnale i tuoi pollici", "in 30 secondi"), ("Colori, font,", "suoni e vibrazioni"), ("Prova gratuita", "di 3 giorni")],
    "nl": [("Hij komt naar de kant", "van je hand"), ("Twee handen op de Duo?", "Hij splitst in tweeën"), ("Volle breedte op", "het buitenscherm"),
           ("Alles wat je kopieert,", "met één tik"), ("Leer hem je duimen", "in 30 seconden"), ("Kleuren, lettertypen,", "geluid en trillen"), ("3 dagen", "gratis proberen")],
    "pt-BR": [("Ele vai para o lado", "da sua mão"), ("Duas mãos no Duo?", "Ele se divide em dois"), ("Largura total na", "tela externa"),
              ("Tudo o que você copia,", "a um toque"), ("Ensine seus polegares", "em 30 segundos"), ("Cores, fontes,", "sons e vibração"), ("Teste grátis", "de 3 dias")],
    "ja": [("持つ手の側に", "キーボードが来る"), ("Duoを両手で？", "2つに分かれます"), ("外側の画面では", "全幅に"),
           ("コピーした内容を", "ワンタップで"), ("親指を覚えさせよう", "たった30秒"), ("カラー、フォント、", "サウンドと振動"), ("3日間", "無料トライアル")],
    "ko": [("쥔 손 쪽으로", "키보드가 와요"), ("Duo를 두 손으로?", "둘로 나뉘어요"), ("바깥 화면에서는", "전체 너비로"),
           ("복사한 모든 것,", "한 번 탭으로"), ("엄지를 가르치세요", "30초면 충분"), ("색상, 글꼴,", "소리와 진동"), ("3일", "무료 체험")],
    "zh-Hans": [("键盘来到", "你握手机的一侧"), ("双手握 Duo？", "它一分为二"), ("外屏上", "全宽显示"),
                ("你复制的一切，", "一键即可粘贴"), ("教它认识你的拇指", "只需 30 秒"), ("颜色、字体、", "声音与振动"), ("3 天", "免费试用")],
    "ru": [("Клавиатура приходит", "к вашей руке"), ("Две руки на Duo?", "Она делится надвое"), ("На всю ширину", "на внешнем экране"),
           ("Всё, что вы копируете,", "в одно касание"), ("Научите её пальцам", "за 30 секунд"), ("Цвета, шрифты,", "звук и вибрация"), ("3 дня", "бесплатно")],
}
KEYS = ["right", "split", "split-out", "clip", "calib", "themes", "pro"]
CAP = {lang: dict(zip(KEYS, v)) for lang, v in C.items()}
HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:%(w)dpx;height:%(h)dpx;overflow:hidden}
body{background:radial-gradient(%(w)dpx %(h)dpx at 20%% 0%%,#3a6df0 0%%,rgba(58,109,240,0) 55%%),linear-gradient(165deg,#1b2a6b 0%%,#0b1030 100%%);
 font-family:"Inter Display","Inter","Noto Sans CJK JP","Noto Sans CJK KR","Noto Sans CJK SC",-apple-system,sans-serif;color:#fff}
.t{position:absolute;left:0;right:0;top:%(ty)dpx;text-align:center;font-weight:800;font-size:%(fs)dpx;line-height:1.08;letter-spacing:-.02em}
.t b{display:block;background:linear-gradient(90deg,#7fd8ff,#53e3b0);-webkit-background-clip:text;background-clip:text;color:transparent}
.s{position:absolute;left:50%%;top:%(sy)dpx;transform:translateX(-50%%);width:%(sw)dpx;border-radius:%(r)dpx;overflow:hidden;
 box-shadow:0 30px 90px rgba(0,0,0,.45),0 0 0 %(bw)dpx #0a0c14}
.s img{display:block;width:100%%}
</style></head><body><div class="t">%(l1)s<b>%(l2)s</b></div><div class="s"><img src="data:image/png;base64,%(img)s"></div></body></html>"""

def render(page, w, h, shot, l1, l2, out):
    iw, ih = Image.open(shot).size
    sy = int(h * 0.2)
    sw = int(min(w * 0.88, (h - sy - h * 0.035) * iw / ih))
    sh = sw * ih / iw
    top = int(sy + max(0, (h - sy - sh) / 2 - h * 0.02))
    ty = int(max(h * 0.05, (top - w * 0.09 * 2.2) / 2))
    params = dict(w=w, h=h, ty=ty, fs=int(w * 0.088), sy=top, sw=sw, r=int(sw * 0.07), bw=int(w * 0.012),
                  l1=l1, l2=l2, img=base64.b64encode(open(shot, "rb").read()).decode())
    page.set_viewport_size({"width": w, "height": h})
    page.set_content(HTML % params)
    page.evaluate("document.fonts.ready")
    page.wait_for_timeout(150)
    page.screenshot(path=out)

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page()
    for lang in CAP:
        n_duo = n_ph = 0
        for i, r in enumerate(ROUTES, 1):
            # Le simulateur ne donne que l'écran déplié du Duo (466 points de large) : il sert aux deux jeux.
            inner = os.path.join(SRC, f"duo-{lang}-{i:02d}-{r}-in.png")
            outer = os.path.join(SRC, f"duo-{lang}-{i:02d}-{r}-out.png")
            if not os.path.exists(inner):
                inner = outer
            if r == "split":
                outer = ""  # pas de clavier coupé en deux sur un iPhone classique
            if os.path.exists(inner):
                n_duo += 1
                l1, l2 = CAP[lang][r]
                render(pg, 2007, 2853, inner, l1, l2, os.path.join(OUT, f"duo-{FILE.get(lang, lang)}-{n_duo}.png"))
            if outer and os.path.exists(outer):
                n_ph += 1
                l1, l2 = CAP[lang]["split-out" if r == "split" else r]
                render(pg, 1290, 2796, outer, l1, l2, os.path.join(OUT, f"{FILE.get(lang, lang)}-{n_ph}.png"))
        print(lang, "duo", n_duo, "iphone", n_ph)
    b.close()
