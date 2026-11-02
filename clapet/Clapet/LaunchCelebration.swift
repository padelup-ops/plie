import SwiftUI

/// Seulement dans la version TestFlight : un grand écran de fête, avec des confettis, pour annoncer
/// que Foldly est sur l'App Store. Il s'affiche une fois au lancement ; « Plus tard » le ferme.
struct LaunchCelebration: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var appear = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.35), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Confetti()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer()
                Text(verbatim: "🎉")
                    .font(.system(size: 88))
                    .scaleEffect(appear ? 1 : 0.3)
                    .rotationEffect(.degrees(appear ? 0 : -30))
                VStack(spacing: 10) {
                    Text("Foldly is on the App Store!")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text("Thank you for testing it. Install the App Store version to keep your data: it simply replaces this beta.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 20)

                Label("The beta ends on November 9.", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .opacity(appear ? 1 : 0)
                Spacer()

                VStack(spacing: 12) {
                    Button {
                        openURL(BetaBanner.appStoreURL)
                    } label: {
                        Label("Get it on the App Store", systemImage: "arrow.down.app.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)

                    Button("Later") { dismiss() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(appear ? 1 : 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 520)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) { appear = true }
        }
    }
}

/// Des confettis qui tombent en boucle (dessinés avec Canvas, sans image).
private struct Confetti: View {
    private struct Piece {
        let x: Double, speed: Double, size: Double, spin: Double, sway: Double, phase: Double, color: Color, round: Bool
    }
    private static let colors: [Color] = [.pink, .orange, .yellow, .green, .mint, .blue, .purple, .red]
    private let pieces: [Piece] = (0..<90).map { _ in
        Piece(x: .random(in: 0...1), speed: .random(in: 0.08...0.2), size: .random(in: 6...12),
              spin: .random(in: 1...4), sway: .random(in: 8...30), phase: .random(in: 0...1),
              color: colors.randomElement()!, round: Bool.random())
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let progress = (p.phase + t * p.speed).truncatingRemainder(dividingBy: 1)
                    let y = -20 + progress * (size.height + 40)
                    let x = p.x * size.width + sin((t + p.phase * 10) * 1.6) * p.sway
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * p.spin + p.phase * 6))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.round ? p.size : p.size / 2)
                    let shape = p.round ? Path(ellipseIn: rect) : Path(rect)
                    c.fill(shape, with: .color(p.color))
                }
            }
        }
    }
}
