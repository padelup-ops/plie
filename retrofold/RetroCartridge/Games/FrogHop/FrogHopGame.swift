// FrogHopGame.swift
// RetroCartridge
//
// Frog Hop: hop across five lanes of traffic and four of river to the five
// homes at the top. Logs carry the frog; water, traffic and the screen
// edges don't forgive. Each life has a time limit, and filling every home
// starts a faster level.

import SwiftUI

final class FrogHopGame: PixelGameProtocol {
    var gameType: GameType = .frogHop
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .frogHop
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    enum LaneKind {
        case road
        case river
    }

    /// A lane of cars or logs, all the same length and evenly spaced,
    /// wrapping around the screen.
    struct Lane {
        var row: Int
        var kind: LaneKind
        /// Cells per second; negative moves left.
        var speed: Double
        /// Length of each car or log, in cells.
        var length: Double
        var count: Int
        /// How far the lane has scrolled, in cells.
        var phase: Double = 0
    }

    // MARK: - Layout

    let columns = 13
    let rows = 12
    let homeRow = 0
    let medianRow = 5
    let startRow = 11
    let homeColumns = [1, 4, 6, 8, 11]
    /// Seconds each life has to reach a home.
    let lifeTime: TimeInterval = 30

    // MARK: - State

    var lanes: [Lane] = []
    var frogX = 6.0
    var frogRow = 11
    var homes: Set<Int> = []
    var lives = 3
    var timeLeft: TimeInterval = 30
    /// The highest row reached this life; each new row scores.
    var bestRow = 11
    /// Pause after a death or a home, during which the frog is hidden.
    var pauseTimer: TimeInterval = 0
    /// Time since the last hop, for the hop squash.
    var sinceHop: TimeInterval = 1

    init() {
        reset()
    }

    // MARK: - Lanes

    /// The period over which a lane repeats, in cells.
    private func period(of lane: Lane) -> Double {
        Double(columns) + lane.length * 2
    }

    /// Left edges of a lane's cars or logs, in cells.
    func objectStarts(in lane: Lane) -> [Double] {
        let span = period(of: lane)
        let spacing = span / Double(lane.count)
        return (0..<lane.count).map { k in
            let raw = (lane.phase + Double(k) * spacing).truncatingRemainder(dividingBy: span)
            return (raw < 0 ? raw + span : raw) - lane.length
        }
    }

    /// Whether any car or log in a lane covers a horizontal position.
    func covers(_ lane: Lane, x: Double, margin: Double = 0) -> Bool {
        objectStarts(in: lane).contains { start in
            x >= start + margin && x <= start + lane.length - margin
        }
    }

    func lane(atRow row: Int) -> Lane? {
        lanes.first { $0.row == row }
    }

    private func buildLanes() {
        let pace = pow(1.12, Double(level - 1))
        func jitter() -> Double { Double.random(in: 0.85...1.15, using: &rng) }
        lanes = [
            Lane(row: 1, kind: .river, speed: 1.1 * pace * jitter(), length: 4, count: 2),
            Lane(row: 2, kind: .river, speed: -0.9 * pace * jitter(), length: 3, count: 3),
            Lane(row: 3, kind: .river, speed: 1.5 * pace * jitter(), length: 5, count: 2),
            Lane(row: 4, kind: .river, speed: -1.1 * pace * jitter(), length: 3, count: 3),
            Lane(row: 6, kind: .road, speed: -1.6 * pace * jitter(), length: 2, count: 2),
            Lane(row: 7, kind: .road, speed: 1.2 * pace * jitter(), length: 1, count: 3),
            Lane(row: 8, kind: .road, speed: -1.0 * pace * jitter(), length: 1, count: 3),
            Lane(row: 9, kind: .road, speed: 2.1 * pace * jitter(), length: 1, count: 2),
            Lane(row: 10, kind: .road, speed: -1.3 * pace * jitter(), length: 1, count: 3)
        ]
        for index in lanes.indices {
            lanes[index].phase = Double.random(in: 0..<period(of: lanes[index]), using: &rng)
        }
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        guard gameState == .playing else { return }

        for index in lanes.indices {
            lanes[index].phase += lanes[index].speed * deltaTime
        }
        sinceHop += deltaTime

        if pauseTimer > 0 {
            pauseTimer -= deltaTime
            if pauseTimer <= 0 { respawn() }
            return
        }

        timeLeft -= deltaTime
        if timeLeft <= 0 {
            die()
            return
        }

        guard let lane = lane(atRow: frogRow) else { return }
        let center = frogX + 0.5
        switch lane.kind {
        case .road:
            if covers(lane, x: center, margin: 0.15) {
                emit(.crash)
                die()
            }
        case .river:
            if covers(lane, x: center, margin: 0.05) {
                // Riding a log; off the screen edge is a loss
                frogX += lane.speed * deltaTime
                if frogX < -0.3 || frogX > Double(columns) - 0.7 {
                    die()
                }
            } else {
                die()
            }
        }
    }

