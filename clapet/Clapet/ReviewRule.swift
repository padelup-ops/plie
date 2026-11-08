import Foundation

/// La demande de note d'Apple, au bon moment et sans insister :
/// seulement après quelques jours d'utilisation, un jour où tout va bien (sous la limite, ou série en cours),
/// au plus une fois tous les 4 mois (et Apple n'affiche de toute façon la fenêtre que 3 fois par an).
/// Jamais dans TestFlight, jamais en plein milieu d'autre chose. On peut toujours l'ignorer.
enum ReviewRule {
    static let lastKey = "reviewAskedAt"
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6827349081?action=write-review")!

    static func shouldAsk(_ stats: ClapetStats, isTestBuild: Bool, now: Date = Date()) -> Bool {
        guard !isTestBuild, !Demo.seeded, Demo.screen == nil else { return false }
        guard stats.daysCounted >= 4 else { return false }
        if let last = UserDefaults.standard.object(forKey: lastKey) as? Date, now.timeIntervalSince(last) < 120 * 86_400 { return false }
        // Un bon jour : sous la limite, ou une série de 3 jours ou plus.
        let goodDay = stats.goalOn ? (stats.today > 0 && stats.left(now: now) >= 0) : stats.today > 0
        return goodDay || stats.currentStreak(now: now) >= 3
    }

    static func markAsked(now: Date = Date()) { UserDefaults.standard.set(now, forKey: lastKey) }

    /// Juste après l'achat de Foldly+ : on demande une note (pas plus d'une fois par mois).
    static func shouldAskAfterPurchase(isTestBuild: Bool, now: Date = Date()) -> Bool {
        guard !isTestBuild, !Demo.seeded, Demo.screen == nil else { return false }
        if let last = UserDefaults.standard.object(forKey: lastKey) as? Date, now.timeIntervalSince(last) < 30 * 86_400 { return false }
        return true
    }
}
