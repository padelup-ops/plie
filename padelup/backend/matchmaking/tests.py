from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from app.models import BlockedUser, Notification

from .models import MatchProposal, PlayerPresence


class RadarTests(APITestCase):
    def make(self, name, level, lat=None, lng=None):
        u = User.objects.create_user(username=name, password='Padel-test-2026!', first_name=name.capitalize())
        u.profile.skill_level = level
        u.profile.save()
        if lat is not None:
            PlayerPresence.objects.create(user=u, latitude=lat, longitude=lng)
        return u

    def login(self, user):
        self.client.credentials(HTTP_AUTHORIZATION='Token ' + Token.objects.get_or_create(user=user)[0].key)

    def setUp(self):
        self.me = self.make('moi', 4)
        self.near = self.make('voisin', 4, 50.63, 3.06)       # Lille, ~1 km
        self.far = self.make('loin', 4, 48.85, 2.35)           # Paris
        self.strong = self.make('fort', 8, 50.64, 3.07)
        self.login(self.me)

    def test_position_is_rounded_and_never_returned(self):
        r = self.client.patch('/api/radar/', {'lat': 50.637712, 'lng': 3.063341}, format='json')
        self.assertEqual(r.status_code, 200)
        p = PlayerPresence.objects.get(user=self.me)
        self.assertEqual(str(p.latitude), '50.64')
        self.assertEqual(str(p.longitude), '3.06')
        r = self.client.get('/api/radar/?lat=50.6292&lng=3.0573&radius_km=15&min_skill=3&max_skill=5')
        self.assertEqual(r.status_code, 200)
        names = [x['username'] for x in r.data['results']]
        self.assertEqual(names, ['voisin'])
        row = r.data['results'][0]
        self.assertNotIn('latitude', row)
        self.assertGreaterEqual(row['distance_km'], 1.0)

    def test_hidden_and_blocked_players_do_not_appear(self):
        PlayerPresence.objects.filter(user=self.near).update(visible=False)
        r = self.client.get('/api/radar/?lat=50.6292&lng=3.0573&radius_km=15')
        self.assertNotIn('voisin', [x['username'] for x in r.data['results']])
        PlayerPresence.objects.filter(user=self.near).update(visible=True)
        BlockedUser.objects.create(blocker=self.near, blocked=self.me)
        r = self.client.get('/api/radar/?lat=50.6292&lng=3.0573&radius_km=15')
        self.assertNotIn('voisin', [x['username'] for x in r.data['results']])

    def test_availability_filters(self):
        self.login(self.near)
        r = self.client.post('/api/availabilities/', {'day_of_week': 2, 'time_slot': 'evening', 'radius_km': 10}, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertEqual(self.client.post('/api/availabilities/', {'time_slot': 'evening'}, format='json').status_code, 400)
        self.login(self.me)
        r = self.client.get('/api/radar/?lat=50.6292&lng=3.0573&radius_km=15&time_slot=evening&day_of_week=2')
        self.assertEqual([x['username'] for x in r.data['results']], ['voisin'])
        r = self.client.get('/api/radar/?lat=50.6292&lng=3.0573&radius_km=15&time_slot=morning')
        self.assertEqual(r.data['results'], [])

    def test_proposal_flow(self):
        day = (timezone.localdate() + timedelta(days=3)).isoformat()
        r = self.client.post('/api/proposals/', {'receiver_id': self.near.id, 'proposed_date': day,
                                                 'proposed_time_slot': 'evening', 'message': 'Partant ?'}, format='json')
        self.assertEqual(r.status_code, 201)
        pid = r.data['id']
        self.assertTrue(Notification.objects.filter(user=self.near, type='match_proposal').exists())
        dup = self.client.post('/api/proposals/', {'receiver_id': self.near.id, 'proposed_date': day, 'proposed_time_slot': 'evening'}, format='json')
        self.assertEqual(dup.status_code, 400)
        # Seul le destinataire répond
        self.assertEqual(self.client.put(f'/api/proposals/{pid}/', {'action': 'accept'}, format='json').status_code, 404)
        self.login(self.near)
        got = self.client.get('/api/proposals/')
        self.assertEqual(len(got.data['received']), 1)
        r = self.client.put(f'/api/proposals/{pid}/', {'action': 'accept'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['status'], 'accepted')
        self.assertEqual(MatchProposal.objects.get(id=pid).status, 'accepted')
        self.assertTrue(Notification.objects.filter(user=self.me, type='match_proposal_accepted').exists())
        self.assertEqual(self.client.put(f'/api/proposals/{pid}/', {'action': 'decline'}, format='json').status_code, 400)

    def test_cannot_propose_to_self_or_in_the_past(self):
        day = (timezone.localdate() - timedelta(days=1)).isoformat()
        self.assertEqual(self.client.post('/api/proposals/', {'receiver_id': self.me.id, 'proposed_date': day,
                                                              'proposed_time_slot': 'evening'}, format='json').status_code, 400)
        self.assertEqual(self.client.post('/api/proposals/', {'receiver_id': self.near.id, 'proposed_date': day,
                                                              'proposed_time_slot': 'evening'}, format='json').status_code, 400)
