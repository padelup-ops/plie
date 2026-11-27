"""Construit le fichier mondial des clubs de padel (OpenStreetMap) embarqué dans l'app PadelUp Neo.

    python3 padelup/tools/world_clubs.py sortie.json

Le monde est découpé en zones (l'Espagne, l'Italie et la France sont très denses), chaque zone est demandée
à Overpass avec plusieurs serveurs de secours, puis les terrains sont regroupés en clubs (voir app/opendata.py).
Données © contributeurs OpenStreetMap, licence ODbL : l'attribution est affichée dans l'app.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'backend', 'app'))
import opendata  # noqa: E402

LAT_BANDS = [(-60, 0), (0, 30), (30, 38), (38, 44), (44, 50), (50, 75)]
LON_BANDS = [(-180, -60), (-60, -20), (-20, -5), (-5, 5), (5, 15), (15, 30), (30, 60), (60, 180)]


def main(out):
    seen, elements, failures = set(), [], []
    for s, n in LAT_BANDS:
        for w, e in LON_BANDS:
            started = time.time()
            try:
                batch = opendata.run_query(opendata.bbox_query(s, w, n, e, timeout=300), timeout=330, retries=3)
            except RuntimeError as exc:
                failures.append(f'{s},{w},{n},{e}: {exc}')
                print('ÉCHEC', s, w, n, e, exc, flush=True)
                continue
            fresh = 0
            for el in batch:
                key = (el.get('type'), el.get('id'))
                if key not in seen:
                    seen.add(key)
                    elements.append(el)
                    fresh += 1
            print(f'zone {s:>4},{w:>5} → {n:>4},{e:>5} : {fresh:>6} éléments ({time.time() - started:.0f} s)', flush=True)
            time.sleep(2)
    clubs = opendata.group_clubs(elements)
    clubs.sort(key=lambda c: (c['lat'], c['lon']))
    data = opendata.to_compact(clubs)
    data['generated'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    data['source'] = '© OpenStreetMap contributors (ODbL)'
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    courts = sum(c['courts'] for c in clubs)
    named = sum(1 for c in clubs if c['name'])
    print(f'{len(elements)} éléments OSM → {len(clubs)} clubs ({named} avec un nom), {courts} terrains, '
          f'{os.path.getsize(out) / 1e6:.1f} Mo')
    if failures:
        print('Zones en échec :', *failures, sep='\n  ')
    # Échec si trop de zones manquent : on garde alors le fichier précédent.
    return 0 if len(failures) <= 3 and len(clubs) > 1000 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'clubs-world.json'))
