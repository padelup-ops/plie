"""Moteur du bot : trouve les créneaux qui correspondent aux règles des joueurs et les réserve à leur place.

Lancé en continu par `python manage.py run_booking_bot --loop` (service « worker »), ou appelé par un cron
externe via POST /api/bot/tick/ (en-tête X-Bot-Secret). Chaque règle est verrouillée pendant son traitement :
deux passages simultanés ne réservent jamais deux fois.
"""
import logging
from datetime import timedelta

from django.utils import timezone

from .models import AutoBookingRule, BotAttempt
from .providers import BookingResult, ProviderAuthError, ProviderError, SlotUnavailable, get_provider
from .providers.base import zone

logger = logging.getLogger(__name__)

DAYS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche']
MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']
MAX_TRIES_PER_RUN = 3


def fr_datetime(dt):
    return f'{DAYS[dt.weekday()]} {dt.day} {MONTHS[dt.month - 1]} à {dt.strftime("%H:%M")}'


def notify(user, kind, message, title='PadelUp', data=None):
    try:
        from app.fcm_service import create_notification
        create_notification(user=user, notification_type=kind, message=message, target='mobile', title=title,
                            data=data or {})
    except Exception as exc:  # une notification ne doit jamais bloquer une réservation
        logger.error('Notification du bot impossible : %s', exc)


def candidate_dates(rule, today):
    if rule.specific_date:
        return [rule.specific_date] if today <= rule.specific_date <= today + timedelta(days=30) else []
    weekdays = {int(d) for d in (rule.weekdays or []) if str(d).isdigit()}
    return [today + timedelta(days=i) for i in range(rule.days_ahead + 1)
            if not weekdays or (today + timedelta(days=i)).weekday() in weekdays]


def slot_matches(rule, slot, now, dates):
    tz = zone(slot.timezone or rule.club_timezone)
    local = slot.start.astimezone(tz)
    if local.date() not in dates:
        return False
    t = local.time().replace(second=0, microsecond=0)
    if not (rule.time_from <= t <= rule.time_to):
        return False
    if rule.durations and slot.duration not in [int(d) for d in rule.durations]:
        return False
    if rule.court_preference == 'indoor' and slot.indoor is False:
        return False
    if rule.court_preference == 'outdoor' and slot.indoor is True:
        return False
    if rule.max_price is not None and slot.price is not None and slot.price > rule.max_price:
        return False
    return slot.start >= now + timedelta(minutes=rule.min_notice_minutes)


def slot_rank(rule, slot):
    prefs = [int(d) for d in (rule.durations or [])]
    pref = prefs.index(slot.duration) if slot.duration in prefs else len(prefs)
    exact_court = 0 if rule.court_preference == 'any' or slot.indoor is not None else 1
    return (slot.start.date(), pref, exact_court, slot.start, slot.price or 0, slot.court_name)


def book_slot(user, provider_code, account, slot, rule=None, provider=None, club_name=''):
    """Réserve un créneau (bouton « Réserver » de l'app ou règle automatique), journalise et prévient le joueur."""
    provider = provider or get_provider(provider_code, user, account)
    club_name = club_name or (rule.club_name if rule else '')
    try:
        result = provider.book(slot)
    except SlotUnavailable as exc:
        result = BookingResult('failed', message=str(exc) or 'Créneau déjà pris.')
    except ProviderAuthError as exc:
        if account:
            account.mark_needs_reauth(str(exc))
        result = BookingResult('auth_error', message=str(exc))
    except ProviderError as exc:
        result = BookingResult('failed', message=str(exc))

    local = slot.local_start
    attempt = BotAttempt.objects.create(
        user=user, rule=rule, provider=provider_code, club_external_id=slot.club_id, club_name=club_name,
        status=result.status, slot_key=slot.key, slot_start=slot.start, slot_date=local.date(),
        duration=slot.duration, court_name=slot.court_name[:120], price=slot.price_label,
        external_booking_id=result.external_id[:120], action_url=result.action_url, message=result.message[:2000],
    )
    if account:
        account.last_used_at = timezone.now()
        account.save(update_fields=['last_used_at'])

    when = fr_datetime(local)
    data = {'action': 'bot_booking', 'attempt_id': str(attempt.id), 'provider': provider_code}
    if result.ok:
        notify(user, 'bot_booked', f'Réservé ✅ {club_name} — {when} ({slot.duration} min, {slot.court_name}). Bon match !',
               title='Le bot a réservé ton terrain', data=data)
    elif result.status == 'needs_action':
        notify(user, 'bot_action_required', f'{club_name} — {when} : {result.message}',
               title='Le bot a besoin de toi', data={**data, 'url': result.action_url})
    return attempt, result


def _attempt_blocks(rule, now):
    """Dates déjà réservées, dates en attente d'une action du joueur, créneaux récemment ratés."""
    booked = set(BotAttempt.objects.filter(rule=rule, status='booked').values_list('slot_date', flat=True))
    waiting = set(BotAttempt.objects.filter(rule=rule, status='needs_action', created_at__gte=now - timedelta(hours=12))
                  .values_list('slot_date', flat=True))
    recent_failed = set(BotAttempt.objects.filter(rule=rule, status='failed', created_at__gte=now - timedelta(minutes=15))
                        .values_list('slot_key', flat=True))
    notified = set(BotAttempt.objects.filter(rule=rule, status='notified').values_list('slot_key', flat=True))
    return booked, waiting, recent_failed, notified


def _finish(rule, now, status, message):
    rule.last_checked_at = now
    rule.last_status = status
    rule.last_message = message[:2000]
    rule.save(update_fields=['last_checked_at', 'last_status', 'last_message', 'bookings_made', 'is_active', 'updated_at'])
    return {'rule': rule.id, 'status': status, 'message': message}


