// PixelGameProtocol.swift
// RetroCartridge
//
// Common protocol for all retro mini-games.
// Each game conforms to this protocol and is created by PixelGameEngine.

import SwiftUI

// MARK: - Pixel Game Protocol

/// The contract every mini-game must fulfill to integrate with the game engine.
///
/// The engine calls `update(deltaTime:)` every frame (~60 FPS),
/// then `render(context:size:)` to draw the current state.
/// Input is forwarded from the controller via `handleInput(action:)`.
protocol PixelGameProtocol: AnyObject {
    
    /// The type of this game, used for identification and UI display.
    var gameType: GameType { get }
    
    /// The current state of the game (menu, playing, paused, gameOver).
    var gameState: GameState { get set }
    
    /// The player's current score.
    var score: Int { get }
    
    /// The current level/difficulty.
    var level: Int { get }
    
    /// High score for this game (persisted).
    var highScore: Int { get set }

    /// The rule set being played, one of `gameType.modes`. Set by
    /// `PixelGameEngine` before the first round; games read it on `reset()`.
    var mode: GameMode { get set }

    // MARK: - Appearance

    /// The colors `render` draws with. Starts as the game's native palette
    /// and can be swapped at any time, even mid-round.
    var palette: GamePalette { get set }

    // MARK: - Sound

    /// Sound effects raised since the last frame. Games add to it with
    /// `emit(_:)`; the frame loop empties it with `drainSounds()` and plays
    /// them, so games never depend on the audio system.
    var pendingSounds: [GameSound] { get set }

    // MARK: - Game Loop
    
    /// Called every frame by the game engine.
    /// - Parameter deltaTime: Time elapsed since the last frame, in seconds.
    func update(deltaTime: TimeInterval)
    
    /// Called every frame after `update` to render the current game state.
    /// - Parameters:
    ///   - context: The SwiftUI GraphicsContext for drawing.
    ///   - size: The available canvas size.
    func render(context: inout GraphicsContext, size: CGSize)
    
    // MARK: - Input
    
    /// Called when the player interacts with the controller.
    /// - Parameter action: The input action from D-Pad or buttons.
    func handleInput(action: GameInputAction)
    
    // MARK: - Lifecycle
    
    /// Pause the game (e.g., when device folds or app backgrounds).
    func pause()
    
    /// Resume the game from a paused state.
    func resume()
    
    /// Reset the game to its initial state for a fresh start.
    func reset()
}

// MARK: - Default Implementations

extension PixelGameProtocol {
    
    func pause() {
        if case .playing = gameState {
            gameState = .paused
        }
    }
    
    func resume() {
        if case .paused = gameState {
            gameState = .playing
        }
    }

    /// A random generator for a new round: seeded from the day for a daily
    /// round, unpredictable otherwise. Games call it from `reset()` and draw
    /// every random choice from it.
    func makeRNG() -> GameRNG {
        guard mode.isDaily else { return GameRNG() }
        return GameRNG(seed: DailySeed.seed(for: gameType, day: DailySeed.dayKey()))
    }

    /// Queues a sound effect for the next frame. Duplicates within a frame
    /// are dropped (e.g. several bricks breaking at once play one sound).
    func emit(_ sound: GameSound) {
        guard !pendingSounds.contains(sound), pendingSounds.count < 8 else { return }
        pendingSounds.append(sound)
    }

    /// Returns and clears the queued sound effects.
    func drainSounds() -> [GameSound] {
        guard !pendingSounds.isEmpty else { return [] }
        let sounds = pendingSounds
        pendingSounds = []
        return sounds
    }
}

// MARK: - Hinge input

/// A game that can also be played by folding the device. Apple describes
/// live hinge data as "ideal for driving interactions or effects", so a game
/// may use it as input, but never as the only way to play: every hinge
/// action has a button equivalent, so it works in every pose.
protocol HingeControllable: AnyObject {
    /// Called every frame with the hinge angle in degrees (180 = flat).
    func hingeDidChange(angle: Double)
}
