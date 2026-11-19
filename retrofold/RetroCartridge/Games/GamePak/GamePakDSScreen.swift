// GamePakDSScreen.swift
// RetroCartridge
//
// A DS game on the open iPhone Duo: the two screens spread over the whole
// inner display, like a real DS. Held sideways (fold up and down the middle),
// the top screen is on the left half and the touch screen on the right half,
// each with its buttons under it. Held upright, the screens stack. With a game
// controller, the on-screen buttons go away.

import SwiftUI
import UIKit

struct GamePakDSScreen: View {
    let game: GamePakGame
    let showsButtons: Bool
    /// Where the finger is on the touch screen (0 to 1), for the visual feedback.
    @State private var touchPoint: CGPoint?
    /// The last release, which leaves a fading ring.
    @State private var releasePoint: CGPoint?
    @State private var releaseFade = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black
                if wide {
                    HStack(spacing: 0) {
                        half(top: true, size: CGSize(width: geo.size.width / 2, height: geo.size.height))
                        half(top: false, size: CGSize(width: geo.size.width / 2, height: geo.size.height))
                    }
                } else {
                    VStack(spacing: 0) {
                        screen(top: true)
                        screen(top: false)
                    }
                    .overlay(alignment: .bottom) {
                        if showsButtons {
                            HStack(alignment: .bottom) {
                                leftButtons(unit: geo.size.width / 9)
                                Spacer()
                                rightButtons(unit: geo.size.width / 9)
                            }
                            .padding(16)
                            .opacity(0.55)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// One half of the open Duo: a DS screen near the fold's top, its buttons below.
    private func half(top: Bool, size: CGSize) -> some View {
        let unit = min(size.width / 5.5, size.height / 9)
        return VStack(spacing: unit * 0.3) {
            screen(top: top)
                .padding(.horizontal, unit * 0.35)
                .padding(.top, unit * 0.5)
            if showsButtons {
                Spacer(minLength: 0)
                if top { leftButtons(unit: unit) } else { rightButtons(unit: unit) }
                Spacer(minLength: unit * 0.4)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One DS screen, 4:3, drawn without smoothing. The bottom one is the touch screen.
    private func screen(top: Bool) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { [date = timeline.date] context, size in
                _ = date
                guard let screens = game.dsScreens() else { return }
                let image = top ? screens.top : screens.bottom
                context.withCGContext { cg in
                    cg.interpolationQuality = .none
                    cg.translateBy(x: 0, y: size.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.draw(image, in: CGRect(origin: .zero, size: size))
                }
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .overlay {
            if !top {
                GeometryReader { g in
                    let r = max(14, g.size.width * 0.045)
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                        // Visual feedback: a dot under the finger, then a ring that fades where it let go.
                        if let p = touchPoint {
                            Circle()
                                .fill(Color.white.opacity(0.35))
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                                .frame(width: r * 2, height: r * 2)
                                .position(x: p.x * g.size.width, y: p.y * g.size.height)
                                .allowsHitTesting(false)
                        }
                        if let p = releasePoint {
                            Circle()
                                .stroke(Color.white.opacity(releaseFade ? 0 : 0.8), lineWidth: 2)
                                .frame(width: r * (releaseFade ? 4 : 2), height: r * (releaseFade ? 4 : 2))
                                .position(x: p.x * g.size.width, y: p.y * g.size.height)
                                .allowsHitTesting(false)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let p = CGPoint(x: min(max(v.location.x / g.size.width, 0), 1),
                                                y: min(max(v.location.y / g.size.height, 0), 1))
                                if touchPoint == nil { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6) }
                                touchPoint = p
                                game.touchDS(p)
                            }
                            .onEnded { _ in
                                releasePoint = touchPoint
                                touchPoint = nil
                                game.touchDS(nil)
                                releaseFade = false
                                withAnimation(.easeOut(duration: 0.35)) { releaseFade = true }
                            }
                    )
                }
            }
        }
        .accessibilityLabel(top ? "DS top screen" : "DS touch screen")
    }

    // MARK: - Buttons

    /// Under the top screen: L, the D-Pad, SELECT and pause.
    private func leftButtons(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.35) {
            HStack {
                pill("L", .l, unit: unit)
                Spacer()
                Button {
                    game.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: unit * 0.3, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: unit * 0.8, height: unit * 0.8)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Pause")
            }
            dpad(unit: unit)
            pill("SELECT", .select, unit: unit)
        }
        .frame(maxWidth: unit * 4.2)
    }

    /// Under the touch screen: R, X / Y / A / B and START.
    private func rightButtons(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.35) {
            HStack {
                Spacer()
                pill("R", .r, unit: unit)
            }
            ZStack {
                round("X", .x, unit: unit).offset(y: -unit * 0.95)
                round("Y", .y, unit: unit).offset(x: -unit * 0.95)
                round("A", .a, unit: unit).offset(x: unit * 0.95)
                round("B", .b, unit: unit).offset(y: unit * 0.95)
            }
            .frame(width: unit * 3, height: unit * 3)
            pill("START", .start, unit: unit)
        }
        .frame(maxWidth: unit * 4.2)
    }

    private func dpad(unit: CGFloat) -> some View {
        ZStack {
            key("chevron.up", .up, unit: unit).offset(y: -unit * 0.95)
            key("chevron.down", .down, unit: unit).offset(y: unit * 0.95)
            key("chevron.left", .left, unit: unit).offset(x: -unit * 0.95)
            key("chevron.right", .right, unit: unit).offset(x: unit * 0.95)
        }
        .frame(width: unit * 3, height: unit * 3)
    }

    private func key(_ symbol: String, _ b: PakButton, unit: CGFloat) -> some View {
        PakHoldButton(game: game, button: b) { down in
            RoundedRectangle(cornerRadius: unit * 0.18, style: .continuous)
                .fill(Color.white.opacity(down ? 0.35 : 0.14))
                .frame(width: unit * 0.95, height: unit * 0.95)
                .overlay(Image(systemName: symbol).font(.system(size: unit * 0.38, weight: .bold)).foregroundStyle(.white.opacity(0.8)))
        }
    }

    private func round(_ title: String, _ b: PakButton, unit: CGFloat) -> some View {
        PakHoldButton(game: game, button: b) { down in
            Circle()
                .fill(Color(hex: "#F15BB5").opacity(down ? 0.9 : 0.55))
                .frame(width: unit * 0.95, height: unit * 0.95)
                .overlay(Text(title).font(.pixel(unit * 0.36, bold: true)).foregroundStyle(.white))
        }
    }

    private func pill(_ title: String, _ b: PakButton, unit: CGFloat) -> some View {
        PakHoldButton(game: game, button: b) { down in
            Capsule()
                .fill(Color.white.opacity(down ? 0.35 : 0.14))
                .frame(width: unit * 1.6, height: unit * 0.55)
                .overlay(Text(title).font(.pixel(unit * 0.22, bold: true)).foregroundStyle(.white.opacity(0.8)))
        }
    }
}

/// A button held while the finger stays on it.
private struct PakHoldButton<Label: View>: View {
    let game: GamePakGame
    let button: PakButton
    @ViewBuilder let label: (Bool) -> Label
    @State private var down = false

    var body: some View {
        label(down)
            .scaleEffect(down ? 0.88 : 1)
            .shadow(color: .white.opacity(down ? 0.45 : 0), radius: down ? 8 : 0)
            .animation(.easeOut(duration: 0.08), value: down)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        game.overlayButton(button, true)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in
                        down = false
                        game.overlayButton(button, false)
                    }
            )
            .accessibilityAddTraits(.isButton)
    }
}
