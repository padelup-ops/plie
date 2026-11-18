// TowerStackGame.swift
// RetroCartridge
//
// Tower Stack: a block slides back and forth above the tower; press A (or
// ▼) to drop it. Whatever hangs over the edge is cut off and falls away, so
// the tower narrows with every miss. Landing a block exactly on the one
// below is a perfect drop: nothing is cut, and a streak of them grows the
// block back. Every ten blocks the slider speeds up; a block that misses
// the tower completely ends the round.

import SwiftUI

final class TowerStackGame: PixelGameProtocol {
    var gameType: GameType = .towerStack
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .towerStack
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    /// A placed block: its left edge and width, as shares of the field width.
    struct Block: Equatable {
        var x: Double
        var width: Double
    }

    /// A cut-off piece falling away.
    struct Piece {
        var x: Double
        var width: Double
        /// The row it fell from.
        var row: Int
        /// How far it has fallen, in rows.
        var drop: Double = 0
        var speed: Double = 0
    }

    // MARK: - Tuning

    /// Width of the first block.
    let baseWidth = 0.5
    /// How close to the block below counts as a perfect drop.
    let perfectTolerance = 0.015
    /// Rows shown on screen.
    let visibleRows = 14
    /// Blocks per level.
    let blocksPerLevel = 10
    /// Width a streak of perfect drops grows back, per drop from the third.
    let regrowth = 0.02

    // MARK: - State

    /// The tower, bottom first. The first block is the base.
    var blocks: [Block] = []
    /// The sliding block's left edge.
    var sliderX = 0.0
    var sliderDirection = 1.0
    /// Field widths per second.
    var sliderSpeed = 0.45
    var pieces: [Piece] = []
    /// Perfect drops in a row.
    var streak = 0
    /// Time since the last perfect drop, for its flash.
    var sincePerfect: TimeInterval = 10
    /// Where the camera is, in rows from the bottom, easing toward the top.
    var cameraRow = 0.0

    /// The block on top of the tower.
    var top: Block { blocks.last ?? Block(x: 0.25, width: baseWidth) }

    /// Blocks placed on the base.
    var height: Int { max(0, blocks.count - 1) }

    init() {
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        for index in pieces.indices {
            pieces[index].speed += 30 * deltaTime
            pieces[index].drop += pieces[index].speed * deltaTime
        }
        pieces.removeAll { $0.drop > Double(visibleRows + 4) }
        cameraRow += (targetCameraRow - cameraRow) * min(1, deltaTime * 6)

        guard gameState == .playing else { return }
        sincePerfect += deltaTime

        sliderX += sliderDirection * sliderSpeed * deltaTime
        let maxX = 1 - top.width
        if sliderX > maxX {
            sliderX = maxX
            sliderDirection = -1
        } else if sliderX < 0 {
            sliderX = 0
            sliderDirection = 1
        }
    }

    /// Keeps the top of the tower in the lower part of the screen.
    private var targetCameraRow: Double {
        Double(max(0, blocks.count - (visibleRows - 5)))
    }

    // MARK: - Rules

    private func drop() {
        guard gameState == .playing else { return }
        let below = top
        let left = max(sliderX, below.x)
        let right = min(sliderX + below.width, below.x + below.width)
        let row = blocks.count

        guard right - left > 0.001 else {
            // Missed the tower: the whole block falls
            pieces.append(Piece(x: sliderX, width: below.width, row: row))
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.collision)
            emit(.gameOver)
            return
        }

        if abs(sliderX - below.x) <= perfectTolerance {
            // Perfect: snap onto the block below, and grow back on a streak
            streak += 1
            sincePerfect = 0
            var width = below.width
            if streak >= 3 {
                width = min(baseWidth, width + regrowth)
            }
            let x = min(1 - width, max(0, below.x - (width - below.width) / 2))
            blocks.append(Block(x: x, width: width))
            score += 10 * level + 5 * streak
            emit(.powerUp)
        } else {
            streak = 0
            blocks.append(Block(x: left, width: right - left))
            // The overhang falls away
            if sliderX < left {
                pieces.append(Piece(x: sliderX, width: left - sliderX, row: row))
            }
            if sliderX + below.width > right {
                pieces.append(Piece(x: right, width: sliderX + below.width - right, row: row))
            }
            score += 10 * level
            emit(.pieceLock)
        }

