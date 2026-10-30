import Foundation
import UserNotifications

/// Le bilan du soir (21 h 30) : les plis, le temps ouvert et le temps fermé. Reprogrammé à chaque changement, avec les chiffres du moment.
enum EveningSummary {
    private static let key = "eveningSummary"
    private static let id = "foldly.evening"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Renvoie faux si iOS refuse les notifications.
    static func setOn(_ on: Bool, stats: ClapetStats) async -> Bool {
        if on {
            let ok = await LimitAlerts.requestPermission()
            UserDefaults.standard.set(ok, forKey: key)
            if ok { schedule(stats) }
            return ok
        }
        UserDefaults.standard.set(false, forKey: key)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        return true
    }

    static func schedule(_ stats: ClapetStats, now: Date = Date()) {
        guard isOn else { return }
        let cal = Calendar.current
        var at = cal.dateComponents([.year, .month, .day], from: now)
        at.hour = 21
        at.minute = 30
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your day with Foldly")
        if let fire = cal.date(from: at), fire > now {
            let open = TimeFormat.short(stats.openTime(now, now: now))
            let closed = TimeFormat.short(stats.closedTime(now, now: now))
            let day = stats.day(now)
            content.body = String(localized: "\(day.closes) folds · \(open) open · \(closed) closed")
        } else {
            // Déjà passé 21 h 30 : demain, sans chiffres (ils seront mis à jour au premier pli).
            at = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: 1, to: now) ?? now)
            at.hour = 21
            at.minute = 30
            content.body = String(localized: "Your folds and your time open and closed today.")
        }
        content.sound = nil
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: at, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
