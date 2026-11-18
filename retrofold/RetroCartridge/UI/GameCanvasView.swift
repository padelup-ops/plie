//
// GameCanvasView.swift
// RetroCartridge
//
// The screen half of the console: a molded bezel with power LED around a
// CRT tube that renders the active game at 60 FPS, in-tube messages for the
// title and game-over states, the pause menu, and a score readout on the
// bezel. Ejecting powers the tube off before the cartridge comes out.
//

import SwiftUI

struct GameCanvasView: View {
    @Environment(AppState.self) private var appState
    @Environment(HingeEngine.self) private var hingeEngine
    @Environment(AudioManager.self) private var audioManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(StoreManager.self) private var storeManager

    /// When the CRT power-on animation started. This view is created fresh
    /// for each game session, so every cartridge gets its own power-on.
    @State private var powerOnStart = Date()

    /// Duration of the CRT power-on animation, in seconds.
    private let powerOnDuration: TimeInterval = 0.7

    /// Duration of the power-off animation when ejecting, in seconds.
    private let powerOffDuration: TimeInterval = 0.45

    /// The achievement being announced on the bezel, and until when.
    @State private var toast: Achievement?
    @State private var toastUntil = Date.distantPast

    /// Handheld-style, slightly wider than square (Game Boy screens are 10:9).
    private let screenAspectRatio: CGFloat = 10 / 9

    init() {}

