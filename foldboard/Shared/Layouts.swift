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
    /// Comme chez Apple, la touche dessinée est plus étroite que sa place (un petit vide entre ⇧ et W, et avant ⌫) :
    /// en largeurs de lettre, retirées à droite (positif) ou à gauche (négatif). La zone d'appui reste entière.
    var trim: Double = 0
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
    /// Cinq signes sur la largeur de sept lettres (la dernière rangée des chiffres, comme chez Apple).
    static func wide(_ s: String) -> [KeySpec] { s.map { KeySpec(kind: .char(String($0)), width: 1.4) } }

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
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5, trim: 0.35)] + chars("wxcvbn") + [c("’"), KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
                ]
            case .qwerty:
                return [
                    KeyRow(keys: chars("qwertyuiop")),
                    KeyRow(keys: chars("asdfghjkl"), inset: 0.5),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5, trim: 0.35)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
                ]
            case .qwertz:
                return [
                    KeyRow(keys: chars11("qwertzuiopü")),
                    KeyRow(keys: chars11("asdfghjklöä")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5, trim: 0.35)] + chars("yxcvbnm") + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
                ]
            case .swedish:
                return [
                    KeyRow(keys: chars11("qwertyuiopå")),
                    KeyRow(keys: chars11("asdfghjklöä")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5, trim: 0.35)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
                ]
            case .spanish:
                return [
                    KeyRow(keys: chars("qwertyuiop")),
                    KeyRow(keys: chars("asdfghjklñ")),
                    KeyRow(keys: [KeySpec(kind: .shift, width: 1.5, trim: 0.35)] + chars("zxcvbnm") + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
                ]
            }
        case .numbers:
            return [
                KeyRow(keys: chars("1234567890")),
                KeyRow(keys: [c("-"), c("/"), c(":"), c(";"), c("("), c(")"), c(money), c("&"), c("@"), c("\"")]),
                // Comme le clavier d'Apple : cinq signes larges entre « #+= » et l'effacement (le % et le + sont
                // sur la page des symboles), pour retrouver l'apostrophe et le point d'exclamation à la même place.
                KeyRow(keys: [KeySpec(kind: .page(.symbols), width: 1.5, trim: 0.35)] + wide(apostrophePunct) + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
            ]
        case .symbols:
            return [
                KeyRow(keys: [c("["), c("]"), c("{"), c("}"), c("#"), c("%"), c("^"), c("*"), c("+"), c("=")]),
                KeyRow(keys: [c("_"), c("\\"), c("|"), c("~"), c("<"), c(">"), c(otherMoney[0]), c(otherMoney[1]), c(otherMoney[2]), c("•")]),
                KeyRow(keys: [KeySpec(kind: .page(.numbers), width: 1.5, trim: 0.35)] + wide(apostrophePunct) + [KeySpec(kind: .backspace, width: 1.5, trim: -0.35)]),
            ]
        }
    }

    /// La dernière rangée des chiffres et des symboles (comme chez Apple : l'apostrophe typographique en français).
    static var apostrophePunct: String { ".,?!" + (currentLayoutIsFrench ? "’" : "'") }
    /// Réglé par le clavier quand la disposition change.
    static var currentLayoutIsFrench = false

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
        // Comme le clavier d'Apple : 123, 🌐, 😀, l'espace et retour (la virgule et le point sont sur la page 123).
        keys[0].width = 1.25
        if globe { keys.append(KeySpec(kind: .globe, width: 1.1)) }
        if emoji { keys.append(KeySpec(kind: .emoji, width: 1.1)) }
        keys.append(KeySpec(kind: .space, width: 10 - 1.25 - 1.75 - (globe ? 1.1 : 0) - (emoji ? 1.1 : 0)))
        keys.append(KeySpec(kind: .ret, width: 1.75))
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
