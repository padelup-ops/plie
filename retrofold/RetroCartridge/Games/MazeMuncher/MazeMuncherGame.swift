// MazeMuncherGame.swift
// RetroCartridge
//
// Maze Muncher: clear the maze of pellets while three ghosts hunt you, one
// chasing, one heading you off and one wandering. Power pellets turn the
// tables for a few seconds, and eaten ghosts are worth more in a row. The
// middle row is a tunnel from one edge to the other.

import SwiftUI

final class MazeMuncherGame: PixelGameProtocol {
    var gameType: GameType = .mazeMuncher
    var gameState: GameState = .menu
    var score: Int = 0
    var level: Int = 1
    var highScore: Int = 0
    var mode: GameMode = .standard
    var palette: GamePalette = .mazeMuncher
    var rng = GameRNG()
    var pendingSounds: [GameSound] = []

    // MARK: - Types

    struct Tile: Hashable {
        var x: Int
        var y: Int
    }

    enum Direction: CaseIterable {
        case up, down, left, right

        var dx: Int { self == .left ? -1 : (self == .right ? 1 : 0) }
        var dy: Int { self == .up ? -1 : (self == .down ? 1 : 0) }

        var reversed: Direction {
            switch self {
            case .up: return .down
            case .down: return .up
            case .left: return .right
            case .right: return .left
            }
        }
    }

    /// Something that moves tile by tile, drawn gliding between tiles.
    struct Mover {
        var tile: Tile
        var previous: Tile
        var heading: Direction
        /// Time since the last step.
        var timer: TimeInterval = 0
    }

    struct Ghost {
        var mover: Mover
        /// Seconds before it leaves its spot at the start of a life.
        var releaseTimer: TimeInterval
        /// Seconds before an eaten ghost comes back.
        var respawnTimer: TimeInterval = 0
    }

    // MARK: - Maze

    /// `#` wall, `-` ghost-house door (a wall), `.` pellet, `o` power
    /// pellet, `P` start, `G` ghosts' spot, space an empty path. Row 9 wraps.
    static let layout: [String] = [
        "###################",
        "#o.......#.......o#",
        "#.##.###.#.###.##.#",
        "#.................#",
        "#.##.#.#####.#.##.#",
        "#....#...#...#....#",
        "####.### # ###.####",
        "   #.#   G   #.#   ",
        "####.# ##-## #.####",
        "    .  #   #  .    ",
        "####.# ##### #.####",
        "   #.#       #.#   ",
        "####.# ##### #.####",
        "#........#........#",
        "#.##.###.#.###.##.#",
        "#o.#.....P.....#.o#",
        "##.#.#.#####.#.#.##",
        "#....#...#...#....#",
        "###################"
    ]

    let width = MazeMuncherGame.layout[0].count
    let height = MazeMuncherGame.layout.count
    let walls: Set<Tile>
    let doors: Set<Tile>
    let start: Tile
    let ghostSpot: Tile

    // MARK: - State

    var pellets: Set<Tile> = []
    var powerPellets: Set<Tile> = []
    var player: Mover
    var wanted: Direction = .left
    var ghosts: [Ghost] = []
    var lives = 3
    /// Seconds the ghosts stay frightened.
    var frightenedTimer: TimeInterval = 0
    /// Ghosts eaten during the current fright, for the rising bonus.
    var ghostCombo = 0
    /// A short pause after losing a life or clearing the maze.
    var pauseTimer: TimeInterval = 0
    private var clock: TimeInterval = 0

