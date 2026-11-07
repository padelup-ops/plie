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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "[" || first == "{",
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let r = parseJSON(json)
            if !r.isEmpty { return r }
        }
        return parseLines(trimmed)
    }

    private static func parseJSON(_ json: Any) -> HistoryImport {
        var r = HistoryImport()
        func add(_ key: String, closes: Int, opens: Int) {
            var d = r.days[key] ?? Day()
            d.closes += closes
            d.opens += opens
            r.days[key] = d
        }
        func fromObject(_ o: [String: Any], dateHint: String? = nil) {
            var key = dateHint.flatMap { DateReader.key(from: $0) }
            var closes: Int?, opens: Int?
            var kind: String?
            for (k, v) in o {
                let name = k.lowercased()
                if key == nil, let s = v as? String, let d = DateReader.key(from: s) { key = d; continue }
                if key == nil, let n = v as? Double, ["date", "time", "timestamp", "day", "t"].contains(name), let d = DateReader.key(fromUnix: n) { key = d; continue }
                if let s = v as? String, ["type", "event", "action", "kind"].contains(name) { kind = s.lowercased() }
                guard let n = (v as? NSNumber)?.intValue ?? (v as? String).flatMap({ Int($0) }) else { continue }
                if name.contains("unfold") || name.contains("open") { opens = n }
                else if name.contains("fold") || name.contains("close") || name.contains("count") || name == "value" || name == "total" { closes = n }
            }
            guard let key else { return }
            if closes == nil && opens == nil {
                r.eventLog = true
                if let kind, kind.contains("unfold") || kind.contains("open") { add(key, closes: 0, opens: 1) } else { add(key, closes: 1, opens: 0) }
            } else {
                add(key, closes: closes ?? 0, opens: opens ?? 0)
            }
        }
        if let list = json as? [Any] {
            for item in list {
                if let o = item as? [String: Any] { fromObject(o) }
                else if let s = item as? String, let key = DateReader.key(from: s) { r.eventLog = true; add(key, closes: 1, opens: 0) }
                else if let n = item as? Double, let key = DateReader.key(fromUnix: n) { r.eventLog = true; add(key, closes: 1, opens: 0) }
            }
        } else if let o = json as? [String: Any] {
            // { "2026-10-01": 52 } ou { "2026-10-01": { "folds": 52, "opens": 48 } } ou { "history": [...] }
            var dated = false
            for (k, v) in o {
                guard let key = DateReader.key(from: k) else { continue }
                dated = true
                if let n = (v as? NSNumber)?.intValue { add(key, closes: n, opens: 0) }
                else if let sub = v as? [String: Any] { fromObject(sub, dateHint: k) }
            }
            if !dated {
                // Un historique rangé plus bas : { "history": [...] } ou, comme Scriptable,
                // { "total": 493, "days": { "2026-10-27": 47, … }, "hours": { … } }.
                // On garde la partie qui donne le plus de jours (pas « hours », qui ne parle que d'aujourd'hui).
                var best: HistoryImport?
                for v in o.values where v is [Any] || v is [String: Any] {
                    let sub = parseJSON(v)
                    if !sub.isEmpty, sub.days.count > (best?.days.count ?? 0) { best = sub }
                }
                if let best { return best }
                fromObject(o)
            }
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
        DateReader.guessDayFirst(lines)

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
