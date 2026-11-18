//
//  ArcadeCabinetSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let arcadeCabinet = SkinTheme(
        bodyColor: Color(red: 92/255, green: 64/255, blue: 51/255), // #5C4033
        buttonColor: Color(red: 255/255, green: 0, blue: 0), // #FF0000
        accentColor: Color(red: 255/255, green: 215/255, blue: 0), // #FFD700
        textColor: Color(red: 255/255, green: 215/255, blue: 0), // #FFD700
        screenBorderColor: Color(red: 59/255, green: 35/255, blue: 22/255), // #3B2316
        actionButtonColor: Color(hex: "#E53935"), // arcade red
        finish: .woodGrain,
        bezelTopColor: Color(hex: "#1A1A1A"), // black lacquer bezel, amber LED
        bezelBottomColor: Color(hex: "#0A0A0A"),
        ledColor: Color(hex: "#FFB300"),
        menu: MenuTheme(accent: "#FFD700", panel: ("#271C15", "#140E0A"))
    )
}
