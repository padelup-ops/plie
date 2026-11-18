// AttractPilot.swift
// RetroCartridge
//
// Plays a game by itself for the cover screen's attract mode, the way
// arcade cabinets demo themselves. The pilot only reads game state and
// sends the same inputs a player would, so games need no demo code. It
// plays well but not perfectly, and starts a new round after a game over.

import Foundation

final class AttractPilot {

    /// The game being played.
    let game: any PixelGameProtocol

    /// Time since the pilot started, for its deliberate imperfections.
    private var clock: TimeInterval = 0

    /// Time spent on the game-over screen before starting again.
    private var gameOverTime: TimeInterval = 0

    /// D-Pad directions currently held down.
    private var held: Set<Hold> = []

    private enum Hold {
        case left, right
    }

    /// Whether the thrust (D-Pad up) is held, for Lunar Hinge.
    private var thrusting = false

    /// Time until the next decision, for games played in discrete moves.
    private var decisionTimer: TimeInterval = 0

    /// The pad Lunar Hinge is heading for this attempt.
    private var lunarTarget: Double?

    // Falling Blocks plan for the current piece
    private var lastPieceY = Int.max
    private var targetColumn = 0
    private var rotationsLeft = 0
    private var moveTimer: TimeInterval = 0

    init(type: GameType) {
        game = PixelGameEngine.createGame(type: type)
        game.handleInput(action: .buttonAPressed)
    }

    // MARK: - Frame

    /// Decides this frame's inputs, then advances the game. Sounds are
    /// dropped: attract mode is silent.
    func step(deltaTime: TimeInterval) {
        clock += deltaTime

        switch game.gameState {
        case .gameOver:
            release()
            gameOverTime += deltaTime
            if gameOverTime > 1.5 {
                gameOverTime = 0
                game.handleInput(action: .buttonAPressed)
            }
        case .menu, .paused:
            game.handleInput(action: .buttonAPressed)
            game.resume()
        case .playing:
            steer(deltaTime: deltaTime)
        }

        game.update(deltaTime: deltaTime)
        _ = game.drainSounds()
    }

    private func steer(deltaTime: TimeInterval) {
        switch game {
        case let brickBreaker as BrickBreakerGame:
            steer(brickBreaker)
        case let snake as SnakeGame:
            steer(snake)
        case let racer as RetroRacerGame:
            steer(racer)
        case let blocks as FallingBlocksGame:
            steer(blocks, deltaTime: deltaTime)
        case let invaders as PixelInvadersGame:
            steer(invaders)
        case let mines as MineSweepGame:
            decide(every: 0.12, deltaTime: deltaTime) { steer(mines) }
        case let maze as MazeMuncherGame:
            steer(maze)
        case let frog as FrogHopGame:
            decide(every: 0.25, deltaTime: deltaTime) { steer(frog) }
        case let lander as LunarHingeGame:
            steer(lander)
        case let paddles as PaddleDuelGame:
            steer(paddles)
        case let ship as AstroDriftGame:
            steer(ship)
        case let tower as TowerStackGame:
            steer(tower)
        default:
            break
        }
    }

    /// Runs a decision at a steady pace, like a player pressing buttons.
    private func decide(every interval: TimeInterval, deltaTime: TimeInterval, _ decision: () -> Void) {
        decisionTimer -= deltaTime
        guard decisionTimer <= 0 else { return }
        decisionTimer = interval
        decision()
    }

    /// Presses or releases the thrust, only on change.
    private func setThrust(_ on: Bool) {
        guard on != thrusting else { return }
        thrusting = on
        game.handleInput(action: on ? .dpadUpPressed : .dpadUpReleased)
    }

    private func press(_ direction: MazeMuncherGame.Direction) {
        switch direction {
        case .up: game.handleInput(action: .dpadUpPressed)
        case .down: game.handleInput(action: .dpadDownPressed)
        case .left: game.handleInput(action: .dpadLeftPressed)
        case .right: game.handleInput(action: .dpadRightPressed)
        }
    }

    // MARK: - Held directions

    /// Holds left, right or neither, sending presses and releases only on change.
    private func hold(_ direction: Hold?) {
        for current in held where current != direction {
            game.handleInput(action: current == .left ? .dpadLeftReleased : .dpadRightReleased)
            held.remove(current)
        }
        if let direction, !held.contains(direction) {
            game.handleInput(action: direction == .left ? .dpadLeftPressed : .dpadRightPressed)
            held.insert(direction)
        }
    }

    private func release() {
        hold(nil)
    }

    // MARK: - Brick Breaker

