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
/// Le filtre « 1 € » : il lisse beaucoup quand la tête est immobile (plus de tremblement) et presque plus quand
/// elle bouge (pas de retard). C'est le filtre habituel pour ce genre de suivi.
private struct OneEuro {
    var calm: Float
    var lively: Float
    private var value: Float?
    private(set) var speed: Float = 0

    init(calm: Float, lively: Float) {
        self.calm = calm
        self.lively = lively
    }

    mutating func reset() {
        value = nil
        speed = 0
    }

    private static func blend(_ cutoff: Float, _ dt: Float) -> Float {
        1 / (1 + 1 / (2 * Float.pi * cutoff * dt))
    }

    mutating func step(_ x: Float, dt: Float) -> Float {
        guard let last = value, dt > 0 else {
            value = x
            return x
        }
        speed += ((x - last) / dt - speed) * OneEuro.blend(1, dt)
        let out = last + (x - last) * OneEuro.blend(calm + lively * abs(speed), dt)
        value = out
        return out
    }
}

final class HeadTracker: NSObject, ARSessionDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Mode { case none, face, camera, tilt }

    /// Appelé sur le fil principal. `nil` : le visage n'est plus vu, on revient en face.
    var onEye: ((SIMD3<Float>?) -> Void)?
    var onMode: ((Mode) -> Void)?
    /// Le visage est-il vu, et où (en mètres : décalage vers la droite, vers le haut, distance) ?
    /// Appelé sur le fil principal quand ça change d'au moins un centimètre.
    var onSeen: ((Bool, SIMD3<Float>) -> Void)?
    var orientation: UIInterfaceOrientation = .portrait {
        didSet {
            guard oldValue != orientation else { return }
            recenter()
            let now = orientation
            captureQueue.async { self.applyRotation(now) }
        }
    }

    /// Comment lire la mesure pour cet écran : quel axe mesuré va vers la droite, et dans quel sens.
    /// Sur un appareil ordinaire, il n'y a rien à tourner. Sur l'écran intérieur de l'iPhone Duo, l'orientation
    /// annoncée ne dit pas comment la caméra est posée : le joueur fait le réglage une fois, en deux gestes.
    struct Mapping: Equatable {
        var swapped = false
        var signX: Float = 1
        var signY: Float = 1

        func apply(_ v: SIMD2<Float>) -> SIMD2<Float> {
            swapped ? SIMD2<Float>(v.y * signX, v.x * signY) : SIMD2<Float>(v.x * signX, v.y * signY)
        }

        /// Le réglage qui envoie le geste « vers la droite » sur +x et le geste « vers le haut » sur +y.
        /// `nil` si les deux gestes vont dans la même direction ou sont trop petits.
        static func from(right: SIMD2<Float>, up: SIMD2<Float>) -> Mapping? {
            let swapped = abs(right.y) > abs(right.x)
            let along = swapped ? right.y : right.x
            let across = swapped ? up.x : up.y
            guard abs(along) > 0.025, abs(across) > 0.015 else { return nil }
            return Mapping(swapped: swapped, signX: along > 0 ? 1 : -1, signY: across > 0 ? 1 : -1)
        }
    }

    var mapping = Mapping() {
        didSet { if oldValue != mapping { recenter() } }
    }
    /// La dernière mesure, avant réglage et avant filtrage (x, y en mètres). Sert au réglage.
    private(set) var lastRaw: SIMD2<Float>?

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
    private var reported = SIMD3<Float>(0, 0, 0)
    private var filterX = OneEuro(calm: 2.5, lively: 40)
    private var filterY = OneEuro(calm: 2.5, lively: 40)
    private var filterZ = OneEuro(calm: 0.8, lively: 6)
    private var lastFeed = Date.distantPast
    /// Vrai quand la vue a été remise en face faute de visage.
    private var parked = true
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
        report(false, SIMD3<Float>(0, 0, 0))
        onEye?(nil)
    }

    /// La position actuelle de la tête redevient « bien en face ».
    func recenter() {
        neutral = nil
        samples.removeAll()
        level = nil
        filterX.reset()
        filterY.reset()
        filterZ.reset()
    }

    /// Après un réglage : ce point mesuré devient « bien en face ».
    func recenter(onRaw point: SIMD2<Float>) {
        recenter()
        neutral = mapping.apply(point)
    }

    /// La caméra ordinaire tremble plus que le capteur 3D : on règle le filtre en conséquence.
    private func tune(calm: Float, lively: Float) {
        filterX = OneEuro(calm: calm, lively: lively)
        filterY = OneEuro(calm: calm, lively: lively)
        filterZ = OneEuro(calm: calm * 0.3, lively: lively * 0.15)
    }

    private func set(_ m: Mode) {
        guard m != mode else { return }
        mode = m
        onMode?(m)
    }

    private func report(_ nowSeen: Bool, _ where_: SIMD3<Float>) {
        // Annoncé seulement si ça a bougé d'au moins un centimètre : inutile de redessiner l'écran pour moins.
        guard nowSeen != seen || simd_distance(where_, reported) > 0.01 else { return }
        seen = nowSeen
        reported = where_
        onSeen?(nowSeen, where_)
    }

    /// Une mesure de la tête, d'où qu'elle vienne. `nil` : pas de visage dans cette image.
    private func feed(_ raw: SIMD3<Float>?) {
        let now = Date()
        guard let raw else {
            // Le visage sort du champ de la caméra, typiquement quand on se penche loin sur le côté.
            // La vue ne revient pas au centre : elle reste où elle était, comme si la tête s'était arrêtée là.
            // Ce n'est qu'au bout de quelques secondes sans personne qu'elle se remet doucement en face.
            let gone = now.timeIntervalSince(lastSeen)
            if seen, gone > 0.6 {
                report(false, SIMD3<Float>(0, 0, 0))
                filterX.reset()
                filterY.reset()
                filterZ.reset()
            }
            if !parked, gone > 6 {
                parked = true
                onEye?(nil)
            }
            return
        }
        parked = false
        let dt = Float(min(0.1, max(0.004, now.timeIntervalSince(lastFeed))))
        lastFeed = now
        lastSeen = now
        lastRaw = SIMD2<Float>(raw.x, raw.y)
        let turned = mapping.apply(SIMD2<Float>(raw.x, raw.y))
        var head = SIMD3<Float>(filterX.step(turned.x, dt: dt), filterY.step(turned.y, dt: dt), filterZ.step(raw.z, dt: dt))
        // Un rien d'avance : on place la tête là où elle sera quand l'image s'affichera.
        head.x += max(-0.02, min(0.02, filterX.speed * 0.025))
        head.y += max(-0.02, min(0.02, filterY.speed * 0.025))
        guard let zero = neutral else {
            samples.append(SIMD2<Float>(head.x, head.y))
            if samples.count >= 10 {
                neutral = samples.reduce(SIMD2<Float>(0, 0), +) / Float(samples.count)
                samples.removeAll()
            }
            report(true, SIMD3<Float>(0, 0, head.z))
            onEye?(SIMD3<Float>(0, 0, head.z))
            return
        }
        let eye = SIMD3<Float>(head.x - zero.x, head.y - zero.y, head.z)
        report(true, eye)
        onEye?(eye)
    }

    private func startCameraTracking() {
        if ARFaceTrackingConfiguration.isSupported, !prefersCamera { startFace() } else { startCamera() }
    }

    // MARK: 1. Le visage en 3D (ARKit)

    private func startFace() {
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        tune(calm: 2.5, lively: 40)
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
        // Repère de la caméra, tourné comme l'interface. Avec la caméra avant, ARKit donne un monde « en miroir »
        // (c'est ce qui lui permet de dessiner par-dessus l'image retournée) : x grandit vers la droite de l'écran.
        // C'est aussi ce que fait TheParallaxView, le projet de référence de cette technique, qui inverse x pour
        // retrouver le monde réel.
        let view = frame.camera.viewMatrix(for: orientation) * world
        let head = SIMD3<Float>(view.x, view.y, abs(view.z))
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
        tune(calm: 1.2, lively: 22)
        recenter()
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
            self.feed(head)
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
