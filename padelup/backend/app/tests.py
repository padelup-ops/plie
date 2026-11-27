"""Tests de non-régression des correctifs de l'audit (sécurité, réservations, matchs, open data)."""
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient, APITestCase

from .models import (Booking, Club, Court, EmailVerificationCode, Match, MatchMessage, MatchParticipant,
                     PasswordResetCode, PlayerStats)
from . import opendata

NO_THROTTLE = {'DEFAULT_THROTTLE_RATES': {'auth': '10000/min', 'user': '10000/min', 'anon': '10000/min'},
               'DEFAULT_AUTHENTICATION_CLASSES': ['rest_framework.authentication.TokenAuthentication'],
               'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination', 'PAGE_SIZE': 10,
               'EXCEPTION_HANDLER': 'app.exceptions.custom_exception_handler'}


def make_user(name, **extra):
    user = User.objects.create_user(name, f'{name}@example.com', 'Sup3r-secret-pass', **extra)
    user.profile.is_completed = True
    user.profile.save()
    return user


def make_club(**extra):
    data = dict(name='Club Test', address='1 rue', city='Tunis', postal_code='1000', latitude=Decimal('36.8'),
                longitude=Decimal('10.18'), phone='1', email='c@example.com', currency='TND',
                opening_hours={k: '08:00-23:00' for k in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday',
                                                         'saturday', 'sunday']})
    data.update(extra)
    return Club.objects.create(**data)


