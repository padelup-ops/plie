import ActivityKit
import Foundation

/// Le compteur en direct (Live Activity) : sur l'écran verrouillé et l'écran extérieur, mis à jour à chaque pli.
struct FoldActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var today: Int
        var limit: Int
        var day: String
        var lastFold: Date?
    }

    var title = "Foldly"
}

extension FoldActivityAttributes.ContentState {
    init(stats: ClapetStats, now: Date = Date()) {
        self.init(today: stats.day(now).closes, limit: stats.goal, day: ClapetStats.key(now), lastFold: stats.lastClose)
    }

    /// Après minuit, tant qu'aucun pli n'est venu mettre l'activité à jour : la nouvelle journée commence à zéro.
    func fresh(_ isStale: Bool) -> Self {
        guard isStale || day != ClapetStats.key(Date()) else { return self }
        var s = self
        s.today = 0
        return s
    }

    var left: Int { limit - today }
    var progress: Double { limit > 0 ? min(1, Double(today) / Double(limit)) : 0 }
}
