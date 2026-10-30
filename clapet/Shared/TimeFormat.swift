import Foundation

/// Les durées affichées dans l'app et les widgets : « 2 h 10 », « 25 min ».
enum TimeFormat {
    static func short(_ t: TimeInterval) -> String {
        let minutes = Int(max(0, t) / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: allowed, width: .abbreviated))
    }

    /// En heures seulement, pour les petites places (« 5 h », « 40 min »).
    static func compact(_ t: TimeInterval) -> String {
        let minutes = Int(max(0, t) / 60)
        if minutes < 60 {
            return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: [.minutes], width: .narrow))
        }
        return Duration.seconds(Double(minutes / 60 * 3600)).formatted(.units(allowed: [.hours], width: .narrow))
    }
}
