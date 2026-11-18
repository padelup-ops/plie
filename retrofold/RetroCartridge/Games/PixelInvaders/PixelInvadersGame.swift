// PixelInvadersGame.swift
// RetroCartridge
//
// Pixel Invaders: a fixed-screen shooter. A formation marches side to
// side, stepping down at the edges and speeding up as it thins out, to a
// four-note bass march. Four shields erode under fire, and a saucer crosses
// the top now and then for bonus points.

import SwiftUI

final class PixelInvadersGame: PixelGameProtocol {
    var gameType: GameType = .pixelInvaders
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .pixelInvaders
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    struct Shot {
        var x: Double
        var y: Double
    }

    struct ShieldBlock: Hashable {
        var column: Int
        var row: Int
    }

    struct Saucer {
        var x: Double
        var direction: Double
    }

    // MARK: - Layout

    let columns = 8
    let rows = 4
    let spacingX = 0.085
    let spacingY = 0.075
    let invaderWidth = 0.06
    let invaderHeight = 0.045
    let cannonY = 0.9
    let cannonWidth = 0.08
    /// The formation has landed once its bottom row reaches this line.
    let invasionLine = 0.84

    // Shields: four bunkers of 6 × 4 blocks
    let shieldTop = 0.72
    let shieldBlockWidth = 0.014
    let shieldBlockHeight = 0.018
    let shieldCenters = [0.16, 0.39, 0.62, 0.85]

    // MARK: - State

    /// Whether each invader is alive, row by row from the top.
    var alive: [Bool] = []
    /// Top-left corner of the formation.
    var formationX = 0.1
    var formationY = 0.12
    var direction = 1.0
    var stepTimer: TimeInterval = 0
    /// Which of the two walking frames the invaders show.
    var walkFrame = 0
    var marchNote = 0

    var cannonX = 0.5
    var lives = 3
    var leftHeld = false
    var rightHeld = false

    var shot: Shot?
    var bombs: [Shot] = []
    var bombTimer: TimeInterval = 1
    var shields: Set<ShieldBlock> = []
    var saucer: Saucer?
    var saucerTimer: TimeInterval = 12
    /// Brief pause after the cannon is hit.
    var respawnTimer: TimeInterval = 0

    init() {
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        if respawnTimer > 0 {
            respawnTimer -= deltaTime
            return
        }

        moveCannon(deltaTime: deltaTime)
        marchFormation(deltaTime: deltaTime)
        moveShot(deltaTime: deltaTime)
        dropBombs(deltaTime: deltaTime)
        moveSaucer(deltaTime: deltaTime)

        if !alive.contains(true) {
            level += 1
            score += 100 * level
            emit(.levelUp)
            startWave()
        }
    }

    private func moveCannon(deltaTime: TimeInterval) {
        let speed = 0.55 * deltaTime
        if leftHeld { cannonX -= speed }
        if rightHeld { cannonX += speed }
        cannonX = max(cannonWidth / 2, min(1 - cannonWidth / 2, cannonX))
    }

    /// Seconds between formation steps: faster with fewer invaders and on
    /// later waves.
    private var stepInterval: TimeInterval {
        let remaining = Double(alive.filter { $0 }.count) / Double(alive.count)
        return max(0.05, (0.08 + 0.5 * remaining) * pow(0.9, Double(level - 1)))
    }

    private func marchFormation(deltaTime: TimeInterval) {
        stepTimer += deltaTime
        guard stepTimer >= stepInterval else { return }
        stepTimer = 0
        walkFrame = 1 - walkFrame
        emit(.march(step: marchNote))
        marchNote = (marchNote + 1) % 4

        let (minColumn, maxColumn) = livingColumnRange()
        let left = formationX + Double(minColumn) * spacingX
        let right = formationX + Double(maxColumn) * spacingX + invaderWidth
        let step = 0.02 * direction

        if left + step < 0.02 || right + step > 0.98 {
            formationY += 0.03
            direction = -direction
        } else {
            formationX += step
        }

        if let bottom = lowestLivingRow(), formationY + Double(bottom) * spacingY + invaderHeight >= invasionLine {
            gameOver()
        }
    }

