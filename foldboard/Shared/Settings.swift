import CoreGraphics
import Foundation
import Security

// MARK: - Les réglages du clavier
//
// Partagés entre l'app et le clavier dans un groupe de trousseau commun (« ÉQUIPE.com.padelup.foldboard.shared »).
// Si le trousseau n'est pas joignable (accès complet coupé), chacun garde sa copie dans ses préférences.

enum KBLayout: String, Codable, CaseIterable, Identifiable {
    case azerty, qwerty, qwertz, spanish, swedish
    var id: String { rawValue }
    var title: String {
        switch self {
        case .azerty: return "AZERTY"
        case .qwerty: return "QWERTY"
        case .qwertz: return "QWERTZ (Deutsch)"
        case .spanish: return "QWERTY (Español)"
        case .swedish: return "QWERTY (Svenska)"
        }
    }

    /// La disposition habituelle pour la langue de l'iPhone.
    static var forLocale: KBLayout {
        switch Locale.current.language.languageCode?.identifier {
        case "fr": return .azerty
        case "de": return .qwertz
        case "es": return .spanish
        case "sv": return .swedish
        default: return .qwerty
        }
    }
}

/// Où se place le clavier.
enum KBMode: String, Codable, CaseIterable, Identifiable {
    /// Une main, et le clavier vient du côté de la main.
    case auto
    /// Une main, collé à gauche ou à droite.
    case left, right
    /// Toute la largeur.
    case full
    /// Deux mains : deux moitiés, une sur chaque bord.
    case split
    var id: String { rawValue }

    var isOneHand: Bool { self == .auto || self == .left || self == .right }
    var symbol: String {
        switch self {
        case .auto: return "hand.raised.fingers.spread"
        case .left: return "keyboard.onehanded.left"
        case .right: return "keyboard.onehanded.right"
        case .full: return "keyboard"
        case .split: return "rectangle.split.2x1"
        }
    }
}

enum KBFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    var id: String { rawValue }
}

enum KBSound: String, Codable, CaseIterable, Identifiable {
    case off, click, soft, pop, wood
    var id: String { rawValue }
}

/// Ce qui remplit l'espace libre à côté du clavier à une main.
enum KBSidePanel: String, Codable, CaseIterable, Identifiable {
    case emoji, phrases, none
    var id: String { rawValue }
}

