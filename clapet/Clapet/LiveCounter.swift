import ActivityKit
import Foundation

/// Démarre, met à jour et arrête le compteur en direct (Live Activity).
enum LiveCounter {
    private static let key = "liveActivity"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// iOS autorise-t-il les activités en direct pour Foldly ?
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static var running: [Activity<FoldActivityAttributes>] {
        Activity<FoldActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// À appeler depuis l'app au premier plan (iOS refuse de démarrer une activité en arrière-plan).
    @discardableResult
    static func start(_ stats: ClapetStats) -> Bool {
        guard allowed else { return false }
        UserDefaults.standard.set(true, forKey: key)
        if !running.isEmpty {
            refresh(stats)
            return true
        }
        do {
            _ = try Activity.request(attributes: FoldActivityAttributes(), content: content(stats), pushType: nil)
            return true
        } catch {
            UserDefaults.standard.set(false, forKey: key)
            return false
        }
    }

    static func stop() {
        UserDefaults.standard.set(false, forKey: key)
        for activity in Activity<FoldActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// À chaque pli (app ouverte ou action Raccourcis en arrière-plan).
    static func refresh(_ stats: ClapetStats) {
        guard isOn else { return }
        let c = content(stats)
        for activity in running {
            Task { await activity.update(c) }
        }
    }

    /// Au retour dans l'app : iOS arrête une activité au bout de quelques heures, on la relance.
    static func resume(_ stats: ClapetStats) {
        guard isOn else { return }
        if running.isEmpty { start(stats) } else { refresh(stats) }
    }

    private static func content(_ stats: ClapetStats) -> ActivityContent<FoldActivityAttributes.ContentState> {
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
        return ActivityContent(state: FoldActivityAttributes.ContentState(stats: stats), staleDate: midnight)
    }
}
