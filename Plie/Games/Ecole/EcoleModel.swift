import SwiftUI

extension Theme {
    static let ecole = Color(hex: 0xFFD84D)
}

// MARK: - Les classes et les questions
//
// Chaque leçon compte 10 questions, tirées selon la classe. La maîtresse lit la question à voix haute :
// les petits n'ont pas besoin de savoir lire.

enum EcoleClass: Int, CaseIterable, Identifiable {
    case petits, cp, ce1, ce2, cm

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .petits: return L("Petits")
        case .cp: return L("CP")
        case .ce1: return L("CE1")
        case .ce2: return L("CE2")
        case .cm: return L("CM1 · CM2")
        }
    }

    var age: String {
        switch self {
        case .petits: return L("4-5 ans")
        case .cp: return L("6 ans")
        case .ce1: return L("7 ans")
        case .ce2: return L("8 ans")
        case .cm: return L("9-10 ans")
        }
    }

    var topics: String {
        switch self {
        case .petits: return L("Compter, couleurs, formes")
        case .cp: return L("Additions, soustractions, lettres")
        case .ce1: return L("Calcul jusqu'à 100, plus grand ou plus petit")
        case .ce2: return L("Tables de 2 à 5, problèmes")
        case .cm: return L("Tables, divisions, culture générale")
        }
    }

    var color: Color {
        switch self {
        case .petits: return Color(hex: 0xFF8FC7)
        case .cp: return Color(hex: 0x8BDB4F)
        case .ce1: return Color(hex: 0x5CC8FF)
        case .ce2: return Color(hex: 0xFFB13D)
        case .cm: return Color(hex: 0xB28CFF)
        }
    }

    var symbol: String {
        switch self {
        case .petits: return "teddybear.fill"
        case .cp: return "plus.forwardslash.minus"
        case .ce1: return "number"
        case .ce2: return "multiply"
        case .cm: return "globe.europe.africa.fill"
        }
    }
}

struct EcoleChoice: Equatable {
    var label: String
    var color: Color?
    var symbol: String?
}

enum EcoleVisual: Equatable {
    case none
    /// Des objets à compter (emoji, nombre).
    case items(String, Int)
    /// Un grand dessin (emoji).
    case picture(String)
    /// Un calcul illustré par des points : a + b ou a − b.
    case dots(Int, Int, subtract: Bool)
}

struct EcoleQuestion: Equatable {
    var prompt: String
    var speech: String
    var visual: EcoleVisual = .none
    var choices: [EcoleChoice] = []
    var correct = 0
    /// Réponse à taper au clavier (sinon on choisit parmi `choices`).
    var keypadAnswer: Int?
    var explanation: String
}

enum EcoleGenerator {
    static func lesson(for c: EcoleClass) -> [EcoleQuestion] {
        var list: [EcoleQuestion] = []
        var lastKind = -1
        while list.count < 10 {
            let kinds = kindsFor(c)
            var k = kinds.randomElement() ?? 0
            if kinds.count > 1 && k == lastKind { k = kinds.randomElement() ?? k }
            lastKind = k
            let q = make(kind: k, for: c)
            if !list.contains(where: { $0.prompt == q.prompt && $0.visual == q.visual }) { list.append(q) }
        }
        return list
    }

    private static func kindsFor(_ c: EcoleClass) -> [Int] {
        switch c {
        case .petits: return [0, 0, 1, 2, 3]
        case .cp: return [4, 4, 5, 5, 6, 0]
        case .ce1: return [7, 7, 8, 8, 9, 10]
        case .ce2: return [11, 11, 11, 12, 7, 8]
        case .cm: return [13, 13, 14, 15, 15, 16]
        }
    }

    // MARK: Fabrique des questions

    private static func make(kind: Int, for c: EcoleClass) -> EcoleQuestion {
        switch kind {
        case 0: return counting(max: c == .petits ? 6 : 10)
        case 1: return colors()
        case 2: return shapes()
        case 3: return bigger(max: 9, picture: true)
        case 4: return addition(maxSum: 10, keypad: false)
        case 5: return subtraction(max: 10, keypad: false)
        case 6: return firstLetter()
        case 7: return addition(maxSum: 100, keypad: true)
        case 8: return subtraction(max: 100, keypad: true)
        case 9: return bigger(max: 100, picture: false)
        case 10: return double(max: 50)
        case 11: return table(from: 2, to: 5)
        case 12: return problem()
        case 13: return table(from: 6, to: 9)
        case 14: return division()
        case 15: return culture()
        default: return problem()
        }
    }