@override_settings(REST_FRAMEWORK=NO_THROTTLE, EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class AuthSecurityTests(TestCase):
    def setUp(self):
        self.api = APIClient()

    def test_register_cannot_create_staff(self):
        r = self.api.post('/api/auth/register/', {'username': 'evil', 'email': 'evil@example.com', 'password': 'Sup3r-secret-pass',
                                                  'password2': 'Sup3r-secret-pass', 'is_staff': True, 'is_active': True}, format='json')
        self.assertEqual(r.status_code, 201)
        user = User.objects.get(username='evil')
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_active)

    @mock.patch.dict('os.environ', {'AUTO_VERIFY_EMAIL': 'true'})
    def test_test_server_signup_without_email_code(self):
        r = self.api.post('/api/auth/register/', {'username': 'tester', 'email': 'tester@example.com', 'password': 'Sup3r-secret-pass',
                                                  'password2': 'Sup3r-secret-pass'}, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertFalse(r.data['verification_required'])
        self.assertTrue(Token.objects.filter(key=r.data['token']).exists())
        self.assertTrue(User.objects.get(username='tester').is_active)

    def test_email_duplicate_case_insensitive(self):
        make_user('dup')
        r = self.api.post('/api/auth/register/', {'username': 'dup2', 'email': 'DUP@example.com', 'password': 'Sup3r-secret-pass',
                                                  'password2': 'Sup3r-secret-pass'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_verification_code_locks_after_five_failures(self):
        self.api.post('/api/auth/register/', {'username': 'neo', 'email': 'neo@example.com', 'password': 'Sup3r-secret-pass',
                                              'password2': 'Sup3r-secret-pass'}, format='json')
        code = EmailVerificationCode.objects.get(user__username='neo').code
        wrong = '000000' if code != '000000' else '111111'
        for _ in range(5):
            self.assertEqual(self.api.post('/api/auth/register/verify/', {'email': 'neo@example.com', 'code': wrong}, format='json').status_code, 400)
        r = self.api.post('/api/auth/register/verify/', {'email': 'neo@example.com', 'code': code}, format='json')
        self.assertEqual(r.status_code, 400)  # le bon code ne marche plus : il faut en redemander un

    def test_verify_accepts_numeric_code_without_crash(self):
        r = self.api.post('/api/auth/register/verify/', {'email': 'x@example.com', 'code': 123456}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_unverified_login_says_verification_required(self):
        user = make_user('pending')
        user.is_active = False
        user.save()
        r = self.api.post('/api/auth/login/', {'email': 'pending@example.com', 'password': 'Sup3r-secret-pass'}, format='json')
        self.assertEqual(r.status_code, 403)
        self.assertTrue(r.data['verification_required'])

    def test_login_messages_do_not_reveal_accounts(self):
        make_user('known')
        a = self.api.post('/api/auth/login/', {'email': 'known@example.com', 'password': 'wrong-password'}, format='json')
        b = self.api.post('/api/auth/login/', {'email': 'nobody@example.com', 'password': 'wrong-password'}, format='json')
        self.assertEqual(a.data, b.data)

    def test_password_reset_revokes_tokens_and_is_case_insensitive(self):
        user = make_user('reset')
        token = Token.objects.create(user=user)
        self.api.post('/api/auth/password-reset/', {'email': 'Reset@Example.com'}, format='json')
        code = PasswordResetCode.objects.get(user=user).code
        r = self.api.post('/api/auth/password-reset/confirm/', {'email': 'RESET@example.com', 'code': code,
                                                               'new_password': 'Another-strong-pass9'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertFalse(Token.objects.filter(key=token.key).exists())

    def test_weak_password_rejected_on_reset(self):
        user = make_user('weak')
        self.api.post('/api/auth/password-reset/', {'email': 'weak@example.com'}, format='json')
        code = PasswordResetCode.objects.get(user=user).code
        r = self.api.post('/api/auth/password-reset/confirm/', {'email': 'weak@example.com', 'code': code, 'new_password': 'abcdefgh'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_google_login_requires_configured_audience(self):
        r = self.api.post('/api/auth/google/', {'id_token': 'abc'}, format='json')
        self.assertEqual(r.status_code, 503)

    @mock.patch.dict('os.environ', {'GOOGLE_CLIENT_IDS': 'our-client'})
    @mock.patch('app.views.http_requests.get')
    def test_google_token_for_other_app_rejected(self, get):
        get.return_value = mock.Mock(status_code=200, json=lambda: {'aud': 'someone-else', 'email': 'v@example.com', 'email_verified': 'true'})
        r = self.api.post('/api/auth/google/', {'id_token': 'abc'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_email_hidden_from_other_players(self):
        me, other = make_user('me'), make_user('other')
        self.api.force_authenticate(me)
        r = self.api.get(f'/api/profile/{other.id}/')
        self.assertEqual(r.status_code, 200)
        self.assertNotIn('email', r.data['user'])
        board = self.api.get('/api/leaderboard/?limit=abc')
        self.assertEqual(board.status_code, 200)
        self.assertTrue(all('email' not in row['user'] for row in board.data if row['user']['id'] != me.id))
        self.assertTrue(any('email' in row['user'] for row in board.data if row['user']['id'] == me.id))


@override_settings(REST_FRAMEWORK=NO_THROTTLE, EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class BookingTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.user = make_user('player')
        self.api.force_authenticate(self.user)
        self.club = make_club()
        self.court = Court.objects.create(club=self.club, name='Court 1', price_per_hour=Decimal('40'),
                                          prices={'peak': 60, 'off_peak': 40})
        self.day = (timezone.localdate() + timedelta(days=2))

    def book(self, start, end, **extra):
        return self.api.post('/api/bookings/', {'court': self.court.id, 'date': self.day.isoformat(), 'start_time': start,
                                                'end_time': end, **extra}, format='json')

    def test_overlap_rejected(self):
        self.assertEqual(self.book('18:00', '19:30').status_code, 201)
        self.assertEqual(self.book('19:00', '20:00').status_code, 400)

    def test_price_and_status_are_server_side(self):
        r = self.book('18:30', '20:00', payment_status='paid', total_amount='1', duration=1, status='completed')
        self.assertEqual(r.status_code, 201)
        b = Booking.objects.get(pk=r.data['id'])
        self.assertEqual(b.payment_status, 'pending')
        self.assertEqual(b.status, 'confirmed')
        self.assertEqual(b.duration, 90)
        self.assertEqual(b.total_amount, Decimal('90.00'))  # tarif « peak » de l'heure du créneau, 1 h 30

    def test_past_reversed_and_unavailable_rejected(self):
        past = (timezone.localdate() - timedelta(days=1)).isoformat()
        r = self.api.post('/api/bookings/', {'court': self.court.id, 'date': past, 'start_time': '10:00', 'end_time': '11:00'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.book('11:00', '10:00').status_code, 400)
        self.court.is_available = False
        self.court.save()
        self.assertEqual(self.book('10:00', '11:00').status_code, 400)

    def test_cancelled_slot_can_be_rebooked(self):
        r = self.book('10:00', '11:00')
        Booking.objects.filter(pk=r.data['id']).update(status='cancelled')
        self.assertEqual(self.book('10:00', '11:00').status_code, 201)

    def test_bad_dates_do_not_crash(self):
        self.assertEqual(self.api.get('/api/bookings/?date_from=abc&date_to=2025-13-01').status_code, 200)


@override_settings(REST_FRAMEWORK=NO_THROTTLE, EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class MatchTests(TestCase):
    def setUp(self):
        self.api = APIClient()
        self.org = make_user('org')
        self.club = make_club()

    def create_match(self, **extra):
        data = dict(title='Match', club=self.club, organizer=self.org, date_time=timezone.now() + timedelta(days=1),
                    max_players=4, is_public=True)
        data.update(extra)
        m = Match.objects.create(**data)
        MatchParticipant.objects.create(match=m, user=self.org, status='confirmed')
        return m

    def test_match_in_progress_then_completed(self):
        m = self.create_match(date_time=timezone.now() - timedelta(minutes=10), duration=90)
        m.update_status()
        self.assertEqual(m.status, 'in_progress')
        Match.objects.filter(pk=m.pk).update(date_time=timezone.now() - timedelta(minutes=100))
        m.refresh_from_db()
        m.update_status()
        self.assertEqual(m.status, 'completed')
        self.assertFalse(m.winners.exists())  # seul dans son match : pas de victoire offerte
        self.assertEqual(PlayerStats.objects.get(user=self.org).matches_won, 0)

    def test_client_cannot_set_status_or_winners(self):
        self.api.force_authenticate(self.org)
        r = self.api.post('/api/matches/', {'title': 'Soirée', 'club': self.club.id, 'date_time': (timezone.now() + timedelta(days=1)).isoformat(),
                                            'status': 'completed', 'winners': [self.org.id]}, format='json')
        self.assertEqual(r.status_code, 201, r.data)
        m = Match.objects.get(pk=r.data['id'])
        self.assertEqual(m.status, 'open')
        self.assertFalse(m.winners.exists())

    def test_private_match_hidden_and_chat_protected(self):
        m = self.create_match(is_public=False)
        MatchMessage.objects.create(match=m, sender=self.org, content='code porte 1234')
        self.assertEqual(self.api.get(f'/api/matches/{m.id}/').status_code, 404)
        r = self.api.get(f'/api/matches/{m.id}/?share_code={m.share_code}')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['messages'], [])
        self.assertIsNone(r.data['share_code'])
        self.assertEqual(self.api.get('/api/matches/?dashboard=true').status_code, 200)
        self.assertNotIn(m.id, [x['id'] for x in self.api.get('/api/matches/?dashboard=true').data.get('results', [])])

    def test_join_private_needs_code_and_respects_capacity(self):
        m = self.create_match(is_public=False, max_players=2)
        p1, p2 = make_user('p1'), make_user('p2')
        self.api.force_authenticate(p1)
        self.assertEqual(self.api.post(f'/api/matches/{m.id}/join/').status_code, 403)
        self.assertEqual(self.api.post(f'/api/matches/{m.id}/join/', {'share_code': m.share_code}, format='json').status_code, 201)
        self.api.force_authenticate(p2)
        self.assertEqual(self.api.post(f'/api/matches/{m.id}/join/', {'share_code': m.share_code}, format='json').status_code, 400)

    def test_finish_rejects_duplicates_and_overlap(self):
        p = make_user('p')
        m = self.create_match(date_time=timezone.now() - timedelta(hours=3))
        MatchParticipant.objects.create(match=m, user=p, status='confirmed')
        self.api.force_authenticate(self.org)
        r = self.api.post(f'/api/matches/{m.id}/finish/', {'winner_ids': [self.org.id], 'loser_ids': [self.org.id]}, format='json')
        self.assertEqual(r.status_code, 400)
        r = self.api.post(f'/api/matches/{m.id}/finish/', {'winner_ids': [self.org.id, self.org.id], 'loser_ids': [p.id]}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(PlayerStats.objects.get(user=self.org).matches_won, 1)

    def test_cannot_rate_self_or_outsider(self):
        p, outsider = make_user('p'), make_user('out')
        m = self.create_match(date_time=timezone.now() - timedelta(hours=3))
        MatchParticipant.objects.create(match=m, user=p, status='confirmed')
        m.update_status()
        self.api.force_authenticate(self.org)
        self.assertEqual(self.api.post('/api/ratings/players/', {'match': m.id, 'rated_user': self.org.id, 'rating': 10}, format='json').status_code, 400)
        self.assertEqual(self.api.post('/api/ratings/players/', {'match': m.id, 'rated_user': outsider.id, 'rating': 1}, format='json').status_code, 400)
        self.assertEqual(self.api.post('/api/ratings/players/', {'match': m.id, 'rated_user': p.id, 'rating': 7}, format='json').status_code, 201)

    def test_bad_query_params_do_not_crash(self):
        for url in ['/api/matches/?date_from=abc&club_id=abc', '/api/clubs/?min_rating=abc&lat=abc&lng=1']:
            self.assertEqual(self.api.get(url).status_code, 200, url)


class OpenDataTests(TestCase):
    def test_grouping_and_import(self):
        from .management.commands.import_osm_clubs import save_osm_club
        els = [
            {'type': 'way', 'id': 10, 'center': {'lat': 43.6, 'lon': 1.44}, 'tags': {'leisure': 'sports_centre', 'sport': 'padel', 'name': 'Toulouse Padel'}},
            {'type': 'way', 'id': 11, 'center': {'lat': 43.6001, 'lon': 1.4401}, 'tags': {'leisure': 'pitch', 'sport': 'padel', 'indoor': 'yes'}},
            {'type': 'way', 'id': 12, 'center': {'lat': -34.6, 'lon': -58.4}, 'tags': {'leisure': 'pitch', 'sport': 'padel', 'addr:city': 'Buenos Aires'}},
        ]
        clubs = opendata.group_clubs(els)
        self.assertEqual(len(clubs), 2)
        club, created = save_osm_club(clubs[0])
        self.assertTrue(created)
        self.assertEqual(club.source, 'osm')
        _, created = save_osm_club(clubs[0])
        self.assertFalse(created)
        compact = opendata.to_compact(clubs)
        self.assertEqual(opendata.from_compact(compact)[1]['city'], 'Buenos Aires')


class CommunityTests(APITestCase):
    def setUp(self):
        from rest_framework.authtoken.models import Token
        self.a = User.objects.create_user(username='auteur', password='Padel-test-2026!')
        self.b = User.objects.create_user(username='lecteur', password='Padel-test-2026!')
        self.ta = Token.objects.create(user=self.a).key
        self.tb = Token.objects.create(user=self.b).key

    def test_post_like_reply(self):
        self.client.credentials(HTTP_AUTHORIZATION='Token ' + self.ta)
        r = self.client.post('/api/community/posts/', {'title': 'Cherche 4e', 'content': 'Jeudi 19 h à Lomme, niveau 4.',
                                                       'category': 'looking_for_players', 'author': self.b.id,
                                                       'likes': [self.b.id]}, format='json')
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(r.data['author'], self.a.id)       # l'auteur vient de la session
        self.assertEqual(r.data['like_count'], 0)            # les « j'aime » ne s'écrivent pas à la création
        pid = r.data['id']
        self.client.credentials(HTTP_AUTHORIZATION='Token ' + self.tb)
        self.assertTrue(self.client.post(f'/api/community/posts/{pid}/like/').data['liked'])
        r = self.client.post(f'/api/community/posts/{pid}/replies/', {'content': 'Partant !'}, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertEqual(self.client.post(f'/api/community/posts/{pid}/replies/', {'content': 'x', 'parent_reply_id': 99999},
                                          format='json').status_code, 400)
        r = self.client.get('/api/community/posts/')
        self.assertEqual(r.data['results'][0]['reply_count'], 1)
