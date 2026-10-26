import SwiftUI

// MARK: - Deux joueurs face à face
//
// Duo ouvert à plat entre deux joueurs : chaque moitié de l'écran est tournée vers son joueur.
// Le siège 0 est en bas (à l'endroit), le siège 1 en haut (retourné). La charnière est au milieu.

struct FaceToFace<Half: View>: View {
    let half: (Int) -> Half

    init(@ViewBuilder half: @escaping (Int) -> Half) {
        self.half = half
    }

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height / 2
            VStack(spacing: 0) {
                // Après le demi-tour, le bas de cette moitié se retrouve en haut de l'écran (caméra, encoche).
                half(1)
                    .padding(.bottom, proxy.safeAreaInsets.top)
                    .frame(width: proxy.size.width, height: h)
                    .rotationEffect(.degrees(180))
                half(0)
                    .padding(.bottom, proxy.safeAreaInsets.bottom)
                    .frame(width: proxy.size.width, height: h)
            }
        }
        .ignoresSafeArea()
    }
}

/// Une zone qu'on glisse pour donner une direction, ou qu'on touche sans glisser.
/// Les directions sont dans le repère de la zone : posée dans une moitié retournée, elles sont donc
/// celles que voit le joueur de cette moitié.
struct SwipeZone: View {
    var threshold: CGFloat = 22
    let onSwipe: (SwipeDirection) -> Void
    var onTap: (() -> Void)?

    @State private var anchor: CGPoint?
    @State private var moved = false

    var body: some View {
        Color.white.opacity(0.001)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if anchor == nil {
                            anchor = value.startLocation
                            moved = false
                        }
                        guard let a = anchor else { return }
                        let dx = value.location.x - a.x
                        let dy = value.location.y - a.y
                        guard max(abs(dx), abs(dy)) >= threshold else { return }
                        let direction: SwipeDirection
                        if abs(dx) > abs(dy) {
                            direction = dx > 0 ? .right : .left
                        } else {
                            direction = dy > 0 ? .down : .up
                        }
                        onSwipe(direction)
                        // On repart d'ici : on peut enchaîner deux virages sans lever le doigt.
                        anchor = value.location
                        moved = true
                    }
                    .onEnded { _ in
                        if !moved { onTap?() }
                        anchor = nil
                        moved = false
                    }
            )
    }
}

enum SwipeDirection: Int, CaseIterable {
    case up, right, down, left

    var dx: Int { [0, 1, 0, -1][rawValue] }
    var dy: Int { [-1, 0, 1, 0][rawValue] }
    var opposite: SwipeDirection { SwipeDirection(rawValue: (rawValue + 2) % 4) ?? .up }
    var turnedLeft: SwipeDirection { SwipeDirection(rawValue: (rawValue + 3) % 4) ?? .up }
    var turnedRight: SwipeDirection { SwipeDirection(rawValue: (rawValue + 1) % 4) ?? .up }

    var symbol: String {
        switch self {
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        }
    }

    var angle: Double { Double(rawValue) * 90 }
}

/// Réagit dès que le doigt se pose (un bouton, lui, attend qu'on le lève) : pour les jeux de réflexes.
struct PressDown: ViewModifier {
    let action: () -> Void
    @State private var down = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            action()
                        }
                    }
                    .onEnded { _ in down = false }
            )
    }
}

extension View {
    func onPressDown(_ action: @escaping () -> Void) -> some View {
        modifier(PressDown(action: action))
    }
}

/// Zone qui compte chaque doigt posé, même à plusieurs doigts à la fois (tir à la corde, réflexes).
struct MultiTapPad: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        view.onTouch = onTouch
    }

    final class PadView: UIView {
        var onTouch: (() -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for _ in touches { onTouch?() }
        }
    }
}

/// Petit bouton rond posé sur la charnière, accessible aux deux joueurs.
struct HingeButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}
