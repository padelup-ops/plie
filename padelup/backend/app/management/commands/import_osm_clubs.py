"""Importe des clubs de padel OpenStreetMap dans la base PadelUp (pour le tableau de bord et les matchs).

    python manage.py import_osm_clubs --file clubs-world.json         # fichier construit par padelup/tools/world_clubs.py
    python manage.py import_osm_clubs --bbox 48.7,2.2,49.0,2.5         # une zone, directement depuis Overpass
    python manage.py import_osm_clubs --file clubs-world.json --country FR --named-only

Les clubs saisis à la main ne sont jamais modifiés ; seuls les clubs déjà importés d'OSM sont mis à jour.
"""
import json
from decimal import Decimal

from django.core.management.base import BaseCommand, CommandError

from app import opendata
from app.models import Club


def save_osm_club(c, update=True):
    defaults = {
        'name': c.get('name') or 'Terrains de padel', 'latitude': Decimal(str(c['lat'])), 'longitude': Decimal(str(c['lon'])),
        'city': c.get('city', ''), 'postal_code': c.get('postcode', ''), 'address': c.get('street', ''),
        'country': c.get('country', ''), 'website': c.get('website') or None, 'phone': c.get('phone', ''),
        'email': c.get('email', '') if '@' in (c.get('email') or '') else '', 'source': 'osm',
        'amenities': ['Terrains couverts'] if c.get('indoor') else [],
    }
    club = Club.objects.filter(osm_id=c['id']).first()
    if club is None:
        return Club.objects.create(osm_id=c['id'], **defaults), True
    if update and club.source == 'osm':
        for k, v in defaults.items():
            setattr(club, k, v)
        club.save()
    return club, False


class Command(BaseCommand):
    help = 'Importe les clubs de padel OpenStreetMap.'

    def add_arguments(self, parser):
        parser.add_argument('--file')
        parser.add_argument('--bbox', help='sud,ouest,nord,est')
        parser.add_argument('--country', help='code pays ISO (si renseigné dans OSM)')
        parser.add_argument('--named-only', action='store_true')

    def handle(self, *args, **opts):
        if opts.get('file'):
            with open(opts['file'], encoding='utf-8') as f:
                clubs = opendata.from_compact(json.load(f))
        elif opts.get('bbox'):
            try:
                s, w, n, e = [float(x) for x in opts['bbox'].split(',')]
            except ValueError:
                raise CommandError('--bbox attend sud,ouest,nord,est')
            clubs = opendata.group_clubs(opendata.run_query(opendata.bbox_query(s, w, n, e)))
        else:
            raise CommandError('Indique --file ou --bbox.')
        if opts.get('country'):
            clubs = [c for c in clubs if (c.get('country') or '').upper() == opts['country'].upper()]
        if opts.get('named_only'):
            clubs = [c for c in clubs if c.get('name')]
        created = 0
        for c in clubs:
            _, new = save_osm_club(c)
            created += new
        self.stdout.write(self.style.SUCCESS(f'{len(clubs)} clubs traités, {created} nouveaux.'))
