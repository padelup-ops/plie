"""Playtomic : recherche de clubs, disponibilités et réservation avec le compte du joueur.

Playtomic ne publie pas d'API ouverte aux applications tierces : ce module parle à l'API utilisée par leur
propre application (api.playtomic.io). Elle peut changer sans préavis, et les conditions d'utilisation de
Playtomic encadrent l'accès automatisé : à valider avec Playtomic (programme partenaires) avant un lancement public.
Les chemins sont regroupés ici pour pouvoir être ajustés en un seul endroit.

Réservation (parcours de leur application) :
  1. POST /v1/payment_intents             -> panier « CUSTOMER_MATCH » (club, terrain, début, durée)
  2. PATCH /v1/payment_intents/{id}       -> moyen de paiement enregistré (porte-monnaie du club, sur place, carte)
  3. POST /v1/payment_intents/{id}/confirmation
Si la banque demande une validation (3-D Secure), la réservation reste à confirmer dans l'app Playtomic.
"""
import logging
import math
import os
from datetime import datetime, time, timedelta, timezone as dt_timezone

import requests
from django.utils import timezone

from .base import (BaseProvider, BookingResult, ProviderAuthError, ProviderClub, ProviderError, Slot,
                   SlotUnavailable, parse_price, zone)

logger = logging.getLogger(__name__)

API_BASE = os.environ.get('PLAYTOMIC_API_BASE', 'https://api.playtomic.io').rstrip('/')
LOGIN_PATH = '/v3/auth/login'
REFRESH_PATH = '/v3/auth/token'
TENANTS_PATH = '/v1/tenants'
AVAILABILITY_PATH = '/v1/availability'
PAYMENT_INTENTS_PATH = '/v1/payment_intents'
TIMEOUT = 20
# Moyens de paiement qui se valident sans page de paiement : crédit du club, bon, paiement sur place.
# (Carte, iDEAL, Bancontact... demandent une redirection : le joueur termine alors dans l'app Playtomic.)
PAYMENT_PREFERENCE = ['MERCHANT_WALLET', 'OFFER', 'CASH', 'AT_THE_CLUB']
ALLOWED_TYPES = ['OFFER', 'CASH', 'MERCHANT_WALLET', 'DIRECT', 'SWISH', 'IDEAL', 'BANCONTACT', 'PAYTRAIL',
                 'CREDIT_CARD', 'QUICK_PAY']


def dry_run():
    return os.environ.get('PLAYTOMIC_DRY_RUN', '').lower() in ('1', 'true', 'yes')


def _parse_dt(value):
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=dt_timezone.utc)


