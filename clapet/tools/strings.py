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
    "Plus": "Plus",
    "Settings": "Réglages",
    "CLAP!": "CLAP !",
    "folds": "plis",
    "Today": "Aujourd'hui",
    "Limit %lld": "Limite %lld",
    "Yesterday %lld": "Hier %lld",
    "%lld left today": "Encore %lld aujourd'hui",
    "Limit reached": "Limite atteinte",
    "%lld over the limit": "%lld au-dessus de la limite",
    "Closed today": "Fermé aujourd'hui",
    "Opened today": "Ouvert aujourd'hui",
    "Last 7 days": "7 derniers jours",
    "All time": "Au total",
    "Limit alerts": "Alertes de limite",
    "A notification at 80 % and 100 % of your limit": "Une notification à 80 % et à 100 % de ta limite",
    "History": "Historique",
    "30 days, 12 months, records": "30 jours, 12 mois, records",
    "On": "Activées",
    "This week": "Cette semaine",
    "Today by hour": "Aujourd'hui, heure par heure",
    "Peak %@": "Pic à %@",
    "Level %lld": "Niveau %lld",
    "%lld to level %lld": "encore %1$lld pour le niveau %2$lld",
    "Duo Folds counts while it's on screen. Keep it open, then close and open your Duo: clap!":
        "Duo Folds compte tant qu'il est à l'écran. Garde-le ouvert, puis ferme et ouvre ton Duo : clap !",
    "No hinge here: tap the mascot to count.": "Pas de charnière ici : touche la mascotte pour compter.",
    "Add the widget: touch and hold your Home Screen or Lock Screen, tap Edit, then add Duo Folds.":
        "Ajoute le widget : reste appuyé sur l'écran d'accueil ou l'écran verrouillé, touche Modifier, puis ajoute Duo Folds.",
    "In the Shortcuts app, the “Count a fold” action adds one fold, even when Duo Folds is closed.":
        "Dans l'app Raccourcis, l'action « Compter un pli » ajoute un pli, même quand Duo Folds est fermé.",
    "This widget is part of Duo Folds+.": "Ce widget fait partie de Duo Folds+.",
    "Three days of tracking! Keep an eye on your folds right from your Home Screen.":
        "Trois jours de suivi ! Garde un œil sur tes plis directement depuis ton écran d'accueil.",
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
    "One-time purchase, linked to your Apple Account. Counting, the daily limit, the week, the levels and the small widget stay free.":
        "Achat unique, lié à ton compte Apple. Le comptage, la limite du jour, la semaine, les niveaux et le petit widget restent gratuits.",
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
    # Couleurs et niveaux
    "Mint": "Menthe", "Orange": "Orange", "Pink": "Rose", "Blue": "Bleu", "Lemon": "Citron",
    "Fresh hinge": "Charnière neuve", "Smooth hinge": "Charnière souple", "Speedy hinge": "Charnière express",
    "Fold master": "Maître du pli", "Hinge hero": "Héros de la charnière", "Fold legend": "Légende du pli",
    "Unbreakable": "Incassable", "Hinge god": "Dieu de la charnière",
}

SHORTCUTS_FR = {
    "Count a fold in ${applicationName}": "Compter un pli dans ${applicationName}",
    "Add a fold in ${applicationName}": "Ajouter un pli dans ${applicationName}",
    "How many folds today in ${applicationName}": "Combien de plis aujourd'hui dans ${applicationName}",
    "My folds in ${applicationName}": "Mes plis dans ${applicationName}",
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
