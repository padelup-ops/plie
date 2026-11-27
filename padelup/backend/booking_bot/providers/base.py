"""Interface commune aux plateformes de réservation (Playtomic, clubs PadelUp, ...)."""
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.conf import settings


class ProviderError(Exception):
    """Erreur de la plateforme (réseau, réponse inattendue...)."""


class ProviderAuthError(ProviderError):
    """Le compte doit être reconnecté (identifiants refusés, jeton expiré)."""


class SlotUnavailable(ProviderError):
    """Le créneau vient d'être pris par quelqu'un d'autre."""


def zone(name):
    try:
        return ZoneInfo(name or settings.TIME_ZONE)
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo(settings.TIME_ZONE)


def parse_price(value):
    """« 24 EUR », « 24.5 € », 24 → (Decimal, devise)."""
    if value is None or value == '':
        return None, ''
    if isinstance(value, (int, float, Decimal)):
        return Decimal(str(value)), ''
    parts = str(value).replace('€', ' EUR').replace(',', '.').split()
    amount, currency = None, ''
    for p in parts:
        try:
            amount = Decimal(p)
        except InvalidOperation:
            if p.isalpha() and len(p) == 3:
                currency = p.upper()
    return amount, currency


@dataclass
class ProviderClub:
    id: str
    name: str
    city: str = ''
    address: str = ''
    country: str = ''
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    timezone: str = ''
    courts: int = 0
    image: str = ''
    booking_url: str = ''
    distance_km: Optional[float] = None

    def to_dict(self):
        return {
            'id': self.id, 'name': self.name, 'city': self.city, 'address': self.address, 'country': self.country,
            'latitude': self.latitude, 'longitude': self.longitude, 'timezone': self.timezone, 'courts': self.courts,
            'image': self.image, 'booking_url': self.booking_url, 'distance_km': self.distance_km,
        }


@dataclass
class Slot:
    club_id: str
    resource_id: str
    court_name: str
    start: datetime  # avec fuseau
    duration: int  # minutes
    price: Optional[Decimal] = None
    currency: str = ''
    indoor: Optional[bool] = None
    timezone: str = ''
    raw_start: str = ''  # valeur à renvoyer telle quelle à la plateforme pour réserver
    extra: dict = field(default_factory=dict)

    @property
    def local_start(self):
        return self.start.astimezone(zone(self.timezone))

    @property
    def key(self):
        return f'{self.club_id}:{self.resource_id}:{self.start.isoformat()}:{self.duration}'

    @property
    def price_label(self):
        if self.price is None:
            return ''
        amount = f'{self.price:.2f}'.rstrip('0').rstrip('.')
        return f'{amount} {self.currency}'.strip()

    def to_dict(self):
        local = self.local_start
        return {
            'key': self.key,
            'club_id': self.club_id,
            'resource_id': self.resource_id,
            'court_name': self.court_name,
            'start': self.start.isoformat(),
            'local_date': local.date().isoformat(),
            'local_time': local.strftime('%H:%M'),
            'duration': self.duration,
            'price': str(self.price) if self.price is not None else None,
            'currency': self.currency,
            'price_label': self.price_label,
            'indoor': self.indoor,
            'timezone': self.timezone,
            'raw_start': self.raw_start,
        }

    @classmethod
    def from_dict(cls, data):
        start = datetime.fromisoformat(str(data['start']).replace('Z', '+00:00'))
        price, currency = parse_price(data.get('price'))
        return cls(
            club_id=str(data['club_id']), resource_id=str(data['resource_id']), court_name=data.get('court_name', ''),
            start=start, duration=int(data['duration']), price=price, currency=data.get('currency') or currency,
            indoor=data.get('indoor'), timezone=data.get('timezone', ''), raw_start=data.get('raw_start', ''),
        )


@dataclass
class BookingResult:
    status: str  # booked | needs_action | failed
    external_id: str = ''
    message: str = ''
    action_url: str = ''

    @property
    def ok(self):
        return self.status == 'booked'


class BaseProvider:
    code = ''
    name = ''
    needs_account = False
    description = ''

    def __init__(self, user=None, account=None):
        self.user = user
        self.account = account

    def connect(self, email, password):  # pragma: no cover - surchargé
        raise ProviderError('Cette plateforme ne demande pas de compte.')

    def search_clubs(self, latitude=None, longitude=None, radius_km=30, query=''):
        raise NotImplementedError

    def get_club(self, club_id):
        raise NotImplementedError

    def list_slots(self, club_id, day: date):
        raise NotImplementedError

    def book(self, slot: Slot) -> BookingResult:
        raise NotImplementedError
