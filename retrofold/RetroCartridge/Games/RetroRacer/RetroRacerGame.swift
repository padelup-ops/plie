// RetroRacerGame.swift
// RetroCartridge
//
// Retro Racer: a three-lane highway dodge that speeds up over time, with
// coins to collect. Night mode leaves only the headlights' cone and the
// traffic's taillights to see by.

import SwiftUI

/// Retro Racer game implementation.
final class RetroRacerGame: PixelGameProtocol {
    var gameType: GameType = .retroRacer
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .retroRacer
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []
    
    struct Car {
        var lane: Int
        var y: Double
        /// Drawn in the palette's second hazard color.
        var isAlt: Bool
    }
    
    var playerLane: Double = 1.0 // 0, 1, 2
    var targetLane: Int = 1
    var obstacles: [Car] = []

    /// A coin waiting in a lane.
    struct Coin {
        var lane: Int
        var y: Double
    }

    var coins: [Coin] = []
    var coinTimer: TimeInterval = 1.5
    
    var roadOffset: Double = 0
    var speed: Double = 0.5
    var spawnTimer: TimeInterval = 0
    var currentSpawnInterval: TimeInterval = 1.5
    
    var survivalTime: TimeInterval = 0
    
    init() {
        reset()
    }
    
    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }
        
        // One point per second survived, independent of frame rate
        survivalTime += deltaTime
        while survivalTime >= 1.0 {
            survivalTime -= 1.0
            score += 1
        }
        
        // Level up over time
        let newLevel = 1 + score / 100
        if newLevel > level {
            emit(.levelUp)
        }
        level = newLevel
        speed = 0.5 + Double(level) * 0.05
        currentSpawnInterval = max(0.4, 1.5 - Double(level - 1) * 0.1)
        
        // Player lane interpolation
        let laneDiff = Double(targetLane) - playerLane
        playerLane += laneDiff * min(1.0, 10.0 * deltaTime)
        
        // Road scrolling
        roadOffset += speed * deltaTime
        if roadOffset > 1.0 { roadOffset -= 1.0 }
        
        // Spawn obstacles
        spawnTimer -= deltaTime
        if spawnTimer <= 0 {
            spawnTimer = currentSpawnInterval
            let lane = Int.random(in: 0...2, using: &rng)
            obstacles.append(Car(lane: lane, y: -0.2, isAlt: Bool.random(using: &rng)))
        }
        
        // Coins, now and then, in a lane free of traffic at the top
        coinTimer -= deltaTime
        if coinTimer <= 0 {
            coinTimer = Double.random(in: 1.8...3.2, using: &rng)
            let lane = Int.random(in: 0...2, using: &rng)
            if !obstacles.contains(where: { $0.lane == lane && $0.y < 0.1 }) {
                coins.append(Coin(lane: lane, y: -0.1))
            }
        }

        // Update obstacles
        let playerRect = CGRect(x: playerLane * 0.33 + 0.165 - 0.05, y: 0.8, width: 0.1, height: 0.1)

        for i in (0..<coins.count).reversed() {
            coins[i].y += speed * deltaTime
            let coinRect = CGRect(x: Double(coins[i].lane) * 0.33 + 0.165 - 0.03, y: coins[i].y, width: 0.06, height: 0.06)
            if playerRect.intersects(coinRect) {
                score += 10 * level
                emit(.coin)
                coins.remove(at: i)
            } else if coins[i].y > 1.2 {
                coins.remove(at: i)
            }
        }
        
        for i in (0..<obstacles.count).reversed() {
            obstacles[i].y += speed * deltaTime
            
            let obsRect = CGRect(x: Double(obstacles[i].lane) * 0.33 + 0.165 - 0.05, y: obstacles[i].y, width: 0.1, height: 0.1)
            
            // Collision
            if playerRect.intersects(obsRect) {
                die()
                return
            }
            
            // Near miss logic could be added here
            
            if obstacles[i].y > 1.2 {
                obstacles.remove(at: i)
            }
        }
    }
    
    func die() {
        if score > highScore { highScore = score }
        gameState = .gameOver(score: score)
        emit(.crash)
        emit(.gameOver)
    }
    
    func render(context: inout GraphicsContext, size: CGSize) {
        // Road
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        
        if gameState == .menu { return }
        
        // Road lines
        for i in 1...2 {
            var path = Path()
            path.move(to: CGPoint(x: size.width * (Double(i) * 0.333), y: 0))
            path.addLine(to: CGPoint(x: size.width * (Double(i) * 0.333), y: size.height))
            // Basic dashed lines with offset
            context.stroke(path, with: .color(palette.guide), style: StrokeStyle(lineWidth: 2, dash: [20, 20], dashPhase: CGFloat(-roadOffset * Double(size.height))))
        }
        
        // Coins
        for coin in coins {
            let cx = size.width * (Double(coin.lane) * 0.333 + 0.166)
            let cy = size.height * coin.y
            let rect = CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: rect), with: .color(palette.pickup))
            context.fill(Path(ellipseIn: rect.insetBy(dx: 6, dy: 4)), with: .color(palette.pickupAlt))
        }

        // Obstacles
        for obs in obstacles {
            let cx = size.width * (Double(obs.lane) * 0.333 + 0.166)
            let cy = size.height * obs.y
            let rect = CGRect(x: cx - 20, y: cy - 30, width: 40, height: 60)
            context.fill(Path(rect), with: .color(obs.isAlt ? palette.hazardAlt : palette.hazard))
        }
        
        // Player, drawn over the night so the car stays visible
        let px = size.width * (playerLane * 0.333 + 0.166)
        let py = size.height * 0.85
        let pRect = CGRect(x: px - 20, y: py - 30, width: 40, height: 60)
        if mode == .racerNight {
            drawNight(in: &context, size: size, carX: px, carTop: pRect.minY)
        }
        context.fill(Path(pRect), with: .color(palette.player))

        // Speedometer
        let kmh = Int(speed * 240)
        context.draw(
            Text("\(kmh) KM/H")
                .font(.pixel(max(10, size.height * 0.045)))
                .foregroundStyle(palette.playerHighlight.opacity(0.8)),
            at: CGPoint(x: size.width - 8, y: 8),
            anchor: .topTrailing
        )
    }

    /// Darkness everywhere but the headlights' cone, with the traffic's
    /// taillights glowing through it.
    private func drawNight(in context: inout GraphicsContext, size: CGSize, carX: Double, carTop: Double) {
        var darkness = Path(CGRect(origin: .zero, size: size))
        var cone = Path()
        cone.move(to: CGPoint(x: carX - 14, y: carTop))
        cone.addLine(to: CGPoint(x: carX - size.width * 0.28, y: carTop - size.height * 0.55))
        cone.addLine(to: CGPoint(x: carX + size.width * 0.28, y: carTop - size.height * 0.55))
        cone.addLine(to: CGPoint(x: carX + 14, y: carTop))
        cone.closeSubpath()
        darkness.addPath(cone)
        context.fill(darkness, with: .color(palette.background.opacity(0.93)), style: FillStyle(eoFill: true))

        for obs in obstacles {
            let cx = size.width * (Double(obs.lane) * 0.333 + 0.166)
            let bottom = size.height * obs.y + 30
            for dx in [-14.0, 10.0] {
                let light = CGRect(x: cx + dx, y: bottom - 5, width: 4, height: 3)
                context.fill(Path(light), with: .color(palette.hazard))
            }
        }
    }
    
    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadLeftPressed:
            if targetLane > 0 {
                targetLane -= 1
                if gameState == .playing { emit(.laneChange) }
            }
        case .dpadRightPressed:
            if targetLane < 2 {
                targetLane += 1
                if gameState == .playing { emit(.laneChange) }
            }
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
        playerLane = 1.0
        targetLane = 1
        obstacles.removeAll()
        coins.removeAll()
        coinTimer = 1.5
        survivalTime = 0
        roadOffset = 0
    }
}

// MARK: - Palette

extension GamePalette {
    /// Retro Racer's native palette.
    static let retroRacer = GamePalette(
        background: Color(hex: "1a1a2e"),  // asphalt
        guide: .white.opacity(0.3),        // lane dashes
        player: Color(hex: "4361EE"),
        playerHighlight: .white,
        pickup: Color(hex: "FFD166"),      // coins
        pickupAlt: Color(hex: "B8860B"),   // coin face
        hazard: Color(hex: "E63946"),      // traffic
        hazardAlt: Color(hex: "FFD166"),   // traffic
        outline: .black,
        spectrum: [Color(hex: "E63946"), Color(hex: "FFD166")]
    )
}

// MARK: - Modes

extension GameMode {
    /// Retro Racer's standard rules.
    static let racerDay = GameMode(id: "standard", title: String(localized: "Day"), summary: String(localized: "Dodge traffic, grab coins."))

    static let racerNight = GameMode(id: "night", title: String(localized: "Night"), summary: String(localized: "Only your headlights to see by."))
}