struct KBSettings: Codable, Equatable {
    var layout: KBLayout = KBLayout.forLocale
    var mode: KBMode = .auto
    /// Côté retenu pour le mode automatique (true = droite).
    var autoRight = true
    /// Mode automatique : deux mains détectées (deux moitiés sur l'écran déplié, toute la largeur sur l'écran extérieur).
    var autoTwo = false
    /// Étalonnage de l'inclinaison : l'angle « droit » et le sens qui veut dire main droite.
    var tiltMid: Double = 0
    var tiltRightNegative = true
    var tiltCalibrated = false
    /// Inclinaisons notées quand on change le clavier de côté à la main (apprentissage).
    var tiltRightSamples: [Double] = []
    var tiltLeftSamples: [Double] = []
    /// Postures étalonnées dans l'app : [inclinaison, angle avec l'horizontale] pour chaque prise.
    var postureRight: [Double] = []
    var postureLeft: [Double] = []
    var postureTwo: [Double] = []
    /// Étalonnage par situation : « closed-portrait », « open-portrait », « open-landscape », « closed-landscape »
    /// → prise (« right », « left », « two ») → [inclinaison, angle avec l'horizontale].
    var calib: [String: [String: [Double]]] = [:]
    /// Inclinaisons apprises quand on change soi-même le clavier de côté, par situation → « right » / « left ».
    var learned: [String: [String: [Double]]] = [:]
    /// Étalonnage par la frappe : pour chaque situation et chaque prise, quelques appuis enregistrés
    /// (mouvement du téléphone sous le pouce, inclinaison, position et taille du toucher).
    var taps: [String: [String: [[Double]]]] = [:]
    /// Largeur du clavier (points) quand chaque situation a été étalonnée : le clavier, dans n'importe quelle app,
    /// retrouve sa situation à sa largeur (même écran, même sens), donc le bon étalonnage.
    var widths: [String: Double] = [:]
    /// La vraie largeur (côté court, en points) de chaque écran du Duo, apprise dans l'app grâce à la charnière :
    /// « closed » (écran extérieur) et « open » (écran intérieur). Les deux écrans ont la même forme.
    var screenWidths: [String: Double] = [:]
    /// « Apprends tes pouces » (dans l'app) : les appuis sur les lettres, par situation et par main, repris par le clavier
    /// (KBThumb) : [zone, décalage sur la touche, rayon du toucher, réaction du téléphone x, y, z]. Et la date de chaque étalonnage.
    var thumbSeed: [String: [String: [[Double]]]] = [:]
    var thumbSeedStamp: [String: Double] = [:]
    /// Glissements du pouce étalonnés, par situation et par main.
    var swipes: [String: [String: [[Double]]]] = [:]
    /// Largeur du clavier à une main, en part de l'écran.
    var oneHandWidth: Double = 0.76
    /// Largeur à une main sur l'écran intérieur du Duo (déplié) : plus compact, à portée du pouce.
    var oneHandWidthOpen: Double = 0.56
    /// Duo ouvert en portrait : clavier coupé en deux (sinon, petit clavier qui suit la main).
    var openSplit = false
    /// Duo ouvert en portrait : le clavier en grand (bouton dans la barre).
    var openFull = false
    /// Duo ouvert en paysage : clavier coupé en deux (sinon, entier).
    var openLandSplit = false
    /// Duo ouvert en paysage : le petit clavier qui suit la main (option ; sinon entier ou coupé en deux).
    var openLandFollow = false
    /// Largeur de chaque moitié en mode deux mains, en part de l'écran.
    var splitWidth: Double = 0.34
    /// Écart avec le bord de l'écran, en points.
    var edgeMargin: Double = 4
    /// Hauteur d'une touche, en points.
    var keyHeight: Double = 46
    /// Hauteur des touches sur l'écran déplié (0 : la même que plié).
    var keyHeightOpen: Double = 0
    /// Les boutons position, réglages et masquer dans la barre du haut (on peut les cacher).
    var barButtons = true
    /// Le bouton « masquer le clavier » dans la barre, à part (on peut cacher position et réglages et le garder).
    var hideKeyButton = true
    /// Garder automatiquement tout ce qu'on copie (iOS demande alors l'autorisation de coller, sauf si on a choisi
    /// « Autoriser » dans Réglages › Foldboard › Coller depuis d'autres apps). Coupé : lu seulement quand on le demande.
    var clipAutoSave = false
    /// Les noms des contacts dans les suggestions.
    var contactNames = true
    /// Un emoji proposé dans la barre pour certains mots (« triste » → 😢), comme le clavier d'Apple.
    var emojiSuggest = true
    /// Les petits messages « Foldboard connaît mieux ta prise en main » / « Noté » dans le clavier.
    var learningTips = true
    /// Une rangée de chiffres au-dessus des lettres (désactivée par défaut : le clavier garde sa hauteur).
    var numberRow = false
    /// La hauteur de la rangée de la barre d'espace, par rapport aux autres (0,8 à 1,5).
    var spaceRowScale: Double = 1
    /// Les touches se décalent vers là où tu tapes vraiment (KBTapMap).
    var tapLearn = true
    /// Le micro au-dessus des touches (dictée, voir KBDictation).
    var dictationKey = true
    /// Le micro aussi dans la rangée du bas, juste à côté de retour (comme le clavier de l'iPhone).
    var micByReturn = false
    /// Le micro à côté de retour ne part qu'en le tenant un instant (pas d'effleurement par erreur).
    var micHold = false
    /// Le bouton ✨ Corriger dans la barre (on peut le cacher).
    var wandButton = true
    /// Où vont les boutons de la barre du haut : « right » (à droite), « left » (à gauche), « split » (de part et
    /// d'autre, les suggestions au milieu).
    var barLayout = "right"
    /// Des touches aux coins carrés.
    var squareKeys = false
    /// La dictée traduite : ce qui est dit dans une langue de la paire s'écrit dans l'autre.
    var dictTranslate = false
    /// Les deux langues de la traduction (dictée et bouton 🌐).
    var translatePair: [String] = ["fr", "en"]
    /// Le bouton 🌐 Traduire dans la barre.
    var translateKey = true
    /// Pendant qu'on écrit, les boutons de la barre se rangent derrière « ⋯ » : les suggestions ont toute la place.
    var compactBar = true
    /// « Mes mots » : jamais corrigés (ajoutés dans l'app, ou quand tu annules une correction). Le plus récent en premier.
    var myWords: [String] = []
    /// La disposition choisie pour chaque écran (« closed-portrait », « open-portrait », « open-landscape »…).
    /// Absent : la disposition générale (`mode`). Choisir une disposition dans le clavier la règle pour cet écran seulement.
    var screenModes: [String: KBMode] = [:]
    /// Le moment où l'on a demandé d'oublier les mains : le clavier efface aussi ce qu'il a appris en mémoire.
    var gripResetAt: Double = 0

