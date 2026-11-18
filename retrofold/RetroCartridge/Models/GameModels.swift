// GameModels.swift
// RetroCartridge
//
// Shared types used across all modules.

import SwiftUI

// MARK: - Game State

/// Represents the current state of any mini-game.
enum GameState: Equatable {
    case menu
    case playing
    case paused
    case gameOver(score: Int)
}

// MARK: - Game Input

/// All possible controller input actions from the D-Pad and buttons.
enum GameInputAction: Equatable {
    // D-Pad directions (press)
    case dpadUpPressed
    case dpadDownPressed
    case dpadLeftPressed
    case dpadRightPressed
    
    // D-Pad release
    case dpadLeftReleased
    case dpadRightReleased
    case dpadUpReleased
    case dpadDownReleased
    
    // Action buttons (press)
    case buttonAPressed
    case buttonBPressed
    
    // Action button release
    case buttonAReleased
    case buttonBReleased
    
    // System buttons
    case buttonStartPressed
    case buttonSelectPressed
}

// MARK: - Device Posture

/// Represents the physical posture of the iPhone Duo, derived by
/// PostureManager from which display the app is on (never from the hinge angle).
enum DevicePosture: Equatable, CustomStringConvertible {
    case closed
    case fullyOpen
    
    var description: String {
        switch self {
        case .closed: return "Closed"
        case .fullyOpen: return "Fully Open"
        }
    }
}

// MARK: - Console Skin

/// Available console skin themes.
enum ConsoleSkinType: String, CaseIterable, Identifiable, Codable {
    case classicGrey = "Classic Grey"
    case atomicPurple = "Atomic Purple"
    case cyberpunkNeon = "Cyberpunk Neon"
    case arcadeCabinet = "90's Arcade Cabinet"
    case clearIce = "Clear Ice"
    case crimsonCream = "Crimson & Cream"
    case electricYellow = "Electric Yellow"
    case goldEdition = "Gold Edition"
    
    var id: String { rawValue }
    
    /// Whether this skin is available in the free tier.
    var isFree: Bool {
        switch self {
        case .classicGrey: return true
        default: return false
        }
    }
    
    /// The IAP product ID required to unlock this skin (nil if free).
    /// Every skin but Classic Grey comes with RetroFold Pro.
    var requiredProductID: String? {
        self == .classicGrey ? nil : ProductIdentifiers.pro
    }
}

// MARK: - Screen

/// The display the game shows through. Every mode is drawn by the
/// `screenEffect` shader; `shaderIndex` selects its branch.
enum ScreenMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case crt
    case lcd
    case trinitron
    case arcade

    var id: String { rawValue }

    /// Name shown in the screen picker.
    var title: String {
        switch self {
        case .crt: return String(localized: "Color CRT")
        case .lcd: return String(localized: "Pocket LCD")
        case .trinitron: return String(localized: "Trinitron")
        case .arcade: return String(localized: "Arcade Monitor")
        }
    }

    /// The title in capitals, as the picker, the store and the pause menu
    /// show it.
    var uppercasedTitle: String {
        title.uppercased()
    }

    /// One-line description for the screen picker.
    var summary: String {
        switch self {
        case .crt: return String(localized: "Curved tube, soft glow")
        case .lcd: return String(localized: "Four shades of green")
        case .trinitron: return String(localized: "Flat and sharp, RGB grille")
        case .arcade: return String(localized: "Deep lines, big bloom")
        }
    }

    /// Model name printed on the bezel above the screen.
    var bezelLabel: String {
        switch self {
        case .crt: return "COLOR CRT"
        case .lcd: return "DOT MATRIX"
        case .trinitron: return "TRINITRON"
        case .arcade: return "ARCADE CRT"
        }
    }

    /// The branch of the `screenEffect` shader that draws this mode.
    var shaderIndex: Float {
        switch self {
        case .crt: return 0
        case .lcd: return 1
        case .trinitron: return 2
        case .arcade: return 3
        }
    }

    /// Whether the picture bends with the tube (an LCD panel is flat).
    var hasCurvature: Bool { self != .lcd }

    /// Name of the line-strength tuning control.
    var linesTitle: String { self == .lcd ? String(localized: "PIXEL GRID") : String(localized: "SCANLINES") }

    /// Name of the bleed tuning control.
    var bleedTitle: String { self == .lcd ? String(localized: "PIXEL SHADOW") : String(localized: "COLOR BLEED") }

    /// The IAP product that unlocks the mode, nil when it is free.
    var requiredProductID: String? {
        self == .crt ? nil : ProductIdentifiers.pro
    }
}

