//
// PauseMenu.swift
// RetroCartridge
//
// The on-screen display shown inside the tube while a game is paused, like
// a TV's settings menu: resume, screen mode, palette, eject. The controller drives it (D-Pad moves and changes,
// A selects, B resumes, Start still resumes through the game), so games
// stay unaware of it. It sits in the CRT, next to the content it affects.
//

import SwiftUI

// MARK: - Items

/// A row of the pause menu.
enum PauseMenuItem: Int, CaseIterable, Sendable {
    case resume
    case screen
    case palette
    case music
    case sound
    case eject

    var title: String {
        switch self {
        case .resume: return String(localized: "RESUME", comment: "Pause menu row")
        case .screen: return String(localized: "SCREEN", comment: "Pause menu row")
        case .palette: return String(localized: "PALETTE", comment: "Pause menu row")
        case .music: return String(localized: "MUSIC", comment: "Pause menu row")
        case .sound: return String(localized: "SOUND", comment: "Pause menu row: sound effects")
        case .eject: return String(localized: "EJECT", comment: "Pause menu row")
        }
    }
}

// MARK: - Input

enum PauseMenu {

    /// What pressing a button in the pause menu did, for feedback.
    enum Outcome {
        case moved
        case changed
        case confirmed
        case ignored
    }

    /// Screen modes the player can switch between from the menu.
    @MainActor
    static func availableScreenModes(store: StoreManager) -> [ScreenMode] {
        ScreenMode.allCases.filter { store.isUnlocked($0) }
    }

    /// Applies a controller press to the pause menu.
    /// - Parameters:
    ///   - screenModes: The modes the player may switch between.
    ///   - currentScreen: The mode being drawn now.
    @discardableResult
    static func handle(
        _ action: GameInputAction,
        appState: AppState,
        screenModes: [ScreenMode],
        currentScreen: ScreenMode
    ) -> Outcome {
        let items = PauseMenuItem.allCases
        let selection = appState.pauseMenuSelection

        switch action {
        case .dpadUpPressed, .dpadDownPressed:
            let step = action == .dpadUpPressed ? -1 : 1
            let index = (selection.rawValue + step + items.count) % items.count
            appState.pauseMenuSelection = items[index]
            return .moved

        case .dpadLeftPressed, .dpadRightPressed:
            let step = action == .dpadLeftPressed ? -1 : 1
            switch selection {
            case .screen:
                return cycleScreen(by: step, appState: appState, modes: screenModes, current: currentScreen)
            case .palette:
                return cyclePalette(by: step, appState: appState)
            case .music:
                appState.isMusicOn.toggle()
                return .changed
            case .sound:
                appState.isSoundOn.toggle()
                return .changed
            case .resume, .eject:
                return .ignored
            }

        case .buttonAPressed:
            switch selection {
            case .resume:
                resume(appState)
                return .confirmed
            case .screen:
                return cycleScreen(by: 1, appState: appState, modes: screenModes, current: currentScreen)
            case .palette:
                return cyclePalette(by: 1, appState: appState)
            case .music:
                appState.isMusicOn.toggle()
                return .changed
            case .sound:
                appState.isSoundOn.toggle()
                return .changed
            case .eject:
                appState.ejectCartridge()
                return .confirmed
            }

        case .buttonBPressed:
            resume(appState)
            return .confirmed

        default:
            return .ignored
        }
    }

    private static func resume(_ appState: AppState) {
        appState.pauseMenuSelection = .resume
        appState.activeGame?.resume()
    }

    private static func cyclePalette(by step: Int, appState: AppState) -> Outcome {
        let palettes = PaletteChoice.allCases
        let index = palettes.firstIndex(of: appState.paletteChoice) ?? 0
        appState.paletteChoice = palettes[(index + step + palettes.count) % palettes.count]
        return .changed
    }

    private static func cycleScreen(by step: Int, appState: AppState, modes: [ScreenMode], current: ScreenMode) -> Outcome {
        guard modes.count > 1 else { return .ignored }
        let index = modes.firstIndex(of: current) ?? 0
        appState.screenSettings.mode = modes[(index + step + modes.count) % modes.count]
        return .changed
    }
}

// MARK: - On-screen display

/// The pause menu as drawn inside the tube, in the phosphor style of the
/// other in-tube messages.
struct PauseMenuPanel: View {
    let selection: PauseMenuItem
    let screenMode: ScreenMode
    let canChangeScreen: Bool
    let paletteTitle: String
    let isMusicOn: Bool
    let isSoundOn: Bool
    let blinkOn: Bool
    /// Base unit, 1/20 of the tube's shorter side.
    let u: CGFloat

    private let phosphor = Color(hex: "#9CFFB8")

    var body: some View {
        VStack(alignment: .leading, spacing: u * 0.55) {
            Text("PAUSED")
                .font(.pixel(u * 1.4))
                .foregroundStyle(.white)
                .shadow(color: phosphor.opacity(0.8), radius: 6)
                .frame(maxWidth: .infinity)
                .padding(.bottom, u * 0.3)

            ForEach(PauseMenuItem.allCases, id: \.self) { item in
                row(item)
            }

            Text("START RESUMES")
                .font(.pixel(u * 0.65))
                .foregroundStyle(phosphor.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.top, u * 0.3)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, u * 1.3)
        .padding(.vertical, u * 1.0)
        .background(
            RoundedRectangle(cornerRadius: u * 0.5)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: u * 0.5).stroke(phosphor.opacity(0.35), lineWidth: 1))
        )
        .padding(u)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paused. \(selection.title.capitalized) selected. Screen: \(screenMode.title). Palette: \(paletteTitle). Music \(onOff(isMusicOn)), sound \(onOff(isSoundOn)).")
    }

    /// The setting shown at the end of a row, with arrows when it can change.
    private func value(of item: PauseMenuItem) -> String? {
        switch item {
        case .screen:
            return canChangeScreen ? "< \(screenMode.uppercasedTitle) >" : screenMode.uppercasedTitle
        case .palette:
            return "< \(paletteTitle.uppercased()) >"
        case .music:
            return "< \(isMusicOn ? String(localized: "ON") : String(localized: "OFF")) >"
        case .sound:
            return "< \(isSoundOn ? String(localized: "ON") : String(localized: "OFF")) >"
        case .resume, .eject:
            return nil
        }
    }

    private func onOff(_ isOn: Bool) -> String {
        isOn ? String(localized: "on") : String(localized: "off")
    }

    private func row(_ item: PauseMenuItem) -> some View {
        let isSelected = item == selection

        return HStack(spacing: u * 0.5) {
            Text(verbatim: ">")
                .opacity(isSelected ? (blinkOn ? 1 : 0.35) : 0)
            Text(item.title)
            if let value = value(of: item) {
                Spacer(minLength: u * 0.5)
                Text(value)
                    .foregroundStyle(phosphor.opacity(isSelected ? 1 : 0.6))
            }
        }
        .font(.pixel(u * 0.85))
        .foregroundStyle(isSelected ? Color.white : phosphor.opacity(0.75))
    }
}
