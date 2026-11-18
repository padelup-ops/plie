// MineSweepGame.swift
// RetroCartridge
//
// Mine Sweep: a calm puzzle on a 10 × 9 board. The D-Pad moves the cursor,
// A reveals and B plants a flag. The first reveal is always safe, empty
// areas open up by themselves, and each cleared board brings a new one
// with more mines.

import SwiftUI

final class MineSweepGame: PixelGameProtocol {
    var gameType: GameType = .mineSweep
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .mineSweep
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    let columns = 10
    let rows = 9

    /// Mines on the board; empty until the first reveal, so it's never a mine.
    var mines: Set<Cell> = []
    var revealed: Set<Cell> = []
    var flagged: Set<Cell> = []
    var cursor = Cell(x: 4, y: 4)
    /// The mine that went off, shown after a loss.
    var detonated: Cell?
    /// Seconds before the next board appears after clearing one.
    var nextBoardTimer: TimeInterval = 0

    /// Mines on the current board.
    var mineCount: Int { min(10 + (level - 1) * 3, 30) }

    /// How long the cursor has blinked, for its animation.
    private var clock: TimeInterval = 0

    init() {
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        clock += deltaTime
        guard gameState == .playing else { return }

        if nextBoardTimer > 0 {
            nextBoardTimer -= deltaTime
            if nextBoardTimer <= 0 {
                newBoard()
            }
        }
    }

    // MARK: - Rules

    private func isInside(_ cell: Cell) -> Bool {
        cell.x >= 0 && cell.x < columns && cell.y >= 0 && cell.y < rows
    }