    init() {
        var walls: Set<Tile> = []
        var doors: Set<Tile> = []
        var start = Tile(x: 9, y: 15)
        var ghostSpot = Tile(x: 9, y: 7)
        for (y, row) in Self.layout.enumerated() {
            for (x, character) in row.enumerated() {
                let tile = Tile(x: x, y: y)
                switch character {
                case "#": walls.insert(tile)
                case "-": doors.insert(tile)
                case "P": start = tile
                case "G": ghostSpot = tile
                default: break
                }
            }
        }
        self.walls = walls
        self.doors = doors
        self.start = start
        self.ghostSpot = ghostSpot
        player = Mover(tile: start, previous: start, heading: .left)
        reset()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval) {
        clock += deltaTime
        guard gameState == .playing else { return }

        if pauseTimer > 0 {
            pauseTimer -= deltaTime
            return
        }

        if frightenedTimer > 0 {
            frightenedTimer = max(0, frightenedTimer - deltaTime)
        }

        stepPlayer(deltaTime: deltaTime)
        for index in ghosts.indices {
            stepGhost(index, deltaTime: deltaTime)
        }
        checkGhostCollisions()

        if pellets.isEmpty && powerPellets.isEmpty && gameState == .playing {
            level += 1
            score += 500 * level
            emit(.levelUp)
            fillMaze()
            placeActors()
            pauseTimer = 1.2
        }
    }

    /// Seconds per tile for the player.
    private var playerInterval: TimeInterval { max(0.09, 0.15 - Double(level - 1) * 0.008) }

    /// Seconds per tile for a ghost.
    private func ghostInterval(frightened: Bool) -> TimeInterval {
        frightened ? 0.3 : max(0.1, 0.19 - Double(level - 1) * 0.01)
    }

    private func stepPlayer(deltaTime: TimeInterval) {
        player.timer += deltaTime
        guard player.timer >= playerInterval else { return }
        player.timer -= playerInterval
        player.previous = player.tile

        if isOpen(player.tile, toward: wanted) {
            player.heading = wanted
        }
        guard isOpen(player.tile, toward: player.heading) else { return }
        player.tile = neighbor(of: player.tile, toward: player.heading)

        if pellets.remove(player.tile) != nil {
            score += 10
            emit(.chomp)
        } else if powerPellets.remove(player.tile) != nil {
            score += 50
            frightenedTimer = max(2, 6 - Double(level - 1) * 0.5)
            ghostCombo = 0
            // Frightened ghosts turn around
            for index in ghosts.indices where ghosts[index].respawnTimer <= 0 {
                ghosts[index].mover.heading = ghosts[index].mover.heading.reversed
            }
            emit(.powerUp)
        }
    }

    private func stepGhost(_ index: Int, deltaTime: TimeInterval) {
        var ghost = ghosts[index]
        defer { ghosts[index] = ghost }

        if ghost.releaseTimer > 0 {
            ghost.releaseTimer -= deltaTime
            return
        }
        if ghost.respawnTimer > 0 {
            ghost.respawnTimer -= deltaTime
            return
        }

        ghost.mover.timer += deltaTime
        let interval = ghostInterval(frightened: frightenedTimer > 0)
        guard ghost.mover.timer >= interval else { return }
        ghost.mover.timer -= interval
        ghost.mover.previous = ghost.mover.tile

        // Choose among open directions, not turning back unless trapped
        var options = Direction.allCases.filter { isOpen(ghost.mover.tile, toward: $0) && $0 != ghost.mover.heading.reversed }
        if options.isEmpty {
            options = [ghost.mover.heading.reversed]
        }

        let choice: Direction
        if frightenedTimer > 0 || index == 2 {
            choice = options.randomElement(using: &rng) ?? options[0]
        } else {
            let target = chaseTarget(for: index)
            let here = ghost.mover.tile
            choice = options.min { lhs, rhs in
                let left = distance(neighbor(of: here, toward: lhs), target)
                let right = distance(neighbor(of: here, toward: rhs), target)
                return left < right
            } ?? options[0]
        }
        ghost.mover.heading = choice
        ghost.mover.tile = neighbor(of: ghost.mover.tile, toward: choice)
    }

    /// Where a ghost heads: the player, or four tiles ahead of the player.
    private func chaseTarget(for index: Int) -> Tile {
        guard index == 1 else { return player.tile }
        return Tile(x: player.tile.x + player.heading.dx * 4, y: player.tile.y + player.heading.dy * 4)
    }

