//
// LabelDesignerView.swift
// RetroCartridge
//
// In-hierarchy overlay for drawing a cartridge's label with a finger: a
// 16×16 grid in the game's own palette, a pencil and a fill tool, mirror
// drawing, undo, and a way back to the built-in artwork. Each finished
// stroke is saved (`LabelStore`), so the cartridge on the shelf, the cover
// and in the records shows the new label right away. Hosted by
// `LibraryOverlays` on both displays (never as a sheet).
//

import SwiftUI

struct LabelDesignerView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(PostureManager.self) private var postureManager
    @Environment(\.menuTheme) private var menuTheme

    /// How a touch on the grid paints.
    enum Tool: CaseIterable {
        /// Paints the pixels the finger passes over.
        case pencil
        /// Fills the area of same-colored pixels that was touched.
        case fill
    }

    /// The cartridge being drawn; nil until the designer appears.
    @State private var game: GameType?
    /// The label as drawn so far.
    @State private var art: PixelArt = .blank
    /// The pixel character painted with; "." erases.
    @State private var ink: Character = "P"
    @State private var tool: Tool = .pencil
    @State private var isMirrored = false
    /// Earlier versions of the label, newest last, for undo.
    @State private var history: [PixelArt] = []
    /// The label before the stroke in progress; nil between strokes.
    @State private var strokeStart: PixelArt?

    /// How many undo steps are kept.
    private static let historyLimit = 40

    var body: some View {
        OverlayPanel(
            title: "LABEL DESIGNER",
            subtitle: "DRAW YOUR OWN CARTRIDGE ART",
            onClose: close
        ) {
            VStack(spacing: 20) {
                cartridgePicker

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        canvas
                        controls
                            .frame(width: 220)
                    }
                    VStack(spacing: 20) {
                        canvas
                        controls
                    }
                }
            }
        }
        .onAppear {
            if game == nil {
                load(initialGame)
            }
        }
    }

    // MARK: - Cartridges

    /// Cartridges that can be drawn: the unlocked ones.
    private var designableGames: [GameType] {
        GameType.allCases.filter { storeManager.isUnlocked($0) }
    }

    /// The selected cartridge when it's unlocked, else the first one that is.
    private var initialGame: GameType {
        let games = designableGames
        return games.contains(appState.selectedGameType) ? appState.selectedGameType : games.first ?? .brickBreaker
    }

    /// The cartridge with its live label, and arrows to switch cartridges.
    private var cartridgePicker: some View {
        let current = game ?? initialGame
        let hasCustomLabel = appState.labels.hasCustomLabel(for: current)

        return HStack(spacing: 16) {
            stepButton("chevron.left", label: "Previous cartridge") { step(by: -1) }

            CartridgeView(game: current)
                .frame(width: 78)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(current.rawValue.uppercased())
                    .retroFont(16, weight: .black)
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                RetroCapsuleLabel(
                    title: hasCustomLabel ? String(localized: "YOUR LABEL") : String(localized: "ORIGINAL LABEL"),
                    systemImage: hasCustomLabel ? "pencil.and.scribble" : "seal.fill",
                    tint: hasCustomLabel ? menuTheme.accent : .white.opacity(0.6)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            stepButton("chevron.right", label: "Next cartridge") { step(by: 1) }
        }
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(CartridgePressStyle())
        .disabled(designableGames.count < 2)
        .accessibilityLabel(label)
    }

    private func step(by offset: Int) {
        let games = designableGames
        guard let current = game, let index = games.firstIndex(of: current), !games.isEmpty else { return }
        hapticManager.playHaptic(.buttonPress)
        load(games[(index + offset % games.count + games.count) % games.count])
    }

    private func load(_ newGame: GameType) {
        game = newGame
        art = appState.labels.art(for: newGame)
        history = []
        strokeStart = nil
        ink = "P"
    }

    // MARK: - Canvas

    /// Side of one pixel on the grid: smaller on the cover display.
    private var cell: CGFloat {
        postureManager.isCompactWidth ? 15 : 22
    }

    private var canvas: some View {
        let cell = self.cell
        let side = cell * CGFloat(PixelArt.size)
        let palette = GamePalette.native(for: game ?? initialGame)

        // Capturing the art and mirror setting makes each drawing's renderer
        // distinct, so the grid redraws as it's painted (see `GameCanvasView`).
        return Canvas { [art = self.art, isMirrored = self.isMirrored] context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

            for (y, row) in art.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = PixelArt.color(for: character, in: palette) else { continue }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }

            // Pixel grid, a little stronger every four pixels
            for i in 0...PixelArt.size {
                let position = CGFloat(i) * cell
                var line = Path()
                line.move(to: CGPoint(x: position, y: 0))
                line.addLine(to: CGPoint(x: position, y: side))
                line.move(to: CGPoint(x: 0, y: position))
                line.addLine(to: CGPoint(x: side, y: position))
                context.stroke(line, with: .color(.white.opacity(i % 4 == 0 ? 0.16 : 0.07)), lineWidth: 0.5)
            }

            // The mirror line down the middle
            if isMirrored {
                var middle = Path()
                middle.move(to: CGPoint(x: side / 2, y: 0))
                middle.addLine(to: CGPoint(x: side / 2, y: side))
                context.stroke(middle, with: .color(menuTheme.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { paint(at: $0.location, cell: cell) }
                .onEnded { _ in endStroke() }
        )
        // VoiceOver users draw by touch, as on the console
        .accessibilityElement()
        .accessibilityLabel("Drawing grid, 16 by 16 pixels")
        .accessibilityValue("\(art.paintedCount) pixels drawn")
        .accessibilityHint("Touch to draw with the selected color.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func paint(at location: CGPoint, cell: CGFloat) {
        let x = Int((location.x / cell).rounded(.down))
        let y = Int((location.y / cell).rounded(.down))
        guard (0..<PixelArt.size).contains(x), (0..<PixelArt.size).contains(y) else { return }

        let isFirstTouch = strokeStart == nil
        if isFirstTouch {
            strokeStart = art
        }

        switch tool {
        case .pencil:
            art = art.setting(ink, atX: x, y: y, mirrored: isMirrored)
        case .fill:
            // One fill per touch, where the finger first came down
            if isFirstTouch {
                art = art.filling(fromX: x, y: y, with: ink)
            }
        }
    }

    /// Ends a stroke: keeps the previous label for undo and saves the new one.
    private func endStroke() {
        guard let before = strokeStart else { return }
        strokeStart = nil
        guard before != art else { return }
        record(before)
        save()
    }

    private func record(_ previous: PixelArt) {
        history.append(previous)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    private func save() {
        guard let game else { return }
        appState.labels.save(art, for: game)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("COLOR") {
                swatches
            }

            section("TOOL") {
                HStack(spacing: 8) {
                    toolButton(.pencil, title: String(localized: "DRAW"), symbol: "pencil")
                    toolButton(.fill, title: String(localized: "FILL"), symbol: "drop.fill")
                }
                Button {
                    hapticManager.playHaptic(.buttonPress)
                    isMirrored.toggle()
                } label: {
                    RetroCapsuleLabel(
                        title: String(localized: "MIRROR"),
                        systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                        tint: menuTheme.accent,
                        filled: isMirrored
                    )
                }
                .buttonStyle(CartridgePressStyle())
                .accessibilityLabel("Mirror drawing")
                .accessibilityValue(isMirrored ? String(localized: "On") : String(localized: "Off"))
            }

            section("EDIT") {
                HStack(spacing: 8) {
                    actionButton(String(localized: "UNDO"), symbol: "arrow.uturn.backward", isEnabled: !history.isEmpty, action: undo)
                    actionButton(String(localized: "CLEAR"), symbol: "trash", isEnabled: art != .blank, action: clear)
                }
                actionButton(String(localized: "ORIGINAL"), symbol: "arrow.counterclockwise", isEnabled: game.map { art != PixelArt.label(for: $0) } ?? false, action: restoreOriginal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .retroFont(12, weight: .heavy)
                .tracking(2.5)
                .foregroundStyle(menuTheme.accent.opacity(0.85))
            content()
        }
    }

    /// The game palette's colors, plus an eraser.
    private var swatches: some View {
        let palette = GamePalette.native(for: game ?? initialGame)
        let columns = [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 8)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(PixelArt.pixels(for: palette), id: \.self) { pixel in
                swatch(pixel, palette: palette)
            }
        }
    }

    private func swatch(_ pixel: Character, palette: GamePalette) -> some View {
        let isSelected = ink == pixel
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return Button {
            hapticManager.playHaptic(.buttonPress)
            ink = pixel
        } label: {
            ZStack {
                shape.fill(PixelArt.color(for: pixel, in: palette) ?? palette.background)
                if pixel == "." {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: 34, height: 34)
            .overlay(shape.stroke(isSelected ? menuTheme.accent : Color.white.opacity(0.18), lineWidth: isSelected ? 3 : 1))
            .shadow(color: isSelected ? menuTheme.accent.opacity(0.5) : .clear, radius: 6)
            .contentShape(shape)
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityLabel(Self.swatchName(pixel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// What VoiceOver calls a swatch, by the role its color plays in the game.
    static func swatchName(_ pixel: Character) -> String {
        switch pixel {
        case ".": return String(localized: "Eraser")
        case "P": return String(localized: "Player color")
        case "H": return String(localized: "Highlight color")
        case "F": return String(localized: "Pickup color")
        case "X": return String(localized: "Hazard color")
        case "Y": return String(localized: "Second hazard color")
        case "G": return String(localized: "Guide color")
        case "W": return String(localized: "White")
        default: return String(localized: "Color \((pixel.wholeNumberValue ?? 0) + 1)")
        }
    }

    private func toolButton(_ value: Tool, title: String, symbol: String) -> some View {
        Button {
            hapticManager.playHaptic(.buttonPress)
            tool = value
        } label: {
            RetroCapsuleLabel(title: title, systemImage: symbol, tint: menuTheme.accent, filled: tool == value)
        }
        .buttonStyle(CartridgePressStyle())
        .accessibilityAddTraits(tool == value ? .isSelected : [])
    }

    private func actionButton(_ title: String, symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            hapticManager.playHaptic(.buttonPress)
            action()
        } label: {
            RetroCapsuleLabel(title: title, systemImage: symbol, tint: .white.opacity(isEnabled ? 0.85 : 0.3))
        }
        .buttonStyle(CartridgePressStyle())
        .disabled(!isEnabled)
    }

    // MARK: - Actions

    private func undo() {
        guard let previous = history.popLast() else { return }
        art = previous
        save()
    }

    private func clear() {
        record(art)
        art = .blank
        save()
    }

    /// Back to the cartridge's built-in artwork; undo brings the drawing back.
    private func restoreOriginal() {
        guard let game else { return }
        record(art)
        art = PixelArt.label(for: game)
        appState.labels.removeCustomLabel(for: game)
    }

    private func close() {
        withAnimation(LibraryOverlays.animation) {
            appState.isLabelDesignerVisible = false
        }
    }
}
