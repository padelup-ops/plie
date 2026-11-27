"""Chiffrement des jetons des comptes connectés (Playtomic, ...).

Les mots de passe des plateformes ne sont jamais enregistrés : on garde seulement les
jetons d'accès renvoyés par la plateforme, chiffrés avec Fernet (AES-128 + HMAC).

La clé vient de BOT_ENCRYPTION_KEY (à générer avec
`python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`).
Sans elle, on dérive une clé de SECRET_KEY : pratique en local, déconseillé en production
(changer SECRET_KEY rendrait alors les jetons illisibles et demanderait de reconnecter les comptes).
"""
import base64
import hashlib
import logging
import os

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings

logger = logging.getLogger(__name__)
_warned = False


def _fernet():
    global _warned
    key = os.environ.get('BOT_ENCRYPTION_KEY', '').strip()
    if not key:
        if not _warned and not settings.DEBUG:
            logger.warning('BOT_ENCRYPTION_KEY absent : clé dérivée de SECRET_KEY (à éviter en production).')
            _warned = True
        digest = hashlib.sha256(('padelup-bot:' + settings.SECRET_KEY).encode()).digest()
        key = base64.urlsafe_b64encode(digest).decode()
    return Fernet(key.encode())


def encrypt(value):
    if not value:
        return ''
    return _fernet().encrypt(value.encode()).decode()


def decrypt(value):
    if not value:
        return ''
    try:
        return _fernet().decrypt(value.encode()).decode()
    except (InvalidToken, ValueError):
        logger.warning('Jeton illisible (clé de chiffrement changée ?) : reconnexion nécessaire.')
        return ''
