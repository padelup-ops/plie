//
//  ElectricYellowSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let electricYellow = SkinTheme(
        bodyColor: Color(hex: "#FFD60A"), // bright yellow
        buttonColor: Color(hex: "#1D3557"),
        accentColor: Color(hex: "#E63946"),
        textColor: Color(hex: "#3D2C00"),
        screenBorderColor: Color(hex: "#3D2C00"),
        actionButtonColor: Color(hex: "#1D3557"),
        finish: .matte,
        ledColor: Color(hex: "#E63946"),
        menu: MenuTheme(accent: "#FFD60A", panel: ("#24220F", "#121107"))
    )
}
