"""VICEFOLD : écrit le contenu du guide (Content/content-en.json et content-fr.json) à partir d'une seule source.

Tout le texte est rédigé pour Vicefold, à partir de faits publics (noms de personnages, de lieux, de missions).
Aucun texte, image ou donnée d'un autre guide n'est copié. Chaque donnée a sa version anglaise et française.
Pour publier une mise à jour du guide : augmenter VERSION, relancer ce script, pousser (l'app la télécharge seule).
"""
import json
import os

VERSION = 3
HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "Content")


def T(en, fr):
    return {"en": en, "fr": fr}


# ---------------------------------------------------------------- Personnages (présentés par l'éditeur avant la sortie)
CHARACTERS = [
    ("jason", "Jason Duval", T("Protagonist", "Personnage principal"),
     T("Grew up around grifters and crooks, then tried the army. Now he works for a drug runner down in the Keys and wants something steadier — until he meets Lucia.",
       "Il a grandi entouré d'escrocs, puis a tenté l'armée. Il travaille maintenant pour un trafiquant dans les Keys et voudrait une vie plus stable — jusqu'à sa rencontre avec Lucia."),
     ["Keys", "Lucia"]),
    ("lucia", "Lucia Caminos", T("Protagonist", "Personnage principal"),
     T("Fresh out of the Leonida Penitentiary and determined not to go back. Fiercely loyal to her family and to Jason, and the one who often has the plan.",
       "Tout juste sortie du pénitencier de Leonida, et bien décidée à ne pas y retourner. Fidèle à sa famille et à Jason, c'est souvent elle qui a le plan."),
     ["Vice City", "Jason"]),
    ("cal", "Cal Hampton", T("Jason's friend", "L'ami de Jason"),
     T("Jason's buddy and fellow worker for Brian. Spends his free time reading about conspiracies and listening in on the Coast Guard radio.",
       "Le copain de Jason, qui travaille lui aussi pour Brian. Passe son temps libre dans les théories du complot et à écouter la radio des garde-côtes."),
     ["Keys"]),
    ("boobie", "Boobie Ike", T("Vice City local legend", "Figure de Vice City"),
     T("A Vice City fixture who turned street money into real estate, a strip club and a recording studio. Business first, always.",
       "Une figure de Vice City qui a transformé l'argent de la rue en immobilier, en club de strip-tease et en studio d'enregistrement. Les affaires avant tout."),
     ["Vice City", "Music"]),
    ("drequan", "Dre'Quan Priest", T("Music manager", "Manager musical"),
     T("A hustler who swapped the street for the music business and runs a label with Boobie. Always looking for the next big act.",
       "Un débrouillard passé de la rue à l'industrie musicale, qui gère un label avec Boobie. Toujours à la recherche du prochain succès."),
     ["Vice City", "Music"]),
    ("realdimez", "Real Dimez", T("Rap duo", "Duo de rap"),
     T("Bae-Luxe and Roxy, best friends since school, went viral and now want to turn the buzz into a real career.",
       "Bae-Luxe et Roxy, amies depuis le lycée, ont fait le buzz et veulent maintenant en faire une vraie carrière."),
     ["Vice City", "Music"]),
    ("raul", "Raul Bautista", T("Bank robber", "Braqueur de banques"),
     T("A seasoned, confident robber who is always looking for new talent for bigger and riskier jobs.",
       "Un braqueur aguerri et sûr de lui, toujours à la recherche de nouveaux talents pour des coups plus gros et plus risqués."),
     ["Heists"]),
    ("brian", "Brian Heder", T("Drug runner in the Keys", "Trafiquant des Keys"),
     T("An old-school smuggler who has run boats through the Keys for decades and lets Jason live in one of his properties — at a price.",
       "Un trafiquant de la vieille école qui fait passer des bateaux par les Keys depuis des décennies, et qui loge Jason dans une de ses propriétés — contre service."),
     ["Keys"]),
]

# ---------------------------------------------------------------- Lieux (sur notre carte : x, y de 0 à 1)
PLACES = [
    ("r-vice", "Vice City", "region", 0.82, 0.61, None, T("Leonida's big city: beaches, nightlife, money.", "La grande ville de Leonida : plages, vie nocturne, argent.")),
    ("r-keys", "Leonida Keys", "region", 0.45, 0.93, None, T("A chain of islands linked by long bridges.", "Un chapelet d'îles reliées par de longs ponts.")),
    ("r-grass", "Grassrivers", "region", 0.6, 0.71, None, T("Wetlands, airboats and alligators.", "Marais, hydroglisseurs et alligators.")),
    ("r-gellhorn", "Port Gellhorn", "region", 0.18, 0.27, None, T("A faded beach town on the gulf coast.", "Une station balnéaire défraîchie sur la côte du golfe.")),
    ("r-ambrosia", "Ambrosia", "region", 0.52, 0.47, None, T("Sugar country around the big lake.", "Le pays du sucre, autour du grand lac.")),
    ("r-kalaga", "Mount Kalaga", "region", 0.5, 0.09, None, T("A national park of forests, trails and rivers.", "Un parc national de forêts, de sentiers et de rivières.")),
    ("l-beach", "Vice Beach", "landmark", 0.9, 0.64, "Vice City", T("The barrier island: hotels, neon and the boardwalk.", "L'île barrière : hôtels, néons et promenade.")),
    ("l-lake", "Lake Leonida", "landmark", 0.58, 0.37, "Ambrosia", T("The big lake in the middle of the state.", "Le grand lac au centre de l'État.")),
    ("l-bridge", "Overseas bridges", "landmark", 0.62, 0.86, "Leonida Keys", T("The long road out to the islands.", "La longue route vers les îles.")),
    ("l-pen", "Leonida Penitentiary", "landmark", 0.36, 0.52, None, T("Where Lucia's story starts.", "Là où commence l'histoire de Lucia."), 0),
    ("a-airboat", "Airboat tours", "activity", 0.55, 0.73, "Grassrivers", T("Rent an airboat and explore the wetlands.", "Loue un hydroglisseur et explore les marais.")),
    ("a-fishing", "Pier fishing", "activity", 0.2, 0.31, "Port Gellhorn", T("Cast a line from the old pier.", "Lance ta ligne depuis la vieille jetée.")),
    ("a-hike", "Kalaga trails", "activity", 0.47, 0.13, "Mount Kalaga", T("Hiking trails with views over the park.", "Des sentiers avec vue sur le parc.")),
]

