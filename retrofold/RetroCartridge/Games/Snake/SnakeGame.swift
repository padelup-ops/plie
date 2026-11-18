// SnakeGame.swift
// RetroCartridge
//
// Snake in three modes: Classic (deadly walls), Wrap (the edges wrap
// around) and Maze (walls inside the field too). Every seventh apple a gold
// bonus appears for a few seconds.

import SwiftUI

/// Snake game implementation.
final class SnakeGame: PixelGameProtocol {
    var gameType: GameType = .snake
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .snake
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    struct SnakeSegment: Hashable {
        var x: Int
        var y: Int
    }

    enum Direction {
        case up, down, left, right
    }

    /// A bonus item and how long it stays.
    struct Bonus {
        var cell: SnakeSegment
        var timeLeft: TimeInterval
    }

    var snake: [SnakeSegment] = []
    var currentDir: Direction = .right
    var nextDir: Direction = .right
    var food: SnakeSegment = SnakeSegment(x: 10, y: 10)
    var bonus: Bonus?
    /// Walls inside the field (Maze mode).
    var obstacles: Set<SnakeSegment> = []

    let gridSize = 20
    var lastMoveTime: TimeInterval = 0
    var moveInterval: TimeInterval = 0.150
    var foodEaten: Int = 0

    /// Seconds a bonus stays on the field.
    let bonusDuration: TimeInterval = 5

    /// Whether the edges wrap around instead of killing.
    var wrapsAround: Bool { mode == .snakeWrap }

    init() {
        reset()
    }

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        if var current = bonus {
            current.timeLeft -= deltaTime
            bonus = current.timeLeft > 0 ? current : nil
        }

