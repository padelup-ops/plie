// ReactionCamera.swift — Allô Père Noël
//
// Comme dans un appel vidéo : pendant que le Père Noël parle, un petit rectangle dans un coin montre l'enfant
// (caméra avant, en direct). C'est le parent qui le décide avant l'appel, sur l'écran de préparation ; pendant l'appel,
// l'enfant ne voit aucun bouton.
//
// Rien n'est enregistré. Avec le Pass Noël, le parent peut demander quelques photos de la réaction de son enfant aux
// meilleurs moments (le bonjour, la surprise de l'étoile, l'au revoir) : elles restent en mémoire, lui sont montrées
// à la fin de l'appel, et ne vont dans Photos ou ailleurs que s'il le demande. Rien ne quitte l'iPhone.

import AVFoundation
import SwiftUI
import UIKit

final class ReactionCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Une photo de la réaction : l'image, ou « trop sombre pour en faire une photo ».
    enum Shot {
        case image(UIImage)
        case tooDark
    }

    let session = AVCaptureSession()
    private let work = DispatchQueue(label: "allonoel.camera")
    private let frames = DispatchQueue(label: "allonoel.camera.frames")
    private let lock = NSLock()
    private var last: CVPixelBuffer?
    /// La clarté moyenne de ce que voit la caméra, de 0 (noir) à 1 ; négative tant qu'elle n'a rien vu.
    private var luma = -1.0
    private var dim = false
    private var count = 0
    private var configured = false
    private var wanted = false
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()

    static var authorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var denied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return s == .denied || s == .restricted
    }

    /// Demande la caméra (la première fois, iOS pose la question au parent).
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// La pièce est sombre (une chambre le soir) : l'app éclaire alors le visage avec l'écran.
    var isDim: Bool { lock.lock(); defer { lock.unlock() }; return dim }

    /// La caméra est encore en train de régler sa lumière : ce n'est pas le moment de prendre une photo.
    var isSettling: Bool {
        lock.lock(); let seen = luma >= 0; lock.unlock()
        return !seen || (input?.device.isAdjustingExposure ?? false)
    }

    func start() {
        guard Self.authorized else { return }
        work.async { [self] in
            wanted = true
            lock.lock(); luma = -1; dim = false; count = 0; lock.unlock()
            if !configured { configure() }
            selectCamera(force: true)
            if input != nil, !session.isRunning { session.startRunning() }
            watch()
        }
    }

    func stop() {
        work.async { [self] in
            wanted = false
            if session.isRunning { session.stopRunning() }
            lock.lock(); last = nil; lock.unlock()
        }
    }

    /// La caméra avant à utiliser maintenant. Un iPhone pliant en a plusieurs, et celle qui est cachée par le pli ne
    /// montre que du noir : on écarte celles que le système a mises en pause, et on préfère celle qu'il recommande.
    private static func frontCamera() -> AVCaptureDevice? {
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera, .builtInUltraWideCamera],
            mediaType: .video, position: .front).devices
        let usable = found.filter { $0.isConnected && !$0.isSuspended }
        if let preferred = AVCaptureDevice.systemPreferredCamera, preferred.position == .front,
           usable.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
        return usable.first ?? found.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }

    /// La sortie des images, une fois pour toutes.
    private func configure() {
        session.beginConfiguration()
        // Pas de micro, et l'app garde la main sur le son de l'appel.
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        output.alwaysDiscardsLateVideoFrames = true
        // Clarté d'un côté, couleur de l'autre : la clarté se mesure sans calcul.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: frames)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    /// Branche la bonne caméra avant (ou en change, si l'iPhone a été plié ou déplié depuis).
    private func selectCamera(force: Bool = false) {
        guard let device = Self.frontCamera() else { return }
        if let input, input.device.uniqueID == device.uniqueID {
            if force { tune(device, bias: 0) }
            return
        }
        guard let fresh = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if let input { session.removeInput(input) }
        if session.canAddInput(fresh) {
            session.addInput(fresh)
            input = fresh
        } else {
            input = nil
        }
        if let c = output.connection(with: .video) {
            // Debout, et comme dans un miroir : ce que l'enfant voit dans le rectangle.
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }
        session.commitConfiguration()
        tune(device, bias: 0)
    }

    /// Les réglages qui comptent dans une chambre peu éclairée : la caméra a le droit de ralentir (jusqu'à 8 images
    /// par seconde) pour poser plus longtemps, elle règle sa lumière en continu, et elle s'aide de ce qu'elle a.
    private func tune(_ device: AVCaptureDevice, bias: Float) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isLowLightBoostSupported { device.automaticallyEnablesLowLightBoostWhenAvailable = true }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        // La plage de cadences du format en cours, bornée à 8…30 : on ne sort jamais de ce que le format accepte.
        if let range = device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
            let fastest = min(range.maxFrameRate, 30)
            let slowest = max(range.minFrameRate, 8)
            if slowest < fastest {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fastest.rounded(.down)))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(slowest.rounded(.up)))
            }
        }
        let wantedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
        device.setExposureTargetBias(wantedBias, completionHandler: nil)
        device.unlockForConfiguration()
    }

    /// Chaque seconde pendant l'appel : la caméra choisie est-elle toujours la bonne, tourne-t-elle, et la pièce
    /// est-elle sombre ? Si oui, on le retient pour tout l'appel (l'écran éclaire alors le visage) et la caméra vise
    /// plus clair.
    private func watch() {
        work.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.wanted else { return }
            self.selectCamera()
            if self.input != nil, !self.session.isRunning { self.session.startRunning() }
            self.lock.lock()
            let seen = self.luma
            let already = self.dim
            let enough = self.count >= 20
            self.lock.unlock()
            if !already, enough, seen >= 0, seen < 0.2, let device = self.input?.device, !device.isAdjustingExposure {
                self.lock.lock(); self.dim = true; self.lock.unlock()
                self.tune(device, bias: 1.3)
            }
            self.watch()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Seule la dernière image est gardée, le temps de la suivante : rien n'est écrit nulle part.
        lock.lock(); last = buffer; count += 1; let n = count; lock.unlock()
        if n % 4 == 0 { measure(buffer) }
    }

    /// La clarté moyenne de l'image, sur un point tous les seize.
    private func measure(_ buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var n = 0
        var y = 8
        while y < height {
            var x = 8
            while x < width {
                sum += Int(pixels[y * row + x])
                n += 1
                x += 16
            }
            y += 16
        }
        guard n > 0 else { return }
        let value = Double(sum) / Double(n) / 255
        lock.lock(); luma = luma < 0 ? value : luma * 0.7 + value * 0.3; lock.unlock()
    }

    /// L'image que la caméra voit en ce moment. Une image sombre est éclaircie (et son grain adouci) ; une image
    /// noire n'est pas gardée : mieux vaut pas de photo qu'un souvenir raté.
    func snapshot() -> Shot? {
        lock.lock(); let buffer = last; let seen = luma; lock.unlock()
        guard let buffer else { return nil }
        if seen >= 0, seen < 0.045 { return .tooDark }
        var image = CIImage(cvPixelBuffer: buffer)
        if seen >= 0, seen < 0.3 {
            // De combien de crans monter pour retrouver un visage lisible (la clarté mesurée est celle de l'écran,
            // pas celle de la lumière : on repasse par la lumière pour compter les crans).
            let light = pow(seen, 2.2)
            let stops = min(3.2, max(0, log2(0.1 / max(light, 0.0008))))
            image = image
                .applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.03, "inputSharpness": 0.25])
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: stops])
                .cropped(to: image.extent)
        }
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return .image(UIImage(cgImage: cg))
    }
}

