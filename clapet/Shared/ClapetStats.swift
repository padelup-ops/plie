import Foundation
import Security
import SwiftUI

// MARK: - Les chiffres de Clapet
//
// Partagés entre l'app et ses widgets dans le trousseau (un groupe de trousseau commun aux deux) :
// pas besoin de groupe d'app à déclarer chez Apple.

struct DayCount: Codable, Equatable {
    var closes = 0
    var opens = 0
    /// Temps passé ouvert ce jour-là, en secondes.
    var openSeconds: Double = 0

    init(closes: Int = 0, opens: Int = 0, openSeconds: Double = 0) {
        self.closes = closes
        self.opens = opens
        self.openSeconds = openSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closes = try c.decodeIfPresent(Int.self, forKey: .closes) ?? 0
        opens = try c.decodeIfPresent(Int.self, forKey: .opens) ?? 0
        openSeconds = try c.decodeIfPresent(Double.self, forKey: .openSeconds) ?? 0
    }
}

struct ClapetStats: Codable, Equatable {
    var days: [String: DayCount] = [:]
    var goal = 100
    var totalCloses = 0
    var totalOpens = 0
    var firstDay: String?
    /// Les clapets d'aujourd'hui, heure par heure.
    var hourlyDay: String?
    var hourly: [Int] = Array(repeating: 0, count: 24)
    var lastClose: Date?
    /// Le record de plis en une heure.
    var recordHour = 0
    /// Duo Folds+ acheté (écrit par l'app, lu par les widgets).
    var plus = false
    /// Couleur des widgets (Duo Folds+).
    var theme = 0
    /// Dernier pli compté par l'automatisation Raccourcis (app fermée).
    var autoLast: Date?
    /// Depuis quand le Duo est ouvert (nil : fermé, ou on ne sait pas).
    var openSince: Date?
    /// Les plis par jour de la semaine et par heure, depuis le début : 7 × 24 cases (dimanche d'abord).
    var weekHours: [Int] = Array(repeating: 0, count: 168)
    /// Au-delà, une ouverture sans fermeture vue est oubliée (une fermeture a dû nous échapper).
    static let maxOpenSession: TimeInterval = 16 * 3600

    init() {}

    enum CodingKeys: String, CodingKey {
        case days, goal, totalCloses, totalOpens, firstDay, hourlyDay, hourly, lastClose, recordHour, plus, theme, autoLast, openSince, weekHours
    }

