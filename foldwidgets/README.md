# Fold Widgets

Six thèmes pour l'iPhone Duo : une couverture pour l'écran extérieur, un intérieur qui se partage sur la charnière, des widgets, et une paire de fonds d'écran à enregistrer.

L'app est gratuite. Rien n'est envoyé : les réglages restent dans un groupe d'app sur l'iPhone, et les images ne quittent l'appareil que si on appuie soi-même sur Partager.

Le code d'une première version construite ailleurs n'était pas accessible depuis ce dépôt. Cette version reprend le même périmètre et le branche sur la signature déjà utilisée ici (Origamo, Foldly, Waffle, Foldboard, RetroFold, Unlocked).

## Les six thèmes

| Thème | Fermé (couverture) | Ouvert (intérieur) |
|---|---|---|
| Révélation | La première lettre | Le mot entier, coupé par le pli |
| Heure | Heure et minutes empilées | Heure d'un côté, minutes de l'autre |
| Citation | Le début de la phrase | La phrase en deux volets |
| Diptyque | Un motif | Le motif et son complément |
| Compte à rebours | Le nombre de jours | Le nombre et l'anneau |
| Humeur | Le mot et la couleur | Le mot d'un côté, un signe de l'autre |

On peut changer le mot, la citation (huit phrases d'origine, ou la sienne), la palette, la date et l'humeur. L'heure suit le téléphone.

## Fonds d'écran et carte

- Extérieur : **1398 × 2034** (l'écran de couverture, 466 × 678 pt à 3×)
- Intérieur : **1878 × 2670**, plié à l'horizontale au milieu (pose portrait, charnière au centre)
- Carte de partage : **1080 × 1920**, avec les deux images

« Enregistrer la paire » écrit les deux fonds dans Photos. « Partager » propose la carte et les deux fichiers. La paire enregistrée est toujours la couverture fermée et l'intérieur ouvert, pas la position intermédiaire du curseur.

## La charnière, et ce que le widget ne peut pas voir

Dans l'app, l'angle vient de `onHingeChange` et la zone à éviter de `reservedRegions(kind: .division)`, les deux en iOS 27.1, compilés seulement avec le drapeau `DUO_SDK` (Xcode 27.1). Sans ce drapeau, l'app compile quand même : un curseur remplace la charnière.

WidgetKit ne sait pas si le téléphone est plié. Le widget choisit son dessin d'après sa **famille** :

- petit, et les complications de l'écran verrouillé : la couverture
- moyen : deux volets côte à côte
- grand : le diptyque intérieur

L'angle n'est pas copié dans le groupe d'app. Chaque thème a son propre widget : on peut poser Heure en petit et Citation en grand.

## Identifiants

Alignés sur le préfixe `com.padelup` des autres apps de ce dépôt (l'équipe vient du secret `APPLE_TEAM_ID`, elle n'est pas écrite dans le projet) :

| | Identifiant |
|---|---|
| App | `com.padelup.foldwidgets` |
| Widget | `com.padelup.foldwidgets.widget` |
| Groupe d'app | `group.com.padelup.foldwidgets` |

Le secret `BUNDLE_ID` reste celui d'Origamo. Fold Widgets ne le lit pas et ne le remplace pas.

Ce dépôt ne passe pas par fastlane. Le workflow `.github/workflows/foldwidgets-testflight.yml` reprend la même chaîne que Waffle et Foldly : XcodeGen, `xcodebuild` sans certificat de développement, puis export signé avec la clé API App Store Connect déjà en place (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`). Aucun secret à créer.

## Lancer le build

Actions → **Fold Widgets - TestFlight**. Sur `main`, et sur les branches `cursor/**` quand `foldwidgets/` change, le Mac compile. Si les secrets sont là, il crée les identifiants manquants, archive, signe, et n'envoie sur TestFlight que si la fiche existe déjà (`FICHE ok` dans le journal).

## À faire à la main

L'API ne crée pas la fiche. Le reste, le workflow essaie de le faire ; s'il échoue, voici quoi cliquer.

1. **Ne pas créer de secret GitHub.** Les cinq secrets existent déjà. Ne pas changer `BUNDLE_ID`.
2. **Groupe d'app** (obligatoire pour signer ; l'API ne peut pas le créer ni l'assigner). developer.apple.com → Certificates, Identifiers & Profiles :
   - Identifiers → **+** → App Groups → `group.com.padelup.foldwidgets`.
   - App ID `com.padelup.foldwidgets` : activer **App Groups**, Configure, cocher ce groupe.
   - App ID `com.padelup.foldwidgets.widget` : la même chose.
   - Le workflow crée les deux App ID et coche la capacité. Sans le groupe assigné, il n'y a pas de profil : la compilation reste verte, l'envoi TestFlight non.
3. **App Store Connect → Apps → + → Nouvelle app** (l'étape que personne d'autre ne peut faire) :
   - Plateforme : iOS
   - Nom : `Fold Widgets`
   - Langue principale : Français
   - Bundle ID : `com.padelup.foldwidgets` (pas le widget)
   - SKU : `foldwidgets-001`
   - Accès : accès complet
4. Le widget n'a pas sa propre fiche. Pas d'achat intégré : rien à créer dans Achats intégrés, et l'accord Paid Apps n'est pas nécessaire pour cette version gratuite.
5. Relancer **Fold Widgets - TestFlight**. Quand le journal contient `FICHE ok`, le build part. Compter 15 à 30 minutes, puis TestFlight → testeurs internes. Le script crée le groupe « Fold Widgets interne » s'il n'existe pas.
6. Sur l'iPhone : installer TestFlight et accepter le build.
7. Avant une soumission App Store (pas pour un test interne) :
   - Confidentialité : **Aucune donnée collectée**.
   - Classification : 4+.
   - Chiffrement : déjà répondu dans Info.plist (pas de chiffrement exempté).
   - Captures : iPhone Duo (extérieur et intérieur) et le format 6,9 pouces si Apple le demande.
   - Notes pour la vérification : l'app dessine des fonds et des widgets. `onHingeChange` et `reservedRegions` animent l'aperçu sur iPhone Duo. Les widgets ne lisent pas la charnière ; leur dessin dépend de la taille choisie. Aucune donnée ne sort de l'appareil.
