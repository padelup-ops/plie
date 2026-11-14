import UIKit

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
        guard let lm, r > Int(Self.t("doubtRank", 99_999)) else { return false }
        return lm.rank(w) == nil
    }

    /// La pénalité du glisser pour un mot douteux : forte si le correcteur d'iOS ne le connaît pas non plus
    /// (« sdi », « rapelle »), légère pour un vrai mot rare (« chiming »).
    private var spellCache: [String: Bool] = [:]
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
        return ok ? Self.t("gJunkValid", Self.t("gJunk", 0)) : Self.t("gJunk", 0)
    }

    private let checker = UITextChecker()
    private var known = Set<String>()
    private var replacements: [String: String] = [:]
    /// Les noms de tes contacts (tels qu'écrits dans Contacts), par forme en minuscules.
    private var names: [String: String] = [:]
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
                let junk = glideJunk(words[i], rank: i)
                let score = -Double(loc * loc) * Self.t("gLoc", 7) - Double(shape) * Self.t("gShape", 6) + prior * Self.t("gPrior", 0.6)
                    + mine - Double(misses) * 2 - Double(missedTurns) * Self.t("gTurn", 2.2) - lenPenalty * Self.t("gLen", 5) - junk
                scored.append((words[i], score))
            }
        }
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

    /// Le remplacement de texte de l'utilisateur pour ce mot, s'il en a un.
    func replacement(for word: String) -> String? { replacements[word.lowercased()] }

    /// La correction à appliquer quand on termine le mot (espace, ponctuation), ou nil.
    func correction(for word: String, before: String, touch: KBTouchModel? = nil) -> String? {
        let low = word.lowercased()
        let prev = Self.previousWord(before, word: word)?.lowercased()
        // Tes remplacements de texte (Réglages > Clavier) : toujours appliqués, même courts (« ty » → « Thank you »).
        if let r = replacements[low] { return r }
        // Les mots à trait d'union tapés d'un bloc : « estce » → « est-ce », « peutetre » → « peut-être ».
        if language.hasPrefix("fr"), let h = Self.frHyphen[low.replacingOccurrences(of: "'", with: "’")] {
            return matchCase(h, like: word)
        }
        // Un prénom de tes contacts tapé en minuscules (et qui n'est pas un mot courant) : la majuscule.
        if word == low, let n = names[low], rank[low] == nil, n.lowercased() == low { return n }
        // Tes mots à toi (tapés plusieurs fois, jamais corrigés) : on n'y touche plus.
        if KBWordStore.shared.count(low) >= 3 { return nil }
        // « a » ou « à » d'après le mot d'avant : « je vais a » → « je vais à », « il a » reste « il a ».
        if language.hasPrefix("fr"), low == "a", let prev, Self.towardA.contains(prev) { return matchCase("à", like: word) }
        if language.hasPrefix("fr"), low == "a", let lm, let sa = lm.score("à", before: before), let s0 = lm.score("a", before: before),
           sa > s0 + 1.6 { return matchCase("à", like: word) }
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
        // Et toutes les fautes de frappe courantes, pour n'importe quel mot (sans attendre qu'iOS les propose) :
        // deux lettres inversées, une touche voisine, une lettre en trop, une lettre oubliée.
        for cand in typoVariants(lower) where !pool.contains(where: { $0.lowercased() == cand }) { pool.append(cand) }
        // Plusieurs touches voisines dans le même mot (« encprz » → « encore ») : les mots de même longueur dont
        // chaque lettre est près de l'endroit où le doigt s'est posé.
        var fromTouch = Set<String>()
        if Self.t("tScan", 0) > 0, let touch, let own = touch.cost(lower) {
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
            guard let r = rank[gl] ?? (fromChecker.contains(gl) && gl.count >= 6 ? 14_000 : nil), r < 15_000 else { continue }
            let d = typoDistance(gl, lower)
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
                if gl.first != lower.first && extra > 1.2 { continue }
                // Une touche trop loin du doigt : pas une faute de frappe. Un peu plus de marge pour un mot très
                // courant (en tapant vite, le pouce tombe souvent sur la touche d'à côté : « courznt »).
                if extra > (r < 3_000 ? 8.5 : 6) { continue }
                score -= extra * 0.6
            } else {
                if gl.first != lower.first { continue }
                score -= Double(d) * 1.5
            }
            if best == nil || score > best!.score { best = (g, score, r) }
        }
        // Le début d'un mot rare (« plur » → pluriel) : on ne corrige que vers un mot bien plus courant que lui.
        if let p = prefixOf {
            let pr = rank[p.lowercased()] ?? 30_000
            guard let b = best, b.rank < 3_000, b.rank * 8 < pr else { return nil }
        }
        // L'espace oubliée : « bonjourtoi » → « bonjour toi » (deux mots courants, rien de mieux à proposer).
        if best == nil, word.count >= 5 {
            let chars = Array(lower)
            var split: (String, Int)?
            for i in 2..<(chars.count - 1) {
                let a = String(chars[..<i]), b = String(chars[i...])
                guard let ra = rank[a], let rb = rank[b], ra < 8_000, rb < 8_000 else { continue }
                let sc = max(ra, rb)
                if split == nil || sc < split!.1 { split = (a + " " + b, sc) }
            }
            if let split { return matchCase(split.0, like: word) }
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

    /// Les mots de la liste à une faute de frappe de `lower` : inversion de deux lettres voisines, touche voisine
    /// sur le clavier, lettre doublée ou en trop, lettre oubliée. Les formes accentuées comptent aussi (« reponse » → « réponse »).
    private func typoVariants(_ lower: String) -> [String] {
        let x = Array(lower)
        guard x.count >= 3, x.count <= 20 else { return [] }
        var seen = Set<String>(), out: [String] = []
        func add(_ w: [Character]) {
            let s = String(w)
            guard s != lower, seen.insert(s).inserted else { return }
            if let r = rank[s], r < 15_000 { out.append(s) }
            if let a = accented[s], words[a] != s, rank[words[a]] ?? .max < 15_000 { out.append(words[a]) }
        }
        let letters = Array(Set(rows.joined()))
        for i in 0..<x.count {
            if i + 1 < x.count, x[i] != x[i + 1] { var w = x; w.swapAt(i, i + 1); add(w) }       // inversion
            for k in letters where k != x[i] && neighbors(k, x[i]) { var w = x; w[i] = k; add(w) }  // touche voisine
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

    /// Les mots de deux lettres (« fe » → « de », « ot » → « to ») : seulement vers un des mots les plus courants,
    /// une touche voisine du doigt ou deux lettres inversées, et si le mot tapé est lui-même rare.
    private func twoLetterFix(_ word: String, before: String, touch: KBTouchModel?) -> String? {
        let lower = word.lowercased()
        guard word != word.uppercased() || word.count == 1 else { return nil }
        let own = rank[lower] ?? Int.max
        guard own > 3_000, !known.contains(lower), KBWordStore.shared.count(lower) == 0 else { return nil }
        if let l2 = second, !isMisspelled(word, in: l2) { return nil }
        let chars = Array(lower)
        var cands: Set<String> = [String(chars.reversed())]
        let letters = Set(rows.joined())
        for i in 0..<2 { for k in letters where k != chars[i] && neighbors(k, chars[i]) { var w = chars; w[i] = k; cands.insert(String(w)) } }
        var best: (String, Double)?
        for c in cands {
            guard let r = rank[c], r < 300 else { continue }
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
    private func touchScan(_ lower: String, touch: KBTouchModel, own: Double) -> [String] {
        let n = lower.count
        guard n >= 4, n <= 14, n == touch.points.count, let p0 = touch.points.first else { return [] }
        var firsts: [String] = []
        for (k, cs) in touch.centers where cs.contains(where: { hypot(($0.x - p0.x) / touch.keyW, ($0.y - p0.y) / touch.keyH) < 1.1 }) {
            firsts.append(String(k))
        }
        let maxExtra = Self.t("tMax", 5)
        var found: [(String, Double)] = []
        for f in firsts {
            for i in byFirst[f] ?? [] where i < 15_000 {
                let w = folded[i]
                guard w.count == n, w != lower, let c = touch.cost(w), c - own < maxExtra else { continue }
                found.append((words[i], c))
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
        var completions = KBWordStore.shared.completions(word, limit: 2).map { matchCase($0, like: word) }
        // Les noms de tes contacts qui commencent ainsi (« Char » → « Charlotte »), en premier.
        if word.count >= 2 {
            let key = word.lowercased()
            for n in names.filter({ $0.key.hasPrefix(key) && $0.key != key }).map(\.value).sorted().prefix(1) { completions.insert(n, at: 0) }
        }
        var pool = listCompletions(word, limit: lm == nil ? 3 : Int(Self.t("compPool", 14)))
        if let lm {
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
