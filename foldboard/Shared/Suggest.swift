import UIKit

/// Où le doigt s'est réellement posé pour chaque lettre du mot en cours, et le centre de chaque touche.
/// C'est ce que fait le clavier d'Apple : « teh » tapé avec le doigt à cheval entre E et R n'a pas la même
/// correction que « teh » tapé au centre des touches.
struct KBTouchModel {
    var points: [CGPoint]
    var centers: [Character: CGPoint]
    var keyW: CGFloat
    var keyH: CGFloat

    /// Le coût de lire `cand` à partir des touchers : 0 si chaque toucher tombe au centre de la touche voulue,
    /// environ 1 par lettre posée au bord, beaucoup plus pour une touche lointaine. nil si on ne peut pas comparer.
    func cost(_ cand: String) -> Double? {
        let c = Array(cand.lowercased())
        guard c.count == points.count, keyW > 0, keyH > 0 else { return nil }
        var total = 0.0
        for (i, ch) in c.enumerated() {
            let base = Character(String(ch).folding(options: .diacriticInsensitive, locale: nil))
            guard let k = centers[base] ?? centers[ch] else { return nil }
            let dx = Double((points[i].x - k.x) / (keyW * 0.55)), dy = Double((points[i].y - k.y) / (keyH * 0.55))
            total += dx * dx + dy * dy
        }
        return total
    }
}

/// Correction automatique et suggestions de mots, avec le correcteur d'iOS (UITextChecker)
/// et le lexique de l'utilisateur (contacts, remplacements de texte).
final class KBSuggest {
    private let checker = UITextChecker()
    private var known = Set<String>()
    private var replacements: [String: String] = [:]
    var language = "en_US"
    /// Les rangées de lettres du clavier : une faute de frappe, c'est une touche voisine, pas n'importe quelle lettre.
    private var rows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    /// Les 30 000 mots les plus courants (du plus fréquent au moins fréquent), pour compléter et classer.
    /// Liste : FrequencyWords (Hermit Dave), contenu sous licence CC BY-SA 4.0.
    private var words: [String] = []
    private var folded: [String] = []
    private var rank: [String: Int] = [:]
    /// Les mots par leurs deux premières lettres : compléter sans parcourir les 30 000 mots à chaque lettre.
    private var byPrefix: [String: [Int]] = [:]
    private var byFirst: [String: [Int]] = [:]
    /// Pour chaque mot sans accents, sa forme accentuée la plus courante (« apres » → « après », « ca » → « ça »).
    private var accented: [String: Int] = [:]
    private var loadedList = ""