    var body: some View {
        let theme = SkinManager.theme(for: storeManager.effectiveSkin(appState.selectedSkin))

        GeometryReader { geo in
            let inset = min(geo.size.width, geo.size.height) * 0.05

            ZStack {
                // Bezel
                RoundedRectangle(cornerRadius: inset * 1.4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.bezelTopColor, theme.bezelBottomColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: inset * 1.4, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                VStack(spacing: inset * 0.6) {
                    bezelHeader(theme: theme, inset: inset)
                        .accessibilityHidden(true)

                    if let activeGame = appState.activeGame {
                        TimelineView(.animation) { timeline in
                            VStack(spacing: inset * 0.6) {
                                screen(game: activeGame, date: timeline.date)
                                    .aspectRatio(screenAspectRatio, contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                if let toast, timeline.date < toastUntil {
                                    AchievementToast(achievement: toast, fontSize: max(10, inset * 0.5))
                                        .transition(.opacity)
                                } else {
                                    BezelReadout(
                                        score: activeGame.score,
                                        level: activeGame.level,
                                        highScore: max(appState.highScore(for: activeGame.gameType, mode: activeGame.mode), activeGame.score),
                                        fontSize: max(10, inset * 0.5)
                                    )
                                }
                            }
                            .onChange(of: timeline.date) { oldDate, newDate in
                                // Music on the title screen and while playing; quiet when
                                // paused, after a game over and while ejecting
                                let wantsMusic: Bool
                                switch activeGame.gameState {
                                case .menu, .playing: wantsMusic = appState.isMusicOn && !appState.isEjecting
                                case .paused, .gameOver: wantsMusic = false
                                }
                                audioManager.playMusic(for: wantsMusic ? activeGame.gameType : nil)

                                // Ejecting: the game stays frozen while the tube powers off
                                if let ejectStart = appState.ejectStart {
                                    if newDate.timeIntervalSince(ejectStart) >= powerOffDuration {
                                        appState.endGame()
                                    }
                                    return
                                }

                                // Games played by folding get the live hinge angle
                                (activeGame as? HingeControllable)?.hingeDidChange(angle: Double(hingeEngine.hingeAngle))

                                let delta = newDate.timeIntervalSince(oldDate)
                                activeGame.update(deltaTime: min(max(delta, 0), 0.05))

                                // Play the sound effects raised by this frame's update and by
                                // any input since the last frame, with one haptic for big events.
                                let sounds = activeGame.drainSounds()
                                for sound in sounds {
                                    audioManager.playGameSound(sound)
                                }
                                if sounds.contains(where: \.isImpactful) {
                                    hapticManager.playHaptic(.gameEvent)
                                }

                                // Announce achievements as soon as they're earned
                                if let earned = AchievementTracker.check(activeGame, progress: appState.progress).first {
                                    toast = earned
                                    toastUntil = newDate.addingTimeInterval(2.5)
                                    audioManager.playGameSound(.powerUp)
                                    hapticManager.playHaptic(.gameEvent)
                                    AccessibilityNotification.Announcement(String(localized: "Achievement earned: \(earned.title.capitalized)")).post()
                                }

                                // Persist the score as soon as a round ends, since pressing A
                                // restarts the game and resets its score.
                                if case .gameOver(let score) = activeGame.gameState {
                                    appState.updateHighScore(score, for: activeGame.gameType, mode: activeGame.mode)
                                }
                            }
                        }
                    }
                }
                .padding(inset)
            }
            .padding(inset)
        }
        .onDisappear {
            audioManager.playMusic(for: nil)
        }
    }

    /// Tube power from 0 (off) to 1 (on): rising at power-on, falling back
    /// while the cartridge is ejected, which plays the power-on in reverse.
    private func tubePower(at date: Date) -> Double {
        if let ejectStart = appState.ejectStart {
            return 1 - date.timeIntervalSince(ejectStart) / powerOffDuration
        }
        return date.timeIntervalSince(powerOnStart) / powerOnDuration
    }

    /// The screen to draw, limited to what the player has unlocked.
    private var screenSettings: ScreenSettings {
        storeManager.effectiveScreenSettings(appState.screenSettings)
    }

    // MARK: - Bezel

    private func bezelHeader(theme: SkinTheme, inset: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Power LED
            Circle()
                .fill(appState.isGameActive ? theme.ledColor : Color(white: 0.25))
                .frame(width: 7, height: 7)
                .shadow(color: appState.isGameActive ? theme.ledColor : .clear, radius: 4)
            Text("POWER")
                .font(.pixel(max(8, inset * 0.36)))
                .foregroundStyle(Color.white.opacity(0.35))

            Spacer()

            Text(screenSettings.mode.bezelLabel)
                .font(.pixel(max(8, inset * 0.36)))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.3))
            Rectangle()
                .fill(theme.actionButtonColor.opacity(0.8))
                .frame(width: inset * 2, height: 2)
            Rectangle()
                .fill(theme.accentColor.opacity(0.8))
                .frame(width: inset * 1.2, height: 2)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Screen

    private func screen(game: any PixelGameProtocol, date: Date) -> some View {
        ZStack {
            // Tube glass behind the picture
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)

            ZStack {
                // Capturing the frame date makes each frame's renderer distinct.
                // Otherwise SwiftUI sees an unchanged closure (it only captures
                // the same game object) and keeps showing the first frame.
                Canvas { [frameDate = date] context, size in
                    _ = frameDate
                    game.render(context: &context, size: size)
                }

                GameStatePanel(
                    title: game.gameType.rawValue,
                    gameState: game.gameState,
                    highScore: max(appState.highScore(for: game.gameType, mode: game.mode), game.score),
                    blinkOn: Int(date.timeIntervalSinceReferenceDate * 2.5) % 2 == 0,
                    mode: game.mode,
                    hasModes: game.gameType.modes.count > 1,
                    menuSelection: appState.pauseMenuSelection,
                    screenMode: screenSettings.mode,
                    canChangeScreen: PauseMenu.availableScreenModes(store: storeManager).count > 1,
                    paletteTitle: appState.paletteChoice.title,
                    isMusicOn: appState.isMusicOn,
                    isSoundOn: appState.isSoundOn
                )
            }
            .screenEffect(
                screenSettings,
                hingeAngle: hingeEngine.hingeAngle,
                powerOnProgress: tubePower(at: date)
            )
            .padding(3)

            // Glass reflection
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.07), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // VoiceOver reads the game's state instead of the pixels
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.gameType.rawValue) screen")
        .accessibilityValue(screenDescription(for: game))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// What the screen shows, in words, for VoiceOver.
    private func screenDescription(for game: any PixelGameProtocol) -> String {
        switch game.gameState {
        case .menu:
            return String(localized: "Title screen, \(game.mode.title) mode. Press A to start.")
        case .playing:
            return String(localized: "Playing. Score \(game.score), level \(game.level).")
        case .paused:
            let selection = appState.pauseMenuSelection.title.capitalized
            let screen = screenSettings.mode.title
            let palette = appState.paletteChoice.title
            let music = appState.isMusicOn ? String(localized: "on") : String(localized: "off")
            let sound = appState.isSoundOn ? String(localized: "on") : String(localized: "off")
            return String(localized: "Paused. \(selection) selected. Screen \(screen), palette \(palette), music \(music), sound \(sound).")
        case .gameOver(let score):
            return String(localized: "Game over. Score \(score). Press A to play again.")
        }
    }
}

