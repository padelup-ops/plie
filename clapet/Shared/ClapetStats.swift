import Foundation
import Security

// MARK: - Les chiffres de Clapet
//
// Partagés entre l'app et ses widgets dans le trousseau (un groupe de trousseau commun aux deux) :
// pas besoin de groupe d'app à déclarer chez Apple.

struct DayCount: Codable, Equatable {
    var closes = 0
    var opens = 0
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

    init() {}

    enum CodingKeys: String, CodingKey {
        case days, goal, totalCloses, totalOpens, firstDay, hourlyDay, hourly, lastClose
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
        hourly[Calendar.current.component(.hour, from: date)] += 1
        lastClose = date
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    mutating func addOpen(_ date: Date = Date()) {
        var d = day(date)
        d.opens += 1
        days[Self.key(date)] = d
        totalOpens += 1
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    /// On garde un peu plus d'un an d'historique.
    private mutating func trim() {
        guard days.count > 420 else { return }
        let keep = Set(days.keys.sorted().suffix(400))
        days = days.filter { keep.contains($0.key) }
    }
}

// MARK: - Les niveaux (sur le total de clapets)

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

    var name: String {
        switch number {
        case 1: return String(localized: "Fresh hinge")
        case 2: return String(localized: "Smooth hinge")
        case 3: return String(localized: "Speedy hinge")
        case 4: return String(localized: "Clap master")
        case 5: return String(localized: "Hinge hero")
        case 6: return String(localized: "Fold legend")
        case 7: return String(localized: "Unbreakable")
        default: return String(localized: "Hinge god")
        }
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