/// The chosen screen and its tuning. Each tuning value runs from 0 to 1,
/// where 0.5 is the mode's designed look.
struct ScreenSettings: Codable, Equatable, Sendable {
    var mode: ScreenMode = .crt
    var curvature: Double = 0.5
    var scanlines: Double = 0.5
    var bleed: Double = 0.5

    /// The free default: Color CRT as designed.
    static let standard = ScreenSettings()

    /// Whether the tuning is the designed look, whatever the mode.
    var hasStandardTuning: Bool {
        curvature == 0.5 && scanlines == 0.5 && bleed == 0.5
    }
}

// MARK: - Game Mode

/// A rule set a cartridge can be played with. Each mode keeps its own high
/// score. Every game supports `.standard`, the rules it shipped with, which
/// a game may present under its own name (e.g. "Marathon"), and `.daily`.
///
/// Two modes are the same rule set when their ids match.
struct GameMode: Hashable, Identifiable, Sendable {
    /// Stable identifier, used in persistence keys. Never rename a shipped one.
    let id: String

    /// Short name for menus, e.g. "SPRINT".
    let title: String

    /// One-line summary of the rules.
    let summary: String

    /// A daily round: standard rules, dealt from the day's shared seed, with
    /// a high score that starts over every day.
    var isDaily: Bool = false

    static let standard = GameMode(id: "standard", title: String(localized: "Standard"), summary: String(localized: "The classic rules."))

    static let daily = GameMode(id: "daily", title: String(localized: "Daily"), summary: String(localized: "Today's round, same for everyone."), isDaily: true)

    static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Cartridge

/// The molded plastic a cartridge shell is made of.
struct CartridgeShell: Equatable, Sendable {
    /// Top of the shell's vertical gradient.
    var topColor: Color

    /// Bottom of the shell's vertical gradient.
    var bottomColor: Color

    /// See-through plastic: the circuit board inside shows through.
    var isTranslucent: Bool = false

    /// Glow-in-the-dark plastic gives off this color; nil for none.
    var glowColor: Color? = nil

    /// The standard grey shell.
    static let grey = CartridgeShell(topColor: Color(white: 0.36), bottomColor: Color(white: 0.24))

    /// Glossy black plastic.
    static let black = CartridgeShell(topColor: Color(white: 0.17), bottomColor: Color(white: 0.07))

    /// Pale glow-in-the-dark plastic.
    static let glow = CartridgeShell(
        topColor: Color(hex: "#D6EFC8"),
        bottomColor: Color(hex: "#A9D39A"),
        glowColor: Color(hex: "#9DFF7A")
    )

    /// Clear purple plastic.
    static let clearPurple = CartridgeShell(
        topColor: Color(hex: "#9B5DE5").opacity(0.55),
        bottomColor: Color(hex: "#4A0E78").opacity(0.65),
        isTranslucent: true
    )

    /// Smoky see-through black plastic.
    static let smoke = CartridgeShell(
        topColor: Color(white: 0.2).opacity(0.6),
        bottomColor: Color(white: 0.05).opacity(0.7),
        isTranslucent: true
    )

    /// Clear green plastic.
    static let clearGreen = CartridgeShell(
        topColor: Color(hex: "#52B788").opacity(0.5),
        bottomColor: Color(hex: "#1B4332").opacity(0.65),
        isTranslucent: true
    )

    /// Off-white plastic, like an old console accessory.
    static let white = CartridgeShell(topColor: Color(hex: "#E9E6DF"), bottomColor: Color(hex: "#BDB8AD"))

    /// Clear blue plastic.
    static let clearBlue = CartridgeShell(
        topColor: Color(hex: "#6D9DC5").opacity(0.5),
        bottomColor: Color(hex: "#1D3557").opacity(0.65),
        isTranslucent: true
    )

    /// Gold plastic, for special editions.
    static let gold = CartridgeShell(
        topColor: Color(hex: "#F3D98B"),
        bottomColor: Color(hex: "#B8860B"),
        glowColor: Color(hex: "#FFD166")
    )
}

/// Everything the library, cover and store know about a cartridge, kept in
/// one place so a new game is described by a single `GameType.info` case.
struct CartridgeInfo: Sendable {
    /// Short description for the game selection UI.
    let subtitle: String

    /// Genre printed on the cartridge, e.g. "PUZZLE".
    let genre: String

