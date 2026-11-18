// BrickBreakerGame.swift
// RetroCartridge
//
// Brick Breaker: twelve hand-built walls with tough and steel bricks, and
// four power-ups (wide paddle, multi-ball, laser, sticky paddle). Each life
// starts with the ball resting on the paddle until A launches it.

import SwiftUI

/// Brick Breaker game implementation.
final class BrickBreakerGame: PixelGameProtocol {
    var gameType: GameType = .brickBreaker
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .brickBreaker
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    struct Paddle {
        var x: Double = 0.5
        var width: Double = BrickBreakerGame.paddleWidth
    }

    struct Ball {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var history: [(Double, Double)] = []
        /// While set, the ball rides on the paddle at this offset from its
        /// center, waiting for A (a serve or the sticky power-up).
        var stuckOffset: Double? = nil
    }

    enum BrickKind {
        /// Breaks in one hit.
        case normal
        /// Takes two hits.
        case tough
        /// Never breaks; not needed to clear the wall.
        case steel
    }

    struct Brick {
        var x: Int
        var y: Int
        /// Index into the palette's spectrum.
        var colorIndex: Int
        var kind: BrickKind = .normal
        /// Hits left before the brick breaks.
        var hitsLeft: Int = 1
        var isDestroyed: Bool = false
    }

    struct PowerUp {
        var x: Double
        var y: Double
        var type: PowerUpType
    }

    enum PowerUpType: CaseIterable {
        case widePaddle
        case multiBall
        case laser
        case sticky

        /// Letter printed on the falling capsule.
        var letter: String {
            switch self {
            case .widePaddle: return "W"
            case .multiBall: return "M"
            case .laser: return "L"
            case .sticky: return "S"
            }
        }
    }

    /// A laser bolt fired from the paddle.
    struct Bolt {
        var x: Double
        var y: Double
    }

    // MARK: - Constants

    static let paddleWidth = 0.15
    let rows = 8
    let cols = 8
    let brickHeight = 0.05
    let wallTop = 0.1
    let paddleY = 0.9

    /// Seconds a ball waits on the paddle before launching by itself.
    let autoLaunchDelay: TimeInterval = 2.5

    /// Seconds between laser shots.
    let laserCooldown: TimeInterval = 0.35

    /// The walls, one per level, eight bricks wide. `.` is empty, a digit is
    /// a normal brick in that spectrum color, `T` tough and `S` steel.
    static let levels: [[String]] = [
        // Classic
        ["00000000", "11111111", "22222222", "33333333", "44444444"],
        // Pyramid
        ["...00...", "..1111..", ".222222.", "33333333", "44444444"],
        // Checkers
        ["0.0.0.0.", ".1.1.1.1", "2.2.2.2.", ".3.3.3.3", "4.4.4.4."],
        // Armored core
        ["00000000", "1TTTTTT1", "22222222", "3TTTTTT3", "44444444"],
        // Steel gates
        ["00000000", "11111111", "SSS..SSS", "22222222", "33333333"],
        // Diamond
        ["...TT...", "..1111..", ".222222.", "33333333", ".444444.", "..0000..", "...TT..."],
        // Columns
        ["0.1.2.3.", "0.1.2.3.", "0.1.2.3.", "T.T.T.T.", "0.1.2.3."],
        // Fortress
        ["S......S", "S000000S", "S1TTTT1S", "S222222S", "SSS..SSS"],
        // Stripes
        ["TTTTTTTT", "........", "11111111", "........", "TTTTTTTT", "33333333"],
        // Invader
        ["..3..3..", "...33...", "..3333..", ".33TT33.", "33333333", "3.3..3.3"],
        // Windows
        ["S.0000.S", "..1111..", ".T....T.", ".22..22.", "33333333", "4.4.4.4."],
        // Lattice
        ["00000000", "STSTSTST", "11111111", "TSTSTSTS", "22222222", "33333333"]
    ]

    // MARK: - State

    var paddle: Paddle = Paddle()
    var balls: [Ball] = []
    var bricks: [Brick] = []
    var powerUps: [PowerUp] = []
    var bolts: [Bolt] = []

    var lives: Int = 3
    var dpadLeftPressed = false
    var dpadRightPressed = false

    /// Seconds left on each timed power-up.
    var wideTimeLeft: TimeInterval = 0
    var laserTimeLeft: TimeInterval = 0
    var stickyTimeLeft: TimeInterval = 0

    /// How long balls have been waiting on the paddle.
    var stuckTime: TimeInterval = 0
    var laserCooldownLeft: TimeInterval = 0