    // MARK: - Rules

    private func hop(dx: Int, dy: Int) {
        guard gameState == .playing, pauseTimer <= 0 else { return }
        let newRow = frogRow + dy
        let newX = frogX + Double(dx)
        guard newRow >= homeRow, newRow <= startRow, newX >= -0.3, newX <= Double(columns) - 0.7 else { return }

        frogRow = newRow
        frogX = newX
        sinceHop = 0
        emit(.hop)

        if frogRow < bestRow {
            bestRow = frogRow
            score += 10
        }

        if frogRow == homeRow {
            arriveHome()
        }
    }

    private func arriveHome() {
        let column = Int(frogX.rounded())
        guard homeColumns.contains(column), !homes.contains(column) else {
            die()
            return
        }
        homes.insert(column)
        score += 50 + Int(timeLeft) * 10
        emit(.bonus)

        if homes.count == homeColumns.count {
            level += 1
            score += 500 * level
            homes.removeAll()
            buildLanes()
            emit(.levelUp)
        }
        pauseTimer = 0.6
    }

    private func die() {
        lives -= 1
        emit(.lifeLost)
        if lives <= 0 {
            if score > highScore { highScore = score }
            gameState = .gameOver(score: score)
            emit(.gameOver)
        } else {
            pauseTimer = 1
        }
    }

