//
//  CyberpunkNeonSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let cyberpunkNeon = SkinTheme(
        bodyColor: Color(red: 13/255, green: 13/255, blue: 13/255), // #0D0D0D
        buttonColor: Color(red: 26/255, green: 26/255, blue: 46/255), // #1A1A2E
        accentColor: Color(red: 0, green: 255/255, blue: 255/255), // #00FFFF
        textColor: Color(red: 255/255, green: 20/255, blue: 147/255), // #FF1493
        screenBorderColor: Color(red: 0, green: 255/255, blue: 255/255), // #00FFFF
        actionButtonColor: Color(hex: "#FF2E88"), // hot pink
        finish: .glossy,
        bezelTopColor: Color(hex: "#0B0B14"), // black glass bezel, cyan LED
        bezelBottomColor: Color(hex: "#050508"),
        ledColor: Color(hex: "#00FFFF"),
        menu: MenuTheme(accent: "#00FFFF", panel: ("#111D20", "#080D0F"))
    )
}