    init() {
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        movePaddle(deltaTime: deltaTime)
        tickPowerUps(deltaTime: deltaTime)
        movePowerUps(deltaTime: deltaTime)
        moveBolts(deltaTime: deltaTime)
        moveBalls(deltaTime: deltaTime)

        if balls.isEmpty {
            loseLife()
        }

        // The wall is clear once every breakable brick is gone
        if bricks.allSatisfy({ $0.isDestroyed || $0.kind == .steel }) {
            level += 1
            score += 100 * level
            emit(.levelUp)
            setupLevel()
        }
    }

    private func movePaddle(deltaTime: TimeInterval) {
        let paddleSpeed = 0.8 * deltaTime
        if dpadLeftPressed { paddle.x -= paddleSpeed }
        if dpadRightPressed { paddle.x += paddleSpeed }
        paddle.x = max(paddle.width / 2, min(1.0 - paddle.width / 2, paddle.x))
    }

    private func tickPowerUps(deltaTime: TimeInterval) {
        if wideTimeLeft > 0 {
            wideTimeLeft -= deltaTime
            if wideTimeLeft <= 0 {
                paddle.width = Self.paddleWidth
            }
        }
        laserTimeLeft = max(0, laserTimeLeft - deltaTime)
        stickyTimeLeft = max(0, stickyTimeLeft - deltaTime)
        laserCooldownLeft = max(0, laserCooldownLeft - deltaTime)

        if balls.contains(where: { $0.stuckOffset != nil }) {
            stuckTime += deltaTime
            if stuckTime >= autoLaunchDelay {
                launchStuckBalls()
            }
        } else {
            stuckTime = 0
        }
    }

    private func movePowerUps(deltaTime: TimeInterval) {
        for i in (0..<powerUps.count).reversed() {
            powerUps[i].y += 0.3 * deltaTime
            if powerUps[i].y > 1.0 {
                powerUps.remove(at: i)
                continue
            }
            if powerUps[i].y >= paddleY && powerUps[i].y <= paddleY + 0.05
                && abs(powerUps[i].x - paddle.x) <= paddle.width / 2 {
                emit(.powerUp)
                applyPowerUp(powerUps[i].type)
                powerUps.remove(at: i)
            }
        }
    }

    private func moveBolts(deltaTime: TimeInterval) {
        for i in (0..<bolts.count).reversed() {
            bolts[i].y -= 1.2 * deltaTime
            if bolts[i].y < 0 {
                bolts.remove(at: i)
            } else if let brick = brickIndex(atX: bolts[i].x, y: bolts[i].y) {
                hitBrick(brick)
                bolts.remove(at: i)
            }
        }
    }

    private func moveBalls(deltaTime: TimeInterval) {
        for i in (0..<balls.count).reversed() {
            var ball = balls[i]

            // Riding on the paddle
            if let offset = ball.stuckOffset {
                ball.x = paddle.x + offset
                ball.y = paddleY - 0.02
                ball.history.removeAll()
                balls[i] = ball
                continue
            }

            ball.history.append((ball.x, ball.y))
            if ball.history.count > 3 {
                ball.history.removeFirst()
            }

            let previousX = ball.x
            let previousY = ball.y
            ball.x += ball.vx * deltaTime
            ball.y += ball.vy * deltaTime

            // Walls
            if ball.x <= 0 || ball.x >= 1.0 {
                ball.vx *= -1
                ball.x = ball.x <= 0 ? 0 : 1.0
                emit(.wallBounce)
            }
            if ball.y <= 0 {
                ball.vy *= -1
                ball.y = 0
                emit(.wallBounce)
            }

            // Paddle (swept: catches the ball even when a slow frame moves it
            // past the paddle's top edge in a single step)
            if ball.vy > 0 && previousY <= paddleY && ball.y >= paddleY
                && abs(ball.x - paddle.x) <= paddle.width / 2 {
                ball.y = paddleY
                emit(.paddleBounce)
                if stickyTimeLeft > 0 {
                    ball.stuckOffset = ball.x - paddle.x
                } else {
                    aim(&ball, fromOffset: ball.x - paddle.x)
                }
            }

            // Bricks
            if let index = brickIndex(atX: ball.x, y: ball.y) {
                let brickLeft = Double(bricks[index].x) / Double(cols)
                let brickRight = brickLeft + 1.0 / Double(cols)
                if previousX < brickLeft || previousX > brickRight {
                    ball.vx *= -1
                } else {
                    ball.vy *= -1
                }
                hitBrick(index)
            }

            if ball.y > 1.0 {
                balls.remove(at: i)
            } else {
                balls[i] = ball
            }
        }
    }

    // MARK: - Rules

    /// The ball's speed on the current level.
    private var ballSpeed: Double {
        0.6 * pow(1.05, Double(level - 1))
    }

