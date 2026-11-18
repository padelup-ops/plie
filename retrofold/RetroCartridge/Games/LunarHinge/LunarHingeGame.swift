// LunarHingeGame.swift
// RetroCartridge
//
// Lunar Hinge: set the lander down gently on one of three pads, the
// narrower the pad the bigger the multiplier. Thrust by folding the device
// a little: 30° further than it was when the attempt began gives full
// thrust. The same thrust is always on ▲ or A, so the game plays in every
// pose (HIG: "don't tie functionality to a specific pose"); the side
// thrusters are on ◀ ▶.

import SwiftUI

final class LunarHingeGame: PixelGameProtocol, HingeControllable {
    var gameType: GameType = .lunarHinge
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .lunarHinge
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    struct Pad {
        var start: Double
        var end: Double
        var height: Double
        var multiplier: Int

        var center: Double { (start + end) / 2 }
    }

    // MARK: - Physics

    let segments = 16
    let halfWidth = 0.02
    let halfHeight = 0.02
    let mainThrust = 0.10
    let sideThrust = 0.045
    let safeVerticalSpeed = 0.07
    let safeHorizontalSpeed = 0.05
    /// Degrees of extra folding that give full thrust.
    let hingeThrustRange = 30.0

    var gravity: Double { min(0.065, 0.04 + 0.003 * Double(level - 1)) }
    var startingFuel: Double { max(100, 150 - 10 * Double(level - 1)) }

    // MARK: - State

    /// Terrain heights at `segments + 1` evenly spaced points.
    var heights: [Double] = []
    var pads: [Pad] = []
    var stars: [CGPoint] = []

    var x = 0.5
    var y = 0.08
    var vx = 0.0
    var vy = 0.0
    var fuel = 150.0
    var lives = 3

    var thrustHeld = false
    var leftHeld = false
    var rightHeld = false

    /// The most-open hinge angle seen this attempt; folding from it thrusts.
    var hingeRest: Double?
    /// Thrust from the hinge, 0...1.
    var hingeThrust = 0.0
    /// Thrust applied this frame, 0...1, for the flame.
    var thrust = 0.0

    /// Pause after a landing or crash, before the next attempt.
    var outcomeTimer: TimeInterval = 0
    var landedPad: Pad?
    var crashed = false
    /// Seconds the controls hint stays up.
    var hintTimer: TimeInterval = 0
    private var thrustSoundTimer: TimeInterval = 0
    private var clock: TimeInterval = 0

    init() {
        reset()
    }

    // MARK: - Terrain

    /// Ground height at a horizontal position.
    func ground(at position: Double) -> Double {
        let clamped = min(max(position, 0), 0.99999)
        let scaled = clamped * Double(segments)
        let index = Int(scaled)
        let t = scaled - Double(index)
        return heights[index] + (heights[index + 1] - heights[index]) * t
    }

