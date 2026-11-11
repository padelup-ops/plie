import UIKit

/// Correction automatique et suggestions de mots, avec le correcteur d'iOS (UITextChecker)
/// et le lexique de l'utilisateur (contacts, remplacements de texte).
final class KBSuggest {
    private let checker = UITextChecker()
    private var known = Set<String>()
    private var replacements: [String: String] = [:]
    var language = "en_US"

    /// Les 30 000 mots les plus courants (du plus fréquent au moins fréquent), pour compléter et classer.
    /// Liste : FrequencyWords (Hermit Dave), contenu sous licence CC BY-SA 4.0.
    private var words: [String] = []
    private var folded: [String] = []
    private var rank: [String: Int] = [:]
    /// Les mots par leurs deux premières lettres : compléter sans parcourir les 30 000 mots à chaque lettre.
    private var byPrefix: [String: [Int]] = [:]
    private var byFirst: [String: [Int]] = [:]
    private var loadedList = ""

    private func loadList(_ code: String) {
        guard loadedList != code else { return }
        loadedList = code
        words = []; folded = []; rank = [:]; byPrefix = [:]; byFirst = [:]
        guard let url = Bundle.main.url(forResource: "words-" + code, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        words = text.split(separator: "\n").map(String.init)
        folded = words.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        for (i, w) in words.enumerated() where rank[w] == nil { rank[w] = i }
        for (i, f) in folded.enumerated() {
            byPrefix[String(f.prefix(2)), default: []].append(i)
            byFirst[String(f.prefix(1)), default: []].append(i)
        }
    }

    /// Les mots courants qui commencent comme `word` (sans tenir compte des accents), du plus fréquent au moins fréquent.
    private func listCompletions(_ word: String, limit: Int) -> [String] {
        let key = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard key.count >= 1 else { return [] }
        var out: [String] = []
        let candidates = (key.count >= 2 ? byPrefix[String(key.prefix(2))] : byFirst[key]) ?? []
        for i in candidates {
            let f = folded[i]
            guard f.count > key.count, f.hasPrefix(key) else { continue }
            out.append(words[i])
            if out.count >= limit { break }
        }
        return out
    }

    func setLayout(_ layout: KBLayout) {
        let want: String
        switch layout {
        case .azerty: want = "fr_FR"
        case .qwertz: want = "de_DE"
        case .spanish: want = "es_ES"
        case .swedish: want = "sv_SE"
        case .qwerty: want = "en_US"
        }
        let available = UITextChecker.availableLanguages
        if available.contains(want) {
            language = want
        } else if let alt = available.first(where: { $0.hasPrefix(String(want.prefix(2))) }) {
            language = alt
        } else {
            language = available.first ?? "en_US"
        }
        loadList(layout == .azerty ? "fr" : (layout == .qwerty ? "en" : "none"))
    }

    func setLexicon(_ lexicon: UILexicon) {
        for e in lexicon.entries {
            let input = e.userInput.lowercased()
            if input == e.documentText.lowercased() {
                known.insert(input)
            } else {
                replacements[input] = e.documentText
                known.insert(e.documentText.lowercased())
            }
        }
    }

    /// Le mot en cours d'écriture, juste avant le curseur (sans l'apostrophe d'élision : « l’arbre » → « arbre »).
    static func currentWord(_ before: String) -> String {
        var chars: [Character] = []
        for ch in before.reversed() {
            if ch.isLetter || ch == "-" { chars.append(ch) } else { break }
        }
        var w = String(chars.reversed())
        while w.hasPrefix("-") { w.removeFirst() }
        return w
    }

    /// Le mot vient-il en début de phrase ?
    static func atSentenceStart(_ before: String, word: String) -> Bool {
        let rest = before.dropLast(word.count).trimmingCharacters(in: .whitespaces)
        guard let last = rest.last else { return true }
        return ".!?…\n".contains(last)
    }

    private func isMisspelled(_ word: String) -> Bool {
        let ns = word as NSString
        let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false, language: language)
        return r.location != NSNotFound
    }

    private func matchCase(_ s: String, like word: String) -> String {
        if word.count > 1, word == word.uppercased() { return s.uppercased() }
        if let f = word.first, f.isUppercase { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// La correction à appliquer quand on termine le mot (espace, ponctuation), ou nil.
    func correction(for word: String, before: String) -> String? {
        guard word.count >= 3, word.count <= 30 else {
            if word == "i" && language.hasPrefix("en") { return "I" }
            return nil
        }
        let lower = word.lowercased()
        if let r = replacements[lower] { return r }
        if known.contains(lower) || rank[lower] != nil { return nil }
        // Un nom propre au milieu d'une phrase : on n'y touche pas.
        if let f = word.first, f.isUppercase, !Self.atSentenceStart(before, word: word) { return nil }
        guard isMisspelled(word) else { return nil }
        let ns = word as NSString
        // Le début d'un vrai mot (« minu » → minute) : on ne corrige pas, la barre propose la suite.
        if !listCompletions(word, limit: 1).isEmpty { return nil }
        var guesses = checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: language) ?? []
        // Les mots courants d'abord.
        guesses = guesses.enumerated().sorted { a, b in
            let ra = rank[a.element.lowercased()] ?? (100_000 + a.offset)
            let rb = rank[b.element.lowercased()] ?? (100_000 + b.offset)
            return ra < rb
        }.map { $0.element }
        // Prudente, comme le clavier d'Apple : on ne remplace que par un mot courant, presque identique
        // (une faute de frappe, deux pour un mot long), qui commence par la même lettre. Sinon, la barre propose.
        if word.contains(where: { $0.isNumber || $0 == "@" || $0 == "." || $0 == "/" }) { return nil }
        let allowed = word.count >= 7 ? 2 : 1
        let best = guesses.first { g in
            let gl = g.lowercased()
            guard !g.contains(" "), !g.contains("-"), gl.first == lower.first else { return false }
            guard let r = rank[gl], r < 20_000 else { return false }
            return Self.distance(gl, lower) <= allowed
        }
        return best.map { matchCase($0, like: word) }
    }

    /// Le nombre de lettres à changer pour passer d'un mot à l'autre (deux lettres inversées comptent pour une).
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[x.count][y.count]
    }

    /// Les trois propositions de la barre : le mot tapé, la meilleure (correction ou fin du mot), une autre.
    func suggestions(for word: String, before: String) -> (items: [String], best: Int?) {
        guard !word.isEmpty else { return ([], nil) }
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        var best: Int?
        let fix = correction(for: word, before: before)
        if let fix, fix != word {
            out = [word, fix]
            best = 1
        } else {
            out = [word]
        }
        var completions = listCompletions(word, limit: 3)
        if completions.isEmpty {
            completions = (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
                .filter { $0.lowercased() != word.lowercased() && !$0.contains(" ") }
        }
        completions = completions.map { matchCase($0, like: word) }
        for c in completions where out.count < 3 && !out.contains(c) { out.append(c) }
        if out.count < 3, fix == nil, isMisspelled(word) {
            for g in checker.guesses(forWordRange: range, in: word, language: language) ?? [] where out.count < 3 && !out.contains(g) {
                out.append(matchCase(g, like: word))
            }
        }
        return (out, best)
    }

    /// Le mot refusé (on a annulé la correction) : on l'apprend pour ne plus le corriger.
    func learn(_ word: String) {
        known.insert(word.lowercased())
        if !UITextChecker.hasLearnedWord(word) { UITextChecker.learnWord(word) }
    }
}
