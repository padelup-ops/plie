// GamePakScreens.swift
// RetroCartridge
//
// The Game Pak's touch screen (DS) on the console, and the full-screen view
// used while a game controller is connected.

import SwiftUI

/// Over the console's screen: touches go to the DS touch screen.
struct GamePakTouchLayer: View {
    let game: GamePakGame

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { game.touch(at: $0.location, in: geo.size) }
                        .onEnded { _ in game.touch(at: nil, in: geo.size) }
                )
        }
    }
}

/// With a game controller, the game fills the display (no console around it). The console underneath keeps
/// running the game; this only draws it bigger.
struct GamePakFullScreenHost: View {
    @Environment(AppState.self) private var appState
    @Environment(PostureManager.self) private var postureManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { _ in
            if let pak = appState.activeGame as? GamePakGame, pak.gameState == .playing,
               !postureManager.isCompactWidth, !appState.isEjecting {
                if pak.isDS {
                    // DS: both screens over the whole open Duo; on-screen buttons unless a controller is connected.
                    GamePakDSScreen(game: pak, showsButtons: !GamePakGame.hasController)
                        .transition(.opacity)
                } else if GamePakGame.hasController {
                    GamePakFullScreen(game: pak)
                        .transition(.opacity)
                }
            }
        }
    }
}

private struct GamePakFullScreen: View {
    let game: GamePakGame

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { [date = timeline.date] context, size in
                _ = date
                game.render(context: &context, size: size)
            }
        }
        .overlay {
            if game.acceptsTouch { GamePakTouchLayer(game: game) }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .accessibilityLabel("Game Pak screen")
    }
}
