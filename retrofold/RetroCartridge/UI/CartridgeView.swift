//
// CartridgeView.swift
// RetroCartridge
//
// A retro game cartridge drawn in SwiftUI: a molded shell in the game's own
// plastic (grey, black, glow-in-the-dark or clear over its circuit board),
// grip ridges, a notched corner and a colored label with the game's genre
// and pixel-art artwork. Locked cartridges look dusty and carry a padlock.
//

import SwiftUI

struct CartridgeView: View {
    let game: GameType

    /// Shown on the label when non-nil and greater than zero.
    var highScore: Int? = nil

    /// Selected cartridges cast a larger, softer shadow.
    var isSelected: Bool = false

    /// Locked cartridges look dusty and faded, with a padlock.
    var isLocked: Bool = false

    /// Achievements earned out of the total, shown as stars once any are earned.
    var achievements: (earned: Int, total: Int)? = nil

    /// Width / height of the cartridge shell.
    static let aspectRatio: CGFloat = 0.8

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let labelColor = Color(hex: game.cartridgeColorHex)
            let shell = game.info.shell
            let outline = CartridgeShape(notch: w * 0.13)

            ZStack(alignment: .top) {
                // Shadow caster: an opaque base under the (possibly clear) shell
                outline
                    .fill(Color.black)
                    .shadow(color: glowColor(shell: shell, label: labelColor), radius: 30)
                    .shadow(color: .black.opacity(0.55), radius: isSelected ? 16 : 8, y: isSelected ? 12 : 6)

                // With Reduce Transparency, clear plastic is drawn solid
                if shell.isTranslucent && !reduceTransparency {
                    CartridgeBoard(width: w)
                        .clipShape(outline)
                }

                // Shell
                outline
                    .fill(
                        LinearGradient(
                            colors: [shell.topColor, shell.bottomColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        outline.stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )

                VStack(spacing: h * 0.04) {
                    // Grip ridges
                    VStack(spacing: h * 0.018) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule()
                                .fill(Color.black.opacity(0.3))
                                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5).offset(y: 0.75))
                                .frame(height: max(1.5, h * 0.012))
                        }
                    }
                    .padding(.horizontal, w * 0.24)
                    .padding(.top, h * 0.055)

                    label(w: w, h: h, color: labelColor)
                        .frame(height: h * 0.5)
                        .padding(.horizontal, w * 0.1)

                    // Embossed footer
                    VStack(spacing: h * 0.012) {
                        Text("RETROFOLD")
                            .font(.pixel(w * 0.05))
                            .tracking(w * 0.006)
                            .foregroundStyle(Color.black.opacity(0.45))
                            .shadow(color: .white.opacity(0.12), radius: 0, y: 0.5)

                        if let highScore, highScore > 0 {
                            Text("HI \(highScore)")
                                .font(.pixel(w * 0.055))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }

                        if let achievements, achievements.earned > 0 {
                            Text(String(repeating: "★", count: achievements.earned)
                                 + String(repeating: "☆", count: max(0, achievements.total - achievements.earned)))
                                .font(.system(size: w * 0.055, weight: .bold))
                                .foregroundStyle(Color(hex: "#FFD166").opacity(0.85))
                                .accessibilityLabel("\(achievements.earned) of \(achievements.total) achievements")
                        }
                    }

                    Spacer(minLength: 0)
                }

                if isLocked {
                    // Dust settled on a cartridge nobody has played yet
                    outline
                        .fill(Color(white: 0.72).opacity(0.22))
                        .colorEffect(ShaderLibrary.shellGrain(.float(0.9)))
                }
            }
            .saturation(isLocked ? 0.25 : 1)
            .overlay {
                if isLocked {
                    OverlayLockBadge()
                        .scaleEffect(min(1, w / 170))
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }

    /// Glow-in-the-dark shells always glow; others glow in their label
    /// color when selected.
    private func glowColor(shell: CartridgeShell, label: Color) -> Color {
        if let glow = shell.glowColor {
            return glow.opacity(isSelected ? 0.6 : 0.35)
        }
        return label.opacity(isSelected ? 0.35 : 0)
    }

    // MARK: - Label

    private func label(w: CGFloat, h: CGFloat, color: Color) -> some View {
        let corner = w * 0.05

        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.85), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Retro racing stripes across the label
            VStack(spacing: h * 0.012) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.18 - Double(i) * 0.05))
                        .frame(height: h * 0.012)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, h * 0.03)

            VStack(spacing: h * 0.015) {
                Text(game.genre)
                    .font(.pixel(w * 0.045))
                    .tracking(w * 0.01)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Artwork in a little screen window
                CartridgeArt(game: game)
                    .frame(width: w * 0.32, height: w * 0.32)
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                            .stroke(Color.black.opacity(0.45), lineWidth: max(1, w * 0.012))
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

                Text(game.rawValue.uppercased())
                    .font(.pixel(w * 0.075))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, w * 0.05)
            .padding(.top, h * 0.025)
            .padding(.bottom, h * 0.06)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.black.opacity(0.35), lineWidth: 1)
        )
    }
}

/// The circuit board seen inside a clear cartridge, with its row of gold
/// edge contacts along the bottom.
private struct CartridgeBoard: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            CircuitBoard(detailScale: width / 420)

            HStack(spacing: width * 0.018) {
                ForEach(0..<14, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: width * 0.005)
                        .fill(Color(hex: "#D8B45A"))
                        .frame(width: width * 0.032, height: width * 0.07)
                }
            }
            .padding(.bottom, width * 0.025)
        }
    }
}

/// Cartridge silhouette: rounded corners with a diagonal notch at the top-right.
struct CartridgeShape: Shape {
    var notch: CGFloat

    func path(in r: CGRect) -> Path {
        let c = min(r.width, r.height) * 0.06
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - notch, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + notch))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Press feedback for cartridges: sinks slightly as if pushed into the slot.
struct CartridgePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Dark studio backdrop with a soft glow tinted by the selected game.
struct ConsoleBackdrop: View {
    var glowColor: Color

    /// The equipped skin: the library and cover are the outside of the
    /// device, so they're drawn as its case.
    @Environment(\.consoleTheme) private var consoleTheme

    var body: some View {
        ZStack {
            ShellSurface(theme: consoleTheme)
            RadialGradient(
                colors: [glowColor.opacity(0.22), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: glowColor)
    }
}
