# Plié : du projet Xcode à TestFlight, puis à l'App Store

Plié regroupe trois jeux pensés pour l'iPhone Duo :

- **RAYON** : on plie le téléphone pour orienter un miroir et envoyer un laser sur la cible. 45 niveaux en 3 mondes, tous vérifiés solubles.
- **LE COFFRE** : on ouvre la charnière lentement comme une molette, on sent le bon cran, on reste immobile pour valider. 30 coffres + un mode duel à deux.
- **1, 2, 3… SOLEIL !** : le téléphone fait l'arbitre. Il annonce « Un, deux, trois… soleil ! », repère qui bouge pendant le STOP avec la caméra et affiche la photo du tricheur. Sur iPhone Duo ouvert, le signal s'affiche sur l'écran extérieur, face aux joueurs.

Sur les autres iPhone, tout marche aussi : la charnière est remplacée par le doigt, et le signal de Soleil s'affiche sur l'écran principal.

Modèle économique : gratuit avec 15 niveaux de RAYON, 10 coffres et Soleil en entier. Un seul achat, le **Pass Plié** (4,99 €), débloque tout le reste, pour toujours.

---

## 0. Déployer sans Mac (le plus rapide)

Le dossier `.github/workflows/testflight.yml` fait tout le travail sur un Mac de GitHub, qui a Xcode 27.1 :
il compile l'app, la signe et l'envoie sur TestFlight. Tu n'as besoin que d'un navigateur.

