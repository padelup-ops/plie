import Foundation

/// Ce que la dictée a entendu, prêt à écrire là où est le curseur, comme la dictée d'Apple :
///  - les commandes dites à voix haute (« à la ligne », « new paragraph ») deviennent des retours à la ligne ;
///  - la majuscule suit l'endroit où l'on écrit (au milieu d'une phrase, « Il fait beau » devient « il fait beau » ;
///    en début de phrase, la majuscule est mise si le moteur l'a oubliée) ;
///  - une espace devant si le texte d'avant ne finit pas par une espace, jamais deux.
/// Rien que du texte : pas de réglage, pas d'état. Vérifié par le banc d'essai (tools/bench).
enum KBDictationText {
    /// `lang` : « fr », « en », « es », « de », « sv »… (les deux premières lettres de la langue de la dictée).
    static func prepare(_ raw: String, before: String, lang: String) -> String {
        var t = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "" }
        t = applyCommands(t, lang: lang)
        // Les débuts de ligne créés par une commande prennent leur majuscule.
        t = capitalizeAfterBreaks(t)
        let lead = t.prefix { $0 == "\n" }
        var body = String(t.dropFirst(lead.count))
        let context = before.trimmingCharacters(in: .whitespaces)
        let sentenceStart = !lead.isEmpty || context.isEmpty || context.last.map { ".!?…\n".contains($0) } == true
        if sentenceStart {
            body = upperFirst(body)
        } else if let first = firstWord(body), shouldLower(first, lang: lang) {
            body = lowerFirst(body)
        }
        t = lead + body
        // Au milieu d'une phrase déjà ponctuée après le curseur, le point final de la dictée ferait doublon : on le
        // laisse quand même, comme Apple (on ne connaît pas toujours le texte d'après).
        let needsSpace: Bool
        if let last = before.last {
            let opens = "([{«“\"'’‘-/\n".contains(last)
            let startsTight = t.first.map { ",.;:!?)]}\n".contains($0) } ?? false
            needsSpace = !last.isWhitespace && !opens && !startsTight
        } else {
            needsSpace = false
        }
        return (needsSpace ? " " : "") + t
    }

    // MARK: Commandes

    private static let commands: [String: [(String, String)]] = [
        "fr": [("nouveau paragraphe", "\n\n"), ("retour à la ligne", "\n"), ("à la ligne", "\n"), ("nouvelle ligne", "\n")],
        "en": [("new paragraph", "\n\n"), ("new line", "\n"), ("newline", "\n")],
        "es": [("nuevo párrafo", "\n\n"), ("nueva línea", "\n"), ("salto de línea", "\n")],
        "de": [("neuer absatz", "\n\n"), ("neue zeile", "\n")],
        "it": [("nuovo paragrafo", "\n\n"), ("nuova riga", "\n"), ("a capo", "\n")],
        "pt": [("novo parágrafo", "\n\n"), ("nova linha", "\n")],
        "sv": [("nytt stycke", "\n\n"), ("ny rad", "\n")],
        "nl": [("nieuwe alinea", "\n\n"), ("nieuwe regel", "\n")],
    ]

    private static func applyCommands(_ text: String, lang: String) -> String {
        guard let list = commands[lang] else { return text }
        var t = text
        for (phrase, out) in list {
            let p = NSRegularExpression.escapedPattern(for: phrase).replacingOccurrences(of: " ", with: "\\s+")
            // La commande, avec la virgule que le moteur met parfois devant et la ponctuation qu'il met derrière.
            // Un point d'avant reste (« Bonjour. À la ligne » → « Bonjour.⏎ »).
            guard let re = try? NSRegularExpression(pattern: "[ \\t]*[,;:]?[ \\t]*(?<![\\p{L}\\p{N}])" + p + "(?![\\p{L}\\p{N}])[ \\t]*[,.;:!?…]*[ \\t]*",
                                                    options: [.caseInsensitive]) else { continue }
            let ns = t as NSString
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: out))
        }
        // Pas plus de deux retours de suite, pas d'espace autour.
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        t = t.replacingOccurrences(of: " \n", with: "\n").replacingOccurrences(of: "\n ", with: "\n")
        // Une dictée qui ne contient que la commande garde son retour ; sinon on ne finit pas par des espaces.
        while t.hasSuffix(" ") { t.removeLast() }
        return t
    }

    private static func capitalizeAfterBreaks(_ text: String) -> String {
        guard text.contains("\n") else { return text }
        var out = ""
        var cap = false
        for ch in text {
            if ch == "\n" { cap = true; out.append(ch); continue }
            if cap, ch.isLetter { out.append(contentsOf: String(ch).uppercased()); cap = false; continue }
            if cap, !ch.isWhitespace { cap = false }
            out.append(ch)
        }
        return out
    }

    // MARK: Majuscule

    private static func firstWord(_ s: String) -> String? {
        let w = s.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        return w.isEmpty ? nil : String(w)
    }

    private static func upperFirst(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }

    private static func lowerFirst(_ s: String) -> String {
        guard let f = s.first, f.isUppercase else { return s }
        return f.lowercased() + s.dropFirst()
    }

    /// Au milieu d'une phrase, le premier mot perd la majuscule que le moteur lui a mise — seulement si c'est un
    /// petit mot de la langue (article, pronom, préposition, verbe très courant…). Un nom propre (« Marie », « Paris »)
    /// ou un sigle garde la sienne ; « I » aussi.
    private static func shouldLower(_ word: String, lang: String) -> Bool {
        guard let f = word.first, f.isUppercase else { return false }
        // Tout en capitales (sigle) : on n'y touche pas.
        if word.count > 1, word == word.uppercased() { return false }
        let low = word.lowercased().replacingOccurrences(of: "'", with: "’")
        if lang == "en", low == "i" || low.hasPrefix("i’") { return false }
        // En allemand, les noms prennent une majuscule : seuls les petits mots la perdent (la liste n'a pas de noms).
        if let set = small[lang], set.contains(low) { return true }
        // Les élisions françaises : « L’autre », « J’ai », « C’est », « Qu’est-ce »…
        if lang == "fr", let i = low.firstIndex(of: "’") {
            return ["l", "j", "c", "d", "n", "m", "t", "s", "qu", "jusqu", "lorsqu", "puisqu"].contains(String(low[..<i]))
        }
        return false
    }

    private static let small: [String: Set<String>] = [
        "fr": ["le", "la", "les", "un", "une", "des", "du", "de", "au", "aux", "ce", "cet", "cette", "ces", "mon", "ma", "mes",
               "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs", "je", "tu", "il", "elle",
               "on", "nous", "vous", "ils", "elles", "moi", "toi", "lui", "eux", "ça", "cela", "ceci", "et", "ou", "mais", "donc",
               "or", "ni", "car", "que", "qui", "quoi", "dont", "où", "si", "comme", "quand", "lorsque", "puisque", "parce", "pour",
               "par", "avec", "sans", "sur", "sous", "dans", "en", "à", "chez", "vers", "entre", "depuis", "pendant", "avant",
               "après", "est", "sont", "suis", "es", "sommes", "êtes", "était", "étaient", "sera", "serait", "a", "ai", "as",
               "avons", "avez", "ont", "avait", "aura", "va", "vais", "vas", "allons", "allez", "vont", "fait", "fais", "faut",
               "peut", "peux", "veut", "veux", "dois", "doit", "ne", "pas", "plus", "très", "trop", "bien", "aussi", "alors",
               "ensuite", "puis", "enfin", "oui", "non", "merci", "bonjour", "bonsoir", "salut", "voilà", "voici", "ici", "là",
               "tout", "tous", "toute", "toutes", "rien", "quelque", "quelques", "chaque", "même", "autre", "encore", "déjà",
               "juste", "peut-être", "maintenant", "demain", "hier", "aujourd’hui", "ok", "d’accord", "se", "me", "te", "y"],
        "en": ["the", "a", "an", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their", "you", "he",
               "she", "it", "we", "they", "me", "him", "us", "them", "and", "or", "but", "so", "because", "if", "when", "while",
               "as", "than", "then", "that’s", "it’s", "there", "here", "what", "who", "which", "where", "why", "how", "to", "of",
               "in", "on", "at", "by", "for", "with", "from", "about", "into", "over", "after", "before", "between", "without",
               "is", "are", "was", "were", "am", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will",
               "would", "can", "could", "should", "may", "might", "must", "shall", "not", "no", "yes", "yeah", "ok", "okay",
               "just", "also", "very", "too", "really", "maybe", "please", "thanks", "thank", "hello", "hi", "hey", "well",
               "now", "today", "tomorrow", "yesterday", "let", "let’s", "don’t", "can’t", "won’t", "isn’t", "there’s", "we’re",
               "you’re", "they’re", "he’s", "she’s", "some", "any", "all", "each", "every", "more", "most", "other", "still",
               "already", "again", "only", "even", "up", "down", "out", "off", "one"],
        "es": ["el", "la", "los", "las", "un", "una", "unos", "unas", "lo", "al", "del", "de", "mi", "mis", "tu", "tus", "su",
               "sus", "nuestro", "nuestra", "yo", "tú", "él", "ella", "nosotros", "ellos", "ellas", "usted", "ustedes", "me",
               "te", "se", "nos", "le", "les", "y", "o", "pero", "porque", "que", "qué", "quien", "quién", "como", "cómo",
               "cuando", "cuándo", "donde", "dónde", "si", "sí", "no", "en", "a", "con", "sin", "por", "para", "sobre", "entre",
               "desde", "hasta", "es", "son", "soy", "eres", "está", "están", "estoy", "era", "fue", "ha", "he", "has", "han",
               "hay", "voy", "vas", "va", "vamos", "van", "muy", "más", "también", "ya", "ahora", "hoy", "mañana", "ayer",
               "gracias", "hola", "bueno", "bien", "este", "esta", "esto", "ese", "esa", "eso", "todo", "todos", "nada", "algo"],
        "de": ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "mein", "meine",
               "dein", "deine", "sein", "seine", "ihr", "ihre", "unser", "unsere", "ich", "du", "er", "es", "wir", "sie", "mich",
               "dich", "ihn", "uns", "euch", "mir", "dir", "ihm", "und", "oder", "aber", "denn", "weil", "dass", "wenn", "als",
               "wie", "was", "wer", "wo", "warum", "ob", "in", "im", "an", "am", "auf", "aus", "bei", "mit", "nach", "von",
               "vom", "zu", "zum", "zur", "für", "über", "unter", "vor", "ohne", "um", "ist", "sind", "bin", "bist", "war",
               "waren", "hat", "habe", "hast", "haben", "hatte", "wird", "werden", "kann", "kannst", "können", "muss", "soll",
               "will", "nicht", "kein", "keine", "ja", "nein", "auch", "sehr", "noch", "schon", "nur", "jetzt", "heute",
               "morgen", "gestern", "dann", "danke", "hallo", "bitte", "so", "da", "hier", "dort", "mal", "doch"],
        "sv": ["en", "ett", "den", "det", "de", "min", "mitt", "mina", "din", "ditt", "dina", "jag", "du", "han", "hon", "vi",
               "ni", "mig", "dig", "oss", "och", "eller", "men", "för", "att", "som", "när", "om", "i", "på", "av", "med",
               "till", "från", "är", "var", "har", "hade", "ska", "kan", "inte", "ja", "nej", "också", "nu", "idag", "imorgon",
               "tack", "hej", "så", "här", "där", "bara", "mycket"],
    ]
}
