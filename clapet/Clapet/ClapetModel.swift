import SwiftUI
import WidgetKit

/// Le compteur : il écoute la charnière tant que l'app est à l'écran.
@Observable
final class ClapetModel {
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
    @ObservationIgnored private var lastWidgetReload = Date.distantPast
    @ObservationIgnored private var pendingReload = false

    init() {
        let d = UserDefaults.standard
        soundOn = d.object(forKey: "sound") as? Bool ?? true
        hapticsOn = d.object(forKey: "haptics") as? Bool ?? true
    }

    // MARK: Charnière

    /// `closed` : l'état donné par iOS (nil s'il ne sait pas). `degrees` : l'angle.
    func hinge(closed: Bool?, degrees: Double?) {
        guard let degrees else { return }
        hasHinge = true
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

    // MARK: Compter

    func clap() {
        stats.addClose()
        claps += 1
        lastClapAt = Date()
        if soundOn { ClapetSound.shared.play(.clap) }
        if hapticsOn { ClapetHaptics.clap() }
        changed()
    }

    private func opened() {
        stats.addOpen()
        if soundOn { ClapetSound.shared.play(.pop) }
        if hapticsOn { ClapetHaptics.tick() }
        changed()
    }

    func setGoal(_ g: Int) {
        stats.goal = max(10, min(2000, g))
        changed()
    }

    func reset() {
        let goal = stats.goal
        stats = ClapetStats()
        stats.goal = goal
        changed()
    }

    // MARK: Sauvegarde et widgets

    func reload() {
        stats = ClapetVault.load()
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
