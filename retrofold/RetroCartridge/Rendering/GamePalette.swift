// GamePalette.swift
// RetroCartridge
//
// The colors a game draws with, named by their role on screen. Games never
// hard-code colors in `render`; they read their `palette`, so the same game
// can be shown in another palette without touching its code. Each game's own
// palette lives next to it (e.g. `GamePalette.snake` in SnakeGame.swift);
// the shared palettes the player can pick (`PaletteChoice`) live here.

import SwiftUI

// MARK: - Game Palette

/// Colors a game renders with, by role.
struct GamePalette: Equatable, Sendable {
    /// Clears the screen every frame.
    var background: Color

    /// Faint guides over the background: grid lines, lane markings.
    var guide: Color

    /// The player's piece: paddle, car, snake body.
    var player: Color

    /// An emphasised player detail: the snake's head, the ball.
    var playerHighlight: Color

    /// Something good to collect: food, a power-up.
    var pickup: Color

    /// A second kind of pickup, told apart from the first.
    var pickupAlt: Color

    /// Something to avoid: traffic.
    var hazard: Color

    /// A second kind of hazard, told apart from the first.
    var hazardAlt: Color

    /// Edges drawn around solid cells.
    var outline: Color

    /// Ordered colors for families of objects, such as brick rows or block
    /// shapes. Read them with `spectrumColor(_:)`, which wraps around.
    var spectrum: [Color]

    /// The spectrum color at `index`, wrapping around in both directions.
    func spectrumColor(_ index: Int) -> Color {
        guard !spectrum.isEmpty else { return player }
        let count = spectrum.count
        return spectrum[((index % count) + count) % count]
    }

    /// The palette a game was designed with.
    static func native(for game: GameType) -> GamePalette {
        switch game {
        case .brickBreaker: return .brickBreaker
        case .retroRacer: return .retroRacer
        case .snake: return .snake
        case .fallingBlocks: return .fallingBlocks
        case .pixelInvaders: return .pixelInvaders
        case .mineSweep: return .mineSweep
        case .mazeMuncher: return .mazeMuncher
        case .frogHop: return .frogHop
        case .lunarHinge: return .lunarHinge
        case .paddleDuel: return .paddleDuel
        case .astroDrift: return .astroDrift
        case .towerStack: return .towerStack
        }
    }
}

// MARK: - Palette choice

/// The palette the player picks for every game: each game's own colors, or a
/// shared palette that recolors any game through its roles.
enum PaletteChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case dmgGreen
    case pocketGrey
    case virtualRed
    case neonNight

    var id: String { rawValue }

    /// Name shown in the pause menu.
    var title: String {
        switch self {
        case .original: return String(localized: "Original")
        case .dmgGreen: return String(localized: "DMG Green")
        case .pocketGrey: return String(localized: "Pocket Grey")
        case .virtualRed: return String(localized: "Virtual Red")
        case .neonNight: return String(localized: "Neon Night")
        }
    }

    /// The palette a game draws with under this choice.
    func palette(for game: GameType) -> GamePalette {
        switch self {
        case .original: return .native(for: game)
        case .dmgGreen: return .dmgGreen
        case .pocketGrey: return .pocketGrey
        case .virtualRed: return .virtualRed
        case .neonNight: return .neonNight
        }
    }
}

// MARK: - Shared palettes

extension GamePalette {
    /// Four shades of green on a pale backplate, like the original handheld.
    static let dmgGreen = GamePalette(
        background: Color(hex: "#9BBC0F"),
        guide: Color(hex: "#8BAC0F"),
        player: Color(hex: "#0F380F"),
        playerHighlight: Color(hex: "#306230"),
        pickup: Color(hex: "#306230"),
        pickupAlt: Color(hex: "#0F380F"),
        hazard: Color(hex: "#0F380F"),
        hazardAlt: Color(hex: "#306230"),
        outline: Color(hex: "#8BAC0F"),
        spectrum: [Color(hex: "#0F380F"), Color(hex: "#306230")]
    )

    /// Neutral greys on a silver screen.
    static let pocketGrey = GamePalette(
        background: Color(hex: "#D8D8C8"),
        guide: Color(hex: "#BCBCAC"),
        player: Color(hex: "#202020"),
        playerHighlight: Color(hex: "#505048"),
        pickup: Color(hex: "#606058"),
        pickupAlt: Color(hex: "#202020"),
        hazard: Color(hex: "#202020"),
        hazardAlt: Color(hex: "#606058"),
        outline: Color(hex: "#BCBCAC"),
        spectrum: [Color(hex: "#202020"), Color(hex: "#505048"), Color(hex: "#808078")]
    )

    /// Red on black, like a stereoscopic headset.
    static let virtualRed = GamePalette(
        background: .black,
        guide: Color(hex: "#3A0000"),
        player: Color(hex: "#FF1A1A"),
        playerHighlight: Color(hex: "#FF7070"),
        pickup: Color(hex: "#FF4040"),
        pickupAlt: Color(hex: "#B00000"),
        hazard: Color(hex: "#D00000"),
        hazardAlt: Color(hex: "#800000"),
        outline: .black,
        spectrum: [Color(hex: "#FF1A1A"), Color(hex: "#C00000"), Color(hex: "#FF5A5A"), Color(hex: "#900000"), Color(hex: "#FF8080")]
    )

    /// Saturated neon on deep violet.
    static let neonNight = GamePalette(
        background: Color(hex: "#0A0014"),
        guide: Color(hex: "#2A1A4A"),
        player: Color(hex: "#00F0FF"),
        playerHighlight: .white,
        pickup: Color(hex: "#39FF14"),
        pickupAlt: Color(hex: "#FFE600"),
        hazard: Color(hex: "#FF2079"),
        hazardAlt: Color(hex: "#FF8A00"),
        outline: Color(hex: "#0A0014"),
        spectrum: [
            Color(hex: "#FF2079"), Color(hex: "#FF8A00"), Color(hex: "#FFE600"), Color(hex: "#39FF14"),
            Color(hex: "#00F0FF"), Color(hex: "#7B61FF"), Color(hex: "#FF5CF0")
        ]
    )
}
