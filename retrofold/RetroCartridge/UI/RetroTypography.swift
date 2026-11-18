//
// RetroTypography.swift
// RetroCartridge
//
// Text in the overlays and the library follows the reader's text size and
// Bold Text setting while keeping the pixel retro look (Silkscreen, OFL,
// bundled in Resources). The console itself (bezel, tube, silkscreen,
// cartridge labels) stays as printed: its text is part of the hardware and
// scales with it instead.
//

import SwiftUI

extension View {
    /// Sets the pixel font that grows with Dynamic Type and gets one step
    /// heavier with Bold Text.
    /// - Parameters:
    ///   - size: The point size at the default text size (Large).
    ///   - design: A system font design to use instead of the pixel font, for
    ///     SF Symbols, which take their weight only from a system font.
    ///   - maxScale: The most the text may grow, so headings keep panels in shape.
    ///   - wraps: Whether text limited to one line may wrap at accessibility
    ///     sizes rather than shrink until it's unreadable.
    func retroFont(
        _ size: CGFloat,
        weight: Font.Weight = .bold,
        design: Font.Design? = nil,
        maxScale: CGFloat = 2,
        wraps: Bool = true
    ) -> some View {
        modifier(RetroFont(size: size, weight: weight, design: design, maxScale: maxScale, wraps: wraps))
    }
}

extension Font {
    /// The pixel font at a fixed size, for the console's printed text (bezel,
    /// tube, silkscreen, cartridge labels), which scales with the console
    /// rather than with Dynamic Type.
    /// - Parameter bold: Silkscreen Bold, only for glyphs that stay open in
    ///   it (its W, M and N fill in).
    static func pixel(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(RetroType.pixelFontName(isBold: bold), fixedSize: size)
    }
}

private struct RetroFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design?
    let maxScale: CGFloat
    let wraps: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        let wrapsHere = wraps && dynamicTypeSize.isAccessibilitySize

        let scaledSize = size * min(maxScale, RetroType.scale(for: dynamicTypeSize))
        let isBold = legibilityWeight == .bold
        let scaledWeight = RetroType.weight(weight, isBold: isBold)

        content
            .font(design.map { .system(size: scaledSize, weight: scaledWeight, design: $0) }
                ?? .custom(RetroType.pixelFontName(isBold: isBold), fixedSize: scaledSize))
            // Closer to the text than the view's own `lineLimit(1)`, so it wins
            .transformEnvironment(\.lineLimit) { limit in
                if wrapsHere { limit = nil }
            }
    }
}

/// How overlay text follows the reader's settings.
enum RetroType {

    // MARK: Text size

    /// How much text grows at a Dynamic Type size, relative to Large (the
    /// default), following the body style (17 pt at Large).
    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 14.0 / 17
        case .small: return 15.0 / 17
        case .medium: return 16.0 / 17
        case .large: return 1
        case .xLarge: return 19.0 / 17
        case .xxLarge: return 21.0 / 17
        case .xxxLarge: return 23.0 / 17
        case .accessibility1: return 28.0 / 17
        case .accessibility2: return 33.0 / 17
        case .accessibility3: return 40.0 / 17
        case .accessibility4: return 47.0 / 17
        case .accessibility5: return 53.0 / 17
        @unknown default: return 1
        }
    }

    // MARK: Pixel font

    /// The bundled pixel font's PostScript names (registered through `UIAppFonts`).
    static let pixelRegular = "Silkscreen-Regular"
    static let pixelBold = "Silkscreen-Bold"

    /// The pixel font cut. Silkscreen has only Regular and a much heavier
    /// Bold whose W, M and N fill in at overlay sizes, so text is Regular at
    /// every weight and Bold only with Bold Text. Headings stand out by size
    /// and color instead.
    static func pixelFontName(isBold: Bool) -> String {
        isBold ? pixelBold : pixelRegular
    }

    // MARK: Bold Text

    /// One step heavier with Bold Text.
    static func weight(_ weight: Font.Weight, isBold: Bool) -> Font.Weight {
        guard isBold else { return weight }
        switch weight {
        case .ultraLight: return .thin
        case .thin: return .light
        case .light: return .regular
        case .regular: return .medium
        case .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return .black
        }
    }
}
