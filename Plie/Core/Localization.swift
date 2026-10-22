import Foundation
import Observation

// MARK: - Langue de l'app
//
// Le français est la langue d'origine. Chaque texte visible passe par L("…") :
// en anglais, on cherche sa traduction dans EnglishStrings.table, sinon on garde le français.
// Les morceaux interpolés « \(…) » deviennent {} dans la clé, et sont remis à leur place
// dans la traduction (dans l'ordre, ou via {0}, {1}… si l'anglais change l'ordre des mots).

@Observable
final class Lang {
    enum Choice: String, CaseIterable, Identifiable {
        case auto, fr, en
        var id: String { rawValue }
    }

    static let shared = Lang()

    var choice: Choice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "language") }
    }

    private init() {
        choice = Choice(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .auto
    }

    var isEnglish: Bool {
        switch choice {
        case .fr: return false
        case .en: return true
        case .auto:
            let first = Locale.preferredLanguages.first ?? "fr"
            return !first.hasPrefix("fr")
        }
    }

    /// Code de langue pour la voix de synthèse.
    var speechLanguage: String { isEnglish ? "en-US" : "fr-FR" }
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
    if Lang.shared.isEnglish, let english = EnglishStrings.table[text.key] {
        template = english
    } else {
        template = text.key
    }
    guard !text.args.isEmpty else { return template }
    return fill(template, with: text.args)
}

/// Texte connu seulement à l'exécution (nom de plante…), traduit tel quel.
func L(key: String) -> String {
    Lang.shared.isEnglish ? (EnglishStrings.table[key] ?? key) : key
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
