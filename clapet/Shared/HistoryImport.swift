import Foundation

// MARK: - Importer un historique (Scriptable, Raccourcis, une autre app, ou l'export CSV de Foldly)
//
// On accepte à peu près tout ce qui ressemble à un historique :
//  • une ligne par jour : « 2026-10-01,52,48 » (date, plis, ouvertures), avec ou sans en-tête, séparé par , ; tab ou |
//  • une ligne par pli : « Nov 5, 2026 at 8:17 PM » ou « 2026-11-05T20:17:00 fold » (chaque ligne compte pour 1)
//  • du JSON : une liste d'objets (date + nombres), ou un objet { "2026-10-01": 52, … }

struct HistoryImport {
    struct Day: Equatable { var closes = 0; var opens = 0 }

    /// Les jours trouvés, par clé « AAAA-MM-JJ ».
    var days: [String: Day] = [:]
    /// Le fichier listait des plis un par un (et non des totaux par jour).
    var eventLog = false

    var isEmpty: Bool { days.isEmpty }
    var totalCloses: Int { days.values.reduce(0) { $0 + $1.closes } }
    var totalOpens: Int { days.values.reduce(0) { $0 + $1.opens } }
    var first: String? { days.keys.min() }
    var last: String? { days.keys.max() }

    // MARK: Lecture

