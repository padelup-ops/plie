"""Fait tourner le bot de réservation.

    python manage.py run_booking_bot              # un passage sur toutes les règles actives
    python manage.py run_booking_bot --loop       # en continu (service « worker »), toutes les 60 s
    python manage.py run_booking_bot --dry-run    # cherche sans réserver
"""
import random
import time

from django.core.management.base import BaseCommand
from django.db import close_old_connections

from booking_bot.engine import run_all


class Command(BaseCommand):
    help = 'Surveille les créneaux et réserve automatiquement pour les joueurs.'

    def add_arguments(self, parser):
        parser.add_argument('--loop', action='store_true')
        parser.add_argument('--interval', type=int, default=60)
        parser.add_argument('--dry-run', action='store_true')
        parser.add_argument('--rule', type=int, action='append')

    def handle(self, *args, **opts):
        while True:
            close_old_connections()
            started = time.monotonic()
            results = run_all(dry_run=opts['dry_run'], rule_ids=opts.get('rule'))
            booked = [r for r in results if r['status'] == 'booked']
            self.stdout.write(f'{len(results)} règle(s) traitée(s), {len(booked)} réservation(s).')
            for r in results:
                if r['status'] not in ('waiting', 'inactive', 'locked'):
                    self.stdout.write(f"  règle {r['rule']} : {r['status']} — {r['message']}")
            if not opts['loop']:
                return
            # Un peu d'aléa pour ne pas interroger les plateformes à la seconde près.
            pause = max(5, opts['interval'] - (time.monotonic() - started)) + random.uniform(0, 5)
            time.sleep(pause)
