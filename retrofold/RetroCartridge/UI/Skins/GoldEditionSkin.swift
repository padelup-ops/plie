//
//  GoldEditionSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let goldEdition = SkinTheme(
        bodyColor: Color(hex: "#C9A227"), // polished gold
        buttonColor: Color(hex: "#2B2B2B"),
        accentColor: Color(hex: "#FFE8A3"),
        textColor: Color(hex: "#3B2F0B"),
        screenBorderColor: Color(hex: "#6B5410"),
        actionButtonColor: Color(hex: "#2B2B2B"),
        finish: .glossy,
        bezelTopColor: Color(hex: "#2A2410"),
        bezelBottomColor: Color(hex: "#15120A"),
        ledColor: Color(hex: "#FFE8A3"),
        menu: MenuTheme(accent: "#FFE8A3", panel: ("#262012", "#130F08"))
    )
}