/// L'image de la caméra, en direct.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.preview?.session = session
        view.preview?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// Le petit rectangle arrondi qui montre l'enfant.
struct ReactionPip: View {
    let session: AVCaptureSession
    var size = CGSize(width: 84, height: 112)
    var body: some View {
        CameraPreview(session: session)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Le rectangle dans un coin de l'appel, comme sur FaceTime : en bas à droite au départ, on le fait glisser au doigt
/// et il s'aimante au coin le plus proche. Le coin choisi est retenu pour les appels suivants. Les coins restent sous
/// la barre du haut et la bulle « le Père Noël t'écoute », et au-dessus des sous-titres et du bouton pour raccrocher.
struct FloatingPip: View {
    let session: AVCaptureSession
    /// La place prise en haut (barre, bulle d'écoute) et en bas (sous-titres, bouton pour raccrocher).
    var top: CGFloat
    var bottom: CGFloat
    /// 0 : en haut à gauche, 1 : en haut à droite, 2 : en bas à gauche, 3 : en bas à droite.
    @AppStorage("allonoel.pip.corner") private var corner = 3
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: 84, height: 112)
            let margin: CGFloat = 14
            let xs = [margin + size.width / 2, geo.size.width - margin - size.width / 2]
            let ys = [top + size.height / 2, max(top + size.height * 1.5 + 12, geo.size.height - bottom - size.height / 2)]
            let c = min(3, max(0, corner))
            let home = CGPoint(x: xs[c % 2], y: ys[c / 2])
            ReactionPip(session: session, size: size)
                .position(x: home.x + offset.width, y: home.y + offset.height)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { offset = $0.translation }
                        .onEnded { drag in
                            let end = CGPoint(x: home.x + drag.predictedEndTranslation.width,
                                              y: home.y + drag.predictedEndTranslation.height)
                            let next = (end.x > geo.size.width / 2 ? 1 : 0) + (end.y > (ys[0] + ys[1]) / 2 ? 2 : 0)
                            // Il part de là où le doigt l'a lâché et rejoint son coin.
                            offset = CGSize(width: home.x + drag.translation.width - xs[next % 2],
                                            height: home.y + drag.translation.height - ys[next / 2])
                            corner = next
                            withAnimation(.spring(duration: 0.4, bounce: 0.25)) { offset = .zero }
                        }
                )
                .animation(.spring(duration: 0.35), value: bottom)
        }
    }
}