def process_rule(rule, now=None, cache=None, dry_run=False):
    now = now or timezone.now()
    cache = {} if cache is None else cache
    if not rule.is_active or rule.is_exhausted:
        return {'rule': rule.id, 'status': 'inactive', 'message': 'Règle en pause.'}
    if not rule.try_lock():
        return {'rule': rule.id, 'status': 'locked', 'message': 'Déjà en cours de traitement.'}
    try:
        account = rule.account
        provider = get_provider(rule.provider, rule.user, account)
        if provider.needs_account and (not account or account.status == 'needs_reauth'):
            if account and not account.reauth_notified:
                notify(rule.user, 'bot_action_required',
                       f'Reconnecte ton compte {provider.name} : le bot ne peut plus réserver pour « {rule} ».',
                       title='Compte à reconnecter')
                account.reauth_notified = True
                account.save(update_fields=['reauth_notified'])
            return _finish(rule, now, 'auth_error', f'Compte {provider.name} à reconnecter.')

        today = now.astimezone(zone(rule.club_timezone)).date()
        dates = candidate_dates(rule, today)
        if rule.specific_date and not dates:
            rule.is_active = False
            return _finish(rule, now, 'expired', 'La date demandée est passée.')
        booked, waiting, recent_failed, notified = _attempt_blocks(rule, now)
        open_dates = [d for d in dates if d not in booked and d not in waiting]

        candidates = []
        for day in open_dates:
            key = (rule.provider, rule.club_external_id, day)
            if key not in cache:
                cache[key] = provider.list_slots(rule.club_external_id, day)
            candidates += [s for s in cache[key] if slot_matches(rule, s, now, set(open_dates))]
        candidates = [s for s in candidates if s.key not in recent_failed]
        candidates.sort(key=lambda s: slot_rank(rule, s))

        if not candidates:
            watched = len(open_dates)
            return _finish(rule, now, 'waiting',
                           f'Aucun créneau libre pour l\'instant ({watched} date{"s" if watched > 1 else ""} surveillée{"s" if watched > 1 else ""}).')

        if rule.mode == 'notify' or dry_run:
            # Une alerte par date (dans les 24 h) : pas de rafale de notifications pour la même journée.
            notified_days = set(BotAttempt.objects.filter(rule=rule, status='notified', created_at__gte=now - timedelta(hours=24))
                                .values_list('slot_date', flat=True))
            fresh = [s for s in candidates if s.key not in notified and s.local_start.date() not in notified_days]
            if not fresh:
                return _finish(rule, now, 'found', f'{len(candidates)} créneau(x) libre(s), déjà signalé(s).')
            best = fresh[0]
            if not dry_run:
                BotAttempt.objects.create(
                    user=rule.user, rule=rule, provider=rule.provider, club_external_id=rule.club_external_id,
                    club_name=rule.club_name, status='notified', slot_key=best.key, slot_start=best.start,
                    slot_date=best.local_start.date(), duration=best.duration, court_name=best.court_name[:120],
                    price=best.price_label, message='Créneau signalé.')
                notify(rule.user, 'bot_slot_found',
                       f'Créneau libre 🎾 {rule.club_name} — {fr_datetime(best.local_start)} ({best.duration} min, {best.court_name}'
                       f'{", " + best.price_label if best.price_label else ""}).',
                       title='Le bot a trouvé un créneau', data={'action': 'bot_slot', 'rule_id': str(rule.id)})
            return _finish(rule, now, 'found', f'Créneau signalé : {fr_datetime(best.local_start)}.')

        tries, booked_now, last = 0, [], None
        for slot in candidates:
            day = slot.local_start.date()
            if day in booked or rule.is_exhausted:
                continue
            if tries >= MAX_TRIES_PER_RUN:
                break
            tries += 1
            attempt, result = book_slot(rule.user, rule.provider, account, slot, rule=rule, provider=provider)
            last = result
            if result.ok:
                booked.add(day)
                booked_now.append(slot)
                rule.bookings_made += 1
                if rule.is_exhausted:
                    rule.is_active = False
            elif result.status in ('needs_action', 'auth_error'):
                break
        if booked_now:
            msg = 'Réservé : ' + ' ; '.join(f'{fr_datetime(s.local_start)} ({s.court_name})' for s in booked_now) + '.'
            return _finish(rule, now, 'booked', msg)
        if last is None:
            return _finish(rule, now, 'waiting', 'Rien à réserver pour le moment.')
        return _finish(rule, now, last.status, last.message)
    except ProviderAuthError as exc:
        if rule.account:
            rule.account.mark_needs_reauth(str(exc))
        return _finish(rule, now, 'auth_error', str(exc))
    except ProviderError as exc:
        logger.warning('Bot, règle %s : %s', rule.id, exc)
        return _finish(rule, now, 'error', str(exc))
    finally:
        rule.unlock()


def run_all(now=None, dry_run=False, rule_ids=None):
    now = now or timezone.now()
    cache = {}
    qs = AutoBookingRule.objects.filter(is_active=True).select_related('account', 'user')
    if rule_ids:
        qs = qs.filter(id__in=rule_ids)
    results = []
    for rule in qs:
        try:
            results.append(process_rule(rule, now=now, cache=cache, dry_run=dry_run))
        except Exception as exc:  # une règle cassée ne doit pas bloquer les autres
            logger.exception('Bot, règle %s', rule.id)
            results.append({'rule': rule.id, 'status': 'error', 'message': str(exc)})
    return results
