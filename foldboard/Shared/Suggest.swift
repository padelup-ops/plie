import UIKit
import NaturalLanguage

/// Où le doigt s'est réellement posé pour chaque lettre du mot en cours, et le centre de chaque touche.
/// C'est ce que fait le clavier d'Apple : « teh » tapé avec le doigt à cheval entre E et R n'a pas la même
/// correction que « teh » tapé au centre des touches.
struct KBTouchModel {
    var points: [CGPoint]
    /// Le centre de chaque touche (deux pour une lettre présente des deux côtés du clavier coupé).
    var centers: [Character: [CGPoint]]
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
            guard let ks = centers[base] ?? centers[ch], !ks.isEmpty else { return nil }
            total += ks.map { k -> Double in
                let dx = Double((points[i].x - k.x) / (keyW * 0.55)), dy = Double((points[i].y - k.y) / (keyH * 0.55))
                return dx * dx + dy * dy
            }.min() ?? 0
        }
        return total
    }
}

/// Ce que le clavier apprend de toi en écrivant : tes mots (prénoms, mots à toi) et les mots qui se suivent
/// (« je suis » → « en »). Gardé sur le téléphone, partagé entre la correction et la barre de suggestions.
final class KBWordStore {
    static let shared = KBWordStore()
    private let lock = NSLock()
    private let key = "foldboard.words.v1"
    private var words: [String: Int] = [:]
    private var pairs: [String: [String: Int]] = [:]
    private var dirty = 0

    private struct Stored: Codable { var words: [String: Int]; var pairs: [String: [String: Int]] }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            words = s.words; pairs = s.pairs
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(Stored(words: words, pairs: pairs)) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// Un mot terminé (espace, ponctuation), avec le mot d'avant s'il y en a un dans la même phrase.
    func commit(_ word: String, after prev: String?) {
        let w = word.lowercased()
        guard w.count >= 1, w.count <= 30, w.allSatisfy({ $0.isLetter || $0 == "’" || $0 == "'" || $0 == "-" }) else { return }
        lock.lock(); defer { lock.unlock() }
        words[w, default: 0] += 1
        if let p = prev?.lowercased(), !p.isEmpty { pairs[p, default: [:]][w, default: 0] += 1 }
        // On garde la mémoire raisonnable : on oublie les mots vus une seule fois.
        if words.count > 4000 { words = words.filter { $0.value > 1 } }
        if pairs.count > 3000 { pairs = pairs.filter { $0.value.values.reduce(0, +) > 1 } }
        dirty += 1
        if dirty >= 5 { dirty = 0; save() }
    }

    func count(_ word: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return words[word.lowercased()] ?? 0
    }

    func pair(_ prev: String, _ word: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return pairs[prev.lowercased()]?[word.lowercased()] ?? 0
    }

    /// Les mots qui ont suivi `prev` le plus souvent.
    func next(after prev: String, limit: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return (pairs[prev.lowercased()] ?? [:]).sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Tes mots qui commencent comme `prefix`, des plus tapés aux moins tapés.
    func completions(_ prefix: String, limit: Int) -> [String] {
        let k = prefix.lowercased()
        lock.lock(); defer { lock.unlock() }
        return words.filter { $0.value >= 2 && $0.key.count > k.count && $0.key.hasPrefix(k) }
            .sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }
}

/// Correction automatique et suggestions de mots, avec le correcteur d'iOS (UITextChecker)
/// et le lexique de l'utilisateur (contacts, remplacements de texte).
final class KBSuggest {
    /// Réglages du moteur, ajustables par le banc d'essai (foldboard/tools/bench) ; sinon les valeurs par défaut.
    static var tune: [String: Double] = [:]
    private static func t(_ k: String, _ d: Double) -> Double { tune[k] ?? d }

    /// Un mot de la liste absent du modèle de langue et rare : souvent une coquille ou un nom (« sdi », « mazel »).
    private func doubtful(_ w: String, rank r: Int) -> Bool {
        guard let lm, r > Int(Self.t("doubtRank", 3_000)) else { return false }
        return lm.rank(w) == nil
    }

    /// La pénalité du glisser pour un mot douteux : forte si le correcteur d'iOS ne le connaît pas non plus
    /// (« sdi », « rapelle »), légère pour un vrai mot rare (« chiming »).
    private var spellCache: [String: Bool] = [:]
    /// iOS manque de mémoire : on vide ce qui se recalcule.
    func trimMemory() { spellCache = [:] }
    private func glideJunk(_ w: String, rank r: Int) -> Double {
        guard doubtful(w, rank: r) else { return 0 }
        let ok: Bool
        if let c = spellCache[w] { ok = c } else {
            let ns = w as NSString
            ok = checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false,
                                               language: language).location == NSNotFound
            if spellCache.count > 5_000 { spellCache = [:] }
            spellCache[w] = ok
        }
        return ok ? Self.t("gJunkValid", 1) : Self.t("gJunk", 4)
    }

    private let checker = UITextChecker()
    private var known = Set<String>()
    private var replacements: [String: String] = [:]
    /// Les noms de tes contacts (tels qu'écrits dans Contacts), par forme en minuscules.
    private var names: [String: String] = [:]
    /// Proposer les noms des contacts (réglage « Noms des contacts dans les suggestions »).
    var useNames = true
    var language = "en_US"
    /// Les rangées de lettres du clavier : une faute de frappe, c'est une touche voisine, pas n'importe quelle lettre.
    private var rows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// Le décalage de chaque rangée, en touches (la rangée du bas commence après la touche maj) : les touches
    /// voisines sont celles qui se touchent vraiment à l'écran (« n » touche « j » et « k », pas « g »).
    private var rowInsets: [Double] = [0, 0.5, 1.5]

    /// Les 30 000 mots les plus courants (du plus fréquent au moins fréquent), pour compléter et classer.
    /// Liste : FrequencyWords (Hermit Dave), contenu sous licence CC BY-SA 4.0.
    private var words: [String] = []
    private var folded: [String] = []
    private var rank: [String: Int] = [:]
    /// Les mots par leurs deux premières lettres : compléter sans parcourir les 30 000 mots à chaque lettre.
    private var byPrefix: [String: [Int]] = [:]
    private var byFirst: [String: [Int]] = [:]
    /// Les 15 000 mots les plus courants, rangés par première lettre et longueur (lettres sans accents) :
    /// la recherche « touches voisines » ne parcourt que les mots de la bonne longueur.
    private var byFirstLen: [String: [(Int, [Character])]] = [:]
    /// Pour chaque mot sans accents, sa forme accentuée la plus courante (« apres » → « après », « ca » → « ça »).
    private var accented: [String: Int] = [:]
    private var loadedList = ""

    /// Le modèle de langue de la disposition (partagé entre la correction et la barre : chargé une seule fois).
    private var lm: KBLanguageModel?
    private static var lmCache: [String: KBLanguageModel] = [:]
    private static let lmLock = NSLock()
    private static func model(_ code: String) -> KBLanguageModel? {
        lmLock.lock(); defer { lmLock.unlock() }
        if let m = lmCache[code] { return m }
        guard let m = KBLanguageModel(lang: code) else { return nil }
        lmCache = [code: m]   // une seule langue en mémoire
        return m
    }

    /// Les listes de mots d'une langue, construites une seule fois et partagées par tous les correcteurs (celui de la
    /// barre, celui de l'espace, et les deux claviers qu'iOS fait tourner un instant quand le Duo s'ouvre ou se ferme) :
    /// une seule copie en mémoire au lieu de quatre. Elles ne changent plus une fois construites.
    private final class ListData {
        var words: [String] = [], folded: [String] = [], rank: [String: Int] = [:]
        var byPrefix: [String: [Int]] = [:], byFirst: [String: [Int]] = [:]
        var byFirstLen: [String: [(Int, [Character])]] = [:], accented: [String: Int] = [:]
    }
    private static var listCache: [String: ListData] = [:]
    private static let listLock = NSLock()
    private static func listData(_ code: String) -> ListData {
        listLock.lock(); defer { listLock.unlock() }
        if let d = listCache[code] { return d }
        let d = ListData()
        if let url = Bundle.main.url(forResource: "words-" + code, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            d.words = text.split(separator: "\n").map(String.init)
            d.folded = d.words.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
            for (i, w) in d.words.enumerated() where d.rank[w] == nil { d.rank[w] = i }
            for (i, w) in d.words.enumerated() {
                let f = d.folded[i]
                if w.lowercased() != f, d.accented[f] == nil { d.accented[f] = i }
            }
            for (i, f) in d.folded.enumerated() {
                d.byPrefix[String(f.prefix(2)), default: []].append(i)
                d.byFirst[String(f.prefix(1)), default: []].append(i)
                if i < 15_000 {
                    let c = Array(f)
                    if c.count >= 4 && c.count <= 14 { d.byFirstLen["\(c[0])\(c.count)", default: []].append((i, c)) }
                }
            }
        }
        // Une seule langue en mémoire (comme le modèle de langue).
        listCache = [code: d]
        return d
    }

