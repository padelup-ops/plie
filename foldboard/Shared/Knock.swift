// Knock.swift — Foldboard
//
// Taper le bord de l'iPhone (le cadre, à gauche ou à droite) met le clavier à une main de ce côté.
// Un coup sur le côté fait bouger le téléphone de travers d'un coup sec : un pic d'accélération sur l'axe
// gauche-droite, alors que taper sur l'écran le fait bouger surtout d'avant en arrière. On ne garde que les pics
// nets, téléphone tenu tranquille juste avant, et loin de toute frappe sur une touche.

import CoreMotion
import Foundation

final class KBKnock {
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "foldboard.knock"
        q.maxConcurrentOperationCount = 1
        return q
    }()
    /// true : le coup a poussé le téléphone vers la droite de l'appareil (on a tapé son bord gauche).
    var onKnock: ((Bool) -> Void)?
    /// L'instant du dernier toucher à l'écran (horloge des événements), mis à jour par le clavier.
    var lastTouch: TimeInterval = 0
    private var prev = (x: 0.0, y: 0.0, z: 0.0)
    private var hp = (x: 0.0, y: 0.0, z: 0.0)
    private var recent: [Double] = []
    private var lastKnock: TimeInterval = 0
    private var warm = 0

    var running: Bool { motion.isAccelerometerActive }

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        warm = 0
        recent = []
        motion.accelerometerUpdateInterval = 1.0 / 100
        motion.startAccelerometerUpdates(to: queue) { [weak self] d, _ in
            guard let self, let d else { return }
            self.process(d.timestamp, d.acceleration.x, d.acceleration.y, d.acceleration.z)
        }
    }

    func stop() {
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
    }

    private func process(_ t: TimeInterval, _ x: Double, _ y: Double, _ z: Double) {
        // Filtre passe-haut : on enlève la gravité et les mouvements lents de la main.
        let a = 0.8
        hp = (a * (hp.x + x - prev.x), a * (hp.y + y - prev.y), a * (hp.z + z - prev.z))
        prev = (x, y, z)
        warm += 1
        let mag = (hp.x * hp.x + hp.y * hp.y + hp.z * hp.z).squareRoot()
        defer {
            recent.append(mag)
            if recent.count > 35 { recent.removeFirst() }
        }
        guard warm > 30, recent.count >= 30 else { return }
        let calm = recent.prefix(recent.count - 3).reduce(0, +) / Double(max(1, recent.count - 3))
        let side = abs(hp.x), other = max(abs(hp.y), abs(hp.z))
        guard side > 0.42, side > other * 2.2, calm < 0.07,
              t - lastKnock > 0.8, t - lastTouch > 0.35 else { return }
        lastKnock = t
        let pushedRight = hp.x > 0
        DispatchQueue.main.async { [weak self] in self?.onKnock?(pushedRight) }
    }
}
