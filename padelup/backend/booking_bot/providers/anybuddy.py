"""Anybuddy : disponibilités des clubs (padel) et réservation avec le compte du joueur.

Ce qui est fiable : les disponibilités, lues sur l'API publique du site (/api/v1/availabilities, sans compte).
Ce qui est expérimental : la réservation par l'API mobile (POST /v2/reservations). Anybuddy fait payer par carte
(Stripe), parfois avec une validation 3-D Secure : quand la réservation ne peut pas aller jusqu'au bout,
le bot renvoie le lien direct du créneau pour payer en un geste.

Connexion : Anybuddy utilise Firebase Authentication. Renseigner ANYBUDDY_FIREBASE_API_KEY (clé publique
de leur application web, visible dans le code de anybuddyapp.com) pour connecter les comptes par e-mail.
Comme pour Playtomic, l'accès automatisé est encadré par les conditions d'Anybuddy : à valider avec eux.
"""
import os
import re
from datetime import datetime, timedelta
from decimal import Decimal

import requests
from django.utils import timezone

from .base import (BaseProvider, BookingResult, ProviderAuthError, ProviderClub, ProviderError, Slot,
                   SlotUnavailable, zone)

WEB_BASE = 'https://www.anybuddyapp.com'
API_BASE = os.environ.get('ANYBUDDY_API_BASE', 'https://api.anybuddyapp.com').rstrip('/')
TIMEOUT = 20
DEFAULT_TZ = 'Europe/Paris'
SLUG_RE = re.compile(r'anybuddyapp\.com/(?:[a-z]{2}/)?club/([a-z0-9\-]+)', re.I)


def club_slug(value):
    """« https://www.anybuddyapp.com/fr/club/padel-xyz » ou « padel-xyz » -> « padel-xyz »."""
    value = (value or '').strip()
    m = SLUG_RE.search(value)
    slug = m.group(1) if m else value.strip('/').split('/')[-1]
    if not re.fullmatch(r'[a-z0-9\-]{2,120}', slug or '', re.I):
        raise ProviderError('Lien ou identifiant de club Anybuddy invalide.')
    return slug.lower()