    private func loadList(_ code: String) {
        guard loadedList != code else { return }
        loadedList = code
        // Les tableaux sont partagés (copie à l'écriture) : aucune copie tant que personne ne les modifie.
        let d = Self.listData(code)
        words = d.words; folded = d.folded; rank = d.rank; byPrefix = d.byPrefix; byFirst = d.byFirst
        byFirstLen = d.byFirstLen; accented = d.accented
    }

    // MARK: Écrire en glissant (comme le clavier d'Apple)
    //
    // Le doigt trace un chemin sur les lettres. Pour chaque mot qui commence près du début du tracé et finit près
    // de la fin, on dessine le chemin « idéal » (de centre de touche en centre de touche) et on le compare au
    // tracé, point par point. Le plus proche gagne, avec un coup de pouce pour les mots courants et ceux qui
    // collent à la phrase (modèle de langue).

    private static func resample(_ pts: [CGPoint], _ n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        let step = total / CGFloat(n - 1)
        var out = [pts[0]]
        var acc: CGFloat = 0
        var prev = pts[0]
        var i = 1
        while i < pts.count && out.count < n {
            let cur = pts[i]
            let d = hypot(cur.x - prev.x, cur.y - prev.y)
            if acc + d >= step && d > 0 {
                let t = (step - acc) / d
                let q = CGPoint(x: prev.x + t * (cur.x - prev.x), y: prev.y + t * (cur.y - prev.y))
                out.append(q)
                prev = q
                acc = 0
            } else {
                acc += d
                prev = cur
                i += 1
            }
        }
        while out.count < n { out.append(pts.last!) }
        return out
    }