# ---------------------------------------------------------------- Guides
GUIDES = [
    ("start-how", "start", T("How to use Vicefold", "Comment utiliser Vicefold"),
     T("Spoilers, map, tracker: the 2-minute tour.", "Spoilers, carte, suivi : le tour en 2 minutes."),
     T("""# Spoiler-free by default
Tell Vicefold which chapter you're in (Settings › Spoilers). Anything after it stays hidden until you get there. Finishing a mission moves you forward on its own.
# Your map
- Tap the pin button, then tap the map to drop your own pin. Give it a name, a note, an icon and a color.
- Mark places as visited: they count toward your 100%.
- With Pro, import a screenshot of the game's full map and line it up once: your pins then sit on your real map.
# Your 100%
Missions, places, collectibles and challenges each fill a part of the ring. Share it as an image from the Tracker.
> On an iPhone Duo, open it: the list sits on one side of the fold and the details on the other.""",
       """# Sans spoiler par défaut
Indique à Vicefold le chapitre où tu en es (Réglages › Spoilers). Tout ce qui vient après reste masqué jusqu'à ce que tu y arrives. Finir une mission te fait avancer tout seul.
# Ta carte
- Touche le bouton épingle, puis la carte pour poser ta propre épingle. Donne-lui un nom, une note, une icône et une couleur.
- Marque les lieux visités : ils comptent pour ton 100 %.
- Avec Pro, importe une capture de la carte complète du jeu et cale-la une fois : tes épingles sont alors sur ta vraie carte.
# Ton 100 %
Missions, lieux, objets à collectionner et défis remplissent chacun une part de l'anneau. Partage-le en image depuis le Suivi.
> Sur un iPhone Duo, ouvre-le : la liste d'un côté du pli, le détail de l'autre."""), 0, 2),
    ("start-first", "start", T("Your first hours", "Tes premières heures"),
     T("Good habits that pay off for the whole game.", "Les bonnes habitudes pour toute la partie."),
     T("""# Follow the story first
The early missions open up the map, the shops and most activities. Side content is easier once you have a car, a phone and some cash.
# Habits worth having
- Check your phone often: new contacts, jobs and texts unlock activities.
- Keep some money aside: properties and upgrades pay back over time.
- Explore by boat as well as by car: a lot of Leonida is coastline and wetlands.
- Note anything odd on your Vicefold map with a pin: you'll want to come back to it.
> Stuck on a mission? Open it in the Tracker: objectives and tips are there, spoiler-free.""",
       """# Suis d'abord l'histoire
Les premières missions ouvrent la carte, les magasins et la plupart des activités. Le contenu annexe est plus simple une fois qu'on a une voiture, un téléphone et un peu d'argent.
# Les bonnes habitudes
- Regarde souvent ton téléphone : nouveaux contacts, boulots et messages débloquent des activités.
- Garde de l'argent de côté : les propriétés et améliorations rapportent avec le temps.
- Explore en bateau autant qu'en voiture : une bonne partie de Leonida, ce sont des côtes et des marais.
- Note tout ce qui t'intrigue avec une épingle sur ta carte Vicefold : tu voudras y revenir.
> Bloqué sur une mission ? Ouvre-la dans le Suivi : objectifs et conseils y sont, sans spoiler."""), 0, 3),
    ("regions", "landmarks", T("The regions of Leonida", "Les régions de Leonida"),
     T("Six regions, from the city to the national park.", "Six régions, de la ville au parc national."),
     T("""# Vice City
The big city on the east coast, with Vice Beach on its barrier island.
# Leonida Keys
Islands linked by long bridges, with boats everywhere.
# Grassrivers
Wetlands and airboats in the south: watch the water.
# Port Gellhorn
A faded beach town on the gulf coast, in the north-west.
# Ambrosia
Farmland and sugar country around Lake Leonida.
# Mount Kalaga
Forests, trails and rivers in the national park up north.""",
       """# Vice City
La grande ville de la côte est, avec Vice Beach sur son île barrière.
# Leonida Keys
Des îles reliées par de longs ponts, et des bateaux partout.
# Grassrivers
Marais et hydroglisseurs au sud : méfie-toi de l'eau.
# Port Gellhorn
Une station balnéaire défraîchie sur la côte du golfe, au nord-ouest.
# Ambrosia
Terres agricoles et pays du sucre autour du lac Leonida.
# Mount Kalaga
Forêts, sentiers et rivières dans le parc national, au nord."""), 0, 3),
]


# ---------------------------------------------------------------- Histoire : 5 chapitres, 91 missions (noms officiels)
CHAPTERS = [(1, "Just Like Paradise"), (2, "Paradise Lost"), (3, "Tits, Ass, Drug Money"), (4, "Vice City, Baby"), (5, "Top of the World, Ma")]
_M = {
    1: ["Prologue|Lucia", "Gone Fishing", "Gear Up", "Just a Scratch", "Lab Fees", "Unwanted Attention", "Pipework", "Hey Arnold!",
        "Island Dreams|Kenton", "Feng Shui", "Coming Home", "Buck Me", "Clean Up After Donnie", "Down to Earth", "Clear Skies",
        "Day Release", "Swamped", "Don Gone", "Recalibration", "Tourist Trap", "Home Sweet Home|Lucia", "Discharge Time"],
    2: ["What's in the Bag?", "Ambulance Chaser", "Just Moved In", "Girls' Trip", "Moses", "Daily Driver", "Slam Dunk", "Breakfast Run",
        "Coffee Break", "Afternoon Delight", "Checking Out"],
    3: ["Welcome to Vice City", "Dealer's Choice|Jason", "Meet the Heders", "Dubious Provenance", "Mami Knows Best|Lucia",
        "South Leonida Real Estate|Lucia", "Tyrone|Jason", "Here, Kitty Kitty", "Car Service|Lucia", "Top Billing", "Boobie Time",
        "First Impressions", "Caught Slipping", "Crosstown Traffic", "Credit Check", "Steal the Zorrusso for Randy|Randy",
        "Sinfrontera National Bank", "Security Expert", "Ride or Die", "Company Property", "The Missing Link", "Safe Word", "Cooties",
        "Bricked Up", "Hidden Charges", "The Cartel Heist"],
    4: ["Ocean Beach", "Another Life|Lucia", "Company Cars", "Lawyer Up|Abe Gonzalez", "Party Hard", "Heavy Lifting", "Photo/Shoot",
        "Making Gainz|Lucia", "Watch It", "Cash Injections", "Amateur Hour", "Dirty Work", "Too Much Baggage|Jason",
        "Adventures in Babysitting", "Fresh Evidence", "Power Play", "Child's Play", "Headliners", "Close Surveillance|Jason",
        "Delivery Method", "Team Building|Lucia", "Fully Catered", "VCIA Takedown", "Sunset", "Starting from Zero"],
    5: ["Bird in the Hand", "Taking Liberties", "VC Baby", "Doggie Bag", "Operation Savage Glory", "Protective Custody", "The End of the Road"],
}
MISSIONS = []
for ch, names in _M.items():
    for i, n in enumerate(names, 1):
        title, _, giver = n.partition("|")
        m = {"id": f"m{ch}-{i:02d}", "chapter": ch, "title": title}
        if giver:
            m["giver"] = giver
        if ch == 5 and i == len(names):
            m["unlocks"] = T("The end credits, the 100% checklist and cheats.", "Le générique de fin, la liste du 100 % et les codes de triche.")
        MISSIONS.append(m)

