//
//  AtomicPurpleSkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let atomicPurple = SkinTheme(
        bodyColor: Color(red: 123/255, green: 47/255, blue: 190/255).opacity(0.7), // #7B2FBE, 0.7 opacity
        buttonColor: Color(red: 74/255, green: 14/255, blue: 120/255), // #4A0E78
        accentColor: Color(red: 255/255, green: 0, blue: 255/255), // #FF00FF
        textColor: .white,
        screenBorderColor: Color(red: 42/255, green: 8/255, blue: 69/255), // #2A0845
        actionButtonColor: Color(hex: "#E040FB"), // bright orchid
        finish: .translucent,
        bezelTopColor: Color(hex: "#2A1540"), // smoky purple bezel, green LED
        bezelBottomColor: Color(hex: "#150A22"),
        ledColor: Color(hex: "#7CFF6B"),
        menu: MenuTheme(accent: "#E040FB", panel: ("#221630", "#120B1A"))
    )
}