        lastMoveTime += deltaTime
        if lastMoveTime >= moveInterval {
            lastMoveTime = 0
            moveSnake()
        }
    }

    func moveSnake() {
        currentDir = nextDir
        var head = snake[0]

        switch currentDir {
        case .up: head.y -= 1
        case .down: head.y += 1
        case .left: head.x -= 1
        case .right: head.x += 1
        }

        if wrapsAround {
            head.x = (head.x + gridSize) % gridSize
            head.y = (head.y + gridSize) % gridSize
        } else if head.x < 0 || head.x >= gridSize || head.y < 0 || head.y >= gridSize {
            die()
            return
        }

        // Walls and the snake's own body. The tail moves away this step, so
        // the head may take its cell.
        if obstacles.contains(head) || snake.dropLast().contains(head) {
            die()
            return
        }

        snake.insert(head, at: 0)

        if let current = bonus, current.cell == head {
            score += 50 * level
            bonus = nil
            emit(.bonus)
        }

        if head == food {
            score += 10 * level
            foodEaten += 1
            emit(.eat)
            if foodEaten % 5 == 0 {
                level += 1
                emit(.levelUp)
                moveInterval = max(0.060, moveInterval - 0.005)
            }
            if foodEaten % 7 == 0 {
                bonus = Bonus(cell: freeCell(), timeLeft: bonusDuration)
            }
            food = freeCell()
        } else {
            snake.removeLast()
        }
    }

    /// A random cell with nothing on it.
    func freeCell() -> SnakeSegment {
        while true {
            let cell = SnakeSegment(
                x: Int.random(in: 0..<gridSize, using: &rng),
                y: Int.random(in: 0..<gridSize, using: &rng)
            )
            if !snake.contains(cell) && !obstacles.contains(cell) && cell != food && cell != bonus?.cell {
                return cell
            }
        }
    }

    func die() {
        if score > highScore { highScore = score }
        gameState = .gameOver(score: score)
        emit(.collision)
        emit(.gameOver)
    }

    // MARK: - Mazes

    /// The inner walls of Maze mode: one of four layouts, all leaving the
    /// start row clear so the snake never begins facing a wall.
    static func maze(_ layout: Int) -> Set<SnakeSegment> {
        var walls: Set<SnakeSegment> = []
        func horizontal(_ y: Int, _ xs: ClosedRange<Int>) { for x in xs { walls.insert(SnakeSegment(x: x, y: y)) } }
        func vertical(_ x: Int, _ ys: ClosedRange<Int>) { for y in ys { walls.insert(SnakeSegment(x: x, y: y)) } }

        switch layout % 4 {
        case 0:
            // Two long bars
            horizontal(5, 4...15)
            horizontal(15, 4...15)
        case 1:
            // Side posts with a gap through the middle
            vertical(4, 3...7)
            vertical(4, 13...17)
            vertical(15, 3...7)
            vertical(15, 13...17)
        case 2:
            // Corner brackets
            horizontal(2, 2...6); vertical(2, 2...6)
            horizontal(2, 13...17); vertical(17, 2...6)
            horizontal(17, 2...6); vertical(2, 13...17)
            horizontal(17, 13...17); vertical(17, 13...17)
        default:
            // Bars and brackets together
            horizontal(5, 6...13)
            horizontal(15, 6...13)
            vertical(2, 2...5); vertical(17, 2...5)
            vertical(2, 14...17); vertical(17, 14...17)
        }
        return walls
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

        if gameState == .menu { return }

        // Square cells, board centered on the screen
        let cellSize = min(size.width, size.height) / Double(gridSize)
        let boardX = (size.width - cellSize * Double(gridSize)) / 2
        let boardY = (size.height - cellSize * Double(gridSize)) / 2
        context.translateBy(x: boardX, y: boardY)

        func cellRect(_ cell: SnakeSegment, inset: Double) -> CGRect {
            CGRect(x: Double(cell.x) * cellSize + inset, y: Double(cell.y) * cellSize + inset, width: cellSize - inset * 2, height: cellSize - inset * 2)
        }

        // Grid; in Wrap mode the border is dashed to show it can be crossed
        for i in 0...gridSize {
            var path = Path()
            path.move(to: CGPoint(x: Double(i) * cellSize, y: 0))
            path.addLine(to: CGPoint(x: Double(i) * cellSize, y: cellSize * Double(gridSize)))
            context.stroke(path, with: .color(palette.guide), lineWidth: 1)

            var path2 = Path()
            path2.move(to: CGPoint(x: 0, y: Double(i) * cellSize))
            path2.addLine(to: CGPoint(x: cellSize * Double(gridSize), y: Double(i) * cellSize))
            context.stroke(path2, with: .color(palette.guide), lineWidth: 1)
        }
        let border = Path(CGRect(x: 0, y: 0, width: cellSize * Double(gridSize), height: cellSize * Double(gridSize)))
        context.stroke(
            border,
            with: .color(wrapsAround ? palette.guide : palette.player.opacity(0.5)),
            style: StrokeStyle(lineWidth: 2, dash: wrapsAround ? [4, 4] : [])
        )

        // Maze walls
        for wall in obstacles {
            context.fill(Path(cellRect(wall, inset: 0.5)), with: .color(palette.hazardAlt))
        }

        // Food
        let now = Date().timeIntervalSince1970
        let pulse = (sin(now * 5) + 1) / 2
        context.fill(Path(cellRect(food, inset: 2)), with: .color(palette.pickup.opacity(0.5 + pulse * 0.5)))

        // Bonus, blinking faster as it runs out
        if let bonus {
            let blinkRate = bonus.timeLeft < 1.5 ? 16.0 : 6.0
            if sin(now * blinkRate) > -0.3 {
                context.fill(Path(ellipseIn: cellRect(bonus.cell, inset: 1)), with: .color(palette.pickupAlt))
            }
        }

        // Snake
        for (i, seg) in snake.enumerated() {
            context.fill(Path(cellRect(seg, inset: 1)), with: .color(i == 0 ? palette.playerHighlight : palette.player))
        }
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadUpPressed: if currentDir != .down { nextDir = .up }
        case .dpadDownPressed: if currentDir != .up { nextDir = .down }
        case .dpadLeftPressed: if currentDir != .right { nextDir = .left }
        case .dpadRightPressed: if currentDir != .left { nextDir = .right }
        case .buttonAPressed:
            switch gameState {
            case .menu, .gameOver:
                reset()
                gameState = .playing
                emit(.roundStart)
            default: break
            }
        case .buttonStartPressed:
            if gameState == .playing { pause() }
            else if gameState == .paused { resume() }
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
        snake = [
            SnakeSegment(x: 10, y: 10),
            SnakeSegment(x: 9, y: 10),
            SnakeSegment(x: 8, y: 10)
        ]
        currentDir = .right
        nextDir = .right
        moveInterval = 0.150
        foodEaten = 0
        bonus = nil
        obstacles = mode == .snakeMaze ? Self.maze(Int.random(in: 0..<4, using: &rng)) : []
        food = SnakeSegment(x: -1, y: -1)
        food = freeCell()
    }
}

// MARK: - Modes

extension GameMode {
    /// Snake's standard rules.
    static let snakeClassic = GameMode(id: "standard", title: String(localized: "Classic"), summary: String(localized: "The walls are deadly."))

    static let snakeWrap = GameMode(id: "wrap", title: String(localized: "Wrap"), summary: String(localized: "Go through a wall, come out the other side."))

    static let snakeMaze = GameMode(id: "maze", title: String(localized: "Maze"), summary: String(localized: "Walls inside the field."))
}

// MARK: - Palette

extension GamePalette {
    /// Snake's native palette.
    static let snake = GamePalette(
        background: .black,
        guide: Color(white: 0.1),          // grid lines
        player: Color(hex: "00FF41"),      // body
        playerHighlight: Color(hex: "50FF80"), // head
        pickup: Color(hex: "00FF41"),      // food
        pickupAlt: Color(hex: "FFD23F"),   // bonus
        hazard: Color(hex: "FF3B30"),
        hazardAlt: Color(hex: "2E7D5B"),   // maze walls
        outline: .black,
        spectrum: [Color(hex: "00FF41"), Color(hex: "50FF80")]
    )
}
