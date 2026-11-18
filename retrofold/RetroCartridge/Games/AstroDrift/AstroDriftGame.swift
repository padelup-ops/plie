// AstroDriftGame.swift
// RetroCartridge
//
// Astro Drift: a vector-style ship adrift in a field of rocks. Turn with
// ◀ ▶, thrust with ▲, fire with A, and jump to hyperspace with B. Rocks
// split in two when hit, down to the smallest; clearing the field brings a
// bigger, faster wave. The field wraps around at every edge.

import SwiftUI

final class AstroDriftGame: PixelGameProtocol {
    var gameType: GameType = .astroDrift
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .astroDrift
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    struct Rock {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        /// 3 is the largest; a size-1 rock breaks up completely.
        var size: Int
        var spin: Double
        var angle: Double = 0
        /// The outline's radius at evenly spaced angles, as a share of the
        /// rock's radius, so every rock has its own craggy shape.
        var outline: [Double]

        var radius: Double { AstroDriftGame.radius(ofSize: size) }
    }

    struct Shot {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var life: TimeInterval
    }

    // MARK: - Tuning (a unit square that wraps)

    static func radius(ofSize size: Int) -> Double {
        switch size {
        case 3: return 0.085
        case 2: return 0.048
        default: return 0.026
        }
    }

    let shipRadius = 0.028
    /// Radians per second while turning.
    let turnRate = 4.2
    /// Acceleration while thrusting, in field sizes per second squared.
    let thrustPower = 0.7
    let maxShipSpeed = 0.6
    let shotSpeed = 0.95
    let shotLife: TimeInterval = 0.85
    let maxShots = 4
    let fireCooldown: TimeInterval = 0.18

    // MARK: - State

    var shipX = 0.5
    var shipY = 0.5
    var shipVX = 0.0
    var shipVY = 0.0
    /// Heading in radians, 0 pointing up, growing clockwise.
    var shipAngle = 0.0
    var rocks: [Rock] = []
    var shots: [Shot] = []
    var lives = 3
    var turningLeft = false
    var turningRight = false
    var thrusting = false
    var cooldown: TimeInterval = 0
    /// While positive the ship is gone: destroyed, or in hyperspace.
    var respawnTimer: TimeInterval = 0
    /// While positive the ship blinks and can't be hit.
    var shieldTimer: TimeInterval = 0
    /// Pause between waves.
    var waveTimer: TimeInterval = 0
    /// Time since the round started, for the thrust flame's flicker.
    var clock: TimeInterval = 0

    /// Whether the ship is on the field.
    var isShipActive: Bool { respawnTimer <= 0 }

    init() {
        reset()
    }

    // MARK: - Update

    /// The longest step the field moves in one go. Shots cross up to 0.026
    /// of the field per 1/60 s, the radius of the smallest rock, so a longer
    /// frame (30 FPS, a dropped frame) is split up or a shot could skip
    /// right over a rock.
    static let maxStep: TimeInterval = 1.0 / 60

    func update(deltaTime: TimeInterval) {
        let steps = max(1, Int((deltaTime / Self.maxStep).rounded(.up)))
        for _ in 0..<steps {
            step(deltaTime: deltaTime / Double(steps))
        }
    }

    private func step(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }
        clock += deltaTime
        cooldown = max(0, cooldown - deltaTime)
        shieldTimer = max(0, shieldTimer - deltaTime)

        if respawnTimer > 0 {
            respawnTimer -= deltaTime
        } else {
            moveShip(deltaTime: deltaTime)
        }

        for index in rocks.indices {
            rocks[index].x = wrap(rocks[index].x + rocks[index].vx * deltaTime)
            rocks[index].y = wrap(rocks[index].y + rocks[index].vy * deltaTime)
            rocks[index].angle += rocks[index].spin * deltaTime
        }

        for index in shots.indices {
            shots[index].x = wrap(shots[index].x + shots[index].vx * deltaTime)
            shots[index].y = wrap(shots[index].y + shots[index].vy * deltaTime)
            shots[index].life -= deltaTime
        }
        shots.removeAll { $0.life <= 0 }

        resolveHits()

        if isShipActive && shieldTimer <= 0 {
            if rocks.contains(where: { distance($0.x, $0.y, shipX, shipY) < $0.radius + shipRadius * 0.8 }) {
                destroyShip()
            }
        }

