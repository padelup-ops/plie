"""Règles communes aux réservations de terrains PadelUp (vue REST et bot de réservation)."""
from datetime import datetime, time, timedelta
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .models import Booking, Court

DAY_KEYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
DEFAULT_OPEN, DEFAULT_CLOSE = time(8, 0), time(23, 0)


class BookingConflict(Exception):
    pass


def _minutes(t):
    return t.hour * 60 + t.minute


def opening_window(club, day):
    """Heures d'ouverture du club ce jour-là, en minutes depuis minuit : (ouverture, fermeture) ou None si fermé.
    Accepte « 08:00-22:00 », « 08:00-00:00 » (minuit), « fermé »/« closed » ou une valeur absente."""
    raw = (club.opening_hours or {}).get(DAY_KEYS[day.weekday()]) if isinstance(club.opening_hours, dict) else None
    if raw is None or raw == '':
        return _minutes(DEFAULT_OPEN), _minutes(DEFAULT_CLOSE)
    text = str(raw).strip().lower()
    if text in ('fermé', 'ferme', 'closed', 'off', '-'):
        return None
    try:
        a, b = [p.strip() for p in text.replace('–', '-').split('-', 1)]
        oh, om = [int(x) for x in a.split(':')[:2]]
        ch, cm = [int(x) for x in b.split(':')[:2]]
    except (ValueError, IndexError):
        return _minutes(DEFAULT_OPEN), _minutes(DEFAULT_CLOSE)
    open_m, close_m = oh * 60 + om, ch * 60 + cm
    if close_m <= open_m:  # « 08:00-00:00 » ou « 18:00-02:00 » : on s'arrête à minuit
        close_m = 24 * 60
    return open_m, close_m


def price_for(court, day, start):
    """Prix horaire selon l'heure du créneau (et non l'heure de la réservation)."""
    base = court.price_per_hour
    prices = court.prices if isinstance(court.prices, dict) else {}
    if prices:
        if 18 <= start.hour < 21 and 'peak' in prices:
            base = prices['peak']
        elif day.weekday() >= 5 and 'weekend' in prices:
            base = prices['weekend']
        elif 'off_peak' in prices:
            base = prices['off_peak']
    try:
        return Decimal(str(base))
    except Exception:
        return Decimal(str(court.price_per_hour))


def overlapping(court, day, start, end, exclude_id=None):
    qs = Booking.objects.filter(court=court, date=day, status='confirmed', start_time__lt=end, end_time__gt=start)
    if exclude_id:
        qs = qs.exclude(pk=exclude_id)
    return qs


def validate_slot(court, day, start, end):
    """Erreur lisible si le créneau n'est pas réservable, sinon None."""
    if end <= start:
        return "L'heure de fin doit être après l'heure de début"
    if not court.is_available:
        return "Ce terrain n'est pas disponible à la réservation"
    tz = timezone.get_current_timezone()
    if timezone.make_aware(datetime.combine(day, start), tz) < timezone.now():
        return 'Impossible de réserver un créneau passé'
    window = opening_window(court.club, day)
    if window is None:
        return 'Le club est fermé ce jour-là'
    if _minutes(start) < window[0] or (_minutes(end) or 24 * 60) > window[1]:
        return "Le créneau est en dehors des heures d'ouverture du club"
    if overlapping(court, day, start, end).exists():
        return 'Ce créneau chevauche une réservation existante'
    return None


def create_booking(user, court, day, start, duration):
    """Crée une réservation confirmée de façon sûre (verrou sur le terrain, contrôle des chevauchements)."""
    end_dt = datetime.combine(day, start) + timedelta(minutes=duration)
    if end_dt == datetime.combine(day + timedelta(days=1), time(0, 0)):
        end = time(23, 59, 59)  # un créneau qui finit à minuit reste sur la même journée
    elif end_dt.date() != day:
        raise BookingConflict('Le créneau dépasse minuit')
    else:
        end = end_dt.time()
    with transaction.atomic():
        court = Court.objects.select_for_update().select_related('club').get(pk=court.pk)
        error = validate_slot(court, day, start, end)
        if error:
            raise BookingConflict(error)
        total = (price_for(court, day, start) * Decimal(duration) / Decimal(60)).quantize(Decimal('0.01'))
        return Booking.objects.create(
            court=court, user=user, date=day, start_time=start, end_time=end, duration=duration,
            status='confirmed', total_amount=total, currency=court.club.currency or 'EUR', payment_status='pending',
        )


def free_slots(court, day, durations, step=30, now=None):
    """Créneaux libres d'un terrain pour une journée : liste de (début, durée)."""
    window = opening_window(court.club, day)
    if window is None or not court.is_available:
        return []
    now = now or timezone.now()
    tz = timezone.get_current_timezone()
    taken = [(_minutes(b.start_time), _minutes(b.end_time) or 24 * 60)
             for b in Booking.objects.filter(court=court, date=day, status='confirmed')]
    out = []
    first = window[0] + (-window[0]) % step
    for m in range(first, window[1], step):
        start = time(m // 60, m % 60)
        if timezone.make_aware(datetime.combine(day, start), tz) <= now:
            continue
        for d in durations:
            e = m + d
            if e > window[1]:
                continue
            if any(m < te and e > ts for ts, te in taken):
                continue
            out.append((start, d))
    return out