    private func loadList(_ code: String) {
        guard loadedList != code else { return }
        loadedList = code
        words = []; folded = []; rank = [:]; byPrefix = [:]; byFirst = [:]; accented = [:]
        guard let url = Bundle.main.url(forResource: "words-" + code, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        words = text.split(separator: "\n").map(String.init)
        folded = words.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
        for (i, w) in words.enumerated() where rank[w] == nil { rank[w] = i }
        for (i, w) in words.enumerated() {
            let f = folded[i]
            if w.lowercased() != f, accented[f] == nil { accented[f] = i }
        }
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
        switch layout {
        case .azerty: rows = ["azertyuiop", "qsdfghjklm", "wxcvbn"]
        case .qwertz: rows = ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"]
        case .spanish: rows = ["qwertyuiop", "asdfghjklñ", "zxcvbnm"]
        case .swedish: rows = ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"]
        case .qwerty: rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
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

    private func isMisspelled(_ word: String, in lang: String? = nil) -> Bool {
        let ns = word as NSString
        let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false, language: lang ?? language)
        return r.location != NSNotFound
    }

    /// L'autre langue qu'on mélange souvent (français ⇄ anglais), comme le clavier d'Apple qui écrit dans les deux.
    private var second: String? {
        let want = language.hasPrefix("en") ? "fr" : "en"
        return UITextChecker.availableLanguages.first { $0.hasPrefix(want) }
    }

    private func matchCase(_ s: String, like word: String) -> String {
        if word.count > 1, word == word.uppercased() { return s.uppercased() }
        if let f = word.first, f.isUppercase { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// Les apostrophes oubliées, comme le clavier d'Apple (« dont » → « don’t », « jai » → « j’ai »).
    private static let contractions: [String: [String: String]] = [
        "en": ["im": "I’m", "ive": "I’ve", "dont": "don’t", "cant": "can’t", "wont": "won’t", "didnt": "didn’t",
               "doesnt": "doesn’t", "isnt": "isn’t", "wasnt": "wasn’t", "arent": "aren’t", "werent": "weren’t",
               "couldnt": "couldn’t", "shouldnt": "shouldn’t", "wouldnt": "wouldn’t", "havent": "haven’t", "hasnt": "hasn’t",
               "youre": "you’re", "youve": "you’ve", "youll": "you’ll", "theyre": "they’re", "theyve": "they’ve",
               "thats": "that’s", "whats": "what’s", "theres": "there’s", "heres": "here’s", "itll": "it’ll",
               "ill": "I’ll", "id": "I’d", "lets": "let’s", "hes": "he’s", "shes": "she’s"],
        "fr": ["jai": "j’ai", "cest": "c’est", "cetait": "c’était", "quil": "qu’il", "quils": "qu’ils", "quon": "qu’on",
               "nest": "n’est", "jen": "j’en", "jy": "j’y", "daccord": "d’accord", "aujourdhui": "aujourd’hui",
               "jespere": "j’espère", "sil": "s’il", "sils": "s’ils", "nimporte": "n’importe", "jetais": "j’étais",
               "jaime": "j’aime", "jarrive": "j’arrive", "jattends": "j’attends", "javais": "j’avais", "jaurais": "j’aurais",
               "quelquun": "quelqu’un", "lautre": "l’autre", "jsuis": "j’suis", "ya": "y’a"],
    ]
    /// Celles qui sont aussi de vrais mots (« ill », « lets », « id », « hes »…) : seulement dans la barre, jamais d'office.
    private static let ambiguous: Set<String> = ["ill", "id", "lets", "hes", "shes", "ya", "jy", "sil", "jen"]

    private func contraction(_ word: String) -> String? {
        guard let c = Self.contractions[String(language.prefix(2))]?[word.lowercased()] else { return nil }
        return c.hasPrefix("I") ? c : matchCase(c, like: word)
    }

    /// La forme accentuée d'un mot tapé sans accents, si elle existe (« apres » → « après »), et son rang.
    private func accentForm(_ word: String) -> (word: String, rank: Int)? {
        let lower = word.lowercased()
        let f = lower.folding(options: [.diacriticInsensitive], locale: nil)
        guard f == lower, let i = accented[f], words[i] != lower else { return nil }
        return (words[i], i)
    }

    /// Ajouter l'accent oublié, comme le clavier d'Apple : seulement si la forme accentuée est bien plus courante
    /// que la forme tapée (« ca » → « ça », « apres » → « après », mais jamais « a » → « à » : les deux existent).
    private func accentFix(_ word: String) -> String? {
        guard word.count >= 2, let a = accentForm(word) else { return nil }
        let own = rank[word.lowercased()] ?? Int.max
        guard own == Int.max || own > a.rank * 4 + 200 else { return nil }
        return matchCase(a.word, like: word)
    }

    /// La correction à appliquer quand on termine le mot (espace, ponctuation), ou nil.
    func correction(for word: String, before: String, touch: KBTouchModel? = nil) -> String? {
        let low = word.lowercased()
        if !known.contains(low), replacements[low] == nil {
            if !Self.ambiguous.contains(low), let c = contraction(word) { return c }
            if let fix = accentFix(word) { return fix }
        }
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
        // Un vrai mot dans l'autre langue (de l'anglais au milieu du français) : on n'y touche pas.
        if let l2 = second, !isMisspelled(word, in: l2) { return nil }
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
        // Les mots en majuscules (sigles) ne sont jamais remplacés.
        if word.count > 1, word == word.uppercased() { return nil }
        let allowed = word.count >= 7 ? 2 : 1
        // Les candidats : ceux du correcteur d'iOS, plus chaque mot obtenu en remplaçant une lettre par une
        // touche voisine du doigt (c'est la faute la plus fréquente, et iOS ne les propose pas toujours).
        var pool = guesses
        if let touch {
            for cand in nearbyWords(lower, touch: touch) where !pool.contains(where: { $0.lowercased() == cand }) { pool.append(cand) }
        }
        var best: (word: String, score: Double)?
        for g in pool {
            let gl = g.lowercased()
            guard !g.contains(" "), !g.contains("-") else { continue }
            guard let r = rank[gl], r < 15_000 else { continue }
            let d = typoDistance(gl, lower)
            guard d <= allowed else { continue }
            // La première lettre change rarement : seulement si le doigt était vraiment entre deux touches.
            var score = -log(Double(r) + 30)
            if let c = touch?.cost(gl), let own = touch?.cost(lower) {
                let extra = c - own
                if gl.first != lower.first && extra > 1.2 { continue }
                if extra > 6 { continue }          // une touche trop loin du doigt : pas une faute de frappe
                score -= extra * 0.6
            } else {
                if gl.first != lower.first { continue }
                score -= Double(d) * 1.5
            }
            if best == nil || score > best!.score { best = (g, score) }
        }
        if best == nil, word.count >= 4, let l2 = second {
            // Rien en français : peut-être une faute de frappe en anglais (et inversement). Seulement une touche voisine.
            let g2 = checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: l2) ?? []
            for g in g2.prefix(4) {
                let gl = g.lowercased()
                guard !g.contains(" "), !g.contains("-"), gl.first == lower.first, typoDistance(gl, lower) <= 1 else { continue }
                if let c = touch?.cost(gl), let own = touch?.cost(lower), c - own > 3 { continue }
                return matchCase(g, like: word)
            }
        }
        return best.map { matchCase($0.word, like: word) }
    }

    /// Les mots courants à une lettre près, dont la lettre changée est une touche proche de l'endroit où le doigt s'est posé.
    private func nearbyWords(_ lower: String, touch: KBTouchModel) -> [String] {
        let chars = Array(lower)
        guard chars.count == touch.points.count, chars.count <= 14 else { return [] }
        var out: [String] = []
        for (i, p) in touch.points.enumerated() {
            for (k, c) in touch.centers where k != chars[i] {
                let dx = (p.x - c.x) / touch.keyW, dy = (p.y - c.y) / touch.keyH
                guard dx * dx + dy * dy < 1.0 else { continue }   // moins d'une touche du doigt
                var w = chars; w[i] = k
                let cand = String(w)
                if let r = rank[cand], r < 15_000 { out.append(cand) }
                // Et la même avec l'accent (« apres » posé sur le e → « après »).
                if let a = accented[cand], words[a] != cand, rank[words[a]] ?? .max < 15_000 { out.append(words[a]) }
            }
        }
        return out
    }

    private func position(_ c: Character) -> (Int, Int)? {
        for (r, row) in rows.enumerated() {
            if let i = row.firstIndex(of: c) { return (r, row.distance(from: row.startIndex, to: i)) }
        }
        return nil
    }

    /// Deux touches voisines sur le clavier (même rangée, ou rangée d'à côté, décalée d'au plus une touche).
    private func neighbors(_ a: Character, _ b: Character) -> Bool {
        let fa = Character(String(a).folding(options: .diacriticInsensitive, locale: nil))
        let fb = Character(String(b).folding(options: .diacriticInsensitive, locale: nil))
        if fa == fb { return true }   // seul l'accent change
        guard let pa = position(fa), let pb = position(fb) else { return false }
        return abs(pa.0 - pb.0) <= 1 && abs(pa.1 - pb.1) <= 1
    }

    /// Comme `distance`, mais remplacer une lettre par une touche qui n'est pas voisine coûte 2 :
    /// « teh » → « the » ou « hrllo » → « hello » passent, « bat » → « cat » non (ce n'est pas une faute de frappe).
    func typoDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : (neighbors(x[i - 1], y[j - 1]) ? 1 : 2)
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[x.count][y.count]
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
    func suggestions(for word: String, before: String, touch: KBTouchModel? = nil) -> (items: [String], best: Int?) {
        guard !word.isEmpty else { return ([], nil) }
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        var best: Int?
        let fix = correction(for: word, before: before, touch: touch)
        if let fix, fix != word {
            out = [word, fix]
            best = 1
        } else {
            out = [word]
        }
        // L'apostrophe oubliée, même quand le mot existe aussi (« ill » → « I’ll ») : proposée dans la barre.
        if let c = contraction(word), !out.contains(c) { out.insert(c, at: min(1, out.count)); if best != nil { best = out.firstIndex(of: fix ?? "") } }
        // L'accent oublié (« a » → « à ») : toujours proposé dans la barre, même quand on ne le corrige pas seul.
        if let a = accentForm(word) {
            let c = matchCase(a.word, like: word)
            if !out.contains(c) { out.insert(c, at: min(1, out.count)); if best != nil { best = out.firstIndex(of: fix ?? "") } }
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