        if rocks.isEmpty {
            waveTimer -= deltaTime
            if waveTimer <= 0 {
                level += 1
                emit(.levelUp)
                spawnWave()
            }
        }
    }

    private func moveShip(deltaTime: TimeInterval) {
        let turn = (turningRight ? 1.0 : 0) - (turningLeft ? 1.0 : 0)
        shipAngle += turn * turnRate * deltaTime

        if thrusting {
            shipVX += sin(shipAngle) * thrustPower * deltaTime
            shipVY -= cos(shipAngle) * thrustPower * deltaTime
        }
        // Space dust slows the ship a little, so it can be brought to rest
        let drag = pow(0.55, deltaTime)
        shipVX *= drag
        shipVY *= drag
        let speed = (shipVX * shipVX + shipVY * shipVY).squareRoot()
        if speed > maxShipSpeed {
            shipVX *= maxShipSpeed / speed
            shipVY *= maxShipSpeed / speed
        }
        shipX = wrap(shipX + shipVX * deltaTime)
        shipY = wrap(shipY + shipVY * deltaTime)
    }

    /// Shots break the rocks they touch into two smaller ones.
    private func resolveHits() {
        var hitShots = Set<Int>()
        var remaining: [Rock] = []
        var fragments: [Rock] = []

        for rock in rocks {
            guard let shot = shots.indices.first(where: { !hitShots.contains($0) && distance(shots[$0].x, shots[$0].y, rock.x, rock.y) < rock.radius }) else {
                remaining.append(rock)
                continue
            }
            hitShots.insert(shot)
            score += [3: 20, 2: 50, 1: 100][rock.size, default: 0]
            emit(rock.size == 3 ? .explosion : .brickBreak)
            if rock.size > 1 {
                fragments += (0..<2).map { _ in makeRock(size: rock.size - 1, x: rock.x, y: rock.y) }
            }
        }

        guard !hitShots.isEmpty else { return }
        shots = shots.indices.filter { !hitShots.contains($0) }.map { shots[$0] }
        rocks = remaining + fragments
        if rocks.isEmpty {
            waveTimer = 1.5
        }
    }

    private func destroyShip() {
        lives -= 1
        emit(.collision)
        emit(.lifeLost)
        if lives <= 0 {
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.gameOver)
            return
        }
        respawnTimer = 1.5
        shipX = 0.5
        shipY = 0.5
        shipVX = 0
        shipVY = 0
        shipAngle = 0
        shieldTimer = respawnTimer + 2
    }

    // MARK: - Actions

    private func fire() {
        guard gameState == .playing, isShipActive, cooldown <= 0, shots.count < maxShots else { return }
        cooldown = fireCooldown
        let dx = sin(shipAngle)
        let dy = -cos(shipAngle)
        shots.append(Shot(
            x: wrap(shipX + dx * shipRadius),
            y: wrap(shipY + dy * shipRadius),
            vx: dx * shotSpeed + shipVX,
            vy: dy * shotSpeed + shipVY,
            life: shotLife
        ))
        emit(.laserShot)
    }

    /// Vanishes and reappears somewhere else a moment later: a way out of a
    /// tight spot, with no guarantee the new spot is safe.
    private func hyperspace() {
        guard gameState == .playing, isShipActive else { return }
        shipX = Double.random(in: 0.1...0.9, using: &rng)
        shipY = Double.random(in: 0.1...0.9, using: &rng)
        shipVX = 0
        shipVY = 0
        respawnTimer = 0.35
        emit(.powerUp)
    }

    // MARK: - Rocks

    /// A new wave of large rocks, on a ring around the ship so none starts on it.
    private func spawnWave() {
        let count = min(9, 2 + level)
        rocks = (0..<count).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let reach = Double.random(in: 0.32...0.48, using: &rng)
            return makeRock(size: 3, x: wrap(shipX + cos(angle) * reach), y: wrap(shipY + sin(angle) * reach))
        }
        shots.removeAll()
        shieldTimer = max(shieldTimer, 1)
    }

    private func makeRock(size: Int, x: Double, y: Double) -> Rock {
        let direction = Double.random(in: 0..<(2 * .pi), using: &rng)
        let speed = (0.05 + 0.03 * Double(3 - size) + 0.01 * Double(level - 1)) * Double.random(in: 0.8...1.3, using: &rng)
        return Rock(
            x: x,
            y: y,
            vx: cos(direction) * speed,
            vy: sin(direction) * speed,
            size: size,
            spin: Double.random(in: -1.2...1.2, using: &rng),
            outline: (0..<9).map { _ in Double.random(in: 0.72...1.08, using: &rng) }
        )
    }

    // MARK: - Geometry

    private func wrap(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    /// The shortest offset from `a` to `b` on the wrapping field.
    static func wrappedOffset(from a: Double, to b: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 1)
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return delta
    }

    private func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let dx = Self.wrappedOffset(from: x1, to: x2)
        let dy = Self.wrappedOffset(from: y1, to: y2)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        // A square field, centered
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        var field = context
        field.clip(to: Path(CGRect(origin: origin, size: CGSize(width: side, height: side))))
        let line = max(1, side * 0.006)

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        // Fixed stars
        for star in 0..<24 {
            let x = Double((star * 37) % 100) / 100
            let y = Double((star * 61 + 13) % 100) / 100
            field.fill(Path(CGRect(origin: point(x, y), size: CGSize(width: line, height: line))), with: .color(palette.guide))
        }

        // Anything near an edge is drawn again on the far side, so it
        // slides across seamlessly
        func copies(_ x: Double, _ y: Double, reach: Double) -> [(Double, Double)] {
            var xs = [x]
            var ys = [y]
            if x < reach { xs.append(x + 1) } else if x > 1 - reach { xs.append(x - 1) }
            if y < reach { ys.append(y + 1) } else if y > 1 - reach { ys.append(y - 1) }
            return xs.flatMap { cx in ys.map { cy in (cx, cy) } }
        }

        for rock in rocks {
            for (x, y) in copies(rock.x, rock.y, reach: rock.radius) {
                var outline = Path()
                for (index, share) in rock.outline.enumerated() {
                    let angle = rock.angle + Double(index) / Double(rock.outline.count) * 2 * .pi
                    let p = point(x + cos(angle) * rock.radius * share, y + sin(angle) * rock.radius * share)
                    if index == 0 { outline.move(to: p) } else { outline.addLine(to: p) }
                }
                outline.closeSubpath()
                field.stroke(outline, with: .color(palette.hazard), lineWidth: line)
            }
        }

        for shot in shots {
            let p = point(shot.x, shot.y)
            field.fill(Path(ellipseIn: CGRect(x: p.x - line, y: p.y - line, width: line * 2, height: line * 2)), with: .color(palette.playerHighlight))
        }

        // The ship, blinking while shielded
        if isShipActive && (shieldTimer <= 0 || Int(clock * 8) % 2 == 0) {
            for (x, y) in copies(shipX, shipY, reach: shipRadius) {
                drawShip(at: x, y, context: &field, point: point, line: line)
            }
        }

        // Ships left
        for life in 0..<max(0, lives - 1) {
            drawShip(at: 0.05 + Double(life) * 0.05, 0.06, context: &field, point: point, line: line, scale: 0.7, flame: false)
        }
    }

    private func drawShip(at x: Double, _ y: Double, context: inout GraphicsContext, point: (Double, Double) -> CGPoint, line: CGFloat, scale: Double = 1, flame: Bool = true) {
        let angle = scale == 1 ? shipAngle : 0
        let r = shipRadius * scale
        func corner(_ offset: Double, _ reach: Double) -> CGPoint {
            point(x + sin(angle + offset) * r * reach, y - cos(angle + offset) * r * reach)
        }

        var hull = Path()
        hull.move(to: corner(0, 1.2))
        hull.addLine(to: corner(2.5, 1))
        hull.addLine(to: corner(.pi, 0.45))
        hull.addLine(to: corner(-2.5, 1))
        hull.closeSubpath()
        context.stroke(hull, with: .color(palette.player), lineWidth: line)

        if flame && thrusting && Int(clock * 20) % 2 == 0 {
            var fire = Path()
            fire.move(to: corner(2.8, 0.7))
            fire.addLine(to: corner(.pi, 1.3))
            fire.addLine(to: corner(-2.8, 0.7))
            context.stroke(fire, with: .color(palette.hazardAlt), lineWidth: line)
        }
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadLeftPressed: turningLeft = true
        case .dpadLeftReleased: turningLeft = false
        case .dpadRightPressed: turningRight = true
        case .dpadRightReleased: turningRight = false
        case .dpadUpPressed:
            thrusting = true
            if gameState == .playing { emit(.thrust) }
        case .dpadUpReleased: thrusting = false
        case .buttonAPressed:
            switch gameState {
            case .menu, .gameOver:
                reset()
                gameState = .playing
                emit(.roundStart)
            case .playing:
                fire()
            case .paused:
                break
            }
        case .buttonBPressed:
            hyperspace()
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
        shipX = 0.5
        shipY = 0.5
        shipVX = 0
        shipVY = 0
        shipAngle = 0
        turningLeft = false
        turningRight = false
        thrusting = false
        cooldown = 0
        respawnTimer = 0
        shieldTimer = 0
        waveTimer = 0
        clock = 0
        spawnWave()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Astro Drift's native palette.
    static let astroDrift = GamePalette(
        background: Color(hex: "#05070D"),
        guide: Color(hex: "#3A4A6B"),          // stars
        player: Color(hex: "#E0FBFC"),         // ship
        playerHighlight: Color(hex: "#FFD166"), // shots
        pickup: Color(hex: "#06D6A0"),
        pickupAlt: Color(hex: "#FFD166"),
        hazard: Color(hex: "#98C1D9"),         // rocks
        hazardAlt: Color(hex: "#EE6C4D"),      // thrust flame
        outline: .black,
        spectrum: [Color(hex: "#98C1D9"), Color(hex: "#3D5A80"), Color(hex: "#E0FBFC")]
    )
}