    /// Follows the lowest falling ball, with a slowly wandering aim error
    /// so the paddle misses now and then.
    private func steer(_ game: BrickBreakerGame) {
        let falling = game.balls.filter { $0.vy > 0 }
        guard let ball = falling.max(by: { $0.y < $1.y }) ?? game.balls.first else {
            release()
            return
        }
        let aimError = sin(clock * 0.7) * 0.07
        let target = ball.x + aimError
        if game.paddle.x < target - 0.02 {
            hold(.right)
        } else if game.paddle.x > target + 0.02 {
            hold(.left)
        } else {
            release()
        }
    }

    // MARK: - Snake

    /// Heads for the food along whichever safe direction gets closest.
    private func steer(_ game: SnakeGame) {
        guard let head = game.snake.first else { return }

        let options: [(SnakeGame.Direction, GameInputAction, Int, Int)] = [
            (.up, .dpadUpPressed, 0, -1),
            (.down, .dpadDownPressed, 0, 1),
            (.left, .dpadLeftPressed, -1, 0),
            (.right, .dpadRightPressed, 1, 0)
        ]

        var best: (action: GameInputAction, distance: Int)?
        for (direction, action, dx, dy) in options {
            guard !isReverse(direction, of: game.currentDir) else { continue }
            var x = head.x + dx
            var y = head.y + dy
            if game.wrapsAround {
                x = (x + game.gridSize) % game.gridSize
                y = (y + game.gridSize) % game.gridSize
            }
            let cell = SnakeGame.SnakeSegment(x: x, y: y)
            let isSafe = x >= 0 && x < game.gridSize && y >= 0 && y < game.gridSize
                && !game.obstacles.contains(cell)
                && !game.snake.dropLast().contains(cell)
            guard isSafe else { continue }
            let distance = abs(game.food.x - x) + abs(game.food.y - y)
            if best == nil || distance < best!.distance {
                best = (action, distance)
            }
        }

        if let best {
            game.handleInput(action: best.action)
        }
    }

    private func isReverse(_ direction: SnakeGame.Direction, of current: SnakeGame.Direction) -> Bool {
        switch (direction, current) {
        case (.up, .down), (.down, .up), (.left, .right), (.right, .left):
            return true
        default:
            return false
        }
    }

    // MARK: - Retro Racer

    /// Changes lanes away from traffic that is getting close.
    private func steer(_ game: RetroRacerGame) {
        func isBlocked(_ lane: Int) -> Bool {
            game.obstacles.contains { $0.lane == lane && $0.y > 0.3 && $0.y < 0.95 }
        }
        guard isBlocked(game.targetLane) else { return }

        let lanes = [game.targetLane - 1, game.targetLane + 1].filter { (0...2).contains($0) }
        if let free = lanes.first(where: { !isBlocked($0) }) {
            game.handleInput(action: free < game.targetLane ? .dpadLeftPressed : .dpadRightPressed)
        }
    }

    // MARK: - Falling Blocks

    /// Picks a rotation and column for each new piece, walks it there a step
    /// at a time and drops it.
    private func steer(_ game: FallingBlocksGame, deltaTime: TimeInterval) {
        guard let piece = game.currentPiece else { return }

        // A new piece spawns higher than the last one was
        if piece.y < lastPieceY {
            rotationsLeft = Int.random(in: 0...3)
            targetColumn = Int.random(in: 0...(game.cols - piece.shape.count))
        }
        lastPieceY = piece.y

        moveTimer += deltaTime
        guard moveTimer >= 0.12 else { return }
        moveTimer = 0

        if rotationsLeft > 0 {
            rotationsLeft -= 1
            game.handleInput(action: .buttonAPressed)
        } else if piece.x < targetColumn {
            let before = piece.x
            game.handleInput(action: .dpadRightPressed)
            if game.currentPiece?.x == before { targetColumn = before }
        } else if piece.x > targetColumn {
            let before = piece.x
            game.handleInput(action: .dpadLeftPressed)
            if game.currentPiece?.x == before { targetColumn = before }
        } else {
            game.handleInput(action: .dpadUpPressed)
            lastPieceY = Int.max
        }
    }

    // MARK: - Pixel Invaders

    /// Lines up under the nearest invader and fires, stepping aside from
    /// bombs about to land.
    private func steer(_ game: PixelInvadersGame) {
        if let bomb = game.bombs.first(where: { $0.y > 0.6 && abs($0.x - game.cannonX) < 0.07 }) {
            hold(bomb.x > game.cannonX ? .left : .right)
            return
        }

        let targets = game.alive.indices.filter { game.alive[$0] }.map { Double(game.invaderFrame($0).midX) }
        guard let target = targets.min(by: { abs($0 - game.cannonX) < abs($1 - game.cannonX) }) else {
            release()
            return
        }
        if game.cannonX < target - 0.015 {
            hold(.right)
        } else if game.cannonX > target + 0.015 {
            hold(.left)
        } else {
            release()
            game.handleInput(action: .buttonAPressed)
        }
    }