    /// Trois ou quatre réponses : la bonne et des voisines, mélangées.
    private static func numberChoices(_ answer: Int, spread: Int = 2, count: Int = 3, minValue: Int = 0) -> (choices: [EcoleChoice], correct: Int) {
        var values: Set<Int> = [answer]
        var guardCount = 0
        while values.count < count && guardCount < 50 {
            guardCount += 1
            let v = answer + Int.random(in: -spread...spread)
            if v >= minValue { values.insert(v) }
        }
        let ordered = values.shuffled()
        return (ordered.map { EcoleChoice(label: "\($0)") }, ordered.firstIndex(of: answer) ?? 0)
    }

    static let countables = ["🍎", "⭐️", "🐟", "🌸", "🚗", "🐞", "🍓", "🎈", "🐥", "⚽️"]

    private static func counting(max: Int) -> EcoleQuestion {
        let n = Int.random(in: 1...max)
        let item = countables.randomElement() ?? "🍎"
        let c = numberChoices(n, spread: 2, count: 3, minValue: 1)
        return EcoleQuestion(prompt: L("Combien y en a-t-il ?"), speech: L("Combien y en a-t-il ? Compte bien !"),
                             visual: .items(item, n), choices: c.choices, correct: c.correct,
                             explanation: L("Il y en a \(n)."))
    }

    private static func colors() -> EcoleQuestion {
        let items: [(String, String, Int)] = [
            ("🍌", L("la banane"), 0), ("🍓", L("la fraise"), 1), ("🥦", L("le brocoli"), 2),
            ("🍆", L("l'aubergine"), 3), ("🥕", L("la carotte"), 4), ("🐳", L("la baleine"), 5)
        ]
        let palette: [(String, UInt32)] = [(L("jaune"), 0xFFD43B), (L("rouge"), 0xF03E3E), (L("vert"), 0x37B24D),
                                           (L("violet"), 0x9C36B5), (L("orange"), 0xFD7E14), (L("bleu"), 0x1C7ED6)]
        let pick = items.randomElement() ?? items[0]
        var options = Set([pick.2])
        while options.count < 3 { options.insert(Int.random(in: 0..<palette.count)) }
        let ordered = options.shuffled()
        let choices = ordered.map { EcoleChoice(label: palette[$0].0, color: Color(hex: palette[$0].1)) }
        return EcoleQuestion(prompt: L("De quelle couleur est \(pick.1) ?"), speech: L("De quelle couleur est \(pick.1) ?"),
                             visual: .picture(pick.0), choices: choices, correct: ordered.firstIndex(of: pick.2) ?? 0,
                             explanation: L("\(pick.1) est \(palette[pick.2].0).").capitalizedFirst)
    }

    private static func shapes() -> EcoleQuestion {
        let shapes: [(String, String)] = [(L("le rond"), "circle.fill"), (L("le carré"), "square.fill"), (L("le triangle"), "triangle.fill"),
                                          (L("l'étoile"), "star.fill"), (L("le cœur"), "heart.fill")]
        let order = Array(0..<shapes.count).shuffled().prefix(3)
        let answer = order.randomElement() ?? 0
        let choices = order.map { EcoleChoice(label: "", symbol: shapes[$0].1) }
        return EcoleQuestion(prompt: L("Touche \(shapes[answer].0)"), speech: L("Touche \(shapes[answer].0)."),
                             choices: Array(choices), correct: Array(order).firstIndex(of: answer) ?? 0,
                             explanation: L("C'était \(shapes[answer].0).").capitalizedFirst)
    }

    private static func bigger(max: Int, picture: Bool) -> EcoleQuestion {
        var a = Int.random(in: 1...max)
        var b = Int.random(in: 1...max)
        while a == b { b = Int.random(in: 1...max) }
        if Bool.random() { swap(&a, &b) }
        let big = Swift.max(a, b)
        let askBig = Bool.random()
        let target = askBig ? big : Swift.min(a, b)
        let prompt = askBig ? L("Quel nombre est le plus grand ?") : L("Quel nombre est le plus petit ?")
        return EcoleQuestion(prompt: prompt, speech: prompt, choices: [EcoleChoice(label: "\(a)"), EcoleChoice(label: "\(b)")],
                             correct: a == target ? 0 : 1,
                             explanation: askBig ? L("\(big) est plus grand que \(Swift.min(a, b)).") : L("\(Swift.min(a, b)) est plus petit que \(big)."))
    }

