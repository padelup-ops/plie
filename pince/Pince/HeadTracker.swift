import ARKit
import AVFoundation
import CoreMotion
import UIKit
import Vision
import simd

/// Où sont les yeux du joueur par rapport à l'écran ?
///
/// Trois façons de le savoir, de la plus précise à la plus simple :
/// 1. le suivi du visage d'ARKit (capteur de profondeur) : la position des yeux en vrais mètres ;
/// 2. la caméra avant ordinaire : on repère le visage dans l'image, sa place donne la direction et sa taille la distance.
///    C'est elle qui sert quand ARKit ne voit rien, par exemple avec la caméra intérieure de l'iPhone Duo ouvert ;
/// 3. sans caméra du tout (refus), l'inclinaison de l'appareil.
///
/// Dans tous les cas on rend la position du milieu des yeux en mètres dans le repère de l'écran : x vers la droite,
/// y vers le haut, z = distance. La position mesurée au premier regard sert de point neutre « bien en face »,
/// ce qui évite de devoir savoir où est la caméra sur chaque appareil.
final class HeadTracker: NSObject, ARSessionDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Mode { case none, face, camera, tilt }

    /// Appelé sur le fil principal. `nil` : le visage n'est plus vu, on revient en face.
    var onEye: ((SIMD3<Float>?) -> Void)?
    var onMode: ((Mode) -> Void)?
    /// Le visage est-il vu, et à quelle distance (en mètres) ? Appelé sur le fil principal quand ça change.
    var onSeen: ((Bool, Float) -> Void)?
    var orientation: UIInterfaceOrientation = .portrait {
        didSet {
            guard oldValue != orientation else { return }
            recenter()
            let now = orientation
            captureQueue.async { self.applyRotation(now) }
        }
    }

    /// Vrai : on n'essaie pas ARKit, on prend tout de suite la caméra ordinaire.
    var prefersCamera = false
    /// Cet appareil sait-il suivre un visage en 3D ?
    static var hasDepthTracking: Bool { ARFaceTrackingConfiguration.isSupported }

    private(set) var mode: Mode = .none
    private let session = ARSession()
    private let motion = CMMotionManager()
    private var running = false

    private var neutral: SIMD2<Float>?
    private var samples: [SIMD2<Float>] = []
    private var lastSeen = Date.distantPast
    private var seen = false
    private var reportedDistance: Float = 0
    private var level: SIMD2<Float>?
    private var watchdog: Timer?

    // La caméra ordinaire
    private let capture = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "peekaclaw.head.camera")
    private let output = AVCaptureVideoDataOutput()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private var configured = false
    /// La focale, en « grands côtés d'image » : 0,5 / tan(champ / 2).
    private var focal: Float = 0.87
    private var smooth: SIMD3<Float>?

    func start() {
        guard !running else { return }
        running = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCameraTracking()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.running, self.mode == .none else { return }
                    if granted { self.startCameraTracking() } else { self.startTilt() }
                }
            }
        default:
            startTilt()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        watchdog?.invalidate()
        watchdog = nil
        if mode == .face { session.pause() }
        captureQueue.async { if self.capture.isRunning { self.capture.stopRunning() } }
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        set(.none)
        report(false, 0)
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

    private func report(_ nowSeen: Bool, _ distance: Float) {
        // La distance n'est annoncée que si elle a bougé d'au moins 3 cm : inutile de redessiner l'écran pour moins.
        guard nowSeen != seen || abs(distance - reportedDistance) > 0.03 else { return }
        seen = nowSeen
        reportedDistance = distance
        onSeen?(nowSeen, distance)
    }

    /// Une mesure de la tête, d'où qu'elle vienne. `nil` : pas de visage dans cette image.
    private func feed(_ head: SIMD3<Float>?) {
        guard let head else {
            if seen, Date().timeIntervalSince(lastSeen) > 0.6 {
                report(false, 0)
                onEye?(nil)
            }
            return
        }
        lastSeen = Date()
        report(true, head.z)
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

    private func startCameraTracking() {
        if ARFaceTrackingConfiguration.isSupported, !prefersCamera { startFace() } else { startCamera() }
    }

    // MARK: 1. Le visage en 3D (ARKit)

    private func startFace() {
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        recenter()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        set(.face)
        // Si ARKit n'a toujours vu personne au bout de quelques secondes, on passe à la caméra ordinaire.
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self, self.running, self.mode == .face, !self.seen else { return }
            self.session.pause()
            self.startCamera()
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, mode == .face else { return }
        guard let face = frame.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first(where: { $0.isTracked }) else {
            feed(nil)
            return
        }
        // Le milieu des deux yeux, d'abord dans le repère du visage, puis dans celui du monde.
        let mid = (face.leftEyeTransform.columns.3 + face.rightEyeTransform.columns.3) * 0.5
        let world = face.transform * SIMD4<Float>(mid.x, mid.y, mid.z, 1)
        // Repère de la caméra, tourné comme l'interface : x vers la droite de l'image, y vers le haut,
        // et la caméra regarde vers −z. La caméra avant regarde le joueur : sa droite est la gauche de l'écran.
        let view = frame.camera.viewMatrix(for: orientation) * world
        let head = SIMD3<Float>(-view.x, view.y, abs(view.z))
        guard head.z > 0.1, head.z < 1.5 else { return }
        feed(head)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard running, mode == .face else { return }
        session.pause()
        startCamera()
    }

    // MARK: 2. Le visage dans l'image (caméra avant ordinaire)

    private func startCamera() {
        watchdog?.invalidate()
        watchdog = nil
        recenter()
        smooth = nil
        set(.camera)
        let now = orientation
        captureQueue.async {
            if !self.configured { self.configured = self.configureCapture() }
            guard self.configured else {
                DispatchQueue.main.async { if self.running, self.mode == .camera { self.startTilt() } }
                return
            }
            self.applyRotation(now)
            if !self.capture.isRunning { self.capture.startRunning() }
        }
    }

    /// Sur la file de la caméra.
    private func configureCapture() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        capture.beginConfiguration()
        defer { capture.commitConfiguration() }
        if capture.canSetSessionPreset(.vga640x480) { capture.sessionPreset = .vga640x480 }
        guard capture.canAddInput(input) else { return false }
        capture.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard capture.canAddOutput(output) else { return false }
        capture.addOutput(output)
        let field = camera.activeFormat.videoFieldOfView
        if field > 20, field < 150 { focal = 0.5 / tan(field * .pi / 360) }
        return true
    }

    /// L'image arrive droite et en miroir, comme dans une glace : ce qui est à droite dans l'image est à droite de l'écran.
    /// Sur la file de la caméra.
    private func applyRotation(_ interface: UIInterfaceOrientation) {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        if connection.isVideoOrientationSupported {
            switch interface {
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default: connection.videoOrientation = .portrait
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:]).perform([faceRequest])
        let width = Float(CVPixelBufferGetWidth(pixels)), height = Float(CVPixelBufferGetHeight(pixels))
        var head: SIMD3<Float>?
        // Le plus grand visage de l'image : celui du joueur.
        if let box = (faceRequest.results ?? []).map({ $0.boundingBox }).max(by: { $0.width < $1.width }) {
            let focalPixels = focal * max(width, height)
            let facePixels = Float(box.width) * width
            if facePixels > 12 {
                // Un visage fait à peu près 15 cm de large : sa taille dans l'image donne la distance.
                let distance = max(0.15, min(1.4, focalPixels * 0.155 / facePixels))
                let x = (Float(box.midX) - 0.5) * width / focalPixels * distance
                let y = (Float(box.midY) - 0.5) * height / focalPixels * distance
                head = SIMD3<Float>(x, y, distance)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.mode == .camera else { return }
            guard let head else {
                self.feed(nil)
                return
            }
            // Le cadre du visage tremble un peu, surtout sa taille : on lisse, la distance plus que le reste.
            var value = self.smooth ?? head
            value.x += (head.x - value.x) * 0.4
            value.y += (head.y - value.y) * 0.4
            value.z += (head.z - value.z) * 0.12
            self.smooth = value
            self.feed(value)
        }
    }

    // MARK: 3. L'inclinaison (sans caméra)

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