    // MARK: - Mine Sweep

    /// Walks the cursor to the nearest safe hidden cell and reveals it. (The
    /// pilot peeks at the mines; it's a demo, not a solver.)
    private func steer(_ game: MineSweepGame) {
        guard game.nextBoardTimer <= 0 else { return }
        guard !game.mines.isEmpty else {
            game.handleInput(action: .buttonAPressed)
            return
        }

        var best: MineSweepGame.Cell?
        var bestDistance = Int.max
        for y in 0..<game.rows {
            for x in 0..<game.columns {
                let cell = MineSweepGame.Cell(x: x, y: y)
                guard !game.revealed.contains(cell), !game.mines.contains(cell), !game.flagged.contains(cell) else { continue }
                let distance = abs(cell.x - game.cursor.x) + abs(cell.y - game.cursor.y)
                if distance < bestDistance {
                    best = cell
                    bestDistance = distance
                }
            }
        }
        guard let target = best else { return }

        if target.x != game.cursor.x {
            game.handleInput(action: target.x > game.cursor.x ? .dpadRightPressed : .dpadLeftPressed)
        } else if target.y != game.cursor.y {
            game.handleInput(action: target.y > game.cursor.y ? .dpadDownPressed : .dpadUpPressed)
        } else {
            game.handleInput(action: .buttonAPressed)
        }
    }

    // MARK: - Maze Muncher

    /// Takes the shortest path to the nearest pellet that avoids the ghosts'
    /// reach, or chases frightened ghosts.
    private func steer(_ game: MazeMuncherGame) {
        let start = game.player.tile
        let activeGhosts = game.ghosts.filter { $0.releaseTimer <= 0 && $0.respawnTimer <= 0 }.map(\.mover.tile)
        let frightened = game.frightenedTimer > 1

        var danger: Set<MazeMuncherGame.Tile> = []
        if !frightened {
            for ghost in activeGhosts {
                danger.insert(ghost)
                for direction in MazeMuncherGame.Direction.allCases where game.isOpen(ghost, toward: direction) {
                    danger.insert(game.neighbor(of: ghost, toward: direction))
                }
            }
        }
        let goals = frightened && !activeGhosts.isEmpty
            ? Set(activeGhosts)
            : game.pellets.union(game.powerPellets)

        // Breadth-first search, remembering each tile's first step
        var firstStep: [MazeMuncherGame.Tile: MazeMuncherGame.Direction] = [:]
        var queue: [MazeMuncherGame.Tile] = []
        var head = 0
        for direction in MazeMuncherGame.Direction.allCases where game.isOpen(start, toward: direction) {
            let next = game.neighbor(of: start, toward: direction)
            guard !danger.contains(next), firstStep[next] == nil else { continue }
            firstStep[next] = direction
            queue.append(next)
        }
        while head < queue.count {
            let tile = queue[head]
            head += 1
            if goals.contains(tile), let direction = firstStep[tile] {
                press(direction)
                return
            }
            for direction in MazeMuncherGame.Direction.allCases where game.isOpen(tile, toward: direction) {
                let next = game.neighbor(of: tile, toward: direction)
                guard next != start, !danger.contains(next), firstStep[next] == nil else { continue }
                firstStep[next] = firstStep[tile]
                queue.append(next)
            }
        }
    }

    // MARK: - Frog Hop