    /// La disposition voulue sur cet écran (avant les limites de la version gratuite).
    func mode(for context: String) -> KBMode { screenModes[context] ?? mode }

    static let myWordsMax = 500

    /// Ajoute un mot à « Mes mots » (sans doublon, en premier). Vrai s'il est nouveau.
    @discardableResult
    mutating func addMyWord(_ word: String) -> Bool {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, w.count <= 40, !w.contains(" "),
              !myWords.contains(where: { $0.lowercased() == w.lowercased() }) else { return false }
        myWords.insert(w, at: 0)
        if myWords.count > Self.myWordsMax { myWords.removeLast(myWords.count - Self.myWordsMax) }
        return true
    }
    var theme: String = "auto"
    var font: KBFont = .system
    /// Force des vibrations, de 0 (coupées) à 1.
    var haptics: Double = 0.5
    var sound: KBSound = .click
    /// Sensibilité du glissement sur la barre d'espace (curseur), de 0 à 1.
    var swipe: Double = 0.5
    var sidePanel: KBSidePanel = .emoji
    var emojis: [String] = KBSettings.defaultEmojis
    /// Les phrases toutes faites de la barre du haut : vides par défaut (on les ajoute dans l'app si on veut).
    var phrases: [String] = []
    var autoCaps = true
    var autocorrect = true
    /// Écrire en glissant le doigt de lettre en lettre (comme le clavier d'Apple).
    var glide = true
    var suggestions = true
    var doubleSpacePeriod = true
    /// La touche emoji de Foldboard (on peut la cacher et passer par le globe vers le clavier emoji d'Apple).
    var emojiKey = true
    /// Le globe dessiné comme un smiley : avec le clavier Emoji juste après Foldboard, il ouvre les emojis d'Apple.
    var globeAsEmoji = false
    /// Modifié le (pour garder la copie la plus récente entre l'app et le clavier).
    var stamp: Date = .distantPast

    static let defaultEmojis = ["😂", "❤️", "👍", "🙏", "😊", "😭", "🔥", "👀", "🎉", "😅", "🥰", "👌"]
    static var defaultPhrases: [String] {
        if Locale.current.language.languageCode?.identifier == "fr" {
            return ["J’arrive !", "Merci beaucoup", "D’accord 👍", "Je te rappelle", "Je suis en route", "Pas de souci", "Bonne journée", "À tout à l’heure"]
        }
        return ["On my way!", "Thanks a lot", "Sounds good 👍", "I’ll call you back", "Running late", "No problem", "Have a nice day", "See you soon"]
    }
    static let legacyPhrasesFR = ["J’arrive !", "Merci beaucoup", "D’accord 👍", "Je te rappelle", "Je suis en route", "Pas de souci", "Bonne journée", "À tout à l’heure"]
    static let legacyPhrasesEN = ["On my way!", "Thanks a lot", "Sounds good 👍", "I’ll call you back", "Running late", "No problem", "Have a nice day", "See you soon"]

    init() {}

