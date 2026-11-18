//
// ConsoleSkinPreview.swift
// RetroCartridge
//
// A miniature of the unfolded clamshell console in a given skin: the shell,
// the screen bezel on the upper half, and the D-Pad, A/B and Select/Start
// buttons on the lower half. Used by the skin picker and the store.
//

import SwiftUI

struct ConsoleSkinPreview: View {
    let theme: SkinTheme

    /// Width / height of the miniature console.
    static let aspectRatio: CGFloat = 0.74

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let corner = w * 0.1
            let unit = w / 5.2

            ZStack {
                // Shell, drawn like the real console at miniature scale
                ShellSurface(theme: theme, cornerRadius: corner, detailScale: w / 669)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    screen(w: w, h: h)
                        .padding(w * 0.08)
                        .frame(height: h / 2)

                    controls(unit: unit)
                        .frame(height: h / 2)
                }

                // Hinge groove
                Rectangle()
                    .fill(LinearGradient(colors: [.black.opacity(0.3), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(1, h * 0.008))
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
        .accessibilityHidden(true)
    }

    private func screen(w: CGFloat, h: CGFloat) -> some View {
        let r = w * 0.05

        return ZStack {
            RoundedRectangle(cornerRadius: r * 1.4, style: .continuous)
                .fill(LinearGradient(colors: [theme.bezelTopColor, theme.bezelBottomColor], startPoint: .top, endPoint: .bottom))

            VStack(spacing: w * 0.035) {
                // Accent light strip, like the bezel header
                Capsule()
                    .fill(theme.accentColor.opacity(0.8))
                    .frame(width: w * 0.16, height: max(1.5, w * 0.018))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    RoundedRectangle(cornerRadius: r * 0.5, style: .continuous)
                        .fill(Color(hex: "#0B130E"))
                    phosphorPixels(w: w)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: r * 0.5, style: .continuous)
                        .stroke(theme.screenBorderColor.opacity(0.9), lineWidth: max(1, w * 0.012))
                )
                .aspectRatio(10 / 9, contentMode: .fit)
            }
            .padding(w * 0.05)
        }
    }

    /// A few rows of glowing "bricks" to suggest a lit CRT.
    private func phosphorPixels(w: CGFloat) -> some View {
        let phosphor = Color(hex: "#9CFFB8")
        let size = w * 0.055

        return VStack(spacing: size * 0.45) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: size * 0.45) {
                    ForEach(0..<5, id: \.self) { col in
                        Rectangle()
                            .fill(phosphor.opacity((row + col).isMultiple(of: 3) ? 0.35 : 0.85))
                            .frame(width: size * 1.4, height: size * 0.7)
                    }
                }
            }
        }
        .shadow(color: phosphor.opacity(0.6), radius: size * 0.6)
    }

    private func controls(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.35) {
            HStack(alignment: .center) {
                dPad(size: unit * 1.55)
                Spacer(minLength: 0)
                actionButtons(unit: unit)
            }
            .padding(.horizontal, unit * 0.4)

            HStack(spacing: unit * 0.35) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule()
                        .fill(theme.buttonColor)
                        .frame(width: unit * 0.55, height: unit * 0.16)
                        .rotationEffect(.degrees(-20))
                }
            }
        }
        .padding(.top, unit * 0.2)
    }

    private func dPad(size: CGFloat) -> some View {
        let arm = size * 0.34

        return ZStack {
            RoundedRectangle(cornerRadius: arm * 0.2, style: .continuous)
                .frame(width: size, height: arm)
            RoundedRectangle(cornerRadius: arm * 0.2, style: .continuous)
                .frame(width: arm, height: size)
        }
        .foregroundStyle(theme.buttonColor)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
    }

    private func actionButtons(unit: CGFloat) -> some View {
        HStack(alignment: .top, spacing: unit * 0.18) {
            Circle()
                .fill(theme.actionButtonColor)
                .frame(width: unit * 0.7, height: unit * 0.7)
                .offset(y: unit * 0.26)
            Circle()
                .fill(theme.actionButtonColor)
                .frame(width: unit * 0.7, height: unit * 0.7)
                .offset(y: -unit * 0.13)
        }
        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        .rotationEffect(.degrees(-8))
    }
}
