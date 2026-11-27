#!/bin/sh
# Démarrage du serveur de test PadelUp (Railway, environnement « test ») : base à jour, fichiers statiques,
# bot de réservation en continu (relancé s'il s'arrête), puis le serveur web.
set -e
python manage.py migrate --noinput
python manage.py collectstatic --noinput
(while true; do python manage.py run_booking_bot --loop --interval 60 || true; sleep 15; done) &
exec gunicorn backend.wsgi:application --bind 0.0.0.0:${PORT:-8080} --workers 3 --timeout 120