# ---------------------------------------------------------------- Le 100 % : ce qui compte, combien, combien il en faut
def C(cid, en, fr, count, needed=None, group=None, reward=None):
    d = {"id": cid, "title": T(en, fr), "count": count}
    en_s, fr_s = [], []
    if needed and needed != count:
        d["needed"] = needed
        en_s.append(f"{needed} of {count} count toward 100%."); fr_s.append(f"{needed} sur {count} comptent pour le 100 %.")
    if reward:
        en_s.append(reward["en"]); fr_s.append(reward["fr"])
    if en_s:
        d["summary"] = T(" ".join(en_s), " ".join(fr_s))
    if group:
        d["group"] = group
    return d

_ex = T("Exploration", "Exploration"); _ac = T("Activities", "Activités"); _jo = T("Jobs", "Coups"); _di = T("Discovery", "Découvertes")
COLLECTIBLES = [
    C("cards", "Collectible card sets", "Séries de cartes à collectionner", 18, 15, _ex, T("480 cards in 18 sets.", "480 cartes en 18 séries.")),
    C("underwater", "Underwater discoveries", "Découvertes sous-marines", 33, None, _ex),
    C("reading", "Magazines, books and comics", "Magazines, livres et BD", 34, 30, _ex, T("27 to read plus 7 book swaps.", "27 à lire plus 7 boîtes à livres.")),
    C("meditation", "Meditation spots", "Lieux de méditation", 18, 15, _ex, T("10 places; each partner counts on their own.", "10 lieux ; chaque partenaire compte séparément.")),
    C("flamingos", "Cocaine flamingos destroyed", "Flamants roses à la cocaïne détruits", 125, 100, _ex, T("50 unlock the Inflatable Flamingo cheat.", "50 débloquent le code Flamant gonflable.")),
    C("wainks", "WAiNK locations scanned", "Lieux scannés avec WAiNK", 100, None, _ex),
    C("kenton", "Kenton sets", "Séries de Kenton", 7, 5, _ex),
    C("styles", "Styles (magazine tattoos and luxury watches)", "Styles (tatouages des magazines et montres de luxe)", 79, 70, _ex, T("45 tattoos and 34 watches.", "45 tatouages et 34 montres.")),
    C("playlists", "Unique playlists", "Playlists uniques", 2, None, _ex),
    C("stunts", "Stunts (jumps, bridges, knife flights, BASE jumps)", "Cascades (sauts, ponts, vols en rase-mottes, sauts en parachute)", 397, 300, _ac, T("130 jumps, 202 under the bridges, 40 knife flights, 25 BASE jumps.", "130 sauts, 202 passages sous les ponts, 40 vols en rase-mottes, 25 sauts en parachute.")),
    C("races", "Unique races won", "Courses uniques gagnées", 40, 30, _ac),
    C("racegold", "Race challenge gold medals", "Médailles d'or aux défis de course", 13, 10, _ac),
    C("range", "Shooting range gold medals", "Médailles d'or au stand de tir", 42, None, _ac, T("18 at Griffin, 24 at Rodgers Ranch.", "18 à Griffin, 24 au Rodgers Ranch.")),
    C("drones", "Drone time trials", "Contre-la-montre en drone", 42, None, _ac, T("14 places, 3 trials each.", "14 lieux, 3 épreuves chacun.")),
    C("hoops", "Basketball hoops", "Paniers de basket", 100, 90, _ac),
    C("pool", "Pool opponents beaten", "Adversaires battus au billard", 7, 5, _ac),
    C("minigolf", "Mini golf courses played", "Parcours de mini-golf joués", 3, 2, _ac),
    C("videogames", "Video games played", "Jeux vidéo joués", 4, None, _ac),
    C("challenges80", "Challenges completed", "Défis réussis", 80, 70, _ac, T("8 categories of 10.", "8 catégories de 10.")),
    C("decks", "Bret's target decks", "Cibles de Bret", 15, None, _ac, T("Jason's hunting story.", "L'histoire de chasse de Jason.")),
    C("tasks", "Optional tasks", "Tâches facultatives", 100, None, _jo, T("Side missions, deliveries, labs, fishing, Strangers & Freaks, meditations…", "Missions annexes, livraisons, labos, pêche, Strangers & Freaks, méditations…")),
    C("gangops", "Gang operations cleared", "Opérations de gangs nettoyées", 39, None, _jo),
    C("banks", "Bank jobs", "Braquages de banques", 22, None, _jo),
    C("payday", "Payday loan jobs", "Coups chez les prêteurs sur salaire", 7, None, _jo),
    C("smash", "Smash 'n' grabs (pawn shops, jewelers)", "Casses éclair (prêteurs sur gage, bijouteries)", 35, 34, _jo),
    C("stickups", "Stick-ups", "Braquages de magasins", 91, 50, _jo),
    C("vaults", "Vaults hit", "Coffres-forts vidés", 8, None, _jo),
    C("vehicles", "Base model vehicles scanned", "Modèles de véhicules scannés", 277, 200, _di),
    C("weapons", "Standard issue weapons found", "Armes standard trouvées", 66, 50, _di),
    C("animals", "Animals studied", "Animaux étudiés", 255, 100, _di),
]
for c in COLLECTIBLES:
    c.setdefault("group", T("Other", "Autres"))

CHALLENGES = [
    {"id": "story", "title": T("Finish the story", "Finir l'histoire"), "group": T("Story — 50% of the 100%", "Histoire — 50 % du 100 %"),
     "detail": T("All main missions, through the end credits.", "Toutes les missions principales, jusqu'au générique.")},
    {"id": "f-narco", "title": T("Fence $100,000 of narcotics", "Écouler 100 000 $ de drogue"), "group": T("Fencing", "Recel")},
    {"id": "f-jewel", "title": T("Fence $100,000 of jewelry", "Écouler 100 000 $ de bijoux"), "group": T("Fencing", "Recel")},
    {"id": "f-bills", "title": T("Fence $250,000 of marked bills", "Écouler 250 000 $ de billets marqués"), "group": T("Fencing", "Recel")},
    {"id": "f-cars", "title": T("Fence $200,000 of vehicles", "Écouler 200 000 $ de véhicules"), "group": T("Fencing", "Recel")},
]

# ---------------------------------------------------------------- Radio : stations et quelques morceaux de chacune
def S(sid, name, en, fr, songs):
    return {"id": sid, "name": name, "genre": T(en, fr), "songs": [{"artist": a, "title": t} for a, t in (x.split(" - ", 1) for x in songs)]}

