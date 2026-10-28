import SwiftUI
import AVFoundation
import UIKit

// MARK: - Couleurs

enum Theme {
    static let ink = Color(hex: 0x0E1020)
    static let laser = Color(hex: 0x3DE0FF)
    static let gold = Color(hex: 0xFFC53D)
    static let sun = Color(hex: 0xFF7A2F)
    static let coral = Color(hex: 0xFF5C4D)
    static let paint = Color(hex: 0xFF4F9A)
    static let go = Color(hex: 0x23C46B)
    static let stop = Color(hex: 0xE8343F)

    // Couleurs dynamiques : encre sur le papier (mode clair), blanc dans la nuit des jeux (mode sombre).
    static let text = Color(paper: 0x2A2438, night: 0xFFFFFF)
    static let muted = Color(paper: 0x2A2438, 0.64, night: 0xFFFFFF, 0.62)
    static let faint = Color(paper: 0x2A2438, 0.10, night: 0xFFFFFF, 0.12)
    static let card = Color(paper: 0xFFFCF6, night: 0x1A1D33)
    static let cardHigh = Color(paper: 0xEFE7D7, night: 0x262A47)
    /// Fond des boutons secondaires.
    static let ghost = Color(paper: 0x2A2438, 0.06, night: 0x1A1D33)
    /// Étoiles et clés : un or plus foncé sur le papier, pour qu'il se voie.
    static let star = Color(paper: 0xE4A11B, night: 0xFFC53D)
    static let emptyStar = Color(paper: 0x2A2438, 0.22, night: 0xFFFFFF, 0.12)
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

/// Le bouton principal : une feuille de couleur posée sur son épaisseur. Appuyé, elle s'enfonce.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.coral
    var textColor: Color = .white
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let depth: CGFloat = 4
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return configuration.label
            .font(.plie(19))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    shape.fill(color)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04), Paper.shadow.opacity(0.07)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.stroke(Paper.shadow.opacity(0.08), lineWidth: 0.75)
                }
            )
            .offset(y: pressed ? depth - 1 : 0)
            .background(
                // L'épaisseur du papier, sous le bouton.
                ZStack {
                    shape.fill(color)
                    shape.fill(Paper.shadow.opacity(0.32))
                }
                .offset(y: depth)
            )
            .padding(.bottom, depth)
            .compositingGroup()
            .shadow(color: Paper.shadow.opacity(pressed ? 0.10 : 0.18), radius: pressed ? 2 : 8, y: pressed ? 2 : 6)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
    }
}

/// Le bouton secondaire : une feuille fine, sans couleur.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.plie(17, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.ghost)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.faint, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Bouton rond avec une icône (fermer, retour…) : un jeton de papier, sur l'accueil comme dans les jeux.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Paper.ink)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Paper.sheet)
                        .shadow(color: Paper.shadow.opacity(0.22), radius: 6, y: 3)
                )
                .overlay(Circle().stroke(Paper.shadow.opacity(0.08), lineWidth: 0.75))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Éléments

struct Pill: View {
    let text: String
    var color: Color = Theme.card
    var textColor: Color = Theme.text

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
            IconButton(symbol: "chevron.left", label: L("Retour"), action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.paperTitle(22))
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
        .foregroundStyle(Theme.text)
    }
}

/// Conseil affiché au-dessus du plateau, qu'on peut masquer : un pense-bête jaune au coin corné.
struct TipBanner: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Paper.accent)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Paper.inkSoft)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(L("Masquer le conseil"))
        }
        .foregroundStyle(Paper.ink)
        .padding(12)
        .padding(.trailing, 6)
        .background(PaperSheet(color: Paper.note, cornerRadius: 14, ear: 14, lift: 0.7))
        .transition(.opacity)
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
                    .foregroundStyle(index < count ? Theme.star : Theme.emptyStar)
            }
        }
        .accessibilityLabel(L("\(count) étoile\(count > 1 ? "s" : "") sur 3"))
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