    /// Hops up when the next row is safe, heads for an empty home along the
    /// top river lane, and backs off from traffic about to arrive.
    private func steer(_ game: FrogHopGame) {
        let center = game.frogX + 0.5

        func isSafe(row: Int, x: Double) -> Bool {
            if row == game.homeRow {
                let column = Int((x - 0.5).rounded())
                return game.homeColumns.contains(column) && !game.homes.contains(column) && abs(x - 0.5 - Double(column)) < 0.3
            }
            guard let lane = game.lane(atRow: row) else { return true }
            var soon = lane
            soon.phase += lane.speed * 0.35
            switch lane.kind {
            case .road:
                return !game.covers(lane, x: x, margin: -0.35) && !game.covers(soon, x: x, margin: -0.35)
            case .river:
                return game.covers(lane, x: x, margin: 0.25)
            }
        }

        if isSafe(row: game.frogRow - 1, x: center) {
            game.handleInput(action: .dpadUpPressed)
            return
        }

        // Along the top river lane, drift toward an empty home
        if game.frogRow == game.homeRow + 1,
           let home = game.homeColumns.filter({ !game.homes.contains($0) }).min(by: { abs(Double($0) - game.frogX) < abs(Double($1) - game.frogX) }) {
            let step = Double(home) > game.frogX ? 1.0 : -1.0
            if isSafe(row: game.frogRow, x: center + step) {
                game.handleInput(action: step > 0 ? .dpadRightPressed : .dpadLeftPressed)
            }
            return
        }

        // Back off when staying put is about to go wrong
        if !isSafe(row: game.frogRow, x: center), isSafe(row: game.frogRow + 1, x: center) {
            game.handleInput(action: .dpadDownPressed)
        }
    }

    // MARK: - Lunar Hinge

    /// Flies to the nearest pad over the terrain in between, then descends
    /// slowly enough to land. Uses the buttons, not the hinge.
    private func steer(_ game: LunarHingeGame) {
        guard game.outcomeTimer <= 0 else {
            lunarTarget = nil
            setThrust(false)
            release()
            return
        }
        let target = lunarTarget ?? game.pads.min(by: { abs($0.center - game.x) < abs($1.center - game.x) })?.center ?? 0.5
        lunarTarget = target
        guard let pad = game.pads.first(where: { $0.center == target }) else { return }

        // Horizontal: the fastest speed that can still stop at the pad
        let dx = target - game.x
        let wantedVX = (dx < 0 ? -1.0 : 1.0) * min(0.08, (game.sideThrust * abs(dx)).squareRoot())
        if game.vx < wantedVX - 0.003 {
            hold(.right)
        } else if game.vx > wantedVX + 0.003 {
            hold(.left)
        } else {
            release()
        }

        // Vertical: clear the terrain on the way, then settle onto the pad
        let wantedVY: Double
        if abs(dx) < (pad.end - pad.start) / 2 - 0.02 {
            let altitude = game.ground(at: game.x) - (game.y + game.halfHeight)
            wantedVY = min(0.06, 0.015 + 0.3 * altitude)
        } else {
            let low = min(game.x, target)
            let high = max(game.x, target)
            let top = (0...20).map { game.ground(at: low + (high - low) * Double($0) / 20) }.min() ?? 0.6
            wantedVY = max(-0.05, min(0.05, (top - 0.1 - game.y) * 0.8))
        }
        setThrust(game.vy > wantedVY)
    }

    // MARK: - Paddle Duel

    /// Meets the ball on its way down, aiming a little off-center so the
    /// returns vary, with a wandering error so it misses now and then.
    private func steer(_ game: PaddleDuelGame) {
        let target = game.ballVY > 0 ? game.ballX + sin(clock * 0.9) * 0.08 : 0.5
        if game.playerX < target - 0.02 {
            hold(.right)
        } else if game.playerX > target + 0.02 {
            hold(.left)
        } else {
            release()
        }
    }

    // MARK: - Astro Drift

    /// Turns toward the nearest rock and fires once it's lined up.
    private func steer(_ game: AstroDriftGame) {
        guard game.isShipActive, let rock = game.rocks.min(by: {
            distance(from: game, to: $0) < distance(from: game, to: $1)
        }) else {
            release()
            return
        }
        let dx = AstroDriftGame.wrappedOffset(from: game.shipX, to: rock.x)
        let dy = AstroDriftGame.wrappedOffset(from: game.shipY, to: rock.y)
        let wanted = atan2(dx, -dy)
        var turn = (wanted - game.shipAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi }
        if turn < -.pi { turn += 2 * .pi }

        if turn > 0.1 {
            hold(.right)
        } else if turn < -0.1 {
            hold(.left)
        } else {
            release()
            game.handleInput(action: .buttonAPressed)
        }
    }

    private func distance(from game: AstroDriftGame, to rock: AstroDriftGame.Rock) -> Double {
        let dx = AstroDriftGame.wrappedOffset(from: game.shipX, to: rock.x)
        let dy = AstroDriftGame.wrappedOffset(from: game.shipY, to: rock.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Tower Stack

    /// Drops the block when it's over the tower, give or take a wandering
    /// error, so some drops are perfect and some get cut.
    private func steer(_ game: TowerStackGame) {
        let aim = game.top.x + sin(clock * 1.3) * 0.03
        if abs(game.sliderX - aim) < 0.012 {
            game.handleInput(action: .buttonAPressed)
        }
    }
}
