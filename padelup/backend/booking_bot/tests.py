"""Tests du bot de réservation : moteur, fournisseurs (Playtomic simulé, Anybuddy simulé, clubs PadelUp réels), API."""
from datetime import datetime, time, timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from app.models import Booking, Club, Court, Notification
from . import crypto, engine
from .models import AutoBookingRule, BotAttempt, ProviderAccount
from .providers import PlaytomicProvider
from .providers.anybuddy import AnybuddyProvider, club_slug

NO_THROTTLE = {'DEFAULT_THROTTLE_RATES': {'auth': '10000/min', 'user': '10000/min', 'anon': '10000/min'},
               'DEFAULT_AUTHENTICATION_CLASSES': ['rest_framework.authentication.TokenAuthentication'],
               'EXCEPTION_HANDLER': 'app.exceptions.custom_exception_handler'}


class FakeResponse:
    def __init__(self, status=200, data=None):
        self.status_code = status
        self._data = data
        self.content = b'x' if data is not None else b''
        self.headers = {'content-type': 'application/json'}
        self.text = str(data)

    def json(self):
        if self._data is None:
            raise ValueError
        return self._data


class FakeSession:
    """Remplace requests.Session : renvoie les réponses prévues selon (méthode, chemin) et garde les appels."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []
        self.headers = {}

    def request(self, method, url, **kwargs):
        path = url.split('://', 1)[1].split('/', 1)[1]
        self.calls.append((method, '/' + path, kwargs))
        for (m, prefix), resp in self.routes.items():
            if m == method and ('/' + path).startswith(prefix):
                return resp(kwargs) if callable(resp) else resp
        return FakeResponse(404, {})

    def get(self, url, **kwargs):
        return self.request('GET', url, **kwargs)

    def post(self, url, **kwargs):
        return self.request('POST', url, **kwargs)


def tomorrow_local(tz='Europe/Madrid'):
    from zoneinfo import ZoneInfo
    return (timezone.now().astimezone(ZoneInfo(tz)) + timedelta(days=1)).date()


TENANT = {
    'tenant_id': 'T1', 'tenant_name': 'Padel Indoor Madrid',
    'address': {'city': 'Madrid', 'timezone': 'Europe/Madrid', 'coordinate': {'lat': 40.4, 'lon': -3.7}},
    'resources': [
        {'resource_id': 'R1', 'name': 'Pista 1', 'sport_id': 'PADEL', 'properties': {'resource_type': 'indoor'}},
        {'resource_id': 'R2', 'name': 'Pista 2', 'sport_id': 'PADEL', 'properties': {'resource_type': 'outdoor'}},
    ],
}


def availability_for(day):
    # 18:00 UTC = 19:00 à Madrid en hiver
    return [
        {'resource_id': 'R1', 'start_date': day.isoformat(), 'slots': [
            {'start_time': '17:00:00', 'duration': 90, 'price': '36 EUR'},
            {'start_time': '18:00:00', 'duration': 90, 'price': '36 EUR'},
        ]},
        {'resource_id': 'R2', 'start_date': day.isoformat(), 'slots': [
            {'start_time': '18:00:00', 'duration': 60, 'price': '20 EUR'},
        ]},
    ]


class CryptoTests(TestCase):
    def test_roundtrip_and_tokens_never_stored_in_clear(self):
        user = User.objects.create_user('c', 'c@example.com', 'x')
        acc = ProviderAccount.objects.create(user=user, provider='playtomic')
        acc.access_token = 'secret-token'
        acc.save()
        acc.refresh_from_db()
        self.assertEqual(acc.access_token, 'secret-token')
        self.assertNotIn('secret-token', acc.access_token_encrypted)
        self.assertEqual(crypto.decrypt('not-a-token'), '')


class PlaytomicProviderTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('p', 'p@example.com', 'x')
        self.acc = ProviderAccount.objects.create(user=self.user, provider='playtomic', external_user_id='U1',
                                                  token_expires_at=timezone.now() + timedelta(hours=1))
        self.acc.access_token = 'AT'
        self.acc.refresh_token = 'RT'
        self.acc.save()
        self.day = tomorrow_local()

    def provider(self, routes):
        return PlaytomicProvider(user=self.user, account=self.acc, session=FakeSession(routes))

    def test_connect_returns_tokens(self):
        p = PlaytomicProvider(session=FakeSession({('POST', '/v3/auth/login'): FakeResponse(200, {
            'access_token': 'A', 'refresh_token': 'R', 'user_id': 42, 'access_token_expiration': '2030-01-01T00:00:00'})}))
        tokens = p.connect('a@b.c', 'pw')
        self.assertEqual(tokens['external_user_id'], '42')
        self.assertEqual(tokens['access_token'], 'A')

    def test_slots_are_converted_to_club_timezone(self):
        p = self.provider({('GET', '/v1/tenants/T1'): FakeResponse(200, TENANT),
                           ('GET', '/v1/availability'): FakeResponse(200, availability_for(self.day))})
        slots = p.list_slots('T1', self.day)
        self.assertEqual(len(slots), 3)
        s = [x for x in slots if x.resource_id == 'R1' and x.raw_start.endswith('18:00:00')][0]
        self.assertEqual(s.price, Decimal('36'))
        self.assertTrue(s.indoor)
        self.assertEqual(s.local_start.strftime('%H:%M'), '19:00')

    def test_book_with_pay_at_club(self):
        calls = {}

        def confirm(kwargs):
            calls['confirmed'] = True
            return FakeResponse(200, {'status': 'SUCCEEDED', 'cart': {'item': {'cart_item_data': {'match_id': 'M9'}}}})
        p = self.provider({
            ('POST', '/v1/payment_intents/PI1/confirmation'): confirm,
            ('POST', '/v1/payment_intents'): FakeResponse(200, {'payment_intent_id': 'PI1', 'available_payment_methods': [
                {'payment_method_id': 'CREDIT_CARD-STRIPE_x', 'method_type': 'CREDIT_CARD'},
                {'payment_method_id': 'CASH', 'name': 'At the club', 'method_type': 'CASH'}]}),
            ('PATCH', '/v1/payment_intents/PI1'): FakeResponse(200, {}),
        })
        slot = engine.Slot if False else None  # noqa
        from .providers.base import Slot
        slot = Slot(club_id='T1', resource_id='R1', court_name='Pista 1', start=timezone.now() + timedelta(days=1),
                    duration=90, raw_start=f'{self.day}T18:00:00')
        result = p.book(slot)
        self.assertEqual(result.status, 'booked')
        self.assertEqual(result.external_id, 'M9')
        patch = [c for c in p.http.calls if c[0] == 'PATCH'][0]
        self.assertEqual(patch[2]['json']['selected_payment_method_id'], 'CASH')

    def test_card_only_club_needs_action(self):
        p = self.provider({('POST', '/v1/payment_intents'): FakeResponse(200, {'payment_intent_id': 'PI2', 'available_payment_methods': [
            {'payment_method_id': 'CREDIT_CARD-STRIPE_x', 'method_type': 'CREDIT_CARD'}]})})
        from .providers.base import Slot
        result = p.book(Slot(club_id='T1', resource_id='R1', court_name='Pista 1', start=timezone.now(), duration=90,
                             raw_start='2030-01-01T18:00:00'))
        self.assertEqual(result.status, 'needs_action')
        self.assertIn('playtomic.io', result.action_url)

    def test_expired_token_is_refreshed(self):
        self.acc.token_expires_at = timezone.now() - timedelta(minutes=1)
        self.acc.save()
        p = self.provider({('POST', '/v3/auth/token'): FakeResponse(200, {'access_token': 'NEW', 'refresh_token': 'RT2'}),
                           ('POST', '/v1/payment_intents'): FakeResponse(409, {'message': 'not available'})})
        from .providers.base import Slot, SlotUnavailable
        with self.assertRaises(SlotUnavailable):
            p.book(Slot(club_id='T1', resource_id='R1', court_name='Pista 1', start=timezone.now(), duration=90, raw_start='x'))
        self.acc.refresh_from_db()
        self.assertEqual(self.acc.access_token, 'NEW')


class AnybuddyTests(TestCase):
    def test_slug_and_slots(self):
        self.assertEqual(club_slug('https://www.anybuddyapp.com/fr/club/padel-horizon-paris'), 'padel-horizon-paris')
        session = FakeSession({('GET', '/api/v1/availabilities'): FakeResponse(200, {'data': [
            {'startDateTime': '2030-06-22T19:00', 'services': [{'id': 's1', 'duration': 90, 'price': 4800, 'discountPrice': 4200,
                                                                'slotId': 'abc', 'name': 'Padel 2'}]}]})})
        p = AnybuddyProvider(session=session)
        slots = p.list_slots('padel-horizon-paris', datetime(2030, 6, 22).date())
        self.assertEqual(len(slots), 1)
        self.assertEqual(slots[0].price, Decimal('42.00'))
        self.assertEqual(slots[0].local_start.strftime('%H:%M'), '19:00')


@override_settings(REST_FRAMEWORK=NO_THROTTLE, EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class EngineTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('bot', 'bot@example.com', 'x')
        self.club = Club.objects.create(name='Club Bot', address='a', city='Tunis', postal_code='1', latitude=Decimal('36.8'),
                                        longitude=Decimal('10.1'), phone='1', email='a@example.com', currency='TND',
                                        opening_hours={})
        self.court = Court.objects.create(club=self.club, name='Court A', price_per_hour=Decimal('30'), is_indoor=True)
        self.day = timezone.localdate() + timedelta(days=2)

    def rule(self, **extra):
        data = dict(user=self.user, provider='padelup', club_external_id=str(self.club.id), club_name='Club Bot',
                    weekdays=[self.day.weekday()], time_from=time(19, 0), time_to=time(20, 0), durations=[90],
                    days_ahead=3, min_notice_minutes=0, mode='book', max_bookings=1)
        data.update(extra)
        return AutoBookingRule.objects.create(**data)

    def test_rule_books_automatically_and_stops(self):
        r = self.rule()
        out = engine.process_rule(r)
        self.assertEqual(out['status'], 'booked', out)
        b = Booking.objects.get(user=self.user)
        self.assertEqual((b.date, b.start_time, b.duration), (self.day, time(19, 0), 90))
        r.refresh_from_db()
        self.assertFalse(r.is_active)
        self.assertTrue(Notification.objects.filter(user=self.user, type='bot_booked').exists())
        # Un second passage ne réserve rien de plus
        self.assertEqual(engine.process_rule(r)['status'], 'inactive')
        self.assertEqual(Booking.objects.count(), 1)

    def test_rule_skips_taken_slots(self):
        other = User.objects.create_user('o', 'o@example.com', 'x')
        Booking.objects.create(court=self.court, user=other, date=self.day, start_time=time(18, 30), end_time=time(20, 0), duration=90)
        r = self.rule(time_to=time(21, 0))
        engine.process_rule(r)
        b = Booking.objects.get(user=self.user)
        self.assertEqual(b.start_time, time(20, 0))

    def test_notify_mode_does_not_book_and_does_not_repeat(self):
        r = self.rule(mode='notify')
        self.assertEqual(engine.process_rule(r)['status'], 'found')
        self.assertEqual(Booking.objects.count(), 0)
        engine.process_rule(r)
        self.assertEqual(BotAttempt.objects.filter(rule=r, status='notified').count(), 1)

    def test_recurring_rule_books_each_matching_day_once(self):
        days = [(self.day + timedelta(days=i)) for i in range(3)]
        r = self.rule(weekdays=sorted({d.weekday() for d in days}), max_bookings=0, days_ahead=6)
        engine.process_rule(r)
        engine.process_rule(r)
        dates = sorted(Booking.objects.filter(user=self.user).values_list('date', flat=True))
        self.assertEqual(len(dates), len(set(dates)))
        self.assertGreaterEqual(len(dates), 3)

    def test_api_flow_slots_then_book_now(self):
        api = APIClient()
        api.force_authenticate(self.user)
        r = api.get(f'/api/bot/slots/?provider=padelup&club_id={self.club.id}&date={self.day}')
        self.assertEqual(r.status_code, 200, r.data)
        slot = [s for s in r.data['days'][0]['slots'] if s['local_time'] == '10:00' and s['duration'] == 60][0]
        r = api.post('/api/bot/book/', {'provider': 'padelup', 'slot': slot, 'club_name': 'Club Bot'}, format='json')
        self.assertEqual(r.status_code, 201, r.data)
        r = api.post('/api/bot/book/', {'provider': 'padelup', 'slot': slot}, format='json')
        self.assertEqual(r.status_code, 409)  # déjà pris

    def test_api_requires_connected_account_for_playtomic(self):
        api = APIClient()
        api.force_authenticate(self.user)
        r = api.post('/api/bot/rules/', {'provider': 'playtomic', 'club_external_id': 'T1', 'club_name': 'X', 'weekdays': [1],
                                         'time_from': '19:00', 'time_to': '21:00', 'durations': [90]}, format='json')
        self.assertEqual(r.status_code, 401)
        self.assertTrue(r.data['reconnect'])

    def test_tick_needs_secret(self):
        api = APIClient()
        self.assertEqual(api.post('/api/bot/tick/').status_code, 403)
        with mock.patch.dict('os.environ', {'BOT_CRON_SECRET': 's3cret'}):
            self.assertEqual(api.post('/api/bot/tick/', HTTP_X_BOT_SECRET='s3cret').status_code, 200)
