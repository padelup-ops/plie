"""Écrit les textes de Duo Folds en anglais et en français (Shared/*.lproj/Localizable.strings).

Usage : python3 clapet/tools/strings.py   (vérifie aussi qu'aucun texte de l'app n'est oublié)
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")

FR = {
    # Accueil
    "Duo Folds": "Duo Folds",
    "Duo Folds+": "Duo Folds+",
    "Settings": "Réglages",
    "folds": "plis",
    "Today": "Aujourd'hui",
    "%lld left today": "Encore %lld aujourd'hui",
    "Limit reached": "Limite atteinte",
    "%lld over the limit": "%lld au-dessus de la limite",
    "Closed today": "Fermé aujourd'hui",
    "Opened today": "Ouvert aujourd'hui",
    "Last 7 days": "7 derniers jours",
    "All time": "Au total",
    "Limit alerts": "Alertes de limite",
    "History": "Historique",
    "30 days, 12 months, records": "30 jours, 12 mois, records",
    "This week": "Cette semaine",
    "Today by hour": "Aujourd'hui, heure par heure",
    "Peak %@": "Pic à %@",
    "This widget is part of Duo Folds+.": "Ce widget fait partie de Duo Folds+.",
    "Limit alerts are part of Duo Folds+.": "Les alertes de limite font partie de Duo Folds+.",
    "Your full history and records are part of Duo Folds+.": "L'historique complet et les records font partie de Duo Folds+.",
    "Day": "Jour",
    "Folds": "Plis",
    "Limit": "Limite",
    # Alertes
    "Daily limit reached": "Limite du jour atteinte",
    "%lld folds today. Time for a break from your phone?": "%lld plis aujourd'hui. Et si tu faisais une pause avec ton téléphone ?",
    "Almost at your limit": "Bientôt ta limite",
    "%lld folds today, your limit is %lld.": "%1$lld plis aujourd'hui, ta limite est de %2$lld.",
    # Historique
    "Export as a spreadsheet (CSV)": "Exporter en tableur (CSV)",
    "Done": "OK",
    "30 days": "30 jours",
    "12 months": "12 mois",
    "Period": "Période",
    "folds in 30 days": "plis en 30 jours",
    "folds in 12 months": "plis en 12 mois",
    "Under the limit": "Sous la limite",
    "Over the limit": "Au-dessus de la limite",
    "Days under the limit in a row": "Jours d'affilée sous la limite",
    "Longest streak": "Plus longue série",
    "This week vs last week": "Cette semaine contre la précédente",
    "Average per day": "Moyenne par jour",
    "Calmest day": "Jour le plus calme",
    "Busiest day": "Jour le plus chargé",
    "Busiest hour": "Heure la plus chargée",
    "Days tracked": "Jours suivis",
    # Raccourcis
    "Adds one fold to today's count.": "Ajoute un pli au compte du jour.",
    "%lld folds today": "%lld plis aujourd'hui",
    "Tells you how many times you closed your Duo today.": "Dit combien de fois tu as fermé ton Duo aujourd'hui.",
    "Count a fold": "Compter un pli",
    "Folds today": "Plis du jour",
    # Duo Folds+
    "Close": "Fermer",
    "Pay once, keep it forever. No subscription.": "Tu paies une fois, c'est à toi pour toujours. Sans abonnement.",
    "Every widget": "Tous les widgets",
    "The big Health-style widget, the medium one and the Lock Screen ones: your folds at a glance.":
        "Le grand widget façon Santé, le moyen et ceux de l'écran verrouillé : tes plis d'un coup d'œil.",
    "A notification at 80 % and at 100 % of your daily limit.": "Une notification à 80 % et à 100 % de ta limite du jour.",
    "Your full history": "Tout l'historique",
    "30 days, 12 months, the calendar of days under your limit, your trends and records.":
        "30 jours, 12 mois, le calendrier des jours sous ta limite, tes tendances et tes records.",
    "Widget colors": "Couleurs des widgets",
    "Five colors for your widgets.": "Cinq couleurs pour tes widgets.",
    "Export": "Export",
    "Your history as a spreadsheet (CSV).": "Ton historique en tableur (CSV).",
    "Duo Folds+ is unlocked. Thank you!": "Duo Folds+ est débloqué. Merci !",
    "Unlock for %@": "Débloquer pour %@",
    "Unlock Duo Folds+": "Débloquer Duo Folds+",
    "Restore purchases": "Restaurer les achats",
    "DUO FOLDS": "DUO FOLDS",
    "all time": "au total",
    "The App Store isn't answering right now. Try again in a moment.": "L'App Store ne répond pas pour le moment. Réessaie dans un instant.",
    "The purchase couldn't be verified.": "L'achat n'a pas pu être vérifié.",
    "Your purchase is waiting for approval.": "Ton achat attend une validation.",
    "The purchase didn't go through. Try again in a moment.": "L'achat n'a pas abouti. Réessaie dans un instant.",
    "Purchases can't be restored right now.": "Impossible de restaurer les achats pour le moment.",
    "No purchase to restore on this Apple Account.": "Aucun achat à restaurer sur ce compte Apple.",
    # Réglages
    "Widget color": "Couleur des widgets",
    "Daily limit: %lld": "Limite du jour : %lld",
    "Daily limit": "Limite du jour",
    "Notifications are off for Duo Folds. Turn them on in the Settings app.":
        "Les notifications de Duo Folds sont coupées. Active-les dans l'app Réglages.",
    "A notification at 80 % and at 100 % of your limit.": "Une notification à 80 % et à 100 % de ta limite.",
    "Sounds": "Sons",
    "Vibrations": "Vibrations",
    "Feel": "Ressenti",
    "iOS only tells an app about the hinge while that app is on screen. Duo Folds counts while it's open, on the inner or the outer screen.":
        "iOS ne prévient une app des mouvements de la charnière que quand elle est à l'écran. Duo Folds compte donc tant qu'il est ouvert, sur l'écran intérieur ou extérieur.",
    "In Shortcuts, the “Count a fold” action adds one fold. If your Duo offers an automation when it's folded, plug it in there to count all day long.":
        "Dans Raccourcis, l'action « Compter un pli » ajoute un pli. Si ton Duo propose une automatisation quand il est plié, branche-la dessus pour compter toute la journée.",
    "How it counts": "Comment il compte",
    "Simulate Duo Folds+": "Simuler Duo Folds+",
    "Test version": "Version de test",
    "Only in TestFlight. In TestFlight, the purchase is free too (Apple's test mode).":
        "Seulement dans TestFlight. Dans TestFlight, l'achat est aussi gratuit (mode test d'Apple).",
    "Reset all folds": "Tout remettre à zéro",
    "Reset all folds?": "Tout remettre à zéro ?",
    "Reset": "Remettre à zéro",
    "Cancel": "Annuler",
    "Your history and records will be erased.": "Ton historique et tes records seront effacés.",
    # Widgets
    "Tap to unlock": "Touche pour débloquer",
    "Tap to unlock this widget": "Touche pour débloquer ce widget",
    "PLUS": "PLUS",
    "Last fold %@": "Dernier pli %@",
    "today vs yesterday": "aujourd'hui / hier",
    "today": "aujourd'hui",
    "%lld all time": "%lld au total",
    "How many times you closed your Duo, like your steps in Health.": "Combien de fois tu as fermé ton Duo, comme tes pas dans Santé.",
    # Couleurs
    "Mint": "Menthe", "Orange": "Orange", "Pink": "Rose", "Blue": "Bleu", "Lemon": "Citron",
    "Fold master": "Maître du pli", "Hinge hero": "Héros de la charnière", "Fold legend": "Légende du pli",
    # Nouveau style
    "Plus": "Plus",
    "+1": "+1",
    "On": "Activées",
    "Hinge %lld°": "Charnière %lld°",
    "Yesterday": "Hier",
    "Lifetime": "Depuis le début",
    "Next milestone: %lld": "Prochain palier : %lld",
    "%lld folds to the next milestone": "%lld plis avant le prochain palier",
    "%lld to go": "encore %lld",
    "%lld folds": "%lld plis",
    "At 80 % and 100 % of your limit": "À 80 % et à 100 % de ta limite",
    "Duo Folds counts while it's on screen, on the inner or the outer display.": "Duo Folds compte tant qu'il est à l'écran, intérieur ou extérieur.",
    "No hinge here: tap the Duo drawing to count.": "Pas de charnière ici : touche le dessin du Duo pour compter.",
    "Add the widgets from your Home Screen or Lock Screen: touch and hold, Edit, then Duo Folds.":
        "Ajoute les widgets depuis l'écran d'accueil ou l'écran verrouillé : reste appuyé, Modifier, puis Duo Folds.",
    "Three days of tracking. Keep an eye on your folds right from your Home Screen.":
        "Trois jours de suivi. Garde un œil sur tes plis directement depuis ton écran d'accueil.",
    "One-time purchase, linked to your Apple Account. Counting, the daily limit, the week, the milestones and the small widget stay free.":
        "Achat unique, lié à ton compte Apple. Le comptage, la limite du jour, la semaine, les paliers et le petit widget restent gratuits.",
    # Comptage automatique (Raccourcis)
    "Automatic counting": "Comptage automatique",
    "Count every fold, even when Duo Folds isn't on screen.": "Compte chaque pli, même quand Duo Folds n'est pas à l'écran.",
    "Your Duo can run a Shortcuts automation each time it's closed. Plug Duo Folds into it: it takes a minute, and it counts all day long.":
        "Ton Duo peut lancer une automatisation Raccourcis à chaque fermeture. Branche Duo Folds dessus : ça prend une minute, et il compte toute la journée.",
    "Open the **Shortcuts** app, **Automation** tab, then tap **+**.": "Ouvre l'app **Raccourcis**, onglet **Automatisation**, puis touche **+**.",
    "Choose the trigger **When iPhone is Opened or Closed**, tap the blue words and keep **Closed** only.":
        "Choisis le déclencheur **iPhone ouvert ou fermé** (When iPhone is Opened or Closed), touche les mots en bleu et garde seulement **Fermé**.",
    "Select **Run Immediately** and turn **Notify When Run** off.": "Choisis **Exécuter immédiatement** et désactive **Notifier lors de l'exécution**.",
    "Tap **Next**, then add the action **Count a fold** (Duo Folds).": "Touche **Suivant**, puis ajoute l'action **Compter un pli** (Duo Folds).",
    "Back in the list, check that the automation is **turned on**. iOS sometimes adds it switched off.":
        "De retour dans la liste, vérifie que l'automatisation est **activée**. iOS l'ajoute parfois désactivée.",
    "Set up": "Mise en place",
    "Optional: a second automation on **Opened** with the action **Count an opening** also counts your openings.":
        "Facultatif : une deuxième automatisation sur **Ouvert** avec l'action **Compter une ouverture** compte aussi tes ouvertures.",
    "Open Shortcuts": "Ouvrir Raccourcis",
    "Working. Last automatic count %@.": "Ça marche. Dernier pli compté automatiquement %@.",
    "Nothing yet. Once it's set up, close your Duo once: this line turns green.": "Rien pour l'instant. Une fois en place, ferme ton Duo une fois : cette ligne passe au vert.",
    "Check": "Vérification",
    "When Duo Folds is on screen as well, each fold is still counted only once. The widgets catch up within a few minutes, iOS decides when they refresh.":
        "Même quand Duo Folds est aussi à l'écran, chaque pli n'est compté qu'une fois. Les widgets suivent en quelques minutes : c'est iOS qui décide quand ils se mettent à jour.",
    "Count even when the app is closed": "Compter même app fermée",
    "Set up the Shortcuts automation in one minute.": "Mets en place l'automatisation Raccourcis en une minute.",
    "Off: counts only while the app is on screen": "Désactivé : ne compte que quand l'app est à l'écran",
    "On, with Shortcuts": "Activé, avec Raccourcis",
    "Without the automation, Duo Folds counts only while it's on screen, on the inner or the outer display.":
        "Sans l'automatisation, Duo Folds ne compte que quand il est à l'écran, intérieur ou extérieur.",
    "Adds one fold to today's count. Use it in a Shortcuts automation that runs when your Duo is closed.": "Ajoute un pli au compte du jour. À utiliser dans une automatisation Raccourcis qui se lance quand ton Duo se ferme.",
    "Adds one opening to today's count. Use it in a Shortcuts automation that runs when your Duo is opened.": "Ajoute une ouverture au compte du jour. À utiliser dans une automatisation Raccourcis qui se lance quand ton Duo s'ouvre.",
    "Count an opening": "Compter une ouverture",
    "On screen, Duo Folds reads the hinge itself. When it's not on screen, iOS doesn't tell it anything: the Shortcuts automation “When iPhone is Closed” with the action “Count a fold” takes over.":
        "À l'écran, Duo Folds lit lui-même la charnière. Quand il n'est pas à l'écran, iOS ne lui dit rien : l'automatisation Raccourcis « iPhone fermé » avec l'action « Compter un pli » prend le relais.",
    "Set up automatic counting": "Mettre en place le comptage automatique",
    # Temps ouvert
    "Time open": "Temps ouvert",
    "Open now": "Ouvert en ce moment",
    "yesterday": "hier",
    "per day, 7 days": "par jour, 7 jours",
    "Hours": "Heures",
    "%lld h": "%lld h",
    "Measured only while Duo Folds is on screen. Set up the two Shortcuts automations to measure all day.":
        "Mesuré seulement quand Duo Folds est à l'écran. Mets en place les deux automatisations Raccourcis pour mesurer toute la journée.",
    "Do it again with **Opened** and the action **Count an opening**: Duo Folds then also measures how long your Duo stays open.":
        "Refais-le avec **Ouvert** et l'action **Compter une ouverture** : Duo Folds mesure alors aussi combien de temps ton Duo reste ouvert.",
    "Open per day (30 days)": "Ouvert par jour (30 jours)",
    "Open in 30 days": "Ouvert en 30 jours",
    # Vidéo du guide Raccourcis
    "Video guide": "Vidéo explicative",
    "Open **Shortcuts** and tap **Automation**.": "Ouvre **Raccourcis** et touche **Automatisation**.",
    "Tap **+** to create an automation.": "Touche **+** pour créer une automatisation.",
    "Choose **iPhone Opened or Closed**.": "Choisis **iPhone ouvert ou fermé**.",
    "Keep **Closed** only, choose **Run Immediately**, then **Next**.": "Garde seulement **Fermé**, choisis **Exécuter immédiatement**, puis **Suivant**.",
    "Search **Duo Folds**, pick **Count a fold**, then turn off **Show When Run**.": "Cherche **Duo Folds**, choisis **Compter un pli**, puis désactive **Afficher lors de l'exécution**.",
    "Check that the automation is **on**. Done!": "Vérifie que l'automatisation est **activée**. C'est fini !",
    "Do the same with **Opened** and **Count an opening** to measure the time open.": "Refais pareil avec **Ouvert** et **Compter une ouverture** pour mesurer le temps ouvert.",
    "Tap the video to start again": "Touche la vidéo pour la relancer",
    "Animated guide: create the automation in Shortcuts.": "Guide animé : créer l'automatisation dans Raccourcis.",
    "Shortcuts": "Raccourcis",
    "Automation": "Automatisation",
    "Gallery": "Galerie",
    "New Automation": "Nouvelle automatisation",
    "Search": "Rechercher",
    "Time of Day": "Heure de la journée",
    "Alarm": "Alarme",
    "iPhone Opened or Closed": "iPhone ouvert ou fermé",
    "Wi-Fi": "Wi-Fi",
    "Battery Level": "Niveau de batterie",
    "When iPhone is": "Quand l'iPhone est",
    "Closed": "fermé",
    "Opened or Closed": "ouvert ou fermé",
    "Run After Confirmation": "Exécuter après confirmation",
    "Run Immediately": "Exécuter immédiatement",
    "Notify When Run": "Notifier lors de l'exécution",
    "Next": "Suivant",
    "Add Action": "Ajouter une action",
    "When iPhone is closed": "Quand l'iPhone est fermé",
    "When iPhone is opened": "Quand l'iPhone est ouvert",
    # Questions fréquentes (comptage automatique)
    "Tap the action, open it with the little arrow and turn **Show When Run** off: nothing will show up, it counts silently.":
        "Touche l'action, ouvre-la avec la petite flèche et désactive **Afficher lors de l'exécution** : plus rien ne s'affiche, ça compte en silence.",
    "Questions": "Questions",
    "Something shows up each time I open my Duo.": "Quelque chose s'affiche à chaque ouverture de mon Duo.",
    "In Shortcuts, open the automation, tap the action and turn **Show When Run** off. Also check that **Notify When Run** is off and **Run Immediately** is selected. Do it for both automations.":
        "Dans Raccourcis, ouvre l'automatisation, touche l'action et désactive **Afficher lors de l'exécution**. Vérifie aussi que **Notifier lors de l'exécution** est désactivé et **Exécuter immédiatement** choisi. Fais-le pour les deux automatisations.",
    "Why keep only “Closed”?": "Pourquoi garder seulement « Fermé » ?",
    "With “Opened or Closed”, every opening would also count as a fold. Use two automations: **Closed** with Count a fold, **Opened** with Count an opening.":
        "Avec « Ouvert ou fermé », chaque ouverture compterait aussi comme un pli. Utilise deux automatisations : **Fermé** avec Compter un pli, **Ouvert** avec Compter une ouverture.",
    "Is a fold counted twice when the app is open?": "Un pli est-il compté deux fois quand l'app est ouverte ?",
    "No. When Duo Folds is on screen and the automation runs too, the fold is counted only once.":
        "Non. Quand Duo Folds est à l'écran et que l'automatisation tourne aussi, le pli n'est compté qu'une fois.",
    "The widget isn't up to date.": "Le widget n'est pas à jour.",
    "iOS decides when widgets refresh, usually within a few minutes. Opening Duo Folds updates them right away.":
        "C'est iOS qui décide quand les widgets se mettent à jour, en général en quelques minutes. Ouvrir Duo Folds les met à jour tout de suite.",
    "Does it open the app or drain the battery?": "Est-ce que ça ouvre l'app ou vide la batterie ?",
    "No. The action runs in the background in a fraction of a second, without opening Duo Folds, even after a restart.":
        "Non. L'action tourne en arrière-plan en une fraction de seconde, sans ouvrir Duo Folds, même après un redémarrage.",
    "It doesn't count anymore.": "Ça ne compte plus.",
    "Check in Shortcuts that both automations are still turned on. If “Working” above isn't recent, close your Duo once and come back here.":
        "Vérifie dans Raccourcis que les deux automatisations sont toujours activées. Si « Ça marche » plus haut n'est pas récent, ferme ton Duo une fois et reviens ici.",
    # Corriger le compteur
    "Adjust the count": "Corriger le compteur",
    "Type today's folds or your lifetime total": "Taper les plis du jour ou le total",
    "Type the number you want, or use − and +. The lifetime total follows the same change.":
        "Tape le nombre voulu, ou utilise − et +. Le total suit la même différence.",
    "Useful if you were counting before Duo Folds. It can't be lower than today's folds.":
        "Pratique si tu comptais déjà avant Duo Folds. Il ne peut pas être inférieur aux plis d'aujourd'hui.",
    "Save": "Enregistrer",
    # Nouvel écran (deux volets)
    "Average": "Moyenne",
    "Average %lld per day": "En moyenne %lld par jour",
    "Counting · %lld°": "Comptage · %lld°",
    "%lld°": "%lld°",
    "Fills in as you fold, hour by hour.": "Se remplit au fil de tes plis, heure par heure.",
    "First week": "Première semaine",
    "Hinge now": "Charnière",
    "More": "Plus d'options",
    "Most folds: %@, around %@": "Le plus de plis : %@, vers %@",
    "No hinge here: tap to count": "Pas de charnière ici : touche pour compter",
    "On the Lock Screen too: touch and hold, Customize, then add Duo Folds.":
        "Sur l'écran verrouillé aussi : maintiens le doigt, Personnaliser, puis ajoute Duo Folds.",
    "Open · counts below %lld°": "Ouvert · compte sous %lld°",
    "Right on your %lld/day average": "Pile dans ta moyenne de %lld par jour",
    "Same as the previous period": "Autant que la période d'avant",
    "Search for Duo Folds and pick a size.": "Cherche Duo Folds et choisis une taille.",
    "Tap Edit, then Add Widget.": "Touche Modifier, puis Ajouter un widget.",
    "Tap to count": "Touche pour compter",
    "Touch and hold an empty spot on your Home Screen.": "Maintiens le doigt sur un espace vide de l'écran d'accueil.",
    "Touch and hold to adjust the count": "Maintiens le doigt pour corriger le compteur",
    "When you fold": "Quand tu plies",
    "Widgets": "Widgets",
    "Your daily average shows up tomorrow": "Ta moyenne par jour s'affiche demain",
    "%lld below your %lld/day average": "%lld de moins que ta moyenne de %lld par jour",
    "%lld above your %lld/day average": "%lld de plus que ta moyenne de %lld par jour",
    "%@ less than the previous period": "%@ de moins que la période d'avant",
    "%@ more than the previous period": "%@ de plus que la période d'avant",
    "%lld per day": "%lld par jour",
    "%@ · %@": "%@ · %@",
    "folds · %@": "plis · %@",
    "Folded": "Plié",
    "Week": "Semaine",
    "Classic": "Classique",
    "Night": "Nuit",
    "Look": "Apparence",
    "Light or dark, like the Health app": "Clair ou sombre, comme l'app Santé",
    "Dark, big numbers, Today and Week tabs": "Sombre, grands chiffres, onglets Aujourd'hui et Semaine",
    "Choose your look": "Choisis ton apparence",
    "You can change it anytime in Settings.": "Tu pourras la changer à tout moment dans les Réglages.",
    "Continue": "Continuer",
    "Counts below %lld°": "Compte sous %lld°",
}

SHORTCUTS_FR = {
    "Count a fold in ${applicationName}": "Compter un pli dans ${applicationName}",
    "Add a fold in ${applicationName}": "Ajouter un pli dans ${applicationName}",
    "How many folds today in ${applicationName}": "Combien de plis aujourd'hui dans ${applicationName}",
    "My folds in ${applicationName}": "Mes plis dans ${applicationName}",
    "Count an opening in ${applicationName}": "Compter une ouverture dans ${applicationName}",
}


def esc(x):
    return x.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write(path, pairs, header):
    with open(path, "w") as f:
        f.write(f"/* {header} (écrit par clapet/tools/strings.py) */\n")
        for k, v in pairs:
            f.write(f'"{esc(k)}" = "{esc(v)}";\n')


write(os.path.join(ROOT, "Shared/en.lproj/Localizable.strings"), [(k, k) for k in FR], "Duo Folds")
write(os.path.join(ROOT, "Shared/fr.lproj/Localizable.strings"), list(FR.items()), "Duo Folds")
write(os.path.join(ROOT, "Clapet/en.lproj/AppShortcuts.strings"), [(k, k) for k in SHORTCUTS_FR], "Raccourcis")
write(os.path.join(ROOT, "Clapet/fr.lproj/AppShortcuts.strings"), list(SHORTCUTS_FR.items()), "Raccourcis")

# Vérification : chaque texte écrit dans le code a sa traduction.
pat = re.compile(r'(?:Text|String\(localized:|LocalizedStringResource|IntentDescription|dialog:|Label|Toggle|Button|shortTitle:|'
                 r'title: LocalizedStringResource =|\.value\()\s*\(?\s*"((?:[^"\\]|\\.)*)"')
missing = set()
for f in glob.glob(os.path.join(ROOT, "**/*.swift"), recursive=True):
    for m in pat.finditer(open(f).read()):
        k = m.group(1)
        if re.fullmatch(r'\\\((?:[^()]|\([^()]*\))*\)', k) or k.startswith("\\(today > yesterday"):
            continue
        cands = {re.sub(r'\\\((?:[^()]|\([^()]*\)|\((?:[^()]|\([^()]*\))*\))*\)', spec, k) for spec in ("%lld", "%@")}
        mixed = re.sub(r'\\\((?:[^()]|\([^()]*\)|\((?:[^()]|\([^()]*\))*\))*\)', "\x00", k)
        if "\x00" in mixed:
            parts = mixed.split("\x00")
            import itertools
            for combo in itertools.product(["%lld", "%@"], repeat=len(parts) - 1):
                cands.add("".join(p + (combo[i] if i < len(combo) else "") for i, p in enumerate(parts)))
        if not any(c in FR for c in cands):
            missing.add((os.path.relpath(f, ROOT), k))
for m in sorted(missing):
    print("MANQUE", m)
print(len(FR), "textes,", len(missing), "manquant(s)")
sys.exit(1 if missing else 0)
