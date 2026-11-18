// PaddleDuelGame.swift
// RetroCartridge
//
// Paddle Duel: table tennis against the computer, your paddle at the bottom
// and its paddle at the top. Where the ball meets the paddle sets its angle,
// a moving paddle adds spin, and every return speeds the ball up. Each point
// won scores; three won points make a level, where the computer gets
// quicker. Three missed balls end the match. Squash mode takes the computer
// away: keep a rally going against the top wall.

import SwiftUI

final class PaddleDuelGame: PixelGameProtocol {
    var gameType: GameType = .paddleDuel
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .paddleDuel
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Layout (a unit square, y down)

    /// Height of the player's paddle.
    let playerY = 0.92
    /// Height of the computer's paddle.
    let cpuY = 0.08
    /// Where the ball bounces off the top wall in Squash.
    let wallY = 0.04
    let paddleHalfWidth = 0.1
    let paddleThickness = 0.025
    let ballRadius = 0.018
    /// How far the player's paddle moves per second.
    let paddleSpeed = 1.3
    /// Fastest the ball goes, in field heights per second.
    let maxBallSpeed = 1.6

    // MARK: - State

    var playerX = 0.5
    var cpuX = 0.5
    var ballX = 0.5
    var ballY = 0.5
    var ballVX = 0.0
    var ballVY = 0.0
    var lives = 3
    /// Points the player has won (Match).
    var pointsWon = 0
    /// Returns in the current rally.
    var rally = 0
    /// Pause after a point, before the next serve; the ball is hidden.
    var serveTimer: TimeInterval = 0
    /// Whether the next serve goes up, toward the computer.
    var serveUp = false
    /// Where the computer aims relative to the ball this rally, so it
    /// misses now and then.
    var cpuAimError = 0.0
    var holdingLeft = false
    var holdingRight = false

    /// Whether this is a rally against the wall, with no computer.
    var isSquash: Bool { mode == .paddleSquash }

    init() {
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        // The player's paddle
        let direction = (holdingRight ? 1.0 : 0) - (holdingLeft ? 1.0 : 0)
        let previousX = playerX
        playerX = clampPaddle(playerX + direction * paddleSpeed * deltaTime)
        let paddleVelocity = deltaTime > 0 ? (playerX - previousX) / deltaTime : 0

        if !isSquash {
            moveComputer(deltaTime: deltaTime)
        }

        if serveTimer > 0 {
            serveTimer -= deltaTime
            if serveTimer <= 0 { serve() }
            return
        }

        let previousY = ballY
        ballX += ballVX * deltaTime
        ballY += ballVY * deltaTime

        // Side walls
        if ballX < ballRadius {
            ballX = ballRadius
            ballVX = abs(ballVX)
            emit(.wallBounce)
        } else if ballX > 1 - ballRadius {
            ballX = 1 - ballRadius
            ballVX = -abs(ballVX)
            emit(.wallBounce)
        }

        // The player's paddle
        let playerFace = playerY - paddleThickness / 2
        if ballVY > 0, previousY + ballRadius <= playerFace, ballY + ballRadius >= playerFace,
           abs(ballX - playerX) <= paddleHalfWidth + ballRadius {
            ballY = playerFace - ballRadius
            returnBall(from: playerX, upward: true, spin: paddleVelocity)
            rally += 1
            score += isSquash ? 10 * level : 10
            if isSquash && rally % 10 == 0 {
                levelUp()
            }
        }

        if isSquash {
            // The top wall
            if ballVY < 0 && ballY - ballRadius <= wallY {
                ballY = wallY + ballRadius
                ballVY = abs(ballVY)
                emit(.wallBounce)
            }
        } else {
            // The computer's paddle
            let cpuFace = cpuY + paddleThickness / 2
            if ballVY < 0, previousY - ballRadius >= cpuFace, ballY - ballRadius <= cpuFace,
               abs(ballX - cpuX) <= paddleHalfWidth + ballRadius {
                ballY = cpuFace + ballRadius
                returnBall(from: cpuX, upward: false, spin: 0)
                cpuAimError = Double.random(in: -1...1, using: &rng) * cpuErrorRange
            }
        }

        // Points
        if ballY > 1 + ballRadius {
            missed()
        } else if ballY < -ballRadius {
            pointWon()
        }
    }

    /// The computer follows the ball on its way up and drifts back to the
    /// middle otherwise, a little quicker every level.
    private func moveComputer(deltaTime: TimeInterval) {
        let target = ballVY < 0 && serveTimer <= 0 ? ballX + cpuAimError : 0.5
        let speed = min(1.1, 0.45 + 0.08 * Double(level - 1))
        let step = speed * deltaTime
        cpuX = clampPaddle(cpuX + max(-step, min(step, target - cpuX)))
    }

    /// How far off the computer may aim: less every level.
    private var cpuErrorRange: Double {
        max(0.05, 0.14 - 0.015 * Double(level - 1))
    }

    private func clampPaddle(_ x: Double) -> Double {
        min(1 - paddleHalfWidth, max(paddleHalfWidth, x))
    }

    // MARK: - Rules

    /// Sends the ball back off a paddle: the farther from the middle it
    /// hits, the steeper the angle, and a moving paddle adds spin.
    private func returnBall(from paddleX: Double, upward: Bool, spin: Double) {
        let offset = max(-1, min(1, (ballX - paddleX) / paddleHalfWidth))
        let speed = min(maxBallSpeed, (ballVX * ballVX + ballVY * ballVY).squareRoot() * 1.05)
        let angle = offset * .pi / 3
        ballVX = speed * sin(angle) + spin * 0.25
        ballVY = speed * cos(angle) * (upward ? -1 : 1)
        emit(.paddleBounce)
    }

