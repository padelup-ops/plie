import ActivityKit
import Foundation

/// Le compteur en direct (Live Activity) : sur l'écran verrouillé et l'écran extérieur, mis à jour à chaque pli.
struct FoldActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var today: Int
        /// La limite du jour si elle est activée, 0 sinon.
        var limit: Int
        var day: String
        var lastFold: Date?
        /// Fermé depuis (nil : ouvert).
        var downSince: Date?
        /// La moyenne par jour, repère quand la limite est désactivée (facultatif : une ancienne activité se relit).
        var average: Int?
    }

    var title = "Foldly"
}

extension FoldActivityAttributes.ContentState {
    init(stats: ClapetStats, now: Date = Date()) {
        self.init(today: stats.day(now).closes, limit: stats.activeLimit, day: ClapetStats.key(now), lastFold: stats.lastClose,
                  downSince: stats.downSince(now: now), average: stats.averageRef(now: now))
    }

    /// Après minuit, tant qu'aucun pli n'est venu mettre l'activité à jour : la nouvelle journée commence à zéro.
    func fresh(_ isStale: Bool) -> Self {
        guard isStale || day != ClapetStats.key(Date()) else { return self }
        var s = self
        s.today = 0
        return s
    }

    var hasLimit: Bool { limit > 0 }
    var left: Int { limit - today }
    /// Le repère : la limite, sinon la moyenne.
    var reference: Int { hasLimit ? limit : (average ?? 0) }
    var progress: Double { reference > 0 ? min(1, Double(today) / Double(reference)) : 0 }
}
