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

    /// Les rangées d'une page avec la rangée de chiffres en option : les chiffres au-dessus des lettres
    /// (et des symboles), et sur la page des chiffres, la première rangée de symboles pour garder la même hauteur.
    static func rows(_ page: KBPage, layout: KBLayout, numberRow: Bool) -> [KeyRow] {
        let base = rows(page, layout: layout)
        guard numberRow else { return base }
        switch page {
        case .letters, .symbols: return [KeyRow(keys: chars("1234567890"))] + base
        case .numbers: return [KeyRow(keys: [c("["), c("]"), c("{"), c("}"), c("#"), c("%"), c("^"), c("*"), c("+"), c("=")])] + base
        }
    }

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
                KeyRow(keys: [c("-"), c("/"), c(":"), c(";"), c("("), c(")"), c(money), c("&"), c("@"), c("\"")]),
                KeyRow(keys: [KeySpec(kind: .page(.symbols), width: 1.5), c("."), c(","), c("?"), c("!"), c("'"), c("%"), c("+"), KeySpec(kind: .backspace, width: 1.5)]),
            ]
        case .symbols:
            return [
                KeyRow(keys: [c("["), c("]"), c("{"), c("}"), c("#"), c("%"), c("^"), c("*"), c("+"), c("=")]),
                KeyRow(keys: [c("_"), c("\\"), c("|"), c("~"), c("<"), c(">"), c(otherMoney[0]), c(otherMoney[1]), c(otherMoney[2]), c("•")]),
                KeyRow(keys: [KeySpec(kind: .page(.numbers), width: 1.5), c("."), c(","), c("?"), c("!"), c("'"), c("«"), c("»"), KeySpec(kind: .backspace, width: 1.5)]),
            ]
        }
    }

    /// Le symbole monétaire de la région du téléphone ($ aux États-Unis, € en France, £ au Royaume-Uni…).
    static var money: String {
        let sym = Locale.current.currencySymbol ?? "$"
        if sym.count == 1 { return sym }
        // « US$ », « CA$ », « R$ », « CHF »… : on garde le signe seul s'il y en a un.
        if let last = sym.last, !last.isLetter { return String(last) }
        return "$"
    }
    /// Les trois autres monnaies de la page des symboles.
    static var otherMoney: [String] {
        Array(["$", "€", "£", "¥"].filter { $0 != money }.prefix(3))
    }

    /// La rangée du bas.
    static func bottom(_ page: KBPage, globe: Bool, layout: KBLayout, compact: Bool = false, leftHand: Bool = false, emoji: Bool = true) -> KeyRow {
        var keys: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), width: 1.5)]
        if compact {
            // Petit clavier à une main : le globe et les emojis montent dans la barre du haut, l'espace est bien plus large.
            // Le point du côté du pouce : à droite de l'espace pour la main droite (le bord gauche est loin du pouce),
            // à gauche pour la main gauche.
            let dot = KeySpec(kind: .char(layout == .azerty && page == .letters ? "," : "."), width: 1)
            if !leftHand {
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
        if emoji { keys.append(KeySpec(kind: .emoji, width: 1.1)) }
        keys.append(KeySpec(kind: .char(layout == .azerty && page == .letters ? "," : "."), width: 1))
        keys.append(KeySpec(kind: .space, width: 5.5 - (globe ? 1.1 : 0) - (emoji ? 1.1 : 0)))
        keys.append(KeySpec(kind: .ret, width: 2))
        return KeyRow(keys: keys)
    }

    /// Les accents en appui long, les plus utiles de la langue en premier (comme le clavier d'Apple).
    static func accents(_ base: String, layout: KBLayout) -> [String] {
        let fr = layout == .azerty, de = layout == .qwertz, es = layout == .spanish, sv = layout == .swedish
        switch base.lowercased() {
        case "e": return fr ? ["é", "è", "ê", "ë", "€"] : (es ? ["é", "è", "ë", "ê", "€"] : ["é", "è", "ê", "ë", "ē", "€"])
        case "a":
            if de { return ["ä", "à", "á", "â", "æ", "ã", "å"] }
            if es { return ["á", "à", "ä", "â", "ã", "ª"] }
            if sv { return ["å", "ä", "à", "á", "â", "æ"] }
            return ["à", "â", "ä", "æ", "á", "ã", "å"]
        case "c": return ["ç", "ć", "č"]
        case "u":
            if de { return ["ü", "ù", "ú", "û", "ū"] }
            if es { return ["ú", "ü", "ù", "û"] }
            return ["ù", "û", "ü", "ú", "ū"]
        case "i": return es ? ["í", "ï", "ì", "î"] : ["î", "ï", "í", "ì", "ī"]
        case "o":
            if de { return ["ö", "ò", "ó", "ô", "õ", "ø", "œ"] }
            if es { return ["ó", "ò", "ö", "ô", "õ", "º"] }
            if sv { return ["ö", "ø", "ò", "ó", "ô", "õ"] }
            return ["ô", "ö", "œ", "ó", "ò", "õ", "ø"]
        case "y": return ["ÿ", "ý"]
        case "n": return es ? ["ñ", "ń"] : ["ñ", "ń", "ň"]
        case "s": return de ? ["ß", "ś", "š"] : ["ß", "ś", "š", "ş"]
        case "z": return ["ž", "ź", "ż"]
        case "l": return ["ł"]
        case "g": return ["ğ"]
        case "r": return ["ř"]
        case "d": return ["ð"]
        case "’", "'": return ["'", "’", "\"", "«", "»", "„", "“"]
        case ".": return ["’", ",", "?", "!", "…"]
        case ",": return [";", ":", "-"]
        case "-": return ["–", "—", "•"]
        case "€", "$", "£", "¥", "₩", "₹", "₽", "₺", "₪", "₫", "₱", "₦", "₴", "฿":
            return (["€", "$", "£", "¥", "¢", "₩", "₹", "₽"].filter { $0 != base })
        case "?": return ["¿"]
        case "!": return ["¡"]
        case "0": return ["°"]
        case "\"": return ["“", "”", "„", "«", "»"]
        default: return []
        }
    }
}
