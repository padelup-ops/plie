"""Test de bout en bout d'un serveur PadelUp (serveur de test Railway par défaut).

    python3 padelup/tools/smoke_test.py https://padelup-test-test.up.railway.app

Crée un compte jetable, choisit un niveau, ajoute un club OpenStreetMap près de Lille, puis vérifie que le bot
lit pour de vrai les clubs et les créneaux Playtomic (sans réserver : aucune règle, aucun compte Playtomic).
"""
import json
import secrets
import sys
import urllib.error
import urllib.request
from datetime import date, timedelta

BASE = (sys.argv[1] if len(sys.argv) > 1 else 'https://padelup-test-test.up.railway.app').rstrip('/')
TOKEN = None
FAILS = 0


def call(method, path, body=None):
    headers = {'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'padelup-smoke-test/1.0'}
    if TOKEN:
        headers['Authorization'] = 'Token ' + TOKEN
    req = urllib.request.Request(BASE + path, method=method, headers=headers,
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw[:300].decode(errors='replace')


def check(name, ok, detail=''):
    global FAILS
    FAILS += 0 if ok else 1
    print(('OK    ' if ok else 'ÉCHEC ') + name + (f'  — {detail}' if detail else ''), flush=True)


code, data = call('GET', '/')
check('serveur en ligne', code == 200, str(data)[:80])

user = 'test_' + secrets.token_hex(4)
code, data = call('POST', '/api/auth/register/', {'username': user, 'email': f'{user}@example.com', 'password': 'Padel-test-2026!',
                                                   'password2': 'Padel-test-2026!', 'full_name': 'Joueur Test'})
TOKEN = (data or {}).get('token') if isinstance(data, dict) else None
check('inscription sans code (serveur de test)', code == 201 and bool(TOKEN), f'{code}')

code, data = call('PUT', '/api/profile/', {'skill_level': 4, 'evaluation_type': 'new', 'right_handed': True, 'location': 'Lille'})
check('choix du niveau', code == 200, f'{code}')
code, data = call('GET', '/api/profile/')
check('profil complet', code == 200 and data['profile']['is_completed'] and data['profile']['skill_level'] == 4,
      f"niveau {data.get('profile', {}).get('skill_level') if isinstance(data, dict) else '?'} · {data.get('profile', {}).get('tier_name') if isinstance(data, dict) else ''}")

code, data = call('POST', '/api/clubs/from-osm/', {'osm_id': 'way/1455979295', 'name': 'Padel Horizon Lomme',
                                                   'latitude': 50.6377, 'longitude': 2.9937, 'city': 'Lomme'})
check('club OpenStreetMap ajouté (Padel Horizon Lomme)', code in (200, 201), f"{code} {data.get('name') if isinstance(data, dict) else data}")
club_id = data.get('id') if isinstance(data, dict) else None
if club_id:
    from datetime import datetime, timezone as tz
    when = (datetime.now(tz.utc) + timedelta(days=2)).replace(hour=18, minute=0, second=0, microsecond=0).isoformat()
    code, m = call('POST', '/api/matches/', {'title': 'Match de test', 'club': club_id, 'date_time': when, 'duration': 90,
                                             'max_players': 4, 'min_skill_level': 3, 'max_skill_level': 6, 'is_public': True})
    check('match créé dans ce club', code == 201, f"{code} {m.get('title') if isinstance(m, dict) else m}")
    if code == 201:
        code, chat = call('POST', f"/api/matches/{m['id']}/chat/", {'content': 'Qui apporte les balles ?'})
        check('message dans la discussion du match', code == 201, f'{code}')

code, data = call('GET', '/api/bot/providers/')
check('plateformes du bot', code == 200, ', '.join(p['name'] for p in data) if code == 200 else str(data)[:120])

for city, lat, lon in [('Lille', 50.6292, 3.0573), ('Genève / Saint-Genis-Pouilly', 46.2436, 6.0256), ('Tunis', 36.8065, 10.1815)]:
    code, clubs = call('GET', f'/api/bot/clubs/?provider=playtomic&lat={lat}&lon={lon}&radius=25')
    ok = code == 200 and isinstance(clubs, list)
    check(f'clubs Playtomic autour de {city}', ok, f"{len(clubs)} club(s) : " + ', '.join(c['name'] for c in clubs[:4]) if ok else f'{code} {str(clubs)[:200]}')
    if ok and clubs:
        tenant = clubs[0]
        day = (date.today() + timedelta(days=2)).isoformat()
        code, slots = call('GET', f"/api/bot/slots/?provider=playtomic&club_id={tenant['id']}&date={day}")
        ok2 = code == 200 and isinstance(slots, dict)
        sample = []
        if ok2:
            for d in slots.get('days', []):
                sample += [f"{s['local_time']} {s['duration']}min {s['court_name']} {s['price_label']}" for s in d['slots'][:4]]
        n = sum(len(d['slots']) for d in slots.get('days', [])) if ok2 else 0
        check(f"créneaux Playtomic de « {tenant['name']} » le {day}", ok2, f'{n} créneau(x) : ' + ' | '.join(sample) if ok2 else f'{code} {str(slots)[:200]}')

code, data = call('GET', '/api/matches/?page=1')
check('liste des matchs', code == 200, f'{code}')
code, data = call('GET', '/api/leaderboard/?limit=5')
check('classement', code == 200, f'{code}')
code, data = call('GET', '/api/friends/suggestions/')
check('suggestions d\'amis (sans e-mail exposé)', code == 200 and all('email' not in s for s in data.get('suggestions', [])), f'{code}')

print(f'\n{FAILS} échec(s)')
sys.exit(1 if FAILS else 0)