STATIONS = [
    S("flash", "Flash FM", "Pop", "Pop", ["Charli xcx - Good Ones", "MGMT - Electric Feel", "Kylie Minogue - Spinning Around", "Dua Lipa - Houdini", "Chappell Roan - Hot to Go!", "Daft Punk - Around the World", "Billie Eilish - Lunch", "Gorillaz - Dare", "Robyn - Show Me Love", "Lorde - Green Light"]),
    S("vcfm", "Vice City FM", "80s pop", "Pop des années 80", ["Echo & the Bunnymen - Lips Like Sugar", "New Order - Thieves Like Us", "The Cure - Just Like Heaven", "Tears for Fears - Head over Heels", "Simple Minds - Alive and Kicking", "Matthew Wilder - Break My Stride", "Lionel Richie - All Night Long (All Night)", "Talk Talk - Talk Talk", "Billy Ocean - Loverboy", "Miami Sound Machine - Dr. Beat"]),
    S("vrock", "V-Rock", "Hard rock", "Hard rock", ["Van Halen - Panama", "Poison - Nothin' but a Good Time", "Mötley Crüe - Dr. Feelgood", "Def Leppard - Pour Some Sugar on Me", "AC/DC - Sin City", "Bon Jovi - Runaway", "Huey Lewis and the News - I Want a New Drug", "Dire Straits - Money for Nothing", "The Clash - Rock the Casbah", "Tom Petty - Love Is a Long Road"]),
    S("vcrr", "VCRR", "Hip-hop", "Hip-hop", ["Drake - Nokia", "Migos - Bad and Boujee", "Pop Smoke - Dior", "Travis Scott - RHYNO", "Gunna - Count Up", "Denzel Curry - Fla Flow", "21 Savage - Cookin", "Cardi B - Don't Chart", "Young Thug - Digits", "Central Cee - Rock N Roll"]),
    S("dirtysouth", "Dirty South Classics", "Southern hip-hop", "Hip-hop du Sud", ["Juvenile - Slow Motion", "Lil Wayne - A Milli", "OutKast - Player's Ball", "T.I. - Rubber Band Man", "Rick Ross - Hustlin'", "Three 6 Mafia - Side 2 Side", "Yung Joc - It's Goin' Down", "Mike Jones - Back Then", "Trick Daddy - I'm a Thug", "Petey Pablo - Freek-a-Leek"]),
    S("cocoteo", "Cocoteo FM", "Latin, reggaeton", "Latino, reggaeton", ["Bad Bunny - EoO", "Myke Towers - Girl", "Young Miko - Ni Le Cabe", "Don Omar - Intocable", "Rauw Alejandro - Macacoa 2000", "Feid - Chorrito Pa Las Ánimas", "Rosalía - Candy", "Karol G & Mariah Angeliq - El Makinón", "Fuerza Regida - Suzuki", "Farruko - Pepas"]),
    S("laola", "La Ola", "Salsa, Latin classics", "Salsa, classiques latinos", ["Gloria Estefan - Mi Tierra", "Celia Cruz - Bemba Colorá", "Héctor Lavoe - Periódico de Ayer", "Willie Colón & Rubén Blades - Pedro Navaja", "El Gran Combo de Puerto Rico - Brujería", "Oscar D'León - Llorarás", "Frankie Ruiz - Tú con Él", "Cachao - Descarga Cubana"]),
    S("afrobank", "AfroBank FM", "African music", "Musiques africaines", ["Asake - Joha", "Burna Boy - Bigger", "Ayra Starr - Sex Bills Bass Thrills", "Fireboy DML - YAWA", "Omah Lay - Holy Ghost", "Manu Dibango - Goro City", "Hugh Masekela - Run No More", "William Onyeabor - Fantastic Man"]),
    S("honey", "Honey FM", "R&B, slow jams", "R&B, slows", ["D'Angelo - Lady", "TLC - Creep", "Jodeci - Feenin'", "Brandy & Monica - The Boy Is Mine", "Mary J. Blige - My Life", "Next - Too Close", "Usher - Bad Girl", "Mariah Carey - Vision of Love", "Silk - Freak Me", "Toni Braxton - You're Makin' Me High"]),
    S("emotion", "Emotion", "Soft rock, ballads", "Soft rock, ballades", ["Phil Collins - In the Air Tonight", "The Cars - Drive", "Roxette - Listen to Your Heart", "Bruce Hornsby & The Range - The Way It Is", "Air Supply - All Out of Love", "Heart - Alone", "Chicago - Hard to Say I'm Sorry", "George Michael - Father Figure"]),
    S("backcountry", "Back Country Radio", "Country", "Country", ["Glen Campbell - Rhinestone Cowboy", "Hank Williams Jr. - A Country Boy Can Survive", "Merle Haggard - Stop the World and Let Me Off", "Joe Diffie - Pickup Man", "Loretta Lynn - Don't Come Home A-Drinkin' (With Lovin' On Your Mind)", "Waylon Jennings - Waymore's Blues", "Morgan Wallen - Last Thing You Need", "Tony Joe White - Polk Salad Annie"]),
    S("chamber", "The Chamber 106.6", "Metal", "Métal", ["Metallica - Master of Puppets", "Slayer - Raining Blood", "Megadeth - Symphony of Destruction", "Iron Maiden - The Trooper", "Pantera - I'm Broken", "Mastodon - Blood and Thunder", "TOOL - Sober", "System of a Down - Sugar"]),
    S("stockyard", "Stockyard FM", "Indie dance", "Indie dance", ["Róisín Murphy - Overpowered", "Justice & Tame Impala - One Night/All Night", "LCD Soundsystem - North American Scum", "Caribou - Never Come Back", "Hot Chip - Hungry Child", "Overmono - Good Lies", "PinkPantheress - Illegal", "The Dare - Interesting"]),
    S("circoloco", "CircoLoco Records Radio", "House, techno", "House, techno", ["Michael Bibi - Rhythm of the Night", "Chris Stussy - We On This Ride", "PAWSA - Collect the Commas", "Prospa - This Rhythm", "Skream - Floral", "Seth Troxler - Bootlicker", "Jimi Jules - Don't Break My Heart", "ANOTR - Silver Lines"]),
    S("kaleido", "Kaleidoscope FM", "World pop", "Pop du monde", ["Marianne Rosenberg - Herz Aus Glas", "Sylvie Vartan - Danse ta vie", "Touré Kunda - Nobel", "Laibach - Geburt einer Nation", "Mexican Institute of Sound - Sinfonía Agridulce", "Ron - Hai capito o no?"]),
    S("worldwide", "Worldwide FM", "Jazz, house, world", "Jazz, house, musiques du monde", ["Jamiroquai - Smile", "Roberta Flack - The First Time Ever I Saw Your Face", "Digable Planets - Rebirth of Slick (Cool Like Dat)", "Floating Points - Del Oro", "Little Simz & Obongjayar - Lion", "Bobby Caldwell - What You Won't Do for Love", "Teena Marie - I'm a Sucker for Your Love"]),
    S("onu", "Radio On-U", "Reggae, dub", "Reggae, dub", ["Horace Andy - Skylarking", "Freddie McGregor - Big Ship", "Ken Boothe - Everything I Own", "Janet Kay - Silly Games", "Gregory Isaacs - Mr. Cop", "Susan Cadogan - Hurt So Good", "Augustus Pablo - Ras Menilik Congo (Harp)"]),
    S("jazz", "Leonida Jazz Radio", "Jazz fusion", "Jazz fusion", ["Weather Report - Birdland", "Grover Washington Jr. - Mister Magic", "Bob James - Night Crawler", "Ronnie Laws - Always There", "Stanley Clarke - School Days", "Kokoroko - Tojo", "Thundercat - Fleer Ultra", "Herb Alpert - Rotation"]),
    S("blues", "Gloriana Blues Radio", "Blues", "Blues", ["John Lee Hooker - Boogie Chillen'", "Muddy Waters - Got My Mojo Working", "Howlin' Wolf - Smokestack Lightnin'", "Bo Diddley - I'm a Man", "Koko Taylor - I Got What It Takes", "Buddy Guy - Stone Crazy", "B.B. King - Chains and Things"]),
    S("symphony", "Symphony FM", "Classical", "Classique", ["Ludwig van Beethoven - Symphony No. 7 in A Major", "Pyotr Ilyich Tchaikovsky - Symphony No. 5 in E Minor", "Maurice Ravel - La valse, M. 72", "Claude Debussy - Nocturnes, L. 91: II. Fêtes", "Dmitri Shostakovich - Symphony No. 5 in D Minor", "George Frideric Handel - Messiah"]),
    S("wipe", "The Wipe", "Talk and more", "Émissions", []),
]