    /// SF Symbol artwork printed on the cartridge label.
    let symbolName: String

    /// Cartridge label color, also used to tint the backdrop.
    let labelColorHex: String

    /// The plastic of the cartridge shell.
    var shell: CartridgeShell = .grey

    /// The rule sets the game offers. The first one is the default.
    var modes: [GameMode] = [.standard]

    /// The IAP product that unlocks the cartridge, nil when it is free.
    var requiredProductID: String? = nil

    /// Score for the "High Scorer" achievement.
    var scoreGoal: Int = 1000

    /// Level for the level achievement.
    var levelGoal: Int = 5
}

// MARK: - Game Type

/// Identifies each available mini-game.
enum GameType: String, CaseIterable, Identifiable, Codable {
    case brickBreaker = "Brick Breaker"
    case retroRacer = "Retro Racer"
    case snake = "Snake"
    case fallingBlocks = "Falling Blocks"
    case pixelInvaders = "Pixel Invaders"
    case mineSweep = "Mine Sweep"
    case mazeMuncher = "Maze Muncher"
    case frogHop = "Frog Hop"
    case lunarHinge = "Lunar Hinge"
    case paddleDuel = "Paddle Duel"
    case astroDrift = "Astro Drift"
    case towerStack = "Tower Stack"
    
    var id: String { rawValue }

    /// The cartridge's metadata.
    var info: CartridgeInfo {
        switch self {
        case .brickBreaker:
            return CartridgeInfo(
                subtitle: String(localized: "Twelve walls, four power-ups"),
                genre: String(localized: "ARCADE", comment: "Genre printed on a cartridge label"),
                symbolName: "square.grid.3x2.fill",
                labelColorHex: "#FF6B6B",
                modes: [.standard, .daily],
                scoreGoal: 3000,
                levelGoal: 4
            )
        case .retroRacer:
            return CartridgeInfo(
                subtitle: String(localized: "8-bit highway dodge"),
                genre: String(localized: "RACING", comment: "Genre printed on a cartridge label"),
                symbolName: "car.fill",
                labelColorHex: "#4ECDC4",
                shell: .black,
                modes: [.racerDay, .racerNight, .daily],
                scoreGoal: 300,
                levelGoal: 5
            )
        case .snake:
            return CartridgeInfo(
                subtitle: String(localized: "Neon grid serpent"),
                genre: String(localized: "ACTION", comment: "Genre printed on a cartridge label"),
                symbolName: "scribble.variable",
                labelColorHex: "#45B7D1",
                shell: .glow,
                modes: [.snakeClassic, .snakeWrap, .snakeMaze, .daily],
                scoreGoal: 500,
                levelGoal: 5
            )
        case .fallingBlocks:
            return CartridgeInfo(
                subtitle: String(localized: "Block stacking puzzle"),
                genre: String(localized: "PUZZLE", comment: "Genre printed on a cartridge label"),
                symbolName: "square.stack.3d.down.right.fill",
                labelColorHex: "#F7DC6F",
                shell: .clearPurple,
                modes: [.blocksMarathon, .blocksSprint, .blocksUltra, .daily],
                scoreGoal: 5000,
                levelGoal: 5
            )
        case .pixelInvaders:
            return CartridgeInfo(
                subtitle: String(localized: "Hold the line"),
                genre: String(localized: "SHOOTER", comment: "Genre printed on a cartridge label"),
                symbolName: "sparkles",
                labelColorHex: "#C77DFF",
                shell: .smoke,
                modes: [.standard, .daily],
                scoreGoal: 3000,
                levelGoal: 3
            )
        case .mineSweep:
            return CartridgeInfo(
                subtitle: String(localized: "Flag every mine"),
                genre: String(localized: "PUZZLE", comment: "Genre printed on a cartridge label"),
                symbolName: "flag.fill",
                labelColorHex: "#A8DADC",
                shell: .grey,
                modes: [.standard, .daily],
                scoreGoal: 2000,
                levelGoal: 3
            )
        case .mazeMuncher:
            return CartridgeInfo(
                subtitle: String(localized: "Pellets, ghosts, tunnels"),
                genre: String(localized: "MAZE", comment: "Genre printed on a cartridge label"),
                symbolName: "circle.grid.cross.fill",
                labelColorHex: "#FFB703",
                shell: .black,
                modes: [.standard, .daily],
                requiredProductID: ProductIdentifiers.pro,
                scoreGoal: 5000,
                levelGoal: 3
            )
        case .frogHop:
            return CartridgeInfo(
                subtitle: String(localized: "Cross the road and river"),
                genre: String(localized: "ACTION", comment: "Genre printed on a cartridge label"),
                symbolName: "arrow.up.circle.fill",
                labelColorHex: "#80ED99",
                shell: .clearGreen,
                modes: [.standard, .daily],
                requiredProductID: ProductIdentifiers.pro,
                scoreGoal: 1000,
                levelGoal: 3
            )
        case .lunarHinge:
            return CartridgeInfo(
                subtitle: String(localized: "Fold to fire the thrusters"),
                genre: String(localized: "LANDER", comment: "Genre printed on a cartridge label"),
                symbolName: "moon.stars.fill",
                labelColorHex: "#E0E1DD",
                shell: .gold,
                modes: [.standard, .daily],
                requiredProductID: ProductIdentifiers.pro,
                scoreGoal: 1000,
                levelGoal: 4
            )
        case .paddleDuel:
            return CartridgeInfo(
                subtitle: String(localized: "Table tennis against the machine"),
                genre: String(localized: "SPORTS", comment: "Genre printed on a cartridge label"),
                symbolName: "sportscourt.fill",
                labelColorHex: "#F9844A",
                shell: .white,
                modes: [.paddleMatch, .paddleSquash, .daily],
                scoreGoal: 1500,
                levelGoal: 4
            )
        case .astroDrift:
            return CartridgeInfo(
                subtitle: String(localized: "Rocks, a ship and a lot of space"),
                genre: String(localized: "SHOOTER", comment: "Genre printed on a cartridge label"),
                symbolName: "scope",
                labelColorHex: "#6D9DC5",
                shell: .clearBlue,
                modes: [.standard, .daily],
                requiredProductID: ProductIdentifiers.pro,
                scoreGoal: 5000,
                levelGoal: 4
            )
        case .towerStack:
            return CartridgeInfo(
                subtitle: String(localized: "Drop it right on top"),
                genre: String(localized: "TIMING", comment: "Genre printed on a cartridge label"),
                symbolName: "square.stack.fill",
                labelColorHex: "#F15BB5",
                shell: .black,
                modes: [.standard, .daily],
                scoreGoal: 1000,
                levelGoal: 4
            )
        }
    }

