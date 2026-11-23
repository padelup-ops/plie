"""VICEFOLD : écrit le contenu du guide (Content/content-en.json et content-fr.json) à partir d'une seule source.

Tout le texte est rédigé pour Vicefold, à partir de faits publics (noms de personnages, de lieux, de missions).
Aucun texte, image ou donnée d'un autre guide n'est copié. Chaque donnée a sa version anglaise et française.
Pour publier une mise à jour du guide : augmenter VERSION, relancer ce script, pousser (l'app la télécharge seule).
"""
import json
import os

VERSION = 1
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

CHAPTERS = []
MISSIONS = []
COLLECTIBLES = []
CHALLENGES = []
STATIONS = []
CHEATS = []
NEWS = [
    ("n1", "2026-11-23", T("Welcome to Vicefold", "Bienvenue dans Vicefold"),
     T("The first guides are here. Missions, collectibles and more arrive with free content updates.",
       "Les premiers guides sont là. Missions, objets à collectionner et le reste arrivent avec des mises à jour gratuites du contenu.")),
]

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
        "stations": STATIONS,
        "cheats": [dict({k: pick(v) for k, v in c.items()}) for c in CHEATS],
        "news": [{"id": n[0], "date": n[1], "title": pick(n[2]), "body": pick(n[3])} for n in NEWS],
    }


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for lang in ("en", "fr"):
        with open(os.path.join(OUT, f"content-{lang}.json"), "w", encoding="utf-8") as f:
            json.dump(build(lang), f, ensure_ascii=False, indent=1)
    print("ok", VERSION)