    /// Chaque champ est facultatif : un ancien réglage se relit toujours.
    init(from decoder: Decoder) throws {
        let d = KBSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decodeIfPresent(KBLayout.self, forKey: .layout)) ?? d.layout
        mode = (try? c.decodeIfPresent(KBMode.self, forKey: .mode)) ?? d.mode
        autoRight = (try? c.decodeIfPresent(Bool.self, forKey: .autoRight)) ?? d.autoRight
        autoTwo = (try? c.decodeIfPresent(Bool.self, forKey: .autoTwo)) ?? d.autoTwo
        tiltMid = (try? c.decodeIfPresent(Double.self, forKey: .tiltMid)) ?? d.tiltMid
        tiltRightNegative = (try? c.decodeIfPresent(Bool.self, forKey: .tiltRightNegative)) ?? d.tiltRightNegative
        tiltCalibrated = (try? c.decodeIfPresent(Bool.self, forKey: .tiltCalibrated)) ?? d.tiltCalibrated
        tiltRightSamples = (try? c.decodeIfPresent([Double].self, forKey: .tiltRightSamples)) ?? []
        tiltLeftSamples = (try? c.decodeIfPresent([Double].self, forKey: .tiltLeftSamples)) ?? []
        postureRight = (try? c.decodeIfPresent([Double].self, forKey: .postureRight)) ?? []
        postureLeft = (try? c.decodeIfPresent([Double].self, forKey: .postureLeft)) ?? []
        postureTwo = (try? c.decodeIfPresent([Double].self, forKey: .postureTwo)) ?? []
        calib = (try? c.decodeIfPresent([String: [String: [Double]]].self, forKey: .calib)) ?? [:]
        learned = (try? c.decodeIfPresent([String: [String: [Double]]].self, forKey: .learned)) ?? [:]
        taps = (try? c.decodeIfPresent([String: [String: [[Double]]]].self, forKey: .taps)) ?? [:]
        widths = (try? c.decodeIfPresent([String: Double].self, forKey: .widths)) ?? [:]
        screenWidths = (try? c.decodeIfPresent([String: Double].self, forKey: .screenWidths)) ?? [:]
        swipes = (try? c.decodeIfPresent([String: [String: [[Double]]]].self, forKey: .swipes)) ?? [:]
        thumbSeed = (try? c.decodeIfPresent([String: [String: [[Double]]]].self, forKey: .thumbSeed)) ?? [:]
        thumbSeedStamp = (try? c.decodeIfPresent([String: Double].self, forKey: .thumbSeedStamp)) ?? [:]
        oneHandWidth = (try? c.decodeIfPresent(Double.self, forKey: .oneHandWidth)) ?? d.oneHandWidth
        oneHandWidthOpen = (try? c.decodeIfPresent(Double.self, forKey: .oneHandWidthOpen)) ?? d.oneHandWidthOpen
        openSplit = (try? c.decodeIfPresent(Bool.self, forKey: .openSplit)) ?? d.openSplit
        openFull = (try? c.decodeIfPresent(Bool.self, forKey: .openFull)) ?? d.openFull
        openLandSplit = (try? c.decodeIfPresent(Bool.self, forKey: .openLandSplit)) ?? d.openLandSplit
        openLandFollow = (try? c.decodeIfPresent(Bool.self, forKey: .openLandFollow)) ?? d.openLandFollow
        splitWidth = (try? c.decodeIfPresent(Double.self, forKey: .splitWidth)) ?? d.splitWidth
        edgeMargin = (try? c.decodeIfPresent(Double.self, forKey: .edgeMargin)) ?? d.edgeMargin
        keyHeight = (try? c.decodeIfPresent(Double.self, forKey: .keyHeight)) ?? d.keyHeight
        keyHeightOpen = (try? c.decodeIfPresent(Double.self, forKey: .keyHeightOpen)) ?? d.keyHeightOpen
        barButtons = (try? c.decodeIfPresent(Bool.self, forKey: .barButtons)) ?? d.barButtons
        hideKeyButton = (try? c.decodeIfPresent(Bool.self, forKey: .hideKeyButton)) ?? d.hideKeyButton
        clipAutoSave = (try? c.decodeIfPresent(Bool.self, forKey: .clipAutoSave)) ?? d.clipAutoSave
        contactNames = (try? c.decodeIfPresent(Bool.self, forKey: .contactNames)) ?? d.contactNames
        emojiSuggest = (try? c.decodeIfPresent(Bool.self, forKey: .emojiSuggest)) ?? d.emojiSuggest
        learningTips = (try? c.decodeIfPresent(Bool.self, forKey: .learningTips)) ?? d.learningTips
        numberRow = (try? c.decodeIfPresent(Bool.self, forKey: .numberRow)) ?? d.numberRow
        spaceRowScale = min(1.5, max(0.8, (try? c.decodeIfPresent(Double.self, forKey: .spaceRowScale)) ?? d.spaceRowScale))
        tapLearn = (try? c.decodeIfPresent(Bool.self, forKey: .tapLearn)) ?? d.tapLearn
        dictationKey = (try? c.decodeIfPresent(Bool.self, forKey: .dictationKey)) ?? d.dictationKey
        micByReturn = (try? c.decodeIfPresent(Bool.self, forKey: .micByReturn)) ?? d.micByReturn
        micHold = (try? c.decodeIfPresent(Bool.self, forKey: .micHold)) ?? d.micHold
        wandButton = (try? c.decodeIfPresent(Bool.self, forKey: .wandButton)) ?? d.wandButton
        barLayout = (try? c.decodeIfPresent(String.self, forKey: .barLayout)) ?? d.barLayout
        squareKeys = (try? c.decodeIfPresent(Bool.self, forKey: .squareKeys)) ?? d.squareKeys
        dictTranslate = (try? c.decodeIfPresent(Bool.self, forKey: .dictTranslate)) ?? d.dictTranslate
        translatePair = (try? c.decodeIfPresent([String].self, forKey: .translatePair)) ?? d.translatePair
        if translatePair.count != 2 { translatePair = d.translatePair }
        translateKey = (try? c.decodeIfPresent(Bool.self, forKey: .translateKey)) ?? d.translateKey
        compactBar = (try? c.decodeIfPresent(Bool.self, forKey: .compactBar)) ?? d.compactBar
        myWords = (try? c.decodeIfPresent([String].self, forKey: .myWords)) ?? d.myWords
        screenModes = (try? c.decodeIfPresent([String: KBMode].self, forKey: .screenModes)) ?? d.screenModes
        gripResetAt = (try? c.decodeIfPresent(Double.self, forKey: .gripResetAt)) ?? d.gripResetAt
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? d.theme
        font = (try? c.decodeIfPresent(KBFont.self, forKey: .font)) ?? d.font
        haptics = (try? c.decodeIfPresent(Double.self, forKey: .haptics)) ?? d.haptics
        sound = (try? c.decodeIfPresent(KBSound.self, forKey: .sound)) ?? d.sound
        swipe = (try? c.decodeIfPresent(Double.self, forKey: .swipe)) ?? d.swipe
        sidePanel = (try? c.decodeIfPresent(KBSidePanel.self, forKey: .sidePanel)) ?? d.sidePanel
        emojis = (try? c.decodeIfPresent([String].self, forKey: .emojis)) ?? d.emojis
        phrases = (try? c.decodeIfPresent([String].self, forKey: .phrases)) ?? d.phrases
        // Les anciennes phrases proposées d'office (jamais modifiées) : retirées, la barre reste aux suggestions.
        if phrases == KBSettings.defaultPhrases || phrases == KBSettings.legacyPhrasesEN || phrases == KBSettings.legacyPhrasesFR { phrases = [] }
        autoCaps = (try? c.decodeIfPresent(Bool.self, forKey: .autoCaps)) ?? d.autoCaps
        autocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .autocorrect)) ?? d.autocorrect
        glide = (try? c.decodeIfPresent(Bool.self, forKey: .glide)) ?? d.glide
        suggestions = (try? c.decodeIfPresent(Bool.self, forKey: .suggestions)) ?? d.suggestions
        doubleSpacePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? d.doubleSpacePeriod
        emojiKey = (try? c.decodeIfPresent(Bool.self, forKey: .emojiKey)) ?? d.emojiKey
        globeAsEmoji = (try? c.decodeIfPresent(Bool.self, forKey: .globeAsEmoji)) ?? d.globeAsEmoji
        stamp = (try? c.decodeIfPresent(Date.self, forKey: .stamp)) ?? d.stamp
        clamp()
    }

    mutating func clamp() {
        // L'ancienne largeur par défaut donnait des touches trop petites : on passe à la nouvelle.
        if abs(oneHandWidth - 0.68) < 0.001 { oneHandWidth = 0.76 }
        oneHandWidth = min(0.95, max(0.45, oneHandWidth))
        oneHandWidthOpen = min(0.9, max(0.4, oneHandWidthOpen))
        splitWidth = min(0.48, max(0.22, splitWidth))
        edgeMargin = min(400, max(0, edgeMargin))
        keyHeight = min(60, max(34, keyHeight))
        if keyHeightOpen != 0 { keyHeightOpen = min(60, max(34, keyHeightOpen)) }
        haptics = min(1, max(0, haptics))
        swipe = min(1, max(0, swipe))
        if emojis.isEmpty { emojis = Self.defaultEmojis }
    }

    /// Note l'inclinaison quand on choisit soi-même un côté, et règle le seuil entre les deux mains.
    mutating func learnTilt(_ angle: Double, right: Bool) {
        if right {
            tiltRightSamples.append(angle)
            if tiltRightSamples.count > 8 { tiltRightSamples.removeFirst() }
        } else {
            tiltLeftSamples.append(angle)
            if tiltLeftSamples.count > 8 { tiltLeftSamples.removeFirst() }
        }
        guard !tiltRightSamples.isEmpty, !tiltLeftSamples.isEmpty else { return }
        let r = tiltRightSamples.reduce(0, +) / Double(tiltRightSamples.count)
        let l = tiltLeftSamples.reduce(0, +) / Double(tiltLeftSamples.count)
        guard abs(r - l) >= 3 else { return }
        tiltMid = (r + l) / 2
        tiltRightNegative = r < l
        tiltCalibrated = true
    }

    /// La situation d'après la taille de l'écran : Duo ouvert (écran presque carré) ou fermé, en portrait ou en paysage.
    /// La forme de l'écran utilisé décide (l'intérieur du Duo est presque carré, l'extérieur est allongé) ;
    /// la charnière (`closed`) ne sert que si la taille est inconnue. L'app et le clavier suivent la même règle.
    static func context(screen: CGSize, closed: Bool? = nil, known: [String: Double] = [:], native: Double? = nil) -> String {
        let w = screen.width, h = screen.height
        let ratio = min(w, h) / max(1, max(w, h))
        let short = Double(min(w, h))
        let open: Bool
        if let closed, closed, short >= 600 {
            // La charnière dit « fermé » mais l'écran fait plus de 600 pt : c'est l'écran intérieur (la charnière
            // n'a pas encore suivi en passant d'un écran à l'autre ; le clavier se mettait alors en disposition
            // d'écran extérieur sur l'écran intérieur, clignotait et tapait d'autres lettres).
            open = true
        } else if let closed, !closed, ratio > 0.6, short >= 420, short <= 520 {
            // L'inverse : la taille est celle de l'écran extérieur.
            open = false
        } else if let closed {
            // Sinon, la charnière dit tout.
            open = !closed
        } else if short >= 600 {
            // Mesuré sur un vrai Duo (azooKey-Duo) : écran extérieur 466 × 678 pt, écran intérieur 669 × 951 pt.
            // Le petit côté ne dépend ni du sens ni de la largeur de la fenêtre : 600 pt les sépare.
            open = true
        } else if ratio > 0.6 && short >= 420 && short <= 520 {
            open = false
        } else if w <= 0 || h <= 0 || ratio <= 0.6 {
            // Écran allongé : un iPhone classique, ou le Duo fermé.
            open = false
        } else if let n = native, let o = known["openPx"], let c = known["closedPx"], abs(o - c) > 20 {
            // Les pixels de chaque écran (appris dans l'app) : ils diffèrent plus que les points.
            open = abs(n - o) < abs(n - c)
        } else if let n = native, let c = known["closedPx"], known["openPx"] == nil {
            // Un seul écran connu : l'autre écran du Duo, c'est celui qui n'a pas cette taille.
            open = abs(n - c) > 20
        } else if let n = native, let o = known["openPx"], known["closedPx"] == nil {
            open = abs(n - o) <= 20
        } else if let o = known["open"], let c = known["closed"], abs(o - c) > 8 {
            // Les deux écrans ont la même forme : la largeur apprise dans l'app les distingue.
            open = abs(short - o) < abs(short - c)
        } else if let c = known["closed"], known["open"] == nil {
            open = abs(short - c) > 8
        } else if let o = known["open"], known["closed"] == nil {
            open = abs(short - o) <= 8
        } else {
            // Impossible de distinguer les deux écrans sans la charnière : on reste sur le fonctionnement
            // de l'écran extérieur (le clavier vient du côté de la main), le plus utile.
            open = false
        }
        return (open ? "open" : "closed") + "-" + (w > h ? "landscape" : "portrait")
    }

    static let contexts = ["closed-portrait", "open-portrait", "open-landscape", "closed-landscape"]

    mutating func calibrate(_ grip: String, roll: Double, incline: Double, context: String) {
        var c = calib[context] ?? [:]
        c[grip] = [roll, incline]
        calib[context] = c
        var l = learned[context] ?? [:]
        l[grip] = nil
        learned[context] = l
        tiltCalibrated = true
    }

    /// Le choix fait à la main : on retient l'inclinaison pour cette situation.
    mutating func learn(roll: Double, right: Bool, context: String) {
        let key = right ? "right" : "left"
        var l = learned[context] ?? [:]
        var a = l[key] ?? []
        a.append(roll)
        if a.count > 8 { a.removeFirst() }
        l[key] = a
        learned[context] = l
    }

    /// Enregistre les appuis d'une prise (étalonnage par la frappe) et en tire la posture moyenne.
    mutating func setTaps(_ samples: [[Double]], grip: String, context: String) {
        let ok = samples.filter { $0.count == GripDetector.featureCount }
        guard !ok.isEmpty else { return }
        var c = taps[context] ?? [:]
        c[grip] = Array(ok.suffix(30))
        taps[context] = c
        // La posture moyenne (inclinaison, angle avec l'horizontale) sert à placer le clavier dès qu'il apparaît.
        let f = ok[0][GripDetector.rollIndex]
        let roll = kbWrap(f + ok.map { kbWrap($0[GripDetector.rollIndex] - f) }.reduce(0, +) / Double(ok.count))
        let inc = ok.map { $0[GripDetector.rollIndex + 1] }.reduce(0, +) / Double(ok.count)
        calibrate(grip, roll: roll, incline: inc, context: context)
    }

    /// L'inclinaison retenue pour une prise dans une situation : apprise, sinon étalonnée.
    func roll(_ grip: String, context: String) -> Double? {
        if let a = learned[context]?[grip], let f = a.first {
            return kbWrap(f + a.map { kbWrap($0 - f) }.reduce(0, +) / Double(a.count))
        }
        if let p = calib[context]?[grip], p.count == 2 { return p[0] }
        return nil
    }

    /// Oublie l'étalonnage et tout ce qui a été appris : on repart des réglages de départ.
    mutating func resetCalibration() {
        gripResetAt = Date().timeIntervalSince1970
        calib = [:]
        learned = [:]
        taps = [:]
        widths = [:]
        swipes = [:]
        tiltMid = 0
        tiltRightNegative = true
        tiltCalibrated = false
        tiltRightSamples = []
        tiltLeftSamples = []
        postureRight = []
        postureLeft = []
        postureTwo = []
    }

    /// Les réglages vraiment appliqués : sans Foldboard Pro (ni essai), on revient à l'essentiel.
    func effective(pro: Bool) -> KBSettings {
        // Comme le clavier d'Apple sur le Duo : quelques emojis dans la place libre à côté des touches
        // (et tous avec la touche 😀) ; les phrases sont dans la barre du haut.
        var s = self
        s.sidePanel = .emoji
        guard !pro else { return s }
        if s.mode == .split { s.mode = .full }
        if s.mode == .auto { s.mode = s.autoRight ? .right : .left }
        s.theme = "auto"
        s.font = .system
        if s.sound != .off { s.sound = .click }
        if s.haptics > 0 { s.haptics = 0.5 }
        s.swipe = 0.5
        s.emojis = Self.defaultEmojis
        s.phrases = []
        return s
    }
}

