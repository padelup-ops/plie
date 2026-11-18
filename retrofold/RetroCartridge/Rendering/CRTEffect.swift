// CRTEffect.swift
// RetroCartridge
//
// SwiftUI bridge that applies the `screenEffect` Metal shader as a layer
// effect, drawing the game through the chosen screen (`ScreenSettings`).

import SwiftUI

extension View {

    /// Renders this view through the chosen screen.
    /// - Parameters:
    ///   - settings: The screen mode and its tuning.
    ///   - hingeAngle: Hinge angle in degrees (0 = closed, 180 = flat).
    ///     Used only for the visual curvature, never for layout (per Apple HIG).
    ///   - powerOnProgress: Power-on animation progress from 0 (off) to 1 (on).
    func screenEffect(_ settings: ScreenSettings, hingeAngle: Float, powerOnProgress: Double) -> some View {
        let normalizedAngle = Double(max(0, min(1, hingeAngle / 180)))
        // 0 when flat, 1 when closed. Eased so the first few degrees of
        // folding stay gentle and the tube bulges more the further it folds.
        let fold = pow(1 - normalizedAngle, 1.5)
        // Subtle curvature when flat, more pronounced as the device folds.
        let tubeCurvature = 0.06 + 0.14 * fold

        let modeCurvature: Double
        switch settings.mode {
        case .crt: modeCurvature = tubeCurvature
        case .lcd: modeCurvature = 0
        case .trinitron: modeCurvature = tubeCurvature * 0.8
        case .arcade: modeCurvature = tubeCurvature * 1.35
        }

        // Tuning runs 0...1 with 0.5 as designed, so each control scales 0...2×.
        return layerEffect(
            ShaderLibrary.screenEffect(
                .boundingRect,
                .float(settings.mode.shaderIndex),
                .float(Float(modeCurvature * settings.curvature * 2)),
                .float(Float(fold)),
                .float(Float(max(0, min(1, powerOnProgress)))),
                .float(Float(settings.scanlines * 2)),
                .float(Float(settings.bleed * 2))
            ),
            maxSampleOffset: CGSize(width: 8, height: 8)
        )
    }
}
