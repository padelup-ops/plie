import AVFoundation
import CoreImage
import UIKit
import Vision

// MARK: - La caméra des gestes
//
// Pour jouer sans toucher l'écran : sur l'iPhone Duo ouvert, l'écran extérieur ne fait qu'afficher,
// alors la personne en face joue avec ses mains (doigts levés, pierre-feuille-ciseaux) ou son visage (sourire).
// Tout est analysé sur le téléphone, image par image ; rien n'est enregistré ni envoyé.
// La caméra doit tourner pour que l'écran extérieur reste allumé.

/// Ce qu'une main montre à la caméra.
struct HandReading: Equatable {
    enum Shape: String, CaseIterable {
        case rock, paper, scissors

        var emoji: String {
            switch self {
            case .rock: return "✊"
            case .paper: return "✋"
            case .scissors: return "✌️"
            }
        }

        var name: String {
            switch self {
            case .rock: return L("Pierre")
            case .paper: return L("Feuille")
            case .scissors: return L("Ciseaux")
            }
        }

        /// Vrai si `self` bat `other`.
        func beats(_ other: Shape) -> Bool {
            switch (self, other) {
            case (.rock, .scissors), (.paper, .rock), (.scissors, .paper): return true
            default: return false
            }
        }
    }

    /// Doigts levés, pouce compris (0 à 5).
    var fingers: Int
    /// Pierre, feuille ou ciseaux, si la main en montre un clairement.
    var shape: Shape?
}

final class GestureCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    /// Ce qu'on cherche dans les images (à régler avant `start`).
    var detectsHands = true
    var detectsSmile = false

    /// Les mains vues dans l'image (0, 1 ou 2). Appelé sur le fil principal, une dizaine de fois par seconde.
    var onHands: (([HandReading]) -> Void)?
    /// Un visage est-il vu, et sourit-il ? Appelé sur le fil principal.
    var onFace: ((_ seen: Bool, _ smiling: Bool) -> Void)?

    private let queue = DispatchQueue(label: "app.plie.gesture.camera")
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: nil)
    private let lock = NSLock()
    private var latest: CIImage?
    private var lastAnalysis = Date.distantPast
    private var faceDetector: CIDetector?
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    private(set) var position: AVCaptureDevice.Position = .back

    // MARK: Démarrer, arrêter

    /// Demande l'autorisation, configure l'objectif voulu et lance la caméra. `completion` sur le fil principal.
    func start(position: AVCaptureDevice.Position, completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.queue.async {
                let ok = self.configure(position: position)
                if ok && !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    /// Change d'objectif sans arrêter la caméra (l'écran extérieur reste allumé).
    func switchTo(_ position: AVCaptureDevice.Position, completion: ((Bool) -> Void)? = nil) {
        queue.async {
            let ok = self.configure(position: position)
            if ok && !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        if self.position == position, !session.inputs.isEmpty { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        for input in session.inputs { session.removeInput(input) }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        self.position = camera.position
        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = camera.position == .front
            }
        }
        return true
    }

    // MARK: Les images

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        lock.lock()
        latest = image
        lock.unlock()

        // Une dizaine d'analyses par seconde suffisent, et ménagent la batterie.
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= 0.09 else { return }
        lastAnalysis = now

        if detectsHands {
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
            var hands: [HandReading] = []
            if (try? handler.perform([handRequest])) != nil {
                hands = (handRequest.results ?? []).compactMap(Self.read)
            }
            DispatchQueue.main.async { [weak self] in self?.onHands?(hands) }
        }
        if detectsSmile {
            if faceDetector == nil {
                faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: ciContext,
                                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorTracking: true])
            }
            let faces = (faceDetector?.features(in: image, options: [CIDetectorSmile: true, CIDetectorImageOrientation: 1]) ?? [])
                .compactMap { $0 as? CIFaceFeature }
            // Le plus grand visage : celui qui est face à la caméra.
            let face = faces.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            let seen = face != nil
            let smiling = face?.hasSmile ?? false
            DispatchQueue.main.async { [weak self] in self?.onFace?(seen, smiling) }
        }
    }

    /// La dernière image, pour une photo souvenir.
    func snapshot() -> UIImage? {
        lock.lock()
        let image = latest
        lock.unlock()
        guard let image, let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Lire une main

    private static func read(_ observation: VNHumanHandPoseObservation) -> HandReading? {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence > 0.3 else { return nil }

        func point(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            return p.location
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        let w = wrist.location
        /// Un doigt est tendu si son bout est nettement plus loin du poignet que sa phalange du milieu,
        /// et si la phalange continue dans la même direction (le doigt n'est pas replié).
        func extended(_ tip: VNHumanHandPoseObservation.JointName,
                      _ pip: VNHumanHandPoseObservation.JointName,
                      _ mcp: VNHumanHandPoseObservation.JointName) -> Bool {
            guard let t = point(tip), let p = point(pip), let m = point(mcp) else { return false }
            guard distance(t, w) > distance(p, w) * 1.12 else { return false }
            let v1 = CGVector(dx: p.x - m.x, dy: p.y - m.y)
            let v2 = CGVector(dx: t.x - p.x, dy: t.y - p.y)
            let n1 = hypot(v1.dx, v1.dy), n2 = hypot(v2.dx, v2.dy)
            guard n1 > 0, n2 > 0 else { return false }
            return (v1.dx * v2.dx + v1.dy * v2.dy) / (n1 * n2) > 0.45
        }

        let index = extended(.indexTip, .indexPIP, .indexMCP)
        let middle = extended(.middleTip, .middlePIP, .middleMCP)
        let ring = extended(.ringTip, .ringPIP, .ringMCP)
        let little = extended(.littleTip, .littlePIP, .littleMCP)

        // Le pouce : son bout s'écarte de la base de l'index, et s'éloigne du poignet.
        var thumb = false
        if let tip = point(.thumbTip), let ip = point(.thumbIP), let mp = point(.thumbMP), let base = point(.indexMCP) {
            thumb = distance(tip, base) > distance(ip, base) * 1.18 && distance(tip, w) > distance(mp, w) * 1.08
        }

        let others = [index, middle, ring, little].filter { $0 }.count
        let shape: HandReading.Shape?
        if others == 0 {
            shape = .rock
        } else if index && middle && !ring && !little {
            shape = .scissors
        } else if others >= 3 {
            shape = .paper
        } else {
            shape = nil
        }
        return HandReading(fingers: others + (thumb ? 1 : 0), shape: shape)
    }
}

/// Garde la réponse la plus fréquente sur un court moment, pour ne pas se fier à une seule image.
struct ReadingWindow<Value: Hashable> {
    private var samples: [(Date, Value)] = []
    var span: TimeInterval = 0.8

    mutating func add(_ value: Value, at date: Date = Date()) {
        samples.append((date, value))
        samples.removeAll { date.timeIntervalSince($0.0) > span }
    }

    mutating func reset() { samples.removeAll() }

    /// La valeur vue le plus souvent, et la part des images où on la voit (0 à 1).
    func mostFrequent() -> (value: Value, share: Double)? {
        guard !samples.isEmpty else { return nil }
        var counts: [Value: Int] = [:]
        for (_, v) in samples { counts[v, default: 0] += 1 }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, Double(best.value) / Double(samples.count))
    }

    var count: Int { samples.count }
}