    private func checkGhostCollisions() {
        for index in ghosts.indices where ghosts[index].releaseTimer <= 0 && ghosts[index].respawnTimer <= 0 {
            let ghost = ghosts[index].mover
            let touches = ghost.tile == player.tile
                || (ghost.tile == player.previous && ghost.previous == player.tile)
            guard touches else { continue }

            if frightenedTimer > 0 {
                ghostCombo += 1
                score += 200 * (1 << (ghostCombo - 1))
                ghosts[index].respawnTimer = 3
                ghosts[index].mover = Mover(tile: ghostSpot, previous: ghostSpot, heading: .left)
                emit(.bonus)
            } else {
                loseLife()
                return
            }
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
            placeActors()
            pauseTimer = 1.2
        }
    }

    // MARK: - Maze helpers

    func neighbor(of tile: Tile, toward direction: Direction) -> Tile {
        Tile(x: (tile.x + direction.dx + width) % width, y: tile.y + direction.dy)
    }

    func isOpen(_ tile: Tile, toward direction: Direction) -> Bool {
        let next = neighbor(of: tile, toward: direction)
        return next.y >= 0 && next.y < height && !walls.contains(next) && !doors.contains(next)
    }

    private func distance(_ a: Tile, _ b: Tile) -> Int {
        let dx = abs(a.x - b.x)
        return min(dx, width - dx) + abs(a.y - b.y)
    }

    private func fillMaze() {
        pellets = []
        powerPellets = []
        for (y, row) in Self.layout.enumerated() {
            for (x, character) in row.enumerated() {
                if character == "." { pellets.insert(Tile(x: x, y: y)) }
                if character == "o" { powerPellets.insert(Tile(x: x, y: y)) }
            }
        }
    }

    private func placeActors() {
        player = Mover(tile: start, previous: start, heading: .left)
        wanted = .left
        frightenedTimer = 0
        ghosts = (0..<3).map { index in
            Ghost(mover: Mover(tile: ghostSpot, previous: ghostSpot, heading: index == 1 ? .right : .left),
                  releaseTimer: Double(index) * 2.5)
        }
    }

    // MARK: - Render

    func render(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        guard gameState != .menu else { return }

        let cell = min(size.width / Double(width), size.height / Double(height))
        let originX = (size.width - cell * Double(width)) / 2
        let originY = (size.height - cell * Double(height)) / 2

        func frame(_ tile: Tile) -> CGRect {
            CGRect(x: originX + Double(tile.x) * cell, y: originY + Double(tile.y) * cell, width: cell, height: cell)
        }

        /// Where a mover is drawn, gliding from its previous tile.
        func glide(_ mover: Mover, interval: TimeInterval) -> CGRect {
            let from = frame(mover.previous)
            let to = frame(mover.tile)
            // No gliding through the tunnel from one edge to the other
            guard abs(mover.previous.x - mover.tile.x) <= 1 else { return to }
            let t = min(1, mover.timer / interval)
            return CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t, width: cell, height: cell)
        }

        // Walls and the ghost-house door
        for wall in walls {
            context.fill(Path(roundedRect: frame(wall).insetBy(dx: cell * 0.12, dy: cell * 0.12), cornerRadius: cell * 0.2), with: .color(palette.hazard.opacity(0.85)))
        }
        for door in doors {
            let f = frame(door)
            context.fill(Path(CGRect(x: f.minX, y: f.midY - 1, width: f.width, height: 2)), with: .color(palette.hazardAlt))
        }

        // Pellets
        for pellet in pellets {
            let f = frame(pellet)
            context.fill(Path(ellipseIn: CGRect(x: f.midX - cell * 0.1, y: f.midY - cell * 0.1, width: cell * 0.2, height: cell * 0.2)), with: .color(palette.pickup))
        }
        if Int(clock * 4) % 2 == 0 {
            for power in powerPellets {
                context.fill(Path(ellipseIn: frame(power).insetBy(dx: cell * 0.2, dy: cell * 0.2)), with: .color(palette.pickupAlt))
            }
        }

