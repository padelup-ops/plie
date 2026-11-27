"""Radar des joueurs, disponibilités et propositions de match (contrat de l'app PadelUp actuelle)."""
import math
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.contrib.auth.models import User
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from app.models import BlockedUser, Friendship, Notification

from .models import TIME_SLOTS, Availability, MatchProposal, PlayerPresence

SLOT_LABELS = dict(TIME_SLOTS)
PRESENCE_MAX_AGE = timedelta(days=30)
MAX_PENDING_SENT = 20


def _float(value, lo, hi):
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    return v if lo <= v <= hi and not math.isnan(v) else None


def _int(value, default, lo, hi):
    try:
        v = int(value)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def _round_coord(value):
    return Decimal(str(value)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def _distance_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _avatar(user):
    profile = getattr(user, 'profile', None)
    if profile is None:
        return None
    if profile.external_avatar_url:
        return profile.external_avatar_url
    return profile.avatar.url if profile.avatar else None


def _availability_dict(a):
    return {
        'id': a.id,
        'day_of_week': a.day_of_week,
        'specific_date': a.specific_date.isoformat() if a.specific_date else None,
        'time_slot': a.time_slot,
        'time_slot_display': SLOT_LABELS.get(a.time_slot, a.time_slot),
        'radius_km': a.radius_km,
        'min_skill': a.min_skill,
        'max_skill': a.max_skill,
        'location_text': a.location_text,
    }


def _proposal_dict(p):
    return {
        'id': p.id,
        'sender_id': p.sender_id,
        'sender_username': p.sender.username,
        'sender_first_name': p.sender.first_name,
        'sender_avatar': _avatar(p.sender),
        'receiver_id': p.receiver_id,
        'receiver_username': p.receiver.username,
        'receiver_first_name': p.receiver.first_name,
        'receiver_avatar': _avatar(p.receiver),
        'proposed_date': p.proposed_date.isoformat(),
        'proposed_time_slot': p.proposed_time_slot,
        'time_slot_display': SLOT_LABELS.get(p.proposed_time_slot, p.proposed_time_slot),
        'message': p.message,
        'location_text': p.location_text,
        'status': p.status,
        'status_display': p.get_status_display(),
        'created_at': p.created_at.isoformat(),
    }


def _display_name(user):
    full = getattr(getattr(user, 'profile', None), 'full_name', '') or ''
    return full.split(' ')[0] if full else (user.first_name or user.username)


class RadarView(APIView):
    """GET : joueurs proches, visibles, du niveau voulu. PATCH : ma position (arrondie). DELETE : me masquer."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat = _float(request.query_params.get('lat'), -90, 90)
        lng = _float(request.query_params.get('lng'), -180, 180)
        if lat is None or lng is None:
            return Response({'error': 'Position requise (lat, lng).'}, status=status.HTTP_400_BAD_REQUEST)
        radius = _int(request.query_params.get('radius_km'), 15, 1, 50)
        min_skill = _int(request.query_params.get('min_skill'), 1, 1, 10)
        max_skill = _int(request.query_params.get('max_skill'), 10, min_skill, 10)
        time_slot = request.query_params.get('time_slot')
        day = request.query_params.get('day_of_week')
        day = _int(day, None, 0, 6) if day not in (None, '') else None

        # Pré-filtre par carré (1° de latitude ≈ 111 km), puis distance exacte.
        dlat = radius / 111.0
        dlng = radius / max(1.0, 111.0 * math.cos(math.radians(lat)))
        qs = (PlayerPresence.objects
              .filter(visible=True, updated_at__gte=timezone.now() - PRESENCE_MAX_AGE,
                      latitude__gte=lat - dlat, latitude__lte=lat + dlat,
                      longitude__gte=lng - dlng, longitude__lte=lng + dlng,
                      user__is_active=True)
              .exclude(user=request.user)
              .select_related('user', 'user__profile', 'user__stats'))
        blocked = set(BlockedUser.objects.filter(Q(blocker=request.user) | Q(blocked=request.user))
                      .values_list('blocker_id', 'blocked_id'))
        blocked_ids = {a for pair in blocked for a in pair} - {request.user.id}
        pending_with = set(MatchProposal.objects.filter(sender=request.user, status='pending').values_list('receiver_id', flat=True))
        today = timezone.localdate()

        results = []
        for presence in qs:
            user = presence.user
            if user.id in blocked_ids:
                continue
            profile = getattr(user, 'profile', None)
            level = (profile.skill_level if profile else None) or 1
            if not (min_skill <= level <= max_skill):
                continue
            km = _distance_km(lat, lng, float(presence.latitude), float(presence.longitude))
            if km > radius:
                continue
            avails = [a for a in user.availabilities.all() if a.specific_date is None or a.specific_date >= today]
            if time_slot and not any(a.time_slot == time_slot and (day is None or a.day_of_week == day) for a in avails):
                continue
            if day is not None and not time_slot and not any(a.day_of_week == day for a in avails):
                continue
            stats = getattr(user, 'stats', None)
            results.append({
                'user_id': user.id,
                'username': user.username,
                'first_name': _display_name(user),
                'avatar': _avatar(user),
                'skill_level': level,
                'evaluation_type': profile.evaluation_type if profile else 'new',
                'tier_name': profile.get_tier_name() if profile else '',
                'city': profile.location if profile else '',
                'distance_km': max(1.0, round(km * 2) / 2),   # arrondi au demi-km, jamais en dessous de 1 km
                'matches_played': stats.matches_played if stats else 0,
                'win_rate': stats.win_rate if stats else 0,
                'is_friend': Friendship.are_friends(request.user, user),
                'has_pending_proposal': user.id in pending_with,
                'availability': [_availability_dict(a) for a in avails[:6]],
            })
        results.sort(key=lambda r: (r['distance_km'], abs(r['skill_level'] - (getattr(request.user.profile, 'skill_level', 0) or 0))))
        me = PlayerPresence.objects.filter(user=request.user).first()
        return Response({'results': results[:100], 'count': len(results), 'radius_km': radius,
                         'visible': bool(me and me.visible)})

    def patch(self, request):
        lat = _float(request.data.get('lat'), -90, 90)
        lng = _float(request.data.get('lng'), -180, 180)
        if lat is None or lng is None:
            return Response({'error': 'Position invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        visible = request.data.get('visible', True)
        visible = visible if isinstance(visible, bool) else str(visible).lower() in ('1', 'true', 'oui')
        PlayerPresence.objects.update_or_create(user=request.user, defaults={
            'latitude': _round_coord(lat), 'longitude': _round_coord(lng), 'visible': visible})
        return Response({'visible': visible})

    def delete(self, request):
        PlayerPresence.objects.filter(user=request.user).update(visible=False)
        return Response({'visible': False})


class AvailabilityListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        today = timezone.localdate()
        items = request.user.availabilities.filter(Q(specific_date__isnull=True) | Q(specific_date__gte=today))
        return Response([_availability_dict(a) for a in items])

    def post(self, request):
        data = request.data
        slot = data.get('time_slot')
        if slot not in SLOT_LABELS:
            return Response({'error': 'Créneau invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        day = data.get('day_of_week')
        day = _int(day, None, 0, 6) if day not in (None, '') else None
        specific = None
        if data.get('specific_date'):
            try:
                from datetime import date
                specific = date.fromisoformat(str(data.get('specific_date')))
            except ValueError:
                return Response({'error': 'Date invalide.'}, status=status.HTTP_400_BAD_REQUEST)
            if specific < timezone.localdate():
                return Response({'error': 'Cette date est passée.'}, status=status.HTTP_400_BAD_REQUEST)
        if day is None and specific is None:
            return Response({'error': 'Choisis un jour de la semaine ou une date.'}, status=status.HTTP_400_BAD_REQUEST)
        if request.user.availabilities.count() >= 30:
            return Response({'error': 'Trop de disponibilités : supprime-en quelques-unes.'}, status=status.HTTP_400_BAD_REQUEST)
        min_skill = _int(data.get('min_skill'), 1, 1, 10)
        a = Availability.objects.create(
            user=request.user, day_of_week=day, specific_date=specific, time_slot=slot,
            radius_km=_int(data.get('radius_km'), 10, 2, 50), min_skill=min_skill,
            max_skill=_int(data.get('max_skill'), 10, min_skill, 10),
            location_text=str(data.get('location_text') or '')[:120])
        return Response(_availability_dict(a), status=status.HTTP_201_CREATED)


class AvailabilityDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, avail_id):
        deleted, _ = Availability.objects.filter(id=avail_id, user=request.user).delete()
        if not deleted:
            return Response({'error': 'Introuvable.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'deleted': True})


class ProposalListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        sent = MatchProposal.objects.filter(sender=request.user).select_related('sender__profile', 'receiver__profile')[:50]
        received = MatchProposal.objects.filter(receiver=request.user).exclude(status='cancelled') \
            .select_related('sender__profile', 'receiver__profile')[:50]
        return Response({'sent': [_proposal_dict(p) for p in sent], 'received': [_proposal_dict(p) for p in received]})

    def post(self, request):
        data = request.data
        try:
            receiver = User.objects.get(id=int(data.get('receiver_id')), is_active=True)
        except (TypeError, ValueError, User.DoesNotExist):
            return Response({'error': 'Joueur introuvable.'}, status=status.HTTP_404_NOT_FOUND)
        if receiver.id == request.user.id:
            return Response({'error': 'Impossible de te proposer un match à toi-même.'}, status=status.HTTP_400_BAD_REQUEST)
        if BlockedUser.is_blocked(request.user, receiver):
            return Response({'error': 'Joueur introuvable.'}, status=status.HTTP_404_NOT_FOUND)
        slot = data.get('proposed_time_slot')
        if slot not in SLOT_LABELS:
            return Response({'error': 'Créneau invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        try:
            from datetime import date
            when = date.fromisoformat(str(data.get('proposed_date')))
        except ValueError:
            return Response({'error': 'Date invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        if when < timezone.localdate() or when > timezone.localdate() + timedelta(days=60):
            return Response({'error': 'Choisis une date dans les deux prochains mois.'}, status=status.HTTP_400_BAD_REQUEST)
        if MatchProposal.objects.filter(sender=request.user, status='pending').count() >= MAX_PENDING_SENT:
            return Response({'error': 'Trop de propositions en attente.'}, status=status.HTTP_429_TOO_MANY_REQUESTS)
        if MatchProposal.objects.filter(sender=request.user, receiver=receiver, proposed_date=when,
                                        proposed_time_slot=slot, status='pending').exists():
            return Response({'error': 'Proposition déjà envoyée.'}, status=status.HTTP_400_BAD_REQUEST)
        lat = _float(data.get('location_lat'), -90, 90)
        lng = _float(data.get('location_lng'), -180, 180)
        p = MatchProposal.objects.create(
            sender=request.user, receiver=receiver, proposed_date=when, proposed_time_slot=slot,
            message=str(data.get('message') or '')[:500], location_text=str(data.get('location_text') or '')[:120],
            location_lat=Decimal(str(round(lat, 6))) if lat is not None else None,
            location_lng=Decimal(str(round(lng, 6))) if lng is not None else None)
        Notification.objects.create(
            user=receiver, type='match_proposal',
            message=f"{_display_name(request.user)} te propose un match le {when.strftime('%d/%m')} ({SLOT_LABELS[slot].lower()}).")
        return Response(_proposal_dict(p), status=status.HTTP_201_CREATED)


class ProposalDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request, proposal_id):
        action = request.data.get('action')
        if action not in ('accept', 'decline'):
            return Response({'error': 'Action invalide.'}, status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            p = MatchProposal.objects.select_for_update().filter(id=proposal_id, receiver=request.user).first()
            if p is None:
                return Response({'error': 'Introuvable.'}, status=status.HTTP_404_NOT_FOUND)
            if p.status != 'pending':
                return Response({'error': 'Cette proposition a déjà une réponse.'}, status=status.HTTP_400_BAD_REQUEST)
            p.status = 'accepted' if action == 'accept' else 'declined'
            p.responded_at = timezone.now()
            p.save(update_fields=['status', 'responded_at'])
        if p.status == 'accepted':
            Notification.objects.create(
                user=p.sender, type='match_proposal_accepted',
                message=f"{_display_name(request.user)} accepte ton match du {p.proposed_date.strftime('%d/%m')}. Réserve un terrain !")
        return Response(_proposal_dict(p))

    def delete(self, request, proposal_id):
        updated = MatchProposal.objects.filter(id=proposal_id, sender=request.user, status='pending').update(status='cancelled')
        if not updated:
            return Response({'error': 'Introuvable.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'cancelled': True})
