import Foundation
import UserNotifications

/// Les deux rappels de l'essai gratuit : la veille de la fin, et le moment où il se termine.
/// Programmés dès que l'essai commence ; retirés si Pro est acheté.
enum TrialReminders {
    private static let ids = ["foldboard.trial.lastDay", "foldboard.trial.over"]

    static func update(_ access: KBAccess) {
        let center = UNUserNotificationCenter.current()
        guard !access.purchased, let end = access.trialEnd, end > Date() else {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            // Ce que le clavier a déjà appris : bien plus parlant qu'un rappel générique.
            let n = KBVault.loadLearn().all
            add(center, id: ids[0], at: end.addingTimeInterval(-86400),
                title: L("One day of free trial left"),
                body: n >= 3 ? String(format: L("Foldboard has learned %lld of your habits. Unlock Pro to keep them."), n)
                             : L("Tomorrow the keyboard stops following your hand. Unlock Foldboard Pro to keep it."))
            add(center, id: ids[1], at: end,
                title: L("Your free trial is over"),
                body: n >= 3 ? String(format: L("Your %lld learned habits are waiting. Open Foldboard to unlock Pro."), n)
                             : L("The keyboard no longer follows your hand. Open Foldboard to unlock Pro."))
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, at date: Date, title: String, body: String) {
        let wait = date.timeIntervalSinceNow
        guard wait > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
