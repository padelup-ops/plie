import Foundation

// MARK: - Ce que l'iPhone envoie à l'Apple Watch
//
// Un petit résumé, envoyé par WatchConnectivity à chaque changement (le dernier remplace le précédent).
// Partagé par l'app iPhone, l'app Apple Watch et ses complications.

struct FoldlyWatchData: Codable, Equatable {
    /// Le jour du résumé (« 2026-11-02 ») : le lendemain, la montre repart à zéro en attendant l'iPhone.
    var day: String
    var today: Int
    var yesterday: Int
    /// La moyenne par jour (ou la limite, si elle est activée), nil les premiers jours.
    var reference: Int?
    var limitOn: Bool
    /// Les 7 derniers jours, du plus ancien à aujourd'hui.
    var week: [Int]
    var closedSeconds: Double
    var openSeconds: Double
    /// Ouvert depuis… (nil : fermé ou inconnu). Fermé depuis… = dernier pli.
    var openSince: Date?
    var lastClose: Date?
    var total: Int
    /// L'heure où l'on plie le plus (journée type), nil au début.
    var peakHour: Int?
    var updated: Date

    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Les chiffres du jour vus à `date` : si le résumé date d'hier, aujourd'hui repart à zéro.
    func current(at date: Date = Date()) -> FoldlyWatchData {
        guard day != Self.key(date) else { return self }
        var fresh = self
        let cal = Calendar.current
        let gap = cal.dateComponents([.day], from: cal.startOfDay(for: Self.date(day) ?? date), to: cal.startOfDay(for: date)).day ?? 1
        fresh.yesterday = gap == 1 ? today : 0
        fresh.week = Array((week + Array(repeating: 0, count: max(0, gap))).suffix(7))
        fresh.today = 0
        fresh.closedSeconds = 0
        fresh.openSeconds = 0
        fresh.day = Self.key(date)
        return fresh
    }

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    /// Pour la galerie des complications.
    static let sample = FoldlyWatchData(day: key(), today: 47, yesterday: 43, reference: 56, limitOn: false,
                                        week: [39, 43, 58, 39, 49, 43, 47], closedSeconds: 9540, openSeconds: 6120,
                                        openSince: nil, lastClose: Date().addingTimeInterval(-17 * 60), total: 4006,
                                        peakHour: 21, updated: Date())
}
