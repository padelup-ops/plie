import SwiftUI

/// Le schéma « où taper » : un iPhone vu de face, le clavier à une main en bas, et les deux bords à taper
/// (le bord gauche met le clavier à gauche, le bord droit à droite), plus la place vide à côté du clavier.
struct KnockDiagram: View {
    @State private var right = false
    @State private var pulse = false
    private let timer = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = min(geo.size.width * 0.42, 150), h = w * 2.05
                let x0 = (geo.size.width - w) / 2, y0 = (geo.size.height - h) / 2
                ZStack(alignment: .topLeading) {
                    // Le téléphone
                    RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(RoundedRectangle(cornerRadius: w * 0.16, style: .continuous).stroke(Color.primary.opacity(0.75), lineWidth: 3))
                        .frame(width: w, height: h)
                        .offset(x: x0, y: y0)
                    // Le clavier à une main, du côté choisi
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.85))
                        .overlay(keys.padding(6))
                        .frame(width: w * 0.62, height: h * 0.3)
                        .offset(x: x0 + (right ? w * 0.34 : w * 0.04), y: y0 + h * 0.64)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: right)
                    // La place vide (à toucher aussi)
                    Image(systemName: right ? "chevron.left.2" : "chevron.right.2")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: w * 0.3, height: h * 0.3)
                        .offset(x: x0 + (right ? w * 0.04 : w * 0.66), y: y0 + h * 0.64)
                    // Les deux bords à taper
                    edge(left: true).offset(x: x0 - 52, y: y0 + h * 0.42)
                    edge(left: false).offset(x: x0 + w + 8, y: y0 + h * 0.42)
                }
            }
            .frame(height: 300)
            Text("Knock the left edge: the keyboard goes left. Knock the right edge: it goes right. Or tap the empty space next to it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Knock the left edge: the keyboard goes left. Knock the right edge: it goes right. Or tap the empty space next to it."))
        .onReceive(timer) { _ in
            pulse = true
            right.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pulse = false }
        }
    }

    private var keys: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) { ForEach(0..<6, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.85)) } }
            }
        }
    }

    /// Un bord à taper : le doigt, et l'onde quand c'est son tour.
    private func edge(left: Bool) -> some View {
        let active = right != left
        return ZStack {
            Circle()
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(active && pulse ? 1.5 : 0.8)
                .opacity(active && pulse ? 0 : 0.8)
                .animation(.easeOut(duration: 0.5), value: pulse)
            Image(systemName: left ? "hand.point.right.fill" : "hand.point.left.fill")
                .font(.title2)
                .foregroundStyle(active ? Color.orange : Color.secondary)
        }
        .frame(width: 44, height: 44)
    }
}