        if height % blocksPerLevel == 0 {
            level += 1
            emit(.levelUp)
        }
        startSlider()
    }

    /// Sends the next block in from one side, a little faster every level.
    private func startSlider() {
        let fromLeft = Bool.random(using: &rng)
        sliderDirection = fromLeft ? 1 : -1
        sliderX = fromLeft ? 0 : 1 - top.width
        let pace = min(1.3, 0.45 + 0.08 * Double(level - 1))
        sliderSpeed = pace * Double.random(in: 0.95...1.05, using: &rng)
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        let rowHeight = size.height / Double(visibleRows)
        let w = size.width

        /// The screen rectangle of a block in a row (0 is the base).
        func rect(x: Double, width: Double, row: Double) -> CGRect {
            CGRect(x: x * w, y: size.height - (row - cameraRow + 1) * rowHeight, width: width * w, height: rowHeight)
        }

        // Guide lines where the tower started
        let base = blocks.first ?? top
        for edge in [base.x, base.x + base.width] {
            var line = Path()
            line.move(to: CGPoint(x: edge * w, y: 0))
            line.addLine(to: CGPoint(x: edge * w, y: size.height))
            context.stroke(line, with: .color(palette.guide), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }

        // The tower, in the spectrum's colors floor by floor
        for (row, block) in blocks.enumerated() {
            let frame = rect(x: block.x, width: block.width, row: Double(row))
            guard frame.maxY >= 0, frame.minY <= size.height else { continue }
            drawBlock(frame, color: row == 0 ? palette.guide : palette.spectrumColor(row - 1), context: &context)
        }

        // A perfect drop flashes the top block
        if sincePerfect < 0.3, let last = blocks.last {
            let frame = rect(x: last.x, width: last.width, row: Double(blocks.count - 1))
            context.fill(Path(frame.insetBy(dx: -2, dy: -2)), with: .color(palette.playerHighlight.opacity(0.6 * (1 - sincePerfect / 0.3))))
        }

        // Falling pieces
        for piece in pieces {
            let frame = rect(x: piece.x, width: piece.width, row: Double(piece.row) - piece.drop)
            drawBlock(frame, color: palette.hazard.opacity(max(0, 1 - piece.drop / 8)), context: &context)
        }

        // The sliding block
        if gameState == .playing {
            let frame = rect(x: sliderX, width: top.width, row: Double(blocks.count))
            drawBlock(frame, color: palette.player, context: &context)
        }

        // Streak pips
        if streak > 1 {
            let pip = rowHeight * 0.3
            for i in 0..<min(streak, 10) {
                let dot = CGRect(x: w - pip * 1.8 * Double(i + 1), y: pip, width: pip, height: pip)
                context.fill(Path(ellipseIn: dot), with: .color(palette.pickupAlt))
            }
        }
    }

    private func drawBlock(_ frame: CGRect, color: Color, context: inout GraphicsContext) {
        context.fill(Path(frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(color))
        // A lit top edge and a dark outline, like a molded brick
        context.fill(Path(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(1, frame.height * 0.15))), with: .color(.white.opacity(0.25)))
        context.stroke(Path(frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(palette.outline), lineWidth: 1)
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .buttonAPressed, .dpadDownPressed:
            switch gameState {
            case .menu, .gameOver:
                guard action == .buttonAPressed else { return }
                reset()
                gameState = .playing
                emit(.roundStart)
            case .playing:
                drop()
            case .paused:
                break
            }
        case .buttonStartPressed:
            if gameState == .playing { pause() }
            else if gameState == .paused { resume() }
        default:
            break
        }
    }

    func reset() {
        rng = makeRNG()
        gameState = .menu
        pendingSounds.removeAll()
        score = 0
        level = 1
        streak = 0
        sincePerfect = 10
        pieces.removeAll()
        blocks = [Block(x: (1 - baseWidth) / 2, width: baseWidth)]
        cameraRow = 0
        startSlider()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Tower Stack's native palette.
    static let towerStack = GamePalette(
        background: Color(hex: "#1A1423"),
        guide: Color(hex: "#3D2E57"),          // base, guide lines
        player: Color(hex: "#F15BB5"),         // sliding block
        playerHighlight: .white,               // perfect flash
        pickup: Color(hex: "#00F5D4"),
        pickupAlt: Color(hex: "#FEE440"),      // streak pips
        hazard: Color(hex: "#FF006E"),         // falling pieces
        hazardAlt: Color(hex: "#9B5DE5"),
        outline: Color(hex: "#0D0A12"),
        spectrum: [Color(hex: "#FEE440"), Color(hex: "#00BBF9"), Color(hex: "#00F5D4"), Color(hex: "#9B5DE5"), Color(hex: "#F15BB5")]
    )
}
