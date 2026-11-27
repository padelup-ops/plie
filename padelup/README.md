# PadelUp Neo

L'app padel reconstruite à partir de [padelup-backend-forked](https://github.com/Ghadje/padelup-backend-forked) : tous les clubs de padel de la zone PadelUp sans passer par le tableau de bord, la météo du court, un bot qui lit les créneaux Playtomic en direct et prévient à la seconde, les matchs entre joueurs de même niveau, et une ambiance qui suit les saisons.

**Design, direction « Court »** (`ios/App/Theme.swift`). La typographie porte l'écran : titres en SF Pro Expanded, heures, prix et scores en chiffres condensés à chasse fixe, comme un tableau de score. Le contenu est posé sur la page (papier `#F4F2EC`, encre `#0D1B24`), séparé par des filets plutôt qu'enfermé dans des cartes. Deux couleurs, chacune avec un rôle : le bleu PadelUp `#094A73` pour agir, le jaune balle `#D6F04A` pour ce qui est libre, en direct ou réservé. Quatre éléments signent l'app : le billet de réservation (entaillé, perforé), le terrain vu de haut dans la fiche match, le niveau en barres montantes et la météo de jeu en graphique. Le mode sombre est un court de nuit, bleu-noir. Pas d'émoji, pas de sous-titre explicatif sous chaque titre.

C'est une **app séparée** de « PADELUP (FR) » (`com.padelup.padelup-new`), qui n'est jamais modifiée. Sa fiche App Store Connect est « PADELUP Neo », identifiant `com.padelup.neo`.

| Dossier | Contenu |
|---|---|
| `ios/` | L'app iPhone (SwiftUI, iOS 26, projet XcodeGen) |
| `backend/` | Le serveur Django repris, corrigé et complété (bot, open data) |
| `tools/zone_clubs.py` | Construit le fichier des clubs de la zone depuis OpenStreetMap |

## L'app iPhone

- **Zone couverte** : France, Belgique, Suisse, les pays frontaliers de la France (Luxembourg, Allemagne, Italie, Monaco, Andorre, Espagne), Maroc, Algérie et Tunisie. Le fichier OpenStreetMap de ces douze pays est embarqué dans l'app : il marche hors ligne et s'affiche tout de suite. Il est construit pays par pays, d'après la frontière officielle de chaque pays dans OSM. La zone affichée sur la carte est ensuite actualisée en direct (API Overpass, avec trois serveurs de secours), et les clubs Playtomic de la zone sont rattachés au club OSM correspondant. Hors de la zone, l'app n'ajoute pas de clubs. La recherche de ville passe par MapKit, sans clé d'API.
- **Fiche club**. On y trouve :
  - les créneaux en direct, relus chaque minute et groupés par heure, puis par matin, après-midi et soir ;
  - le billet de réservation ;
  - la météo de jeu heure par heure (Open-Meteo), avec un indice padel sur 100 qui tient compte de la pluie, du vent et de la température ;
  - l'itinéraire, le téléphone et le site du club.

  Le club est retrouvé sur le site Playtomic par son nom et sa ville, et ce lien est gardé. Le bouton « Match » ajoute le club au serveur PadelUp s'il vient d'OSM.
- **Bot**. Le joueur choisit les jours, la plage horaire, les durées, couvert ou extérieur, un prix maximum et le nombre de réservations. Option **ouverture des réservations**, reprise du dossier Padel Sniper : quand un club ouvre ses créneaux J-x à hh:mm, le bot prévient une minute avant (notification) et affiche un compte à rebours. À l'heure pile, il lit les créneaux une fois par seconde pendant 10 s, puis toutes les 3 s jusqu'à 45 s. Dès que le créneau apparaît, il ouvre la page de réservation, déjà connectée. Le journal garde tout, sur une frise.
- **Compte PadelUp** : inscription par e-mail (code de confirmation) ou Se connecter avec Apple, puis **choix du niveau** (échelle FFT en 8 niveaux avec repères, ou ancienne échelle en 10), main forte et ville.
- **Matchs** : matchs ouverts et les miens, rejoindre ou quitter, créer un match dans n'importe quel club de la carte. **Fiche match** : joueurs et places libres, discussion, saisie du résultat par l'organisateur, **notation des joueurs** (1 à 10, anonyme, elle affine le niveau public) et du terrain (1 à 5). Un rappel apparaît quand un match attend un résultat ou des notes.
- **Amis** : mes amis, demandes reçues et envoyées, recherche de joueurs et suggestions.
- **Classement** et **notifications** (invitations, matchs, amis, réservations du bot).
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

