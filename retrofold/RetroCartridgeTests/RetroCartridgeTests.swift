// RetroCartridgeTests.swift
// RetroCartridgeTests
//
// Unit tests for app state, display detection and game metadata.

import XCTest
import SwiftUI
import AVFoundation
import CoreText
import StoreKit
import StoreKitTest
@testable import RetroCartridge

final class RetroCartridgeTests: XCTestCase {
    
    func testAppStatInitialValues() {
        let appState = AppState()
        XCTAssertEqual(appState.selectedGameType, .brickBreaker)
        XCTAssertNil(appState.activeGame)
        XCTAssertFalse(appState.isGameActive)
    }
    
    func testPostureManagerDefaults() {
        let posture = PostureManager()
        XCTAssertEqual(posture.currentPosture, .closed)
        XCTAssertFalse(posture.isCompactWidth)
    }
    
    func testPostureManagerDisplayDetection() {
        let posture = PostureManager()
        
        // iPhone Duo outer display, in either orientation
        posture.updateDisplay(fullScreenSize: CGSize(width: 678, height: 466))
        XCTAssertTrue(posture.isCompactWidth)
        XCTAssertEqual(posture.currentPosture, .closed)
        posture.updateDisplay(fullScreenSize: CGSize(width: 466, height: 678))
        XCTAssertTrue(posture.isCompactWidth)
        
        // iPhone Duo inner display
        posture.updateDisplay(fullScreenSize: CGSize(width: 669, height: 871))
        XCTAssertFalse(posture.isCompactWidth)
        XCTAssertEqual(posture.currentPosture, .fullyOpen)
        posture.updateDisplay(fullScreenSize: CGSize(width: 871, height: 669))
        XCTAssertFalse(posture.isCompactWidth)
    }

    /// At launch the window is measured as 0×0 before it has a size. Read
    /// as the outer display, a launch on the inner display looked like an
    /// unfold and inserted the cartridge instead of showing the shelf.
    func testPostureIgnoresTheSizeBeforeLayout() {
        let posture = PostureManager()
        posture.updateDisplay(fullScreenSize: .zero)
        XCTAssertFalse(posture.isCompactWidth)
        XCTAssertEqual(posture.currentPosture, .closed)

        posture.updateDisplay(fullScreenSize: CGSize(width: 678, height: 466))
        posture.updateDisplay(fullScreenSize: .zero)
        XCTAssertTrue(posture.isCompactWidth, "a zero size doesn't move the app off the cover")
    }
    
    func testGameTypeMetadata() {
        for gameType in GameType.allCases {
            XCTAssertFalse(gameType.subtitle.isEmpty)
            XCTAssertFalse(gameType.cartridgeColorHex.isEmpty)
        }
    }
    
    func testSkinThemes() {
        for skin in ConsoleSkinType.allCases {
            let theme = SkinManager.theme(for: skin)
            // Verify theme returns valid values (non-crash)
            _ = theme.bodyColor
            _ = theme.buttonColor
            _ = theme.accentColor
        }
    }

    // MARK: - Cartridges

    func testEveryCartridgeOffersTheStandardModeFirst() {
        for gameType in GameType.allCases {
            XCTAssertEqual(gameType.modes.first, GameMode.standard, gameType.rawValue)
            XCTAssertFalse(gameType.genre.isEmpty)
            XCTAssertFalse(gameType.symbolName.isEmpty)
        }
    }

    func testEngineCreatesGamesInTheirNativePalette() {
        for gameType in GameType.allCases {
            let game = PixelGameEngine.createGame(type: gameType)
            XCTAssertEqual(game.gameType, gameType)
            XCTAssertEqual(game.mode, .standard)
            XCTAssertEqual(game.palette, GamePalette.native(for: gameType))
            XCTAssertEqual(game.gameState, .menu)
        }
    }

    // MARK: - Palette

    func testSpectrumColorWrapsAround() {
        let palette = GamePalette.fallingBlocks
        let count = palette.spectrum.count
        XCTAssertEqual(palette.spectrumColor(0), palette.spectrum[0])
        XCTAssertEqual(palette.spectrumColor(count), palette.spectrum[0])
        XCTAssertEqual(palette.spectrumColor(count + 2), palette.spectrum[2])
        XCTAssertEqual(palette.spectrumColor(-1), palette.spectrum[count - 1])
    }

    func testEmptySpectrumFallsBackToThePlayerColor() {
        var palette = GamePalette.snake
        palette.spectrum = []
        XCTAssertEqual(palette.spectrumColor(3), palette.player)
    }

    // MARK: - Progress

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RetroCartridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // Capture only the Sendable suite name: UserDefaults isn't Sendable.
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testStandardModeKeepsTheOriginalHighScoreKey() {
        XCTAssertEqual(ProgressStore.highScoreKey(for: .snake, mode: .standard), "highScore_Snake")
        let sprint = GameMode(id: "sprint", title: "Sprint", summary: "40 lines.")
        XCTAssertEqual(ProgressStore.highScoreKey(for: .fallingBlocks, mode: sprint), "highScore_Falling Blocks_sprint")
    }

    func testHighScoresSavedBeforeModesCarryOver() {
        let defaults = makeDefaults()
        defaults.set(420, forKey: "highScore_Snake")
        let progress = ProgressStore(defaults: defaults)
        XCTAssertEqual(progress.highScore(for: .snake), 420)
        XCTAssertEqual(progress.highScore(for: .retroRacer), 0)
    }

    func testRecordScoreKeepsOnlyTheBest() {
        let defaults = makeDefaults()
        let progress = ProgressStore(defaults: defaults)
        XCTAssertTrue(progress.recordScore(300, for: .brickBreaker))
        XCTAssertFalse(progress.recordScore(200, for: .brickBreaker))
        XCTAssertFalse(progress.recordScore(300, for: .brickBreaker))
        XCTAssertEqual(progress.highScore(for: .brickBreaker), 300)
        XCTAssertEqual(ProgressStore(defaults: defaults).highScore(for: .brickBreaker), 300)
    }

    func testModesKeepSeparateHighScores() {
        let progress = ProgressStore(defaults: makeDefaults())
        let sprint = GameMode(id: "sprint", title: "Sprint", summary: "40 lines.")
        progress.recordScore(500, for: .fallingBlocks, mode: sprint)
        XCTAssertEqual(progress.highScore(for: .fallingBlocks, mode: sprint), 500)
        XCTAssertEqual(progress.highScore(for: .fallingBlocks), 0)
    }

    func testAchievementsPersist() {
        let defaults = makeDefaults()
        let progress = ProgressStore(defaults: defaults)
        XCTAssertTrue(progress.earn("snake.first-apple"))
        XCTAssertFalse(progress.earn("snake.first-apple"))
        XCTAssertTrue(ProgressStore(defaults: defaults).hasEarned("snake.first-apple"))
        XCTAssertFalse(progress.hasEarned("racer.first-mile"))
    }