// MARK: - Readout

/// Segment-display style score strip printed on the bezel under the tube.
private struct BezelReadout: View {
    let score: Int
    let level: Int
    let highScore: Int
    let fontSize: CGFloat

    private let phosphor = Color(hex: "#9CFFB8")

    var body: some View {
        HStack(spacing: fontSize * 1.6) {
            item("SCORE", String(format: "%06d", score))
            item("LV", String(format: "%02d", level))
            item("HI", String(format: "%06d", highScore))
        }
        .font(.pixel(fontSize))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score), level \(level), high score \(highScore)")
    }

    private func item(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: fontSize * 0.4) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.35))
            Text(value)
                .foregroundStyle(phosphor)
                .shadow(color: phosphor.opacity(0.6), radius: 3)
        }
    }
}

// MARK: - Achievement toast

/// A just-earned achievement, shown on the bezel in place of the score strip.
private struct AchievementToast: View {
    let achievement: Achievement
    let fontSize: CGFloat

    private let gold = Color(hex: "#FFD166")

    var body: some View {
        HStack(spacing: fontSize * 0.6) {
            Text("★ \(achievement.title)")
                .foregroundStyle(gold)
                .shadow(color: gold.opacity(0.6), radius: 3)
            Text(achievement.detail.uppercased())
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .font(.pixel(fontSize))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement earned: \(achievement.title.capitalized). \(achievement.detail).")
    }
}

// MARK: - State Panel

/// Title and game-over messages and the pause menu, rendered inside the
/// tube so they get the same curvature and scanlines as the game itself.
private struct GameStatePanel: View {
    let title: String
    let gameState: GameState
    let highScore: Int
    let blinkOn: Bool
    let mode: GameMode
    /// Whether the D-Pad can switch modes on the title and game-over screens.
    let hasModes: Bool
    let menuSelection: PauseMenuItem
    let screenMode: ScreenMode
    let canChangeScreen: Bool
    let paletteTitle: String
    let isMusicOn: Bool
    let isSoundOn: Bool

    private let phosphor = Color(hex: "#9CFFB8")

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 20

            Group {
                switch gameState {
                case .menu:
                    // The D-Pad picks the mode on the title screen
                    panel(
                        u: u,
                        title: title.uppercased(),
                        lines: hasModes ? ["< \(mode.title.uppercased()) >", mode.summary.uppercased()] : [],
                        prompt: String(localized: "PRESS A TO START")
                    )
                case .paused:
                    PauseMenuPanel(
                        selection: menuSelection,
                        screenMode: screenMode,
                        canChangeScreen: canChangeScreen,
                        paletteTitle: paletteTitle,
                        isMusicOn: isMusicOn,
                        isSoundOn: isSoundOn,
                        blinkOn: blinkOn,
                        u: u
                    )
                case .gameOver(let finalScore):
                    panel(
                        u: u,
                        title: String(localized: "GAME OVER"),
                        lines: (finalScore > 0 && finalScore >= highScore
                                ? [String(localized: "NEW HIGH SCORE!"), "\(finalScore)"]
                                : [String(localized: "SCORE \(finalScore)")])
                            + (hasModes ? ["< \(mode.title.uppercased()) >"] : []),
                        prompt: String(localized: "PRESS A TO RETRY")
                    )
                case .playing:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func panel(u: CGFloat, title: String, lines: [String], prompt: String) -> some View {
        VStack(spacing: u * 0.6) {
            Text(title)
                .font(.pixel(u * 1.5))
                .foregroundStyle(.white)
                .shadow(color: phosphor.opacity(0.8), radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.pixel(u * 0.85))
                    .foregroundStyle(phosphor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Text(prompt)
                .font(.pixel(u * 0.8))
                .foregroundStyle(phosphor)
                .opacity(blinkOn ? 1 : 0.15)
                .padding(.top, u * 0.4)
        }
        .padding(.horizontal, u * 1.5)
        .padding(.vertical, u * 1.2)
        .background(
            RoundedRectangle(cornerRadius: u * 0.5)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: u * 0.5).stroke(phosphor.opacity(0.35), lineWidth: 1))
        )
        .padding(u)
    }
}