1. **Compte Apple Developer** (99 €/an) : developer.apple.com/programs/enroll. L'inscription peut prendre de quelques heures à 2 jours : c'est l'étape la plus longue, fais-la en premier.
2. **Identifiant de l'app** : developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > **+** > App IDs > App. Description `Plie`, Bundle ID explicite `com.tonnom.plie`. Laisse les cases par défaut (« In-App Purchase » est déjà incluse).
3. **L'app dans App Store Connect** : voir l'étape 4 plus bas (Nouvelle app, choisis le Bundle ID créé juste avant, puis l'achat intégré).
4. **Clé API** : App Store Connect > Utilisateurs et accès > Intégrations > App Store Connect API > **+**. Nom `GitHub`, accès **Admin**. Télécharge le fichier `AuthKey_XXXX.p8` (une seule fois possible). Note le **Key ID** et l'**Issuer ID**.
5. **Ton Team ID** : developer.apple.com > Account > Membership details (10 caractères).
6. **Dépôt GitHub** : crée un dépôt privé, envoie-y le contenu de ce dossier, puis dans Settings > Secrets and variables > Actions, crée les 5 secrets : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (tout le contenu du .p8), `APPLE_TEAM_ID`, `BUNDLE_ID`.
7. Onglet **Actions** > **TestFlight** > **Run workflow**. Environ 10 minutes plus tard, la version part chez Apple, puis apparaît dans TestFlight 15 à 30 minutes après.
8. **Installer sur ton iPhone** : App Store Connect > ton app > TestFlight > Testeurs internes > ajoute-toi. Installe l'app **TestFlight** sur l'iPhone et accepte l'invitation.

Même sans les secrets, chaque envoi sur GitHub vérifie que l'app compile : on peut corriger les éventuelles erreurs pendant que ton compte Apple est validé.

## 1. Ce qu'il te faut (si tu as un Mac)

- Un Mac avec **Xcode 27.1 ou plus récent** (c'est la version qui contient les outils de l'iPhone Duo).
- Un compte **Apple Developer** (99 € par an) : developer.apple.com/programs
- Idéalement un **iPhone Duo sous iOS 27.1 ou plus** pour tester la charnière, la caméra et l'écran extérieur. Le simulateur ne peut pas tout tester (pas de caméra notamment).

## 2. Ouvrir et lancer le projet

1. Dézippe le dossier et double-clique sur `Plie.xcodeproj`.
2. Clique sur le projet **Plie** dans la colonne de gauche, puis sur la cible **Plie**, onglet **Signing & Capabilities** :
   - **Team** : choisis ton compte développeur.
   - **Bundle Identifier** : remplace `com.CHANGE-MOI.plie` par un identifiant à toi, par exemple `com.tonnom.plie`. Il doit être unique sur tout l'App Store.
   - Clique sur **+ Capability** et ajoute **In-App Purchase**.
3. Branche ton iPhone, choisis-le en haut de la fenêtre et appuie sur ▶︎.

### Si Xcode affiche une erreur sur `onHingeChange`, `sceneAccessory` ou `CameraCaptureAccessory`

Ton Xcode est trop ancien pour l'iPhone Duo. Deux solutions :
- installer Xcode 27.1 ou plus (recommandé, sinon pas de mode Duo) ;
- ou, pour compiler quand même : cible **Plie** > **Build Settings** > cherche **Active Compilation Conditions** > retire `DUO_SDK`. L'app marche alors partout, mais sans la charnière ni l'écran extérieur.

### Si d'autres erreurs de compilation apparaissent

Je n'ai pas pu compiler le projet de mon côté (il faut un Mac). Copie-colle le message d'erreur exact et le nom du fichier : je te donne la correction.

## 3. Tester les achats sans payer

Le projet contient `Plie.storekit`, une boutique de test avec le Pass à 4,99 €. Elle est déjà branchée sur le schéma de lancement. Si Xcode ne la trouve pas : menu **Product** > **Scheme** > **Edit Scheme…** > **Run** > onglet **Options** > **StoreKit Configuration** > choisis `Plie.storekit`.

Dans TestFlight, les achats passent par le « bac à sable » d'Apple : tes testeurs ne paient rien.

## 4. Préparer App Store Connect

Sur appstoreconnect.apple.com :

1. **Accords, taxes et banque** : signe l'accord **Paid Apps** et renseigne ton compte bancaire et tes infos fiscales. Sans ça, impossible de vendre le Pass.
2. **Inscris-toi au Small Business Program** (developer.apple.com/app-store/small-business-program) : Apple prend 15 % au lieu de 30 % tant que tu fais moins d'un million de dollars par an.
3. **Mes apps** > **+** > **Nouvelle app** :
   - Plateforme : iOS
   - Nom : `Plié – Jeux pour iPhone Duo` (si le nom est pris, essaie `Plié : jeux à plier`)
   - Langue principale : Français
   - Bundle ID : celui choisi à l'étape 2
   - SKU : `plie-001`
4. Dans l'app > **Achats intégrés** > **+** :
   - Type : **Non consommable**
   - Nom de référence : `Pass Plié`
   - ID du produit : `plie.pass.complet` (exactement celui-là, c'est celui du code)
   - Prix : 4,99 €
   - Nom affiché : `Pass Plié` ; description : `Tous les niveaux de RAYON et du COFFRE, et les prochains jeux.`
   - Ajoute une capture d'écran de l'écran du Pass (demandée pour la vérification).

## 5. Envoyer sur TestFlight

1. Dans Xcode, en haut, choisis **Any iOS Device (arm64)** comme destination.
2. Menu **Product** > **Archive**. À la fin, la fenêtre **Organizer** s'ouvre.
3. **Distribute App** > **App Store Connect** > **Upload**. Laisse les options par défaut.
4. Attends 15 à 30 minutes que la version soit traitée, puis va dans l'onglet **TestFlight** d'App Store Connect.
5. **Testeurs internes** (jusqu'à 100 personnes de ton équipe) : disponible tout de suite.
6. **Testeurs externes** (jusqu'à 10 000, avec un lien public) : il faut une rapide vérification d'Apple (souvent moins de 24 h). Renseigne une adresse de contact et une courte description du test.

La question sur le chiffrement est déjà réglée dans `Info.plist` (l'app n'utilise pas de chiffrement spécial).

## 6. Avant de publier sur l'App Store

- **Politique de confidentialité** : Apple exige une adresse web. Le texte prêt à coller est en bas de ce guide. Publie-le gratuitement sur une page Notion publique ou GitHub Pages.
- **Confidentialité de l'app** (questionnaire App Store Connect) : réponds **« Aucune donnée collectée »**. C'est vrai : tout reste sur le téléphone.
- **Classification par âge** : 4+.
- **Captures d'écran** : fais-en sur iPhone Duo. Apple affiche un badge « Optimisé pour iPhone Duo » aux apps qui envoient des captures Duo. Prépare aussi des captures iPhone 6,9 pouces.
- **Notes pour la vérification** (champ « App Review Information ») :
  > Plié est conçu pour l'iPhone Duo. RAYON et LE COFFRE se jouent en pliant l'appareil (onHingeChange). Sur les autres iPhone, ils se jouent au doigt. Dans « 1, 2, 3… Soleil ! », la caméra sert à détecter les mouvements des joueurs, et sur iPhone Duo ouvert le signal s'affiche sur l'écran extérieur via CameraCaptureAccessory, pendant la capture. Aucune image n'est enregistrée ni envoyée.
- **Demande de mise en avant** : App Store Connect > **Nominations**. Coche « optimisé pour iPhone Duo » et « prend en charge toutes les positions de l'appareil ». C'est gratuit et c'est ton meilleur levier.

## 7. Textes de la fiche App Store

**Sous-titre** (30 caractères max) :
`3 jeux qui se jouent en pliant`

**Mots-clés** :
`iphone duo,pliable,laser,coffre,soleil,jeu de société,énigme,réflexion,famille,soirée,charnière`

**Description** :

> Ton iPhone Duo se plie. Et si c'était la manette ?
>
> RAYON : plie le téléphone pour orienter le miroir et envoyer le laser pile sur la cible. 45 niveaux, des miroirs fixes, des murs, puis des miroirs jumeaux qui tournent en sens inverse.
>
> LE COFFRE : ouvre la charnière tout doucement, comme la molette d'un coffre-fort. Chaque cran se sent sous les doigts. Le bon fait « clonk ». Reste immobile une seconde, et le chiffre est à toi. Attention aux faux crans. En duel, chacun cache un code à l'autre.
>
> 1, 2, 3… SOLEIL ! : pose le téléphone au bout de la pièce. Il annonce la formule, se retourne, et repère le moindre mouvement avec la caméra. Le tricheur est pris en photo et renvoyé au départ. Sur iPhone Duo, le signal s'affiche sur l'écran extérieur, face aux joueurs.
>
> Fonctionne aussi sur tous les iPhone : la charnière est alors remplacée par le doigt.
>
> Gratuit pour commencer. Le Pass Plié débloque tous les niveaux en un seul achat, sans abonnement ni publicité.
>
> Rien n'est collecté : les images de la caméra ne quittent jamais ton téléphone.

## 8. Faire décoller l'app

Personne ne peut garantir qu'une app perce. Voici ce qui met le plus de chances de ton côté, par ordre d'importance :

1. **Sortir vite.** L'iPhone Duo est sorti le 23 octobre 2026 : les premiers acheteurs cherchent des apps qui montrent ce que leur téléphone sait faire, et il y en a encore très peu. Chaque semaine compte.
2. **La nomination « mise en avant »** (étape 6). Apple aime montrer les apps qui exploitent un nouvel appareil.
3. **Des vidéos courtes.** Soleil se filme tout seul : un groupe qui avance, le téléphone qui crie « Bougé ! », la photo du tricheur. Le duel du coffre aussi (gros plan sur les mains qui tremblent). Poste sur TikTok, Instagram et YouTube Shorts avec #iPhoneDuo.
4. **La presse tech française** : écris à iGeneration, iPhoneSoft, Frandroid, Journal du Geek, avec la vidéo et un code TestFlight. Les sites cherchent des sujets « premières apps pour iPhone Duo ».
5. **Les communautés** : r/iphone, r/iOSGaming, les forums MacGeneration. Montre, ne vends pas.

### Ordre de grandeur des revenus (à prendre avec prudence)

Pour 4,99 € payés par un client en France : environ 0,83 € de TVA, puis 15 % pour Apple. Il te reste **environ 3,50 € par Pass vendu**.

| Téléchargements | Taux d'achat du Pass | Pass vendus | Revenu net |
|---|---|---|---|
| 5 000 | 3 % | 150 | ~525 € |
| 20 000 | 4 % | 800 | ~2 800 € |
| 100 000 | 5 % | 5 000 | ~17 500 € |

Un jeu payant à achat unique fait souvent entre 2 et 5 % d'acheteurs. Le chiffre qui change tout, c'est le nombre de téléchargements, donc la visibilité.

### Les prochaines étapes qui rapportent

- **Un monde 4 pour RAYON** et 20 coffres de plus, inclus dans le Pass : ça donne une raison aux acheteurs de recommander l'app.
- **Traduction en anglais** : le marché américain est le plus gros pour l'iPhone Duo.
- **Un mode « défi du jour »** pour RAYON (un niveau aléatoire par jour, le même pour tout le monde), pour que les joueurs reviennent.

---

## Politique de confidentialité (à publier en ligne)

> **Politique de confidentialité de Plié**
>
> Plié ne collecte, ne stocke sur un serveur et ne partage aucune donnée personnelle.
>
> **Caméra.** Le jeu « 1, 2, 3… Soleil ! » utilise la caméra pour détecter les mouvements des joueurs. L'analyse se fait entièrement sur l'appareil. Les photos des joueurs pris en train de bouger restent dans l'app pendant la partie et sont effacées quand on la quitte. Elles ne sont partagées que si l'utilisateur appuie lui-même sur « Partager ».
>
> **Progression.** Les niveaux réussis et les réglages sont enregistrés uniquement sur l'appareil.
>
> **Achats.** Les achats sont gérés par Apple. Plié ne reçoit aucune information de paiement.
>
> **Contact.** [ton adresse e-mail]
>
> Dernière mise à jour : [date]

---

## Organisation du projet

```
Plie.xcodeproj         le projet Xcode
Plie.storekit          boutique de test (Pass à 4,99 €)
Plie/
  App/                 lancement de l'app, accueil, réglages, écran du Pass
  Core/                couleurs, sons, vibrations, charnière, écran extérieur, achats, progression
  Games/Rayon/         moteur du laser, 45 niveaux, écrans
  Games/Coffre/        règles du coffre, niveaux, molette, duel
  Games/Soleil/        détection de mouvement, déroulement de la partie, écrans
  Sounds/              11 effets sonores
  Assets.xcassets/     icône et couleur d'accent
  PrivacyInfo.xcprivacy  manifeste de confidentialité exigé par Apple
```

Les niveaux de RAYON ont été générés puis vérifiés un par un : pour chacun, il existe une position de la charnière qui envoie le laser sur la cible, et la position de départ ne la touche pas.
