"""Clubs partenaires PadelUp : les terrains gérés dans le back-office PadelUp, réservés sans compte externe."""
import math
from datetime import datetime
from decimal import Decimal

from django.db.models import Q
from django.utils import timezone

from app.booking_utils import BookingConflict, create_booking, free_slots, price_for
from app.models import Club, Court

from .base import BaseProvider, BookingResult, ProviderClub, ProviderError, Slot, SlotUnavailable


def _distance(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return round(2 * r * math.asin(math.sqrt(a)), 1)


class PadelUpProvider(BaseProvider):
    code = 'padelup'
    name = 'Clubs PadelUp'
    needs_account = False
    description = 'Les clubs partenaires PadelUp : réservation directe avec ton compte PadelUp.'

    def _club(self, c, lat=None, lon=None):
        club = ProviderClub(
            id=str(c.id), name=c.name, city=c.city, address=c.address, country=getattr(c, 'country', '') or '',
            latitude=float(c.latitude), longitude=float(c.longitude), timezone='',
            courts=c.courts.filter(is_available=True).count(), image=c.images[0] if c.images else '',
            booking_url=c.reservation_link or '',
        )
        if lat is not None and lon is not None:
            club.distance_km = _distance(float(lat), float(lon), club.latitude, club.longitude)
        return club

    def search_clubs(self, latitude=None, longitude=None, radius_km=30, query=''):
        qs = Club.objects.filter(courts__is_available=True).distinct()
        if query:
            qs = qs.filter(Q(name__icontains=query) | Q(city__icontains=query))
        clubs = [self._club(c, latitude, longitude) for c in qs[:500]]
        if latitude is not None and longitude is not None:
            clubs = [c for c in clubs if c.distance_km is None or c.distance_km <= radius_km]
            clubs.sort(key=lambda c: c.distance_km)
        return clubs[:50]

    def get_club(self, club_id):
        try:
            return self._club(Club.objects.get(pk=int(club_id)))
        except (Club.DoesNotExist, ValueError):
            raise ProviderError('Club PadelUp introuvable.')

    def list_slots(self, club_id, day):
        try:
            courts = Court.objects.filter(club_id=int(club_id), is_available=True).select_related('club')
        except ValueError:
            raise ProviderError('Club PadelUp introuvable.')
        tz = timezone.get_current_timezone()
        slots = []
        for court in courts:
            for start, duration in free_slots(court, day, [60, 90, 120]):
                price = (price_for(court, day, start) * Decimal(duration) / Decimal(60)).quantize(Decimal('0.01'))
                slots.append(Slot(
                    club_id=str(court.club_id), resource_id=str(court.id), court_name=court.name,
                    start=timezone.make_aware(datetime.combine(day, start), tz), duration=duration, price=price,
                    currency=court.club.currency or 'EUR', indoor=court.is_indoor, timezone=str(tz),
                ))
        slots.sort(key=lambda s: (s.start, s.duration, s.court_name))
        return slots

    def book(self, slot):
        if not self.user:
            raise ProviderError('Utilisateur requis.')
        try:
            court = Court.objects.select_related('club').get(pk=int(slot.resource_id))
        except (Court.DoesNotExist, ValueError):
            raise ProviderError('Terrain introuvable.')
        local = slot.start.astimezone(timezone.get_current_timezone())
        try:
            booking = create_booking(self.user, court, local.date(), local.time().replace(second=0, microsecond=0), slot.duration)
        except BookingConflict as exc:
            raise SlotUnavailable(str(exc))
        return BookingResult('booked', external_id=str(booking.id), message=f'Réservé : {court.name}, {court.club.name}.')
