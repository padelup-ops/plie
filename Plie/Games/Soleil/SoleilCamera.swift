import AVFoundation
import CoreImage
import UIKit
import Vision

/// Caméra de 1, 2, 3… Soleil ! : repère les mouvements pendant les phases « STOP ».
///
/// Tout se passe sur le téléphone : chaque image est réduite à une petite grille en niveaux de gris,
/// comparée à l'image prise au moment où tout le monde s'est figé. Rien n'est enregistré ni envoyé.
final class SoleilCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    struct Catch {
        let image: UIImage
    }

    let session = AVCaptureSession()

    /// Niveau de mouvement mesuré (0 à 1, où 1 = seuil de détection atteint). Appelé sur le fil principal.
    var onMotionLevel: ((Double) -> Void)?
    /// Quelqu'un a bougé. Appelé sur le fil principal.
    var onCatch: ((Catch) -> Void)?
    /// Le téléphone lui-même bouge trop. Appelé sur le fil principal.
    var onUnstable: (() -> Void)?

    private let queue = DispatchQueue(label: "app.plie.soleil.camera")
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: nil)
    private var device: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .front

    // État de détection (lu et écrit uniquement sur `queue`)
    private var armed = false
    private var reference: [UInt8]?
    private var referenceWidth = 0
    private var referenceHeight = 0
    private var threshold = 0.012
    private var consecutive = 0
    private var frameCounter = 0
    private var lastLevelSent = Date.distantPast

    static let pixelThreshold = 28

    // MARK: Autorisation et configuration

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func configure(position: AVCaptureDevice.Position) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                continuation.resume(returning: self.configureOnQueue(position: position))
            }
        }
    }

    private func configureOnQueue(position: AVCaptureDevice.Position) -> Bool {
        // On change d'objectif sans arrêter la session : sur iPhone Duo, l'écran extérieur
        // n'est disponible que tant que la caméra filme.
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        for input in session.inputs {
            session.removeInput(input)
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        device = camera
        self.position = camera.position

        if !session.outputs.contains(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }

        if let connection = output.connection(with: .video) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = camera.position == .front
            }
        }
        // Nouvelle caméra : la prochaine image servira de référence.
        reference = nil
        consecutive = 0
        return true
    }

    func start() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            self.armed = false
            self.reference = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Détection

    /// Commence à surveiller : la prochaine image devient la référence.
    func arm(threshold: Double) {
        queue.async {
            self.threshold = threshold
            self.reference = nil
            self.consecutive = 0
            self.armed = true
            self.lockExposure(true)
        }
    }

    func disarm() {
        queue.async {
            self.armed = false
            self.reference = nil
            self.consecutive = 0
            self.lockExposure(false)
        }
    }

    /// Fige l'exposition pendant le « STOP » : sinon un simple changement de lumière passerait pour un mouvement.
    private func lockExposure(_ locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if locked {
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            }
            device.unlockForConfiguration()
        } catch {
            // Sans verrouillage, la détection marche quand même, juste un peu moins bien.
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter &+= 1
        guard armed, frameCounter % 2 == 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard let small = Self.smallGray(pixelBuffer) else { return }
        let (gray, width, height) = small

        guard let reference, referenceWidth == width, referenceHeight == height else {
            self.reference = gray
            referenceWidth = width
            referenceHeight = height
            return
        }

        // Compense un léger changement global de luminosité.
        var sumDiff = 0
        for i in 0..<gray.count { sumDiff += Int(gray[i]) - Int(reference[i]) }
        let shift = sumDiff / max(1, gray.count)

        var changed = 0
        var mask = [Bool](repeating: false, count: gray.count)
        for i in 0..<gray.count {
            let d = abs(Int(gray[i]) - Int(reference[i]) - shift)
            if d > Self.pixelThreshold {
                changed += 1
                mask[i] = true
            }
        }
        let fraction = Double(changed) / Double(gray.count)

        let now = Date()
        if now.timeIntervalSince(lastLevelSent) > 0.08 {
            lastLevelSent = now
            let level = min(1.5, fraction / threshold)
            DispatchQueue.main.async { self.onMotionLevel?(level) }
        }

        // Tout bouge : c'est le téléphone qui a bougé, pas un joueur. On reprend une référence.
        if fraction > 0.45 {
            consecutive = 0
            self.reference = gray
            DispatchQueue.main.async { self.onUnstable?() }
            return
        }

        if fraction > threshold {
            consecutive += 1
        } else {
            consecutive = 0
        }

        if consecutive >= 3 {
            armed = false
            consecutive = 0
            let image = makeSnapshot(pixelBuffer: pixelBuffer, mask: mask, gridWidth: width, gridHeight: height)
            DispatchQueue.main.async {
                if let image { self.onCatch?(Catch(image: image)) }
            }
        }
    }

    // MARK: Image réduite

    /// Réduit la luminance de l'image à une grille de 80 × 60 (ou 60 × 80 en portrait).
    private static func smallGray(_ buffer: CVPixelBuffer) -> ([UInt8], Int, Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width > 4, height > 4 else { return nil }

        let gw = width >= height ? 80 : 60
        let gh = width >= height ? 60 : 80
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var result = [UInt8](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            let y0 = gy * height / gh
            let y1 = min(height - 1, y0 + max(1, height / gh / 2))
            for gx in 0..<gw {
                let x0 = gx * width / gw
                let x1 = min(width - 1, x0 + max(1, width / gw / 2))
                let a = Int(pointer[y0 * rowBytes + x0])
                let b = Int(pointer[y0 * rowBytes + x1])
                let c = Int(pointer[y1 * rowBytes + x0])
                let d = Int(pointer[y1 * rowBytes + x1])
                result[gy * gw + gx] = UInt8((a + b + c + d) / 4)
            }
        }
        return (result, gw, gh)
    }

    // MARK: Photo du « tricheur »

    private func makeSnapshot(pixelBuffer: CVPixelBuffer, mask: [Bool], gridWidth: Int, gridHeight: Int) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)

        // Zone qui a bougé, en coordonnées normalisées (origine en haut à gauche).
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth where mask[gy * gridWidth + gx] {
                let x = Double(gx) / Double(gridWidth)
                let y = Double(gy) / Double(gridHeight)
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x + 1 / Double(gridWidth)); maxY = max(maxY, y + 1 / Double(gridHeight))
            }
        }

        // Cherche la personne qui recouvre le plus la zone en mouvement.
        var personBox: CGRect?
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        if (try? handler.perform([request])) != nil, let people = request.results, !people.isEmpty {
            var best = 0
            for person in people {
                // Vision : origine en bas à gauche.
                let box = person.boundingBox
                let topLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                var overlap = 0
                for gy in 0..<gridHeight {
                    for gx in 0..<gridWidth where mask[gy * gridWidth + gx] {
                        let p = CGPoint(x: (Double(gx) + 0.5) / Double(gridWidth), y: (Double(gy) + 0.5) / Double(gridHeight))
                        if topLeft.contains(p) { overlap += 1 }
                    }
                }
                if overlap > best {
                    best = overlap
                    personBox = topLeft
                }
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            let cg = context.cgContext

            // Cases qui ont bougé, en rouge transparent.
            cg.setFillColor(UIColor.systemRed.withAlphaComponent(0.35).cgColor)
            let cellW = size.width / CGFloat(gridWidth)
            let cellH = size.height / CGFloat(gridHeight)
            for gy in 0..<gridHeight {
                for gx in 0..<gridWidth where mask[gy * gridWidth + gx] {
                    cg.fill(CGRect(x: CGFloat(gx) * cellW, y: CGFloat(gy) * cellH, width: cellW, height: cellH))
                }
            }

            let frame: CGRect
            if let personBox {
                frame = CGRect(x: personBox.minX * size.width, y: personBox.minY * size.height,
                               width: personBox.width * size.width, height: personBox.height * size.height)
            } else if maxX > minX {
                frame = CGRect(x: minX * size.width, y: minY * size.height,
                               width: (maxX - minX) * size.width, height: (maxY - minY) * size.height)
            } else {
                frame = .zero
            }
            if frame != .zero {
                cg.setStrokeColor(UIColor.systemRed.cgColor)
                cg.setLineWidth(max(4, size.width * 0.012))
                cg.stroke(frame.insetBy(dx: -4, dy: -4))
            }
        }
    }
}