    /// Rugged ground with three flat pads, one in each third of the screen:
    /// a wide ×1, a medium ×2 and a narrow ×4, in a random order.
    private func buildTerrain() {
        heights = (0...segments).map { _ in Double.random(in: 0.66...0.92, using: &rng) }
        var specs = [(length: 3, multiplier: 1), (length: 2, multiplier: 2), (length: 1, multiplier: 4)]
        specs.shuffle(using: &rng)
        let thirds = [(1, 5), (6, 10), (11, 15)]
        pads = []
        for (third, spec) in zip(thirds, specs) {
            let start = Int.random(in: third.0...(third.1 - spec.length), using: &rng)
            let height = Double.random(in: 0.72...0.9, using: &rng)
            for index in start...(start + spec.length) {
                heights[index] = height
            }
            pads.append(Pad(
                start: Double(start) / Double(segments),
                end: Double(start + spec.length) / Double(segments),
                height: height,
                multiplier: spec.multiplier
            ))
        }
        stars = (0..<40).map { _ in
            CGPoint(x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...0.6, using: &rng))
        }
    }

    private func spawnLander() {
        x = Double.random(in: 0.1...0.9, using: &rng)
        y = 0.08
        vx = Double.random(in: -0.03...0.03, using: &rng)
        vy = 0
        fuel = startingFuel
        hingeRest = nil
        hingeThrust = 0
        landedPad = nil
        crashed = false
    }

    // MARK: - Hinge

    func hingeDidChange(angle: Double) {
        guard gameState == .playing, outcomeTimer <= 0 else {
            hingeRest = nil
            hingeThrust = 0
            return
        }
        // Opening further moves the rest angle up; folding from it thrusts.
        let rest = max(hingeRest ?? angle, angle)
        hingeRest = rest
        hingeThrust = min(1, max(0, (rest - angle) / hingeThrustRange))
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        clock += deltaTime
        guard gameState == .playing else { return }

        if outcomeTimer > 0 {
            outcomeTimer -= deltaTime
            if outcomeTimer <= 0 {
                if landedPad != nil {
                    buildTerrain()
                }
                spawnLander()
            }
            return
        }
        hintTimer = max(0, hintTimer - deltaTime)

        // Thrusters
        thrust = fuel > 0 ? max(thrustHeld ? 1 : 0, hingeThrust) : 0
        let side = fuel > 0 ? (rightHeld ? 1.0 : 0) - (leftHeld ? 1.0 : 0) : 0
        fuel = max(0, fuel - (8 * thrust + 3 * abs(side)) * deltaTime)

        vx += sideThrust * side * deltaTime
        vy += (gravity - mainThrust * thrust) * deltaTime
        x += vx * deltaTime
        y += vy * deltaTime

        if x < halfWidth || x > 1 - halfWidth {
            x = min(max(x, halfWidth), 1 - halfWidth)
            vx = 0
        }
        if y < 0 {
            y = 0
            vy = max(vy, 0)
        }

        if thrust > 0 {
            thrustSoundTimer -= deltaTime
            if thrustSoundTimer <= 0 {
                thrustSoundTimer = 0.14
                emit(.thrust)
            }
        }

        checkContact()
    }

    private func checkContact() {
        let left = x - halfWidth
        let right = x + halfWidth
        let feet = y + halfHeight
        guard feet >= min(ground(at: left), ground(at: right), ground(at: x)) else { return }

        let pad = pads.first { $0.start <= left && right <= $0.end }
        if let pad, abs(vy) <= safeVerticalSpeed, abs(vx) <= safeHorizontalSpeed {
            y = pad.height - halfHeight
            landedPad = pad
            score += 50 * pad.multiplier * level + Int(fuel)
            level += 1
            emit(.levelUp)
        } else {
            crashed = true
            lives -= 1
            emit(.crash)
            if lives <= 0 {
                if score > highScore { highScore = score }
                gameState = .gameOver(score: score)
                emit(.gameOver)
                return
            }
        }
        thrust = 0
        outcomeTimer = 1.8
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu, !heights.isEmpty else { return }

        func point(_ px: Double, _ py: Double) -> CGPoint {
            CGPoint(x: px * size.width, y: py * size.height)
        }

        // Stars
        for star in stars {
            context.fill(Path(CGRect(x: star.x * size.width, y: star.y * size.height, width: 1.5, height: 1.5)), with: .color(palette.playerHighlight.opacity(0.5)))
        }

        // Ground
        var surface = Path()
        surface.move(to: point(0, 1))
        for (index, height) in heights.enumerated() {
            surface.addLine(to: point(Double(index) / Double(segments), height))
        }
        surface.addLine(to: point(1, 1))
        surface.closeSubpath()
        context.fill(surface, with: .color(palette.guide))
        var ridge = Path()
        for (index, height) in heights.enumerated() {
            let p = point(Double(index) / Double(segments), height)
            if index == 0 {
                ridge.move(to: p)
            } else {
                ridge.addLine(to: p)
            }
        }
        context.stroke(ridge, with: .color(palette.playerHighlight.opacity(0.6)), lineWidth: 1.5)

        // Pads and their multipliers
        for pad in pads {
            var line = Path()
            line.move(to: point(pad.start, pad.height))
            line.addLine(to: point(pad.end, pad.height))
            context.stroke(line, with: .color(palette.pickup), lineWidth: 3)
            context.draw(hudText("×\(pad.multiplier)", size: size.height * 0.035, color: palette.pickup),
                         at: point(pad.center, pad.height + 0.035))
        }

        drawLander(in: &context, size: size)
        drawHUD(in: &context, size: size)
    }

    private func drawLander(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: x * size.width, y: y * size.height)
        let w = halfWidth * 2 * size.width
        let h = halfHeight * 2 * size.height

        if crashed {
            // Debris
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3 + clock
                let r = w * (0.4 + 0.3 * sin(clock * 3 + Double(i)))
                let bit = CGRect(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * 0.5, width: 3, height: 3)
                context.fill(Path(bit), with: .color(palette.hazard))
            }
            return
        }

        // Flame, flickering and sized by thrust
        if thrust > 0 {
            let length = h * (0.5 + thrust * (0.7 + 0.3 * sin(clock * 40)))
            var flame = Path()
            flame.move(to: CGPoint(x: center.x - w * 0.2, y: center.y + h * 0.35))
            flame.addLine(to: CGPoint(x: center.x, y: center.y + h * 0.35 + length))
            flame.addLine(to: CGPoint(x: center.x + w * 0.2, y: center.y + h * 0.35))
            flame.closeSubpath()
            context.fill(flame, with: .color(palette.hazardAlt))
        }

        // Legs, body and window
        var legs = Path()
        legs.move(to: CGPoint(x: center.x - w * 0.3, y: center.y + h * 0.1))
        legs.addLine(to: CGPoint(x: center.x - w * 0.5, y: center.y + h * 0.5))
        legs.move(to: CGPoint(x: center.x + w * 0.3, y: center.y + h * 0.1))
        legs.addLine(to: CGPoint(x: center.x + w * 0.5, y: center.y + h * 0.5))
        context.stroke(legs, with: .color(palette.player), lineWidth: 1.5)
        context.fill(Path(CGRect(x: center.x - w * 0.35, y: center.y - h * 0.1, width: w * 0.7, height: h * 0.45)), with: .color(palette.player))
        context.fill(Path(ellipseIn: CGRect(x: center.x - w * 0.25, y: center.y - h * 0.5, width: w * 0.5, height: h * 0.5)), with: .color(palette.player))
        context.fill(Path(ellipseIn: CGRect(x: center.x - w * 0.1, y: center.y - h * 0.35, width: w * 0.2, height: h * 0.2)), with: .color(palette.background))
    }

    private func drawHUD(in context: inout GraphicsContext, size: CGSize) {
        let unit = size.height * 0.035
        let margin = size.width * 0.03

        // Fuel gauge
        context.draw(hudText(String(localized: "FUEL", comment: "Lunar Hinge HUD"), size: unit, color: palette.playerHighlight.opacity(0.7)), at: CGPoint(x: margin, y: margin), anchor: .topLeading)
        let gauge = CGRect(x: margin, y: margin + unit * 1.4, width: size.width * 0.22, height: unit * 0.6)
        context.stroke(Path(gauge), with: .color(palette.playerHighlight.opacity(0.4)), lineWidth: 1)
        context.fill(Path(CGRect(x: gauge.minX, y: gauge.minY, width: gauge.width * min(1, fuel / 150), height: gauge.height)),
                     with: .color(fuel < 25 ? palette.hazard : palette.pickupAlt))

        // Speeds, red when too fast to land
        let vsColor = abs(vy) > safeVerticalSpeed ? palette.hazard : palette.pickupAlt
        let hsColor = abs(vx) > safeHorizontalSpeed ? palette.hazard : palette.pickupAlt
        context.draw(hudText(String(format: "V %+.2f", -vy), size: unit, color: vsColor), at: CGPoint(x: margin, y: margin + unit * 2.6), anchor: .topLeading)
        context.draw(hudText(String(format: "H %+.2f", vx), size: unit, color: hsColor), at: CGPoint(x: margin, y: margin + unit * 3.9), anchor: .topLeading)

        // Hinge thrust meter
        let meter = CGRect(x: size.width - margin - unit * 0.8, y: margin + unit * 1.4, width: unit * 0.8, height: size.height * 0.2)
        context.draw(hudText(String(localized: "HINGE", comment: "Lunar Hinge HUD: the hinge angle"), size: unit * 0.8, color: palette.playerHighlight.opacity(0.7)), at: CGPoint(x: meter.maxX, y: margin), anchor: .topTrailing)
        context.stroke(Path(meter), with: .color(palette.playerHighlight.opacity(0.4)), lineWidth: 1)
        let filled = meter.height * hingeThrust
        context.fill(Path(CGRect(x: meter.minX, y: meter.maxY - filled, width: meter.width, height: filled)), with: .color(palette.hazardAlt))

        // Messages
        let middle = CGPoint(x: size.width / 2, y: size.height * 0.3)
        if let pad = landedPad {
            context.draw(hudText(String(localized: "LANDED ×\(pad.multiplier)"), size: unit * 1.6, color: palette.pickup), at: middle)
        } else if crashed {
            context.draw(hudText(String(localized: "CRASHED", comment: "Lunar Hinge HUD"), size: unit * 1.6, color: palette.hazard), at: middle)
        } else if hintTimer > 0 {
            context.draw(hudText(String(localized: "FOLD OR HOLD ▲ TO THRUST", comment: "Lunar Hinge HUD hint"), size: unit, color: palette.playerHighlight.opacity(0.85)), at: middle)
        }
    }

    private func hudText(_ text: String, size: Double, color: Color) -> Text {
        Text(text)
            .font(.pixel(size))
            .foregroundStyle(color)
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadUpPressed: thrustHeld = true
        case .dpadUpReleased, .buttonAReleased: thrustHeld = false
        case .dpadLeftPressed: leftHeld = true
        case .dpadLeftReleased: leftHeld = false
        case .dpadRightPressed: rightHeld = true
        case .dpadRightReleased: rightHeld = false
        case .buttonAPressed:
            switch gameState {
            case .menu, .gameOver:
                reset()
                gameState = .playing
                hintTimer = 4
                emit(.roundStart)
            case .playing:
                thrustHeld = true
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
        thrustHeld = false
        leftHeld = false
        rightHeld = false
        outcomeTimer = 0
        buildTerrain()
        spawnLander()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Lunar Hinge's native palette.
    static let lunarHinge = GamePalette(
        background: Color(hex: "#03040A"),
        guide: Color(hex: "#2A2D3A"),        // ground
        player: Color(hex: "#E0E1DD"),       // lander
        playerHighlight: .white,             // stars, ridge, HUD labels
        pickup: Color(hex: "#FFD166"),       // pads
        pickupAlt: Color(hex: "#06D6A0"),    // fuel, safe speeds
        hazard: Color(hex: "#EF476F"),       // danger, debris
        hazardAlt: Color(hex: "#FF9F1C"),    // flame, hinge thrust
        outline: .black,
        spectrum: [Color(hex: "#E0E1DD"), Color(hex: "#FFD166")]
    )
}
