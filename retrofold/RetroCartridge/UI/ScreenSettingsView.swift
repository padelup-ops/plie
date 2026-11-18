//
// ScreenSettingsView.swift
// RetroCartridge
//
// In-hierarchy overlay for choosing the screen the games show through
// (Color CRT, Pocket LCD, Trinitron, Arcade Monitor) and tuning it. Each
// mode card shows a still frame through that mode's shader; the selected
// card reflects the tuning live. Locked modes and tuning open the store.
// Hosted by `LibraryOverlays` on both displays (never as a sheet).
//

import SwiftUI

struct ScreenSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(AudioManager.self) private var audioManager
    @Environment(\.menuTheme) private var menuTheme

    private let columns = 2

    var body: some View {
        OverlayPanel(
            title: "SCREEN",
            subtitle: "CHOOSE YOUR DISPLAY",
            onClose: close
        ) {
            VStack(spacing: 20) {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row) { mode in
                                modeCard(mode)
                            }
                        }
                    }
                }

                tuning
            }
        }
    }

    private var rows: [[ScreenMode]] {
        let all = ScreenMode.allCases
        return stride(from: 0, to: all.count, by: columns).map {
            Array(all[$0..<min($0 + columns, all.count)])
        }
    }

    /// What the console actually draws, limited to what is unlocked.
    private var effectiveSettings: ScreenSettings {
        storeManager.effectiveScreenSettings(appState.screenSettings)
    }

    // MARK: - Actions

    private func close() {
        withAnimation(LibraryOverlays.animation) {
            appState.isScreenSettingsVisible = false
        }
    }

    /// Screen modes and tuning all come with RetroFold Pro.
    private func openStore() {
        withAnimation(LibraryOverlays.animation) {
            appState.openStore(highlighting: ProductIdentifiers.pro)
        }
    }

    private func select(_ mode: ScreenMode) {
        hapticManager.playHaptic(.buttonPress)

        guard storeManager.isUnlocked(mode) else {
            openStore()
            return
        }

        guard mode != effectiveSettings.mode else { return }
        audioManager.playCartridgeClick()
        withAnimation(.easeInOut(duration: 0.25)) {
            appState.screenSettings.mode = mode
        }
    }

    private func resetTuning() {
        hapticManager.playHaptic(.buttonPress)
        withAnimation(.easeInOut(duration: 0.25)) {
            appState.screenSettings = ScreenSettings(mode: appState.screenSettings.mode)
        }
    }

    // MARK: - Mode cards

    private func modeCard(_ mode: ScreenMode) -> some View {
        let isSelected = mode == effectiveSettings.mode
        let isUnlocked = storeManager.isUnlocked(mode)

        return Button {
            select(mode)
        } label: {
            VStack(spacing: 12) {
                ScreenPreview(settings: isSelected ? effectiveSettings : ScreenSettings(mode: mode))
                    .frame(height: 118)
                    .saturation(isUnlocked ? 1 : 0.55)
                    .overlay {
                        if !isUnlocked {
                            OverlayLockBadge()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(spacing: 5) {
                    Text(mode.uppercasedTitle)
                        .retroFont(13, weight: .heavy)
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(mode.summary)
                        .retroFont(11, weight: .medium)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    status(isSelected: isSelected, isUnlocked: isUnlocked)
                }
            }
            .overlayCard(isSelected: isSelected)
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityLabel(mode.title)
        .accessibilityValue(isSelected ? String(localized: "In use") : (isUnlocked ? String(localized: "Unlocked") : String(localized: "Locked, part of \(ProductIdentifiers.fallbackDisplayName(for: ProductIdentifiers.pro))")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func status(isSelected: Bool, isUnlocked: Bool) -> some View {
        Group {
            if isSelected {
                Label("IN USE", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(menuTheme.accent)
            } else if isUnlocked {
                Label("TAP TO USE", systemImage: "hand.tap.fill")
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Label(ProductIdentifiers.shortName(for: ProductIdentifiers.pro), systemImage: "lock.fill")
                    .foregroundStyle(RetroPalette.amber)
            }
        }
        .retroFont(11, weight: .bold)
        .tracking(1)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: - Tuning

    private var tuning: some View {
        @Bindable var appState = appState
        let mode = effectiveSettings.mode
        let canTune = storeManager.canTuneScreen

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TUNING")
                    .retroFont(12, weight: .heavy)
                    .tracking(2.5)
                    .foregroundStyle(menuTheme.accent.opacity(0.85))

                Spacer(minLength: 8)

                if canTune {
                    Button(action: resetTuning) {
                        RetroCapsuleLabel(title: String(localized: "RESET"), systemImage: "arrow.counterclockwise", tint: menuTheme.accent)
                    }
                    .buttonStyle(CartridgePressStyle())
                    .disabled(appState.screenSettings.hasStandardTuning)
                    .opacity(appState.screenSettings.hasStandardTuning ? 0.4 : 1)
                } else {
                    Button(action: openStore) {
                        RetroCapsuleLabel(title: ProductIdentifiers.shortName(for: ProductIdentifiers.pro), systemImage: "lock.fill", tint: RetroPalette.amber)
                    }
                    .buttonStyle(CartridgePressStyle())
                }
            }

            VStack(spacing: 12) {
                tuningSlider(String(localized: "CURVATURE"), value: $appState.screenSettings.curvature)
                    .disabled(!mode.hasCurvature)
                    .opacity(mode.hasCurvature ? 1 : 0.4)
                tuningSlider(mode.linesTitle, value: $appState.screenSettings.scanlines)
                tuningSlider(mode.bleedTitle, value: $appState.screenSettings.bleed)
            }
            .disabled(!canTune)
            .opacity(canTune ? 1 : 0.45)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func tuningSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 8)
                // 0.5 is the designed look, shown as 1.0×
                Text(String(format: "%.1f×", value.wrappedValue * 2))
                    .foregroundStyle(menuTheme.accent)
            }
            .retroFont(11, weight: .bold)
            .tracking(1)

            Slider(value: value, in: 0...1)
                .tint(menuTheme.accent)
                .accessibilityLabel(title.capitalized)
                .accessibilityValue(String(localized: "\(String(format: "%.1f", value.wrappedValue * 2)) times"))
        }
    }
}

// MARK: - Preview frame

/// A still frame of Brick Breaker shown through a screen, for the picker.
struct ScreenPreview: View {
    let settings: ScreenSettings

    var body: some View {
        Canvas { context, size in
            Self.drawFrame(in: &context, size: size)
        }
        // Drawn flat: the preview isn't tied to how the device is folded.
        .screenEffect(settings, hingeAngle: 180, powerOnProgress: 1)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .aspectRatio(10 / 9, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func drawFrame(in context: inout GraphicsContext, size: CGSize) {
        let palette = GamePalette.brickBreaker
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

        // Brick wall with a few bricks already broken
        let columns = 8
        let rows = 5
        let brickWidth = size.width / CGFloat(columns)
        let brickHeight = size.height * 0.06
        let top = size.height * 0.12
        let broken: Set<Int> = [26, 29, 36, 37]
        for row in 0..<rows {
            for column in 0..<columns where !broken.contains(row * columns + column) {
                let rect = CGRect(
                    x: CGFloat(column) * brickWidth + 1,
                    y: top + CGFloat(row) * brickHeight + 1,
                    width: brickWidth - 2,
                    height: brickHeight - 2
                )
                context.fill(Path(rect), with: .color(palette.spectrumColor(row)))
            }
        }

        // Paddle and ball
        let paddle = CGRect(x: size.width * 0.38, y: size.height * 0.86, width: size.width * 0.22, height: size.height * 0.03)
        context.fill(Path(paddle), with: .color(palette.player))
        let ballSize = max(4, size.width * 0.04)
        let ball = CGRect(x: size.width * 0.56, y: size.height * 0.62, width: ballSize, height: ballSize)
        context.fill(Path(ball), with: .color(palette.playerHighlight))
    }
}