    private func moveShot(deltaTime: TimeInterval) {
        guard var current = shot else { return }
        current.y -= 1.3 * deltaTime
        shot = current

        if current.y < 0 {
            shot = nil
            return
        }

        // Saucer
        if let saucer, current.y < 0.08, abs(current.x - saucer.x) < 0.05 {
            self.saucer = nil
            shot = nil
            score += 100 * level
            emit(.bonus)
            return
        }

        // Invaders
        for index in alive.indices where alive[index] {
            let frame = invaderFrame(index)
            if frame.contains(CGPoint(x: current.x, y: current.y)) {
                alive[index] = false
                shot = nil
                score += [30, 20, 20, 10][index / columns] * level
                emit(.explosion)
                return
            }
        }

        if hitShield(at: current) {
            shot = nil
        }
    }

    private func dropBombs(deltaTime: TimeInterval) {
        bombTimer -= deltaTime
        if bombTimer <= 0 {
            bombTimer = max(0.35, Double.random(in: 0.6...1.4, using: &rng) * pow(0.9, Double(level - 1)))
            // The lowest living invader of a random column drops a bomb
            let occupied = (0..<columns).filter { column in
                (0..<rows).contains { alive[$0 * columns + column] }
            }
            if let column = occupied.randomElement(using: &rng),
               let row = (0..<rows).reversed().first(where: { alive[$0 * columns + column] }) {
                let frame = invaderFrame(row * columns + column)
                bombs.append(Shot(x: frame.midX, y: frame.maxY))
            }
        }

        for i in (0..<bombs.count).reversed() {
            bombs[i].y += 0.45 * deltaTime
            let bomb = bombs[i]
            if bomb.y > 1 {
                bombs.remove(at: i)
            } else if hitShield(at: bomb) {
                bombs.remove(at: i)
            } else if bomb.y >= cannonY && bomb.y <= cannonY + 0.04 && abs(bomb.x - cannonX) < cannonWidth / 2 {
                bombs.remove(at: i)
                cannonHit()
                return
            }
        }
    }

    private func moveSaucer(deltaTime: TimeInterval) {
        if var current = saucer {
            current.x += 0.22 * current.direction * deltaTime
            saucer = (current.x < -0.1 || current.x > 1.1) ? nil : current
        } else {
            saucerTimer -= deltaTime
            if saucerTimer <= 0 {
                saucerTimer = Double.random(in: 14...24, using: &rng)
                let fromLeft = Bool.random(using: &rng)
                saucer = Saucer(x: fromLeft ? -0.05 : 1.05, direction: fromLeft ? 1 : -1)
            }
        }
    }

    // MARK: - Rules

    /// The frame an invader occupies, in unit coordinates.
    func invaderFrame(_ index: Int) -> CGRect {
        let row = index / columns
        let column = index % columns
        return CGRect(
            x: formationX + Double(column) * spacingX,
            y: formationY + Double(row) * spacingY,
            width: invaderWidth,
            height: invaderHeight
        )
    }

    private func livingColumnRange() -> (Int, Int) {
        let living = (0..<columns).filter { column in (0..<rows).contains { alive[$0 * columns + column] } }
        return (living.min() ?? 0, living.max() ?? columns - 1)
    }

    private func lowestLivingRow() -> Int? {
        (0..<rows).reversed().first { row in (0..<columns).contains { alive[row * columns + $0] } }
    }

    private func shieldFrame(_ block: ShieldBlock) -> CGRect {
        let bunker = block.column / 6
        let left = shieldCenters[bunker] - shieldBlockWidth * 3
        return CGRect(
            x: left + Double(block.column % 6) * shieldBlockWidth,
            y: shieldTop + Double(block.row) * shieldBlockHeight,
            width: shieldBlockWidth,
            height: shieldBlockHeight
        )
    }

