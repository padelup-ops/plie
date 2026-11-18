// AppState.swift
// RetroCartridge
//
// Global application state managed with @Observable.
// Tracks active game, selected skin, UI preferences and player progress.

import SwiftUI

@Observable
final class AppState {

    /// High scores and achievements, persisted.
    let progress: ProgressStore

    /// The player's own cartridge labels, persisted.
    let labels: LabelStore

    init(progress: ProgressStore = ProgressStore(), labels: LabelStore = LabelStore()) {
        self.progress = progress
        self.labels = labels
    }
    
    // MARK: - Game State
    
    /// The currently selected game type (shown on cover screen carousel).
    var selectedGameType: GameType = .brickBreaker
    
    /// The currently active game instance (nil when on menu/cover screen).
    var activeGame: (any PixelGameProtocol)? = nil
    
    /// Whether a game session is currently in progress.
    var isGameActive: Bool {
        activeGame != nil
    }
    
    // MARK: - Skin & Customization
    
    /// The currently applied console skin. A stored property so `@Observable`
    /// tracks it and every view reading it refreshes; persisted on change.
    var selectedSkin: ConsoleSkinType = AppState.persistedSkin() {
        didSet {
            guard selectedSkin != oldValue else { return }
            UserDefaults.standard.set(selectedSkin.rawValue, forKey: Self.selectedSkinKey)
        }
    }

    private static let selectedSkinKey = "selectedSkin"

    private static func persistedSkin() -> ConsoleSkinType {
        UserDefaults.standard.string(forKey: selectedSkinKey)
            .flatMap(ConsoleSkinType.init(rawValue:)) ?? .classicGrey
    }
    
    // MARK: - Screen

    /// The chosen screen mode and tuning, persisted. What is actually drawn
    /// also depends on purchases: see `StoreManager.effectiveScreenSettings(_:)`.
    var screenSettings: ScreenSettings = AppState.persistedScreenSettings() {
        didSet {
            guard screenSettings != oldValue,
                  let data = try? JSONEncoder().encode(screenSettings) else { return }
            UserDefaults.standard.set(data, forKey: Self.screenSettingsKey)
        }
    }

    private static let screenSettingsKey = "screenSettings"

    private static func persistedScreenSettings() -> ScreenSettings {
        UserDefaults.standard.data(forKey: screenSettingsKey)
            .flatMap { try? JSONDecoder().decode(ScreenSettings.self, from: $0) } ?? .standard
    }

    // MARK: - Palette

    /// The palette games draw with, persisted. Applied to every new game and
    /// to the running one as soon as it changes.
    var paletteChoice: PaletteChoice = AppState.persistedPaletteChoice() {
        didSet {
            guard paletteChoice != oldValue else { return }
            UserDefaults.standard.set(paletteChoice.rawValue, forKey: Self.paletteChoiceKey)
            if let activeGame {
                activeGame.palette = paletteChoice.palette(for: activeGame.gameType)
            }
        }
    }

    private static let paletteChoiceKey = "paletteChoice"

    private static func persistedPaletteChoice() -> PaletteChoice {
        UserDefaults.standard.string(forKey: paletteChoiceKey)
            .flatMap(PaletteChoice.init(rawValue:)) ?? .original
    }

    // MARK: - Sound

    /// The chosen sound pack, persisted. What plays also depends on
    /// purchases: `RootView` hands `AudioManager` the unlocked pack.
    var soundPack: SoundPack = AppState.persistedSoundPack() {
        didSet {
            guard soundPack != oldValue else { return }
            UserDefaults.standard.set(soundPack.rawValue, forKey: Self.soundPackKey)
        }
    }

    private static let soundPackKey = "soundPack"

    /// Whether cartridges play their music, persisted. On by default.
    var isMusicOn: Bool = AppState.persistedMusicOn() {
        didSet {
            guard isMusicOn != oldValue else { return }
            UserDefaults.standard.set(isMusicOn, forKey: Self.musicKey)
        }
    }

    private static let musicKey = "musicOn"

    private static func persistedMusicOn() -> Bool {
        guard UserDefaults.standard.object(forKey: musicKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: musicKey)
    }

    /// Whether games and the console play sound effects (everything but the
    /// music), persisted. On by default.
    var isSoundOn: Bool = AppState.persistedSoundOn() {
        didSet {
            guard isSoundOn != oldValue else { return }
            UserDefaults.standard.set(isSoundOn, forKey: Self.soundKey)
        }
    }

    private static let soundKey = "soundOn"

    private static func persistedSoundOn() -> Bool {
        guard UserDefaults.standard.object(forKey: soundKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: soundKey)
    }

    private static func persistedSoundPack() -> SoundPack {
        UserDefaults.standard.string(forKey: soundPackKey)
            .flatMap(SoundPack.init(rawValue:)) ?? .classic
    }

    // MARK: - UI State
    
    /// Whether the store overlay is visible (drawn in-hierarchy by the library,
    /// never as a sheet, so it follows the pinned display orientation).
    var isStoreVisible: Bool = false

    /// The product the store points out, when it was opened by tapping
    /// something locked; nil when opened from the toolbar.
    var storeHighlight: String?

    /// Opens the store over the other overlays, pointing out the product
    /// that unlocks what was tapped. Call inside `withAnimation`.
    func openStore(highlighting productID: String?) {
        storeHighlight = productID
        isStoreVisible = true
    }

    /// Whether the skin picker overlay is visible. The store stacks above it.
    var isSkinSelectorVisible: Bool = false

