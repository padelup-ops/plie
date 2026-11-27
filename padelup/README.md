# PadelUp Neo

L'app padel reconstruite à partir de [padelup-backend-forked](https://github.com/Ghadje/padelup-backend-forked) : un thème futuriste « court néon », tous les clubs de padel du monde sans passer par le tableau de bord, la météo du court, un bot qui réserve à ta place sur Playtomic et Anybuddy, et une ambiance qui suit les saisons.

C'est une **app séparée** de « PADELUP (FR) » (`com.padelup.padelup-new`), qui n'est jamais modifiée. Sa fiche App Store Connect est « PADELUP Neo », identifiant `com.padelup.neo`.

| Dossier | Contenu |
|---|---|
| `ios/` | L'app iPhone (SwiftUI, iOS 26, projet XcodeGen) |
| `backend/` | Le serveur Django repris, corrigé et complété (bot, open data) |
| `tools/world_clubs.py` | Construit le fichier mondial des clubs depuis OpenStreetMap |

## L'app iPhone

- **Clubs du monde entier**. Le fichier OpenStreetMap est embarqué dans l'app : il couvre tous les pays, marche hors ligne et s'affiche tout de suite. La zone affichée sur la carte est ensuite actualisée en direct (API Overpass, avec trois serveurs de secours), et les clubs Playtomic de la zone sont rattachés au club OSM correspondant. On peut chercher n'importe quelle ville ou n'importe quel pays : la recherche passe par MapKit, sans clé d'API.
- **Fiche club**. On y trouve la météo de jeu heure par heure (Open-Meteo, avec un indice padel sur 100 qui tient compte de la pluie, du vent et de la température), les disponibilités, la réservation en un geste par le bot, l'itinéraire, le site et le téléphone. Le bouton « Créer un match » ajoute le club au serveur PadelUp s'il vient d'OSM.
- **Bot de réservation**. Le joueur connecte son compte Playtomic, puis choisit les jours, la plage horaire, les durées, intérieur ou extérieur, un prix maximum et le nombre de réservations. Le bot surveille et réserve tout seul. Il envoie une notification à chaque réservation et tient un journal.
- **Matchs et classement**, avec le compte PadelUp : e-mail ou Se connecter avec Apple.
- **Saisons** (l'idée de Yacine) :

  | Saison | Période | Effet |
  |---|---|---|
  | Automne | 22 sept. – 30 nov. | Feuilles qui tombent |
  | Halloween | 25 – 31 oct. | Feuilles orange et violettes |
  | Noël | 1er – 30 déc. | Neige |
  | Nouvel An | 31 déc. – 2 janv. | Confettis |
  | Hiver | 3 janv. – 19 mars | Neige légère |
  | Printemps | 20 mars – 20 juin | Pétales |
  | Été | 21 juin – 21 sept. | Éclats de soleil |

  Dans Profil, on peut forcer une saison pour la prévisualiser, ou couper les effets. Les effets s'arrêtent aussi quand « Réduire les animations » est activé sur l'iPhone.

### Ce que le bot fait tout seul, plateforme par plateforme

| Plateforme | Disponibilités | Réservation automatique |
|---|---|---|
| **Playtomic** | Oui, recherche publique | **Oui, de bout en bout**, si le club accepte le paiement sur place, le crédit club ou un bon. Si le club exige la carte, le bot ouvre le paiement et demande au joueur de le valider dans Playtomic (3-D Secure) |
| **Anybuddy** | Oui, API publique du site | Le bot repère le créneau à la seconde et ouvre directement la page du créneau. Anybuddy fait payer par carte (Stripe) : la validation finale se fait en un geste. Le serveur peut tenter la réservation par l'API mobile d'Anybuddy (expérimental) |
| **Clubs PadelUp** | Oui | Oui, immédiate |

> Ni Playtomic ni Anybuddy ne publient d'API pour les applications tierces. Le bot utilise les mêmes appels que leurs propres applications. Ces appels peuvent changer sans prévenir, et leurs conditions d'utilisation encadrent l'automatisation. Avant un lancement public, il faut valider avec eux, par exemple via le programme partenaires de Playtomic.
>
> Le mot de passe Playtomic n'est jamais enregistré. Seuls les jetons de session sont gardés : dans le trousseau de l'iPhone, et chiffrés (Fernet) sur le serveur si le bot 24 h/24 est activé.

### Où tourne le bot

- **Sur l'iPhone**, sans compte PadelUp : toutes les 60 secondes quand l'app est ouverte, puis en arrière-plan quand iOS le permet. iOS limite le travail en arrière-plan, donc ce mode ne capte pas tous les créneaux.
- **Sur le serveur, 24 h/24**, quand le joueur est connecté à son compte PadelUp : la règle et le compte Playtomic sont envoyés au serveur, qui réserve même quand l'iPhone est éteint. C'est le mode à utiliser pour décrocher les créneaux très demandés, qui ouvrent à heure fixe.

### Compiler, tester, publier

Le workflow `.github/workflows/padelup-ios.yml` se lance à chaque envoi qui touche `padelup/ios/`. Il :

1. embarque le fichier mondial des clubs ;
2. compile l'app ;
3. l'envoie sur TestFlight, dans la fiche PADELUP Neo ;
4. prend des captures sur le simulateur.

Les journaux et les captures sont publiés dans la branche `ci-padelup-ios`.

L'app se lance en mode captures avec `-shot home|clubs|club|bot|matches|profile` (données d'exemple, sans réseau). On choisit la saison avec `-seasonMode christmas`.

