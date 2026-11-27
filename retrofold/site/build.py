"""Assemble le site du guide : la partie libre (page.html) et le contenu payant (premium.html), chiffré avec le
code d'accès remis après paiement. La page publiée ne contient que le contenu chiffré : sans le code, il est illisible.

    GUIDE_CODE=XXXX-XXXX python3 build.py            -> dist/index.html

Le code n'est écrit nulle part dans le dépôt. Pour le changer (code qui a fuité), reconstruire avec un autre code.
"""
import base64, json, os, sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

HERE = os.path.dirname(os.path.abspath(__file__))
ITERATIONS = 250_000


def normalise(code):
    """Le code tel que la page le reforme à la saisie : majuscules, sans espace ni tiret."""
    return "".join(c for c in code.upper() if c.isalnum())


def coffre(html, code):
    salt, iv = os.urandom(16), os.urandom(12)
    key = PBKDF2HMAC(hashes.SHA256(), 32, salt, ITERATIONS).derive(normalise(code).encode())
    data = AESGCM(key).encrypt(iv, html.encode(), None)
    b64 = lambda b: base64.b64encode(b).decode()
    return {"salt": b64(salt), "iv": b64(iv), "data": b64(data), "iterations": ITERATIONS}


def main():
    code = os.environ.get("GUIDE_CODE", "")
    if len(normalise(code)) < 8:
        sys.exit("GUIDE_CODE : le code d'accès doit compter au moins 8 lettres ou chiffres")
    page = open(os.path.join(HERE, "page.html"), encoding="utf-8").read()
    premium = open(os.path.join(HERE, "premium.html"), encoding="utf-8").read()
    marker = "/*__COFFRE__*/null"
    if page.count(marker) != 1:
        sys.exit("page.html : repère du coffre introuvable")
    out = page.replace(marker, json.dumps(coffre(premium, code)))
    os.makedirs(os.path.join(HERE, "dist"), exist_ok=True)
    with open(os.path.join(HERE, "dist", "index.html"), "w", encoding="utf-8") as f:
        f.write(out)
    print(f"dist/index.html : {len(out) // 1024} Ko, contenu payant chiffré ({len(premium) // 1024} Ko en clair)")


if __name__ == "__main__":
    main()