### Ce que le bot fait, plateforme par plateforme

| Plateforme | Connexion | Créneaux | Réservation |
|---|---|---|---|
| **Playtomic** | Sur le site playtomic.com, ouvert dans l'app | En direct, lus sur le site depuis l'iPhone du joueur | La page du club s'ouvre à la bonne date, déjà connectée : le joueur valide et paie en un geste |
| **Anybuddy** | Sur le site anybuddyapp.com (`/fr/login`), ouvert dans l'app | Non lus par PadelUp : Anybuddy les protège par une vérification anti-robot | La page du club (`/fr/club/<slug>`) et la réservation automatique d'Anybuddy s'ouvrent, déjà connectées |
| **Clubs PadelUp** | Compte PadelUp | Oui | Oui, immédiate, y compris par le serveur 24 h/24 |

Les règles du dossier Padel Sniper sont appliquées à la lettre :
- **Aucun mot de passe de plateforme** n'est demandé, transmis ni enregistré. Le joueur se connecte sur le site de la plateforme, dans une vue web qui partage le stockage de l'app (`WKWebsiteDataStore.default`). La session reste sur l'iPhone. L'app repère la connexion dans les cookies et le stockage local.
- **Aucune protection n'est contournée.** Si Playtomic répond 403 ou 429, le bot s'arrête et se met en pause une heure. Les créneaux d'Anybuddy, protégés, ne sont pas lus.
- **Transparence** : PadelUp n'est affilié ni à Playtomic ni à Anybuddy, ce qui est écrit dans l'app.

> Pourquoi le serveur ne réserve plus sur Playtomic : depuis novembre 2026, l'API mobile de Playtomic exige la vérification de leur propre application (`APP_ATTESTATION_REQUIRED`), et leur pare-feu refuse les adresses de serveurs. Une réservation 100 % automatique demanderait de contourner ces protections, ce que le dossier interdit. La voie propre est un accès partenaire Playtomic.
>
> Pourquoi la connexion Anybuddy ne marchait pas : l'app ouvrait leur site dans un Safari intégré (`SFSafariViewController`), qui garde ses cookies pour lui. L'app ne voyait donc jamais la session. Le site s'ouvre maintenant dans l'app, avec le stockage partagé.

### Où tourne le bot

- **Sur l'iPhone**, pour Playtomic : toutes les 30 à 60 secondes quand l'app est ouverte, puis en arrière-plan quand iOS le permet. Pour une ouverture à heure fixe, la notification une minute avant fait ouvrir l'app, et le bot lit les créneaux à la seconde.
- **Sur le serveur, 24 h/24**, pour les clubs partenaires PadelUp, quand le joueur est connecté à son compte PadelUp.

### Compiler, tester, publier

Le workflow `.github/workflows/padelup-ios.yml` se lance à chaque envoi qui touche `padelup/ios/`. Il :

1. embarque le fichier des clubs de la zone ;
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

- **Clubs de la zone** (`app/opendata.py`, liste des pays dans `ZONE_COUNTRIES`) :
  - `POST /api/clubs/from-osm/ {"osm_id": "way/123"}` ajoute un club OpenStreetMap. Le serveur relit l'élément chez OSM : aucune donnée ne vient du client.
  - `python manage.py import_osm_clubs --file clubs-zone.json [--country FR] [--named-only]` importe en masse.
  - Les clubs ont maintenant les champs `country`, `source`, `osm_id`, `playtomic_tenant_id` et `anybuddy_slug`.

- Le workflow `padelup-clubs.yml` reconstruit le fichier des clubs de la zone chaque lundi. Il est publié dans la branche `ci-padelup-clubs`. Pour ajouter un pays, il suffit d'ajouter son code ISO dans `ZONE_COUNTRIES` (serveur) et un rectangle dans `CoverageZone` (app).

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
