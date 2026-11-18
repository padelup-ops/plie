//
//  ClassicGreySkin.swift
//  RetroCartridge
//

import SwiftUI

extension SkinTheme {
    static let classicGrey = SkinTheme(
        bodyColor: Color(red: 155/255, green: 155/255, blue: 155/255), // #9B9B9B
        buttonColor: Color(red: 60/255, green: 60/255, blue: 60/255), // #3C3C3C
        accentColor: Color(red: 107/255, green: 123/255, blue: 141/255), // #6B7B8D
        textColor: Color(red: 44/255, green: 44/255, blue: 44/255), // #2C2C2C
        screenBorderColor: Color(red: 28/255, green: 28/255, blue: 28/255), // #1C1C1C
        actionButtonColor: Color(hex: "#A8325E"), // deep magenta, like classic handheld A/B
        finish: .matte
    )
}
