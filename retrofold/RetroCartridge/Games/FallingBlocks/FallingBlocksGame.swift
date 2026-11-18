// FallingBlocksGame.swift
// RetroCartridge
//
// Falling Blocks in three modes: Marathon (endless, faster every ten
// lines), Sprint (clear forty lines; time left becomes bonus points) and
// Ultra (score as much as possible in two minutes). The next three pieces
// are shown beside the well, the lines and time on the other side.

import SwiftUI

/// Falling Blocks (Tetris-style) game implementation.
final class FallingBlocksGame: PixelGameProtocol {
    var gameType: GameType = .fallingBlocks
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .fallingBlocks
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []
    
    let cols = 10
    let rows = 20
    
    /// Locked cells, holding the spectrum index of the piece that filled them.
    var grid: [[Int?]] = Array(repeating: Array(repeating: nil, count: 10), count: 20)
    
    struct Tetromino {
        var shape: [[Int]]
        /// Index into the palette's spectrum, one per piece kind.
        var colorIndex: Int
        var x: Int
        var y: Int
        
        mutating func rotateClockwise() {
            let s = shape.count
            var newShape = Array(repeating: Array(repeating: 0, count: s), count: s)
            for i in 0..<s {
                for j in 0..<s {
                    newShape[j][s - 1 - i] = shape[i][j]
                }
            }
            shape = newShape
        }
        
        mutating func rotateCounterClockwise() {
            let s = shape.count
            var newShape = Array(repeating: Array(repeating: 0, count: s), count: s)
            for i in 0..<s {
                for j in 0..<s {
                    newShape[s - 1 - j][i] = shape[i][j]
                }
            }
            shape = newShape
        }
    }
    
    /// Piece shapes; each one's index is also its spectrum color index.
    let pieceShapes: [[[Int]]] = [
        [[0,0,0,0], [1,1,1,1], [0,0,0,0], [0,0,0,0]], // I
        [[1,1], [1,1]], // O
        [[0,1,0], [1,1,1], [0,0,0]], // T
        [[0,1,1], [1,1,0], [0,0,0]], // S
        [[1,1,0], [0,1,1], [0,0,0]], // Z
        [[0,0,1], [1,1,1], [0,0,0]], // L
        [[1,0,0], [1,1,1], [0,0,0]] // J
    ]
    
    var currentPiece: Tetromino!
    /// The pieces after the current one, next first.
    var upcoming: [Tetromino] = []
    /// How many upcoming pieces are shown.
    let previewCount = 3
    
    var dropTimer: TimeInterval = 0
    var dropInterval: TimeInterval = 0.8
    var linesClearedTotal = 0

    /// Seconds played this round.
    var elapsed: TimeInterval = 0

    /// Lines to clear in Sprint.
    let sprintLines = 40
    /// Length of an Ultra round, in seconds.
    let ultraDuration: TimeInterval = 120
    /// Seconds in which a Sprint still earns a time bonus.
    let sprintBonusWindow: TimeInterval = 240
    
    init() {
        reset()
    }
    
    func spawnPiece() {
        while upcoming.count <= previewCount {
            upcoming.append(randomPiece())
        }
        currentPiece = upcoming.removeFirst()
        
        if checkCollision(piece: currentPiece, dx: 0, dy: 0) {
            die()
        }
    }
    
    /// A random piece at the top center of the board.
    func randomPiece() -> Tetromino {
        let kind = Int.random(in: 0..<pieceShapes.count, using: &rng)
        let shape = pieceShapes[kind]
        return Tetromino(shape: shape, colorIndex: kind, x: cols/2 - shape.count/2, y: 0)
    }
    
    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        elapsed += deltaTime
        if mode == .blocksUltra && elapsed >= ultraDuration {
            finish()
            return
        }
        
