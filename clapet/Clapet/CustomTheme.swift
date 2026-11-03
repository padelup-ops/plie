import SwiftUI
import UIKit

/// « Mon thème » (Foldly+) : tes propres couleurs, pour l'accent et le fond (un dégradé du haut vers le bas).
/// La mise en page est celle du Moderne ; le texte passe en clair ou en sombre selon le fond choisi.
enum CustomTheme {
    static let accentKey = "customAccent"
    static let topKey = "customTop"
    static let bottomKey = "customBottom"

    static let defaultAccent = "#FFB45C"
    static let defaultTop = "#3B1F5C"
    static let defaultBottom = "#0E0B1F"

    static var accent: Color { Color(hex: UserDefaults.standard.string(forKey: accentKey) ?? defaultAccent) }
    static var top: Color { Color(hex: UserDefaults.standard.string(forKey: topKey) ?? defaultTop) }
    static var bottom: Color { Color(hex: UserDefaults.standard.string(forKey: bottomKey) ?? defaultBottom) }

    /// Fond sombre : texte clair.
    static var isDark: Bool { (top.luminance + bottom.luminance) / 2 < 0.5 }

    /// Les cartes : un voile clair sur fond sombre, sombre sur fond clair.
    static var card: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    static var solid: Color { bottom }

    /// Quelques idées toutes prêtes.
    static let presets: [(name: LocalizedStringKey, accent: String, top: String, bottom: String)] = [
        ("Sunset", "#FFB45C", "#5C2A4F", "#170B1E"),
        ("Ocean", "#5CE1FF", "#0F3B5C", "#06121F"),
        ("Forest", "#9BE15C", "#1F3B2A", "#08140D"),
        ("Rose", "#FF5C8A", "#FFE4EC", "#FFF7F9"),
        ("Paper", "#2F6BFF", "#FAF7F0", "#EFEAE0"),
    ]

    static func apply(accent: String, top: String, bottom: String) {
        UserDefaults.standard.set(accent, forKey: accentKey)
        UserDefaults.standard.set(top, forKey: topKey)
        UserDefaults.standard.set(bottom, forKey: bottomKey)
    }
}

/// Le fond de « Mon thème ».
struct CustomBackdrop: View {
    var body: some View {
        LinearGradient(colors: [CustomTheme.top, CustomTheme.bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Les réglages de « Mon thème » (dans Réglages › Apparence).
struct CustomThemeEditor: View {
    @AppStorage(CustomTheme.accentKey) private var accentHex = CustomTheme.defaultAccent
    @AppStorage(CustomTheme.topKey) private var topHex = CustomTheme.defaultTop
    @AppStorage(CustomTheme.bottomKey) private var bottomHex = CustomTheme.defaultBottom

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CustomTheme.presets.indices, id: \.self) { i in
                    let p = CustomTheme.presets[i]
                    Button {
                        accentHex = p.accent; topHex = p.top; bottomHex = p.bottom
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                LinearGradient(colors: [Color(hex: p.top), Color(hex: p.bottom)], startPoint: .top, endPoint: .bottom)
                                Circle().fill(Color(hex: p.accent)).frame(width: 14, height: 14)
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(accentHex == p.accent && topHex == p.top ? 0.9 : 0.12), lineWidth: 2))
                            Text(p.name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        ColorPicker(selection: binding($accentHex), supportsOpacity: false) { Text("Accent color") }
        ColorPicker(selection: binding($topHex), supportsOpacity: false) { Text("Background, top") }
        ColorPicker(selection: binding($bottomHex), supportsOpacity: false) { Text("Background, bottom") }
    }

    private func binding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = { (x: CGFloat) in Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
