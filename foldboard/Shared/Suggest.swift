import UIKit

/// Correction automatique et suggestions de mots, avec le correcteur d'iOS (UITextChecker)
/// et le lexique de l'utilisateur (contacts, remplacements de texte).
final class KBSuggest {
    private let checker = UITextChecker()
    private var known = Set<String>()
    private var replacements: [String: String] = [:]
    var language = "en_US"

    func setLayout(_ layout: KBLayout) {
        let want = layout == .azerty ? "fr_FR" : "en_US"
        let available = UITextChecker.availableLanguages
        if available.contains(want) {
            language = want
        } else if let alt = available.first(where: { $0.hasPrefix(String(want.prefix(2))) }) {
            language = alt
        } else {
            language = available.first ?? "en_US"
        }
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
        guard word.count >= 2, word.count <= 30 else {
            if word == "i" && language.hasPrefix("en") { return "I" }
            return nil
        }
        let lower = word.lowercased()
        if let r = replacements[lower] { return r }
        if known.contains(lower) { return nil }
        // Un nom propre au milieu d'une phrase : on n'y touche pas.
        if let f = word.first, f.isUppercase, !Self.atSentenceStart(before, word: word) { return nil }
        guard isMisspelled(word) else { return nil }
        let ns = word as NSString
        let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: language) ?? []
        // On garde une proposition proche (même début, longueur voisine) pour ne pas changer le sens.
        let best = guesses.first { g in
            let gl = g.lowercased()
            return abs(g.count - word.count) <= 2 && gl.first == lower.first && !g.contains(" ")
        } ?? guesses.first { abs($0.count - word.count) <= 1 && !$0.contains(" ") }
        return best.map { matchCase($0, like: word) }
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
        let completions = (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
            .filter { $0.lowercased() != word.lowercased() && !$0.contains(" ") }
            .map { matchCase($0, like: word) }
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
