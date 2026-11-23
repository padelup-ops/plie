// Alerts.swift — Vicefold
//
// Les alertes de nouveau contenu (optionnelles) : de temps en temps, l'iPhone regarde si notre serveur a de nouveaux
// guides et prévient par une notification. Rien n'est envoyé : l'app ne fait que lire un fichier public.

import BackgroundTasks
import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class Alerts {
    static let shared = Alerts()
    static let task = "com.padelup.vicefold.refresh"

    var enabled = UserDefaults.standard.bool(forKey: "vicefold.alerts") {
        didSet { UserDefaults.standard.set(enabled, forKey: "vicefold.alerts"); if enabled { Task { await ask() } }; schedule() }
    }
    private(set) var denied = false

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.task, using: nil) { task in
            Task { @MainActor in
                let fresh = await ContentStore.shared.refresh()
                if fresh, Alerts.shared.enabled { Alerts.shared.notify() }
                Alerts.shared.schedule()
                task.setTaskCompleted(success: true)
            }
        }
    }

    func schedule() {
        guard enabled else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.task); return }
        let r = BGAppRefreshTaskRequest(identifier: Self.task)
        r.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }

    func check() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        denied = s.authorizationStatus == .denied
        schedule()
    }

    private func ask() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        denied = !ok
    }

    private func notify() {
        let c = UNMutableNotificationContent()
        c.title = String(localized: "New guides in Vicefold")
        c.body = ContentStore.shared.content.news?.first?.title ?? String(localized: "Fresh walkthroughs and map places are ready.")
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