    /// Erodes the shield block a shot or bomb touches.
    /// Erodes the shield block a shot or bomb touches; false if it misses.
    func hitShield(at point: Shot) -> Bool {
        guard point.y >= shieldTop - 0.01, point.y <= shieldTop + 4 * shieldBlockHeight + 0.01 else { return false }
        let target = CGPoint(x: point.x, y: point.y)
        // The slightly enlarged frames overlap, so a shot can touch two
        // blocks. Erode the nearest, ties broken by position, never by the
        // set's order: that differs between devices (and instances), and a
        // daily round would play out differently for different players.
        let touched = shields.filter { shieldFrame($0).insetBy(dx: -0.004, dy: -0.004).contains(target) }
        guard let block = touched.min(by: { lhs, rhs in
            (distance(from: target, to: lhs), lhs.row, lhs.column) < (distance(from: target, to: rhs), rhs.row, rhs.column)
        }) else { return false }
        shields.remove(block)
        return true
    }

    private func distance(from point: CGPoint, to block: ShieldBlock) -> Double {
        let frame = shieldFrame(block)
        return hypot(point.x - frame.midX, point.y - frame.midY)
    }

    private func cannonHit() {
        lives -= 1
        emit(.crash)
        bombs.removeAll()
        shot = nil
        if lives <= 0 {
            gameOver()
        } else {
            respawnTimer = 1.2
            cannonX = 0.5
        }
    }

    private func gameOver() {
        if score > highScore { highScore = score }
        gameState = .gameOver(score: score)
        emit(.gameOver)
    }

    private func fire() {
        guard shot == nil, respawnTimer <= 0 else { return }
        shot = Shot(x: cannonX, y: cannonY)
        emit(.laserShot)
    }

    /// Builds a fresh formation, a little lower on each wave.
    func startWave() {
        alive = Array(repeating: true, count: rows * columns)
        formationX = 0.1
        formationY = 0.12 + min(0.12, Double(level - 1) * 0.03)
        direction = 1
        stepTimer = 0
        shot = nil
        bombs.removeAll()
    }

    // MARK: - Render