Sur un Mac : `cd padelup/ios && xcodegen generate && open PadelUpNeo.xcodeproj`.

L'icône se régénère avec `python3 padelup/ios/tools/icon.py`.

## Le serveur (backend/)

Démarrage local :

```bash
cd padelup/backend
python -m venv venv && . venv/bin/activate && pip install -r requirements.txt
cp .env.example .env
python manage.py migrate && python manage.py test app booking_bot
python manage.py runserver
```

### Nouveautés

- **Bot de réservation** (`booking_bot/`), monté sous `/api/bot/` :

  | Route | Rôle |
  |---|---|
  | `providers/` | Plateformes disponibles |
  | `accounts/` | Connexion d'un compte Playtomic ou Anybuddy |
  | `clubs/` | Recherche de clubs sur une plateforme |
  | `slots/` | Disponibilités d'un club |
  | `book/` | Réservation immédiate d'un créneau |
  | `rules/` | Règles de réservation automatique |
  | `rules/<id>/run/` | Lancer une règle tout de suite |
  | `attempts/` | Journal du bot |
  | `tick/` | Passage du bot déclenché par un cron (en-tête `X-Bot-Secret`) |

  Pour le faire tourner en continu : `python manage.py run_booking_bot --loop`, c'est-à-dire le service `worker` du Procfile ou de `render.yaml`. Sans worker (offre gratuite), un cron externe appelle `POST /api/bot/tick/` chaque minute avec l'en-tête `X-Bot-Secret`.

- **Clubs du monde** (`app/opendata.py`) :
  - `POST /api/clubs/from-osm/ {"osm_id": "way/123"}` ajoute un club OpenStreetMap. Le serveur relit l'élément chez OSM : aucune donnée ne vient du client.
  - `python manage.py import_osm_clubs --file clubs-world.json [--country FR] [--named-only]` importe en masse.
  - Les clubs ont maintenant les champs `country`, `source`, `osm_id`, `playtomic_tenant_id` et `anybuddy_slug`.

- Le workflow `padelup-clubs.yml` reconstruit le fichier mondial chaque lundi. Il est publié dans la branche `ci-padelup-clubs`.

### Correctifs de l'audit (38 tests dans `app/tests.py` et `booking_bot/tests.py`)

**Failles critiques corrigées :**

- On pouvait s'inscrire avec `is_staff` et devenir administrateur.
- Les matchs privés et leurs chats étaient lisibles sans compte, et `?dashboard=true` les listait tous.
- La connexion Google acceptait des jetons émis pour d'autres applications. `GOOGLE_CLIENT_IDS` est désormais obligatoire.
- La connexion Apple faisait confiance à l'e-mail envoyé par le client. Le compte Apple est maintenant lié à son identifiant `sub`.
- Les codes à 6 chiffres pouvaient être devinés par force brute. Ils sont maintenant limités à 5 essais, générés avec `secrets` et soumis à une limite de débit.

**Autres correctifs :**

- Changer ou réinitialiser le mot de passe révoque les jetons, et les mots de passe faibles sont refusés.
- Les messages de connexion ne révèlent plus si un compte existe.
- L'e-mail des joueurs n'est plus visible des autres joueurs.
- Réservations :
  - les chevauchements, les créneaux passés et les terrains indisponibles sont refusés, sous verrou ;
  - le prix est calculé au tarif de l'heure du créneau ;
  - le statut et le paiement ne sont plus modifiables par le client ;
  - un créneau annulé peut être réservé de nouveau.
- Matchs :
  - un match est « en cours » pendant la partie et « terminé » seulement à la fin (avant, il était terminé dès le début) ;
  - la capacité est vérifiée sous verrou ;
  - rejoindre un match privé demande le code de partage ou une invitation ;
  - statut, vainqueurs et perdants ne sont plus modifiables par le client ;
  - plus de victoire offerte quand on joue seul ;
  - on ne peut plus se noter soi-même, ni noter un joueur qui n'était pas dans le match ;
  - pour noter un terrain, il faut avoir joué le match terminé sur ce terrain.
- Des paramètres mal formés provoquaient des erreurs 500 ; ils sont maintenant ignorés ou renvoient une erreur 400.
- Les e-mails échappent le HTML.
- Les jetons FCM morts sont nettoyés correctement.
- Les commandes d'administration n'envoient plus de notifications en masse, et `create_test_matches` compile en Python 3.11.
- `DEBUG` est faux par défaut, et les cookies ne passent plus en CORS.

### À faire de votre côté

1. **Régénérer les secrets** publiés dans le dépôt d'origine :
   - le `SECRET_KEY` et le DSN Sentry du `.env` versionné ;
   - la clé Freeimage, qui était écrite dans `views.py`.

   Le `.env` n'a pas été recopié ici, et la clé Freeimage passe maintenant par la variable `FREEIMAGE_API_KEY`.
2. Définir les variables listées dans `backend/.env.example` : `BOT_ENCRYPTION_KEY`, `GOOGLE_CLIENT_IDS`, `BOT_CRON_SECRET`, etc.
3. Indiquer l'adresse de l'API de production. L'app utilise `https://padelup-api.onrender.com/api` par défaut, défini dans `ios/project.yml` (clé `PadelUpAPIBaseURL`). Elle est modifiable dans Profil → Serveur PadelUp.
