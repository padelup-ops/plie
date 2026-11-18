//
// CartridgeArt.swift
// RetroCartridge
//
// Pixel-art cartridge labels. Each label is a 16×16 grid of characters
// naming palette roles, drawn in the game's own palette, so the artwork
// always matches what the game looks like:
//
//   .  empty (the palette background)   P  player       H  player highlight
//   F  pickup   X  hazard   Y  hazard alt   G  guide    W  white
//   0-9  spectrum colors (brick rows, block shapes)
//

import SwiftUI

// MARK: - Pixel art

/// A small grid of pixels, one character per pixel (see the key above).
struct PixelArt: Equatable, Sendable {
    let rows: [String]

    /// The label artwork of a cartridge.
    static func label(for game: GameType) -> PixelArt {
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

    /// The color of a pixel character in a palette, nil for an empty pixel.
    static func color(for pixel: Character, in palette: GamePalette) -> Color? {
        switch pixel {
        case "P": return palette.player
        case "H": return palette.playerHighlight
        case "F": return palette.pickup
        case "X": return palette.hazard
        case "Y": return palette.hazardAlt
        case "G": return palette.guide
        case "W": return .white
        default: return pixel.wholeNumberValue.map { palette.spectrumColor($0) }
        }
    }
}

// MARK: - Editing

extension PixelArt {
    /// Labels are square, this many pixels a side.
    static let size = 16

    /// A label with nothing drawn on it.
    static let blank = PixelArt(rows: Array(repeating: String(repeating: ".", count: size), count: size))

    /// Every character a label may use (see the key above).
    static let knownPixels = Set<Character>(".PHFXYGW0123456789")

    /// Whether this is a 16×16 grid of known pixel characters.
    var isValid: Bool {
        rows.count == Self.size && rows.allSatisfy { row in
            row.count == Self.size && row.allSatisfy(Self.knownPixels.contains)
        }
    }

    /// The pixel characters a palette can draw, in the designer's order:
    /// empty, the roles, then the palette's spectrum colors.
    static func pixels(for palette: GamePalette) -> [Character] {
        Array(".PHFXYGW") + (0..<min(10, palette.spectrum.count)).map { Character(String($0)) }
    }

    /// The character at a pixel, or empty outside the grid.
    func pixel(atX x: Int, y: Int) -> Character {
        guard rows.indices.contains(y) else { return "." }
        let row = Array(rows[y])
        return row.indices.contains(x) ? row[x] : "."
    }

    /// This art with one pixel set, and its mirror image across the middle
    /// column too when `mirrored`.
    func setting(_ pixel: Character, atX x: Int, y: Int, mirrored: Bool = false) -> PixelArt {
        var grid = rows.map(Array.init)
        guard grid.indices.contains(y), grid[y].indices.contains(x) else { return self }
        grid[y][x] = pixel
        if mirrored {
            grid[y][grid[y].count - 1 - x] = pixel
        }
        return PixelArt(rows: grid.map { String($0) })
    }

    /// This art with the area of same-colored pixels around a pixel (joined
    /// edge to edge) filled with another.
    func filling(fromX x: Int, y: Int, with pixel: Character) -> PixelArt {
        var grid = rows.map(Array.init)
        guard grid.indices.contains(y), grid[y].indices.contains(x) else { return self }
        let target = grid[y][x]
        guard target != pixel else { return self }

        var pending = [(x, y)]
        while let point = pending.popLast() {
            let (px, py) = point
            guard grid.indices.contains(py), grid[py].indices.contains(px), grid[py][px] == target else { continue }
            grid[py][px] = pixel
            pending += [(px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)]
        }
        return PixelArt(rows: grid.map { String($0) })
    }

    /// How many pixels are drawn (not empty).
    var paintedCount: Int {
        rows.joined().filter { $0 != "." }.count
    }
}

// MARK: - Pixel art view

/// Draws pixel art in a palette, pixels kept square and centered.
struct PixelArtView: View {
    let art: PixelArt
    let palette: GamePalette

