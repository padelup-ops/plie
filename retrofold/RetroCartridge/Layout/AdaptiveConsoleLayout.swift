//
// AdaptiveConsoleLayout.swift
// RetroCartridge
//
// Root router between the outer (cover) and inner displays.
//
// - Outer display: locked to the landscape orientation with the hinge on top
//   (see `ConsoleHostingController`); a cartridge carousel.
// - Inner display: follows the system's orientation and splits the console at
//   the fold (see `FullScreenLayout`).
//
// App controls (title, Skins, Screen, Labels, Store, Records) live in the system toolbar, which iPhone
// Duo lays out vertically in the column beside the camera and status bar, or
// as a regular top bar on the inner display in portrait. The toolbar is
// hidden over a running console, an immersive screen without bars
// (DESIGN.md §5–6).
//

import SwiftUI

public struct AdaptiveConsoleLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(PostureManager.self) private var postureManager
    @Environment(HingeEngine.self) private var hingeEngine
    @Environment(AudioManager.self) private var audioManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(StoreManager.self) private var storeManager

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 25/255, green: 28/255, blue: 28/255) // #191C1C
                .ignoresSafeArea()

            if postureManager.isCompactWidth {
                ZStack {
                    ConsoleBackdrop(glowColor: Color(hex: appState.selectedGameType.cartridgeColorHex))
                    CoverScreenLayout()
                    LibraryOverlays()
                }
                .transition(.opacity)
            } else {
                FullScreenLayout()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: postureManager.isCompactWidth)
        // The library and cover are the equipped skin's case and the overlays
        // take its colors; a locked skin (e.g. after a refund) gives the
        // default, like the console
        .environment(\.consoleTheme, equippedTheme)
        .environment(\.menuTheme, equippedTheme.menu)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .toolbarVisibility(showsConsole ? .hidden : .automatic, for: .navigationBar)
        .background {
            // Measure the whole display (not the safe area) to tell which one we're on
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    postureManager.updateDisplay(fullScreenSize: size)
                }
                .ignoresSafeArea()
        }
        // Real hinge angle for the CRT curvature and the unfold chime (visuals only)
        .onHingeChange { _, context in
            hingeEngine.updateFromHardware(context.hinge)
        }
        .onChange(of: postureManager.isCompactWidth) { wasCompact, isCompact in
            if wasCompact && !isCompact {
                // Unfolded: insert the cartridge chosen on the cover screen,
                // swapping out a paused one if the player picked another
                appState.insertCartridgeOnUnfold(isUnlocked: storeManager.isUnlocked(appState.selectedGameType))
            } else if isCompact {
                // Folded: keep the session but pause it (app continuity)
                appState.pauseActiveGame()
            }
        }
    }

    /// The skin the console shows, which the library and overlays follow.
    private var equippedTheme: SkinTheme {
        SkinManager.theme(for: storeManager.effectiveSkin(appState.selectedSkin))
    }

    /// A running console on the inner display is immersive: no bars.
    private var showsConsole: Bool {
        !postureManager.isCompactWidth && appState.isGameActive
    }

    // MARK: - Toolbar

    /// Symbol + title items, so the system can lay them out vertically in the
    /// side column (text-only or custom-view items would stay horizontal).
    ///
    /// Two groups, as the HIG suggests, with visibility priorities from whole
    /// groups down: customization (Skins, Screen, Labels) stays longest; then Store,
    /// with Records, the least-used, at the bottom so it overflows first.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // The app icon in the top-leading corner, where the title used to
        // be: decorative, so no glass capsule and hidden from VoiceOver.
        ToolbarItem(placement: .topBarLeading) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                .accessibilityHidden(true)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                open(\.isSkinSelectorVisible)
            } label: {
                Label("Skins", systemImage: "paintpalette.fill")
            }
            Button {
                open(\.isScreenSettingsVisible)
            } label: {
                Label("Screen", systemImage: "tv")
            }
            Button {
                open(\.isLabelDesignerVisible)
            } label: {
                Label("Labels", systemImage: "pencil.and.scribble")
            }
        }
        .visibilityPriority(.high)

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                open(\.isStoreVisible)
            } label: {
                Label("Store", systemImage: "bag.fill")
            }
            Button {
                open(\.isRecordsVisible)
            } label: {
                Label("Records", systemImage: "trophy.fill")
            }
        }
    }

    private func open(_ flag: ReferenceWritableKeyPath<AppState, Bool>) {
        audioManager.playCartridgeClick()
        hapticManager.playHaptic(.buttonPress)
        withAnimation(LibraryOverlays.animation) {
            // Skins, Screen, Labels and Records replace each other; the store stacks on top.
            if flag != \AppState.isStoreVisible {
                appState.isSkinSelectorVisible = false
                appState.isScreenSettingsVisible = false
                appState.isRecordsVisible = false
                appState.isLabelDesignerVisible = false
            } else {
                appState.storeHighlight = nil
            }
            appState[keyPath: flag] = true
        }
    }
}