    /// Whether the screen settings overlay is visible. The store stacks above it.
    var isScreenSettingsVisible: Bool = false

    /// Whether the records overlay is visible. The store stacks above it.
    var isRecordsVisible: Bool = false

    /// Whether the label designer overlay is visible. The store stacks above it.
    var isLabelDesignerVisible: Bool = false

    // MARK: - Intro

    /// Whether the how-to-play intro is showing, above every other overlay.
    /// It opens by itself until the player has been through it once.
    var isIntroVisible: Bool = !AppState.persistedHasSeenIntro()

    /// Whether the player has finished or closed the intro, persisted.
    var hasSeenIntro: Bool = AppState.persistedHasSeenIntro() {
        didSet {
            guard hasSeenIntro != oldValue else { return }
            UserDefaults.standard.set(hasSeenIntro, forKey: Self.hasSeenIntroKey)
        }
    }

    private static let hasSeenIntroKey = "hasSeenIntro"

    private static func persistedHasSeenIntro() -> Bool {
        UserDefaults.standard.bool(forKey: hasSeenIntroKey)
    }

    /// Opens the intro again, in place of the other overlays. Call inside
    /// `withAnimation`.
    func showIntro() {
        isSkinSelectorVisible = false
        isScreenSettingsVisible = false
        isRecordsVisible = false
        isLabelDesignerVisible = false
        isStoreVisible = false
        isIntroVisible = true
    }

    /// Closes the intro for good. Call inside `withAnimation`.
    func finishIntro() {
        isIntroVisible = false
        hasSeenIntro = true
    }
    
    // MARK: - High Scores (Persisted)
    
    /// The high score for a game type in a mode.
    func highScore(for gameType: GameType, mode: GameMode = .standard) -> Int {
        progress.highScore(for: gameType, mode: mode)
    }
    
    /// Update the high score for a game type in a mode if the new score is higher.
    func updateHighScore(_ score: Int, for gameType: GameType, mode: GameMode = .standard) {
        progress.recordScore(score, for: gameType, mode: mode)
    }
    
    // MARK: - Game Lifecycle
    
    /// Insert a cartridge: create a fresh game of the given type and power on.
    func startGame(type: GameType, mode: GameMode = .standard) {
        selectedGameType = type
        startGame(PixelGameEngine.createGame(type: type, mode: mode))
    }
    
    /// Unfolding inserts the cartridge picked on the cover. A paused round
    /// of that same cartridge stays as it was; if the player picked another
    /// one while folded, the paused round ends (its score still counts) and
    /// the new cartridge goes in. A locked pick leaves the library showing
    /// it on the shelf, and the intro, while open, inserts nothing (its last
    /// page does).
    func insertCartridgeOnUnfold(isUnlocked: Bool) {
        guard !isIntroVisible else { return }
        if let game = activeGame {
            guard game.gameType != selectedGameType else { return }
            endGame()
        }
        guard isUnlocked else { return }
        startGame(type: selectedGameType)
    }

    /// Start a new game session with the selected game type.
    func startGame(_ game: any PixelGameProtocol) {
        game.palette = paletteChoice.palette(for: game.gameType)
        activeGame = game
        ejectStart = nil
        pauseMenuSelection = .resume
        // Library overlays shouldn't reappear when the cartridge is ejected.
        isStoreVisible = false
        isSkinSelectorVisible = false
        isScreenSettingsVisible = false
        isRecordsVisible = false
        isLabelDesignerVisible = false
        // Hidden, not marked as seen: a game only starts under the intro
        // from its own last page, which marks it
        isIntroVisible = false
    }

    /// When the eject began: the tube powers off, then `GameCanvasView`
    /// calls `endGame()`. Nil while no eject is in progress.
    private(set) var ejectStart: Date?

    /// Whether the cartridge is being ejected (the tube is powering off).
    var isEjecting: Bool { ejectStart != nil }

    /// Starts ejecting the cartridge: the game freezes while the tube powers off.
    func ejectCartridge() {
        guard activeGame != nil, ejectStart == nil else { return }
        ejectStart = Date()
    }
    
    /// End the current game session and return to menu.
    func endGame() {
        if let game = activeGame {
            updateHighScore(game.score, for: game.gameType, mode: game.mode)
        }
        activeGame = nil
        ejectStart = nil
    }

    /// Switches the active game to its next (or previous) mode and resets it
    /// to the title screen. Only on the title and game-over screens, and only
    /// for games with more than one mode.
    /// - Returns: Whether the mode changed.
    @discardableResult
    func cycleMode(by step: Int) -> Bool {
        guard let game = activeGame, !isEjecting else { return false }
        switch game.gameState {
        case .menu, .gameOver: break
        case .playing, .paused: return false
        }
        let modes = game.gameType.modes
        guard modes.count > 1 else { return false }
        let index = modes.firstIndex(of: game.mode) ?? 0
        game.mode = modes[(index + step % modes.count + modes.count) % modes.count]
        game.reset()
        return true
    }

    // MARK: - Pause Menu

    /// The highlighted row of the in-tube pause menu.
    var pauseMenuSelection: PauseMenuItem = .resume

    /// Whether controller input drives the pause menu instead of the game.
    var isPauseMenuActive: Bool {
        activeGame?.gameState == .paused && !isEjecting
    }
    
    /// Pause the active game (e.g., on fold/background).
    func pauseActiveGame() {
        activeGame?.pause()
    }
}
