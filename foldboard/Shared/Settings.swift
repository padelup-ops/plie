import Foundation
import Security

// MARK: - Les réglages du clavier
//
// Partagés entre l'app et le clavier dans un groupe de trousseau commun (« ÉQUIPE.com.padelup.foldboard.shared »).
// Si le trousseau n'est pas joignable (accès complet coupé), chacun garde sa copie dans ses préférences.

enum KBLayout: String, Codable, CaseIterable, Identifiable {
    case azerty, qwerty
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
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
    var layout: KBLayout = Locale.current.language.languageCode?.identifier == "fr" ? .azerty : .qwerty
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
    /// Largeur du clavier à une main, en part de l'écran.
    var oneHandWidth: Double = 0.68
    /// Largeur de chaque moitié en mode deux mains, en part de l'écran.
    var splitWidth: Double = 0.34
    /// Écart avec le bord de l'écran, en points.
    var edgeMargin: Double = 4
    /// Hauteur d'une touche, en points.
    var keyHeight: Double = 46
    var theme: String = "auto"
    var font: KBFont = .system
    /// Force des vibrations, de 0 (coupées) à 1.
    var haptics: Double = 0.5
    var sound: KBSound = .click
    /// Sensibilité du glissement sur la barre d'espace (curseur), de 0 à 1.
    var swipe: Double = 0.5
    var sidePanel: KBSidePanel = .emoji
    var emojis: [String] = KBSettings.defaultEmojis
    var phrases: [String] = KBSettings.defaultPhrases
    var autoCaps = true
    var autocorrect = true
    var suggestions = true
    var doubleSpacePeriod = true
    /// Modifié le (pour garder la copie la plus récente entre l'app et le clavier).
    var stamp: Date = .distantPast

    static let defaultEmojis = ["😂", "❤️", "👍", "🙏", "😊", "😭", "🔥", "👀", "🎉", "😅", "🥰", "👌"]
    static var defaultPhrases: [String] {
        if Locale.current.language.languageCode?.identifier == "fr" {
            return ["J’arrive !", "Merci beaucoup", "D’accord 👍", "Je te rappelle", "Je suis en route", "Pas de souci", "Bonne journée", "À tout à l’heure"]
        }
        return ["On my way!", "Thanks a lot", "Sounds good 👍", "I’ll call you back", "Running late", "No problem", "Have a nice day", "See you soon"]
    }

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
        oneHandWidth = (try? c.decodeIfPresent(Double.self, forKey: .oneHandWidth)) ?? d.oneHandWidth
        splitWidth = (try? c.decodeIfPresent(Double.self, forKey: .splitWidth)) ?? d.splitWidth
        edgeMargin = (try? c.decodeIfPresent(Double.self, forKey: .edgeMargin)) ?? d.edgeMargin
        keyHeight = (try? c.decodeIfPresent(Double.self, forKey: .keyHeight)) ?? d.keyHeight
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? d.theme
        font = (try? c.decodeIfPresent(KBFont.self, forKey: .font)) ?? d.font
        haptics = (try? c.decodeIfPresent(Double.self, forKey: .haptics)) ?? d.haptics
        sound = (try? c.decodeIfPresent(KBSound.self, forKey: .sound)) ?? d.sound
        swipe = (try? c.decodeIfPresent(Double.self, forKey: .swipe)) ?? d.swipe
        sidePanel = (try? c.decodeIfPresent(KBSidePanel.self, forKey: .sidePanel)) ?? d.sidePanel
        emojis = (try? c.decodeIfPresent([String].self, forKey: .emojis)) ?? d.emojis
        phrases = (try? c.decodeIfPresent([String].self, forKey: .phrases)) ?? d.phrases
        autoCaps = (try? c.decodeIfPresent(Bool.self, forKey: .autoCaps)) ?? d.autoCaps
        autocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .autocorrect)) ?? d.autocorrect
        suggestions = (try? c.decodeIfPresent(Bool.self, forKey: .suggestions)) ?? d.suggestions
        doubleSpacePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? d.doubleSpacePeriod
        stamp = (try? c.decodeIfPresent(Date.self, forKey: .stamp)) ?? d.stamp
        clamp()
    }

    mutating func clamp() {
        oneHandWidth = min(0.95, max(0.45, oneHandWidth))
        splitWidth = min(0.48, max(0.22, splitWidth))
        edgeMargin = min(120, max(0, edgeMargin))
        keyHeight = min(60, max(34, keyHeight))
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

    /// Les réglages vraiment appliqués : sans Foldboard Pro (ni essai), on revient à l'essentiel.
    func effective(pro: Bool) -> KBSettings {
        guard !pro else { return self }
        var s = self
        if s.mode == .split { s.mode = .full }
        if s.mode == .auto { s.mode = s.autoRight ? .right : .left }
        s.theme = "auto"
        s.font = .system
        if s.sound != .off { s.sound = .click }
        if s.haptics > 0 { s.haptics = 0.5 }
        s.swipe = 0.5
        s.sidePanel = .emoji
        s.emojis = Self.defaultEmojis
        s.phrases = Self.defaultPhrases
        return s
    }
}

// MARK: - L'accès Pro (essai de 3 jours ou achat)

struct KBAccess: Codable, Equatable {
    /// Début de l'essai gratuit (achat gratuit « 3-day Trial »).
    var trialStart: Date?
    var purchased = false
    var stamp: Date = .distantPast

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

    static func save(_ access: KBAccess) {
        var a = access
        a.stamp = Date()
        guard let data = try? JSONEncoder().encode(a) else { return }
        write("access", data)
        UserDefaults.standard.set(data, forKey: "foldboard.access")
    }
}