# ---------------------------------------------------------------- Codes de triche : même suite de flèches sur PS5 et Xbox
_ARROW = {"U": "↑", "D": "↓", "L": "←", "R": "→"}
def X(cid, en, fr, seq, group, unlock_en, unlock_fr):
    arrows = " ".join(_ARROW[c] for c in seq)
    return {"id": cid, "name": T(en[0], fr[0]), "effect": T(en[1], fr[1]), "group": group,
            "playstation": "↑ · L1+R1 · " + arrows, "xbox": "↑ · LB+RB · " + arrows, "note": T("Unlock: " + unlock_en, "Déblocage : " + unlock_fr)}
_P = T("Player", "Joueur"); _K = T("Combat", "Combat"); _V = T("Vehicles", "Véhicules"); _E = T("World", "Monde"); _F = T("Screen filters", "Filtres")
_story = ("finish the story", "finir l'histoire")
CHEATS = [
    X("money", ("$250,000", "Money"), ("250 000 $", "Argent"), "URDLULDR", _P, *_story),
    X("drunk", ("Drunk", "You and your partner get drunk."), ("Ivre", "Toi et ton partenaire êtes ivres."), "ULRUULRULR", _P, "spend $2,500 on alcohol", "dépenser 2 500 $ en alcool"),
    X("heat", ("Raise heat level", "Raises the heat level across the map."), ("Augmenter la tension", "Augmente le niveau de tension sur toute la carte."), "LDRDUDU", _P, "lose a 3-star wanted level 25 times", "semer 25 fois un avis de recherche 3 étoiles"),
    X("wanted", ("Raise wanted level", "Raises your wanted level."), ("Augmenter l'avis de recherche", "Augmente ton niveau de recherche."), "LDRDURU", _P, "lose a 3-star wanted level 50 times", "semer 50 fois un avis de recherche 3 étoiles"),
    X("focus", ("Unlimited focus", "Focus never runs out."), ("Concentration illimitée", "La concentration ne s'épuise jamais."), "DUUDUDUDUR", _P, *_story),
    X("nofall", ("No fall damage", "You take no fall damage."), ("Pas de dégâts de chute", "Aucun dégât en tombant."), "DUUUUUUUD", _P, "survive a 40 ft fall 20 times", "survivre 20 fois à une chute de 12 m"),
    X("parachute", ("Parachute", "Adds a parachute."), ("Parachute", "Ajoute un parachute."), "RULURULUR", _P, "50 skydives or BASE jumps from 300 ft or more", "50 sauts en parachute de 90 m ou plus"),
    X("armor", ("Body armor", "Adds body armor."), ("Gilet pare-balles", "Ajoute un gilet pare-balles."), "DULUUUUUUDD", _P, "complete 100 workouts", "faire 100 séances de sport"),
    X("repair", ("Repair vehicle", "Fully repairs your vehicle."), ("Réparer le véhicule", "Répare entièrement ton véhicule."), "RDDRDRRD", _P, "win 10 races at the raceways", "gagner 10 courses sur les circuits"),
    X("nitro", ("Unlimited nitrous", "Nitrous and fuel never run out."), ("Nitro illimitée", "Nitro et carburant illimités."), "RDDRDRRL", _P, "complete 50 stunt jumps", "réussir 50 sauts"),
    X("maxammo", ("Max ammo", "Refills every weapon."), ("Munitions au max", "Recharge toutes les armes."), "DURDLLUUDL", _K, "25 bronze medals at shooting ranges", "25 médailles de bronze au stand de tir"),
    X("infammo", ("Infinite ammo", "Ammo never runs out."), ("Munitions infinies", "Les munitions ne s'épuisent jamais."), "DURDLLUDDD", _K, "25 silver medals at shooting ranges", "25 médailles d'argent au stand de tir"),
    X("noreload", ("No reload", "No more reloading."), ("Sans rechargement", "Plus besoin de recharger."), "DURDLLUDDU", _K, "25 gold medals at shooting ranges", "25 médailles d'or au stand de tir"),
    X("explosives", ("All explosive weapons", "Every explosive weapon, full ammo."), ("Toutes les armes explosives", "Toutes les armes explosives, munitions pleines."), "RULURULUL", _K, "throw 100 grenades", "lancer 100 grenades"),
    X("fireammo", ("Incendiary ammo", "Shots set targets on fire."), ("Balles incendiaires", "Les tirs enflamment les cibles."), "DURDLDURDD", _K, "100 kills with fire", "100 éliminations par le feu"),
    X("bottles", ("Exploding bottles", "Bottles explode when hit."), ("Bouteilles explosives", "Les bouteilles explosent quand on les touche."), "DULLRDDUL", _K, "throw 100 Molotovs", "lancer 100 cocktails Molotov"),
    X("shotgun", ("Explosive shotgun", "A shotgun with explosive shells."), ("Fusil à pompe explosif", "Un fusil à cartouches explosives."), "DURDLDURDL", _K, "100 explosive hits on enemies", "100 coups explosifs sur des ennemis"),
    X("hat", ("Hauners H-AT", "Adds a rocket launcher."), ("Hauners H-AT", "Ajoute un lance-roquettes."), "RULURULUU", _K, "destroy 100 vehicles", "détruire 100 véhicules"),
    X("force", ("Attack force", "Hits send people flying."), ("Force d'impact", "Les coups projettent les gens."), "DULLRDDUD", _K, *_story),
    X("balls", ("Exploding balls", "Sports balls explode on impact."), ("Ballons explosifs", "Les ballons explosent à l'impact."), "DULLRDDUR", _K, "20 explosive hits on enemies", "20 coups explosifs sur des ennemis"),
    X("vforce", ("Vehicle force", "Cars launch people into the air."), ("Force des véhicules", "Les voitures projettent les gens en l'air."), "DULLRDLUD", _K, "25 vehicle kills", "25 éliminations en véhicule"),
    X("v-ambulance", ("Interstate Ambulance", "Spawns it."), ("Ambulance Interstate", "La fait apparaître."), "LURDLRRR", _V, "discover it in the Progress menu", "la découvrir dans le menu Progression"),
    X("v-airboat", ("Airboat 09", "Spawns it."), ("Hydroglisseur Airboat 09", "Le fait apparaître."), "LURDLDUR", _V, "5 Survival challenges", "5 défis Survie"),
    X("v-banshee", ("Bravado Banshee", "Spawns it."), ("Bravado Banshee", "La fait apparaître."), "LURDLRUL", _V, "all Combat challenges", "tous les défis Combat"),
    X("v-bmx", ("Tuff BMX", "Spawns it."), ("BMX Tuff", "Le fait apparaître."), "LURDLLUR", _V, "5 Fitness challenges", "5 défis Forme"),
    X("v-boomazoom", ("Maibatsu Boomazoom", "Spawns it."), ("Maibatsu Boomazoom", "La fait apparaître."), "LURDLLUL", _V, "5 Shopping challenges", "5 défis Shopping"),
    X("v-carbon", ("Nagasaki Carbon RS", "Spawns it."), ("Nagasaki Carbon RS", "La fait apparaître."), "LURDLLUU", _V, "all Exploration challenges", "tous les défis Exploration"),
    X("v-dominator", ("'65 Vapid Dominator", "Spawns it."), ("Vapid Dominator 65", "La fait apparaître."), "LURDLRLR", _V, "all Fitness challenges", "tous les défis Forme"),
    X("v-emerus", ("Progen Emerus", "Spawns it."), ("Progen Emerus", "La fait apparaître."), "LURDLRUR", _V, "all Vehicle challenges", "tous les défis Véhicules"),
    X("v-flamingo", ("Inflatable Flamingo", "Spawns it."), ("Flamant gonflable", "Le fait apparaître."), "LURDLDUD", _V, "destroy 50 cocaine flamingos", "détruire 50 flamants roses à la cocaïne"),
    X("v-pumper", ("MTL Pumper fire truck", "Spawns it."), ("Camion de pompiers MTL Pumper", "Le fait apparaître."), "LURDLRRU", _V, "discover it in the Progress menu", "le découvrir dans le menu Progression"),
    X("v-taxi", ("Vapid Stanier G2 Taxi", "Spawns it."), ("Taxi Vapid Stanier G2", "Le fait apparaître."), "LURDLRRL", _V, "5 Sports challenges", "5 défis Sport"),
    X("v-lazer", ("Hauners P-996 Lazer", "Spawns the jet."), ("Hauners P-996 Lazer", "Fait apparaître le jet."), "LURDLUUD", _V, "every challenge", "tous les défis"),
    X("v-dozer", ("HVY Bulldozer", "Spawns it."), ("Bulldozer HVY", "Le fait apparaître."), "LURDLRRD", _V, "discover it in the Progress menu", "le découvrir dans le menu Progression"),
    X("v-mallard", ("Lapwing Mallard", "Spawns the plane."), ("Lapwing Mallard", "Fait apparaître l'avion."), "LURDLUUU", _V, "5 Vehicle challenges", "5 défis Véhicules"),
    X("v-golfer", ("Brimstone Golfer", "Spawns it."), ("Brimstone Golfer", "La fait apparaître."), "LURDLRUD", _V, "all Sports challenges", "tous les défis Sport"),
    X("v-rhino", ("Hauners Rhino Tank", "Spawns the tank."), ("Char Hauners Rhino", "Fait apparaître le char."), "LURDLRLU", _V, "all Survival challenges", "tous les défis Survie"),
    X("v-sanchez", ("Maibatsu Sanchez", "Spawns the dirt bike."), ("Maibatsu Sanchez", "Fait apparaître la moto-cross."), "LURDLLRU", _V, "5 Criminal challenges", "5 défis Criminels"),
    X("v-seasparrow", ("Nagasaki Sea Sparrow", "Spawns the helicopter."), ("Nagasaki Sea Sparrow", "Fait apparaître l'hélicoptère."), "LURDLUUR", _V, "5 Exploration challenges", "5 défis Exploration"),
    X("v-speeder", ("Speeder 700 GT", "Spawns the boat."), ("Speeder 700 GT", "Fait apparaître le bateau."), "LURDLDUU", _V, "5 Combat challenges", "5 défis Combat"),
    X("v-thrax", ("Truffade Thrax", "Spawns it."), ("Truffade Thrax", "La fait apparaître."), "LURDLRUU", _V, "all Shopping challenges", "tous les défis Shopping"),
    X("v-bobber", ("Western Zombie Bobber", "Spawns the motorcycle."), ("Western Zombie Bobber", "Fait apparaître la moto."), "LURDLLUD", _V, "all Criminal challenges", "tous les défis Criminels"),
    X("time", ("Move time forward", "Moves the time of day forward."), ("Avancer l'heure", "Fait avancer l'heure."), "DRUDRUU", _E, "find 10 collectible watches", "trouver 10 montres"),
    X("pause", ("Pause time of day", "Freezes the time of day."), ("Figer l'heure", "Fige l'heure."), "DRUDRUL", _E, "find 20 collectible watches", "trouver 20 montres"),
    X("weather", ("Cycle weather", "Changes the weather."), ("Changer la météo", "Fait défiler les météos."), "DRUDRUR", _E, *_story),
    X("f-golden", ("Golden Hour", "Golden tint, widescreen."), ("Heure dorée", "Teinte dorée, format large."), "DDURRULLUU", _F, "spend 4 hours holding hands", "passer 4 heures main dans la main"),
    X("f-sugar", ("Powdered Sugar", "A white, sparkling world."), ("Sucre glace", "Un monde blanc et scintillant."), "DDURRULLUR", _F, "scan all space debris with WAiNK", "scanner tous les débris spatiaux avec WAiNK"),
    X("f-pinhole", ("Pinhole", "Pinhole camera look."), ("Sténopé", "Effet d'appareil sténopé."), "DDURRULLUD", _F, "clear 25 gang operations with your partner", "nettoyer 25 opérations de gangs à deux"),
    X("f-neon", ("Neon Jungle", "Neon highlights."), ("Jungle néon", "Reflets néon."), "DDURRULLUL", _F, "find all 16 Girlypop vehicles", "trouver les 16 véhicules Girlypop"),
    X("f-yesteryear", ("Yesteryear", "Black-and-white TV look."), ("Autrefois", "Look de vieille télé noir et blanc."), "DDURRULLRU", _F, "discover the Ridgeway", "découvrir la Ridgeway"),
    X("f-cataclysm", ("Cataclysm", "Murky smoke everywhere."), ("Cataclysme", "Une fumée épaisse partout."), "DDURRULLRR", _F, "discover Martha's Vamos", "découvrir la Vamos de Martha"),
    X("f-vhs", ("Videotape", "Old videotape look."), ("Cassette vidéo", "Look de vieille cassette."), "DDURRULLRD", _F, "50 activities with your partner", "50 activités à deux"),
    X("f-mirror", ("Dark Mirror", "Black, upside-down world."), ("Miroir noir", "Monde noir, à l'envers."), "DDURRULLRL", _F, "make $500,000 selling vehicles", "gagner 500 000 $ en vendant des véhicules"),
    X("f-migraine", ("Migraine", "Blurred, distorted screen."), ("Migraine", "Écran flou et déformé."), "DDURRULLDU", _F, "survive 6 minutes at 6 stars", "survivre 6 minutes à 6 étoiles"),
    X("f-doll", ("Dollhouse", "Vivid colors, narrow frame."), ("Maison de poupée", "Couleurs vives, cadre étroit."), "DDURRULLDR", _F, "spend 8 hours with your partner", "passer 8 heures avec ton partenaire"),
    X("f-bubblegum", ("Bubblegum", "Purple and yellow sparkles."), ("Chewing-gum", "Violet, jaune et paillettes."), "DDURRULLDD", _F, "find all 24 Vice City Flamingos cards", "trouver les 24 cartes Vice City Flamingos"),
    X("f-fast", ("Fast Forward", "Motion blur, fast clouds."), ("Avance rapide", "Flou de mouvement, nuages rapides."), "DDURRULLDL", _F, "complete 50 meditations", "faire 50 méditations"),
    X("f-fisheye", ("Fisheye", "Fisheye lens."), ("Fisheye", "Objectif fisheye."), "DDURRULLLU", _F, "catch 100 fish", "pêcher 100 poissons"),
    X("f-faded", ("Faded Glory", "Old color TV look."), ("Gloire passée", "Look de vieille télé couleur."), "DDURRULLLR", _F, "rob 50 stores with your partner", "braquer 50 magasins à deux"),
    X("f-pixel", ("Pixel Art", "Pixelated screen."), ("Pixel art", "Écran pixelisé."), "DDURRULLLD", _F, "make $250,000 selling collectibles", "gagner 250 000 $ en vendant des objets"),
    X("f-hell", ("Hellscape", "Red, hazy, burning world."), ("Enfer", "Monde rouge et brûlant."), "DDURRULLLL", _F, "steal 100 police vehicles", "voler 100 véhicules de police"),
]
NEWS = [
    ("n1", "2026-11-23", T("Welcome to Vicefold", "Bienvenue dans Vicefold"),
     T("The first guides are here. Missions, collectibles and more arrive with free content updates.",
       "Les premiers guides sont là. Missions, objets à collectionner et le reste arrivent avec des mises à jour gratuites du contenu.")),
]

