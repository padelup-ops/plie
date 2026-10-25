import CoreMotion
import Foundation

/// Mouvements du téléphone : la gravité (pour savoir comment il est tenu) et les secousses.
/// Pas d'autorisation à demander : ce sont les capteurs de mouvement de base.
final class MotionSensor {
    struct Reading {
        /// Gravité dans le repère du téléphone (z sort de l'écran).
        let gx: Double
        let gy: Double
        let gz: Double
        /// Force de la secousse (accélération due à l'utilisateur, en g).
        let shake: Double
    }

    private let manager = CMMotionManager()
    var onReading: ((Reading) -> Void)?

    var available: Bool { manager.isDeviceMotionAvailable }

    func start(hz: Double = 30) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / hz
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let a = motion.userAcceleration
            let g = motion.gravity
            self?.onReading?(Reading(gx: g.x, gy: g.y, gz: g.z, shake: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()))
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }
}