        dropTimer += deltaTime
        if dropTimer >= dropInterval {
            dropTimer = 0
            if !checkCollision(piece: currentPiece, dx: 0, dy: 1) {
                currentPiece.y += 1
            } else {
                lockPiece()
            }
        }
    }
    
    /// Merges the current piece into the grid, clears lines and spawns the next piece.
    /// - Parameter sound: The landing sound; a hard drop plays its own slam.
    func lockPiece(sound: GameSound = .pieceLock) {
        emit(sound)
        for i in 0..<currentPiece.shape.count {
            for j in 0..<currentPiece.shape[i].count {
                if currentPiece.shape[i][j] == 1 {
                    let r = currentPiece.y + i
                    let c = currentPiece.x + j
                    if r >= 0 && r < rows && c >= 0 && c < cols {
                        grid[r][c] = currentPiece.colorIndex
                    }
                }
            }
        }
        
        clearLines()
        // A completed Sprint ends here, without a next piece
        guard gameState == .playing else { return }
        spawnPiece()
    }
    
    func clearLines() {
        var linesCleared = 0
        for r in (0..<rows).reversed() {
            if grid[r].allSatisfy({ $0 != nil }) {
                grid.remove(at: r)
                grid.insert(Array(repeating: nil, count: cols), at: 0)
                linesCleared += 1
            }
        }
        
        if linesCleared > 0 {
            linesClearedTotal += linesCleared
            emit(.lineClear(lines: linesCleared))
            let newLevel = 1 + linesClearedTotal / 10
            if newLevel > level {
                emit(.levelUp)
            }
            level = newLevel
            dropInterval = max(0.1, 0.8 - Double(level - 1) * 0.05)
            
            switch linesCleared {
            case 1: score += 100 * level
            case 2: score += 300 * level
            case 3: score += 500 * level
            case 4: score += 800 * level
            default: break
            }

            if mode == .blocksSprint && linesClearedTotal >= sprintLines {
                // Every second left in the bonus window is worth 50 points
                score += max(0, Int((sprintBonusWindow - elapsed) * 50))
                finish()
            }
        }
    }

    /// Ends a Sprint or Ultra round that was completed rather than lost.
    func finish() {
        if score > highScore { highScore = score }
        gameState = .gameOver(score: score)
        emit(.levelUp)
    }
    
    func checkCollision(piece: Tetromino, dx: Int, dy: Int) -> Bool {
        for i in 0..<piece.shape.count {
            for j in 0..<piece.shape[i].count {
                if piece.shape[i][j] == 1 {
                    let r = piece.y + i + dy
                    let c = piece.x + j + dx
                    
                    if c < 0 || c >= cols || r >= rows { return true }
                    if r >= 0 && grid[r][c] != nil { return true }
                }
            }
        }
        return false
    }
    
    func getGhostPiece() -> Tetromino {
        var ghost = currentPiece!
        while !checkCollision(piece: ghost, dx: 0, dy: 1) {
            ghost.y += 1
        }
        return ghost
    }
    
    func die() {
        if score > highScore { highScore = score }
        gameState = .gameOver(score: score)
        emit(.gameOver)
    }
    
    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        
        if gameState == .menu { return }
        
        let cellW = size.width / Double(cols)
        let cellH = size.height / Double(rows)
        let cellSize = min(cellW, cellH)
        
        let offsetX = (size.width - Double(cols) * cellSize) / 2
        let offsetY = (size.height - Double(rows) * cellSize) / 2
        
        // Draw grid
        for r in 0..<rows {
            for c in 0..<cols {
                let rect = CGRect(x: offsetX + Double(c) * cellSize, y: offsetY + Double(r) * cellSize, width: cellSize, height: cellSize)
                if let colorIndex = grid[r][c] {
                    context.fill(Path(rect), with: .color(palette.spectrumColor(colorIndex)))
                    context.stroke(Path(rect), with: .color(palette.outline), lineWidth: 1)
                }
            }
        }
        
        guard currentPiece != nil else { return }
        
        // Ghost piece
        let ghost = getGhostPiece()
        for i in 0..<ghost.shape.count {
            for j in 0..<ghost.shape[i].count {
                if ghost.shape[i][j] == 1 {
                    let rect = CGRect(x: offsetX + Double(ghost.x + j) * cellSize, y: offsetY + Double(ghost.y + i) * cellSize, width: cellSize, height: cellSize)
                    context.stroke(Path(rect), with: .color(palette.spectrumColor(ghost.colorIndex).opacity(0.5)), lineWidth: 2)
                }
            }
        }
        
        // Current piece
        for i in 0..<currentPiece.shape.count {
            for j in 0..<currentPiece.shape[i].count {
                if currentPiece.shape[i][j] == 1 {
                    let rect = CGRect(x: offsetX + Double(currentPiece.x + j) * cellSize, y: offsetY + Double(currentPiece.y + i) * cellSize, width: cellSize, height: cellSize)
                    context.fill(Path(rect), with: .color(palette.spectrumColor(currentPiece.colorIndex)))
                    context.stroke(Path(rect), with: .color(palette.outline), lineWidth: 1)
                }
            }
        }

        // The well's outline
        let well = CGRect(x: offsetX, y: offsetY, width: Double(cols) * cellSize, height: Double(rows) * cellSize)
        context.stroke(Path(well), with: .color(palette.playerHighlight.opacity(0.25)), lineWidth: 1)

        // Side panels, when the screen is wide enough
        guard offsetX > cellSize * 3.5 else { return }
        drawPreview(in: &context, left: well.maxX + cellSize * 0.8, top: offsetY + cellSize, cellSize: cellSize)
        drawStats(in: &context, right: well.minX - cellSize * 0.8, top: offsetY + cellSize, cellSize: cellSize)
    }

    /// The next pieces, smaller, stacked beside the well.
    private func drawPreview(in context: inout GraphicsContext, left: Double, top: Double, cellSize: Double) {
        context.draw(label(String(localized: "NEXT", comment: "Falling Blocks HUD: the next piece"), size: cellSize * 0.7), at: CGPoint(x: left, y: top), anchor: .leading)

        let mini = cellSize * 0.6
        var y = top + cellSize
        for piece in upcoming.prefix(previewCount) {
            for i in 0..<piece.shape.count {
                for j in 0..<piece.shape[i].count where piece.shape[i][j] == 1 {
                    let rect = CGRect(x: left + Double(j) * mini, y: y + Double(i) * mini, width: mini, height: mini)
                    context.fill(Path(rect), with: .color(palette.spectrumColor(piece.colorIndex)))
                    context.stroke(Path(rect), with: .color(palette.outline), lineWidth: 1)
                }
            }
            y += mini * 3.2
        }
    }

    /// Lines and time, aligned to the left edge of the well.
    private func drawStats(in context: inout GraphicsContext, right: Double, top: Double, cellSize: Double) {
        let lines = mode == .blocksSprint ? "\(min(linesClearedTotal, sprintLines))/\(sprintLines)" : "\(linesClearedTotal)"
        let seconds = mode == .blocksUltra ? max(0, ultraDuration - elapsed) : elapsed
        let time = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)

        let rows: [(String, String)] = [
            (String(localized: "LINES", comment: "Falling Blocks HUD"), lines),
            (String(localized: "TIME", comment: "Falling Blocks HUD"), time)
        ]
        var y = top
        for (title, value) in rows {
            context.draw(label(title, size: cellSize * 0.6), at: CGPoint(x: right, y: y), anchor: .trailing)
            context.draw(label(value, size: cellSize * 0.85, bright: true), at: CGPoint(x: right, y: y + cellSize * 0.9), anchor: .trailing)
            y += cellSize * 2.6
        }
    }

    private func label(_ text: String, size: Double, bright: Bool = false) -> Text {
        Text(text)
            .font(.pixel(size))
            .foregroundStyle(palette.playerHighlight.opacity(bright ? 0.95 : 0.55))
    }
    
    func handleInput(action: GameInputAction) {
        guard gameState == .playing else {
            if action == .buttonStartPressed {
                resume()
                return
            }
            if action == .buttonAPressed {
                switch gameState {
                case .menu, .gameOver:
                    reset()
                    gameState = .playing
                    emit(.roundStart)
                default: break
                }
            }
            return
        }
        
        switch action {
        case .dpadLeftPressed:
            if !checkCollision(piece: currentPiece, dx: -1, dy: 0) {
                currentPiece.x -= 1
                emit(.moveTick)
            }
        case .dpadRightPressed:
            if !checkCollision(piece: currentPiece, dx: 1, dy: 0) {
                currentPiece.x += 1
                emit(.moveTick)
            }
        case .dpadDownPressed:
            if !checkCollision(piece: currentPiece, dx: 0, dy: 1) {
                currentPiece.y += 1
                score += 1
            }
        case .dpadUpPressed:
            while !checkCollision(piece: currentPiece, dx: 0, dy: 1) {
                currentPiece.y += 1
                score += 2
            }
            lockPiece(sound: .hardDrop)
        case .buttonAPressed:
            var temp = currentPiece!
            temp.rotateClockwise()
            if !checkCollision(piece: temp, dx: 0, dy: 0) {
                currentPiece = temp
                emit(.rotate)
            }
        case .buttonBPressed:
            var temp = currentPiece!
            temp.rotateCounterClockwise()
            if !checkCollision(piece: temp, dx: 0, dy: 0) {
                currentPiece = temp
                emit(.rotate)
            }
        case .buttonStartPressed:
            pause()
        default: break
        }
    }
    
    func pause() {
        if gameState == .playing { gameState = .paused }
    }
    
    func resume() {
        if gameState == .paused { gameState = .playing }
    }
    
    func reset() {
        rng = makeRNG()
        gameState = .menu
        pendingSounds.removeAll()
        score = 0
        level = 1
        linesClearedTotal = 0
        dropInterval = 0.8
        elapsed = 0
        grid = Array(repeating: Array(repeating: nil, count: 10), count: 20)
        currentPiece = nil
        upcoming = []
        spawnPiece()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Falling Blocks's native palette.
    static let fallingBlocks = GamePalette(
        background: .black,
        guide: Color(white: 0.1),
        player: .cyan,
        playerHighlight: .white,
        pickup: .yellow,
        pickupAlt: .green,
        hazard: .red,
        hazardAlt: .orange,
        outline: .black,                   // cell edges
        spectrum: [.cyan, .yellow, .purple, .green, .red, .orange, .blue] // I O T S Z L J
    )
}

// MARK: - Modes

extension GameMode {
    /// Falling Blocks' standard rules.
    static let blocksMarathon = GameMode(id: "standard", title: String(localized: "Marathon"), summary: String(localized: "Endless, faster every ten lines."))

    static let blocksSprint = GameMode(id: "sprint", title: String(localized: "Sprint"), summary: String(localized: "Clear 40 lines fast. Time left is bonus."))

    static let blocksUltra = GameMode(id: "ultra", title: String(localized: "Ultra"), summary: String(localized: "Score all you can in two minutes."))
}