# Ce qu'on sait de certaines missions (protagoniste, lieu), et les missions facultatives de chaque chapitre.
_INFO = {
    "Coming Home": {"giver": "Jason & Lucia", "location": "Leonida Penitentiary → Leonida Keys"},
    "Pipework": {"giver": "Jason", "location": "Leonida Keys"},
    "Unwanted Attention": {"giver": "Jason"},
    "Sinfrontera National Bank": {"giver": "Jason & Lucia", "location": "Vice City"},
}
for m in MISSIONS:
    for k, v in _INFO.get(m["title"], {}).items():
        m.setdefault(k, v)
_OPT = {1: ["Get Shirley's Rum", "Steal the Scooter", "Pick Up Groceries", "Buy Flowers", "Buy Lucia a Necklace", "Get The Chop", "Get Lucia's Clothes", "Find the Lost Drugs"],
        2: ["Pick Up a Gun", "Hit Avery Pawn", "Hit Kingpin Bowling"], 3: ["Get Your Wheels"],
        4: ["Bad Driver!", "This is a Free Call From...", "Attend Eddie Acosta's Party", "That's Where the Money Is"]}
for ch, names in _OPT.items():
    for i, n in enumerate(names, 1):
        MISSIONS.append({"id": f"o{ch}-{i:02d}", "chapter": ch, "title": n, "optional": True})

