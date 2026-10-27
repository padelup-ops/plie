import SwiftUI
import WidgetKit

/// Le compteur : il écoute la charnière tant que l'app est à l'écran,
/// et reçoit les plis de l'automatisation Raccourcis « iPhone fermé » quand elle n'y est pas.
@Observable
final class ClapetModel {
    /// Le compteur de l'app en cours (pour les actions Raccourcis qui tournent dans l'app).
    static weak var current: ClapetModel?

    private(set) var stats = ClapetVault.load()
    /// Angle de la charnière (degrés), nil si l'appareil n'en a pas.
    private(set) var degrees: Double?
    private(set) var hasHinge = false
    private(set) var isClosed = false
    /// Change à chaque clapet (pour l'animation).
    private(set) var claps = 0
    private(set) var lastClapAt = Date.distantPast

    private(set) var soundOn: Bool
    private(set) var hapticsOn: Bool

    func setSound(_ on: Bool) {
        soundOn = on
        UserDefaults.standard.set(on, forKey: "sound")
    }

    func setHaptics(_ on: Bool) {
        hapticsOn = on
        UserDefaults.standard.set(on, forKey: "haptics")
    }

    @ObservationIgnored private var state: Bool?   // vrai : fermé, faux : ouvert, nil : pas encore vu
    /// La charnière était en train de se refermer (pour l'écran qui s'éteint avant la fin du geste).
    @ObservationIgnored private var closing = false
    @ObservationIgnored private var lastAngleAt = Date.distantPast
    /// Un même pli peut arriver par la charnière et par l'automatisation : on ne le compte qu'une fois.
    @ObservationIgnored private var lastHingeClose = Date.distantPast
    @ObservationIgnored private var lastAutoClose = Date.distantPast
    @ObservationIgnored private var lastHingeOpen = Date.distantPast
    @ObservationIgnored private var lastAutoOpen = Date.distantPast
    private let sameFold: TimeInterval = 3
    @ObservationIgnored private var lastWidgetReload = Date.distantPast
    @ObservationIgnored private var pendingReload = false

    init() {
        let d = UserDefaults.standard
        soundOn = d.object(forKey: "sound") as? Bool ?? false
        hapticsOn = d.object(forKey: "haptics") as? Bool ?? true
        if Demo.seeded { Demo.seed(&stats) }
        ClapetModel.current = self
    }

    // MARK: Charnière

    /// `closed` : l'état donné par iOS (nil s'il ne sait pas). `degrees` : l'angle.
    func hinge(closed: Bool?, degrees: Double?) {
        guard let degrees else { return }
        hasHinge = true
        if let previous = self.degrees {
            if degrees < previous - 0.5 { closing = true } else if degrees > previous + 0.5 { closing = false }
        }
        lastAngleAt = Date()
        self.degrees = degrees
        // Un peu d'hystérésis : fermé sous 12°, ouvert au-delà de 40°.
        let nowClosed: Bool?
        if closed == true || degrees < 12 {
            nowClosed = true
        } else if degrees > 40 || (closed == false && degrees > 25) {
            nowClosed = false
        } else {
            nowClosed = nil
        }
        guard let nowClosed else { return }
        isClosed = nowClosed
        defer { state = nowClosed }
        guard let previous = state, previous != nowClosed else { return }
        if nowClosed { clap() } else { opened() }
    }

    /// L'app quitte l'écran. Si c'est parce que le Duo se referme (l'écran s'éteint pendant le geste),
    /// iOS ne nous donne pas la fin du mouvement : on compte quand même ce pli.
    func leavingScreen() {
        guard state == false, closing, let d = degrees, d < 75,
              Date().timeIntervalSince(lastAngleAt) < 1.2 else { return }
        state = true
        isClosed = true
        clap()
    }

    // MARK: Compter

    /// Un pli vu par l'app (charnière, ou toucher sans charnière).
    func clap() {
        lastHingeClose = Date()
        if soundOn { ClapetSound.shared.play(.clap) }
        if hapticsOn { ClapetHaptics.clap() }
        // Déjà compté par l'automatisation il y a un instant ?
        guard Date().timeIntervalSince(lastAutoClose) > sameFold else { return }
        countClose()
    }

    private func opened() {
        lastHingeOpen = Date()
        if soundOn { ClapetSound.shared.play(.pop) }
        if hapticsOn { ClapetHaptics.tick() }
        guard Date().timeIntervalSince(lastAutoOpen) > sameFold else { return }
        stats.addOpen()
        changed()
    }

    /// Un pli envoyé par l'automatisation Raccourcis « iPhone fermé ».
    func automationClose() {
        lastAutoClose = Date()
        stats.autoLast = Date()
        if Date().timeIntervalSince(lastHingeClose) > sameFold {
            countClose()
        } else {
            changed()
        }
        // L'app peut être remise en veille juste après : les widgets tout de suite.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Une ouverture envoyée par l'automatisation Raccourcis « iPhone ouvert ».
    func automationOpen() {
        lastAutoOpen = Date()
        stats.autoLast = Date()
        if Date().timeIntervalSince(lastHingeOpen) > sameFold { stats.addOpen() }
        changed()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func countClose() {
        let before = stats.today
        stats.addClose()
        LimitAlerts.check(before: before, after: stats.today, limit: stats.goal, plus: stats.plus)
        claps += 1
        lastClapAt = Date()
        changed()
    }

    func setGoal(_ g: Int) {
        stats.goal = max(10, min(2000, g))
        changed()
    }

    func reset() {
        var fresh = ClapetStats()
        fresh.goal = stats.goal
        fresh.plus = stats.plus
        fresh.theme = stats.theme
        stats = fresh
        changed()
    }

    // MARK: Duo Folds+

    /// Écrit dans le coffre partagé, pour que les widgets se débloquent aussitôt.
    func setPlus(_ on: Bool) {
        guard stats.plus != on else { return }
        stats.plus = on
        flush()
    }

    func setTheme(_ theme: ClapetTheme) {
        stats.theme = theme.rawValue
        flush()
    }

    /// Alertes de limite (Duo Folds+).
    private(set) var alertsOn = LimitAlerts.enabled

    /// Renvoie faux si iOS refuse les notifications.
    @MainActor
    func setAlerts(_ on: Bool) async -> Bool {
        if on {
            let ok = await LimitAlerts.requestPermission()
            LimitAlerts.setEnabled(ok)
            alertsOn = ok
            return ok
        }
        LimitAlerts.setEnabled(false)
        alertsOn = false
        return true
    }

    // MARK: Sauvegarde et widgets

    func reload() {
        guard !Demo.seeded else { return }
        let plus = stats.plus
        stats = ClapetVault.load()
        stats.plus = plus
    }

    func flush() {
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func changed() {
        ClapetVault.save(stats)
        // Les widgets suivent, sans les recharger à chaque clapet.
        let wait = 1.5 - Date().timeIntervalSince(lastWidgetReload)
        if wait <= 0 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else if !pendingReload {
            pendingReload = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.pendingReload = false
                self.lastWidgetReload = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

/// Lit la charnière de l'iPhone Duo (iOS 27.1). Ailleurs, ne fait rien.
struct HingeReader: ViewModifier {
    let action: (Bool?, Double?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else {
                    action(nil, nil)
                    return
                }
                let closed: Bool?
                if hinge.status == .closed {
                    closed = true
                } else if hinge.status == .fullyOpen || hinge.status == .partiallyOpen {
                    closed = false
                } else {
                    closed = nil
                }
                action(closed, hinge.angle.degrees)
            }
        } else {
            content
        }
    }
}