    static func parse(_ text: String) -> HistoryImport {
        // Certains outils écrivent une marque invisible en tête de fichier : elle cachait l'accolade du JSON.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DateReader.guessDayFirst(trimmed.components(separatedBy: .newlines))
        if let first = trimmed.first, first == "[" || first == "{" {
            if let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
                let r = cleaned(parseJSON(json))
                if !r.isEmpty { return r }
            }
            // Un journal : un objet JSON par ligne.
            let lines = cleaned(parseJSONLines(trimmed))
            if !lines.isEmpty { return lines }
            // Du JSON abîmé (virgule en trop, morceau coupé) : les dates que l'on y reconnaît, plutôt que de le
            // lire comme un tableau à virgules.
            let found = cleaned(scan(trimmed))
            if !found.isEmpty { return found }
        }
        let r = parseLines(trimmed)
        if !r.isEmpty { return r }
        // Dernier recours : les dates que l'on reconnaît dans le texte, où qu'elles soient rangées.
        return cleaned(scan(trimmed))
    }

    /// Ne garder que des valeurs plausibles.
    private static func cleaned(_ imp: HistoryImport) -> HistoryImport {
        var r = imp
        r.days = r.days.filter { $0.value.closes >= 0 && $0.value.opens >= 0 && $0.value.closes <= 100_000 && $0.value.opens <= 100_000 && ($0.value.closes > 0 || $0.value.opens > 0) }
        return r
    }

    /// Un vrai/faux du JSON (et pas un nombre 0 ou 1).
    private static func isBool(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private static func number(_ v: Any) -> Double? {
        if isBool(v) { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Un nombre de plis : entier, entre 0 et 100 000 (écrit en nombre ou en texte).
    private static func count(_ v: Any) -> Int? {
        guard let d = number(v), d >= 0, d <= 100_000, d == d.rounded() else { return nil }
        return Int(d)
    }

    /// Une date : un texte qui se lit comme une date, ou un nombre qui a tout d'un horodatage.
    private static func dateKey(_ v: Any) -> String? {
        if let s = v as? String { return DateReader.key(from: s) }
        if !isBool(v), let n = (v as? NSNumber)?.doubleValue, n >= 1_000_000_000 { return DateReader.key(fromUnix: n) }
        return nil
    }

    /// Ce que compte un champ, d'après son nom : des ouvertures ou des plis, et à quel point on en est sûr.
    private static func meaning(_ name: String) -> (open: Bool, rank: Int)? {
        if name.contains("unfold") || name.contains("open") || name.contains("ouvert") { return (true, 3) }
        if name.contains("fold") || name.contains("close") || name.contains("shut") || name.contains("ferm") || name.contains("pli") { return (false, 3) }
        if ["u", "o"].contains(name) { return (true, 2) }
        if name.contains("count") || ["f", "n", "c", "num", "number", "nb", "amount", "times", "flips", "value"].contains(name) { return (false, 2) }
        if name == "total" { return (false, 1) }
        return nil
    }

    private static func saysOpen(_ s: String) -> Bool {
        let low = s.lowercased()
        return low.contains("unfold") || low.contains("open") || low.contains("ouvert")
    }

    private static func parseJSON(_ json: Any) -> HistoryImport {
        var r = HistoryImport()
        func add(_ key: String, closes: Int, opens: Int) {
            var d = r.days[key] ?? Day()
            d.closes += closes
            d.opens += opens
            r.days[key] = d
        }
        func merge(_ other: HistoryImport) {
            for (key, d) in other.days { add(key, closes: d.closes, opens: d.opens) }
            if other.eventLog { r.eventLog = true }
        }
        func fromObject(_ o: [String: Any], dateHint: String? = nil) {
            let low = Dictionary(o.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            let ordered = low.sorted { $0.key < $1.key }
            var key = dateHint.flatMap { DateReader.key(from: $0) }
            var dateField: String?
            // La date : d'abord un champ au nom parlant, puis n'importe quel texte qui se lit comme une date,
            // puis un nombre qui a tout d'un horodatage.
            if key == nil {
                for name in ["date", "day", "time", "timestamp", "datetime", "t", "ts", "at", "when", "created", "start"] {
                    if let v = low[name], let d = dateKey(v) { key = d; dateField = name; break }
                }
            }
            if key == nil {
                for (name, v) in ordered {
                    if let s = v as? String, let d = DateReader.key(from: s) { key = d; dateField = name; break }
                }
            }
            if key == nil {
                for (name, v) in ordered where !(v is String) {
                    if let d = dateKey(v) { key = d; dateField = name; break }
                }
            }
            guard let key else {
                // Pas de date ici : l'historique est peut-être rangé plus bas.
                for (_, v) in ordered where v is [Any] || v is [String: Any] { merge(parseJSON(v)) }
                return
            }
            var closes: Int?, opens: Int?
            var closesRank = 0, opensRank = 0
            var loose: [Int] = []
            var isOpen: Bool?
            for (name, v) in ordered where name != dateField {
                if let s = v as? String, ["type", "event", "action", "kind", "state", "status", "position"].contains(name) {
                    isOpen = saysOpen(s)
                    continue
                }
                if isBool(v), let b = v as? Bool, let m = meaning(name) {
                    // { "open": true } : une ouverture ; { "folded": false } aussi.
                    isOpen = m.open ? b : !b
                    continue
                }
                if dateHint != nil, let list = v as? [Any], let m = meaning(name) {
                    // { "2026-10-27": { "folds": [ … ], "unfolds": [ … ] } } : un élément par pli.
                    if m.open { opens = list.count; opensRank = 4 } else { closes = list.count; closesRank = 4 }
                    continue
                }
                guard let n = count(v) else { continue }
                if let m = meaning(name) {
                    if m.open {
                        if m.rank > opensRank { opens = n; opensRank = m.rank }
                    } else if m.rank > closesRank {
                        closes = n; closesRank = m.rank
                    }
                } else {
                    loose.append(n)
                }
            }
            if closes == nil && opens == nil {
                if dateHint != nil, !loose.isEmpty {
                    // { "2026-10-27": { "08": 3, "09": 5 } } : des tranches de la journée, à additionner.
                    add(key, closes: loose.reduce(0, +), opens: 0)
                    return
                }
                r.eventLog = true
                if isOpen == true { add(key, closes: 0, opens: 1) } else { add(key, closes: 1, opens: 0) }
            } else {
                add(key, closes: closes ?? 0, opens: opens ?? 0)
            }
        }
        /// [ "2026-10-27", 47, 45 ] : une date puis des nombres ; une date seule : un pli.
        func fromRow(_ row: [Any]) {
            guard let i = row.firstIndex(where: { dateKey($0) != nil }), let key = dateKey(row[i]) else { return }
            let numbers = row.enumerated().compactMap { $0.offset == i ? nil : count($0.element) }
            if numbers.isEmpty {
                r.eventLog = true
                let open = row.contains { ($0 as? String).map(saysOpen) == true }
                add(key, closes: open ? 0 : 1, opens: open ? 1 : 0)
            } else {
                add(key, closes: numbers[0], opens: numbers.count > 1 ? numbers[1] : 0)
            }
        }
        if let list = json as? [Any] {
            for item in list {
                if let o = item as? [String: Any] { fromObject(o) }
                else if let row = item as? [Any] { fromRow(row) }
                else if let key = dateKey(item) { r.eventLog = true; add(key, closes: 1, opens: 0) }
            }
        } else if let o = json as? [String: Any] {
            // { "2026-10-01": 52 } ou { "2026-10-01": { "folds": 52, "opens": 48 } } ou { "history": [...] }
            var dated = false
            for (k, v) in o {
                guard let key = DateReader.key(from: k) else { continue }
                dated = true
                if let sub = v as? [String: Any] {
                    fromObject(sub, dateHint: key)
                } else if let list = v as? [Any] {
                    // [plis, ouvertures], ou la liste des plis du jour (un élément par pli).
                    let numbers = list.compactMap { count($0) }
                    if list.count == 2, numbers.count == 2 {
                        add(key, closes: numbers[0], opens: numbers[1])
                    } else if !list.isEmpty {
                        r.eventLog = true
                        add(key, closes: list.count, opens: 0)
                    }
                } else if let n = count(v) {
                    add(key, closes: n, opens: 0)
                }
            }
            if !dated {
                // Un historique rangé plus bas : { "history": [...] } ou, comme Scriptable,
                // { "total": 493, "days": { "2026-10-27": 47, … }, "hours": { … } }.
                // On garde la partie qui donne le plus de jours (pas « hours », qui ne parle que d'aujourd'hui).
                var best: HistoryImport?
                for v in o.values where v is [Any] || v is [String: Any] {
                    let sub = cleaned(parseJSON(v))
                    if !sub.isEmpty, sub.days.count > (best?.days.count ?? 0) { best = sub }
                }
                if let best { return best }
                fromObject(o)
            }
        }
        return r
    }

    /// Un objet JSON par ligne (journal écrit pli après pli), avec ou sans virgule en fin de ligne.
    private static func parseJSONLines(_ text: String) -> HistoryImport {
        var items: [Any] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            while line.hasSuffix(",") { line.removeLast() }
            guard line.count >= 2, let data = line.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            items.append(item)
        }
        return items.isEmpty ? HistoryImport() : parseJSON(items)
    }

    /// Dernier recours, sur le texte brut : « date : nombre » (un total par jour), sinon chaque date avec son heure
    /// (un pli), sinon chaque horodatage (un pli).
    private static func scan(_ text: String) -> HistoryImport {
        var r = HistoryImport()
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: all) ?? []
        }
        for m in matches(#"(\d{4}-\d{2}-\d{2})["']?\s*[:=,;|\t]\s*["']?(\d{1,6})(?![\d:\-T/.])"#) {
            guard let key = DateReader.key(from: ns.substring(with: m.range(at: 1))), let n = Int(ns.substring(with: m.range(at: 2))) else { continue }
            r.days[key, default: Day()].closes += n
        }
        if !r.days.isEmpty { return r }
        r.eventLog = true
        for m in matches(#"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+\-]\d{2}:?\d{2})?"#) {
            let found = ns.substring(with: m.range)
            guard let key = DateReader.key(from: found) ?? DateReader.key(from: String(found.prefix(10))) else { continue }
            r.days[key, default: Day()].closes += 1
        }
        if !r.days.isEmpty { return r }
        for m in matches(#"(?<![\d.])1\d{9}(\d{3})?(?![\d.])"#) {
            guard let n = Double(ns.substring(with: m.range)), let key = DateReader.key(fromUnix: n) else { continue }
            r.days[key, default: Day()].closes += 1
        }
        return r
    }

    private static func parseLines(_ text: String) -> HistoryImport {
        var r = HistoryImport()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return r }
        let sep = separator(for: lines)
        func fields(_ line: String) -> [String] {
            guard let sep else { return [line] }
            return line.split(separator: sep, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
        }
        // En-tête : quelles colonnes sont les plis et les ouvertures
        var closeCol: Int?, openCol: Int?
        let head = fields(lines[0]).map { $0.lowercased() }
        if head.allSatisfy({ DateReader.key(from: $0) == nil && Int($0) == nil }) {
            for (i, h) in head.enumerated() {
                if h.contains("unfold") || h.contains("open") || h.contains("ouvert") { openCol = openCol ?? i }
                else if h.contains("fold") || h.contains("close") || h.contains("ferm") || h.contains("pli") || h.contains("count") { closeCol = closeCol ?? i }
            }
        }

        for line in lines {
            // Une date seule sur la ligne (avec ses virgules : « Nov 5, 2026 at 8:17 PM ») : un pli.
            if let key = DateReader.key(from: line) {
                r.eventLog = true
                r.days[key, default: Day()].closes += 1
                continue
            }
            var f = fields(line)
            // Une date coupée par le séparateur : on recolle deux morceaux.
            if sep == ",", !f.contains(where: { DateReader.key(from: $0) != nil }) {
                for i in 0..<max(0, f.count - 1) {
                    let joined = f[i] + "," + f[i + 1]
                    if DateReader.key(from: joined) != nil { f[i] = joined; f.remove(at: i + 1); break }
                }
            }
            guard let dateIndex = f.firstIndex(where: { DateReader.key(from: $0) != nil }),
                  let key = DateReader.key(from: f[dateIndex]) else { continue }
            let numbers: [(Int, Int)] = f.enumerated().compactMap { i, s in
                guard i != dateIndex, let n = Int(s.replacingOccurrences(of: " ", with: "")) else { return nil }
                return (i, n)
            }
            var d = r.days[key] ?? Day()
            if numbers.isEmpty {
                // Une ligne = un pli (ou une ouverture si la ligne le dit)
                r.eventLog = true
                let low = line.lowercased()
                if low.contains("unfold") || low.contains("open") || low.contains("ouvert") { d.opens += 1 } else { d.closes += 1 }
            } else if closeCol != nil || openCol != nil {
                d.closes += numbers.first { $0.0 == closeCol }?.1 ?? 0
                d.opens += numbers.first { $0.0 == openCol }?.1 ?? 0
            } else {
                d.closes += numbers[0].1
                if numbers.count > 1 { d.opens += numbers[1].1 }
            }
            r.days[key] = d
        }
        // Ne garder que des valeurs plausibles
        r.days = r.days.filter { $0.value.closes >= 0 && $0.value.opens >= 0 && $0.value.closes <= 100_000 && $0.value.opens <= 100_000 && ($0.value.closes > 0 || $0.value.opens > 0) }
        return r
    }

    private static func separator(for lines: [String]) -> Character? {
        let sample = lines.prefix(20)
        for c: Character in ["\t", ";", "|", ","] {
            let counts = sample.map { $0.filter { $0 == c }.count }
            if let m = counts.min(), m > 0 { return c }
        }
        return nil
    }
}