# Strangers & Freaks : les quêtes annexes, par personnage (cochables dans Défis).
_SF = [("Kirk", 1, ["Search for the Skunk Ape", "Search for Tree Effigies", "Help Kirk Find Mr. Mangrove"]),
       ("Shirley", 1, ["Get Shirley's Rum", "Steal the Scooter"]),
       ("Kenton", 1, ["Treasure dives"]), ("Cal", 1, ["Catch a Bigger Fish"]),
       ("Kyle", 2, ["Check Out McKittrick Farm", "Collect Chemicals for Kyle", "Buddy?"]),
       ("Billy", 2, ["Thrillbillies", "Twist Wrist, Smash, Grab", "Mall Rats", "The Impaler", "Hometown Heroes"]),
       ("Bret Vogel", 2, ["Veteran Hunted", "Bret's Hunting Decks"]), ("Moses", 2, ["Steal Vehicles for Moses"]),
       ("Yago", 3, ["Join a Street Race", "Bumper to Bumper", "Race Against Yago", "Brother to Brother"]),
       ("Andy", 3, ["Climbing the Cellerichain", "Pay the Cellerica Fee", "Peach!", "Read the Label", "Puff Puff Pass"]),
       ("Yasmani", 3, ["Jewelry Jobs", "ATM Jobs", "Payday Loans Jobs", "Tail the Security Van"]),
       ("Randy", 3, ["Randy's Wish List"]), ("Tyrone", 3, ["Take Out Kitty Litter", "Spin On This"]),
       ("Pilot Pete", 4, ["The Last Mile: Passing the Torch", "The Last Mile: Backseat Pilot", "Pete's Deliveries"])]
for who, ch, items in _SF:
    for i, n in enumerate(items, 1):
        CHALLENGES.append({"id": f"sf-{who.lower().replace(' ', '')}-{i}", "title": n,
                           "group": T(f"Strangers & Freaks — {who}", f"Strangers & Freaks — {who}"),
                           "detail": T(f"Chapter {ch}", f"Chapitre {ch}")})

