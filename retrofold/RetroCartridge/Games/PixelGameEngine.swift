// PixelGameEngine.swift
// RetroCartridge

/// Creates game instances for each cartridge.
enum PixelGameEngine {
    
    /// Creates a fresh game of the given type.
    /// - Parameters:
    ///   - type: The cartridge to create.
    ///   - mode: The rule set, one of `type.modes`.
    static func createGame(type: GameType, mode: GameMode = .standard) -> any PixelGameProtocol {
        assert(type.modes.contains(mode), "\(type.rawValue) has no \(mode.id) mode")

        let game: any PixelGameProtocol
        switch type {
        case .brickBreaker:
            game = BrickBreakerGame()
        case .snake:
            game = SnakeGame()
        case .retroRacer:
            game = RetroRacerGame()
        case .fallingBlocks:
            game = FallingBlocksGame()
        case .pixelInvaders:
            game = PixelInvadersGame()
        case .mineSweep:
            game = MineSweepGame()
        case .mazeMuncher:
            game = MazeMuncherGame()
        case .frogHop:
            game = FrogHopGame()
        case .lunarHinge:
            game = LunarHingeGame()
        case .paddleDuel:
            game = PaddleDuelGame()
        case .astroDrift:
            game = AstroDriftGame()
        case .towerStack:
            game = TowerStackGame()
        }
        game.mode = mode
        game.reset()
        return game
    }
}
