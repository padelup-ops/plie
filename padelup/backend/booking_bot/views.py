"""API du bot de réservation (/api/bot/...)."""
import hmac
import os
from datetime import date, timedelta

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle
from rest_framework.views import APIView

from . import engine
from .models import AutoBookingRule, BotAttempt, ProviderAccount
from .providers import PROVIDERS, ProviderAuthError, ProviderError, Slot, get_provider
from .serializers import (AutoBookingRuleSerializer, BotAttemptSerializer, ConnectAccountSerializer,
                          ProviderAccountSerializer)


class BotThrottle(UserRateThrottle):
    rate = '60/min'


def _float(value):
    try:
        return float(value) if value not in (None, '') else None
    except (TypeError, ValueError):
        return None


def _account_for(user, provider_code):
    cls = PROVIDERS.get(provider_code)
    if not cls:
        raise ProviderError('Plateforme inconnue.')
    if not cls.needs_account:
        return None
    account = ProviderAccount.objects.filter(user=user, provider=provider_code).first()
    if not account:
        raise ProviderAuthError(f'Connecte d’abord ton compte {cls.name}.')
    return account


def _provider_error(exc):
    code = status.HTTP_401_UNAUTHORIZED if isinstance(exc, ProviderAuthError) else status.HTTP_502_BAD_GATEWAY
    return Response({'error': str(exc), 'reconnect': isinstance(exc, ProviderAuthError)}, status=code)


class ProvidersView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response([{
            'code': p.code, 'name': p.name, 'needs_account': p.needs_account, 'description': p.description,
        } for p in PROVIDERS.values()])


class AccountListView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [BotThrottle]

    def get(self, request):
        return Response(ProviderAccountSerializer(request.user.provider_accounts.all(), many=True).data)

    def post(self, request):
        """Connecte un compte : on se connecte à la plateforme et on garde seulement ses jetons (chiffrés)."""
        ser = ConnectAccountSerializer(data=request.data)
        if not ser.is_valid():
            return Response({'error': 'E-mail et mot de passe requis.', 'details': ser.errors}, status=400)
        code = ser.validated_data['provider']
        provider = get_provider(code, request.user)
        try:
            tokens = provider.connect(ser.validated_data['email'], ser.validated_data['password'])
        except ProviderError as exc:
            return _provider_error(exc)
        account, _ = ProviderAccount.objects.get_or_create(user=request.user, provider=code)
        account.login_email = ser.validated_data['email']
        account.apply_tokens(tokens)
        # Les règles de cette plateforme reprennent automatiquement avec le compte reconnecté.
        AutoBookingRule.objects.filter(user=request.user, provider=code).update(account=account)
        return Response(ProviderAccountSerializer(account).data, status=201)


class AccountDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, account_id):
        account = get_object_or_404(ProviderAccount, pk=account_id, user=request.user)
        AutoBookingRule.objects.filter(account=account).update(is_active=False)
        account.delete()
        return Response(status=204)


class ClubSearchView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [BotThrottle]

    def get(self, request):
        code = request.query_params.get('provider', 'playtomic')
        try:
            provider = get_provider(code, request.user)
            radius = min(max(_float(request.query_params.get('radius')) or 30, 1), 200)
            clubs = provider.search_clubs(_float(request.query_params.get('lat')), _float(request.query_params.get('lon')),
                                          radius, request.query_params.get('q', '')[:200])
        except ProviderError as exc:
            return _provider_error(exc)
        return Response([c.to_dict() for c in clubs])


class SlotsView(APIView):
    """Disponibilités d'un club : ?provider=playtomic&club_id=...&date=2026-12-01&days=3"""
    permission_classes = [IsAuthenticated]
    throttle_classes = [BotThrottle]

    def get(self, request):
        code = request.query_params.get('provider', 'playtomic')
        club_id = request.query_params.get('club_id', '').strip()
        if not club_id:
            return Response({'error': 'club_id requis.'}, status=400)
        try:
            start = date.fromisoformat(request.query_params.get('date') or date.today().isoformat())
            days = min(max(int(request.query_params.get('days', 1)), 1), 7)
        except ValueError:
            return Response({'error': 'Date ou nombre de jours invalide.'}, status=400)
        if start < date.today() - timedelta(days=1) or start > date.today() + timedelta(days=60):
            return Response({'error': 'Date hors limites.'}, status=400)
        try:
            provider = get_provider(code, request.user)
            club = provider.get_club(club_id)
            out = []
            for i in range(days):
                day = start + timedelta(days=i)
                out.append({'date': day.isoformat(), 'slots': [s.to_dict() for s in provider.list_slots(club_id, day)]})
        except ProviderError as exc:
            return _provider_error(exc)
        return Response({'provider': code, 'club': club.to_dict(), 'days': out})


