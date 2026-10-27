import UserNotifications

/// Alertes de limite (Duo Folds+) : une notification à 80 % puis à 100 % de la limite du jour.
enum LimitAlerts {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "alerts") }

    static func setEnabled(_ on: Bool) { UserDefaults.standard.set(on, forKey: "alerts") }

    /// Demande la permission d'afficher des notifications.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Après un pli : prévient quand on passe 80 % puis 100 % de la limite.
    static func check(before: Int, after: Int, limit: Int, plus: Bool) {
        guard plus, enabled, limit > 0 else { return }
        let warn = Int((Double(limit) * 0.8).rounded(.up))
        if before < limit && after >= limit {
            post(id: "limit",
                 title: String(localized: "Daily limit reached"),
                 body: String(localized: "\(after) folds today. Time for a break from your phone?"))
        } else if before < warn && after >= warn {
            post(id: "warn",
                 title: String(localized: "Almost at your limit"),
                 body: String(localized: "\(after) folds today, your limit is \(limit)."))
        }
    }

    private static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "duofolds.\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Montre aussi les alertes quand l'app est à l'écran.
final class AlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