// MARK: - L'accès Pro (essai de 3 jours ou achat)

struct KBAccess: Codable, Equatable {
    /// Début de l'essai gratuit (achat gratuit « 3-day Trial »).
    var trialStart: Date?
    var purchased = false
    var stamp: Date = .distantPast
    /// Versions de test seulement : « fin d'essai simulée » depuis l'app (les vrais achats sont ignorés).
    var simulated: Bool? = nil

    static let trialDays: Double = 3

    var trialEnd: Date? { trialStart.map { $0.addingTimeInterval(Self.trialDays * 86400) } }

    func isPro(_ now: Date = Date()) -> Bool {
        if purchased { return true }
        if let end = trialEnd, now < end { return true }
        return false
    }

    /// L'essai a été lancé puis est fini (et rien n'a été acheté).
    func trialOver(_ now: Date = Date()) -> Bool {
        !purchased && trialEnd.map { now >= $0 } == true
    }
}

// MARK: - Ce que le clavier a appris (montré dans l'app)

struct KBLearn: Codable, Equatable {
    /// Nombre d'habitudes apprises par situation (« closed-portrait », « open-portrait »…).
    var total: [String: Int] = [:]
    var stamp: Date = .distantPast
    /// Les décisions du clavier : côté choisi seul et gardé (juste), ou corrigé juste après (raté).
    var hits: Int? = nil
    var misses: Int? = nil