    private func pointWon() {
        pointsWon += 1
        score += 100 * level
        emit(.coin)
        if pointsWon % 3 == 0 {
            levelUp()
        }
        prepareServe(up: false)
    }

    private func missed() {
        lives -= 1
        emit(.lifeLost)
        if lives <= 0 {
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.gameOver)
        } else {
            prepareServe(up: !isSquash)
        }
    }

    private func levelUp() {
        level += 1
        emit(.levelUp)
    }

    /// Hides the ball for a moment before the next serve.
    private func prepareServe(up: Bool) {
        serveUp = up
        serveTimer = 0.8
        rally = 0
        ballX = 0.5
        ballY = 0.5
        ballVX = 0
        ballVY = 0
    }

    /// Serves from the middle toward whoever won the point, so the player
    /// who just missed gets a moment to recover, a little faster every
    /// level. Squash serves from the top wall.
    private func serve() {
        let speed = min(maxBallSpeed, 0.55 + 0.05 * Double(level - 1))
        let angle = Double.random(in: -0.5...0.5, using: &rng)
        ballX = 0.5
        ballY = isSquash ? wallY + 0.1 : 0.5
        ballVX = speed * sin(angle)
        ballVY = speed * cos(angle) * (serveUp ? -1 : 1)
        cpuAimError = Double.random(in: -1...1, using: &rng) * cpuErrorRange
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        let w = size.width
        let h = size.height

        if isSquash {
            // The wall, with its bricks
            let wall = CGRect(x: 0, y: 0, width: w, height: wallY * h)
            context.fill(Path(wall), with: .color(palette.hazardAlt))
            var joints = Path()
            for i in 1..<10 {
                let x = w * Double(i) / 10
                joints.move(to: CGPoint(x: x, y: 0))
                joints.addLine(to: CGPoint(x: x, y: wall.maxY))
            }
            context.stroke(joints, with: .color(palette.background.opacity(0.5)), lineWidth: 1)
        } else {
            // The net across the middle
            var net = Path()
            net.move(to: CGPoint(x: 0, y: h / 2))
            net.addLine(to: CGPoint(x: w, y: h / 2))
            context.stroke(net, with: .color(palette.guide), style: StrokeStyle(lineWidth: 2, dash: [w * 0.03, w * 0.03]))

            // The computer's paddle
            context.fill(paddlePath(x: cpuX, y: cpuY, size: size), with: .color(palette.hazard))
        }

        context.fill(paddlePath(x: playerX, y: playerY, size: size), with: .color(palette.player))

        // The ball, square as on the old sets
        if serveTimer <= 0 {
            let side = ballRadius * 2 * min(w, h)
            context.fill(Path(CGRect(x: ballX * w - side / 2, y: ballY * h - side / 2, width: side, height: side)), with: .color(palette.playerHighlight))
        }

        // Balls left, in the corner
        let pip = min(w, h) * 0.022
        for life in 0..<max(0, lives - 1) {
            let rect = CGRect(x: w * 0.03 + Double(life) * pip * 1.8, y: h - pip * 1.6, width: pip, height: pip)
            context.fill(Path(rect), with: .color(palette.pickupAlt))
        }

        // Points won, one tick each (Match)
        if !isSquash && pointsWon > 0 {
            for point in 0..<min(pointsWon, 12) {
                let rect = CGRect(x: w * 0.97 - pip - Double(point) * pip * 1.5, y: h / 2 + pip, width: pip * 0.6, height: pip * 1.4)
                context.fill(Path(rect), with: .color(palette.pickup))
            }
        }
    }

    private func paddlePath(x: Double, y: Double, size: CGSize) -> Path {
        let rect = CGRect(
            x: (x - paddleHalfWidth) * size.width,
            y: (y - paddleThickness / 2) * size.height,
            width: paddleHalfWidth * 2 * size.width,
            height: paddleThickness * size.height
        )
        return Path(roundedRect: rect, cornerRadius: rect.height * 0.3)
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadLeftPressed: holdingLeft = true
        case .dpadLeftReleased: holdingLeft = false
        case .dpadRightPressed: holdingRight = true
        case .dpadRightReleased: holdingRight = false
        case .buttonAPressed:
            switch gameState {
            case .menu, .gameOver:
                reset()
                gameState = .playing
                emit(.roundStart)
            default:
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
        lives = 3
        pointsWon = 0
        playerX = 0.5
        cpuX = 0.5
        holdingLeft = false
        holdingRight = false
        prepareServe(up: false)
        serveTimer = 0.6
    }
}

// MARK: - Modes

extension GameMode {
    /// Paddle Duel's standard rules.
    static let paddleMatch = GameMode(id: "standard", title: String(localized: "Match"), summary: String(localized: "Beat the computer. Three misses and you're out."))

    static let paddleSquash = GameMode(id: "squash", title: String(localized: "Squash"), summary: String(localized: "Alone against the wall. Keep the rally going."))
}

// MARK: - Palette

extension GamePalette {
    /// Paddle Duel's native palette.
    static let paddleDuel = GamePalette(
        background: Color(hex: "#0B1320"),
        guide: Color(hex: "#2A3A5C"),          // net
        player: Color(hex: "#F9844A"),         // your paddle
        playerHighlight: .white,               // ball
        pickup: Color(hex: "#90BE6D"),         // points won
        pickupAlt: Color(hex: "#F9C74F"),      // balls left
        hazard: Color(hex: "#4D9DE0"),         // the computer's paddle
        hazardAlt: Color(hex: "#577590"),      // squash wall
        outline: .black,
        spectrum: [Color(hex: "#F9844A"), Color(hex: "#F9C74F"), Color(hex: "#90BE6D"), Color(hex: "#4D9DE0")]
    )
}
