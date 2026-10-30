import SwiftUI
import AVFoundation

// MARK: - Les jeux « sans toucher » : morceaux communs
//
// CHIFOUMI, CALCUL AUX DOIGTS et PAS DE SOURIRE ! se jouent à deux écrans : celui qui tient le Duo
// a l'écran intérieur, la personne en face regarde l'écran extérieur et joue avec ses mains ou son visage,
// devant la caméra du dos (l'écran extérieur ne se touche pas quand le Duo est ouvert).

extension Theme {
    static let chifoumi = Color(hex: 0x8C6BFF)
    static let doigts = Color(hex: 0x2EC4B6)
    static let sourire = Color(hex: 0xFFB020)
}

/// Le fond en papier des trois jeux, en mode clair.
struct GestesScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PaperBackdrop().ignoresSafeArea()
            content()
        }
        .foregroundStyle(Paper.ink)
        .environment(\.colorScheme, .light)
    }
}

/// Un grand bouton de mode de jeu, sur une feuille pliée de la couleur du jeu.
struct GestesModeButton: View {
    let symbol: String
    let title: String
    let detail: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.plie(19))
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .opacity(0.85)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Paper.ink)
            .padding(16)
            .background(FoldedPaper(color: color.paperTone(), cornerRadius: 22))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Ce que voit la caméra, dans un cadre de papier, avec une étiquette en bas.
struct GestesCameraCard: View {
    let session: AVCaptureSession
    var ready: Bool
    var label: String?
    var height: CGFloat = 170

    var body: some View {
        ZStack(alignment: .bottom) {
            if ready {
                CameraPreview(session: session, readyToken: 1)
            } else {
                Paper.creamDeep
                VStack(spacing: 6) {
                    Image(systemName: "video.slash.fill").font(.title2)
                    Text(L("Caméra éteinte"))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(Paper.inkSoft)
                .frame(maxHeight: .infinity)
            }
            if let label {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Paper.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Paper.sheet.opacity(0.92)))
                    .padding(8)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Paper.shadow.opacity(0.12), lineWidth: 1))
        .shadow(color: Paper.shadow.opacity(0.12), radius: 8, y: 4)
    }
}

/// Le score d'un joueur : son nom et ses points, sur une pastille.
struct GestesScore: View {
    let name: String
    let points: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(points)")
                .font(.plie(22))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(color.paperTone().opacity(0.9)))
        .foregroundStyle(Paper.ink)
    }
}

/// L'écran extérieur : une feuille crème plein écran, lisible de loin.
struct GestesOuterScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(hex: 0xF6F0E4).ignoresSafeArea()
            content()
                .padding(24)
        }
        .foregroundStyle(Color(hex: 0x2A2438))
        .environment(\.colorScheme, .light)
    }
}

/// Planifie une suite d'étapes, qu'on peut annuler en changeant de « génération ».
final class GestesTimeline {
    private(set) var generation = 0

    func cancel() { generation += 1 }

    /// Lance `action` après `delay` secondes, sauf si la timeline a été annulée entre-temps.
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == gen else { return }
            action()
        }
    }
}