    /// Sends a ball up at an angle set by where it left the paddle.
    private func aim(_ ball: inout Ball, fromOffset offset: Double) {
        let hitFactor = max(-1, min(1, offset / (paddle.width / 2)))
        let vx = hitFactor * 0.8
        let vy = -0.6
        let length = sqrt(vx * vx + vy * vy)
        ball.vx = vx / length * ballSpeed
        ball.vy = vy / length * ballSpeed
    }

    private func launchStuckBalls() {
        for i in balls.indices {
            guard let offset = balls[i].stuckOffset else { continue }
            balls[i].stuckOffset = nil
            aim(&balls[i], fromOffset: offset == 0 ? paddle.width * 0.2 : offset)
        }
        stuckTime = 0
        emit(.paddleBounce)
    }

    private func fireLaser() {
        guard laserTimeLeft > 0, laserCooldownLeft <= 0 else { return }
        laserCooldownLeft = laserCooldown
        let edge = paddle.width / 2 - 0.01
        bolts.append(Bolt(x: paddle.x - edge, y: paddleY))
        bolts.append(Bolt(x: paddle.x + edge, y: paddleY))
        emit(.laserShot)
    }

    /// The live brick covering a point, if any.
    private func brickIndex(atX x: Double, y: Double) -> Int? {
        let brickWidth = 1.0 / Double(cols)
        return bricks.firstIndex { brick in
            guard !brick.isDestroyed else { return false }
            let left = Double(brick.x) * brickWidth
            let top = wallTop + Double(brick.y) * brickHeight
            return x >= left && x <= left + brickWidth && y >= top && y <= top + brickHeight
        }
    }

    func hitBrick(_ index: Int) {
        switch bricks[index].kind {
        case .steel:
            emit(.armorHit)
            return
        case .tough where bricks[index].hitsLeft > 1:
            bricks[index].hitsLeft -= 1
            score += 5
            emit(.armorHit)
            return
        default:
            break
        }

        bricks[index].isDestroyed = true
        score += bricks[index].kind == .tough ? 25 : 10
        emit(.brickBreak)

        if Double.random(in: 0...1, using: &rng) < 0.18 {
            let brickWidth = 1.0 / Double(cols)
            let type = PowerUpType.allCases.randomElement(using: &rng) ?? .widePaddle
            powerUps.append(PowerUp(
                x: (Double(bricks[index].x) + 0.5) * brickWidth,
                y: wallTop + (Double(bricks[index].y) + 0.5) * brickHeight,
                type: type
            ))
        }
    }

