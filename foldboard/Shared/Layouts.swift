import Foundation

/// Ce que fait une touche.
enum KeyKind: Equatable {
    case char(String)
    case shift
    case backspace
    case space
    case ret
    /// Passe aux chiffres, aux symboles ou aux lettres.
    case page(KBPage)
    /// Clavier suivant (globe), seulement quand iOS le demande.
    case globe
    /// Ouvre les emojis (comme le clavier d'Apple).
    case emoji
}

enum KBPage: Equatable {
    case letters, numbers, symbols
}

struct KeySpec: Equatable {
    var kind: KeyKind
    /// Largeur relative (une lettre = 1).
    var width: Double = 1
}

/// Une rangée : ses touches et l'espace à laisser de chaque côté (en largeurs de lettre).
struct KeyRow: Equatable {
    var keys: [KeySpec]
    var inset: Double = 0
}

enum KBLayouts {
    static func c(_ s: String) -> KeySpec { KeySpec(kind: .char(s)) }
    static func chars(_ s: String) -> [KeySpec] { s.map { c(String($0)) } }
    /// Onze touches sur une rangée (allemand) : un peu plus étroites, la rangée garde la même largeur.
    static func chars11(_ s: String) -> [KeySpec] { s.map { KeySpec(kind: .char(String($0)), width: 10.0 / 11.0) } }

    /// Les rangées d'une page, avant la rangée du bas (qui dépend du mode).
    static func rows(_ page: KBPage, layout: KBLayout) -> [KeyRow] {
        switch page {
        case .letters:
            switch layout {
            case .azerty:
                return [
                    KeyRow(keys: chars("azertyuiop")),
                    KeyRow(keys: chars("qsdfghjklm")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5)] + chars("wxcvbn") + [c("’"), KeySpec(kind: .backspace, width: 1.5)]),
                ]
            case .qwerty:
                return [
                    KeyRow(keys: chars("qwertyuiop")),
                    KeyRow(keys: chars("asdfghjkl"), inset: 0.5),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5)]),
                ]
            case .qwertz:
                return [
                    KeyRow(keys: chars11("qwertzuiopü")),
                    KeyRow(keys: chars11("asdfghjklöä")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5)] + chars("yxcvbnm") + [KeySpec(kind: .backspace, width: 1.5)]),
                ]
            case .swedish:
                return [
                    KeyRow(keys: chars11("qwertyuiopå")),
                    KeyRow(keys: chars11("asdfghjklöä")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5)]),
                ]
            case .spanish:
                return [
                    KeyRow(keys: chars("qwertyuiop")),
                    KeyRow(keys: chars("asdfghjklñ")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5)]),
                ]
            }
        case .numbers:
            return [
                KeyRow(keys: chars("1234567890")),
                KeyRow(keys: [c("-"), c("/"), c(":"), c(";"), c("("), c(")"), c("€"), c("&"), c("@"), c("\"")]),
                KeyRow(keys: [KeySpec(kind: .page(.symbols), width: 1.5), c("."), c(","), c("?"), c("!"), c("'"), c("%"), c("+"), KeySpec(kind: .backspace, width: 1.5)]),
            ]
        case .symbols:
            return [
                KeyRow(keys: [c("["), c("]"), c("{"), c("}"), c("#"), c("%"), c("^"), c("*"), c("+"), c("=")]),
                KeyRow(keys: [c("_"), c("\\"), c("|"), c("~"), c("<"), c(">"), c("$"), c("£"), c("¥"), c("•")]),
                KeyRow(keys: [KeySpec(kind: .page(.numbers), width: 1.5), c("."), c(","), c("?"), c("!"), c("'"), c("«"), c("»"), KeySpec(kind: .backspace, width: 1.5)]),
            ]
        }
    }

    /// La rangée du bas.
    static func bottom(_ page: KBPage, globe: Bool, layout: KBLayout, compact: Bool = false, leftHand: Bool = false) -> KeyRow {
        var keys: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), width: 1.5)]
        if compact {
            // Petit clavier à une main : le globe et les emojis montent dans la barre du haut, l'espace est bien plus large.
            // Main gauche : le point passe de l'autre côté de l'espace (la frappe est en miroir de la main droite).
            let dot = KeySpec(kind: .char(layout == .azerty && page == .letters ? "," : "."), width: 1)
            if leftHand {
                keys.append(KeySpec(kind: .space, width: 5.5))
                keys.append(dot)
                keys.append(KeySpec(kind: .ret, width: 2))
                return KeyRow(keys: keys)
            }
            keys.append(dot)
            keys.append(KeySpec(kind: .space, width: 5.5))
            keys.append(KeySpec(kind: .ret, width: 2))
            return KeyRow(keys: keys)
        }
        if globe { keys.append(KeySpec(kind: .globe, width: 1.1)) }
        keys.append(KeySpec(kind: .emoji, width: 1.1))
        keys.append(KeySpec(kind: .char(layout == .azerty && page == .letters ? "," : "."), width: 1))
        keys.append(KeySpec(kind: .space, width: globe ? 3.3 : 4.4))
        keys.append(KeySpec(kind: .ret, width: 2))
        return KeyRow(keys: keys)
    }

    /// Les accents en appui long.
    static func accents(_ base: String, layout: KBLayout) -> [String] {
        let fr = layout == .azerty
        switch base.lowercased() {
        case "e": return fr ? ["é", "è", "ê", "ë", "€"] : ["é", "è", "ê", "ë", "ē"]
        case "a": return ["à", "â", "ä", "æ", "á", "ã"]
        case "c": return ["ç", "ć", "č"]
        case "u": return ["ù", "û", "ü", "ú"]
        case "i": return ["î", "ï", "í", "ì"]
        case "o": return ["ô", "ö", "œ", "ó", "ò", "õ", "ø"]
        case "y": return ["ÿ", "ý"]
        case "n": return ["ñ", "ń"]
        case "s": return ["ß", "ś", "š"]
        case "’", "'": return ["'", "’", "\"", "«", "»"]
        case ".": return ["’", ",", "?", "!", "…"]
        case ",": return [";", ":", "-"]
        case "-": return ["–", "—", "•"]
        case "€": return ["$", "£", "¥", "¢"]
        case "?": return ["¿"]
        case "!": return ["¡"]
        default: return []
        }
    }
}
