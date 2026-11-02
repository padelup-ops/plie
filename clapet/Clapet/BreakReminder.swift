import Foundation
import UserNotifications

// MARK: - Rappel de pause
//
// Quand le Duo reste ouvert longtemps (30 min par défaut), une notification douce propose une pause.
// L'iPhone l'envoie aussi sur l'Apple Watch quand il est verrouillé ou posé. Désactivé par défaut.
// Reprogrammé à chaque ouverture et annulé à chaque fermeture.

enum BreakReminder {
    static let key = "breakReminder"
    static let minutesKey = "breakReminderMinutes"
    static let choices = [20, 30, 45, 60]
    private static let id = "foldly.break"

    private static var defaults: UserDefaults { .standard }

    static var isOn: Bool { defaults.bool(forKey: key) }

    static var minutes: Int {
        let m = defaults.integer(forKey: minutesKey)
        return choices.contains(m) ? m : 30
    }

    static func setMinutes(_ m: Int, stats: ClapetStats) {
        defaults.set(m, forKey: minutesKey)
        schedule(stats)
    }

    static func setOn(_ on: Bool, stats: ClapetStats) {
        defaults.set(on, forKey: key)
        if on { schedule(stats) } else { cancel() }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Ouvert : une notification à « ouvert depuis + délai ». Fermé : rien en attente.
    static func schedule(_ stats: ClapetStats, now: Date = Date()) {
        cancel()
        guard isOn, let since = stats.openSince,
              now.timeIntervalSince(since) < ClapetStats.maxOpenSession else { return }
        let m = minutes
        let fire = since.addingTimeInterval(Double(m * 60))
        let wait = fire.timeIntervalSince(now)
        guard wait > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time for a break?")
        content.body = String(localized: "Your iPhone Duo has been open for \(m) min. Fold it for a moment.")
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