    private static func addition(maxSum: Int, keypad: Bool) -> EcoleQuestion {
        let total = Int.random(in: (maxSum > 10 ? 20 : 2)...maxSum)
        let a = Int.random(in: (maxSum > 10 ? 5 : 1)...(total - 1))
        let b = total - a
        let prompt = "\(a) + \(b) = ?"
        let speech = L("Combien font \(a) plus \(b) ?")
        if keypad {
            return EcoleQuestion(prompt: prompt, speech: speech, keypadAnswer: total, explanation: L("\(a) + \(b) = \(total)"))
        }
        let c = numberChoices(total, spread: 2, count: 3, minValue: 0)
        return EcoleQuestion(prompt: prompt, speech: speech, visual: .dots(a, b, subtract: false), choices: c.choices, correct: c.correct,
                             explanation: L("\(a) + \(b) = \(total)"))
    }

    private static func subtraction(max: Int, keypad: Bool) -> EcoleQuestion {
        let a = Int.random(in: (max > 10 ? 20 : 3)...max)
        let b = Int.random(in: 1...(a - 1))
        let r = a - b
        let prompt = "\(a) − \(b) = ?"
        let speech = L("Combien font \(a) moins \(b) ?")
        if keypad {
            return EcoleQuestion(prompt: prompt, speech: speech, keypadAnswer: r, explanation: L("\(a) − \(b) = \(r)"))
        }
        let c = numberChoices(r, spread: 2, count: 3, minValue: 0)
        return EcoleQuestion(prompt: prompt, speech: speech, visual: .dots(a, b, subtract: true), choices: c.choices, correct: c.correct,
                             explanation: L("\(a) − \(b) = \(r)"))
    }

    private static func double(max: Int) -> EcoleQuestion {
        let n = Int.random(in: 2...max)
        return EcoleQuestion(prompt: L("Le double de \(n) ?"), speech: L("Quel est le double de \(n) ?"), keypadAnswer: n * 2,
                             explanation: L("Le double de \(n), c'est \(n) + \(n) = \(n * 2)."))
    }

    private static func table(from: Int, to: Int) -> EcoleQuestion {
        let a = Int.random(in: from...to)
        let b = Int.random(in: 2...10)
        return EcoleQuestion(prompt: "\(a) × \(b) = ?", speech: L("Combien font \(a) fois \(b) ?"), keypadAnswer: a * b,
                             explanation: L("\(a) × \(b) = \(a * b)"))
    }

    private static func division() -> EcoleQuestion {
        let b = Int.random(in: 2...9)
        let q = Int.random(in: 2...10)
        return EcoleQuestion(prompt: "\(b * q) ÷ \(b) = ?", speech: L("Combien font \(b * q) divisé par \(b) ?"), keypadAnswer: q,
                             explanation: L("\(b) × \(q) = \(b * q), donc \(b * q) ÷ \(b) = \(q)."))
    }

    private static func problem() -> EcoleQuestion {
        let a = Int.random(in: 3...9)
        let b = Int.random(in: 2...6)
        switch Int.random(in: 0..<3) {
        case 0:
            return EcoleQuestion(prompt: L("Léa a \(a) billes. Elle en gagne \(b). Combien en a-t-elle ?"),
                                 speech: L("Léa a \(a) billes. Elle en gagne \(b). Combien en a-t-elle maintenant ?"),
                                 visual: .picture("🔮"), keypadAnswer: a + b, explanation: L("\(a) + \(b) = \(a + b) billes."))
        case 1:
            return EcoleQuestion(prompt: L("\(b) paquets de \(a) bonbons. Combien de bonbons ?"),
                                 speech: L("Il y a \(b) paquets de \(a) bonbons. Combien de bonbons en tout ?"),
                                 visual: .picture("🍬"), keypadAnswer: a * b, explanation: L("\(b) × \(a) = \(a * b) bonbons."))
        default:
            let total = a + b + 4
            return EcoleQuestion(prompt: L("Tom a \(total) cartes. Il en donne \(b). Combien lui en reste-t-il ?"),
                                 speech: L("Tom a \(total) cartes. Il en donne \(b). Combien lui en reste-t-il ?"),
                                 visual: .picture("🃏"), keypadAnswer: total - b, explanation: L("\(total) − \(b) = \(total - b) cartes."))
        }
    }