    var body: some View {
        // Capturing the art makes each drawing's renderer distinct, so
        // changed art redraws (see `GameCanvasView`).
        Canvas { [art, palette] context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

            let count = CGFloat(max(art.rows.count, art.rows.map(\.count).max() ?? 0))
            guard count > 0 else { return }
            let pixel = min(size.width, size.height) / count
            let origin = CGPoint(x: (size.width - pixel * count) / 2, y: (size.height - pixel * count) / 2)

            for (y, row) in art.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = PixelArt.color(for: character, in: palette) else { continue }
                    // A hair of overlap hides seams between neighboring pixels
                    let rect = CGRect(
                        x: origin.x + CGFloat(x) * pixel,
                        y: origin.y + CGFloat(y) * pixel,
                        width: pixel + 0.3,
                        height: pixel + 0.3
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Label artwork view

/// Draws a cartridge's label in its game's palette: the player's own label
/// when they drew one, else the built-in art.
struct CartridgeArt: View {
    let game: GameType

    @Environment(AppState.self) private var appState

    var body: some View {
        PixelArtView(art: appState.labels.art(for: game), palette: .native(for: game))
    }
}

// MARK: - Artwork

extension PixelArt {
    /// Brick Breaker: a broken wall, the ball and the paddle.
    static let brickBreaker = PixelArt(rows: [
        "................",
        ".00.00.00.00.00.",
        ".11.11.11.11.11.",
        ".22.22....22.22.",
        ".33.......33.33.",
        ".44..........44.",
        "................",
        "................",
        "........HH......",
        "........HH......",
        "................",
        "................",
        "................",
        "................",
        ".....PPPPPP.....",
        "................"
    ])

    /// Retro Racer: two cars ahead of the player on a three-lane road.
    static let retroRacer = PixelArt(rows: [
        ".....G....G.....",
        ".XXX.G....G.....",
        ".XWX............",
        ".XXX............",
        ".XXX.G....G.....",
        ".....G....G.....",
        "............YYY.",
        "............YWY.",
        ".....G....G.YYY.",
        ".....G....G.YYY.",
        "................",
        "......PPP.......",
        ".....GPHP.G.....",
        ".....GPPP.G.....",
        "......PPP.......",
        "................"
    ])

    /// Snake: a winding snake heading for an apple.
    static let snake = PixelArt(rows: [
        "................",
        ".............F..",
        "............XX..",
        "............XX..",
        "................",
        "....PPPPPPPHH...",
        "....P...........",
        "....P...........",
        "....PPPPP.......",
        "........P.......",
        "........P.......",
        "........P.......",
        "...PPPPPP.......",
        "................",
        "................",
        "................"
    ])

    /// Falling Blocks: a T piece dropping onto a stack.
    static let fallingBlocks = PixelArt(rows: [
        "................",
        "................",
        "......222.......",
        ".......2........",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "0...............",
        "0.........11.6..",
        "0.33......11.655",
        "033.11.2.44.6665",
        "000011222.446665"
    ])

    /// Pixel Invaders: two invaders over a shield, a shot rising from the cannon.
    static let pixelInvaders = PixelArt(rows: [
        "................",
        "..0..0..........",
        "...00...........",
        "..0000....1..1..",
        ".00..00....11...",
        "00000000..1111..",
        "0.0..0.0.11..11.",
        "........11111111",
        "........1.1..1.1",
        "................",
        "...........H....",
        "...........H....",
        "..XXXX..........",
        "..X..X.....P....",
        "..........PPP...",
        ".........PPPPP.."
    ])

    /// Mine Sweep: tiles with numbers, two flags and a mine.
    static let mineSweep = PixelArt(rows: [
        "GGG.GGG.....GGG.",
        "GGG.GGG..0..GGG.",
        "GGG.GGG.....GGG.",
        "................",
        "GXG.........GGG.",
        "GXX..1...0..GGG.",
        "GWG.........GGG.",
        "................",
        ".............Y..",
        ".0...0......YYY.",
        ".............Y..",
        "................",
        "GGG.GXG.....GGG.",
        "GGG.GXX..0..GGG.",
        "GGG.GWG.....GGG.",
        "................"
    ])

    /// Maze Muncher: the muncher, a trail of pellets and a ghost.
    static let mazeMuncher = PixelArt(rows: [
        "XXXXXXXXXXXXXXXX",
        "X..............X",
        "X.........000..X",
        "X........00000.X",
        "X........0H0H0.X",
        "X........00000.X",
        "X..PPP...0.0.0.X",
        "X.PPPP.........X",
        "X.PPP...F.F.F..X",
        "X.PPPP.........X",
        "X..PPX.........X",
        "X....X..XXXXX..X",
        "X....X.........X",
        "X....X.........X",
        "X..............X",
        "XXXXXXXXXXXXXXXX"
    ])

    /// Frog Hop: logs on the river, cars on the road, the frog at the start.
    static let frogHop = PixelArt(rows: [
        "................",
        "GGGGGGGGGGGGGGGG",
        "GGFFFFFFGGGGGGGG",
        "GGGGGGGGGGGGGGGG",
        "GGGGGGGGGFFFFFGG",
        "GGGGGGGGGGGGGGGG",
        "................",
        "................",
        ".XXXX...........",
        ".XWXX...........",
        "..........YYY...",
        "..........YWY...",
        "......H..H......",
        ".......PP.......",
        "......PPPP......",
        "......P..P......"
    ])

    /// Lunar Hinge: the lander firing over its pad among the stars.
    static let lunarHinge = PixelArt(rows: [
        "........H.......",
        ".H..............",
        ".............H..",
        "........PP......",
        "....H..PPPP.....",
        ".......PHHP.....",
        "......PPPPPP..H.",
        "......P....P....",
        "........YY......",
        ".........Y......",
        "...........G....",
        ".GG.......GGG...",
        "GGGG..FFFFGGGG..",
        "GGGGGGGGGGGGGGG.",
        "GGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGG"
    ])

    /// Paddle Duel: the ball's path from the computer's paddle to yours.
    static let paddleDuel = PixelArt(rows: [
        "................",
        "...XXXXXX.......",
        "................",
        "..........F.....",
        "...........F....",
        "............F...",
        "G.G.G.G.G.G.G.G.",
        "............F...",
        "...........F....",
        "..........F.....",
        ".........HH.....",
        ".........HH.....",
        "................",
        "................",
        ".......PPPPPP...",
        "................"
    ])

    /// Astro Drift: the ship firing at a big rock, a small one drifting by.
    static let astroDrift = PixelArt(rows: [
        "..G.........G...",
        ".....XXXX.......",
        "....X....X.....G",
        "....X.....X.....",
        "....X....X......",
        ".....XXXX.......",
        "..........H.....",
        "...G.......H....",
        "........P.......",
        ".......PPP......",
        "......PP.PP.....",
        "......P...P.....",
        ".......YYY....G.",
        ".G.........XX...",
        "..........X..X..",
        "...........XX..."
    ])

    /// Tower Stack: a narrowing tower, the next block sliding in, and a
    /// cut-off piece falling away.
    static let towerStack = PixelArt(rows: [
        "................",
        "..PPPPPP........",
        "................",
        "...........XX...",
        ".....44444......",
        ".....33333..XX..",
        "....333333......",
        "....2222222.....",
        "...22222222.....",
        "...11111111.....",
        "..111111111.....",
        "..0000000000....",
        ".00000000000....",
        ".GGGGGGGGGGGG...",
        "GGGGGGGGGGGGGGGG",
        "GGGGGGGGGGGGGGGG"
    ])
}