    /// Chaque champ est facultatif : une ancienne sauvegarde se relit toujours.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String: DayCount].self, forKey: .days) ?? [:]
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 100
        totalCloses = try c.decodeIfPresent(Int.self, forKey: .totalCloses) ?? 0
        totalOpens = try c.decodeIfPresent(Int.self, forKey: .totalOpens) ?? 0
        firstDay = try c.decodeIfPresent(String.self, forKey: .firstDay)
        hourlyDay = try c.decodeIfPresent(String.self, forKey: .hourlyDay)
        hourly = try c.decodeIfPresent([Int].self, forKey: .hourly) ?? Array(repeating: 0, count: 24)
        if hourly.count != 24 { hourly = Array(repeating: 0, count: 24) }
        lastClose = try c.decodeIfPresent(Date.self, forKey: .lastClose)
        recordHour = try c.decodeIfPresent(Int.self, forKey: .recordHour) ?? 0
        plus = try c.decodeIfPresent(Bool.self, forKey: .plus) ?? false
        theme = try c.decodeIfPresent(Int.self, forKey: .theme) ?? 0
        autoLast = try c.decodeIfPresent(Date.self, forKey: .autoLast)
        openSince = try c.decodeIfPresent(Date.self, forKey: .openSince)
        if let saved = try c.decodeIfPresent([Int].self, forKey: .weekHours), saved.count == 168 {
            weekHours = saved
        } else if let key = hourlyDay, let d = Self.date(key) {
            // Première ouverture de cette version : on part des plis d'aujourd'hui, heure par heure.
            let row = (Calendar.current.component(.weekday, from: d) - 1) * 24
            for h in 0..<24 { weekHours[row + h] = hourly[h] }
        }
    }

    /// Les clapets d'une journée, heure par heure (seulement pour aujourd'hui).
    func hours(_ date: Date = Date()) -> [Int] {
        hourlyDay == Self.key(date) ? hourly : Array(repeating: 0, count: 24)
    }

    func yesterday(_ date: Date = Date()) -> Int {
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return 0 }
        return day(y).closes
    }

    var level: ClapetLevel { ClapetLevel.of(totalCloses) }

    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func day(_ date: Date = Date()) -> DayCount { days[Self.key(date)] ?? DayCount() }

    /// Un « clapet », c'est une fermeture du Duo.
    var today: Int { day().closes }

    var progress: Double { goal > 0 ? min(1, Double(today) / Double(goal)) : 0 }

    var best: Int { days.values.map(\.closes).max() ?? 0 }

    /// Les 7 derniers jours, du plus ancien à aujourd'hui.
    func lastWeek(now: Date = Date()) -> [(date: Date, closes: Int)] {
        (0..<7).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: now) else { return nil }
            return (d, day(d).closes)
        }
    }

    var weekTotal: Int { lastWeek().reduce(0) { $0 + $1.closes } }

    mutating func addClose(_ date: Date = Date()) {
        var d = day(date)
        d.closes += 1
        days[Self.key(date)] = d
        totalCloses += 1
        let key = Self.key(date)
        if hourlyDay != key {
            hourlyDay = key
            hourly = Array(repeating: 0, count: 24)
        }
        let h = Calendar.current.component(.hour, from: date)
        hourly[h] += 1
        recordHour = max(recordHour, hourly[h])
        let cell = (Calendar.current.component(.weekday, from: date) - 1) * 24 + h
        if weekHours.count == 168 { weekHours[cell] += 1 }
        lastClose = date
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    /// Corrige à la main le nombre de plis d'une journée (le total suit de la même différence).
    mutating func setCloses(_ value: Int, on date: Date = Date()) {
        let key = Self.key(date)
        var d = day(date)
        let target = max(0, min(100_000, value))
        let delta = target - d.closes
        guard delta != 0 else { return }
        d.closes = target
        days[key] = d
        totalCloses = max(target, totalCloses + delta)
        // Heure par heure : on ne garde que des plis vraiment vus, en retirant d'abord les plus récents.
        if delta < 0, hourlyDay == key {
            var excess = hourly.reduce(0, +) - target
            for h in stride(from: 23, through: 0, by: -1) where excess > 0 {
                let cut = min(hourly[h], excess)
                hourly[h] -= cut
                excess -= cut
            }
        }
        if firstDay == nil && target > 0 { firstDay = key }
        trim()
    }

    /// Corrige à la main le total depuis le début (jamais moins que les plis d'aujourd'hui).
    mutating func setTotal(_ value: Int, now: Date = Date()) {
        totalCloses = max(day(now).closes, min(10_000_000, value))
        if firstDay == nil && totalCloses > 0 { firstDay = Self.key(now) }
    }

    mutating func addOpen(_ date: Date = Date()) {
        var d = day(date)
        d.opens += 1
        days[Self.key(date)] = d
        totalOpens += 1
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    // MARK: Temps ouvert

    /// Le Duo vient de s'ouvrir.
    mutating func startOpen(_ date: Date = Date()) {
        if let s = openSince, date.timeIntervalSince(s) < Self.maxOpenSession { return }
        openSince = date
    }

    /// Le Duo vient de se fermer : on ajoute la durée d'ouverture (répartie sur les jours traversés).
    mutating func endOpen(_ date: Date = Date()) {
        guard let start = openSince else { return }
        openSince = nil
        let total = date.timeIntervalSince(start)
        guard total > 0, total < Self.maxOpenSession else { return }
        let cal = Calendar.current
        var s = start
        while s < date {
            let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: s)) ?? date
            let end = min(date, midnight)
            var d = day(s)
            d.openSeconds += end.timeIntervalSince(s)
            days[Self.key(s)] = d
            s = end
        }
    }

    /// Temps ouvert d'une journée, en comptant l'ouverture en cours pour aujourd'hui.
    func openTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        var t = day(date).openSeconds
        if Self.key(date) == Self.key(now), let s = openSince, now.timeIntervalSince(s) < Self.maxOpenSession {
            t += max(0, now.timeIntervalSince(max(s, Calendar.current.startOfDay(for: now))))
        }
        return t
    }

    /// Moyenne de temps ouvert par jour, sur les jours mesurés des `count` derniers jours.
    func averageOpen(days count: Int = 30, now: Date = Date()) -> TimeInterval {
        let values = lastDays(count, now: now).map { openTime($0.date, now: now) }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: Historique (Duo Folds+)

    /// Les `count` derniers jours, du plus ancien à aujourd'hui.
    func lastDays(_ count: Int, now: Date = Date()) -> [(date: Date, closes: Int)] {
        (0..<count).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: now) else { return nil }
            return (d, day(d).closes)
        }
    }

    /// Les 12 derniers mois (total des plis), du plus ancien au mois en cours.
    func lastMonths(now: Date = Date()) -> [(date: Date, closes: Int)] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var totals: [String: Int] = [:]
        for (key, value) in days { totals[String(key.prefix(7)), default: 0] += value.closes }
        return (0..<12).reversed().compactMap { back in
            guard let m = cal.date(byAdding: .month, value: -back, to: start) else { return nil }
            return (m, totals[String(Self.key(m).prefix(7))] ?? 0)
        }
    }

    /// Le jour le plus chargé et sa date.
    var bestDay: (date: Date, closes: Int)? {
        guard let top = days.max(by: { $0.value.closes < $1.value.closes || ($0.value.closes == $1.value.closes && $0.key > $1.key) }),
              top.value.closes > 0, let d = Self.date(top.key) else { return nil }
        return (d, top.value.closes)
    }

    /// `goal` est la limite du jour : on cherche à rester en dessous.
    var limit: Int { goal }

    /// Ce qui reste avant la limite aujourd'hui (négatif : dépassée).
    func left(now: Date = Date()) -> Int { goal - day(now).closes }

    /// Jours d'affilée sous la limite, depuis le premier jour suivi (aujourd'hui compte s'il est encore sous la limite).
    func currentStreak(now: Date = Date()) -> Int {
        guard goal > 0, let first = firstDay else { return 0 }
        let cal = Calendar.current
        var d = now
        var n = 0
        while Self.key(d) >= first && day(d).closes <= goal {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return n
    }

    /// La plus longue série de jours sous la limite.
    func longestStreak(now: Date = Date()) -> Int {
        guard goal > 0, let first = firstDay.flatMap(Self.date) else { return 0 }
        let cal = Calendar.current
        var d = first
        var best = 0, run = 0
        while Self.key(d) <= Self.key(now) {
            run = day(d).closes <= goal ? run + 1 : 0
            best = max(best, run)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return best
    }

    /// Le jour le plus calme (le moins de plis, aujourd'hui exclu).
    func calmestDay(now: Date = Date()) -> (date: Date, closes: Int)? {
        let today = Self.key(now)
        guard let low = days.filter({ $0.key != today && $0.value.closes > 0 })
            .min(by: { $0.value.closes < $1.value.closes }), let d = Self.date(low.key) else { return nil }
        return (d, low.value.closes)
    }

    /// Les 7 derniers jours comparés aux 7 d'avant, en pourcentage (nil sans semaine d'avant).
    func weekChange(now: Date = Date()) -> Double? {
        let recent = lastDays(14, now: now)
        let previous = recent.prefix(7).reduce(0) { $0 + $1.closes }
        let current = recent.suffix(7).reduce(0) { $0 + $1.closes }
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }

    /// Moyenne par jour sur les 30 jours avant aujourd'hui (depuis le premier jour suivi). nil le premier jour.
    func recentAverage(now: Date = Date()) -> Double? {
        guard let first = firstDay else { return nil }
        let past = lastDays(31, now: now).dropLast().filter { Self.key($0.date) >= first }
        guard !past.isEmpty else { return nil }
        return Double(past.reduce(0) { $0 + $1.closes }) / Double(past.count)
    }

    /// La case la plus chargée de la semaine type : (jour 0 = dimanche, heure).
    var busiestSlot: (weekday: Int, hour: Int)? {
        guard weekHours.count == 168, let top = weekHours.max(), top > 0,
              let i = weekHours.firstIndex(of: top) else { return nil }
        return (i / 24, i % 24)
    }

    /// Moyenne par jour depuis le premier jour compté.
    func dailyAverage(now: Date = Date()) -> Double {
        guard let first = firstDay.flatMap(Self.date) else { return 0 }
        let n = (Calendar.current.dateComponents([.day], from: first, to: now).day ?? 0) + 1
        return Double(totalCloses) / Double(max(1, n))
    }

    var daysCounted: Int { days.values.filter { $0.closes > 0 }.count }

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// L'historique en tableur : date, fermetures, ouvertures.
    func csv() -> String {
        var out = "date,folds,opens\n"
        for key in days.keys.sorted() {
            let d = days[key] ?? DayCount()
            out += "\(key),\(d.closes),\(d.opens)\n"
        }
        return out
    }

    /// On garde un peu plus d'un an d'historique.
    private mutating func trim() {
        guard days.count > 420 else { return }
        let keep = Set(days.keys.sorted().suffix(400))
        days = days.filter { keep.contains($0.key) }
    }
}

// MARK: - Les couleurs des widgets (Duo Folds+)

enum ClapetTheme: Int, CaseIterable, Identifiable {
    case mint, orange, pink, blue, lemon

    var id: Int { rawValue }

    /// Rouge, vert, bleu entre 0 et 1.
    var rgb: (Double, Double, Double) {
        switch self {
        case .mint: return (0.43, 0.84, 0.65)
        case .orange: return (1.0, 0.58, 0.28)
        case .pink: return (1.0, 0.42, 0.62)
        case .blue: return (0.40, 0.70, 1.0)
        case .lemon: return (0.95, 0.88, 0.32)
        }
    }

    var name: String {
        switch self {
        case .mint: return String(localized: "Mint")
        case .orange: return String(localized: "Orange")
        case .pink: return String(localized: "Pink")
        case .blue: return String(localized: "Blue")
        case .lemon: return String(localized: "Lemon")
        }
    }
}

extension ClapetTheme {
    var color: Color {
        let (r, g, b) = rgb
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Les niveaux (sur le total de plis)

struct ClapetLevel {
    let number: Int
    let start: Int
    let next: Int?

    static let thresholds = [0, 500, 1500, 4000, 10_000, 25_000, 60_000, 150_000]

    static func of(_ total: Int) -> ClapetLevel {
        var i = 0
        while i + 1 < thresholds.count && total >= thresholds[i + 1] { i += 1 }
        return ClapetLevel(number: i + 1, start: thresholds[i], next: i + 1 < thresholds.count ? thresholds[i + 1] : nil)
    }

    func progress(_ total: Int) -> Double {
        guard let next else { return 1 }
        return min(1, Double(total - start) / Double(max(1, next - start)))
    }
}

// MARK: - Le coffre (trousseau partagé)

enum ClapetVault {
    private static let service = "com.padelup.clapet"
    private static let account = "stats"

    /// Groupe de trousseau commun à l'app et aux widgets (« ÉQUIPE.com.padelup.clapet.shared »).
    private static var group: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "ClapetKeychainGroup") as? String,
              !g.hasPrefix("."), !g.isEmpty else { return nil }
        return g
    }

    private static func query(_ group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func load() -> ClapetStats {
        for g in [group, nil] {
            var q = query(g)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
               let stats = try? JSONDecoder().decode(ClapetStats.self, from: data) {
                return stats
            }
            if group == nil { break }
        }
        // Secours : la copie de l'app
        if let data = UserDefaults.standard.data(forKey: "clapet.stats"),
           let stats = try? JSONDecoder().decode(ClapetStats.self, from: data) {
            return stats
        }
        return ClapetStats()
    }

    static func save(_ stats: ClapetStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: "clapet.stats")
        if write(data, group: group) != errSecSuccess && group != nil {
            // Sans le groupe partagé (développement), on garde au moins une copie pour l'app.
            _ = write(data, group: nil)
        }
    }

    private static func write(_ data: Data, group: String?) -> OSStatus {
        let q = query(group)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }
}