    /// Centrer et mettre à l'échelle un tracé : sa forme seule, où qu'il soit sur le clavier.
    private static func normalized(_ pts: [CGPoint]) -> [CGPoint] {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0), h = (ys.max() ?? 0) - (ys.min() ?? 0)
        let size = max(w, h, 1)
        let cx = xs.reduce(0, +) / CGFloat(pts.count), cy = ys.reduce(0, +) / CGFloat(pts.count)
        return pts.map { CGPoint(x: ($0.x - cx) / size, y: ($0.y - cy) / size) }
    }

    /// Les mots qu'on a probablement tracés, du plus probable au moins probable.
    ///
    /// Deux mesures, comme les claviers à glisser connus : la position (le tracé passe-t-il sur les bonnes touches ?)
    /// et la forme (a-t-il le même dessin, même un peu décalé ?). Le début et la fin comptent triple : c'est là que
    /// le doigt vise le mieux. Puis le modèle de langue départage les mots au tracé proche.
    func glide(_ raw: [CGPoint], touch: KBTouchModel, before: String, limit: Int = 4) -> [String] {
        guard raw.count >= 2, !words.isEmpty else { return [] }
        // Le pouce se pose un peu plus bas qu'il ne vise : même correction que pour la frappe.
        let path = raw.map { CGPoint(x: $0.x, y: $0.y - 4) }
        let kw = touch.keyW, kh = touch.keyH
        func center(_ c: Character, near p: CGPoint) -> CGPoint? {
            let base = Character(String(c).folding(options: .diacriticInsensitive, locale: nil))
            guard let cs = touch.centers[base] ?? touch.centers[c] else { return nil }
            return cs.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }
        }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot((a.x - b.x) / kw, (a.y - b.y) / kh) }
        let n = 48
        let user = Self.resample(path, n)
        let userShape = Self.normalized(user)
        let probe = Self.resample(path, 64)
        let start = path[0], end = path[path.count - 1]
        // La longueur du tracé (en touches) et ses virages francs : un mot doit avoir à peu près la même longueur
        // de chemin et passer par chaque virage (« bonjour » fait demi-tour sur n puis sur o ; « bobby » non).
        func length(_ p: [CGPoint]) -> CGFloat { zip(p, p.dropFirst()).reduce(0) { $0 + dist($1.0, $1.1) } }
        let userLen = length(user)
        var corners: [CGPoint] = []
        if n >= 9 {
            var lastK = -10
            for k in 3..<(n - 3) {
                let a = CGPoint(x: user[k].x - user[k - 3].x, y: user[k].y - user[k - 3].y)
                let b = CGPoint(x: user[k + 3].x - user[k].x, y: user[k + 3].y - user[k].y)
                let la = hypot(a.x / kw, a.y / kh), lb = hypot(b.x / kw, b.y / kh)
                guard la > 0.35, lb > 0.35 else { continue }
                let cosv = (a.x * b.x + a.y * b.y) / max(0.0001, hypot(a.x, a.y) * hypot(b.x, b.y))
                guard cosv < 0.35 else { continue }          // plus de ~70° : un vrai virage
                if k - lastK <= 4, !corners.isEmpty { continue }
                corners.append(user[k]); lastK = k
            }
        }
        // Pour chaque lettre, à quelle distance le tracé passe de sa touche, point par point.
        var near: [Character: [CGFloat]] = [:]
        for (k, cs) in touch.centers {
            near[k] = probe.map { p in cs.map { dist($0, p) }.min() ?? 9 }
        }
        var firsts: [String] = []
        for (k, _) in touch.centers where (near[k]?.first ?? 9) < 1.25 { firsts.append(String(k)) }
        var scored: [(String, Double)] = []
        var ranks: [Int] = []
        for f0 in firsts {
            for i in (byFirst[f0] ?? []).prefix(30_000) {
                let w = folded[i]
                guard w.count >= 2, w.count <= 20, let last = w.last, let dl = near[last]?.last, dl < 1.35 else { continue }
                // Chaque lettre (sans les doubles) doit être frôlée dans l'ordre ; une seule peut manquer.
                var j = 0, misses = 0
                var prevC: Character?
                for c in w where c != prevC {
                    prevC = c
                    guard let row = near[c] else { misses = 9; break }
                    if let k = row[j...].firstIndex(where: { $0 < 1.05 }) { j = k } else { misses += 1 }
                    if misses > 1 { break }
                }
                guard misses <= 1 else { continue }
                var ideal: [CGPoint] = []
                var anchor = start
                var ok = true
                for c in w {
                    guard let k = center(c, near: anchor) else { ok = false; break }
                    if ideal.last != k { ideal.append(k) }
                    anchor = k
                }
                guard ok else { continue }
                let tpl = Self.resample(ideal.count == 1 ? [ideal[0], ideal[0]] : ideal, n)
                var loc: CGFloat = 0, wsum: CGFloat = 0
                for k in 0..<n {
                    let wgt: CGFloat = (k < 3 || k >= n - 3) ? 3 : 1
                    loc += dist(tpl[k], user[k]) * wgt
                    wsum += wgt
                }
                loc /= wsum
                guard loc < 1.25 else { continue }
                // Les virages du tracé que le mot ne visite pas, et l'écart de longueur.
                var missedTurns = 0
                for c in corners where !ideal.contains(where: { dist($0, c) < 0.95 }) { missedTurns += 1 }
                let lenRatio = Double(max(0.3, length(tpl)) / max(0.3, userLen))
                let lenPenalty = userLen > 1.5 ? abs(log(lenRatio)) : 0
                let tplShape = Self.normalized(tpl)
                var shape: CGFloat = 0
                for k in 0..<n { shape += hypot(tplShape[k].x - userShape[k].x, tplShape[k].y - userShape[k].y) }
                shape /= CGFloat(n)
                let prior = lm?.score(words[i], before: before) ?? -log(Double(i) + 30)
                let mine = log(1 + Double(KBWordStore.shared.count(w))) * 0.6
                let score = -Double(loc * loc) * Self.t("gLoc", 9) - Double(shape) * Self.t("gShape", 5) + prior * Self.t("gPrior", 0.45)
                    + mine - Double(misses) * 2 - Double(missedTurns) * Self.t("gTurn", 2.2) - lenPenalty * Self.t("gLen", 5)
                scored.append((words[i], score))
                ranks.append(i)
            }
        }
        // Les mots douteux (coquilles du dictionnaire) ne sont vérifiés que parmi les meilleurs : le correcteur d'iOS
        // est lent, on ne l'appelle pas pour des centaines de mots à chaque geste.
        let order = scored.indices.sorted { scored[$0].1 > scored[$1].1 }
        for j in order.prefix(Int(Self.t("gJunkTop", 20))) { scored[j].1 -= glideJunk(scored[j].0, rank: ranks[j]) }
        scored.sort { $0.1 > $1.1 }
        var out: [String] = []
        for (w, _) in scored where !out.contains(w) { out.append(w); if out.count == limit { break } }
        return out
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
        rowInsets = layout == .qwerty ? [0, 0.5, 1.5] : [0, 0, 1.5]
        let available = UITextChecker.availableLanguages
        if available.contains(want) {
            language = want
        } else if let alt = available.first(where: { $0.hasPrefix(String(want.prefix(2))) }) {
            language = alt
        } else {
            language = available.first ?? "en_US"
        }
        let code = layout == .azerty ? "fr" : (layout == .qwerty ? "en" : "none")
        loadList(code)
        lm = code == "none" ? nil : Self.model(code)
    }

    func setLexicon(_ lexicon: UILexicon) {
        for e in lexicon.entries {
            let input = e.userInput.lowercased()
            if input == e.documentText.lowercased() {
                known.insert(input)
                // Un nom (une majuscule) : on le proposera en entier dès les premières lettres.
                if let f = e.documentText.first, f.isUppercase, e.documentText.count >= 2 { names[input] = e.documentText }
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

    /// La phrase en cours est-elle en anglais ? (au moins deux mots avant celui-ci, et l'anglais nettement en tête).
    /// Gardé pour la phrase : la barre redemande à chaque lettre.
    private var englishCache: (String, Bool) = ("", false)
    private func sentenceIsEnglish(_ before: String, word: String) -> Bool {
        guard Self.t("bilingual", 1) > 0 else { return false }
        var text = String(before.dropLast(word.count))
        if let cut = text.lastIndex(where: { ".!?\n".contains($0) }) { text = String(text[text.index(after: cut)...]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text == englishCache.0 { return englishCache.1 }
        var english = false
        let ws = text.split(whereSeparator: { $0 == " " })
        if ws.count >= 2, let en = second, let fr = UITextChecker.availableLanguages.first(where: { $0.hasPrefix("fr") }) {
            // Les mots qui n'existent que dans une des deux langues (« know », « the » / « je », « suis »).
            var onlyEN = 0, onlyFR = 0
            for w in ws.suffix(8) {
                let s = String(w).trimmingCharacters(in: .punctuationCharacters)
                guard s.count >= 2 else { continue }
                let isFR = rank[s.lowercased()] != nil || !isMisspelled(s, in: fr)
                let isEN = !isMisspelled(s, in: en)
                if isEN && !isFR { onlyEN += 1 } else if isFR && !isEN { onlyFR += 1 }
            }
            if onlyEN >= 2 && onlyFR == 0 {
                english = true
            } else if onlyEN >= 1 && onlyEN > onlyFR {
                let r = NLLanguageRecognizer()
                r.languageConstraints = [.english, .french]
                r.processString(String(ws.suffix(10).joined(separator: " ")))
                english = (r.languageHypotheses(withMaximum: 2)[.english] ?? 0) >= 0.6
            }
        }
        englishCache = (text, english)
        return english
    }

    /// La correction en anglais (phrase anglaise sur le clavier français) : prudente, comme pour le français —
    /// une faute de frappe (deux pour un mot long), même première lettre, vers une proposition du correcteur d'iOS.
    private func englishCorrection(_ word: String, before: String, lang: String, touch: KBTouchModel?) -> String? {
        let low = word.lowercased()
        if let r = replacements[low] { return r }
        if low == "i" { return "I" }
        if !Self.ambiguous.contains(low), let c = Self.contractions["en"]?[low] { return c.hasPrefix("I") ? c : matchCase(c, like: word) }
        guard word.count >= 3, word.count <= 30, !known.contains(low), KBWordStore.shared.count(low) < 3 else { return nil }
        if word.contains(where: { $0.isNumber || $0 == "@" || $0 == "." || $0 == "/" }) { return nil }
        if word.count > 1, word == word.uppercased() { return nil }
        if let f = word.first, f.isUppercase, !Self.atSentenceStart(before, word: word) { return nil }
        guard isMisspelled(word, in: lang) else { return nil }
        let ns = word as NSString
        let allowed = word.count >= 7 ? 2 : 1
        var best: (String, Int)?
        for (k, g) in (checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: lang) ?? []).prefix(6).enumerated() {
            let gl = g.lowercased()
            let d = typoDistance(gl, low)
            guard !g.contains(" "), !g.contains("-"), d <= allowed else { continue }
            let swapped = Self.isSwap(gl, low)
            if gl.first != low.first {
                guard let a = gl.first, let b = low.first, neighbors(a, b), d <= 1 else { continue }
            }
            // Deux lettres inversées : chaque doigt a visé la bonne touche, dans le désordre (pas de contrôle du toucher).
            if !swapped, let c = touch?.cost(gl), let own = touch?.cost(low), c - own > 6 { continue }
            let score = (swapped ? 0 : (gl.first == low.first ? 10 : 20)) + d * 3 + k
            if best == nil || score < best!.1 { best = (g, score) }
        }
        return best.map { matchCase($0.0, like: word) }
    }

    /// L'autre langue qu'on mélange souvent (français ⇄ anglais), comme le clavier d'Apple qui écrit dans les deux.
    private var second: String? {
        let want = language.hasPrefix("en") ? "fr" : "en"
        return UITextChecker.availableLanguages.first { $0.hasPrefix(want) }
    }

    static let frHyphen: [String: String] = [
        "estce": "est-ce", "questce": "qu’est-ce", "qu’estce": "qu’est-ce", "peutetre": "peut-être", "peutêtre": "peut-être",
        "atil": "a-t-il", "atelle": "a-t-elle", "aton": "a-t-on", "yatil": "y a-t-il", "vatil": "va-t-il", "vatelle": "va-t-elle", "vaton": "va-t-on",
        "estil": "est-il", "estelle": "est-elle", "esttu": "es-tu", "estu": "es-tu", "astu": "as-tu", "sontils": "sont-ils", "sontelles": "sont-elles",
        "peuxtu": "peux-tu", "veuxtu": "veux-tu", "saistu": "sais-tu", "voistu": "vois-tu", "vienstu": "viens-tu", "vastu": "vas-tu", "pourraistu": "pourrais-tu",
        "peutil": "peut-il", "peutelle": "peut-elle", "peuton": "peut-on", "fautil": "faut-il", "doisje": "dois-je", "puisje": "puis-je", "suisje": "suis-je",
        "pouvezvous": "pouvez-vous", "voulezvous": "voulez-vous", "avezvous": "avez-vous", "etesvous": "êtes-vous", "êtesvous": "êtes-vous", "savezvous": "savez-vous",
        "pourriezvous": "pourriez-vous", "dismoi": "dis-moi", "ditesmoi": "dites-moi", "excusezmoi": "excusez-moi", "excusemoi": "excuse-moi",
        "attendsmoi": "attends-moi", "rappellemoi": "rappelle-moi", "envoiemoi": "envoie-moi", "allezy": "allez-y", "vasy": "vas-y", "allonsy": "allons-y",
        "celuici": "celui-ci", "celleci": "celle-ci", "ceuxci": "ceux-ci", "cellesci": "celles-ci", "celuila": "celui-là", "cellela": "celle-là",
        "lahaut": "là-haut", "labas": "là-bas", "audessus": "au-dessus", "audessous": "au-dessous", "audela": "au-delà", "pardessus": "par-dessus",
        "rendezvous": "rendez-vous", "aujourdhui": "aujourd’hui", "aujourd’hui": "aujourd’hui", "cestadire": "c’est-à-dire", "c’estadire": "c’est-à-dire",
        "moimeme": "moi-même", "toimeme": "toi-même", "luimeme": "lui-même", "ellememe": "elle-même", "nousmemes": "nous-mêmes", "vousmeme": "vous-même",
        "euxmemes": "eux-mêmes", "aprèsmidi": "après-midi", "apresmidi": "après-midi", "weekend": "week-end", "grandmere": "grand-mère", "grandpere": "grand-père",
        "grandsparents": "grands-parents", "petitdejeuner": "petit-déjeuner", "vingtetun": "vingt-et-un", "dixhuit": "dix-huit", "dixneuf": "dix-neuf", "dixsept": "dix-sept",
        "tshirt": "t-shirt", "c’estàdire": "c’est-à-dire", "quelquun": "quelqu’un", "jusqua": "jusqu’à",
    ]

    private func matchCase(_ s: String, like word: String) -> String {
        if word.count > 1, word == word.uppercased() { return s.uppercased() }
        if let f = word.first, f.isUppercase { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// Le mot suivant le plus probable, pour démarrer avant que le clavier ait appris tes habitudes.
    private static let nextSeeds: [String: [String: [String]]] = [
        "fr": ["": ["Je", "Merci", "Bonjour"], "je": ["suis", "vais", "ne"], "suis": ["en", "pas", "à"], "en": ["train", "fait", "plus"],
               "train": ["de", "d’"], "c’est": ["pas", "un", "la"], "il": ["y", "est", "a"], "y": ["a", "en", "aller"], "à": ["la", "demain", "tout"],
               "de": ["la", "faire", "l’"], "pas": ["de", "le", "encore"], "est": ["ce", "pas", "un"], "merci": ["beaucoup", "pour", "à"],
               "tu": ["es", "as", "peux"], "on": ["se", "va", "peut"], "vais": ["à", "te", "faire"], "pour": ["le", "la", "moi"],
               "ça": ["va", "me", "fait"], "va": ["bien", "être", "te"], "bonne": ["journée", "soirée", "nuit"],
               "et": ["je", "toi", "le"], "que": ["je", "tu", "le"], "mais": ["je", "c’est", "pas"], "tout": ["le", "de", "à"],
               "bon": ["courage", "appétit", "week-end"], "avec": ["toi", "le", "moi"], "très": ["bien", "bon", "beau"], "on se": []],
        "en": ["": ["I", "Thanks", "The"], "i": ["am", "think", "have"], "i’m": ["not", "going", "so"], "am": ["going", "not", "a"],
               "going": ["to", "out", "home"], "to": ["be", "the", "get"], "thank": ["you"], "thanks": ["for", "so", "a"],
               "it": ["is", "was", "would"], "is": ["a", "the", "not"], "the": ["same", "best", "only"], "you": ["are", "can", "have"],
               "of": ["the", "course", "my"], "in": ["the", "a", "my"], "on": ["the", "my", "a"], "for": ["the", "a", "you"],
               "how": ["are", "is", "about"], "what": ["is", "are", "do"], "see": ["you", "it", "the"], "let": ["me", "us"],
               "let’s": ["go", "do", "see"], "have": ["a", "to", "you"], "good": ["morning", "night", "luck"], "can": ["you", "i", "be"]],
    ]

    /// Ce qui vient après le texte : appris de toi d'abord, puis les débuts les plus courants.
    func predictions(before: String) -> [String] {
        let prev = Self.lastWord(before)
        let lang = String(language.prefix(2))
        let start = Self.atSentenceStart(before + "x", word: "x")
        var out: [String] = []
        if let lm {
            // Ce que tu écris d'habitude après ce mot passe d'abord, puis le modèle de langue.
            if !start, let prev { out = Array(KBWordStore.shared.next(after: prev, limit: 3).filter { KBWordStore.shared.pair(prev, $0) >= 2 }.prefix(2)) }
            for w in lm.next(before: before, limit: 6) where out.count < 3 && !out.contains(w) { out.append(w) }
        }
        if out.isEmpty, !start, let prev {
            out = KBWordStore.shared.next(after: prev, limit: 3)
            for w in Self.nextSeeds[lang]?[prev.lowercased()] ?? [] where out.count < 3 && !out.contains(w) { out.append(w) }
        } else {
            for w in Self.nextSeeds[lang]?[""] ?? [] where out.count < 3 { out.append(w) }
        }
        out = out.map { w in
            if lang == "en", w == "i" || w.hasPrefix("i’") { return "I" + w.dropFirst() }
            return w
        }
        if start { out = out.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        return out
    }

    /// Le dernier mot entier avant le curseur (le texte se termine par une espace), dans la même phrase.
    static func lastWord(_ before: String) -> String? {
        let t = before.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, last.isLetter else { return nil }
        var chars: [Character] = []
        for ch in t.reversed() {
            if ch.isLetter || ch == "’" || ch == "'" || ch == "-" { chars.append(ch) } else { break }
        }
        let w = String(chars.reversed())
        return w.isEmpty ? nil : w
    }

    /// Le mot juste avant le mot en cours.
    static func previousWord(_ before: String, word: String) -> String? {
        lastWord(String(before.dropLast(word.count)))
    }

    /// Les apostrophes oubliées, comme le clavier d'Apple (« dont » → « don’t », « jai » → « j’ai »).
    private static let contractions: [String: [String: String]] = [
        "en": ["im": "I’m", "ive": "I’ve", "dont": "don’t", "cant": "can’t", "wont": "won’t", "didnt": "didn’t",
               "doesnt": "doesn’t", "isnt": "isn’t", "wasnt": "wasn’t", "arent": "aren’t", "werent": "weren’t",
               "couldnt": "couldn’t", "shouldnt": "shouldn’t", "wouldnt": "wouldn’t", "havent": "haven’t", "hasnt": "hasn’t",
               "youre": "you’re", "youve": "you’ve", "youll": "you’ll", "theyre": "they’re", "theyve": "they’ve",
               "thats": "that’s", "whats": "what’s", "theres": "there’s", "heres": "here’s", "itll": "it’ll",
               "ill": "I’ll", "id": "I’d", "lets": "let’s", "hes": "he’s", "shes": "she’s", "its": "it’s"],
        "fr": ["jai": "j’ai", "cest": "c’est", "cetait": "c’était", "quil": "qu’il", "quils": "qu’ils", "quon": "qu’on",
               "nest": "n’est", "jen": "j’en", "jy": "j’y", "daccord": "d’accord", "aujourdhui": "aujourd’hui",
               "jespere": "j’espère", "sil": "s’il", "sils": "s’ils", "nimporte": "n’importe", "jetais": "j’étais",
               "jaime": "j’aime", "jarrive": "j’arrive", "jattends": "j’attends", "javais": "j’avais", "jaurais": "j’aurais",
               "quelquun": "quelqu’un", "lautre": "l’autre", "jsuis": "j’suis", "ya": "y’a"],
    ]
    /// Celles qui sont aussi de vrais mots (« ill », « lets », « id », « hes »…) : seulement dans la barre, jamais d'office.
    private static let ambiguous: Set<String> = ["ill", "id", "lets", "hes", "shes", "ya", "jy", "sil", "jen", "its"]

    /// Les mots après lesquels « its » est bien le possessif (« of its », « on its own », « has its »).
    /// Partout ailleurs (début de phrase, « I think its », « but its »…), c'est presque toujours « it’s ».
    private static let itsPossessive: Set<String> = ["of", "in", "on", "for", "with", "to", "by", "from", "at", "into", "onto",
        "about", "has", "have", "had", "having", "lost", "lose", "loses", "through", "within", "under", "over", "during",
        "across", "after", "before", "behind", "beyond", "toward", "towards", "upon", "without", "change", "changed", "keep",
        "kept", "keeps", "do", "does", "did", "doing", "show", "shows", "find", "found", "reach", "reached", "make", "made",
        "all", "one", "each", "both", "near", "around", "against", "among", "via", "despite", "like", "than"]

    /// Les mots après lesquels « a » est presque toujours « à ».
    private static let towardA: Set<String> = ["vais", "vas", "va", "allons", "allez", "vont", "aller", "allé", "allée", "allés",
        "jusqu’", "grâce", "face", "quant", "pense", "penses", "pensé", "rentre", "rentrer", "arrive", "arriver", "habite", "commence",
        "commencer", "continue", "réussi", "réussir", "aide", "aider", "parle", "parler", "dit", "dis", "demande", "envoie", "donne",
        "rendez-vous", "prêt", "prête", "machine", "merci"]

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

    /// AZERTY : l'apostrophe tapée à la place du n, au milieu d'un mot (« ma’que » → « manque »). Seulement si ce qui
    /// précède l'apostrophe n'est pas une élision (« l’arbre », « qu’il » restent) et que le mot avec le n existe.
    func apostropheTypo(_ token: String) -> String? {
        guard rows.first == "azertyuiop", token.count >= 4 else { return nil }
        let chars = Array(token)
        let idx = chars.indices.filter { chars[$0] == "’" || chars[$0] == "'" }
        guard idx.count == 1, let i = idx.first, i > 0, i < chars.count - 1 else { return nil }
        let a = String(chars[..<i]).lowercased(), b = String(chars[(i + 1)...]).lowercased()
        guard a.allSatisfy({ $0.isLetter }), b.allSatisfy({ $0.isLetter }) else { return nil }
        let elided: Set<String> = ["c", "j", "l", "d", "m", "n", "s", "t", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu", "presqu", "aujourd"]
        guard !elided.contains(a) else { return nil }
        let cand = a + "n" + b
        guard let r = rank[cand], r < 15_000 else { return nil }
        return matchCase(cand, like: token)
    }

    /// Le remplacement de texte de l'utilisateur pour ce mot, s'il en a un.
    func replacement(for word: String) -> String? { replacements[word.lowercased()] }

    /// La correction à appliquer quand on termine le mot (espace, ponctuation), ou nil.
    /// `fast` : appelé sur le fil principal (à l'espace) — sans les suggestions du correcteur d'iOS, qui peuvent
    /// prendre une demi-seconde en français ; nos propres candidats (fautes de frappe, touches voisines) suffisent.
    func correction(for word: String, before: String, touch: KBTouchModel? = nil, fast: Bool = false) -> String? {
        // Une phrase en anglais sur le clavier français (comme le clavier d'Apple avec deux langues) : on corrige en
        // anglais, et rien de français (« the » ne devient pas « thé », « a » pas « à »).
        if language.hasPrefix("fr"), let l2 = second, sentenceIsEnglish(before, word: word) {
            return englishCorrection(word, before: before, lang: l2, touch: touch)
        }
        let low = word.lowercased()
        let prev = Self.previousWord(before, word: word)?.lowercased()
        // Tes remplacements de texte (Réglages > Clavier) : toujours appliqués, même courts (« ty » → « Thank you »).
        if let r = replacements[low] { return r }
        // Les mots à trait d'union tapés d'un bloc : « estce » → « est-ce », « peutetre » → « peut-être ».
        if language.hasPrefix("fr"), let h = Self.frHyphen[low.replacingOccurrences(of: "'", with: "’")] {
            return matchCase(h, like: word)
        }
        // Et avec une touche voisine (« edtce » → « est-ce »).
        if language.hasPrefix("fr"), Self.t("hyphenTypo", 1) > 0, low.count >= 5, rank[low] == nil, !known.contains(low),
           let h = Self.frHyphen.first(where: { $0.key.count == low.count && typoDistance($0.key, low) <= 1 })?.value {
            return matchCase(h, like: word)
        }
        // Une lettre seule qui n'est pas un mot, juste à côté du « a » (AZERTY : « il y z » → « il y a »,
        // « je pense z » → « je pense à ») : c'est « a », puis « a » ou « à » d'après la phrase.
        if language.hasPrefix("fr"), Self.t("oneLetterFix", 1) > 0, word.count == 1, let ch = low.first, ch.isLetter,
           !(Self.oneLetter["fr"]?.contains(low) ?? true), low != "à", neighbors("a", ch) {
            let a = matchCase("a", like: word)
            return correction(for: a, before: String(before.dropLast(word.count)) + a, touch: nil, fast: fast) ?? a
        }
        // Un prénom de tes contacts tapé en minuscules (et qui n'est pas un mot courant) : la majuscule.
        if useNames, word == low, let n = names[low], rank[low] == nil, n.lowercased() == low { return n }
        // « a » ou « à » d'après le mot d'avant : « je vais a » → « je vais à », « il a » reste « il a ».
        // Avant « tes mots à toi » : « a » est tapé si souvent (« il a ») qu'il y passerait et ne serait plus jamais
        // corrigé (« aller a la piscine » restait).
        if language.hasPrefix("fr"), low == "a", let prev, Self.towardA.contains(prev) || Self.isInfinitive(prev) { return matchCase("à", like: word) }
        if language.hasPrefix("fr"), low == "a", let lm, let sa = lm.score("à", before: before), let s0 = lm.score("a", before: before),
           sa > s0 + Self.t("aDelta", 0.5) { return matchCase("à", like: word) }
        // Tes mots à toi (tapés plusieurs fois, jamais corrigés) : on n'y touche plus.
        if KBWordStore.shared.count(low) >= 3 { return nil }
        // « its » ou « it’s » d'après le mot d'avant, comme le clavier d'Apple : « its great » → « it’s great »,
        // mais « on its own » reste.
        if language.hasPrefix("en"), low == "its", !known.contains(low) {
            if let prev, Self.itsPossessive.contains(prev) { return nil }
            return word.first?.isUppercase == true ? "It’s" : "it’s"
        }
        if !known.contains(low), replacements[low] == nil {
            if !Self.ambiguous.contains(low), let c = contraction(word) { return c }
            if let fix = accentFix(word) { return fix }
        }
        // L'apostrophe oubliée ou tapée à côté (AZERTY : le ’ est à côté du n) : « cedt » → « c’est », « nnzi » → « n’ai »,
        // « jzi » → « j’ai », « qua » → « qu’à ».
        if language.hasPrefix("fr"), Self.t("elision", 1) > 0, word.count >= 3, !known.contains(low), (rank[low] ?? Int.max) > 2_000,
           let e = elisionFix(low, before: before) { return matchCase(e, like: word) }
        if fast, Self.t("shortFix", 1) > 0, word.count >= 2, word.count <= 3, let f = shortContextFix(word, before: before, touch: touch) { return f }
        if word.count == 2, let f = twoLetterFix(word, before: before, touch: touch) { return f }
        guard word.count >= 3, word.count <= 30 else {
            if word == "i" && language.hasPrefix("en") { return "I" }
            return nil
        }
        let lower = word.lowercased()
        if let r = replacements[lower] { return r }
        if known.contains(lower) { return nil }
        if let r = rank[lower], !(Self.t("cJunk", 0) > 0 && doubtful(lower, rank: r)) { return nil }
        // Un nom propre au milieu d'une phrase : on n'y touche pas.
        if let f = word.first, f.isUppercase, !Self.atSentenceStart(before, word: word) { return nil }
        guard isMisspelled(word) else { return nil }
        // Un vrai mot dans l'autre langue (de l'anglais au milieu du français) : on n'y touche pas.
        if let l2 = second, !isMisspelled(word, in: l2) { return nil }
        let ns = word as NSString
        // Le début d'un vrai mot (« minu » → minute) : on ne corrige pas, la barre propose la suite.
        // Sauf si un mot très courant est à une faute près (« plur » → « pour », pas « pluriel ») : voir plus bas.
        let prefixOf = listCompletions(word, limit: 1).first
        let skipChecker = fast || Self.t("noGuesses", 0) > 0
        var guesses = skipChecker ? [] : (checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: language) ?? [])
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
        // Et toutes les fautes de frappe courantes, pour n'importe quel mot (sans attendre qu'iOS les propose) :
        // deux lettres inversées, une touche voisine, une lettre en trop, une lettre oubliée.
        for cand in typoVariants(lower) where !pool.contains(where: { $0.lowercased() == cand }) { pool.append(cand) }
        // Plusieurs touches voisines dans le même mot (« encprz » → « encore ») : les mots de même longueur dont
        // chaque lettre est près de l'endroit où le doigt s'est posé.
        var fromTouch = Set<String>()
        if Self.t("tScan", 1) > 0, let touch, let own = touch.cost(lower) {
            for cand in touchScan(lower, touch: touch, own: own) {
                fromTouch.insert(cand.lowercased())
                if !pool.contains(where: { $0.lowercased() == cand.lowercased() }) { pool.append(cand) }
            }
        }
        var best: (word: String, score: Double, rank: Int)?
        let fromChecker = Set(guesses.map { $0.lowercased() })
        for g in pool {
            let gl = g.lowercased()
            guard !g.contains(" "), !g.contains("-") else { continue }
            // Un mot que la liste ne connaît pas (formes conjuguées, pluriels : « reconnues ») mais que le
            // correcteur d'iOS propose : accepté comme un mot peu courant.
            let d = typoDistance(gl, lower)
            // Un mot moins courant (« largeur ») : accepté s'il n'est qu'à une touche voisine du mot tapé, même longueur.
            let rareOK = Self.t("rareSub", 1) > 0 && d <= 1 && gl.count == lower.count && lower.count >= 5
            guard let r = rank[gl] ?? (fromChecker.contains(gl) && gl.count >= 6 ? 14_000 : nil), r < (rareOK ? 30_000 : 15_000) else { continue }
            let n = lower.count
            let touchAllowed = fromTouch.contains(gl) ? (n >= 8 ? 3 : (n >= 5 ? 2 : 1)) : 0
            guard d <= max(allowed, touchAllowed) else { continue }
            // Deux lettres inversées (« reocnnues ») : chaque doigt a bien visé sa touche, juste dans le désordre.
            let swapped = Self.isSwap(gl, lower)
            // La première lettre change rarement : seulement si le doigt était vraiment entre deux touches.
            var score = lm?.score(gl, before: before) ?? -log(Double(r) + 30)
            // Le mot d'avant : ce que tu écris d'habitude après lui passe devant (« bonne j » → « journée »).
            if let prev { score += log(1 + Double(KBWordStore.shared.pair(prev, gl))) * 0.9 }
            score += log(1 + Double(KBWordStore.shared.count(gl))) * 0.3
            if swapped {
                score -= 0.8
            } else if let c = touch?.cost(gl), let own = touch?.cost(lower) {
                let extra = c - own
                // La première lettre : le doigt entre deux touches, ou une touche voisine vers un mot très courant
                // (« gompris » → « compris »).
                if gl.first != lower.first && extra > (r < 3_000 ? Self.t("firstTouch", 3.6) : 1.2) { continue }
                // Une touche trop loin du doigt : pas une faute de frappe. Un peu plus de marge pour un mot très
                // courant (en tapant vite, le pouce tombe souvent sur la touche d'à côté : « courznt »).
                if extra > (r < 3_000 ? 8.5 : (n >= 7 ? Self.t("extraLong", 7) : 6)) { continue }
                score -= extra * 0.6
            } else {
                // Sans les touchers : la première lettre ne change que vers une touche voisine et un mot très courant.
                if gl.first != lower.first {
                    guard Self.t("firstNoTouch", 1) > 0, d <= 1, r < 1_500, gl.count == lower.count,
                          let a = gl.first, let b = lower.first, neighbors(a, b) else { continue }
                    score -= 1
                }
                score -= Double(d) * 1.5
            }
            if best == nil || score > best!.score { best = (g, score, r) }
        }
        // Rien d'une seule faute : d'abord les cas sûrs (l'apostrophe oubliée, deux mots collés tels quels), puis
        // deux fautes dans un mot long, puis deux mots collés dont l'un a une faute.
        if best == nil, prefixOf == nil {
            // L'apostrophe oubliée devant un mot courant (« sactiver » → « s’activer », « lavion » → « l’avion »).
            if language.hasPrefix("fr"), let e = genericElision(lower) { return matchCase(e, like: word) }
            // L'espace oubliée (« bonjourtoi » → « bonjour toi », « jaiete » → « j’ai été ») ou ratée, la lettre juste
            // au-dessus de la barre d'espace (« auncourant » → « au courant », « jensuis » → « je suis »).
            if word.count >= 5 {
                let sp = [exactSplit(lower), nearSpaceSplit(lower, typo: false)].compactMap { $0 }.min { $0.1 < $1.1 }
                if let sp { return matchCase(sp.0, like: word) }
            }
            // Deux fautes dans un mot long (« vrizment » → « vraiment », « mzitnenant » → « maintenant »).
            if Self.t("scan2", 1) > 0, language.hasPrefix("fr") || language.hasPrefix("en") {
                for (cand, r, d) in twoTypoScan(lower) {
                    var score = lm?.score(cand, before: before) ?? -log(Double(r) + 30)
                    score -= Double(d) * 1.5
                    if cand.first != lower.first { score -= 1.5 }
                    if let c = touch?.cost(cand), let own = touch?.cost(lower) {
                        let extra = c - own
                        if extra > 9 { continue }
                        score -= extra * 0.4
                    }
                    if best == nil || score > best!.score { best = (cand, score, r) }
                }
            }
        }
        // Le début d'un mot rare (« plur » → pluriel) : on ne corrige que vers un mot bien plus courant que lui.
        if let p = prefixOf {
            let pr = rank[p.lowercased()] ?? 30_000
            guard let b = best, b.rank < 3_000, b.rank * 8 < pr else { return nil }
        }
        // Deux mots collés dont l'un a une touche voisine (« lenremplaczment » → « le remplacement »,
        // « largzurnest » → « largeur est », « alorsnedtce » → « alors est-ce »).
        if best == nil, Self.t("spaceSplit", 1) > 0, word.count >= 5, let sp = nearSpaceSplit(lower, typo: Self.t("splitTypo", 1) > 0) {
            return matchCase(sp.0, like: word)
        }
        if best == nil, !(fast || Self.t("noGuesses", 0) > 0), word.count >= 4, let l2 = second {
            // Rien en français : peut-être une faute de frappe en anglais (et inversement). Seulement une touche voisine.
            let g2 = checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: l2) ?? []
            for g in g2.prefix(4) {
                let gl = g.lowercased()
                guard !g.contains(" "), !g.contains("-"), gl.first == lower.first, typoDistance(gl, lower) <= 1 else { continue }
                if let c = touch?.cost(gl), let own = touch?.cost(lower), c - own > 3 { continue }
                return matchCase(g, like: word)
            }
        }
        // « cest » (sans apostrophe, présent dans la liste de mots) : toujours avec son apostrophe.
        if let b = best, let c = Self.contractions[String(language.prefix(2))]?[b.word.lowercased()], !Self.ambiguous.contains(b.word.lowercased()) {
            return c.hasPrefix("I") ? c : matchCase(c, like: word)
        }
        return best.map { matchCase($0.word, like: word) }
    }

    /// Même lettre, seul l'accent change (« é » et « e ») : pas une faute de frappe.
    static func sameBase(_ a: Character, _ b: Character) -> Bool {
        String(a).folding(options: .diacriticInsensitive, locale: nil) == String(b).folding(options: .diacriticInsensitive, locale: nil)
    }

    /// Un infinitif (« aller », « venir », « prendre », « voir ») : « a » derrière est presque toujours « à ».
    static func isInfinitive(_ w: String) -> Bool {
        guard w.count >= 4 else { return false }
        return ["aller", "venir", "partir", "commencer", "continuer", "réussir", "arriver", "penser", "jouer", "apprendre",
                "aider", "servir", "rester", "chercher", "passer", "donner", "parler", "écrire", "envoyer", "monter",
                "descendre", "rentrer", "retourner", "habiter", "travailler", "manger", "dormir", "courir"].contains(w)
    }

    /// Les élisions les plus courantes, écrites sans apostrophe, avec leur forme correcte. L'ordre départage.
    private static let elisions: [(String, String)] = [
        ("cest", "c’est"), ("jai", "j’ai"), ("nai", "n’ai"), ("nest", "n’est"), ("quil", "qu’il"), ("cetait", "c’était"),
        ("quon", "qu’on"), ("qua", "qu’à"), ("quelle", "qu’elle"), ("quun", "qu’un"), ("quune", "qu’une"), ("jen", "j’en"),
        ("jy", "j’y"), ("ny", "n’y"), ("nen", "n’en"), ("na", "n’a"), ("sil", "s’il"), ("sest", "s’est"), ("lai", "l’ai"),
        ("lon", "l’on"), ("dun", "d’un"), ("dune", "d’une"), ("jetais", "j’étais"), ("javais", "j’avais"), ("jaime", "j’aime"),
        ("maime", "m’aime"), ("ma", "m’a"), ("tas", "t’as"), ("tes", "t’es"), ("taime", "t’aime"), ("jarrive", "j’arrive"),
        ("jespere", "j’espère"), ("cetait", "c’était"), ("jattends", "j’attends"), ("jaurais", "j’aurais"),
    ]

    /// L'élision écrite sans l'apostrophe, ou avec le n à sa place (AZERTY : touches voisines), avec au plus une
    /// touche voisine ratée ailleurs : « cedt » → « c’est », « nnzi » → « n’ai », « jzi » → « j’ai », « qua » → « qu’à ».
    private func elisionFix(_ lower: String, before: String) -> String? {
        // Seulement si le mot tapé n'est pas déjà un mot courant (« tes », « ma », « na » restent).
        if let r = rank[lower], r < 8_000 { return nil }
        var best: (String, Int)?
        for (i, (plain, full)) in Self.elisions.enumerated() {
            // Les formes de deux lettres (« ma », « na ») et celles qui sont aussi un vrai mot (« quelle », « tes »)
            // ne servent pas : « queloe » est « quelle », pas « qu’elle ».
            guard plain.count >= 3, (rank[plain] ?? Int.max) > 3_000 else { continue }
            let apos = full.firstIndex(of: "’").map { full.distance(from: full.startIndex, to: $0) } ?? 1
            var forms = [plain]
            // Le n tapé à la place de l'apostrophe (seulement en AZERTY, où ils sont voisins).
            if rows.first == "azertyuiop" { var w = Array(plain); w.insert("n", at: apos); forms.append(String(w)) }
            for f in forms {
                guard abs(f.count - lower.count) <= 0, f.first == lower.first else { continue }
                let d = typoDistance(f.folding(options: .diacriticInsensitive, locale: nil), lower)
                guard d <= 1 else { continue }
                let score = d * 100 + i
                if best == nil || score < best!.1 { best = (full, score) }
            }
        }
        return best?.0
    }

    /// Les mots d'une lettre (absents de la liste) qui peuvent former le début d'une coupure.
    private static let oneLetter: [String: Set<String>] = ["fr": ["a", "à", "y", "j"], "en": ["a", "i"]]

    /// Un mot court qui existe mais n'a rien à faire là (« il faut sue » → « que », « pas fu » → « du ») : une touche
    /// voisine donne un mot très courant que la phrase attend nettement plus. Avant la vérification « mot anglais »,
    /// car « sue » ou « fu » existent aussi en anglais.
    private func shortContextFix(_ word: String, before: String, touch: KBTouchModel?) -> String? {
        guard let lm, word != word.uppercased() || word.count == 1 else { return nil }
        let lower = word.lowercased()
        let own = rank[lower] ?? Int.max
        guard own > 2_000, !known.contains(lower), KBWordStore.shared.count(lower) == 0 else { return nil }
        // Il faut un vrai contexte (au moins un mot avant) pour juger.
        guard Self.previousWord(before, word: word) != nil else { return nil }
        // Un mot absent du modèle : estimé d'après sa fréquence dans la liste (pas -20, qui ferait tout corriger).
        let ownScore = lm.score(lower, before: before) ?? (own == Int.max ? -20 : -log(Double(own) + 30) - 2)
        let chars = Array(lower)
        let letters = Set(rows.joined())
        var best: (String, Double)?
        for i in 0..<chars.count {
            for k in letters where k != chars[i] && neighbors(k, chars[i]) {
                var w = chars; w[i] = k
                let c = String(w)
                guard let r = rank[c], r < 150, let sc = lm.score(c, before: before) else { continue }
                if let cc = touch?.cost(c), let oc = touch?.cost(lower), cc - oc > 4 { continue }
                if sc - ownScore >= Self.t("shortDelta", 6), best == nil || sc > best!.1 { best = (c, sc) }
            }
        }
        return best.map { matchCase($0.0, like: word) }
    }

    /// Les mots de la liste à une faute de frappe de `lower` : inversion de deux lettres voisines, touche voisine
    /// sur le clavier, lettre doublée ou en trop, lettre oubliée. Les formes accentuées comptent aussi (« reponse » → « réponse »).
    /// Deux mots collés sans espace, chacun éventuellement sans son apostrophe ou ses accents.
    private func exactSplit(_ lower: String) -> (String, Int)? {
        let chars = Array(lower)
        guard chars.count >= 4 else { return nil }
        var split: (String, Int)?
        for i in 2..<(chars.count - 1) {
            let a = String(chars[..<i]), b = String(chars[i...])
            guard let pa = resolvePart(a, typo: false), let pb = resolvePart(b, typo: false) else { continue }
            let sc = max(pa.1, pb.1)
            if split == nil || sc < split!.1 { split = (pa.0 + " " + pb.0, sc) }
        }
        return split
    }

    /// Deux mots séparés par la lettre juste au-dessus de la barre d'espace (c, v, b, n) au lieu de l'espace.
    /// Avec `typo`, l'un des deux mots (5 lettres ou plus) peut avoir une touche voisine.
    private func nearSpaceSplit(_ lower: String, typo: Bool) -> (String, Int)? {
        let chars = Array(lower)
        guard chars.count >= 5 else { return nil }
        let nearSpace: Set<Character> = ["c", "v", "b", "n"]
        var split: (String, Int)?
        for i in 1..<(chars.count - 1) where nearSpace.contains(chars[i]) {
            let a = String(chars[..<i]), b = String(chars[(i + 1)...])
            guard b.count >= 2 else { continue }
            let oneA = Self.oneLetter[String(language.prefix(2))]?.contains(a) == true
            let pa: (String, Int)? = oneA ? (a, 50) : resolvePart(a, typo: typo && a.count >= 5)
            guard let pa, let pb = resolvePart(b, typo: typo && b.count >= 5) else { continue }
            // Une seule faute de frappe en tout.
            if pa.1 >= 20_000 && pb.1 >= 20_000 { continue }
            let sc = max(pa.1, pb.1)
            if split == nil || sc < split!.1 { split = (pa.0 + " " + pb.0, sc) }
        }
        return split
    }

    /// Un morceau d'un mot collé (« jai », « ete », « edtce », « largzur ») : le mot qu'il devait être, et un rang
    /// (plus petit = plus sûr). Avec `typo`, une touche voisine est permise (moins sûr : rang + 20 000).
    private func resolvePart(_ s: String, typo: Bool) -> (String, Int)? {
        if let i = accented[s], i < 8_000, i < (rank[s] ?? .max) { return (words[i], i) }
        if let r = rank[s], r < 8_000 { return (s, r) }
        let lang = String(language.prefix(2))
        if s.count >= 3, !Self.ambiguous.contains(s), let c = Self.contractions[lang]?[s] { return (c, 300) }
        if lang == "fr", let h = Self.frHyphen[s] { return (h, 300) }
        guard typo, s.count >= 5 else { return nil }
        if lang == "fr", let h = Self.frHyphen.first(where: { $0.key.count == s.count && typoDistance($0.key, s) <= 1 })?.value { return (h, 20_300) }
        // Un mot avec une touche voisine : 6 lettres au moins (« tiver » ne devient pas « hiver » : « sactiver »).
        guard s.count >= 6 else { return nil }
        if let fb = typoVariants(s).filter({ $0.count == s.count && typoDistance($0.lowercased(), s) <= 1 && !$0.contains("-") })
            .min(by: { (rank[$0] ?? .max) < (rank[$1] ?? .max) }), let rb = rank[fb], rb < 30_000 { return (fb, rb + 20_000) }
        return nil
    }

    /// L'apostrophe oubliée devant un mot courant qui commence par une voyelle : « sactiver » → « s’activer »,
    /// « lavion » → « l’avion », « jarrive » → « j’arrive ». Le reste fait au moins 4 lettres (« set » reste).
    private func genericElision(_ lower: String) -> String? {
        guard language.hasPrefix("fr"), Self.t("genElision", 1) > 0, lower.count >= 5, rank[lower] == nil else { return nil }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y", "h", "é", "è", "ê", "à", "â", "î", "ô", "û"]
        var best: (String, Int)?
        for p in ["qu", "c", "d", "j", "l", "m", "n", "s", "t"] where lower.hasPrefix(p) {
            let rest = String(lower.dropFirst(p.count))
            guard rest.count >= 4, let f = rest.first, vowels.contains(f) else { continue }
            var r = rank[rest]
            var form = rest
            if r == nil, let i = accented[rest] { r = i; form = words[i] }
            guard let rr = r, rr < 15_000 else { continue }
            if best == nil || rr < best!.1 { best = (p + "’" + form, rr) }
        }
        return best?.0
    }

    /// Les mots courants de longueur voisine, à deux fautes de frappe au plus du mot tapé : même première lettre
    /// (ou une touche voisine, pour un mot long et courant). Rapide : seulement les mots rangés par première
    /// lettre et longueur, et chaque comparaison s'arrête dès qu'elle dépasse deux fautes.
    private func twoTypoScan(_ lower: String) -> [(String, Int, Int)] {
        let x = Array(lower.folding(options: .diacriticInsensitive, locale: nil))
        let n = x.count
        guard n >= 5, n <= 14, let f0 = x.first else { return [] }
        var firsts: [Character] = [f0]
        if n >= 6 { for k in Set(rows.joined()) where k != f0 && neighbors(k, f0) { firsts.append(k) } }
        var out: [(String, Int, Int)] = []
        for f in firsts {
            // Même longueur seulement : deux touches voisines, ou deux lettres inversées et une touche voisine
            // (une lettre en plus ou en moins avec une autre faute donne trop de mots possibles : « moeiw » → « mois »).
            for len in [n] {
                for (i, c) in byFirstLen["\(f)\(len)"] ?? [] {
                    // Un mot de 5 lettres : seulement vers un mot très courant (« qiakd » → « quand »).
                    if n == 5 && i >= 1_000 { continue }
                    if f != f0 && i >= 8_000 { continue }
                    let d = boundedTypoDistance(c, x, limit: 2)
                    guard d >= 1, d <= 2 else { continue }
                    let w = words[i]
                    guard !w.contains("-"), !w.contains("’"), !w.contains("'") else { continue }
                    out.append((w, i, d))
                }
            }
        }
        return out
    }

    /// `typoDistance`, mais arrêtée dès qu'elle dépasse `limit` (renvoie alors `limit + 1`).
    private func boundedTypoDistance(_ x: [Character], _ y: [Character], limit: Int) -> Int {
        if abs(x.count - y.count) > limit { return limit + 1 }
        if x.isEmpty || y.isEmpty { return max(x.count, y.count) }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            var rowMin = Int.max
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] || Self.sameBase(x[i - 1], y[j - 1]) ? 0 : (neighbors(x[i - 1], y[j - 1]) ? 1 : 2)
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
                rowMin = min(rowMin, d[i][j])
            }
            if rowMin > limit { return limit + 1 }
        }
        return d[x.count][y.count]
    }

    private func typoVariants(_ lower: String) -> [String] {
        let x = Array(lower)
        guard x.count >= 3, x.count <= 20 else { return [] }
        var seen = Set<String>(), out: [String] = []
        var cap = 15_000
        func add(_ w: [Character]) {
            let s = String(w)
            guard s != lower, seen.insert(s).inserted else { return }
            if let r = rank[s], r < cap { out.append(s) }
            if let a = accented[s], words[a] != s, rank[words[a]] ?? .max < cap { out.append(words[a]) }
        }
        let letters = Array(Set(rows.joined()))
        for i in 0..<x.count {
            if i + 1 < x.count, x[i] != x[i + 1] { var w = x; w.swapAt(i, i + 1); add(w) }       // inversion
            cap = x.count >= 5 && Self.t("rareSub", 1) > 0 ? 30_000 : 15_000                        // touche voisine :
            for k in letters where k != x[i] && neighbors(k, x[i]) { var w = x; w[i] = k; add(w) }  // aussi les mots rares
            cap = 15_000
            var d = x; d.remove(at: i); add(d)                                                    // lettre en trop
        }
        for i in 0...x.count {                                                                   // lettre oubliée
            for k in letters { var w = x; w.insert(k, at: i); add(w) }
        }
        return out
    }

    /// Deux lettres voisines inversées, rien d'autre (« teh » / « the »).
    static func isSwap(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard x.count == y.count, x.count >= 2 else { return false }
        let diff = (0..<x.count).filter { x[$0] != y[$0] }
        return diff.count == 2 && diff[1] == diff[0] + 1 && x[diff[0]] == y[diff[1]] && x[diff[1]] == y[diff[0]]
    }

    private static let englishTwo: Set<String> = ["am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it",
        "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "we", "ya", "yo", "ah", "eh", "ha", "uh", "ox",
        "ad", "ex", "id", "re", "vs", "tv", "pc", "pm", "hm", "mm"]

    /// Les mots de deux lettres (« fe » → « de », « ot » → « to ») : seulement vers un des mots les plus courants,
    /// une touche voisine du doigt ou deux lettres inversées, et si le mot tapé est lui-même rare.
    private func twoLetterFix(_ word: String, before: String, touch: KBTouchModel?) -> String? {
        let lower = word.lowercased()
        guard word != word.uppercased() || word.count == 1 else { return nil }
        let own = rank[lower] ?? Int.max
        guard own > 3_000, !known.contains(lower), KBWordStore.shared.count(lower) == 0 else { return nil }
        // Un vrai mot anglais courant (« is », « to ») reste ; pas une abréviation que le correcteur anglais accepte
        // aussi (« cz », « ke »).
        if second != nil, Self.englishTwo.contains(lower) { return nil }
        let chars = Array(lower)
        var cands: Set<String> = [String(chars.reversed())]
        let letters = Set(rows.joined())
        for i in 0..<2 { for k in letters where k != chars[i] && neighbors(k, chars[i]) { var w = chars; w[i] = k; cands.insert(String(w)) } }
        // Et leur forme accentuée (« cz » → « ca » → « ça »).
        for c in cands { if let a = accented[c], a < 1_000 { cands.insert(words[a]) } }
        var best: (String, Double)?
        for c in cands {
            guard let r = rank[c], r < (c.allSatisfy({ $0.isASCII }) ? 300 : 1_000) else { continue }
            var score = lm?.score(c, before: before) ?? -log(Double(r) + 30)
            if !Self.isSwap(c, lower), let cc = touch?.cost(c), let oc = touch?.cost(lower) {
                if cc - oc > 5 { continue }
                score -= (cc - oc) * 0.6
            }
            if best == nil || score > best!.1 { best = (c, score) }
        }
        return best.map { matchCase($0.0, like: word) }
    }

    /// Les mots courants à une lettre près, dont la lettre changée est une touche proche de l'endroit où le doigt s'est posé.
    private func nearbyWords(_ lower: String, touch: KBTouchModel) -> [String] {
        let chars = Array(lower)
        guard chars.count == touch.points.count, chars.count <= 14 else { return [] }
        var out: [String] = []
        for (i, p) in touch.points.enumerated() {
            for (k, cs) in touch.centers where k != chars[i] {
                guard cs.contains(where: { c in
                    let dx = (p.x - c.x) / touch.keyW, dy = (p.y - c.y) / touch.keyH
                    return dx * dx + dy * dy < 1.0                  // moins d'une touche du doigt
                }) else { continue }
                var w = chars; w[i] = k
                let cand = String(w)
                if let r = rank[cand], r < 15_000 { out.append(cand) }
                // Et la même avec l'accent (« apres » posé sur le e → « après »).
                if let a = accented[cand], words[a] != cand, rank[words[a]] ?? .max < 15_000 { out.append(words[a]) }
            }
        }
        return out
    }

    /// Les mots courants de même longueur dont chaque lettre est proche du toucher correspondant.
    /// Rapide (appelé à chaque espace sur le fil principal) : les mots sont déjà rangés par première lettre et longueur,
    /// et on abandonne un mot dès qu'il devient trop loin des touchers.
    private func touchScan(_ lower: String, touch: KBTouchModel, own: Double) -> [String] {
        let n = lower.count
        guard n >= 4, n <= 14, n == touch.points.count, let p0 = touch.points.first else { return [] }
        let sx = Double(touch.keyW * 0.55), sy = Double(touch.keyH * 0.55)
        guard sx > 0, sy > 0 else { return [] }
        var near: [Character: Double] = [:]
        func dist(_ ch: Character, _ i: Int) -> Double? {
            guard let ks = touch.centers[ch], !ks.isEmpty else { return nil }
            let p = touch.points[i]
            return ks.map { k -> Double in
                let dx = Double(p.x - k.x) / sx, dy = Double(p.y - k.y) / sy
                return dx * dx + dy * dy
            }.min()
        }
        for (k, cs) in touch.centers where cs.contains(where: { hypot(($0.x - p0.x) / touch.keyW, ($0.y - p0.y) / touch.keyH) < 1.1 }) {
            near[k] = 0
        }
        // Un mot long supporte deux touches voisines ratées (« chzngrr » → « changer ») : plus de marge.
        let limit = own + (n >= 6 ? Self.t("tMaxLong", 7.5) : Self.t("tMax", 4))
        let me = Array(lower)
        // Distances déjà calculées : lettre × position.
        var memo: [Int: Double] = [:]
        var found: [(String, Double)] = []
        for first in near.keys {
            for (i, c) in byFirstLen["\(first)\(n)"] ?? [] where c != me {
                var total = 0.0
                var ok = true
                for (j, ch) in c.enumerated() {
                    let key = j * 0x10000 + Int(ch.unicodeScalars.first?.value ?? 0)
                    let d: Double
                    if let m = memo[key] { d = m } else if let v = dist(ch, j) { d = v; memo[key] = v } else { ok = false; break }
                    total += d
                    if total >= limit { ok = false; break }
                }
                if ok { found.append((words[i], total)) }
            }
        }
        return found.sorted { $0.1 < $1.1 }.prefix(12).map { $0.0 }
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
        guard let pa = position(fa), let pb = position(fb), abs(pa.0 - pb.0) <= 1 else { return false }
        let xa = (pa.0 < rowInsets.count ? rowInsets[pa.0] : 0) + Double(pa.1)
        let xb = (pb.0 < rowInsets.count ? rowInsets[pb.0] : 0) + Double(pb.1)
        return abs(xa - xb) <= 1.01
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
                let cost = x[i - 1] == y[j - 1] || Self.sameBase(x[i - 1], y[j - 1]) ? 0 : (neighbors(x[i - 1], y[j - 1]) ? 1 : 2)
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
        let englishHere = language.hasPrefix("fr") && second != nil && sentenceIsEnglish(before, word: word)
        let fix = correction(for: word, before: before, touch: touch)
        if let fix, fix != word {
            out = [word, fix]
            best = 1
        } else {
            out = [word]
        }
        // L'apostrophe oubliée, même quand le mot existe aussi (« ill » → « I’ll ») : proposée dans la barre.
        if !englishHere, let c = contraction(word), !out.contains(c) { out.insert(c, at: min(1, out.count)); if best != nil { best = out.firstIndex(of: fix ?? "") } }
        // L'accent oublié (« a » → « à ») : toujours proposé dans la barre, même quand on ne le corrige pas seul.
        if !englishHere, let a = accentForm(word) {
            let c = matchCase(a.word, like: word)
            if !out.contains(c) { out.insert(c, at: min(1, out.count)); if best != nil { best = out.firstIndex(of: fix ?? "") } }
        }
        var completions = KBWordStore.shared.completions(word, limit: 2).map { matchCase($0, like: word) }
        // Les noms de tes contacts qui commencent ainsi (« Char » → « Charlotte »), en premier.
        if word.count >= 2 {
            let key = word.lowercased()
            for n in (useNames ? names : [:]).filter({ $0.key.hasPrefix(key) && $0.key != key }).map(\.value).sorted().prefix(1) { completions.insert(n, at: 0) }
        }
        var pool = englishHere ? [] : listCompletions(word, limit: lm == nil ? 3 : Int(Self.t("compPool", 14)))
        if englishHere, let l2 = second {
            pool = (checker.completions(forPartialWordRange: range, in: word, language: l2) ?? [])
                .filter { $0.lowercased() != word.lowercased() && !$0.contains(" ") }
        } else if let lm {
            // Les fins de mot qui collent à la phrase passent devant (« bonne jour » → « journée »).
            let key = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            for w in lm.next(before: before, limit: 24) where w.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).hasPrefix(key)
                && w.count > word.count && !pool.contains(w) { pool.append(w) }
            pool = pool.map { ($0, lm.score($0, before: before) ?? -20) }.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        for c in pool.prefix(3) where !completions.contains(where: { $0.lowercased() == c.lowercased() }) { completions.append(c) }
        if completions.isEmpty {
            completions = (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
                .filter { $0.lowercased() != word.lowercased() && !$0.contains(" ") }
        }
        completions = completions.map { names[$0.lowercased()] == $0 ? $0 : matchCase($0, like: word) }
        for c in completions where out.count < 3 && !out.contains(c) { out.append(c) }
        let guessLang = englishHere ? (second ?? language) : language
        if out.count < 3, fix == nil, isMisspelled(word, in: guessLang) {
            for g in checker.guesses(forWordRange: range, in: word, language: guessLang) ?? [] where out.count < 3 && !out.contains(g) {
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
