import Foundation
import Observation

// MARK: - Langue de l'app
//
// Le français est la langue d'origine. Chaque texte visible passe par L("…") :
// dans une autre langue, on cherche sa traduction dans la table de cette langue (puis l'anglais), sinon on garde le français.
// Les morceaux interpolés « \(…) » deviennent {} dans la clé, et sont remis à leur place
// dans la traduction (dans l'ordre, ou via {0}, {1}… si l'anglais change l'ordre des mots).

@Observable
final class Lang {
    enum Choice: String, CaseIterable, Identifiable {
        case auto, fr, en, de, es, ja, ko
        case zhHans = "zh-Hans"
        var id: String { rawValue }

        /// Nom de la langue, écrit dans cette langue.
        var nativeName: String {
            switch self {
            case .auto: return "Automatique · Automatic"
            case .fr: return "Français"
            case .en: return "English"
            case .de: return "Deutsch"
            case .es: return "Español"
            case .ja: return "日本語"
            case .ko: return "한국어"
            case .zhHans: return "简体中文"
            }
        }
    }

    static let shared = Lang()

    var choice: Choice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "language") }
    }

    private init() {
        choice = Choice(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .auto
    }

    /// La langue réellement utilisée (jamais .auto).
    var current: Choice {
        if choice != .auto { return choice }
        for pref in Locale.preferredLanguages {
            let p = pref.lowercased()
            if p.hasPrefix("fr") { return .fr }
            if p.hasPrefix("en") { return .en }
            if p.hasPrefix("de") { return .de }
            if p.hasPrefix("es") { return .es }
            if p.hasPrefix("ja") { return .ja }
            if p.hasPrefix("ko") { return .ko }
            if p.hasPrefix("zh") { return .zhHans }
        }
        return .en
    }

    var isFrench: Bool { current == .fr }
    /// Vrai pour toutes les langues autres que le français (les listes de contenu partent de l'anglais).
    var isEnglish: Bool { current != .fr }
    /// Langue sans alphabet latin (pas de jeu « un mot qui commence par… »).
    var isCJK: Bool { [.ja, .ko, .zhHans].contains(current) }
    /// Virgule décimale.
    var decimalComma: Bool { [.fr, .de, .es].contains(current) }

    /// Noms des notes Do Ré Mi (sinon C D E).
    var usesSolfege: Bool { [.fr, .es].contains(current) }

    /// Texte de contenu écrit en anglais (mots à deviner, thèmes…), traduit dans la langue courante.
    static func content(_ english: String) -> String {
        switch shared.current {
        case .de: return GermanStrings.words[english] ?? english
        case .es: return SpanishStrings.words[english] ?? english
        case .ja: return JapaneseStrings.words[english] ?? english
        case .ko: return KoreanStrings.words[english] ?? english
        case .zhHans: return ChineseStrings.words[english] ?? english
        default: return english
        }
    }

    /// Code de langue pour la voix de synthèse.
    var speechLanguage: String {
        switch current {
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .es: return "es-ES"
        case .ja: return "ja-JP"
        case .ko: return "ko-KR"
        case .zhHans: return "zh-CN"
        default: return "en-US"
        }
    }

    /// Table de traduction de la langue courante (nil = français, la langue d'origine).
    var table: [String: String]? {
        switch current {
        case .fr: return nil
        case .de: return GermanStrings.table
        case .es: return SpanishStrings.table
        case .ja: return JapaneseStrings.table
        case .ko: return KoreanStrings.table
        case .zhHans: return ChineseStrings.table
        default: return EnglishStrings.table
        }
    }
}

struct LocalizedText: ExpressibleByStringInterpolation {
    let key: String
    let args: [String]

    init(stringLiteral value: String) {
        key = value
        args = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        args = stringInterpolation.args
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
        }

        mutating func appendLiteral(_ literal: String) {
            key += literal
        }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "{}"
            args.append("\(value)")
        }
    }
}

/// Texte traduit dans la langue de l'app.
func L(_ text: LocalizedText) -> String {
    let template: String
    let lang = Lang.shared
    if let table = lang.table, let t = table[text.key] ?? (lang.current == .en ? nil : EnglishStrings.table[text.key]) {
        template = t
    } else {
        template = text.key
    }
    guard !text.args.isEmpty else { return template }
    return fill(template, with: text.args)
}

/// Texte connu seulement à l'exécution (nom de plante…), traduit tel quel.
func L(key: String) -> String {
    guard let table = Lang.shared.table else { return key }
    return table[key] ?? EnglishStrings.table[key] ?? key
}

/// Remplace {} (dans l'ordre) et {0}, {1}… (par position) par les valeurs.
private func fill(_ template: String, with args: [String]) -> String {
    var result = ""
    var next = 0
    var i = template.startIndex
    while i < template.endIndex {
        let c = template[i]
        if c == "{" {
            var j = template.index(after: i)
            var digits = ""
            while j < template.endIndex, template[j].isNumber {
                digits.append(template[j])
                j = template.index(after: j)
            }
            if j < template.endIndex, template[j] == "}" {
                let index = digits.isEmpty ? next : (Int(digits) ?? next)
                if digits.isEmpty { next += 1 }
                result += index < args.count ? args[index] : ""
                i = template.index(after: j)
                continue
            }
        }
        result.append(c)
        i = template.index(after: i)
    }
    return result
}
