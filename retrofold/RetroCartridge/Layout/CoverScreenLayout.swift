//
// CoverScreenLayout.swift
// RetroCartridge
//
// 5.4" outer display: a swipeable cartridge case. The display is locked to the
// landscape orientation that puts the hinge on top (ConsoleHostingController).
// The app name and the Skins / Screen / Store buttons live in the system
// toolbar. Behind the details, the selected cartridge plays itself faintly
// (attract mode). The chosen cartridge is inserted automatically when the
// device is unfolded.
//

import SwiftUI

public struct CoverScreenLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    /// The cover is the case: its text is the skin's print color.
    @Environment(\.consoleTheme) private var consoleTheme
    @State private var blink: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            // Hinge-on-top pose: cartridge on the left, details on the right
            HStack(spacing: 0) {
                carousel(cartridgeWidth: min(geo.size.height * 0.72 * CartridgeView.aspectRatio, geo.size.width * 0.4))
                    .frame(width: geo.size.width * 0.48)
                
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    details(alignment: .leading)
                    pageIndicator
                        .padding(.top, 16)
                    Spacer()
                    unfoldPrompt
                }
                .padding(.vertical, 24)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background { attractMode }
    }

    /// The selected game playing itself behind the details. It spans the
    /// display edge to edge like a background, faded toward the cartridge
    /// and toward the toolbar column so neither loses contrast.
    private var attractMode: some View {
        AttractScreen(gameType: appState.selectedGameType)
            .aspectRatio(10 / 9, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .opacity(0.2)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.45),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .ignoresSafeArea()
    }
    
    // MARK: - Pieces

    private func carousel(cartridgeWidth: CGFloat) -> some View {
        @Bindable var appState = appState

        return TabView(selection: $appState.selectedGameType) {
            ForEach(GameType.allCases) { game in
                CartridgeView(
                    game: game,
                    highScore: appState.highScore(for: game),
                    isSelected: game == appState.selectedGameType,
                    isLocked: !storeManager.isUnlocked(game),
                    achievements: AchievementTracker.tally(for: game, progress: appState.progress)
                )
                .frame(width: cartridgeWidth)
                .padding(.vertical, 20)
                .tag(game)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func details(alignment: HorizontalAlignment) -> some View {
        let selected = appState.selectedGameType

        return VStack(alignment: alignment, spacing: 8) {
            Text(selected.rawValue.uppercased())
                .retroFont(24, weight: .black, maxScale: 1.35, wraps: false)
                .foregroundStyle(consoleTheme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(selected.subtitle)
                .retroFont(14, weight: .medium, maxScale: 1.35, wraps: false)
                .foregroundStyle(consoleTheme.textColor.opacity(0.9))

            let best = appState.highScore(for: selected)
            if best > 0 {
                Text("HI \(best)")
                    .retroFont(13, weight: .bold, maxScale: 1.35, wraps: false)
                    .foregroundStyle(consoleTheme.textColor)
                    .padding(.top, 2)
            }
        }
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private var pageIndicator: some View {
        let selected = appState.selectedGameType

        return HStack(spacing: 8) {
            ForEach(GameType.allCases) { game in
                Capsule()
                    .fill(game == selected ? Color(hex: game.cartridgeColorHex) : consoleTheme.textColor.opacity(0.25))
                    .frame(width: game == selected ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }

    private var unfoldPrompt: some View {
        let isLocked = !storeManager.isUnlocked(appState.selectedGameType)

        return HStack(spacing: 10) {
            Image(systemName: isLocked ? "lock.fill" : "arrow.up.and.down")
                .font(.system(size: 14, weight: .bold))
            Text(isLocked ? ProductIdentifiers.shortName(for: appState.selectedGameType.info.requiredProductID ?? "") : String(localized: "UNFOLD TO PLAY"))
                .retroFont(15, weight: .heavy, maxScale: 1.35, wraps: false)
                .tracking(3)
        }
        .foregroundStyle(consoleTheme.textColor)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(consoleTheme.textColor.opacity(0.08))
                .overlay(Capsule().stroke(Color(hex: appState.selectedGameType.cartridgeColorHex).opacity(0.6), lineWidth: 1))
        )
        .opacity(blink ? 1.0 : 0.35)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: blink)
        .onAppear { blink = true }
    }
}
