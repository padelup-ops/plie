import SwiftUI
import UIKit

// PADELUP NEO : style épuré, dans la lignée des autres apps PadelUp (thème Bento de Foldly).
// Une seule famille de gris chauds, des cartes blanches, UNE couleur d'accent (le bleu PadelUp #094A73),
// une carte « héros » bleu profond, pas de dégradé ni de néon. Clair ou sombre selon l'iPhone.
enum UI {
    static func dyn(_ light: UInt32, _ dark: UInt32, _ alpha: CGFloat = 1) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: alpha)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    static let bg = dyn(0xF6F6F3, 0x0F0F0E)
    static let tray = dyn(0xECECE8, 0x1A1A18)
    static let card = dyn(0xFFFFFF, 0x1C1C1A)
    static let ink = dyn(0x141413, 0xF2F2EE)
    static let muted = dyn(0x6B6B66, 0x9A9A93)
    static let faint = dyn(0xA6A6A0, 0x66665F)
    static let line = dyn(0x000000, 0xFFFFFF, 0.08)
    static let accent = dyn(0x094A73, 0x6AB4E0)      // bleu PadelUp
    static let onAccent = dyn(0xFFFFFF, 0x0B1A24)
    static let tint = dyn(0xE7F0F6, 0x15283A)
    static let hero = dyn(0x094A73, 0x0C3A57)        // la carte héros, bleu profond dans les deux thèmes
    static let success = dyn(0x0F9F6E, 0x3ECF97)
    static let warning = dyn(0xB25E09, 0xF2A33A)
    static let danger = dyn(0xD12C2C, 0xF27272)
    static let ball = Color(red: 0.85, green: 0.95, blue: 0.29)  // la balle, réservée au logo

    static let radius: CGFloat = 22

    static func largeTitle() -> Font { .system(size: 34, weight: .bold) }
    static func title() -> Font { .system(size: 22, weight: .bold) }
    static func headline() -> Font { .system(size: 17, weight: .semibold) }
    static func body() -> Font { .system(size: 16) }
    static func callout() -> Font { .system(size: 15) }
    static func caption() -> Font { .system(size: 13) }
    static func small() -> Font { .system(size: 12, weight: .medium) }
    static func number(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
}

// Carte : fond blanc (ou gris très sombre), coins doux, filet discret. Pas d'ombre, pas de verre.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = UI.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.line, lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = UI.card) -> some View { modifier(CardStyle(padding: padding, fill: fill)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = UI.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UI.headline())
            .foregroundStyle(UI.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(color))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = UI.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(UI.tray))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Petit bouton texte (« Connecter », « Vérifier »…).
struct LinkButtonStyle: ButtonStyle {
    var color: Color = UI.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold)).foregroundStyle(color).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct Pill: View {
    var text: String
    var systemImage: String? = nil
    var active = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(UI.small())
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .foregroundStyle(active ? UI.onAccent : UI.ink)
        .background(Capsule().fill(active ? UI.accent : UI.tray))
    }
}

/// Étiquette d'information (couleur sémantique, fond très léger).
struct Tag: View {
    var text: String
    var systemImage: String? = nil
    var color: Color = UI.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(UI.headline()).foregroundStyle(UI.ink)
            Spacer()
            if let trailing { Text(trailing).font(UI.caption()).foregroundStyle(UI.muted) }
        }
        .padding(.horizontal, 4)
    }
}

struct Metric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(UI.number(26)).foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
        }
        .card(padding: 14)
    }
}

struct IconBadge: View {
    var systemImage: String
    var color: Color = UI.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.12)))
    }
}

/// Le logo : une balle de padel, à plat.
struct BallMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(UI.ball)
            Circle().trim(from: 0.1, to: 0.4).stroke(Color.white, lineWidth: size * 0.07).rotationEffect(.degrees(-36)).padding(size * 0.14)
            Circle().trim(from: 0.6, to: 0.9).stroke(Color.white, lineWidth: size * 0.07).rotationEffect(.degrees(-36)).padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 28, weight: .regular)).foregroundStyle(UI.faint)
            Text(title).font(UI.headline()).foregroundStyle(UI.ink)
            Text(message).font(UI.callout()).foregroundStyle(UI.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .card(padding: 0)
    }
}

/// Champ de saisie sobre.
struct InputField: View {
    var title: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if secure { SecureField(title, text: $text) } else {
                TextField(title, text: $text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .font(UI.body())
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.tray))
    }
}

/// Mise en page commune : fond, défilement, marges.
struct Screen<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(UI.largeTitle()).foregroundStyle(UI.ink)
                    if let subtitle { Text(subtitle).font(UI.callout()).foregroundStyle(UI.muted) }
                }
                .padding(.horizontal, 4)
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(UI.bg.ignoresSafeArea())
    }
}