/// Sur l'écran de préparation (côté parent) : montrer l'enfant pendant l'appel, et garder sa réaction en photos.
/// Toujours visible, juste au-dessus du bouton qui lance l'appel.
struct ReactionOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @State private var refused = false

    var body: some View {
        let show = Binding<Bool>(
            get: { model.showChild },
            set: { on in
                guard on else { model.showChild = false; return }
                Task { @MainActor in
                    let ok = await ReactionCamera.request()
                    model.showChild = ok
                    refused = !ok
                }
            })
        let keep = Binding<Bool>(
            get: { model.keepReactions && store.owned },
            set: { on in
                if store.owned { model.keepReactions = on } else { model.sheet = .paywall }
            })
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Noel.goldLight)
                    .frame(width: 22)
                Text("Show your child in a corner, like a video call")
                    .font(.ui(14, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Toggle(isOn: show) { EmptyView() }.labelsHidden()
            }
            if model.showChild {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Noel.goldLight)
                        .frame(width: 22)
                    Text("Keep their reaction in photos")
                        .font(.ui(14, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !store.owned { PremiumTag() }
                    Spacer(minLength: 6)
                    Toggle(isOn: keep) { EmptyView() }.labelsHidden()
                }
                Text(model.keepReactions && store.owned
                     ? "A few photos at the best moments, shown to you after the call. They stay on this iPhone unless you save or share them."
                     : "The front camera shows on screen only. Nothing is recorded.")
                    .font(.ui(12))
                    .opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if refused {
                Text("The camera is turned off for this app. You can allow it in the iPhone's Settings.")
                    .font(.ui(12))
                    .foregroundStyle(Noel.goldLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Noel.gold)
        .foregroundStyle(Noel.cream)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Noel.night.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Noel.cream.opacity(0.15), lineWidth: 1))
        .onAppear {
            // L'autorisation a pu être retirée dans les Réglages depuis la dernière fois.
            if model.showChild, !ReactionCamera.authorized { model.showChild = false }
        }
    }
}

/// À la fin de l'appel : les photos de la réaction, que le parent enregistre ou partage s'il le veut.
struct ReactionsStrip: View {
    let images: [UIImage]
    @State private var saved = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Their reaction")
                .font(.story(20))
                .foregroundStyle(Noel.goldLight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Noel.goldLight.opacity(0.6), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 28)
            }
            Text("These photos are only here for now. Save or share the ones you want to keep.")
                .font(.ui(13))
                .foregroundStyle(Noel.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 34)
            HStack(spacing: 10) {
                Button {
                    for image in images { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
                    withAnimation { saved = true }
                } label: {
                    Label(saved ? "Saved to Photos" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(saved)
                ShareLink(items: images.map { Image(uiImage: $0) }, preview: { SharePreview(Text("Santa called!"), image: $0) }) {
                    Label("Share the photos", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 28)
        }
    }
}
