//
//  CrimsonCreamSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let crimsonCream = SkinTheme(
        bodyColor: Color(hex: "#F1E9DA"), // cream, like an 8-bit family console
        buttonColor: Color(hex: "#3A3A3A"),
        accentColor: Color(hex: "#B5121B"),
        textColor: Color(hex: "#B5121B"),
        screenBorderColor: Color(hex: "#7A0C12"),
        actionButtonColor: Color(hex: "#B5121B"),
        finish: .matte,
        bezelTopColor: Color(hex: "#8E1B22"),
        bezelBottomColor: Color(hex: "#5C0F14"),
        menu: MenuTheme(accent: "#FF5A64", panel: ("#29191A", "#140C0D"))
    )
}