/// Lit les dates écrites de mille façons, et rend la clé du jour « AAAA-MM-JJ » (dans le fuseau de l'iPhone).
enum DateReader {
    /// 05/11/2026 : jour d'abord (Europe) ou mois d'abord (États-Unis) ? Décidé sur tout le fichier.
    private static var dayFirst = !(Locale.current.region?.identifier == "US")

    static func guessDayFirst(_ lines: [String]) {
        let re = try? NSRegularExpression(pattern: #"\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b"#)
        var a = false, b = false
        for l in lines.prefix(500) {
            let ns = l as NSString
            re?.enumerateMatches(in: l, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                if let x = Int(ns.substring(with: m.range(at: 1))), x > 12 { a = true }
                if let y = Int(ns.substring(with: m.range(at: 2))), y > 12 { b = true }
            }
        }
        if a && !b { dayFirst = true } else if b && !a { dayFirst = false }
    }

    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = .current
        d.dateFormat = f
        return d
    }

    private static let common: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
        "MMM d, yyyy 'at' h:mm a", "MMM d, yyyy 'at' h:mm:ss a", "MMM d, yyyy, h:mm a", "MMM d, yyyy h:mm a", "MMM d, yyyy",
        "MMMM d, yyyy 'at' h:mm a", "MMMM d, yyyy", "d MMM yyyy 'at' HH:mm", "d MMM yyyy HH:mm", "d MMM yyyy", "d MMMM yyyy",
        "EEEE, MMMM d, yyyy", "EEE, d MMM yyyy HH:mm:ss Z",
    ].map(formatter)
    private static let compact = formatter("yyyyMMdd")
    private static let dayFirstFormats: [DateFormatter] = [
        "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "dd.MM.yyyy HH:mm", "dd.MM.yyyy", "dd-MM-yyyy", "dd/MM/yy", "d/M/yyyy",
    ].map(formatter)
    private static let monthFirstFormats: [DateFormatter] = [
        "MM/dd/yyyy h:mm a", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "M/d/yyyy, h:mm a", "M/d/yyyy h:mm a", "M/d/yyyy", "MM/dd/yy", "M/d/yy, h:mm a",
    ].map(formatter)

    static func key(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).replacingOccurrences(of: "\u{202F}", with: " ")
        guard s.count >= 6, s.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        // Horodatage Unix (secondes ou millisecondes)
        if let n = Double(s), s.count >= 9 { return key(fromUnix: n) }
        // 20261027 : la date écrite d'un bloc.
        if s.count == 8, s.allSatisfy({ $0.isASCII && $0.isNumber }), let d = compact.date(from: s), plausible(d) { return ClapetStats.key(d) }
        if Double(s) != nil { return nil }
        let ordered = dayFirst ? dayFirstFormats + monthFirstFormats : monthFirstFormats + dayFirstFormats
        for f in common + ordered {
            if let d = f.date(from: s), plausible(d) { return ClapetStats.key(d) }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s), plausible(d) { return ClapetStats.key(d) }
        return nil
    }

    static func key(fromUnix n: Double) -> String? {
        let seconds = n > 1e11 ? n / 1000 : n
        let d = Date(timeIntervalSince1970: seconds)
        return plausible(d) ? ClapetStats.key(d) : nil
    }

    /// Entre 2015 et aujourd'hui.
    private static func plausible(_ d: Date) -> Bool {
        d > Date(timeIntervalSince1970: 1_420_070_400) && d <= Date().addingTimeInterval(86_400)
    }
}