        // Ghosts
        let frightened = frightenedTimer > 0
        let fading = frightenedTimer > 0 && frightenedTimer < 1.5 && Int(clock * 8) % 2 == 0
        for (index, ghost) in ghosts.enumerated() where ghost.respawnTimer <= 0 {
            let f = glide(ghost.mover, interval: ghostInterval(frightened: frightened)).insetBy(dx: cell * 0.08, dy: cell * 0.08)
            let body = frightened ? (fading ? palette.playerHighlight : palette.hazardAlt) : palette.spectrumColor(index)
            drawGhost(in: f, color: body, context: &context)
        }

        // The muncher, mouth opening and closing toward its heading
        let f = glide(player, interval: playerInterval).insetBy(dx: cell * 0.06, dy: cell * 0.06)
        let mouth = Double(35 * abs(sin(clock * 12)))
        let facing: Double
        switch player.heading {
        case .right: facing = 0
        case .down: facing = 90
        case .left: facing = 180
        case .up: facing = 270
        }
        var muncher = Path()
        muncher.move(to: CGPoint(x: f.midX, y: f.midY))
        muncher.addArc(center: CGPoint(x: f.midX, y: f.midY), radius: f.width / 2,
                       startAngle: .degrees(facing + mouth), endAngle: .degrees(facing + 360 - mouth), clockwise: false)
        muncher.closeSubpath()
        context.fill(muncher, with: .color(palette.player))
    }

    private func drawGhost(in f: CGRect, color: Color, context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: f.minX, y: f.maxY))
        body.addLine(to: CGPoint(x: f.minX, y: f.midY))
        body.addArc(center: CGPoint(x: f.midX, y: f.midY), radius: f.width / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        body.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        // Wavy hem
        let step = f.width / 4
        for i in 0..<4 {
            let x = f.maxX - Double(i) * step
            body.addLine(to: CGPoint(x: x - step / 2, y: f.maxY - step * 0.6))
            body.addLine(to: CGPoint(x: x - step, y: f.maxY))
        }
        body.closeSubpath()
        context.fill(body, with: .color(color))

        for eyeX in [f.minX + f.width * 0.3, f.minX + f.width * 0.7] {
            let eye = CGRect(x: eyeX - f.width * 0.12, y: f.minY + f.height * 0.3, width: f.width * 0.24, height: f.height * 0.26)
            context.fill(Path(ellipseIn: eye), with: .color(palette.playerHighlight))
            context.fill(Path(ellipseIn: eye.insetBy(dx: eye.width * 0.3, dy: eye.height * 0.3)), with: .color(palette.background))
        }
    }

    // MARK: - Input

    func handleInput(action: GameInputAction) {
        switch action {
        case .dpadUpPressed: wanted = .up
        case .dpadDownPressed: wanted = .down
        case .dpadLeftPressed: wanted = .left
        case .dpadRightPressed: wanted = .right
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
        pauseTimer = 0
        ghostCombo = 0
        fillMaze()
        placeActors()
    }
}

// MARK: - Palette

extension GamePalette {
    /// Maze Muncher's native palette.
    static let mazeMuncher = GamePalette(
        background: .black,
        guide: Color(hex: "#1B1B6B"),
        player: Color(hex: "#FFE600"),       // the muncher
        playerHighlight: .white,             // ghost eyes
        pickup: Color(hex: "#FFB8AE"),       // pellets
        pickupAlt: Color(hex: "#FFB8AE"),    // power pellets
        hazard: Color(hex: "#2121DE"),       // walls
        hazardAlt: Color(hex: "#3A5BFF"),    // frightened ghosts, door
        outline: .black,
        spectrum: [Color(hex: "#FF0000"), Color(hex: "#FFB8FF"), Color(hex: "#00FFFF")] // ghosts
    )
}