class AnybuddyProvider(BaseProvider):
    code = 'anybuddy'
    name = 'Anybuddy'
    needs_account = True
    description = ("Connecte ton compte Anybuddy : le bot surveille les créneaux de padel de tes clubs Anybuddy "
                   "et réserve dès qu'un créneau correspond (paiement par ta carte enregistrée).")

    def __init__(self, user=None, account=None, session=None):
        super().__init__(user, account)
        self.http = session or requests.Session()
        self.http.headers.update({
            'Accept': 'application/json', 'Accept-Language': 'fr-FR,fr;q=0.9',
            'Origin': WEB_BASE, 'Referer': WEB_BASE + '/',
            'User-Agent': os.environ.get('ANYBUDDY_USER_AGENT', 'PadelUp/2.0 (booking-bot)'),
        })

    def _get(self, url, **kwargs):
        try:
            resp = self.http.get(url, timeout=TIMEOUT, **kwargs)
        except requests.RequestException as exc:
            raise ProviderError(f'Anybuddy injoignable : {exc.__class__.__name__}') from exc
        if resp.status_code == 404:
            raise ProviderError('Club Anybuddy introuvable.')
        if resp.status_code >= 300:
            raise ProviderError(f'Anybuddy a répondu {resp.status_code}.')
        try:
            return resp.json()
        except ValueError:
            raise ProviderError('Réponse Anybuddy illisible.')

    # --------------------------------------------------------------- compte
    def _firebase_key(self):
        key = os.environ.get('ANYBUDDY_FIREBASE_API_KEY', '').strip()
        if not key:
            raise ProviderError("La connexion Anybuddy n'est pas encore activée sur ce serveur (ANYBUDDY_FIREBASE_API_KEY).")
        return key

    def connect(self, email, password):
        try:
            resp = requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
                                 params={'key': self._firebase_key()}, timeout=TIMEOUT,
                                 json={'email': email, 'password': password, 'returnSecureToken': True})
        except requests.RequestException as exc:
            raise ProviderError(f'Connexion Anybuddy impossible : {exc.__class__.__name__}') from exc
        data = resp.json() if resp.content else {}
        if resp.status_code >= 300 or not data.get('idToken'):
            raise ProviderAuthError('Identifiants Anybuddy refusés.')
        return {
            'external_user_id': data.get('localId', ''),
            'access_token': data['idToken'],
            'refresh_token': data.get('refreshToken', ''),
            'token_expires_at': timezone.now() + timedelta(seconds=int(data.get('expiresIn') or 3600)),
            'refresh_expires_at': None,
        }

    def _token(self):
        acc = self.account
        if not acc or acc.status == 'needs_reauth':
            raise ProviderAuthError('Reconnecte ton compte Anybuddy.')
        if acc.access_token and acc.token_expires_at and acc.token_expires_at > timezone.now() + timedelta(seconds=60):
            return acc.access_token
        if not acc.refresh_token:
            raise ProviderAuthError('Session Anybuddy expirée : reconnecte ton compte.')
        try:
            resp = requests.post('https://securetoken.googleapis.com/v1/token', params={'key': self._firebase_key()},
                                 data={'grant_type': 'refresh_token', 'refresh_token': acc.refresh_token}, timeout=TIMEOUT)
            data = resp.json()
        except (requests.RequestException, ValueError) as exc:
            raise ProviderError('Renouvellement de session Anybuddy impossible.') from exc
        if resp.status_code >= 300 or not data.get('id_token'):
            acc.mark_needs_reauth('Le renouvellement de session Anybuddy a échoué.')
            raise ProviderAuthError('Session Anybuddy expirée : reconnecte ton compte.')
        acc.access_token = data['id_token']
        acc.refresh_token = data.get('refresh_token') or acc.refresh_token
        acc.token_expires_at = timezone.now() + timedelta(seconds=int(data.get('expires_in') or 3600))
        acc.save()
        return acc.access_token

    # ----------------------------------------------------------------- clubs
    def search_clubs(self, latitude=None, longitude=None, radius_km=30, query=''):
        # Pas de recherche publique connue : on accepte le lien de la page du club Anybuddy.
        if not query:
            raise ProviderError('Colle le lien de la page du club sur anybuddyapp.com.')
        return [self.get_club(query)]

    def get_club(self, club_id):
        slug = club_slug(club_id)
        try:
            data = self._get(f'{API_BASE}/v1/centers/{slug}')
        except ProviderError:
            data = {}
        loc = data.get('location') or data.get('address') or {}
        lat = data.get('latitude') or (loc.get('latitude') or loc.get('lat') if isinstance(loc, dict) else None)
        lon = data.get('longitude') or (loc.get('longitude') or loc.get('lng') or loc.get('lon') if isinstance(loc, dict) else None)
        return ProviderClub(
            id=slug, name=data.get('name') or slug.replace('-', ' ').title(),
            city=(loc.get('city') if isinstance(loc, dict) else '') or data.get('city') or '',
            address=(loc.get('address') if isinstance(loc, dict) else '') or '',
            country='FR', latitude=float(lat) if lat else None, longitude=float(lon) if lon else None,
            timezone=DEFAULT_TZ, booking_url=f'{WEB_BASE}/fr/club/{slug}',
        )

    # -------------------------------------------------------- disponibilités
    def list_slots(self, club_id, day):
        slug = club_slug(club_id)
        data = self._get(f'{WEB_BASE}/api/v1/availabilities', params={
            'clubSlug': slug, 'dateFrom': day.isoformat(), 'dateTo': f'{day.isoformat()}T23:59', 'activity': 'padel'})
        tz = zone(DEFAULT_TZ)
        slots = []
        for group in data.get('data') or []:
            raw = group.get('startDateTime') or ''
            try:
                start = datetime.fromisoformat(raw).replace(tzinfo=tz)
            except ValueError:
                continue
            for svc in group.get('services') or []:
                cents = svc.get('discountPrice') or svc.get('price')
                slots.append(Slot(
                    club_id=slug, resource_id=str(svc.get('id') or ''), court_name=svc.get('name') or 'Terrain',
                    start=start, duration=int(svc.get('duration') or 60),
                    price=(Decimal(cents) / 100).quantize(Decimal('0.01')) if cents else None, currency='EUR',
                    indoor=None, timezone=DEFAULT_TZ, raw_start=raw,
                    extra={'slot_id': svc.get('slotId') or '', 'price_cents': svc.get('price') or 0},
                ))
        slots.sort(key=lambda s: (s.start, s.duration, s.court_name))
        return slots

    # ------------------------------------------------------------ réservation
    def book(self, slot):
        link = f'{WEB_BASE}/fr/club/{slot.club_id}'
        token = self._token()
        end = (datetime.fromisoformat(slot.raw_start) + timedelta(minutes=slot.duration)).strftime('%Y-%m-%dT%H:%M')
        payload = {
            'centerId': slot.club_id, 'serviceId': slot.resource_id, 'slotId': slot.extra.get('slot_id', ''),
            'startDateTime': slot.raw_start, 'endDateTime': end, 'acceptedTerms': True,
            'price': slot.extra.get('price_cents') or (int(slot.price * 100) if slot.price else 0), 'partySize': 4,
        }
        try:
            resp = self.http.post(f'{API_BASE}/v2/reservations', json=payload, timeout=TIMEOUT,
                                  headers={'Authorization': f'Bearer {token}'})
        except requests.RequestException as exc:
            raise ProviderError(f'Anybuddy injoignable : {exc.__class__.__name__}') from exc
        if resp.status_code == 401:
            raise ProviderAuthError('Session Anybuddy expirée : reconnecte ton compte.')
        if resp.status_code in (409, 410):
            raise SlotUnavailable('Créneau déjà pris.')
        data = resp.json() if resp.content and 'json' in resp.headers.get('content-type', '') else {}
        state = str(data.get('status') or data.get('state') or '').lower()
        if resp.status_code < 300 and state in ('confirmed', 'paid', 'booked', 'validated'):
            return BookingResult('booked', external_id=str(data.get('id') or data.get('reservationId') or ''),
                                 message='Réservé sur Anybuddy.')
        return BookingResult('needs_action', external_id=str(data.get('id') or ''), action_url=link,
                             message='Créneau bloqué pour toi : termine le paiement sur Anybuddy (carte enregistrée).')