GUIDES += [
    ("hundred", "challenges", T("What counts toward 100%", "Ce qui compte pour le 100 %"),
     T("Story is half of it. Here's the other half, and how much you really need.", "L'histoire en fait la moitié. Voici l'autre moitié, et ce qu'il faut vraiment."),
     T("""# How the 100% is split
- Story: 50%. Finish every main mission, through the end credits.
- Tasks: 27%. Optional tasks, gang operations, bank jobs, payday loans, smash 'n' grabs, stick-ups, vaults, and money fenced.
- Exploration and activities: 20%. Collectibles, stunts, races, shooting ranges, drones, hoops, pool, mini golf and more.
- Discovery: 3%. Vehicles scanned, weapons found, animals studied.
# You don't need everything
Many categories only ask for part of the total: 15 of 18 card sets, 100 of 125 flamingos, 300 of 397 stunts, 50 of 91 stick-ups. Vicefold shows both numbers on every counter.
# Where to track it
Tracker › Collectibles has a counter for each category, with what's needed. The game's own checklist opens after the story, under Progress › Stats.
> Reaching 100% unlocks the A Long Road trophy.""",
       """# Comment se répartit le 100 %
- Histoire : 50 %. Toutes les missions principales, jusqu'au générique.
- Tâches : 27 %. Tâches facultatives, opérations de gangs, braquages de banques, prêteurs sur salaire, casses éclair, braquages de magasins, coffres, et argent écoulé.
- Exploration et activités : 20 %. Objets à collectionner, cascades, courses, stands de tir, drones, paniers, billard, mini-golf et plus.
- Découvertes : 3 %. Véhicules scannés, armes trouvées, animaux étudiés.
# Pas besoin de tout faire
Beaucoup de catégories ne demandent qu'une partie du total : 15 séries de cartes sur 18, 100 flamants sur 125, 300 cascades sur 397, 50 braquages de magasins sur 91. Vicefold affiche les deux nombres sur chaque compteur.
# Où suivre tout ça
Suivi › Objets a un compteur par catégorie, avec ce qu'il faut. La liste du jeu s'ouvre après l'histoire, dans Progression › Statistiques.
> Le 100 % débloque le trophée A Long Road."""), 0, 3),
    ("cheats-how", "cheats", T("How cheat codes work", "Comment marchent les codes"),
     T("Unlock them first, then enter them on the phone.", "Débloque-les d'abord, puis tape-les sur le téléphone."),
     T("""# Unlock them
Cheats open after the story, one at a time: each one has its own goal (a number of jumps, medals, kills, places found…). Vicefold lists the goal under every code.
# Enter them
1. Press up on the D-pad to open the phone.
2. Hold L1 (LB on Xbox) and press R1 (RB).
3. Enter the arrows on the D-pad.
# Before you use one
> A cheat turns off trophies and saving for the session, and what you do after it is lost when you quit. Save first.""",
       """# Les débloquer
Les codes s'ouvrent après l'histoire, un par un : chacun a son objectif (un nombre de sauts, de médailles, d'éliminations, de lieux trouvés…). Vicefold l'indique sous chaque code.
# Les entrer
1. Appuie en haut sur la croix pour ouvrir le téléphone.
2. Maintiens L1 (LB sur Xbox) et appuie sur R1 (RB).
3. Entre les flèches sur la croix.
# Avant de t'en servir
> Un code coupe les trophées et la sauvegarde pour la session, et ce que tu fais ensuite est perdu en quittant. Sauvegarde avant."""), 5, 2),
    ("strangers", "events", T("Strangers & Freaks", "Strangers & Freaks"),
     T("The side stories, character by character.", "Les histoires annexes, personnage par personnage."),
     T("""# Who you'll meet
- Chapter 1: Kirk (cryptid hunting), Shirley (errands), Kenton (treasure dives in the Keys), Cal (fishing).
- Chapter 2: Kyle, Billy (mud club and more), Bret Vogel (hunting, Jason only), Moses (car thefts).
- Chapter 3: Yago (street racing), Andy (Lucia only), Yasmani (jewelry, ATM and payday loan jobs), Randy (cars to steal), Tyrone.
- Chapter 4: Pilot Pete (flights from the airfields).
# Track them
Each one is in Tracker › Challenges, grouped by character. They count among the optional tasks of the 100%.""",
       """# Qui tu vas croiser
- Chapitre 1 : Kirk (chasse aux créatures), Shirley (courses), Kenton (plongées au trésor dans les Keys), Cal (pêche).
- Chapitre 2 : Kyle, Billy (mud club et plus), Bret Vogel (chasse, Jason seulement), Moses (vols de voitures).
- Chapitre 3 : Yago (courses de rue), Andy (Lucia seulement), Yasmani (bijouteries, distributeurs et prêteurs sur salaire), Randy (voitures à voler), Tyrone.
- Chapitre 4 : Pilot Pete (vols depuis les aérodromes).
# Les suivre
Chacune est dans Suivi › Défis, rangée par personnage. Elles comptent dans les tâches facultatives du 100 %."""), 1, 2),
    ("radio-guide", "hobbies", T("The radio", "La radio"),
     T("21 stations, from 80s pop to Southern rap.", "21 stations, de la pop des années 80 au rap du Sud."),
     T("""# Two playlists count
Two unique playlists count toward 100%. Find the stations in More › Radio, with track lists and 30-second previews.
# A few to start with
- Vice City FM for 80s pop, V-Rock for big guitars.
- VCRR and Dirty South Classics for rap.
- Cocoteo FM and La Ola for reggaeton and salsa.
- Honey FM for slow jams, Emotion for ballads.""",
       """# Deux playlists comptent
Deux playlists uniques comptent pour le 100 %. Les stations sont dans Plus › Radio, avec leurs morceaux et des extraits de 30 secondes.
# Pour commencer
- Vice City FM pour la pop des années 80, V-Rock pour les grosses guitares.
- VCRR et Dirty South Classics pour le rap.
- Cocoteo FM et La Ola pour le reggaeton et la salsa.
- Honey FM pour les slows, Emotion pour les ballades."""), 0, 2),
]
NEWS.insert(0, ("n2", "2026-11-23", T("All 91 missions and the full 100%", "Les 91 missions et tout le 100 %"),
     T("Every story mission by chapter, optional missions, Strangers & Freaks, every 100% category, 61 cheat codes and 21 radio stations.",
       "Toutes les missions par chapitre, les missions facultatives, Strangers & Freaks, toutes les catégories du 100 %, 61 codes et 21 radios.")))

SOURCES = T(["Facts from the publisher's official character and setting announcements. All text written for Vicefold."],
            ["Faits tirés des annonces officielles de l'éditeur (personnages, lieux). Tous les textes sont rédigés pour Vicefold."])


def build(lang):
    pick = lambda t: t[lang] if isinstance(t, dict) else t
    places = []
    for p in PLACES:
        pid, name, kind, x, y, region, note = p[:7]
        d = {"id": pid, "name": name, "kind": kind, "x": x, "y": y, "note": pick(note)}
        if region:
            d["region"] = region
        if len(p) > 7:
            d["spoiler"] = p[7]
        places.append(d)
    return {
        "version": VERSION,
        "updated": NEWS[0][1],
        "sources": pick(SOURCES),
        "chapters": [{"id": c[0], "title": pick(c[1])} for c in CHAPTERS],
        "missions": [dict({k: pick(v) for k, v in m.items()}) for m in MISSIONS],
        "guides": [{"id": g[0], "category": g[1], "title": pick(g[2]), "summary": pick(g[3]), "body": pick(g[4]),
                    "spoiler": g[5], "minutes": g[6]} for g in GUIDES],
        "places": places,
        "collectibles": [dict({k: pick(v) for k, v in c.items()}) for c in COLLECTIBLES],
        "challenges": [dict({k: pick(v) for k, v in c.items()}) for c in CHALLENGES],
        "characters": [{"id": c[0], "name": c[1], "role": pick(c[2]), "bio": pick(c[3]), "tags": c[4], "spoiler": 0} for c in CHARACTERS],
        "stations": [dict({k: (pick(v) if k != "songs" else v) for k, v in st.items()}) for st in STATIONS],
        "cheats": [dict({k: pick(v) for k, v in c.items()}) for c in CHEATS],
        "news": [{"id": n[0], "date": n[1], "title": pick(n[2]), "body": pick(n[3])} for n in NEWS],
    }


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for lang in ("en", "fr"):
        with open(os.path.join(OUT, f"content-{lang}.json"), "w", encoding="utf-8") as f:
            json.dump(build(lang), f, ensure_ascii=False, indent=1)
    print("ok", VERSION)
