//
// FullScreenLayout.swift
// RetroCartridge
//
// 7.6" inner display. Without a game it shows the cartridge library; with a
// game it becomes a handheld console split exactly at the fold, using the
// fold's reserved region: CRT above and controls below in portrait (the
// clamshell / laptop pose), CRT on the leading side in landscape (book pose).
// The inner display doesn't honor orientation locks, so the layout adapts to
// whatever orientation the system uses (DESIGN.md §4).
//

import SwiftUI

public struct FullScreenLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(HapticManager.self) private var hapticManager
    @Environment(AudioManager.self) private var audioManager
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.consoleTheme) private var consoleTheme

    /// The cartridge sliding into the slot, just before the console powers on.
    @State private var insertingGame: GameType?

    /// Bumped when a cartridge goes in, jolting the console once.
    @State private var consoleThunk = 0

    public init() {}

    public var body: some View {
        ZStack {
            if appState.isGameActive {
                console
                    .transition(.opacity)
            } else {
                library
                    .transition(.opacity)
            }

            // Overlays belong to the library, so they never cover a running console.
            LibraryOverlays(isEnabled: !appState.isGameActive)
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isGameActive)
    }
    
    // MARK: - Console

    private var console: some View {
        let theme = SkinManager.theme(for: storeManager.effectiveSkin(appState.selectedSkin))
        
        return GeometryReader { geo in
            let split = FoldSplit(
                size: geo.size,
                fold: geo.reservedRegions(kind: .division, options: .includeInactive).first?.frame
            )
            let insets = geo.safeAreaInsets
            
            ZStack(alignment: .topLeading) {
                ConsoleShell(theme: theme)
                
                // Halves are measured on the full display so the split lands on
                // the fold; each half then keeps clear of its own screen edges
                // and of an active camera.
                ZStack(alignment: .topLeading) {
                    GameCanvasView()
                        .avoidingOcclusion()
                        .padding(split.firstHalfInsets(from: insets))
                        .frame(width: split.first.width, height: split.first.height)
                        .offset(x: split.first.minX, y: split.first.minY)

                    ControllerView()
                        .avoidingOcclusion()
                        .padding(split.secondHalfInsets(from: insets))
                        .frame(width: split.second.width, height: split.second.height)
                        .offset(x: split.second.minX, y: split.second.minY)
                }
                // The cartridge seating: the parts jolt down and settle back
                .keyframeAnimator(initialValue: 0.0, trigger: consoleThunk) { content, drop in
                    content.offset(y: drop)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(5, duration: 0.07)
                        SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                    }
                }
                
                HingeGroove(isVertical: split.isSideBySide)
                    .frame(
                        width: split.isSideBySide ? 2 : geo.size.width,
                        height: split.isSideBySide ? geo.size.height : 2
                    )
                    .offset(
                        x: split.isSideBySide ? split.foldPosition - 1 : 0,
                        y: split.isSideBySide ? 0 : split.foldPosition - 1
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion {
                consoleThunk += 1
            }
        }
    }
    
    // MARK: - Library

    /// Margin around the library content.
    private static let libraryPadding: CGFloat = 32

    private var library: some View {
        GeometryReader { geo in
            // Decided once per display, not per pose: `.includeInactive` also
            // returns the fold while flat, so folding never reflows the grid.
            let hasFold = !geo.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            let metrics = LibraryGridMetrics(
                itemCount: GameType.allCases.count,
                availableWidth: geo.size.width - Self.libraryPadding * 2,
                hasFold: hasFold
            )

            ScrollView {
                libraryContent(metrics: metrics)
                    .padding(Self.libraryPadding)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(ConsoleBackdrop(glowColor: Color(hex: appState.selectedGameType.cartridgeColorHex)))
    }

    private func libraryContent(metrics: LibraryGridMetrics) -> some View {
        VStack(spacing: 36) {
            VStack(spacing: 10) {
                // Printed on the case, in the skin's own print color
                Text("RETROFOLD")
                    .retroFont(34, weight: .black, maxScale: 1.35, wraps: false)
                    .tracking(4)
                    .foregroundStyle(consoleTheme.textColor)
                Text("CHOOSE A CARTRIDGE")
                    .retroFont(13, weight: .semibold)
                    .tracking(4)
                    .foregroundStyle(consoleTheme.textColor.opacity(0.9))
                collectionCounter
                    .padding(.top, 6)
            }

            ownGamesButton

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(metrics.itemWidth), spacing: LibraryGridMetrics.spacing, alignment: .top),
                    count: metrics.columns
                ),
                spacing: LibraryGridMetrics.spacing
            ) {
                ForEach(GameType.shelf) { game in
                    cartridgeSlot(game, width: metrics.itemWidth)
                }
            }
        }
    }
    
    /// The Game Pak, said plainly: the player's own games, one big button above the shelf.
    private var ownGamesButton: some View {
        Button {
            insert(.gamePak)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 26, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLAY YOUR OWN GAMES")
                        .retroFont(17, weight: .black, maxScale: 1.35, wraps: false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("GAME BOY · COLOR · ADVANCE · DS")
                        .retroFont(11, weight: .semibold, maxScale: 1.35, wraps: false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .heavy))
            }
            .foregroundStyle(Color(hex: "#0F380F"))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: GameType.gamePak.cartridgeColorHex).gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color(hex: GameType.gamePak.cartridgeColorHex).opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityLabel("Play your own games: Game Boy, Game Boy Color, Game Boy Advance and DS")
    }

    /// How many cartridges are playable, out of all of them.
    private var collectionCounter: some View {
        let owned = GameType.allCases.filter { storeManager.isUnlocked($0) }.count
        return RetroCapsuleLabel(
            title: String(localized: "COLLECTION \(owned)/\(GameType.allCases.count)"),
            systemImage: "square.stack.fill",
            tint: consoleTheme.textColor
        )
        .accessibilityLabel("\(owned) of \(GameType.allCases.count) cartridges in your collection")
    }

    /// A cartridge standing on its stretch of shelf, with its subtitle.
    private func cartridgeSlot(_ game: GameType, width: CGFloat) -> some View {
        let isLocked = !storeManager.isUnlocked(game)
        let isInserting = insertingGame == game

        return VStack(spacing: 0) {
            Button {
                insert(game)
            } label: {
                CartridgeView(
                    game: game,
                    highScore: appState.highScore(for: game),
                    isSelected: game == appState.selectedGameType,
                    isLocked: isLocked,
                    achievements: AchievementTracker.tally(for: game, progress: appState.progress)
                )
                // Sliding down into the slot, behind the shelf
                .offset(y: isInserting ? width * 0.35 : 0)
                .scaleEffect(isInserting ? 0.92 : 1)
                .opacity(isInserting ? 0 : 1)
            }
            .buttonStyle(CartridgePressStyle())
            .opacity(insertingGame != nil && !isInserting ? 0.35 : 1)
            .contextMenu {
                if !isLocked {
                    Button("Design Label", systemImage: "pencil.and.scribble") {
                        designLabel(for: game)
                    }
                }
            }
            .accessibilityLabel(game.rawValue)
            .accessibilityValue(isLocked ? String(localized: "Locked, part of \(ProductIdentifiers.fallbackDisplayName(for: game.info.requiredProductID ?? ""))") : game.subtitle)

            // Neighboring planks meet across the grid spacing into one shelf
            ShelfLedge()
                .frame(width: width + LibraryGridMetrics.spacing, height: 12)

            // Locked cartridges say which pack they come in
            Group {
                if isLocked, let productID = game.info.requiredProductID {
                    Label(ProductIdentifiers.shortName(for: productID), systemImage: "lock.fill")
                        .foregroundStyle(consoleTheme.textColor)
                } else {
                    Text(game.subtitle)
                        .foregroundStyle(consoleTheme.textColor.opacity(0.9))
                }
            }
            .retroFont(12, weight: .medium)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 10)
            .accessibilityHidden(true)
        }
        .frame(width: width)
    }

    /// Opens the label designer on a cartridge.
    private func designLabel(for game: GameType) {
        hapticManager.playHaptic(.buttonPress)
        appState.selectedGameType = game
        withAnimation(LibraryOverlays.animation) {
            appState.isSkinSelectorVisible = false
            appState.isScreenSettingsVisible = false
            appState.isRecordsVisible = false
            appState.isLabelDesignerVisible = true
        }
    }

    private func insert(_ game: GameType) {
        guard insertingGame == nil else { return }
        guard storeManager.isPlayable(game) else {
            hapticManager.playHaptic(.buttonPress)
            storeManager.demoEnded = game
            withAnimation(LibraryOverlays.animation) {
                appState.openStore(highlighting: game.info.requiredProductID)
            }
            return
        }
        audioManager.playCartridgeClick()

        guard !reduceMotion else {
            hapticManager.playHaptic(.cartridgeInsert)
            appState.startGame(type: game)
            return
        }

        // Slide the cartridge into the slot, then power on
        withAnimation(.easeIn(duration: 0.25)) {
            insertingGame = game
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            hapticManager.playHaptic(.cartridgeInsert)
            appState.startGame(type: game)
            insertingGame = nil
        }
    }
}