class BookNowView(APIView):
    """Le joueur touche un créneau affiché : le bot fait toute la réservation à sa place."""
    permission_classes = [IsAuthenticated]
    throttle_classes = [BotThrottle]

    def post(self, request):
        code = request.data.get('provider', 'playtomic')
        try:
            slot = Slot.from_dict(request.data.get('slot') or {})
        except (KeyError, TypeError, ValueError):
            return Response({'error': 'Créneau invalide.'}, status=400)
        try:
            account = _account_for(request.user, code)
            attempt, result = engine.book_slot(request.user, code, account, slot,
                                               club_name=str(request.data.get('club_name', ''))[:200])
        except ProviderError as exc:
            return _provider_error(exc)
        http = 201 if result.ok else 202 if result.status == 'needs_action' else 409
        return Response({'status': result.status, 'message': result.message, 'action_url': result.action_url,
                         'attempt': BotAttemptSerializer(attempt).data}, status=http)


class RuleListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(AutoBookingRuleSerializer(request.user.auto_booking_rules.all(), many=True).data)

    def post(self, request):
        ser = AutoBookingRuleSerializer(data=request.data)
        if not ser.is_valid():
            return Response({'error': 'Règle invalide.', 'details': ser.errors}, status=400)
        code = ser.validated_data['provider']
        try:
            account = _account_for(request.user, code)
        except ProviderError as exc:
            return _provider_error(exc)
        if request.user.auto_booking_rules.filter(is_active=True).count() >= 20:
            return Response({'error': 'Maximum 20 règles actives.'}, status=400)
        rule = ser.save(user=request.user, account=account)
        result = engine.process_rule(rule)  # premier passage tout de suite
        rule.refresh_from_db()
        return Response({**AutoBookingRuleSerializer(rule).data, 'first_run': result}, status=201)


class RuleDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get_rule(self, request, rule_id):
        return get_object_or_404(AutoBookingRule, pk=rule_id, user=request.user)

    def get(self, request, rule_id):
        return Response(AutoBookingRuleSerializer(self.get_rule(request, rule_id)).data)

    def patch(self, request, rule_id):
        rule = self.get_rule(request, rule_id)
        ser = AutoBookingRuleSerializer(rule, data=request.data, partial=True)
        if not ser.is_valid():
            return Response({'error': 'Règle invalide.', 'details': ser.errors}, status=400)
        rule = ser.save()
        return Response(AutoBookingRuleSerializer(rule).data)

    put = patch

    def delete(self, request, rule_id):
        self.get_rule(request, rule_id).delete()
        return Response(status=204)


class RuleRunView(APIView):
    permission_classes = [IsAuthenticated]
    throttle_classes = [BotThrottle]

    def post(self, request, rule_id):
        rule = get_object_or_404(AutoBookingRule, pk=rule_id, user=request.user)
        result = engine.process_rule(rule)
        rule.refresh_from_db()
        return Response({**AutoBookingRuleSerializer(rule).data, 'run': result})


class AttemptListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = BotAttempt.objects.filter(user=request.user)
        if request.query_params.get('rule', '').isdigit():
            qs = qs.filter(rule_id=int(request.query_params['rule']))
        return Response(BotAttemptSerializer(qs[:100], many=True).data)


class TickView(APIView):
    """Pour un cron externe (cron-job.org, Render Cron...) quand aucun service « worker » ne tourne."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        secret = os.environ.get('BOT_CRON_SECRET', '')
        given = request.headers.get('X-Bot-Secret', '')
        if not secret or not hmac.compare_digest(secret, given):
            return Response({'error': 'Interdit.'}, status=403)
        results = engine.run_all()
        return Response({'rules': len(results), 'booked': sum(1 for r in results if r['status'] == 'booked')})
