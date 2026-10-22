import SwiftUI
import AVFoundation
import UIKit

// MARK: - Couleurs

enum Theme {
    static let ink = Color(hex: 0x0E1020)
    static let card = Color(hex: 0x1A1D33)
    static let cardHigh = Color(hex: 0x262A47)
    static let laser = Color(hex: 0x3DE0FF)
    static let gold = Color(hex: 0xFFC53D)
    static let sun = Color(hex: 0xFF7A2F)
    static let coral = Color(hex: 0xFF5C4D)
    static let paint = Color(hex: 0xFF4F9A)
    static let go = Color(hex: 0x23C46B)
    static let stop = Color(hex: 0xE8343F)
    static let muted = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.12)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    static func plie(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Boutons

struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.coral
    var textColor: Color = .white
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plie(20))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 10, y: configuration.isPressed ? 1 : 6)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plie(17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.faint, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Bouton rond avec une icône (fermer, retour…).
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Éléments

struct Pill: View {
    let text: String
    var color: Color = Theme.card
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.plie(13, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(color))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// En-tête commun aux écrans de jeu : retour, titre, élément à droite.
struct GameHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "chevron.left", label: "Retour", action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.plie(20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(.white)
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(index < count ? Theme.gold : Theme.faint)
            }
        }
        .accessibilityLabel("\(count) étoile\(count > 1 ? "s" : "") sur 3")
    }
}

func formatSeconds(_ seconds: Double) -> String {
    if seconds < 60 {
        return String(format: "%.1f s", seconds)
    }
    let total = Int(seconds.rounded())
    return String(format: "%d min %02d", total / 60, total % 60)
}

// MARK: - Aperçu caméra

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Change de valeur quand la caméra est prête, pour caler la rotation de l'image.
    var readyToken: Int = 0
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.videoGravity = gravity
        uiView.attachRotationIfNeeded()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?
        private weak var observedDevice: AVCaptureDevice?

        override func layoutSubviews() {
            super.layoutSubviews()
            attachRotationIfNeeded()
        }

        func attachRotationIfNeeded() {
            guard let device = previewLayer.session?.inputs
                    .compactMap({ $0 as? AVCaptureDeviceInput })
                    .first(where: { $0.device.hasMediaType(.video) })?
                    .device,
                  device !== observedDevice else { return }
            observedDevice = device
            let newCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            coordinator = newCoordinator
            observation = newCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    guard let connection = self?.previewLayer.connection,
                          connection.isVideoRotationAngleSupported(angle) else { return }
                    connection.videoRotationAngle = angle
                }
            }
        }
    }
}