#if !HISTORY_IMPORT_TEST
extension ClapetStats {
    /// Ajoute un historique importé. Foldly et l'autre outil ont compté les mêmes plis : pour chaque jour,
    /// on garde le plus grand des deux nombres (jamais la somme). Aujourd'hui compris : si l'autre outil
    /// tournait avant l'installation de Foldly, ses plis du matin ne sont pas perdus.
    /// Rend le nombre de jours ajoutés ou complétés.
    @discardableResult
    mutating func importHistory(_ imp: HistoryImport) -> Int {
        let today = Self.key()
        var added = 0
        for (key, d) in imp.days where key <= today {
            var n = days[key] ?? DayCount()
            let moreCloses = max(0, d.closes - n.closes)
            let moreOpens = max(0, d.opens - n.opens)
            guard moreCloses > 0 || moreOpens > 0 else { continue }
            n.closes += moreCloses
            n.opens += moreOpens
            days[key] = n
            totalCloses += moreCloses
            totalOpens += moreOpens
            added += 1
            if firstDay.map({ key < $0 }) ?? true { firstDay = key }
        }
        keepRecentDays()
        return added
    }

    /// Combien de jours du fichier Foldly a déjà comptés (on y garde le plus grand des deux nombres).
    func importOverlap(_ imp: HistoryImport) -> Int {
        imp.days.keys.filter { key in (days[key]?.closes ?? 0) > 0 || (days[key]?.opens ?? 0) > 0 }.count
    }
}
#endif