    func testAppStateRecordsScoresInItsProgressStore() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.updateHighScore(90, for: .snake)
        XCTAssertEqual(appState.highScore(for: .snake), 90)
        XCTAssertEqual(appState.progress.highScore(for: .snake), 90)
    }

    // MARK: - Library grid

    func testLibraryGridBalancesRows() {
        // Room for three: 2 × 2 rather than 3 + 1
        let metrics = LibraryGridMetrics(itemCount: 4, availableWidth: 600, hasFold: false)
        XCTAssertEqual(metrics.columns, 2)
    }

    func testLibraryGridUsesOneRowWhenEverythingFits() {
        let metrics = LibraryGridMetrics(itemCount: 4, availableWidth: 800, hasFold: true)
        XCTAssertEqual(metrics.columns, 4)
        XCTAssertLessThanOrEqual(metrics.itemWidth, LibraryGridMetrics.maxItemWidth)
    }

    func testLibraryGridPrefersEvenColumnsOnAFoldingDisplay() {
        // Five cartridges with room for four: 3 columns flat-out, 4 with a fold
        XCTAssertEqual(LibraryGridMetrics(itemCount: 5, availableWidth: 760, hasFold: false).columns, 3)
        XCTAssertEqual(LibraryGridMetrics(itemCount: 5, availableWidth: 760, hasFold: true).columns, 4)
        // Three cartridges with room for exactly three: drop to two
        XCTAssertEqual(LibraryGridMetrics(itemCount: 3, availableWidth: 520, hasFold: true).columns, 2)
    }

    func testLibraryGridCartridgesFitTheWidth() {
        for width in stride(from: CGFloat(200), through: 1000, by: 50) {
            for hasFold in [false, true] {
                let metrics = LibraryGridMetrics(itemCount: 6, availableWidth: width, hasFold: hasFold)
                let used = metrics.itemWidth * CGFloat(metrics.columns)
                    + LibraryGridMetrics.spacing * CGFloat(metrics.columns - 1)
                XCTAssertLessThanOrEqual(used, width + 0.001, "width \(width), fold \(hasFold)")
                if hasFold && metrics.columns > 1 {
                    XCTAssertEqual(metrics.columns % 2, 0, "width \(width)")
                }
            }
        }
    }

    // MARK: - Cartridge art

    func testEveryCartridgeLabelIsASixteenPixelSquare() {
        for gameType in GameType.allCases {
            let rows = PixelArt.label(for: gameType).rows
            XCTAssertEqual(rows.count, 16, gameType.rawValue)
            for row in rows {
                XCTAssertEqual(row.count, 16, "\(gameType.rawValue): \(row)")
            }
        }
    }

    func testCartridgeLabelsOnlyUseKnownPixels() {
        for gameType in GameType.allCases {
            let palette = GamePalette.native(for: gameType)
            for character in PixelArt.label(for: gameType).rows.joined() where character != "." {
                XCTAssertNotNil(PixelArt.color(for: character, in: palette), "\(gameType.rawValue): \(character)")
            }
        }
    }

    // MARK: - Screen

    func testScreenSettingsRoundTrip() throws {
        let settings = ScreenSettings(mode: .trinitron, curvature: 0.2, scanlines: 0.9, bleed: 0.4)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ScreenSettings.self, from: data), settings)
        XCTAssertFalse(settings.hasStandardTuning)
        XCTAssertTrue(ScreenSettings(mode: .arcade).hasStandardTuning)
    }

    func testOnlyColorCRTIsFree() {
        XCTAssertNil(ScreenMode.crt.requiredProductID)
        for mode in ScreenMode.allCases where mode != .crt {
            XCTAssertEqual(mode.requiredProductID, ProductIdentifiers.pro)
        }
    }

    // MARK: - Attract mode

    func testAttractPilotPlaysEveryGame() {
        for gameType in GameType.allCases {
            let pilot = AttractPilot(type: gameType)
            var bestScore = 0
            // Thirty seconds at 60 FPS
            for _ in 0..<1_800 {
                pilot.step(deltaTime: 1.0 / 60)
                bestScore = max(bestScore, pilot.game.score)
                XCTAssertTrue(pilot.game.pendingSounds.isEmpty, "attract mode is silent")
            }
            XCTAssertGreaterThan(bestScore, 0, gameType.rawValue)
            XCTAssertNotEqual(pilot.game.gameState, .menu, gameType.rawValue)
        }
    }

    // MARK: - Long play

    /// Every floating point value in a game's stored state that isn't finite.
    private func nonFiniteValues(in value: Any, path: String = "", depth: Int = 0) -> [String] {
        if let number = value as? Double { return number.isFinite ? [] : [path] }
        if let number = value as? CGFloat { return number.isFinite ? [] : [path] }
        guard depth < 5, !(value is GamePalette) else { return [] }
        return Mirror(reflecting: value).children.enumerated().flatMap { index, child in
            nonFiniteValues(in: child.value, path: path + "." + (child.label ?? "\(index)"), depth: depth + 1)
        }
    }

    /// A game's stored state as text, with sets and dictionaries sorted
    /// (their order differs between equal instances), so equal states match.
    private func stateDescription(of value: Any, depth: Int = 0) -> String {
        let mirror = Mirror(reflecting: value)
        guard !mirror.children.isEmpty, depth < 6, !(value is GamePalette) else { return String(describing: value) }
        var parts = mirror.children.map { "\($0.label ?? ""):\(stateDescription(of: $0.value, depth: depth + 1))" }
        if mirror.displayStyle == .set || mirror.displayStyle == .dictionary { parts.sort() }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static let everyInput: [GameInputAction] = [
        .dpadUpPressed, .dpadDownPressed, .dpadLeftPressed, .dpadRightPressed,
        .dpadUpReleased, .dpadDownReleased, .dpadLeftReleased, .dpadRightReleased,
        .buttonAPressed, .buttonAReleased, .buttonBPressed, .buttonBReleased
    ]

    /// A minute of random button mashing in every mode, at uneven frame
    /// times up to the frame loop's 0.05 s cap: no non-finite state, and the
    /// score and level never go backwards within a round.
    func testEveryModeSurvivesAMinuteOfRandomInput() {
        for gameType in GameType.allCases {
            for mode in gameType.modes {
                let label = "\(gameType.rawValue) / \(mode.id)"
                let game = PixelGameEngine.createGame(type: gameType, mode: mode)
                var rng = GameRNG(seed: 42)
                var lastScore = 0
                var lastLevel = 1
                var rounds = 0
                for frame in 0..<3_600 {
                    switch game.gameState {
                    case .menu, .gameOver:
                        game.handleInput(action: .buttonAPressed)
                        rounds += 1
                        lastScore = 0
                        lastLevel = game.level
                    case .paused:
                        game.resume()
                    case .playing:
                        if rng.next() % 6 == 0 {
                            game.handleInput(action: Self.everyInput[Int(rng.next() % UInt64(Self.everyInput.count))])
                        }
                    }
                    game.update(deltaTime: [1.0 / 60, 1.0 / 30, 0.05][Int(rng.next() % 3)])
                    _ = game.drainSounds()

                    if case .gameOver(let final) = game.gameState {
                        XCTAssertEqual(final, game.score, label)
                    } else if game.gameState == .playing {
                        XCTAssertGreaterThanOrEqual(game.score, lastScore, label)
                        XCTAssertGreaterThanOrEqual(game.level, lastLevel, label)
                        lastScore = game.score
                        lastLevel = game.level
                    }
                    if frame % 30 == 0 {
                        let bad = nonFiniteValues(in: game)
                        XCTAssertTrue(bad.isEmpty, "\(label): \(bad)")
                        if !bad.isEmpty { break }
                    }
                }
                XCTAssertGreaterThan(rounds, 0, label)
            }
        }
    }

    /// Two daily rounds played with the same inputs stay identical in every
    /// cartridge, so everyone really gets the same round.
    func testDailyRoundsPlayOutTheSameInEveryGame() {
        for gameType in GameType.allCases {
            guard let daily = gameType.modes.first(where: \.isDaily) else {
                XCTFail("\(gameType.rawValue) has no daily mode")
                continue
            }
            var traces: [[String]] = []
            for _ in 0..<2 {
                let game = PixelGameEngine.createGame(type: gameType, mode: daily)
                var rng = GameRNG(seed: 99)
                var trace = [stateDescription(of: game)]
                game.handleInput(action: .buttonAPressed)
                for frame in 0..<1_800 {
                    if case .gameOver = game.gameState {
                        game.handleInput(action: .buttonAPressed)
                    } else if rng.next() % 8 == 0 {
                        game.handleInput(action: Self.everyInput[Int(rng.next() % UInt64(Self.everyInput.count))])
                    }
                    game.update(deltaTime: 1.0 / 60)
                    _ = game.drainSounds()
                    if frame % 120 == 0 {
                        trace.append(stateDescription(of: game))
                    }
                }
                traces.append(trace)
            }
            XCTAssertEqual(traces[0], traces[1], gameType.rawValue)
        }
    }

    /// A shot on the seam between two shield blocks touches both. The one
    /// eroded used to be the first in the set's order, which differs
    /// between instances and devices, so daily rounds played out
    /// differently. However the set was built, the same block goes.
    func testPixelInvadersErodesTheSameShieldBlockEverywhere() {
        let reference = PixelInvadersGame()
        let blocks = Array(reference.shields)
        let seam = PixelInvadersGame.Shot(
            x: reference.shieldCenters[0] - reference.shieldBlockWidth * 2,
            y: reference.shieldTop + reference.shieldBlockHeight / 2
        )
        var eroded: Set<Set<PixelInvadersGame.ShieldBlock>> = []
        for variant in 0..<24 {
            let game = PixelInvadersGame()
            // The same blocks, inserted in different orders and capacities
            var shields = Set<PixelInvadersGame.ShieldBlock>(minimumCapacity: blocks.count + variant * 7)
            for block in variant.isMultiple(of: 2) ? blocks : blocks.reversed() {
                shields.insert(block)
            }
            game.shields = shields
            XCTAssertTrue(game.hitShield(at: seam))
            XCTAssertEqual(game.shields.count, blocks.count - 1)
            eroded.insert(Set(blocks).subtracting(game.shields))
        }
        XCTAssertEqual(eroded, [[PixelInvadersGame.ShieldBlock(column: 0, row: 0)]])
    }

    /// A shot fired at full speed hits even the smallest rock when frames
    /// run long (the cover plays at 30 FPS, and dropped frames reach the
    /// 0.05 s cap), instead of skipping over it between two frames.
    func testAstroDriftShotsDontSkipOverRocks() {
        for deltaTime in [1.0 / 60, 1.0 / 30, 0.05] {
            for offset in 0..<40 {
                let game = AstroDriftGame()
                game.handleInput(action: .buttonAPressed)
                game.shieldTimer = 100
                let rockY = 0.30 + Double(offset) * 0.004
                game.rocks = [AstroDriftGame.Rock(x: 0.5, y: rockY, vx: 0, vy: 0, size: 1, spin: 0, outline: Array(repeating: 1, count: 9))]
                // Fire while flying forward at top speed, then move the ship
                // out of the way; the shot keeps the ship's speed
                game.shipVY = -game.maxShipSpeed
                game.handleInput(action: .buttonAPressed)
                game.shipVY = 0
                game.shipY = 0.9
                for _ in 0..<10 {
                    game.update(deltaTime: deltaTime)
                }
                XCTAssertTrue(game.rocks.isEmpty, "rock at \(rockY) missed at \(deltaTime) s frames")
            }
        }
    }

    // MARK: - Pause menu and eject

    private func makePausedAppState() -> AppState {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.startGame(type: .snake)
        appState.activeGame?.handleInput(action: .buttonAPressed)
        appState.activeGame?.pause()
        return appState
    }

    func testPauseMenuIsActiveOnlyWhilePaused() {
        let appState = makePausedAppState()
        XCTAssertTrue(appState.isPauseMenuActive)
        appState.activeGame?.resume()
        XCTAssertFalse(appState.isPauseMenuActive)
    }

    func testPauseMenuSelectionWraps() {
        let appState = makePausedAppState()
        XCTAssertEqual(appState.pauseMenuSelection, .resume)
        PauseMenu.handle(.dpadUpPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.pauseMenuSelection, .eject)
        PauseMenu.handle(.dpadDownPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.pauseMenuSelection, .resume)
    }

    func testPauseMenuResumesWithB() {
        let appState = makePausedAppState()
        PauseMenu.handle(.buttonBPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.activeGame?.gameState, .playing)
    }

    func testPauseMenuCyclesOnlyUnlockedScreens() {
        let appState = makePausedAppState()
        // AppState persists screen settings in the app's own defaults, so
        // put back whatever was set on this simulator
        let original = appState.screenSettings
        defer { appState.screenSettings = original }
        appState.screenSettings = .standard
        appState.pauseMenuSelection = .screen
        XCTAssertEqual(
            PauseMenu.handle(.dpadRightPressed, appState: appState, screenModes: [.crt], currentScreen: .crt),
            .ignored
        )
        PauseMenu.handle(.dpadLeftPressed, appState: appState, screenModes: [.crt, .lcd, .arcade], currentScreen: .crt)
        XCTAssertEqual(appState.screenSettings.mode, .arcade)
    }

    func testEjectingKeepsTheGameUntilThePowerOffEnds() {
        let appState = makePausedAppState()
        appState.pauseMenuSelection = .eject
        PauseMenu.handle(.buttonAPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertTrue(appState.isEjecting)
        XCTAssertNotNil(appState.activeGame)
        XCTAssertFalse(appState.isPauseMenuActive)
        appState.endGame()
        XCTAssertFalse(appState.isEjecting)
        XCTAssertNil(appState.activeGame)
    }

    // MARK: - Variety infrastructure

    func testModesAreTheSameRuleSetWhenTheirIdsMatch() {
        let marathon = GameMode(id: "standard", title: "Marathon", summary: "Endless.")
        XCTAssertEqual(marathon, .standard)
        XCTAssertEqual(Set([marathon, .standard]).count, 1)
        XCTAssertNotEqual(GameMode.daily, .standard)
    }

    func testDailyRoundsAreDealtTheSameWay() {
        func pieces(_ game: FallingBlocksGame) -> [Int] {
            (0..<12).map { _ in game.randomPiece().colorIndex }
        }
        let first = PixelGameEngine.createGame(type: .fallingBlocks, mode: .daily) as! FallingBlocksGame
        let second = PixelGameEngine.createGame(type: .fallingBlocks, mode: .daily) as! FallingBlocksGame
        XCTAssertEqual(pieces(first), pieces(second))
    }

    func testDailySeedDependsOnGameAndDay() {
        let day = "2026-09-29"
        XCTAssertEqual(DailySeed.seed(for: .snake, day: day), DailySeed.seed(for: .snake, day: day))
        XCTAssertNotEqual(DailySeed.seed(for: .snake, day: day), DailySeed.seed(for: .retroRacer, day: day))
        XCTAssertNotEqual(DailySeed.seed(for: .snake, day: day), DailySeed.seed(for: .snake, day: "2026-09-30"))
        XCTAssertEqual(DailySeed.dayKey(for: Date(timeIntervalSince1970: 0)), "1970-01-01")
    }

    func testDailyHighScoresStartOverEachDay() {
        let defaults = makeDefaults()
        var day = "2026-09-29"
        let progress = ProgressStore(defaults: defaults, today: { day })
        XCTAssertTrue(progress.recordScore(500, for: .snake, mode: .daily))
        XCTAssertEqual(progress.highScore(for: .snake, mode: .daily), 500)

        day = "2026-09-30"
        XCTAssertEqual(progress.highScore(for: .snake, mode: .daily), 0)
        XCTAssertTrue(progress.recordScore(100, for: .snake, mode: .daily))
        XCTAssertEqual(ProgressStore(defaults: defaults, today: { day }).highScore(for: .snake, mode: .daily), 100)
    }

    func testModeCyclesOnlyOnTheTitleAndGameOverScreens() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.startGame(type: .snake)
        XCTAssertTrue(appState.cycleMode(by: 1))
        XCTAssertEqual(appState.activeGame?.mode, GameType.snake.modes[1])
        XCTAssertEqual(appState.activeGame?.gameState, .menu)

        appState.activeGame?.handleInput(action: .buttonAPressed)
        XCTAssertFalse(appState.cycleMode(by: 1))
    }

    func testPaletteChoiceRecolorsTheRunningGame() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        let original = appState.paletteChoice
        defer { appState.paletteChoice = original }

        appState.paletteChoice = .original
        appState.startGame(type: .snake)
        XCTAssertEqual(appState.activeGame?.palette, GamePalette.snake)
        appState.paletteChoice = .dmgGreen
        XCTAssertEqual(appState.activeGame?.palette, GamePalette.dmgGreen)
    }

    func testPauseMenuCyclesPalettes() {
        let appState = makePausedAppState()
        let original = appState.paletteChoice
        defer { appState.paletteChoice = original }

        appState.paletteChoice = .original
        appState.pauseMenuSelection = .palette
        PauseMenu.handle(.dpadRightPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.paletteChoice, PaletteChoice.allCases[1])
    }

    // MARK: - Brick Breaker

    func testEveryBrickBreakerWallCanBeCleared() {
        let game = BrickBreakerGame()
        for index in BrickBreakerGame.levels.indices {
            game.level = index + 1
            game.setupLevel()
            XCTAssertTrue(game.bricks.contains { $0.kind != .steel }, "level \(index + 1)")
            XCTAssertTrue(game.bricks.allSatisfy { $0.x < game.cols && $0.y < game.rows }, "level \(index + 1)")
        }
    }

    func testBallWaitsOnThePaddleUntilLaunched() {
        let game = BrickBreakerGame()
        game.handleInput(action: .buttonAPressed)
        XCTAssertEqual(game.gameState, .playing)
        XCTAssertNotNil(game.balls.first?.stuckOffset)

        game.handleInput(action: .buttonAPressed)
        XCTAssertNil(game.balls.first?.stuckOffset)
        XCTAssertLessThan(game.balls.first?.vy ?? 0, 0)
    }

    func testBallLaunchesByItselfAfterAWhile() {
        let game = BrickBreakerGame()
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<180 {
            game.update(deltaTime: 1.0 / 60)
        }
        XCTAssertNil(game.balls.first?.stuckOffset)
    }

    func testToughBricksTakeTwoHits() {
        let game = BrickBreakerGame()
        game.level = 4 // Armored core
        game.setupLevel()
        let tough = game.bricks.firstIndex { $0.kind == .tough }!
        game.hitBrick(tough)
        XCTAssertFalse(game.bricks[tough].isDestroyed)
        game.hitBrick(tough)
        XCTAssertTrue(game.bricks[tough].isDestroyed)

        let steel = game.bricks.firstIndex { $0.kind == .steel }
        XCTAssertNil(steel, "Armored core has no steel")
    }

    func testSteelBricksNeverBreak() {
        let game = BrickBreakerGame()
        game.level = 5 // Steel gates
        game.setupLevel()
        let steel = game.bricks.firstIndex { $0.kind == .steel }!
        for _ in 0..<5 {
            game.hitBrick(steel)
        }
        XCTAssertFalse(game.bricks[steel].isDestroyed)
    }

    // MARK: - Snake

    func testWrapModeCarriesTheSnakeAcrossTheEdge() {
        let game = PixelGameEngine.createGame(type: .snake, mode: .snakeWrap) as! SnakeGame
        game.handleInput(action: .buttonAPressed)
        game.snake = [SnakeGame.SnakeSegment(x: 19, y: 3), SnakeGame.SnakeSegment(x: 18, y: 3)]
        game.food = SnakeGame.SnakeSegment(x: 5, y: 15)
        game.moveSnake()
        XCTAssertEqual(game.gameState, .playing)
        XCTAssertEqual(game.snake.first, SnakeGame.SnakeSegment(x: 0, y: 3))
    }

    func testClassicModeWallsAreDeadly() {
        let game = PixelGameEngine.createGame(type: .snake, mode: .snakeClassic) as! SnakeGame
        game.handleInput(action: .buttonAPressed)
        game.snake = [SnakeGame.SnakeSegment(x: 19, y: 3), SnakeGame.SnakeSegment(x: 18, y: 3)]
        game.moveSnake()
        XCTAssertNotEqual(game.gameState, .playing)
    }

    func testMazesLeaveTheStartClear() {
        let start = (8...19).map { SnakeGame.SnakeSegment(x: $0, y: 10) }
        for layout in 0..<4 {
            let walls = SnakeGame.maze(layout)
            XCTAssertFalse(walls.isEmpty)
            XCTAssertTrue(walls.isDisjoint(with: start), "layout \(layout)")
        }
    }

    // MARK: - Falling Blocks

    func testSprintEndsAtFortyLines() {
        let game = PixelGameEngine.createGame(type: .fallingBlocks, mode: .blocksSprint) as! FallingBlocksGame
        game.handleInput(action: .buttonAPressed)
        game.linesClearedTotal = 39
        game.grid[game.rows - 1] = Array(repeating: 0, count: game.cols)
        game.clearLines()
        XCTAssertNotEqual(game.gameState, .playing)
        XCTAssertGreaterThan(game.score, 0)
    }

    func testUltraEndsAfterTwoMinutes() {
        let game = PixelGameEngine.createGame(type: .fallingBlocks, mode: .blocksUltra) as! FallingBlocksGame
        game.handleInput(action: .buttonAPressed)
        game.elapsed = game.ultraDuration - 0.01
        game.update(deltaTime: 0.02)
        XCTAssertNotEqual(game.gameState, .playing)
    }

    func testThreePiecesAreAlwaysPreviewed() {
        let game = FallingBlocksGame()
        XCTAssertGreaterThanOrEqual(game.upcoming.count, game.previewCount)
        game.handleInput(action: .buttonAPressed)
        game.handleInput(action: .dpadUpPressed)
        XCTAssertGreaterThanOrEqual(game.upcoming.count, game.previewCount)
    }

    // MARK: - Retro Racer

    func testCoinsScore() {
        let game = RetroRacerGame()
        game.handleInput(action: .buttonAPressed)
        game.coins = [RetroRacerGame.Coin(lane: game.targetLane, y: 0.82)]
        game.update(deltaTime: 1.0 / 60)
        XCTAssertTrue(game.coins.isEmpty)
        XCTAssertGreaterThanOrEqual(game.score, 10)
    }

    // MARK: - New cartridges

    func testEveryCartridgeHasItsOwnPaletteArtAndGame() {
        for gameType in GameType.allCases {
            let game = PixelGameEngine.createGame(type: gameType)
            XCTAssertEqual(game.gameType, gameType)
            XCTAssertEqual(game.palette, GamePalette.native(for: gameType))
            XCTAssertEqual(PixelArt.label(for: gameType).rows.count, 16)
        }
    }

    func testInvaderShotScores() {
        let game = PixelInvadersGame()
        game.handleInput(action: .buttonAPressed)
        let target = game.invaderFrame(game.rows * game.columns - 1)
        game.shot = PixelInvadersGame.Shot(x: Double(target.midX), y: Double(target.maxY) + 0.01)
        game.update(deltaTime: 1.0 / 60)
        XCTAssertFalse(game.alive[game.rows * game.columns - 1])
        XCTAssertGreaterThan(game.score, 0)
    }

    func testFirstRevealIsNeverAMine() {
        for seed in 0..<20 {
            let game = MineSweepGame()
            game.rng = GameRNG(seed: UInt64(seed))
            game.handleInput(action: .buttonAPressed)
            game.rng = GameRNG(seed: UInt64(seed))
            game.reveal(game.cursor)
            XCTAssertEqual(game.gameState, .playing)
            XCTAssertEqual(game.mines.count, game.mineCount)
            XCTAssertEqual(game.adjacentMines(game.cursor), 0)
            XCTAssertGreaterThan(game.revealed.count, 1, "an empty cell opens its area")
        }
    }

    func testEveryMazePelletIsReachable() {
        let game = MazeMuncherGame()
        var seen: Set<MazeMuncherGame.Tile> = [game.start]
        var queue = [game.start]
        while let tile = queue.popLast() {
            for direction in MazeMuncherGame.Direction.allCases where game.isOpen(tile, toward: direction) {
                let next = game.neighbor(of: tile, toward: direction)
                if seen.insert(next).inserted { queue.append(next) }
            }
        }
        XCTAssertTrue(game.pellets.isSubset(of: seen))
        XCTAssertTrue(game.powerPellets.isSubset(of: seen))
        XCTAssertTrue(seen.contains(game.ghostSpot))
    }

    func testFrogScoresForNewRows() {
        let game = FrogHopGame()
        game.handleInput(action: .buttonAPressed)
        game.lanes.removeAll { $0.row == game.startRow - 1 }
        game.handleInput(action: .dpadUpPressed)
        XCTAssertEqual(game.frogRow, game.startRow - 1)
        XCTAssertEqual(game.score, 10)
        game.handleInput(action: .dpadDownPressed)
        game.handleInput(action: .dpadUpPressed)
        XCTAssertEqual(game.score, 10, "only new rows score")
    }

    func testFrogDrownsOffTheLogs() {
        let game = FrogHopGame()
        game.handleInput(action: .buttonAPressed)
        game.frogRow = 2
        game.lanes = game.lanes.map { lane in
            var empty = lane
            if lane.kind == .river { empty.count = 0 }
            return empty
        }
        let lives = game.lives
        game.update(deltaTime: 1.0 / 60)
        XCTAssertEqual(game.lives, lives - 1)
    }

    func testGentleLandingOnAPadScores() {
        let game = LunarHingeGame()
        game.handleInput(action: .buttonAPressed)
        let pad = game.pads[0]
        game.x = pad.center
        // Feet just touching the pad
        game.y = pad.height - game.halfHeight + 0.0001
        game.vx = 0
        game.vy = 0.03
        game.update(deltaTime: 1.0 / 60)
        XCTAssertNotNil(game.landedPad)
        XCTAssertGreaterThan(game.score, 0)
        XCTAssertEqual(game.level, 2)
    }

    func testHardLandingCrashes() {
        let game = LunarHingeGame()
        game.handleInput(action: .buttonAPressed)
        let pad = game.pads[0]
        game.x = pad.center
        game.y = pad.height - game.halfHeight + 0.0001
        game.vy = 0.2
        game.update(deltaTime: 1.0 / 60)
        XCTAssertTrue(game.crashed)
        XCTAssertEqual(game.lives, 2)
    }

    func testFoldingTheHingeThrusts() {
        let game = LunarHingeGame()
        game.handleInput(action: .buttonAPressed)
        game.hingeDidChange(angle: 120)
        XCTAssertEqual(game.hingeThrust, 0, "the first reading sets the rest angle")
        game.hingeDidChange(angle: 105)
        XCTAssertEqual(game.hingeThrust, 0.5, accuracy: 0.001)
        game.hingeDidChange(angle: 60)
        XCTAssertEqual(game.hingeThrust, 1)
        game.hingeDidChange(angle: 150)
        XCTAssertEqual(game.hingeThrust, 0, "opening further raises the rest angle")
    }

    // MARK: - Achievements

    func testAchievementIdsAreUniqueAndStable() {
        let ids = GameType.allCases.flatMap { Achievement.all(for: $0).map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Achievement.all(for: .snake).first?.id, "Snake.first-points")
    }

    func testFirstPointsAreAnnouncedOnce() {
        let progress = ProgressStore(defaults: makeDefaults())
        let game = SnakeGame()
        game.handleInput(action: .buttonAPressed)
        XCTAssertTrue(AchievementTracker.check(game, progress: progress).isEmpty)

        game.score = 10
        XCTAssertEqual(AchievementTracker.check(game, progress: progress).map(\.title), ["OFF THE MARK"])
        XCTAssertTrue(AchievementTracker.check(game, progress: progress).isEmpty)
        XCTAssertEqual(AchievementTracker.tally(for: .snake, progress: progress).earned, 1)
    }

    func testExplorerNeedsARoundInEveryMode() {
        let progress = ProgressStore(defaults: makeDefaults())
        let modes = GameType.retroRacer.modes
        for (index, mode) in modes.enumerated() {
            let game = PixelGameEngine.createGame(type: .retroRacer, mode: mode)
            game.gameState = .gameOver(score: 0)
            let earned = AchievementTracker.check(game, progress: progress).map(\.title)
            XCTAssertEqual(earned.contains("EXPLORER"), index == modes.count - 1)
            if mode.isDaily {
                XCTAssertTrue(earned.contains("DAILY PLAYER"))
            }
        }
    }

    // MARK: - Sound packs and skins

    func testSoundPacksRevoiceNotes() {
        let patch = SynthPatch.levelUp.definition
        XCTAssertEqual(SoundPack.classic.voice(patch).notes.map(\.startHz), patch.notes.map(\.startHz))
        XCTAssertTrue(SoundPack.mellow.voice(patch).notes.allSatisfy { $0.waveform == .triangle })
        XCTAssertLessThan(SoundPack.arcade.voice(patch).notes[0].startHz, patch.notes[0].startHz)
        XCTAssertNil(SoundPack.classic.requiredProductID)
    }

    func testEveryPaidSkinComesWithPro() {
        XCTAssertNil(ConsoleSkinType.classicGrey.requiredProductID)
        XCTAssertEqual(ProductIdentifiers.skins(unlockedBy: ProductIdentifiers.pro), ConsoleSkinType.allCases.filter { $0 != .classicGrey })
    }

    // MARK: - Unfolding

    func testUnfoldingInsertsTheCartridgePickedOnTheCover() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.isIntroVisible = false
        appState.selectedGameType = .snake
        appState.insertCartridgeOnUnfold(isUnlocked: true)
        XCTAssertEqual(appState.activeGame?.gameType, .snake)
    }

    func testUnfoldingResumesThePausedCartridgeWhenThePickIsUnchanged() throws {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.isIntroVisible = false
        appState.startGame(type: .snake)
        let paused = try XCTUnwrap(appState.activeGame)
        appState.pauseActiveGame()

        appState.insertCartridgeOnUnfold(isUnlocked: true)
        XCTAssertTrue(appState.activeGame === paused)
    }

    func testUnfoldingSwapsInANewPickAndKeepsTheOldScore() throws {
        let progress = ProgressStore(defaults: makeDefaults())
        let appState = AppState(progress: progress)
        appState.isIntroVisible = false
        appState.startGame(type: .snake)
        let paused = try XCTUnwrap(appState.activeGame as? SnakeGame)
        paused.score = 120
        appState.pauseActiveGame()

        // Folded, the player swipes to another cartridge on the cover
        appState.selectedGameType = .brickBreaker
        appState.insertCartridgeOnUnfold(isUnlocked: true)
        XCTAssertEqual(appState.activeGame?.gameType, .brickBreaker)
        XCTAssertFalse(appState.activeGame === paused)
        XCTAssertEqual(appState.highScore(for: .snake), 120)
    }

    func testUnfoldingOnALockedPickEndsThePausedRoundAndShowsTheShelf() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.isIntroVisible = false
        appState.startGame(type: .snake)
        appState.pauseActiveGame()

        appState.selectedGameType = .lunarHinge
        appState.insertCartridgeOnUnfold(isUnlocked: false)
        XCTAssertNil(appState.activeGame)
        XCTAssertEqual(appState.selectedGameType, .lunarHinge)
    }

    // MARK: - Menu themes

    func testClassicGreyKeepsTheClassicMenu() {
        XCTAssertEqual(SkinTheme.classicGrey.menu, .classic)
    }

    func testOnlyTheDefaultMenuSitsInTheGreyCase() {
        XCTAssertEqual(MenuTheme.classic.shell, .greyCase)
        for skin in ConsoleSkinType.allCases where skin != .classicGrey {
            XCTAssertNil(SkinManager.theme(for: skin).menu.shell, skin.rawValue)
        }
    }

    func testEveryPaidSkinHasItsOwnAccent() {
        let paid = ConsoleSkinType.allCases.filter { $0 != .classicGrey }
        let accents = paid.map { hex(SkinManager.theme(for: $0).menu.accent) }
        XCTAssertEqual(Set(accents).count, paid.count)
        XCTAssertFalse(accents.contains(hex(MenuTheme.classic.accent)))
    }

    func testEveryMenuAccentReadsOnItsSurfaces() {
        for skin in ConsoleSkinType.allCases {
            let menu = SkinManager.theme(for: skin).menu
            // Text in the accent on the panels (WCAG AA)
            for surface in [menu.panelTop, menu.panelBottom] {
                XCTAssertGreaterThanOrEqual(contrast(menu.accent, surface), 4.5, "\(skin.rawValue)")
            }
            // Dark text on a filled accent button
            XCTAssertGreaterThanOrEqual(contrast(menu.accent, .black), 4.5, "\(skin.rawValue)")
            // White text on the menu surfaces
            XCTAssertGreaterThanOrEqual(contrast(.white, menu.panelTop), 12, "\(skin.rawValue)")
        }
    }

    private func rgb(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func hex(_ color: Color) -> String {
        let (r, g, b) = rgb(color)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// WCAG contrast ratio between two opaque colors.
    private func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let (r, g, b) = rgb(color)
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    // MARK: - Store contents

    func testCartridgesAreSplitBetweenFreeAndPro() {
        let free = GameType.allCases.filter(\.isFree)
        XCTAssertEqual(free, [.brickBreaker, .retroRacer, .snake, .fallingBlocks, .pixelInvaders, .mineSweep, .paddleDuel, .towerStack])
        XCTAssertEqual(ProductIdentifiers.cartridges(unlockedBy: ProductIdentifiers.pro), [.mazeMuncher, .frogHop, .lunarHinge, .astroDrift])
    }

    func testProIsTheOnlyProduct() {
        XCTAssertEqual(ProductIdentifiers.allProductIDs, [ProductIdentifiers.pro])
        XCTAssertEqual(ProductIdentifiers.displayOrder, [ProductIdentifiers.pro])
        XCTAssertTrue(ProductIdentifiers.unlocksScreenTuning(ProductIdentifiers.pro))
        XCTAssertFalse(ProductIdentifiers.unlocks(ProductIdentifiers.pro, itemRequiring: nil))
    }

    func testEveryPaidItemBelongsToARealProduct() {
        let products = ProductIdentifiers.allProductIDs
        let required = ConsoleSkinType.allCases.compactMap(\.requiredProductID)
            + GameType.allCases.compactMap(\.info.requiredProductID)
            + SoundPack.allCases.compactMap(\.requiredProductID)
            + ScreenMode.allCases.compactMap(\.requiredProductID)
        XCTAssertFalse(required.isEmpty)
        XCTAssertTrue(required.allSatisfy { products.contains($0) })
    }

    func testStoreSummariesDescribeTheContents() {
        XCTAssertEqual(
            ProductIdentifiers.summary(for: ProductIdentifiers.pro),
            "4 cartridges, 7 skins, 3 sound packs and 3 screen modes with tuning."
        )
    }

    func testTappingSomethingLockedHighlightsItsProduct() {
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.openStore(highlighting: GameType.lunarHinge.info.requiredProductID)
        XCTAssertTrue(appState.isStoreVisible)
        XCTAssertEqual(appState.storeHighlight, ProductIdentifiers.pro)
    }

    // MARK: - Occlusion

    func testNoRegionsNoInsets() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertEqual(OcclusionInsets.insets(for: bounds, avoiding: []), EdgeInsets())
        XCTAssertEqual(OcclusionInsets.insets(for: bounds, avoiding: [CGRect(x: 700, y: 0, width: 50, height: 50)]), EdgeInsets())
    }

    func testCameraAtTheTopPushesContentDown() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let camera = CGRect(x: 500, y: -10, width: 60, height: 50)
        let insets = OcclusionInsets.insets(for: bounds, avoiding: [camera])
        XCTAssertEqual(insets.top, 40)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.trailing, 0)
        XCTAssertEqual(insets.bottom, 0)
    }

    func testCameraAtTheSidePushesContentInFromThatSide() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let camera = CGRect(x: 570, y: 150, width: 40, height: 60)
        XCTAssertEqual(OcclusionInsets.insets(for: bounds, avoiding: [camera]).trailing, 30)
    }

    func testRegionsNeverPushMoreThanTheCap() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let huge = CGRect(x: -10, y: -10, width: 620, height: 300)
        let insets = OcclusionInsets.insets(for: bounds, avoiding: [huge])
        XCTAssertLessThanOrEqual(insets.top, 400 * OcclusionInsets.maximumShare)
    }

    // MARK: - Music

    func testNoteNamesBecomeFrequencies() {
        XCTAssertEqual(ChipMusic.frequency(of: "A4") ?? 0, 440, accuracy: 0.001)
        XCTAssertEqual(ChipMusic.frequency(of: "C4") ?? 0, 261.63, accuracy: 0.01)
        XCTAssertEqual(ChipMusic.frequency(of: "Bb3") ?? 0, ChipMusic.frequency(of: "A#3") ?? 1, accuracy: 0.001)
        XCTAssertNil(ChipMusic.frequency(of: "H2"))
    }

    func testEveryTrackLoopsInStep() {
        for game in GameType.allCases {
            let track = ChipMusic.track(for: game)
            let length = track.drumBar.count * track.bars
            XCTAssertEqual(track.drumBar.count, 16, game.rawValue)
            XCTAssertEqual(ChipMusic.sixteenths(inScore: track.lead), length, game.rawValue)
            XCTAssertEqual(ChipMusic.sixteenths(inScore: track.bass), length, game.rawValue)
            // A sixteenth is a whole number of samples
            XCTAssertEqual(661_500 % track.bpm, 0, game.rawValue)
        }
    }

    func testEveryScoreTokenIsANoteOrRest() {
        for game in GameType.allCases {
            let track = ChipMusic.track(for: game)
            for score in [track.lead, track.bass] {
                let tokens = score.split(whereSeparator: { $0 == " " || $0 == "|" })
                let notes = ChipMusic.notes(fromScore: score, bpm: track.bpm, waveform: .square, volume: 0.2)
                XCTAssertEqual(notes.count, tokens.count, game.rawValue)
            }
        }
    }

    func testMusicPatchesLoopOnTheMusicChannels() {
        let patches = ChipMusic.patches(for: ChipMusic.track(for: .snake))
        XCTAssertEqual(patches.count, ChipMusic.partsPerTrack)
        XCTAssertTrue(patches.allSatisfy(\.loops))
        XCTAssertEqual(patches.map(\.channel), SynthChannel.music)
        // Sound packs keep music lengths, so the parts stay in step
        let arcade = SoundPack.arcade.voice(patches[0])
        XCTAssertEqual(arcade.notes.map(\.durationMs), patches[0].notes.map(\.durationMs))
    }

    func testLimiterOnlyTouchesPeaks() {
        XCTAssertEqual(ToneGenerator.limit(0.5), 0.5)
        XCTAssertEqual(ToneGenerator.limit(-ToneGenerator.limiterKnee), -ToneGenerator.limiterKnee)
        XCTAssertLessThan(ToneGenerator.limit(1), 1)
        // Six voices at their loudest, after the master gain
        XCTAssertLessThan(ToneGenerator.limit(3.2), 1)
        XCTAssertGreaterThan(ToneGenerator.limit(3.2), ToneGenerator.limit(1))
        // Far beyond that, it saturates at full scale but never passes it
        XCTAssertLessThanOrEqual(ToneGenerator.limit(100), 1)
        XCTAssertEqual(ToneGenerator.limit(-2), -ToneGenerator.limit(2))
    }

    /// The loudest moment found by rendering offline: a crash and the
    /// game-over tune over Falling Blocks' music in the Arcade pack. It used
    /// to clip flat for hundreds of samples.
    func testLoudestMomentsDontClip() throws {
        let table = SynthPatch.allCases.map(\.definition)
            + GameType.allCases.flatMap { ChipMusic.patches(for: ChipMusic.track(for: $0)) }
        let generator = ToneGenerator(patches: table.map { SoundPack.arcade.voice($0) }, sampleRate: ChipMusic.sampleRate)
        let track = try XCTUnwrap(GameType.allCases.firstIndex(of: .fallingBlocks))
        let music = SynthPatch.allCases.count + track * ChipMusic.partsPerTrack
        for part in 0..<ChipMusic.partsPerTrack {
            generator.trigger(patchIndex: music + part)
        }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: ChipMusic.sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512
        var peak: Float = 0
        for block in 0..<200 {
            if block == 80 {
                for patch in [SynthPatch.crashTone, .crashNoise, .gameOver] {
                    generator.trigger(patchIndex: patch.rawValue)
                }
            }
            _ = generator.render(frameCount: 512, audioBufferList: buffer.mutableAudioBufferList)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: 512)
            peak = max(peak, samples.map(abs).max() ?? 0)
        }
        XCTAssertGreaterThan(peak, Float(ToneGenerator.limiterKnee), "the moment is loud enough to reach the limiter")
        XCTAssertLessThan(peak, 0.999)
    }

    func testPauseMenuTogglesMusic() {
        let appState = makePausedAppState()
        let original = appState.isMusicOn
        defer { appState.isMusicOn = original }

        appState.pauseMenuSelection = .music
        PauseMenu.handle(.buttonAPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.isMusicOn, !original)
    }

    func testPauseMenuTogglesSoundEffectsApartFromMusic() {
        let appState = makePausedAppState()
        let original = (music: appState.isMusicOn, sound: appState.isSoundOn)
        defer { appState.isMusicOn = original.music; appState.isSoundOn = original.sound }

        appState.pauseMenuSelection = .sound
        PauseMenu.handle(.dpadRightPressed, appState: appState, screenModes: [.crt], currentScreen: .crt)
        XCTAssertEqual(appState.isSoundOn, !original.sound)
        XCTAssertEqual(appState.isMusicOn, original.music)
        // Persisted for the next launch
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "soundOn"), !original.sound)
    }

    // MARK: - Paddle Duel, Astro Drift, Tower Stack

    func testPaddleReturnScoresAndSpeedsUp() {
        let game = PaddleDuelGame()
        game.handleInput(action: .buttonAPressed)
        game.serveTimer = 0
        game.ballX = game.playerX
        game.ballY = game.playerY - 0.06
        game.ballVX = 0
        game.ballVY = 0.6
        for _ in 0..<10 { game.update(deltaTime: 1.0 / 60) }
        XCTAssertLessThan(game.ballVY, 0, "the ball goes back up")
        XCTAssertGreaterThan((game.ballVX * game.ballVX + game.ballVY * game.ballVY).squareRoot(), 0.6)
        XCTAssertEqual(game.score, 10)
    }

    func testPaddleMissCostsABallAndThreeEndTheMatch() {
        let game = PaddleDuelGame()
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<3 {
            game.serveTimer = 0
            game.playerX = 0.1
            game.ballX = 0.9
            game.ballY = 0.97
            game.ballVX = 0
            game.ballVY = 1
            game.update(deltaTime: 0.1)
        }
        XCTAssertEqual(game.lives, 0)
        XCTAssertEqual(game.gameState, .gameOver(score: 0))
    }

    func testPaddlePointsWonLevelUp() {
        let game = PaddleDuelGame()
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<3 {
            game.serveTimer = 0
            game.cpuX = 0.1
            game.ballX = 0.9
            game.ballY = 0.02
            game.ballVX = 0
            game.ballVY = -1
            game.update(deltaTime: 0.1)
        }
        XCTAssertEqual(game.pointsWon, 3)
        XCTAssertEqual(game.level, 2)
        XCTAssertEqual(game.score, 100 + 100 + 100)
    }

    func testAstroShotsSplitRocks() {
        let game = AstroDriftGame()
        game.handleInput(action: .buttonAPressed)
        game.shieldTimer = 10
        // One big rock straight ahead of the ship, standing still
        game.rocks = [AstroDriftGame.Rock(x: 0.5, y: 0.3, vx: 0, vy: 0, size: 3, spin: 0, outline: Array(repeating: 1, count: 9))]
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<30 { game.update(deltaTime: 1.0 / 60) }
        XCTAssertEqual(game.score, 20)
        XCTAssertEqual(game.rocks.count, 2)
        XCTAssertTrue(game.rocks.allSatisfy { $0.size == 2 })
    }

    func testAstroClearingTheFieldStartsABiggerWave() {
        let game = AstroDriftGame()
        game.handleInput(action: .buttonAPressed)
        let firstWave = game.rocks.count
        game.shieldTimer = 10
        game.rocks = [AstroDriftGame.Rock(x: 0.5, y: 0.3, vx: 0, vy: 0, size: 1, spin: 0, outline: Array(repeating: 1, count: 9))]
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<150 { game.update(deltaTime: 1.0 / 60) }
        XCTAssertEqual(game.level, 2)
        XCTAssertEqual(game.rocks.count, firstWave + 1)
    }

    func testAstroFieldWraps() {
        XCTAssertEqual(AstroDriftGame.wrappedOffset(from: 0.95, to: 0.05), 0.1, accuracy: 1e-9)
        XCTAssertEqual(AstroDriftGame.wrappedOffset(from: 0.05, to: 0.95), -0.1, accuracy: 1e-9)
    }

    func testTowerPerfectDropKeepsTheWidth() {
        let game = TowerStackGame()
        game.handleInput(action: .buttonAPressed)
        game.sliderX = game.top.x + 0.005
        game.handleInput(action: .buttonAPressed)
        XCTAssertEqual(game.blocks.count, 2)
        XCTAssertEqual(game.top.width, game.baseWidth, accuracy: 1e-9)
        XCTAssertEqual(game.streak, 1)
        XCTAssertEqual(game.score, 15)
    }

    func testTowerOverhangIsCutOff() {
        let game = TowerStackGame()
        game.handleInput(action: .buttonAPressed)
        let base = game.top
        game.sliderX = base.x + 0.1
        game.handleInput(action: .dpadDownPressed)
        XCTAssertEqual(game.top.x, base.x + 0.1, accuracy: 1e-9)
        XCTAssertEqual(game.top.width, base.width - 0.1, accuracy: 1e-9)
        XCTAssertEqual(game.pieces.count, 1)
        XCTAssertEqual(game.streak, 0)
    }

    func testTowerMissEndsTheRoundAndTenBlocksLevelUp() {
        let game = TowerStackGame()
        game.handleInput(action: .buttonAPressed)
        for _ in 0..<10 {
            game.sliderX = game.top.x
            game.handleInput(action: .buttonAPressed)
        }
        XCTAssertEqual(game.level, 2)

        game.sliderX = game.top.x + game.top.width + 0.01
        game.handleInput(action: .buttonAPressed)
        if case .gameOver = game.gameState {} else { XCTFail("a miss ends the round") }
    }

    // MARK: - Label designer

    func testBuiltInLabelsAreValid() {
        for gameType in GameType.allCases {
            XCTAssertTrue(PixelArt.label(for: gameType).isValid, gameType.rawValue)
        }
        XCTAssertTrue(PixelArt.blank.isValid)
        XCTAssertEqual(PixelArt.blank.paintedCount, 0)
        XCTAssertFalse(PixelArt(rows: ["P"]).isValid)
        XCTAssertFalse(PixelArt.blank.setting("Z", atX: 0, y: 0).isValid)
    }

    func testPencilPaintsAndMirrors() {
        let single = PixelArt.blank.setting("P", atX: 2, y: 3)
        XCTAssertEqual(single.pixel(atX: 2, y: 3), "P")
        XCTAssertEqual(single.paintedCount, 1)

        let mirrored = PixelArt.blank.setting("X", atX: 2, y: 3, mirrored: true)
        XCTAssertEqual(mirrored.pixel(atX: 13, y: 3), "X")
        XCTAssertEqual(mirrored.paintedCount, 2)

        // Outside the grid nothing changes
        XCTAssertEqual(PixelArt.blank.setting("P", atX: 16, y: 0), .blank)
    }

    func testFillStopsAtOtherColors() {
        // A closed box of walls: filling inside stays inside
        var art = PixelArt.blank
        for i in 2...6 {
            art = art.setting("G", atX: i, y: 2).setting("G", atX: i, y: 6)
                .setting("G", atX: 2, y: i).setting("G", atX: 6, y: i)
        }
        let filled = art.filling(fromX: 4, y: 4, with: "F")
        XCTAssertEqual(filled.paintedCount - art.paintedCount, 9) // the 3×3 inside
        XCTAssertEqual(filled.pixel(atX: 0, y: 0), ".")

        // Filling outside covers everything else
        let outside = art.filling(fromX: 0, y: 0, with: "P")
        XCTAssertEqual(outside.paintedCount, 256 - 9)
    }

    func testCustomLabelsPersistAndFallBack() {
        let defaults = makeDefaults()
        let store = LabelStore(defaults: defaults)
        XCTAssertEqual(store.art(for: .snake), PixelArt.label(for: .snake))
        XCTAssertFalse(store.hasCustomLabel(for: .snake))

        let drawing = PixelArt.blank.setting("H", atX: 7, y: 7)
        store.save(drawing, for: .snake)
        XCTAssertEqual(LabelStore(defaults: defaults).art(for: .snake), drawing)

        // Drawing the original back, or removing the label, restores it
        store.save(PixelArt.label(for: .snake), for: .snake)
        XCTAssertFalse(store.hasCustomLabel(for: .snake))
        store.save(drawing, for: .snake)
        store.removeCustomLabel(for: .snake)
        XCTAssertFalse(LabelStore(defaults: defaults).hasCustomLabel(for: .snake))
    }

    func testCorruptSavedLabelsAreIgnored() {
        let defaults = makeDefaults()
        defaults.set(["Snake": ["PPP"], "Not A Game": PixelArt.blank.rows], forKey: "customLabels")
        let store = LabelStore(defaults: defaults)
        XCTAssertTrue(store.customLabels.isEmpty)
    }

    func testDesignerOffersEveryPaletteColor() {
        for gameType in GameType.allCases {
            let palette = GamePalette.native(for: gameType)
            let pixels = PixelArt.pixels(for: palette)
            XCTAssertEqual(pixels.first, ".")
            for pixel in pixels.dropFirst() {
                XCTAssertNotNil(PixelArt.color(for: pixel, in: palette), "\(gameType.rawValue): \(pixel)")
            }
        }
    }

    // MARK: - Intro

    func testIntroPicturesAreValidLabels() {
        XCTAssertEqual(IntroPage.allCases.count, 5)
        for page in IntroPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.text.isEmpty)
            if let art = page.art {
                XCTAssertTrue(art.isValid, page.title)
                for pixel in art.rows.joined() where pixel != "." {
                    XCTAssertNotNil(PixelArt.color(for: pixel, in: .intro), "\(page.title): \(pixel)")
                }
            }
        }
    }

    func testIntroShowsUntilSeenAndCanBeReplayed() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "hasSeenIntro")
        defer { defaults.set(original, forKey: "hasSeenIntro") }

        defaults.removeObject(forKey: "hasSeenIntro")
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()), labels: LabelStore(defaults: makeDefaults()))
        XCTAssertTrue(appState.isIntroVisible)

        appState.finishIntro()
        XCTAssertFalse(appState.isIntroVisible)
        XCTAssertFalse(AppState(progress: ProgressStore(defaults: makeDefaults())).isIntroVisible)

        appState.isRecordsVisible = true
        appState.showIntro()
        XCTAssertTrue(appState.isIntroVisible)
        XCTAssertFalse(appState.isRecordsVisible)
    }

    func testStartingAGameHidesTheIntroWithoutMarkingItSeen() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "hasSeenIntro")
        defer { defaults.set(original, forKey: "hasSeenIntro") }

        defaults.removeObject(forKey: "hasSeenIntro")
        let appState = AppState(progress: ProgressStore(defaults: makeDefaults()))
        appState.startGame(type: .snake)
        XCTAssertFalse(appState.isIntroVisible)
        XCTAssertFalse(appState.hasSeenIntro)
    }

    // MARK: - Text size and Bold Text

    func testOverlayTextFollowsTheTextSize() {
        XCTAssertEqual(RetroType.scale(for: .large), 1)
        XCTAssertLessThan(RetroType.scale(for: .xSmall), 1)
        // Each size is larger than the one before
        let sizes = DynamicTypeSize.allCases.map(RetroType.scale(for:))
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func testBoldTextMakesTextOneStepHeavier() {
        XCTAssertEqual(RetroType.weight(.medium, isBold: false), .medium)
        XCTAssertEqual(RetroType.weight(.medium, isBold: true), .semibold)
        XCTAssertEqual(RetroType.weight(.heavy, isBold: true), .black)
        XCTAssertEqual(RetroType.weight(.black, isBold: true), .black)
    }

    func testOverlayTextUsesTheBundledPixelFont() {
        for name in [RetroType.pixelRegular, RetroType.pixelBold] {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name, "Pixel font not registered (UIAppFonts)")
        }
    }

    func testPixelFontStillGetsHeavierWithBoldText() {
        XCTAssertEqual(RetroType.pixelFontName(isBold: false), RetroType.pixelRegular)
        XCTAssertEqual(RetroType.pixelFontName(isBold: true), RetroType.pixelBold)
    }

    // MARK: - Language

    func testAppShipsInEnglishOnly() {
        // The pixel font has no Turkish letters, so the app ships English only
        XCTAssertNil(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        XCTAssertFalse(Bundle.main.localizations.contains("tr"))
    }

    func testCapitalsFollowEnglishRules() {
        // Capitals never depend on the device's region (no Turkish İ)
        XCTAssertEqual(ScreenMode.trinitron.uppercasedTitle, "TRINITRON")
        XCTAssertEqual(ProductIdentifiers.fallbackDisplayName(for: ProductIdentifiers.pro).uppercased(), "RETROFOLD PRO")
        XCTAssertEqual(ProductIdentifiers.shortName(for: "com.example.unknown"), "COM.EXAMPLE.UNKNOWN")
    }
}