    /// Mots illustrés pour la première lettre (le mot dépend de la langue).
    private static func firstLetter() -> EcoleQuestion {
        let words: [(String, String)] = [("🍎", L("POMME")), ("🐱", L("CHAT")), ("🌙", L("LUNE")), ("🐟", L("POISSON")),
                                         ("🦁", L("LION")), ("🚗", L("VOITURE")), ("🎈", L("BALLON")), ("🐭", L("SOURIS")),
                                         ("🌞", L("SOLEIL")), ("🍰", L("GÂTEAU"))]
        let pick = words.randomElement() ?? words[0]
        let first = String(pick.1.folding(options: .diacriticInsensitive, locale: nil).prefix(1))
        var letters: Set<String> = [first]
        let alphabet = "ABCDEFGHIJKLMNOPRSTV".map(String.init)
        while letters.count < 3 { letters.insert(alphabet.randomElement() ?? "A") }
        let ordered = letters.shuffled()
        return EcoleQuestion(prompt: L("Par quelle lettre commence ce mot ?"), speech: L("Par quelle lettre commence le mot \(pick.1.lowercased()) ?"),
                             visual: .picture(pick.0), choices: ordered.map { EcoleChoice(label: $0) },
                             correct: ordered.firstIndex(of: first) ?? 0,
                             explanation: L("\(pick.1) commence par \(first)."))
    }

    private static func culture() -> EcoleQuestion {
        let bank: [(String, String, [String], Int)] = [
            ("🇫🇷", L("Quelle est la capitale de la France ?"), [L("Paris"), L("Lyon"), L("Marseille")], 0),
            ("🇮🇹", L("Quelle est la capitale de l'Italie ?"), [L("Milan"), L("Rome"), L("Venise")], 1),
            ("🇪🇸", L("Quelle est la capitale de l'Espagne ?"), [L("Barcelone"), L("Séville"), L("Madrid")], 2),
            ("🇯🇵", L("Quelle est la capitale du Japon ?"), [L("Tokyo"), L("Pékin"), L("Séoul")], 0),
            ("🪐", L("Quelle est la plus grande planète ?"), [L("Mars"), L("Jupiter"), L("Vénus")], 1),
            ("🔴", L("Quelle planète appelle-t-on la planète rouge ?"), [L("Mars"), L("Saturne"), L("Mercure")], 0),
            ("🕷️", L("Combien de pattes a une araignée ?"), ["6", "8", "10"], 1),
            ("🐝", L("Combien de pattes a un insecte ?"), ["4", "6", "8"], 1),
            ("🗓️", L("Combien y a-t-il de jours dans une semaine ?"), ["5", "7", "10"], 1),
            ("⏰", L("Combien y a-t-il de minutes dans une heure ?"), ["60", "100", "30"], 0),
            ("🐋", L("Quel est le plus grand animal du monde ?"), [L("L'éléphant"), L("La baleine bleue"), L("La girafe")], 1),
            ("🧊", L("À quelle température l'eau gèle-t-elle ?"), ["0 °C", "10 °C", "100 °C"], 0),
            ("🌍", L("Combien y a-t-il de continents ?"), ["3", "5", "7"], 2),
            ("🦖", L("Les dinosaures ont-ils vécu avec les humains ?"), [L("Oui"), L("Non")], 1),
            ("🌈", L("Combien de couleurs dans un arc-en-ciel ?"), ["5", "7", "9"], 1)
        ]
        let pick = bank.randomElement() ?? bank[0]
        let order = Array(pick.2.indices).shuffled()
        let choices = order.map { EcoleChoice(label: pick.2[$0]) }
        return EcoleQuestion(prompt: pick.1, speech: pick.1, visual: .picture(pick.0), choices: choices,
                             correct: order.firstIndex(of: pick.3) ?? 0,
                             explanation: L("La réponse : \(pick.2[pick.3])."))
    }
}

extension String {
    /// Première lettre en majuscule (« la banane est jaune » → « La banane est jaune »).
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
