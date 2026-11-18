//
//  SkinManager.swift
//  RetroCartridge
//

import SwiftUI

/// The surface of a console shell. Drawn by the console artwork.
enum SkinFinish: Sendable {
    /// Flat, lightly textured plastic.
    case matte
    /// Polished plastic with a strong highlight.
    case glossy
    /// See-through plastic that shows the parts inside.
    case translucent
    /// Wood-grain laminate, like an arcade cabinet.
    case woodGrain
}

struct SkinTheme: Equatable, Sendable {
    var bodyColor: Color
    var buttonColor: Color
    var accentColor: Color
    var textColor: Color
    var screenBorderColor: Color
    /// Fill color of the A / B action buttons.
    var actionButtonColor: Color
    /// Surface of the shell.
    var finish: SkinFinish

    // MARK: Screen bezel

    /// Top of the screen bezel's vertical gradient.
    var bezelTopColor: Color = Color(hex: "#2B2E35")
    /// Bottom of the screen bezel's vertical gradient.
    var bezelBottomColor: Color = Color(hex: "#17191D")
    /// The power LED while a game is running.
    var ledColor: Color = Color(hex: "#FF3B30")

    // MARK: Menus

    /// Colors for the library, cover and overlays while this skin is equipped.
    var menu: MenuTheme = .classic
}

enum SkinManager {
    static func theme(for skin: ConsoleSkinType) -> SkinTheme {
        switch skin {
        case .classicGrey:
            return .classicGrey
        case .atomicPurple:
            return .atomicPurple
        case .cyberpunkNeon:
            return .cyberpunkNeon
        case .arcadeCabinet:
            return .arcadeCabinet
        case .clearIce:
            return .clearIce
        case .crimsonCream:
            return .crimsonCream
        case .electricYellow:
            return .electricYellow
        case .goldEdition:
            return .goldEdition
        }
    }
}