    // MARK: Shorthands

    /// Short description for the game selection UI.
    var subtitle: String { info.subtitle }

    /// Genre printed on the cartridge.
    var genre: String { info.genre }

    /// SF Symbol artwork printed on the cartridge label.
    var symbolName: String { info.symbolName }

    /// Cartridge label color for the cover screen carousel.
    var cartridgeColorHex: String { info.labelColorHex }

    /// The rule sets the game offers. The first one is the default.
    var modes: [GameMode] { info.modes }

    /// Whether the cartridge is playable without a purchase.
    var isFree: Bool { info.requiredProductID == nil }
}

// MARK: - Haptic Event Type

/// Identifies haptic feedback patterns for different interactions.
enum HapticEventType {
    case buttonPress          // D-Pad & action buttons
    case cartridgeInsert      // Cartridge slot-in moment
    case hingeClick           // Hinge close mechanical click
    case gameEvent            // In-game collision, line clear, etc.
}

// MARK: - Game Sound

/// Sound effects a game can raise. Games queue these with
/// `PixelGameProtocol.emit(_:)`; the frame loop plays them through `AudioManager`.
enum GameSound: Equatable, Sendable {
    // Shared
    case roundStart
    case levelUp
    case gameOver
    case powerUp
    case collision

    // Brick Breaker
    case paddleBounce
    case wallBounce
    case brickBreak
    case lifeLost
    case laserShot
    case armorHit

    // Snake
    case eat
    case bonus

    // Retro Racer
    case laneChange
    case crash
    case coin

    // Falling Blocks
    case moveTick
    case rotate
    case pieceLock
    case hardDrop
    case lineClear(lines: Int)

    // Pixel Invaders
    /// One beat of the formation's four-note march, 0...3.
    case march(step: Int)
    case explosion

    // Mine Sweep
    case reveal
    case flag

    // Maze Muncher
    case chomp

    // Frog Hop
    case hop

    // Lunar Hinge
    case thrust

    /// Whether the event is big enough to also fire the `.gameEvent` haptic.
    var isImpactful: Bool {
        switch self {
        case .collision, .crash, .lifeLost, .lineClear, .gameOver, .explosion:
            return true
        default:
            return false
        }
    }
}
