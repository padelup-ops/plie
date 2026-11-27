"""Test de bout en bout d'un serveur PadelUp (serveur de test Railway par défaut).

    python3 padelup/tools/smoke_test.py https://padelup-test-test.up.railway.app

Crée un compte jetable, choisit un niveau, ajoute un club OpenStreetMap près de Lille, crée un match, vérifie le radar
des joueurs (présence arrondie, disponibilité, proposition acceptée) et la communauté.
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

# Playtomic n'est plus lu par le serveur (vérification d'appareil et pare-feu Playtomic) : l'app le lit depuis l'iPhone.

# Radar des joueurs : un second joueur visible près de Lille, retrouvé à distance arrondie, sans coordonnées.
main_token = TOKEN
other = 'test_' + secrets.token_hex(4)
code, data = call('POST', '/api/auth/register/', {'username': other, 'email': f'{other}@example.com', 'password': 'Padel-test-2026!',
                                                   'password2': 'Padel-test-2026!', 'full_name': 'Voisin Test'})
other_token = (data or {}).get('token') if isinstance(data, dict) else None
if other_token:
    TOKEN = other_token
    call('PUT', '/api/profile/', {'skill_level': 4})
    code, data = call('PATCH', '/api/radar/', {'lat': 50.6377, 'lng': 3.0633})
    check('présence sur le radar (position arrondie)', code == 200, f'{code}')
    code, data = call('POST', '/api/availabilities/', {'day_of_week': 1, 'time_slot': 'evening', 'radius_km': 10})
    check('disponibilité ajoutée', code == 201, f'{code}')
    other_id = call('GET', '/api/profile/')[1].get('id')
    TOKEN = main_token
    code, data = call('GET', '/api/radar/?lat=50.6292&lng=3.0573&radius_km=15&min_skill=3&max_skill=5')
    rows = data.get('results', []) if isinstance(data, dict) else []
    found = [r for r in rows if r.get('username') == other]
    check('radar : joueur voisin trouvé, sans coordonnées', code == 200 and bool(found) and 'latitude' not in found[0],
          f"{code} {len(rows)} joueur(s), distance {found[0]['distance_km'] if found else '?'} km")
    day = (date.today() + timedelta(days=3)).isoformat()
    code, data = call('POST', '/api/proposals/', {'receiver_id': other_id, 'proposed_date': day, 'proposed_time_slot': 'evening',
                                                  'message': 'Partant ?'})
    check('proposition de match envoyée', code == 201, f'{code}')
    pid = data.get('id') if isinstance(data, dict) else None
    TOKEN = other_token
    code, data = call('PUT', f'/api/proposals/{pid}/', {'action': 'accept'})
    check('proposition acceptée', code == 200 and data.get('status') == 'accepted', f'{code}')
    call('DELETE', '/api/radar/')
    TOKEN = main_token

code, data = call('POST', '/api/community/posts/', {'title': 'Cherche un 4e', 'content': 'Jeudi 19 h à Lomme, niveau 4.',
                                                    'category': 'looking_for_players', 'city': 'Lille'})
check('communauté : publication', code == 201, f'{code}')
if code == 201:
    code, data2 = call('POST', f"/api/community/posts/{data['id']}/like/")
    check('communauté : j\'aime', code == 200 and data2.get('liked') is True, f'{code}')

code, data = call('GET', '/api/matches/?page=1')
check('liste des matchs', code == 200, f'{code}')
code, data = call('GET', '/api/leaderboard/?limit=5')
check('classement', code == 200, f'{code}')
code, data = call('GET', '/api/friends/suggestions/')
check('suggestions d\'amis (sans e-mail exposé)', code == 200 and all('email' not in s for s in data.get('suggestions', [])), f'{code}')

print(f'\n{FAILS} échec(s)')
sys.exit(1 if FAILS else 0)