    private func respawn() {
        frogX = 6
        frogRow = startRow
        bestRow = startRow
        timeLeft = lifeTime
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        let cell = min(size.width / Double(columns), size.height / Double(rows + 1))
        let originX = (size.width - cell * Double(columns)) / 2
        let originY = (size.height - cell * Double(rows + 1)) / 2

        func rowRect(_ row: Int) -> CGRect {
            CGRect(x: originX, y: originY + Double(row) * cell, width: cell * Double(columns), height: cell)
        }

        // River, safe strips and homes
        for row in 1...4 {
            context.fill(Path(rowRect(row)), with: .color(palette.guide))
        }
        for row in [medianRow, startRow] {
            context.fill(Path(rowRect(row)), with: .color(palette.outline))
        }
        context.fill(Path(rowRect(homeRow)), with: .color(palette.pickupAlt.opacity(0.35)))
        for column in homeColumns {
            let bay = CGRect(x: originX + Double(column) * cell, y: originY, width: cell, height: cell).insetBy(dx: 2, dy: 2)
            context.fill(Path(bay), with: .color(palette.guide))
            if homes.contains(column) {
                drawFrog(in: bay, context: &context)
            }
        }

        // Lane markings on the road
        for row in 7...10 {
            var line = Path()
            let y = originY + Double(row) * cell
            line.move(to: CGPoint(x: originX, y: y))
            line.addLine(to: CGPoint(x: originX + cell * Double(columns), y: y))
            context.stroke(line, with: .color(palette.playerHighlight.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [cell * 0.4, cell * 0.4]))
        }

        // Logs and cars, clipped to the playfield
        var field = context
        field.clip(to: Path(CGRect(x: originX, y: originY, width: cell * Double(columns), height: cell * Double(rows))))
        for lane in lanes {
            for start in objectStarts(in: lane) {
                let rect = CGRect(x: originX + start * cell, y: originY + Double(lane.row) * cell, width: lane.length * cell, height: cell)
                switch lane.kind {
                case .river:
                    field.fill(Path(roundedRect: rect.insetBy(dx: 1, dy: cell * 0.15), cornerRadius: cell * 0.3), with: .color(palette.pickup))
                case .road:
                    let car = rect.insetBy(dx: cell * 0.08, dy: cell * 0.18)
                    field.fill(Path(roundedRect: car, cornerRadius: cell * 0.12), with: .color(lane.row % 2 == 0 ? palette.hazard : palette.hazardAlt))
                    // Headlights on the leading end
                    let front = lane.speed > 0 ? car.maxX - 3 : car.minX + 1
                    field.fill(Path(CGRect(x: front, y: car.minY + 2, width: 2, height: 3)), with: .color(palette.playerHighlight))
                    field.fill(Path(CGRect(x: front, y: car.maxY - 5, width: 2, height: 3)), with: .color(palette.playerHighlight))
                }
            }
        }

        // The frog, squashing briefly after a hop
        if pauseTimer <= 0 {
            let squash = sinceHop < 0.1 ? 0.8 : 1.0
            let frame = CGRect(x: originX + frogX * cell, y: originY + Double(frogRow) * cell, width: cell, height: cell)
            let body = CGRect(x: frame.midX - cell * 0.4, y: frame.midY - cell * 0.4 * squash, width: cell * 0.8, height: cell * 0.8 * squash)
            drawFrog(in: body, context: &context)
        }

        // Time bar and lives under the playfield
        let barY = originY + Double(rows) * cell + cell * 0.3
        let barWidth = cell * Double(columns) * 0.6 * max(0, timeLeft / lifeTime)
        context.fill(Path(CGRect(x: originX + cell * Double(columns) * 0.4, y: barY, width: barWidth, height: cell * 0.35)), with: .color(timeLeft < 8 ? palette.hazard : palette.pickupAlt))
        for life in 0..<max(0, lives - 1) {
            let icon = CGRect(x: originX + Double(life) * cell * 0.8, y: barY - cell * 0.1, width: cell * 0.55, height: cell * 0.55)
            drawFrog(in: icon, context: &context)
        }
    }

    private func drawFrog(in frame: CGRect, context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.08)), with: .color(palette.player))
        for x in [frame.minX + frame.width * 0.1, frame.maxX - frame.width * 0.28] {
            context.fill(Path(ellipseIn: CGRect(x: x, y: frame.minY, width: frame.width * 0.18, height: frame.width * 0.18)), with: .color(palette.playerHighlight))
            context.fill(Path(CGRect(x: x, y: frame.maxY - frame.height * 0.2, width: frame.width * 0.18, height: frame.height * 0.2)), with: .color(palette.player))
        }
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadUpPressed: hop(dx: 0, dy: -1)
        case .dpadDownPressed: hop(dx: 0, dy: 1)
        case .dpadLeftPressed: hop(dx: -1, dy: 0)
        case .dpadRightPressed: hop(dx: 1, dy: 0)
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
        homes.removeAll()
        pauseTimer = 0
        buildLanes()
        respawn()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Frog Hop's native palette.
    static let frogHop = GamePalette(
        background: Color(hex: "#15171C"),   // road
        guide: Color(hex: "#123E6B"),        // river, home bays
        player: Color(hex: "#5BE35B"),       // frog
        playerHighlight: .white,             // eyes, lane lines, headlights
        pickup: Color(hex: "#8B5A2B"),       // logs
        pickupAlt: Color(hex: "#6BCB77"),    // time bar, riverbank
        hazard: Color(hex: "#E63946"),       // cars
        hazardAlt: Color(hex: "#FFB703"),    // cars
        outline: Color(hex: "#3C2A4D"),      // safe strips
        spectrum: [Color(hex: "#5BE35B"), Color(hex: "#8B5A2B")]
    )
}
