import ARKit
import AVFoundation
import CoreMotion
import UIKit
import simd

/// Où sont les yeux du joueur par rapport à l'écran ?
///
/// La caméra avant suit le visage (ARKit). On en tire la position du milieu des deux yeux, en mètres, dans le repère
/// de l'écran : x vers la droite, y vers le haut, z = distance à l'écran. La position mesurée au premier regard sert
/// de point neutre « bien en face », ce qui évite de devoir savoir où est la caméra sur chaque appareil.
/// Sans caméra (refus, appareil sans suivi du visage), on se rabat sur l'inclinaison de l'appareil.
final class HeadTracker: NSObject, ARSessionDelegate {
    enum Mode { case none, face, tilt }

    /// Appelé sur le fil principal. `nil` : le visage n'est plus vu, on revient en face.
    var onEye: ((SIMD3<Float>?) -> Void)?
    var onMode: ((Mode) -> Void)?
    var orientation: UIInterfaceOrientation = .portrait {
        didSet { if oldValue != orientation { recenter() } }
    }

    private(set) var mode: Mode = .none
    private let session = ARSession()
    private let motion = CMMotionManager()
    private var running = false

    private var neutral: SIMD2<Float>?
    private var samples: [SIMD2<Float>] = []
    private var lastSeen: TimeInterval = 0
    private var lost = true
    private var level: SIMD2<Float>?

    func start() {
        guard !running else { return }
        running = true
        guard ARFaceTrackingConfiguration.isSupported else { startTilt(); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startFace()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.running else { return }
                    if granted { self.startFace() } else { self.startTilt() }
                }
            }
        default:
            startTilt()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if mode == .face { session.pause() }
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        set(.none)
        onEye?(nil)
    }

    /// La position actuelle de la tête redevient « bien en face ».
    func recenter() {
        neutral = nil
        samples.removeAll()
        level = nil
    }

    private func set(_ m: Mode) {
        guard m != mode else { return }
        mode = m
        onMode?(m)
    }

    // MARK: Le visage

    private func startFace() {
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        recenter()
        lost = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        set(.face)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, mode == .face else { return }
        guard let face = frame.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first(where: { $0.isTracked }) else {
            if !lost, frame.timestamp - lastSeen > 0.6 {
                lost = true
                onEye?(nil)
            }
            return
        }
        lastSeen = frame.timestamp
        lost = false

        // Le milieu des deux yeux, d'abord dans le repère du visage, puis dans celui du monde.
        let mid = (face.leftEyeTransform.columns.3 + face.rightEyeTransform.columns.3) * 0.5
        let world = face.transform * SIMD4<Float>(mid.x, mid.y, mid.z, 1)
        // Repère de la caméra, tourné comme l'interface : x vers la droite de l'image, y vers le haut,
        // et la caméra regarde vers −z. La caméra avant regarde le joueur : sa droite est la gauche de l'écran.
        let view = frame.camera.viewMatrix(for: orientation) * world
        let head = SIMD3<Float>(-view.x, view.y, -view.z)
        guard head.z > 0.1, head.z < 1.5 else { return }

        guard let zero = neutral else {
            samples.append(SIMD2<Float>(head.x, head.y))
            if samples.count >= 10 {
                neutral = samples.reduce(SIMD2<Float>(0, 0), +) / Float(samples.count)
                samples.removeAll()
            }
            onEye?(SIMD3<Float>(0, 0, head.z))
            return
        }
        onEye?(SIMD3<Float>(head.x - zero.x, head.y - zero.y, head.z))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard running else { return }
        session.pause()
        startTilt()
    }

    // MARK: L'inclinaison (solution de repli)

    private func startTilt() {
        guard motion.isDeviceMotionAvailable else {
            set(.none)
            onEye?(nil)
            return
        }
        level = nil
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, self.running, let g = data?.gravity else { return }
            // La gravité dans le repère de l'appareil, ramenée au repère de l'interface.
            let x = Float(g.x), y = Float(g.y)
            let now: SIMD2<Float>
            switch self.orientation {
            case .landscapeRight: now = SIMD2<Float>(-y, x)
            case .landscapeLeft: now = SIMD2<Float>(y, -x)
            case .portraitUpsideDown: now = SIMD2<Float>(-x, -y)
            default: now = SIMD2<Float>(x, y)
            }
            // La référence suit lentement la posture : on penche pour jeter un œil, puis la vue se recentre.
            var zero = self.level ?? now
            zero += (now - zero) * 0.006
            self.level = zero
            let lean = now - zero
            // Pencher le bord droit vers le bas revient à regarder l'écran depuis la gauche.
            self.onEye?(SIMD3<Float>(-lean.x * 0.42, -lean.y * 0.42, 0))
        }
        set(.tilt)
    }
}