def _haversine(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return round(2 * r * math.asin(math.sqrt(a)), 1)


class PlaytomicProvider(BaseProvider):
    code = 'playtomic'
    name = 'Playtomic'
    needs_account = True
    description = ("Connecte ton compte Playtomic : le bot voit les disponibilités des clubs Playtomic "
                   "et réserve à ta place avec ton moyen de paiement enregistré.")

    def __init__(self, user=None, account=None, session=None):
        super().__init__(user, account)
        self.http = session or requests.Session()
        self.http.headers.update({'Accept': 'application/json', 'Content-Type': 'application/json',
                                  'X-Requested-With': 'com.playtomic.web', 'User-Agent': 'PadelUp/2.0 (booking-bot)'})
        self._tenants = {}

    # ------------------------------------------------------------------ HTTP
    def _request(self, method, path, auth=False, retry_auth=True, **kwargs):
        headers = kwargs.pop('headers', {})
        if auth:
            headers['Authorization'] = 'Bearer ' + self._ensure_token()
        try:
            resp = self.http.request(method, API_BASE + path, headers=headers, timeout=TIMEOUT, **kwargs)
        except requests.RequestException as exc:
            raise ProviderError(f'Playtomic injoignable : {exc.__class__.__name__}') from exc
        if resp.status_code == 401 and auth and retry_auth and self.account and self.account.refresh_token:
            self._refresh()
            return self._request(method, path, auth=auth, retry_auth=False, headers={}, **kwargs)
        if resp.status_code == 401 and auth:
            raise ProviderAuthError('Session Playtomic expirée : reconnecte ton compte.')
        if resp.status_code == 429:
            raise ProviderError('Playtomic limite les requêtes, nouvel essai plus tard.')
        return resp

    @staticmethod
    def _json(resp):
        try:
            return resp.json()
        except ValueError:
            return {}

    @staticmethod
    def _error_text(resp):
        data = PlaytomicProvider._json(resp)
        if isinstance(data, dict):
            return str(data.get('localized_message') or data.get('message') or data.get('status') or resp.status_code)
        return str(resp.status_code)

    # --------------------------------------------------------------- compte
    def connect(self, email, password):
        resp = self._request('POST', LOGIN_PATH, json={'grant_type': 'password', 'email': email, 'password': password})
        if resp.status_code in (400, 401, 403, 404):
            raise ProviderAuthError('Identifiants Playtomic refusés.')
        if resp.status_code >= 300:
            raise ProviderError(f'Connexion Playtomic impossible ({self._error_text(resp)}).')
        data = self._json(resp)
        if not data.get('access_token'):
            raise ProviderError('Réponse de connexion Playtomic inattendue.')
        return {
            'external_user_id': str(data.get('user_id') or ''),
            'access_token': data['access_token'],
            'refresh_token': data.get('refresh_token') or '',
            'token_expires_at': _parse_dt(data.get('access_token_expiration')) or timezone.now() + timedelta(hours=1),
            'refresh_expires_at': _parse_dt(data.get('refresh_token_expiration')),
        }

    def _save_tokens(self, data):
        self.account.apply_tokens(data)

    def _refresh(self):
        acc = self.account
        if not acc or not acc.refresh_token:
            raise ProviderAuthError('Session Playtomic expirée : reconnecte ton compte.')
        resp = self._request('POST', REFRESH_PATH, json={'grant_type': 'refresh_token', 'refresh_token': acc.refresh_token})
        data = self._json(resp)
        if resp.status_code >= 300 or not data.get('access_token'):
            acc.mark_needs_reauth('Le renouvellement de session Playtomic a échoué.')
            raise ProviderAuthError('Session Playtomic expirée : reconnecte ton compte.')
        self._save_tokens({
            'access_token': data['access_token'],
            'refresh_token': data.get('refresh_token') or '',
            'token_expires_at': _parse_dt(data.get('access_token_expiration')) or timezone.now() + timedelta(hours=1),
            'refresh_expires_at': _parse_dt(data.get('refresh_token_expiration')),
            'external_user_id': str(data.get('user_id') or ''),
        })

    def _ensure_token(self):
        acc = self.account
        if not acc:
            raise ProviderAuthError('Aucun compte Playtomic connecté.')
        if acc.status == 'needs_reauth':
            raise ProviderAuthError('Reconnecte ton compte Playtomic.')
        token = acc.access_token
        expires = acc.token_expires_at
        if not token or (expires and expires <= timezone.now() + timedelta(seconds=60)):
            self._refresh()
            token = acc.access_token
        return token

    # ----------------------------------------------------------------- clubs
    def _club_from_tenant(self, t, lat=None, lon=None):
        addr = t.get('address') or {}
        coord = addr.get('coordinate') or addr.get('geo_location') or t.get('geo_location') or {}
        clat, clon = coord.get('lat', coord.get('latitude')), coord.get('lon', coord.get('longitude'))
        images = t.get('images') or []
        resources = [r for r in (t.get('resources') or []) if (r.get('sport_id') or 'PADEL') == 'PADEL']
        club = ProviderClub(
            id=str(t.get('tenant_id')),
            name=t.get('tenant_name') or 'Club',
            city=addr.get('city') or '',
            address=', '.join(x for x in [addr.get('street'), addr.get('postal_code'), addr.get('city')] if x),
            country=addr.get('country') or addr.get('country_code') or '',
            latitude=clat, longitude=clon,
            timezone=addr.get('timezone') or '',
            courts=len(resources),
            image=images[0] if images and isinstance(images[0], str) else '',
            booking_url=f"https://playtomic.io/{t.get('slug') or 'tenant/' + str(t.get('tenant_id'))}",
        )
        if lat is not None and lon is not None and clat is not None and clon is not None:
            club.distance_km = _haversine(float(lat), float(lon), float(clat), float(clon))
        return club

    def search_clubs(self, latitude=None, longitude=None, radius_km=30, query=''):
        if latitude is None or longitude is None:
            raise ProviderError('Position nécessaire pour chercher des clubs Playtomic.')
        params = {
            'coordinate': f'{float(latitude):.5f},{float(longitude):.5f}',
            'sport_id': 'PADEL',
            'radius': int(min(max(radius_km, 1), 200) * 1000),
            'size': 50,
        }
        resp = self._request('GET', TENANTS_PATH, params=params)
        if resp.status_code >= 300:
            raise ProviderError(f'Recherche Playtomic impossible ({self._error_text(resp)}).')
        tenants = self._json(resp)
        if isinstance(tenants, dict):
            tenants = tenants.get('content') or tenants.get('tenants') or []
        clubs = []
        q = (query or '').strip().lower()
        for t in tenants:
            self._tenants[str(t.get('tenant_id'))] = t
            club = self._club_from_tenant(t, latitude, longitude)
            if q and q not in club.name.lower() and q not in club.city.lower():
                continue
            clubs.append(club)
        clubs.sort(key=lambda c: c.distance_km if c.distance_km is not None else 1e9)
        return clubs

    def _tenant(self, club_id):
        club_id = str(club_id)
        if club_id not in self._tenants or not self._tenants[club_id].get('resources'):
            resp = self._request('GET', f'{TENANTS_PATH}/{club_id}')
            if resp.status_code == 404:
                raise ProviderError('Club Playtomic introuvable.')
            if resp.status_code >= 300:
                raise ProviderError(f'Club Playtomic illisible ({self._error_text(resp)}).')
            tenant = self._json(resp) or {}
            if not tenant.get('resources'):
                res = self._request('GET', f'{TENANTS_PATH}/{club_id}/resources')
                if res.status_code < 300 and isinstance(self._json(res), list):
                    tenant['resources'] = self._json(res)
            self._tenants[club_id] = tenant
        return self._tenants[club_id]

    def get_club(self, club_id):
        return self._club_from_tenant(self._tenant(club_id))

    # -------------------------------------------------------- disponibilités
    def list_slots(self, club_id, day):
        tenant = self._tenant(club_id)
        tz_name = (tenant.get('address') or {}).get('timezone') or ''
        tz = zone(tz_name)
        resources = {}
        for r in tenant.get('resources') or []:
            props = r.get('properties') or {}
            kind = (props.get('resource_type') or '').lower()
            resources[str(r.get('resource_id'))] = {
                'name': r.get('name') or 'Terrain',
                'indoor': True if kind == 'indoor' else False if kind == 'outdoor' else None,
                'sport': r.get('sport_id') or 'PADEL',
            }
        # La journée locale du club, exprimée en UTC (l'API reçoit et renvoie des heures UTC).
        start_local = datetime.combine(day, time(0, 0), tzinfo=tz)
        end_local = datetime.combine(day, time(23, 59, 59), tzinfo=tz)
        params = {
            'sport_id': 'PADEL',
            'tenant_id': str(club_id),
            'start_min': start_local.astimezone(dt_timezone.utc).strftime('%Y-%m-%dT%H:%M:%S'),
            'start_max': end_local.astimezone(dt_timezone.utc).strftime('%Y-%m-%dT%H:%M:%S'),
        }
        resp = self._request('GET', AVAILABILITY_PATH, params=params)
        if resp.status_code >= 300:
            raise ProviderError(f'Disponibilités Playtomic illisibles ({self._error_text(resp)}).')
        slots = []
        for block in self._json(resp) or []:
            rid = str(block.get('resource_id'))
            info = resources.get(rid, {'name': 'Terrain', 'indoor': None, 'sport': 'PADEL'})
            if info['sport'] != 'PADEL':
                continue
            for s in block.get('slots') or []:
                raw = f"{block.get('start_date')}T{s.get('start_time')}"
                try:
                    start = datetime.fromisoformat(raw).replace(tzinfo=dt_timezone.utc)
                except ValueError:
                    continue
                price, currency = parse_price(s.get('price'))
                slots.append(Slot(
                    club_id=str(club_id), resource_id=rid, court_name=info['name'], start=start,
                    duration=int(s.get('duration') or 60), price=price, currency=currency or 'EUR',
                    indoor=info['indoor'], timezone=tz_name, raw_start=raw,
                ))
        slots.sort(key=lambda x: (x.start, x.duration, x.court_name))
        return slots

    # ------------------------------------------------------------ réservation
    @staticmethod
    def _choose_method(methods):
        """Renvoie l'identifiant du moyen de paiement à utiliser, ou None s'il faut une action du joueur."""
        def ident(m):
            return m if isinstance(m, str) else (m.get('payment_method_id') or m.get('id'))

        def kind(m):
            if isinstance(m, str):
                return m.upper()
            return ' '.join(str(m.get(k) or '') for k in ('method_type', 'payment_method_type', 'type', 'code', 'name',
                                                          'payment_method_id')).upper().replace(' ', '_')
        usable = [m for m in methods if ident(m) and (isinstance(m, str) or m.get('enabled', True) is not False)]
        for wanted in PAYMENT_PREFERENCE:
            for m in usable:
                if wanted in kind(m):
                    return ident(m)
        return None

    def book(self, slot):
        acc = self.account
        user_id = acc.external_user_id if acc else ''
        if not user_id:
            raise ProviderAuthError('Compte Playtomic incomplet : reconnecte-le.')
        cart = {
            'allowed_payment_method_types': ALLOWED_TYPES,
            'user_id': user_id,
            'cart': {'requested_item': {
                'cart_item_type': 'CUSTOMER_MATCH',
                'cart_item_voucher_id': None,
                'cart_item_data': {
                    'supports_split_payment': True,
                    'number_of_players': 4,
                    'tenant_id': slot.club_id,
                    'resource_id': slot.resource_id,
                    'start': slot.raw_start or slot.start.astimezone(dt_timezone.utc).strftime('%Y-%m-%dT%H:%M:%S'),
                    'duration': slot.duration,
                    'match_registrations': [{'user_id': user_id, 'pay_now': True}],
                },
            }},
        }
        resp = self._request('POST', PAYMENT_INTENTS_PATH, auth=True, json=cart)
        if resp.status_code in (409, 422) or (resp.status_code == 400 and 'avail' in self._error_text(resp).lower()):
            raise SlotUnavailable('Créneau déjà pris.')
        if resp.status_code >= 300:
            return BookingResult('failed', message=f'Playtomic a refusé le panier ({self._error_text(resp)}).')
        intent = self._json(resp)
        pid = intent.get('payment_intent_id') or intent.get('id')
        if not pid:
            return BookingResult('failed', message='Réponse Playtomic inattendue (pas de paiement créé).')
        club_url = f'https://playtomic.io/tenant/{slot.club_id}'
        method = self._choose_method(intent.get('available_payment_methods') or [])
        if not method:
            return BookingResult('needs_action', external_id=str(pid), action_url=club_url,
                                 message="Ce club demande un paiement par carte : termine la réservation dans l'app Playtomic "
                                         "(ou choisis un club qui accepte le paiement sur place / le crédit club).")
        resp = self._request('PATCH', f'{PAYMENT_INTENTS_PATH}/{pid}', auth=True, json={
            'selected_payment_method_id': method,
            'selected_payment_method_data': None,
        })
        if resp.status_code >= 300:
            return BookingResult('failed', message=f'Moyen de paiement refusé ({self._error_text(resp)}).')
        if dry_run():
            return BookingResult('failed', message='Mode simulation (PLAYTOMIC_DRY_RUN) : tout est prêt, réservation non confirmée.')
        resp = self._request('POST', f'{PAYMENT_INTENTS_PATH}/{pid}/confirmation', auth=True)
        data = self._json(resp)
        state = str(data.get('status') or '').upper() if isinstance(data, dict) else ''
        if resp.status_code < 300 and state in ('SUCCEEDED', 'PAYMENT_SUCCEEDED', 'CONFIRMED', 'COMPLETED', ''):
            return BookingResult('booked', external_id=str(_find_match_id(data) or pid), message='Réservé sur Playtomic.')
        if resp.status_code == 422 and state == 'PAYMENT_INTENT_STATUS_INVALID':
            # Déjà confirmé de leur côté (paiement validé automatiquement) : c'est réservé.
            return BookingResult('booked', external_id=str(_find_match_id(data) or pid), message='Réservé sur Playtomic.')
        if state in ('REQUIRES_ACTION', 'REQUIRES_PAYMENT_METHOD', 'PENDING'):
            return BookingResult('needs_action', external_id=str(pid), action_url=club_url,
                                 message="Ta banque demande une validation : termine le paiement dans l'app Playtomic.")
        if resp.status_code in (409, 422):
            raise SlotUnavailable('Créneau déjà pris.')
        return BookingResult('failed', message=f'Confirmation refusée ({self._error_text(resp) if resp.status_code >= 300 else state}).')


def _find_match_id(data):
    """Cherche « match_id » dans la réponse (cart.item.cart_item_data.match_id le plus souvent)."""
    if isinstance(data, dict):
        if isinstance(data.get('match_id'), str) and data['match_id']:
            return data['match_id']
        for v in data.values():
            found = _find_match_id(v)
            if found:
                return found
    elif isinstance(data, list):
        for v in data:
            found = _find_match_id(v)
            if found:
                return found
    return None
