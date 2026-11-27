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
    let session = AVCaptureSession()
    private let work = DispatchQueue(label: "allonoel.camera")
    private let frames = DispatchQueue(label: "allonoel.camera.frames")
    private let lock = NSLock()
    private var last: CVPixelBuffer?
    private var configured = false
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

    func start() {
        guard Self.authorized else { return }
        work.async { [self] in
            if !configured { configure() }
            if configured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        work.async { [self] in
            if session.isRunning { session.stopRunning() }
            lock.lock(); last = nil; lock.unlock()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        // Pas de micro, et l'app garde la main sur le son de l'appel.
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frames)
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let c = output.connection(with: .video) {
                // Debout, et comme dans un miroir : ce que l'enfant voit dans le rectangle.
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                if c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = true
                }
            }
        }
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Seule la dernière image est gardée, le temps de la suivante : rien n'est écrit nulle part.
        lock.lock(); last = buffer; lock.unlock()
    }

    /// L'image que la caméra voit en ce moment, ou rien si elle ne tourne pas.
    func snapshot() -> UIImage? {
        lock.lock(); let buffer = last; lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
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

/// Le petit rectangle arrondi, dans un coin de l'appel.
struct ReactionPip: View {
    let session: AVCaptureSession
    var body: some View {
        CameraPreview(session: session)
            .frame(width: 104, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}

/// Sur l'écran de préparation (côté parent) : montrer l'enfant pendant l'appel, et garder sa réaction en photos.
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
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: show) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show your child in a corner, like a video call")
                        .font(.ui(16, .semibold))
                    Text("The front camera shows on screen only. Nothing is recorded.")
                        .font(.ui(13))
                        .opacity(0.7)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if model.showChild {
                Toggle(isOn: keep) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Keep their reaction in photos")
                                .font(.ui(16, .semibold))
                            if !store.owned { PremiumTag() }
                        }
                        Text("A few photos at the best moments, shown to you after the call. They stay on this iPhone unless you save or share them.")
                            .font(.ui(13))
                            .opacity(0.7)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if refused {
                Text("The camera is turned off for this app. You can allow it in the iPhone's Settings.")
                    .font(.ui(13))
                    .foregroundStyle(Noel.goldLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Noel.gold)
        .foregroundStyle(Noel.cream)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Noel.night.opacity(0.55)))
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