// MARK: - StoreKit

/// Purchases, restores and refunds against the local StoreKit configuration
/// (`Products.storekit`), through `StoreManager` as the app uses it.
@MainActor
final class StoreKitPurchaseTests: XCTestCase {

    private var session: SKTestSession!

    override func setUp() async throws {
        // The configuration the scheme runs the app with, found from this file
        let configuration = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Products.storekit")
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session = nil
    }

    // MARK: Helpers

    private func makeStore() async throws -> StoreManager {
        let store = StoreManager()
        await store.loadProducts()
        XCTAssertEqual(Set(store.products.map(\.id)), ProductIdentifiers.allProductIDs)
        XCTAssertNil(store.productLoadError)
        return store
    }

    private func buy(_ productID: String, in store: StoreManager) async throws {
        let product = try XCTUnwrap(store.product(for: productID))
        await store.purchase(product)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.isPurchased(productID))
    }

    /// Refunds a product in the test session, then refreshes the store's
    /// entitlements as the app does at launch and whenever the store opens.
    ///
    /// A running store also hears of refunds through `Transaction.updates`,
    /// but the test session sometimes drops that notification for a refund
    /// sent milliseconds after the purchase (about one run in three), so
    /// the test doesn't depend on it. The session can also apply the refund
    /// a moment late, so the refresh retries for up to two seconds.
    private func refund(_ productID: String, in store: StoreManager) async throws {
        let transaction = try XCTUnwrap(session.allTransactions().last { $0.productIdentifier == productID })
        try session.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<20 {
            await store.loadProducts()
            if !store.isPurchased(productID) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.isPurchased(productID), "\(productID) still owned after the refund")
    }

    // MARK: Tests

    func testNothingIsUnlockedBeforeAPurchase() async throws {
        let store = try await makeStore()
        XCTAssertTrue(store.purchasedProductIDs.isEmpty)
        XCTAssertEqual(ConsoleSkinType.allCases.filter(store.isUnlocked), [.classicGrey])
        XCTAssertEqual(GameType.allCases.filter(store.isUnlocked), GameType.allCases.filter(\.isFree))
        XCTAssertEqual(SoundPack.allCases.filter(store.isUnlocked), [.classic])
        XCTAssertEqual(ScreenMode.allCases.filter(store.isUnlocked), [.crt])
        XCTAssertFalse(store.canTuneScreen)
    }

    func testProUnlocksEverything() async throws {
        let store = try await makeStore()
        try await buy(ProductIdentifiers.pro, in: store)

        XCTAssertTrue(store.hasPro)
        XCTAssertEqual(ConsoleSkinType.allCases.filter(store.isUnlocked), ConsoleSkinType.allCases)
        XCTAssertEqual(GameType.allCases.filter(store.isUnlocked), GameType.allCases)
        XCTAssertEqual(SoundPack.allCases.filter(store.isUnlocked), SoundPack.allCases)
        XCTAssertEqual(ScreenMode.allCases.filter(store.isUnlocked), ScreenMode.allCases)
        XCTAssertTrue(store.canTuneScreen)
        let tuned = ScreenSettings(mode: .trinitron, curvature: 0.9, scanlines: 0.2, bleed: 0.8)
        XCTAssertEqual(store.effectiveScreenSettings(tuned), tuned)
    }

    func testRestoreBringsPurchasesBackToAFreshStore() async throws {
        let first = try await makeStore()
        try await buy(ProductIdentifiers.pro, in: first)

        // A new install knows nothing until it restores
        let reinstalled = StoreManager()
        XCTAssertFalse(reinstalled.isPurchased(ProductIdentifiers.pro))
        await reinstalled.restorePurchases()
        XCTAssertNil(reinstalled.errorMessage)
        XCTAssertTrue(reinstalled.isPurchased(ProductIdentifiers.pro))
        XCTAssertTrue(reinstalled.isUnlocked(.mazeMuncher))
        XCTAssertTrue(reinstalled.canTuneScreen)
    }

    func testRefundsFallBackToTheFreeChoices() async throws {
        let store = try await makeStore()
        try await buy(ProductIdentifiers.pro, in: store)

        let tuned = ScreenSettings(mode: .trinitron, curvature: 0.9, scanlines: 0.2, bleed: 0.8)
        XCTAssertEqual(store.effectiveSkin(.goldEdition), .goldEdition)
        XCTAssertEqual(store.effectiveScreenSettings(tuned), tuned)

        // Refunding Pro leaves only the free tier
        try await refund(ProductIdentifiers.pro, in: store)
        XCTAssertFalse(store.isUnlocked(.lunarHinge))
        XCTAssertFalse(store.isUnlocked(.mazeMuncher))
        XCTAssertEqual(store.effectiveScreenSettings(tuned), ScreenSettings.standard)
        XCTAssertEqual(store.effectiveSkin(.goldEdition), .classicGrey)
        XCTAssertEqual(store.effectiveSkin(.atomicPurple), .classicGrey)
        XCTAssertEqual(store.effectiveSoundPack(.arcade), .classic)

        // A fresh launch agrees: refunded products aren't entitlements
        let relaunched = try await makeStore()
        XCTAssertTrue(relaunched.purchasedProductIDs.isEmpty)
    }
}