    /// Invader sprites (8 × 6), two walking frames per kind.
    private static let sprites: [[[String]]] = [
        [ // Squid
            ["...##...", "..####..", ".##..##.", "########", "..#..#..", ".#.##.#."],
            ["...##...", "..####..", ".##..##.", "########", ".#.##.#.", "#......#"]
        ],
        [ // Crab
            ["..#..#..", "...##...", "..####..", ".##..##.", "########", "#.#..#.#"],
            ["..#..#..", "#..##..#", "#.####.#", "###..###", ".######.", ".#....#."]
        ],
        [ // Octopus
            ["..####..", ".######.", "##.##.##", "########", ".#.##.#.", "#......#"],
            ["..####..", ".######.", "##.##.##", "########", "..#..#..", ".#.##.#."]
        ]
    ]

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
        }

        // Ground line
        context.fill(Path(CGRect(x: 0, y: size.height * 0.96, width: size.width, height: 1)), with: .color(palette.guide))

        // Invaders
        for index in alive.indices where alive[index] {
            let kind = [0, 1, 1, 2][index / columns]
            let color = palette.spectrumColor(index / columns)
            drawSprite(Self.sprites[kind][walkFrame], in: rect(invaderFrame(index)), color: color, context: &context)
        }

        // Shields
        for block in shields {
            context.fill(Path(rect(shieldFrame(block))), with: .color(palette.pickup))
        }

        // Saucer
        if let saucer {
            let frame = rect(CGRect(x: saucer.x - 0.045, y: 0.04, width: 0.09, height: 0.03))
            context.fill(Path(ellipseIn: frame), with: .color(palette.hazardAlt))
            context.fill(Path(ellipseIn: frame.insetBy(dx: frame.width * 0.3, dy: -frame.height * 0.2).offsetBy(dx: 0, dy: -frame.height * 0.35)), with: .color(palette.hazardAlt.opacity(0.7)))
        }

        // Shots and bombs
        if let shot {
            context.fill(Path(CGRect(x: shot.x * size.width - 1, y: shot.y * size.height - 8, width: 2, height: 8)), with: .color(palette.playerHighlight))
        }
        for bomb in bombs {
            var zigzag = Path()
            let x = bomb.x * size.width
            let y = bomb.y * size.height
            zigzag.move(to: CGPoint(x: x, y: y - 8))
            zigzag.addLine(to: CGPoint(x: x + 2, y: y - 5))
            zigzag.addLine(to: CGPoint(x: x - 2, y: y - 2))
            zigzag.addLine(to: CGPoint(x: x, y: y))
            context.stroke(zigzag, with: .color(palette.hazard), lineWidth: 1.5)
        }

        // Cannon (blinking while it respawns) and spare lives
        if respawnTimer <= 0 || Int(respawnTimer * 10) % 2 == 0 {
            drawCannon(at: cannonX * size.width, y: cannonY * size.height, width: cannonWidth * size.width, context: &context)
        }
        for life in 0..<max(0, lives - 1) {
            drawCannon(at: size.width * (0.05 + Double(life) * 0.07), y: size.height * 0.975, width: size.width * 0.045, context: &context)
        }
    }

    private func drawSprite(_ sprite: [String], in frame: CGRect, color: Color, context: inout GraphicsContext) {
        let pixelWidth = frame.width / 8
        let pixelHeight = frame.height / Double(sprite.count)
        for (y, row) in sprite.enumerated() {
            for (x, pixel) in row.enumerated() where pixel == "#" {
                let cell = CGRect(x: frame.minX + Double(x) * pixelWidth, y: frame.minY + Double(y) * pixelHeight, width: pixelWidth + 0.3, height: pixelHeight + 0.3)
                context.fill(Path(cell), with: .color(color))
            }
        }
    }

    private func drawCannon(at x: Double, y: Double, width: Double, context: inout GraphicsContext) {
        let height = width * 0.45
        context.fill(Path(CGRect(x: x - width / 2, y: y, width: width, height: height * 0.6)), with: .color(palette.player))
        context.fill(Path(CGRect(x: x - width * 0.08, y: y - height * 0.4, width: width * 0.16, height: height * 0.45)), with: .color(palette.player))
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadLeftPressed: leftHeld = true
        case .dpadLeftReleased: leftHeld = false
        case .dpadRightPressed: rightHeld = true
        case .dpadRightReleased: rightHeld = false
        case .buttonAPressed, .buttonBPressed:
            switch gameState {
            case .menu, .gameOver:
                guard action == .buttonAPressed else { return }
                reset()
                gameState = .playing
                emit(.roundStart)
            case .playing:
                fire()
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
        lives = 3
        cannonX = 0.5
        leftHeld = false
        rightHeld = false
        walkFrame = 0
        marchNote = 0
        saucer = nil
        saucerTimer = 12
        bombTimer = 1
        respawnTimer = 0
        shields = []
        for bunker in 0..<shieldCenters.count {
            for row in 0..<4 {
                for column in 0..<6 where !(row == 3 && (column == 2 || column == 3)) {
                    shields.insert(ShieldBlock(column: bunker * 6 + column, row: row))
                }
            }
        }
        startWave()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Pixel Invaders' native palette.
    static let pixelInvaders = GamePalette(
        background: Color(hex: "#05040F"),
        guide: Color(hex: "#39FF14").opacity(0.5),  // ground
        player: Color(hex: "#39FF14"),              // cannon
        playerHighlight: .white,                    // shot
        pickup: Color(hex: "#39FF14").opacity(0.8), // shields
        pickupAlt: Color(hex: "#FFE600"),
        hazard: Color(hex: "#FF4D6D"),              // bombs
        hazardAlt: Color(hex: "#FF4D6D"),           // saucer
        outline: .black,
        spectrum: [Color(hex: "#F72585"), Color(hex: "#B5179E"), Color(hex: "#7209B7"), Color(hex: "#4CC9F0")]
    )
}
