//
//  ClearIceSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let clearIce = SkinTheme(
        bodyColor: Color(hex: "#A8DADC").opacity(0.55), // icy blue, see-through
        buttonColor: Color(hex: "#E8F4F8"),
        accentColor: Color(hex: "#48CAE4"),
        textColor: Color(hex: "#023E8A"),
        screenBorderColor: Color(hex: "#0077B6"),
        actionButtonColor: Color(hex: "#90E0EF"),
        finish: .translucent,
        bezelTopColor: Color(hex: "#1D3557"),
        bezelBottomColor: Color(hex: "#0B1A2E"),
        ledColor: Color(hex: "#48CAE4"),
        menu: MenuTheme(accent: "#48CAE4", panel: ("#152630", "#0A141A"))
    )
}