    private func loseLife() {
        lives -= 1
        if lives <= 0 {
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.gameOver)
        } else {
            emit(.lifeLost)
            clearTimedPowerUps()
            serveBall()
        }
    }

    func applyPowerUp(_ type: PowerUpType) {
        switch type {
        case .widePaddle:
            paddle.width = Self.paddleWidth * 1.5
            wideTimeLeft = 10
        case .multiBall:
            if let firstBall = balls.first(where: { $0.stuckOffset == nil }) {
                var b1 = firstBall
                b1.vx = -b1.vx
                balls.append(b1)

                var b2 = firstBall
                b2.vy = -abs(b2.vy)
                b2.vx = firstBall.vx * 0.5
                balls.append(b2)
            } else {
                serveBall()
            }
        case .laser:
            laserTimeLeft = 8
        case .sticky:
            stickyTimeLeft = 10
        }
    }

    private func clearTimedPowerUps() {
        paddle.width = Self.paddleWidth
        wideTimeLeft = 0
        laserTimeLeft = 0
        stickyTimeLeft = 0
        bolts.removeAll()
    }

    /// Builds the wall for the current level and serves a new ball.
    func setupLevel() {
        bricks.removeAll()
        let layout = Self.levels[(level - 1) % Self.levels.count]
        for (row, line) in layout.prefix(rows).enumerated() {
            for (column, character) in line.prefix(cols).enumerated() {
                switch character {
                case "T":
                    bricks.append(Brick(x: column, y: row, colorIndex: row, kind: .tough, hitsLeft: 2))
                case "S":
                    bricks.append(Brick(x: column, y: row, colorIndex: row, kind: .steel, hitsLeft: .max))
                default:
                    if let colorIndex = character.wholeNumberValue {
                        bricks.append(Brick(x: column, y: row, colorIndex: colorIndex))
                    }
                }
            }
        }
        powerUps.removeAll()
        clearTimedPowerUps()
        balls.removeAll()
        serveBall()
    }

    /// Puts a ball on the paddle, ready to launch.
    func serveBall() {
        balls.append(Ball(x: paddle.x, y: paddleY - 0.02, vx: 0, vy: 0, stuckOffset: 0))
        stuckTime = 0
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))

        if gameState == .menu {
            return
        }

        // Bricks
        let brickW = size.width / Double(cols)
        let brickH = size.height * brickHeight
        let wallY = size.height * wallTop
        for brick in bricks where !brick.isDestroyed {
            let rect = CGRect(x: Double(brick.x) * brickW, y: wallY + Double(brick.y) * brickH, width: brickW - 2, height: brickH - 2)
            switch brick.kind {
            case .normal:
                context.fill(Path(rect), with: .color(palette.spectrumColor(brick.colorIndex)))
            case .tough:
                let color = palette.spectrumColor(brick.colorIndex)
                context.fill(Path(rect), with: .color(brick.hitsLeft > 1 ? color : color.opacity(0.55)))
                context.stroke(Path(rect.insetBy(dx: 2, dy: 2)), with: .color(palette.playerHighlight), lineWidth: 1)
            case .steel:
                context.fill(Path(rect), with: .color(palette.guide))
                context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(palette.playerHighlight.opacity(0.8)), lineWidth: 1.5)
            }
        }

        // Paddle, with cannons while the laser lasts and a bright top while sticky
        let pWidth = size.width * paddle.width
        let pRect = CGRect(x: size.width * paddle.x - pWidth / 2, y: size.height * paddleY, width: pWidth, height: size.height * 0.02)
        context.fill(Path(pRect), with: .color(palette.player))
        if laserTimeLeft > 0 {
            for x in [pRect.minX, pRect.maxX - 4] {
                context.fill(Path(CGRect(x: x, y: pRect.minY - 5, width: 4, height: 5)), with: .color(palette.hazard))
            }
        }
        if stickyTimeLeft > 0 {
            context.fill(Path(CGRect(x: pRect.minX, y: pRect.minY, width: pRect.width, height: 2)), with: .color(palette.pickup))
        }

        // Laser bolts
        for bolt in bolts {
            let rect = CGRect(x: size.width * bolt.x - 1, y: size.height * bolt.y - 8, width: 2, height: 8)
            context.fill(Path(rect), with: .color(palette.hazard))
        }

        // Power-up capsules with their letter
        for p in powerUps {
            let rect = CGRect(x: size.width * p.x - 9, y: size.height * p.y - 6, width: 18, height: 12)
            context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color(of: p.type)))
            context.draw(
                Text(p.type.letter)
                    .font(.pixel(9))
                    .foregroundStyle(palette.background),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        }

        // Balls with a short trail
        for ball in balls {
            for (idx, pos) in ball.history.enumerated() {
                let rect = CGRect(x: size.width * pos.0 - 2, y: size.height * pos.1 - 2, width: 4, height: 4)
                context.fill(Path(rect), with: .color(palette.playerHighlight.opacity(Double(idx + 1) * 0.25)))
            }
            let rect = CGRect(x: size.width * ball.x - 4, y: size.height * ball.y - 4, width: 8, height: 8)
            context.fill(Path(rect), with: .color(palette.playerHighlight))
        }
    }

    private func color(of type: PowerUpType) -> Color {
        switch type {
        case .widePaddle: return palette.pickup
        case .multiBall: return palette.pickupAlt
        case .laser: return palette.hazard
        case .sticky: return palette.hazardAlt
        }
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadLeftPressed: dpadLeftPressed = true
        case .dpadLeftReleased: dpadLeftPressed = false
        case .dpadRightPressed: dpadRightPressed = true
        case .dpadRightReleased: dpadRightPressed = false
        case .buttonAPressed:
            switch gameState {
            case .menu, .gameOver:
                reset()
                gameState = .playing
                emit(.roundStart)
            case .playing:
                // A launches a waiting ball, otherwise fires the laser
                if balls.contains(where: { $0.stuckOffset != nil }) {
                    launchStuckBalls()
                } else {
                    fireLaser()
                }
            case .paused:
                break
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
        lives = 3
        paddle = Paddle()
        dpadLeftPressed = false
        dpadRightPressed = false
        setupLevel()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Brick Breaker's native palette.
    static let brickBreaker = GamePalette(
        background: .black,
        guide: Color(white: 0.35),    // steel bricks
        player: .cyan,                // paddle
        playerHighlight: .white,      // ball, trail, brick rims
        pickup: .orange,              // wide paddle
        pickupAlt: .white,            // multi-ball
        hazard: .red,                 // laser
        hazardAlt: Color(hex: "#B388FF"), // sticky
        outline: .black,
        spectrum: [.red, .orange, .yellow, .green, .cyan] // brick rows, top down
    )
}