/// A shelf plank for cartridges to stand on: a lit top surface and a
/// darker front edge.
private struct ShelfLedge: View {
    var body: some View {
        // Shades over the case rather than fixed greys, so the ledge reads
        // as molded into whichever case the skin has
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                .frame(height: 4)
            Rectangle()
                .fill(LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
        }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Library grid

/// Column count and cartridge width for the library grid.
///
/// Rows are balanced, so four cartridges become 2×2 rather than 3 + 1. On a
/// display with a fold the column count is even, following the HIG ("In a
/// grid-style layout, prefer an even number of columns so content divides
/// cleanly"). Cartridges are sized from the container, not fixed dimensions.
struct LibraryGridMetrics: Equatable {
    /// Space between cartridges, in both directions.
    static let spacing: CGFloat = 28

    /// Narrowest a cartridge may get before a column is dropped.
    static let minItemWidth: CGFloat = 150

    /// Widest a cartridge may grow.
    static let maxItemWidth: CGFloat = 190

    let columns: Int
    let itemWidth: CGFloat

    init(itemCount: Int, availableWidth: CGFloat, hasFold: Bool) {
        let spacing = Self.spacing
        let fitting = max(1, Int((availableWidth + spacing) / (Self.minItemWidth + spacing)))

        // As few rows as fit, with the cartridges spread evenly over them
        let items = max(1, itemCount)
        let rows = (items + fitting - 1) / fitting
        var columns = (items + rows - 1) / rows

        if hasFold && columns % 2 == 1 {
            columns = columns + 1 <= fitting ? columns + 1 : max(1, columns - 1)
        }

        self.columns = columns
        let widthPerColumn = (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        self.itemWidth = max(1, min(Self.maxItemWidth, widthPerColumn))
    }
}

// MARK: - Shell

/// The molded body of the console in the current skin, edge to edge.
private struct ConsoleShell: View {
    let theme: SkinTheme

    var body: some View {
        ShellSurface(theme: theme)
            .ignoresSafeArea()
    }
}

/// A subtle groove marking where the device folds.
private struct HingeGroove: View {
    let isVertical: Bool
    
    var body: some View {
        Rectangle().fill(
            LinearGradient(
                colors: [.black.opacity(0.25), .white.opacity(0.12)],
                startPoint: isVertical ? .leading : .top,
                endPoint: isVertical ? .trailing : .bottom
            )
        )
    }
}

// MARK: - Fold split

/// Splits the display into two halves at the fold. The fold comes from the
/// `.division` reserved region, queried with `.includeInactive` so it is
/// known even when the device is flat; without one, the display is split in
/// the middle across its longer side.
struct FoldSplit {
    /// The CRT half: top in portrait, leading in landscape.
    let first: CGRect
    /// The controller half: bottom in portrait, trailing in landscape.
    let second: CGRect
    /// True when the fold runs vertically, so the halves sit side by side.
    let isSideBySide: Bool
    /// The fold's center along the split axis.
    let foldPosition: CGFloat
    
    init(size: CGSize, fold: CGRect?) {
        if let fold, fold.width != fold.height {
            isSideBySide = fold.height > fold.width
        } else {
            isSideBySide = size.width > size.height
        }
        
        if isSideBySide {
            let center = fold.map { $0.midX } ?? size.width / 2
            let halfGap = (fold?.width ?? 0) / 2
            foldPosition = center
            first = CGRect(x: 0, y: 0, width: center - halfGap, height: size.height)
            second = CGRect(x: center + halfGap, y: 0, width: size.width - center - halfGap, height: size.height)
        } else {
            let center = fold.map { $0.midY } ?? size.height / 2
            let halfGap = (fold?.height ?? 0) / 2
            foldPosition = center
            first = CGRect(x: 0, y: 0, width: size.width, height: center - halfGap)
            second = CGRect(x: 0, y: center + halfGap, width: size.width, height: size.height - center - halfGap)
        }
    }
    
    /// Safe area insets on the first half's outer edges.
    func firstHalfInsets(from insets: EdgeInsets) -> EdgeInsets {
        isSideBySide
            ? EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: 0)
            : EdgeInsets(top: insets.top, leading: insets.leading, bottom: 0, trailing: insets.trailing)
    }
    
    /// Safe area insets on the second half's outer edges.
    func secondHalfInsets(from insets: EdgeInsets) -> EdgeInsets {
        isSideBySide
            ? EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom, trailing: insets.trailing)
            : EdgeInsets(top: 0, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }
}