    /// La part de bons choix, quand il y en a assez pour que ça veuille dire quelque chose.
    var accuracy: Double? {
        let h = hits ?? 0, m = misses ?? 0
        return h + m >= 5 ? Double(h) / Double(h + m) : nil
    }

    var all: Int { total.values.reduce(0, +) }
    var closed: Int { total.filter { $0.key.hasPrefix("closed") }.values.reduce(0, +) }
    var open: Int { total.filter { $0.key.hasPrefix("open") }.values.reduce(0, +) }
}

// MARK: - Le coffre

enum KBVault {
    private static let service = "com.padelup.foldboard"

    /// Groupe de trousseau commun à l'app et au clavier.
    private static var group: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "FoldboardKeychainGroup") as? String,
              !g.hasPrefix("."), !g.isEmpty, !g.hasPrefix("$") else { return nil }
        return g
    }

    private static func query(_ account: String, _ group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    private static func read(_ account: String) -> Data? {
        var groups: [String?] = [group]
        if group != nil { groups.append(nil) }
        for g in groups {
            var q = query(account, g)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data { return data }
        }
        return nil
    }

    private static func write(_ account: String, _ data: Data) {
        let q = query(account, group)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = q
            add.merge(attrs) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    // Réglages : la copie la plus récente gagne (trousseau partagé ou préférences locales).
    static func loadSettings() -> KBSettings {
        let shared = read("settings").flatMap { try? JSONDecoder().decode(KBSettings.self, from: $0) }
        let local = UserDefaults.standard.data(forKey: "foldboard.settings").flatMap { try? JSONDecoder().decode(KBSettings.self, from: $0) }
        switch (shared, local) {
        case let (s?, l?): return s.stamp >= l.stamp ? s : l
        case let (s?, nil): return s
        case let (nil, l?): return l
        default: return KBSettings()
        }
    }

    static func save(_ settings: KBSettings) {
        var s = settings
        s.stamp = Date()
        guard let data = try? JSONEncoder().encode(s) else { return }
        write("settings", data)
        UserDefaults.standard.set(data, forKey: "foldboard.settings")
    }

    static func loadAccess() -> KBAccess {
        let shared = read("access").flatMap { try? JSONDecoder().decode(KBAccess.self, from: $0) }
        let local = UserDefaults.standard.data(forKey: "foldboard.access").flatMap { try? JSONDecoder().decode(KBAccess.self, from: $0) }
        switch (shared, local) {
        case let (s?, l?): return s.stamp >= l.stamp ? s : l
        case let (s?, nil): return s
        case let (nil, l?): return l
        default: return KBAccess()
        }
    }

    static func loadLearn() -> KBLearn {
        let shared = read("learn").flatMap { try? JSONDecoder().decode(KBLearn.self, from: $0) }
        let local = UserDefaults.standard.data(forKey: "foldboard.learn").flatMap { try? JSONDecoder().decode(KBLearn.self, from: $0) }
        switch (shared, local) {
        case let (s?, l?): return s.stamp >= l.stamp ? s : l
        case let (s?, nil): return s
        case let (nil, l?): return l
        default: return KBLearn()
        }
    }

    static func save(_ learn: KBLearn) {
        var l = learn
        l.stamp = Date()
        guard let data = try? JSONEncoder().encode(l) else { return }
        write("learn", data)
        UserDefaults.standard.set(data, forKey: "foldboard.learn")
    }

    // Bilan de frappe : le plus récent gagne (comme les réglages).
    /// La dictée en cours (voir KBDictation) : écrite par l'app, lue par le clavier.
    static func loadDictation() -> KBDictation.State? {
        read("dictation").flatMap { try? JSONDecoder().decode(KBDictation.State.self, from: $0) }
    }

    static func saveDictation(_ s: KBDictation.State) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        write("dictation", d)
    }

    /// Où tu tapes (voir KBTapMap) : écrit par le clavier, lu et remis à zéro par l'app.
    static func loadTaps() -> KBTapMap? {
        read("taps").flatMap { try? JSONDecoder().decode(KBTapMap.self, from: $0) }
    }

    static func saveTaps(_ m: KBTapMap) {
        guard let d = try? JSONEncoder().encode(m) else { return }
        write("taps", d)
    }

    /// La dernière version publiée sur l'App Store, vue par l'app (le clavier, lui, ne va jamais sur internet).
    static func loadLatestVersion() -> String? {
        read("latest").flatMap { String(data: $0, encoding: .utf8) }
    }

    static func saveLatestVersion(_ v: String) {
        guard let d = v.data(using: .utf8) else { return }
        write("latest", d)
    }

    /// État du glisser neuronal, écrit par le clavier et lu par l'app.
    static func loadNeural() -> String? {
        read("neural").flatMap { String(data: $0, encoding: .utf8) }
    }

    static func saveNeural(_ s: String) {
        guard let d = s.data(using: .utf8) else { return }
        write("neural", d)
    }

    static func loadStats() -> KBStats {
        let shared = read("stats").flatMap { try? JSONDecoder().decode(KBStats.self, from: $0) }
        let local = UserDefaults.standard.data(forKey: "foldboard.stats").flatMap { try? JSONDecoder().decode(KBStats.self, from: $0) }
        switch (shared, local) {
        case let (s?, l?): return s.stamp >= l.stamp ? s : l
        case let (s?, nil): return s
        case let (nil, l?): return l
        default: return KBStats()
        }
    }

    static func save(_ stats: KBStats) {
        var s = stats
        s.stamp = Date()
        guard let data = try? JSONEncoder().encode(s) else { return }
        write("stats", data)
        UserDefaults.standard.set(data, forKey: "foldboard.stats")
    }

    static func save(_ access: KBAccess) {
        var a = access
        a.stamp = Date()
        guard let data = try? JSONEncoder().encode(a) else { return }
        write("access", data)
        UserDefaults.standard.set(data, forKey: "foldboard.access")
    }
}

/// Les numéros de version : celle qui tourne, et s'il en existe une plus récente sur l'App Store.
enum KBVersion {
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// La version plus récente publiée, s'il y en a une (l'app la note une fois par jour).
    static var updateAvailable: String? {
        guard let latest = KBVault.loadLatestVersion(), isNewer(latest, than: current) else { return nil }
        return latest
    }
}