    func neighbors(of cell: Cell) -> [Cell] {
        var result: [Cell] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let neighbor = Cell(x: cell.x + dx, y: cell.y + dy)
                if isInside(neighbor) { result.append(neighbor) }
            }
        }
        return result
    }

    /// How many mines touch a cell.
    func adjacentMines(_ cell: Cell) -> Int {
        neighbors(of: cell).filter { mines.contains($0) }.count
    }

    /// Lays the mines, keeping the first revealed cell and its neighbors clear.
    private func layMines(avoiding start: Cell) {
        let keepClear = Set(neighbors(of: start) + [start])
        var candidates: [Cell] = []
        for y in 0..<rows {
            for x in 0..<columns where !keepClear.contains(Cell(x: x, y: y)) {
                candidates.append(Cell(x: x, y: y))
            }
        }
        candidates.shuffle(using: &rng)
        mines = Set(candidates.prefix(mineCount))
    }

    /// Reveals a cell, opening its whole empty area.
    func reveal(_ cell: Cell) {
        guard gameState == .playing, nextBoardTimer <= 0,
              !revealed.contains(cell), !flagged.contains(cell) else { return }

        if mines.isEmpty {
            layMines(avoiding: cell)
        }

        if mines.contains(cell) {
            detonated = cell
            revealed.formUnion(mines)
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.crash)
            emit(.gameOver)
            return
        }

        // Flood-fill the area around empty cells
        var queue = [cell]
        var opened = 0
        while let current = queue.popLast() {
            guard !revealed.contains(current), !flagged.contains(current) else { continue }
            revealed.insert(current)
            opened += 1
            if adjacentMines(current) == 0 {
                queue.append(contentsOf: neighbors(of: current).filter { !revealed.contains($0) })
            }
        }
        score += opened * 5 * level
        emit(.reveal)

        if revealed.count == columns * rows - mines.count {
            score += 200 * level
            level += 1
            flagged = mines
            nextBoardTimer = 1.5
            emit(.levelUp)
        }
    }

    func toggleFlag(_ cell: Cell) {
        guard gameState == .playing, nextBoardTimer <= 0, !revealed.contains(cell) else { return }
        if flagged.contains(cell) {
            flagged.remove(cell)
        } else {
            flagged.insert(cell)
        }
        emit(.flag)
    }

    private func newBoard() {
        mines = []
        revealed = []
        flagged = []
        detonated = nil
        nextBoardTimer = 0
    }

    private func moveCursor(dx: Int, dy: Int) {
        let target = Cell(x: cursor.x + dx, y: cursor.y + dy)
        guard isInside(target) else { return }
        cursor = target
        emit(.moveTick)
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        let cellSize = min(size.width / Double(columns), size.height / Double(rows))
        let originX = (size.width - cellSize * Double(columns)) / 2
        let originY = (size.height - cellSize * Double(rows)) / 2
        let isLost: Bool
        if case .gameOver = gameState { isLost = true } else { isLost = false }

        for y in 0..<rows {
            for x in 0..<columns {
                let cell = Cell(x: x, y: y)
                let frame = CGRect(x: originX + Double(x) * cellSize, y: originY + Double(y) * cellSize, width: cellSize, height: cellSize)
                let inner = frame.insetBy(dx: 1, dy: 1)

                if revealed.contains(cell) {
                    context.fill(Path(inner), with: .color(palette.guide.opacity(0.35)))
                    if mines.contains(cell) {
                        drawMine(in: inner, exploded: cell == detonated, context: &context)
                    } else {
                        let count = adjacentMines(cell)
                        if count > 0 {
                            context.draw(
                                Text("\(count)")
                                    .font(.pixel(cellSize * 0.6))
                                    .foregroundStyle(palette.spectrumColor(count - 1)),
                                at: CGPoint(x: frame.midX, y: frame.midY)
                            )
                        }
                    }
                } else {
                    // A raised tile: lit top-left edge, shaded bottom-right
                    context.fill(Path(inner), with: .color(palette.guide))
                    context.fill(Path(CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 2)), with: .color(palette.playerHighlight.opacity(0.35)))
                    context.fill(Path(CGRect(x: inner.minX, y: inner.minY, width: 2, height: inner.height)), with: .color(palette.playerHighlight.opacity(0.35)))
                    if flagged.contains(cell) {
                        drawFlag(in: inner, context: &context)
                    }
                }
            }
        }

        // Cursor
        if !isLost {
            let frame = CGRect(x: originX + Double(cursor.x) * cellSize, y: originY + Double(cursor.y) * cellSize, width: cellSize, height: cellSize)
            let pulse = 0.6 + 0.4 * sin(clock * 6)
            context.stroke(Path(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(palette.player.opacity(pulse)), lineWidth: 2.5)
        }
    }

    private func drawMine(in frame: CGRect, exploded: Bool, context: inout GraphicsContext) {
        if exploded {
            context.fill(Path(frame), with: .color(palette.hazard.opacity(0.6)))
        }
        let body = frame.insetBy(dx: frame.width * 0.28, dy: frame.height * 0.28)
        var spikes = Path()
        spikes.move(to: CGPoint(x: body.midX, y: frame.minY + frame.height * 0.15))
        spikes.addLine(to: CGPoint(x: body.midX, y: frame.maxY - frame.height * 0.15))
        spikes.move(to: CGPoint(x: frame.minX + frame.width * 0.15, y: body.midY))
        spikes.addLine(to: CGPoint(x: frame.maxX - frame.width * 0.15, y: body.midY))
        context.stroke(spikes, with: .color(palette.hazardAlt), lineWidth: 1.5)
        context.fill(Path(ellipseIn: body), with: .color(palette.hazardAlt))
    }

    private func drawFlag(in frame: CGRect, context: inout GraphicsContext) {
        let poleX = frame.minX + frame.width * 0.38
        context.fill(Path(CGRect(x: poleX, y: frame.minY + frame.height * 0.2, width: 1.5, height: frame.height * 0.6)), with: .color(palette.playerHighlight))
        var flag = Path()
        flag.move(to: CGPoint(x: poleX + 1.5, y: frame.minY + frame.height * 0.2))
        flag.addLine(to: CGPoint(x: frame.maxX - frame.width * 0.2, y: frame.minY + frame.height * 0.35))
        flag.addLine(to: CGPoint(x: poleX + 1.5, y: frame.minY + frame.height * 0.5))
        flag.closeSubpath()
        context.fill(flag, with: .color(palette.hazard))
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch gameState {
        case .menu, .gameOver:
            if action == .buttonAPressed {
                reset()
                gameState = .playing
                emit(.roundStart)
            }
        case .paused:
            if action == .buttonStartPressed { resume() }
        case .playing:
            switch action {
            case .dpadUpPressed: moveCursor(dx: 0, dy: -1)
            case .dpadDownPressed: moveCursor(dx: 0, dy: 1)
            case .dpadLeftPressed: moveCursor(dx: -1, dy: 0)
            case .dpadRightPressed: moveCursor(dx: 1, dy: 0)
            case .buttonAPressed: reveal(cursor)
            case .buttonBPressed: toggleFlag(cursor)
            case .buttonStartPressed: pause()
            default: break
            }
        }
    }

    func reset() {
        rng = makeRNG()
        gameState = .menu
        pendingSounds.removeAll()
        score = 0
        level = 1
        cursor = Cell(x: columns / 2 - 1, y: rows / 2)
        newBoard()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Mine Sweep's native palette.
    static let mineSweep = GamePalette(
        background: Color(hex: "#101418"),
        guide: Color(hex: "#5C6B7A"),        // hidden tiles
        player: Color(hex: "#FFD166"),       // cursor
        playerHighlight: .white,             // tile bevel, flag pole
        pickup: Color(hex: "#06D6A0"),
        pickupAlt: Color(hex: "#FFD166"),
        hazard: Color(hex: "#EF476F"),       // flags, explosion
        hazardAlt: Color(hex: "#E8E8E8"),    // mines
        outline: .black,
        spectrum: [ // numbers 1-8
            Color(hex: "#4CC9F0"), Color(hex: "#06D6A0"), Color(hex: "#EF476F"), Color(hex: "#9B5DE5"),
            Color(hex: "#F77F00"), Color(hex: "#00B4D8"), Color(hex: "#E8E8E8"), Color(hex: "#ADB5BD")
        ]
    )
}
