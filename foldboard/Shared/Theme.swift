import UIKit

/// Les couleurs du clavier.
struct KBTheme: Identifiable, Equatable {
    let id: String
    /// Nom affiché (clé de traduction).
    let name: String
    let background: UIColor
    let key: UIColor
    let special: UIColor
    let text: UIColor
    let accent: UIColor

    private static func c(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// Suit le mode clair / sombre de l'iPhone.
    static let auto = KBTheme(
        id: "auto", name: "Automatic",
        background: UIColor { $0.userInterfaceStyle == .dark ? c(0x1C1C1F) : c(0xD3D6DD) },
        key: UIColor { $0.userInterfaceStyle == .dark ? c(0x48484D) : c(0xFFFFFF) },
        special: UIColor { $0.userInterfaceStyle == .dark ? c(0x2E2E33) : c(0xADB2BC) },
        text: UIColor { $0.userInterfaceStyle == .dark ? c(0xFFFFFF) : c(0x0D0E11) },
        accent: c(0x2F7CF6))

    static let all: [KBTheme] = [
        auto,
        KBTheme(id: "cloud", name: "Cloud", background: c(0xE6E8EE), key: c(0xFFFFFF), special: c(0xC7CCD6), text: c(0x111318), accent: c(0x2F7CF6)),
        KBTheme(id: "night", name: "Night", background: c(0x0E0F13), key: c(0x24262D), special: c(0x17181D), text: c(0xF2F3F5), accent: c(0x7FA8FF)),
        KBTheme(id: "mint", name: "Mint", background: c(0xD8F1E7), key: c(0xF7FFFB), special: c(0xA9DDC8), text: c(0x0D3B2C), accent: c(0x11B787)),
        KBTheme(id: "peach", name: "Peach", background: c(0xFBE3D6), key: c(0xFFF8F3), special: c(0xF2BFA6), text: c(0x4A2112), accent: c(0xEF5B2A)),
        KBTheme(id: "lavender", name: "Lavender", background: c(0xE5E0F7), key: c(0xFBFAFF), special: c(0xC3B8EC), text: c(0x251A4D), accent: c(0x7B5CE0)),
        KBTheme(id: "slate", name: "Slate", background: c(0x2A3140), key: c(0x3B4456), special: c(0x222835), text: c(0xEEF1F6), accent: c(0x5BC0EB)),
        KBTheme(id: "sun", name: "Sun", background: c(0xFFF1C2), key: c(0xFFFDF5), special: c(0xF5D77A), text: c(0x3D2E00), accent: c(0xE0A100)),
    ]

    static func named(_ id: String) -> KBTheme { all.first { $0.id == id } ?? auto }
}

extension KBFont {
    func ui(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .system: return base
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        guard let d = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}
