import SwiftUI
import UIKit

// MARK: - L'accueil « Atelier » (à l'essai, TestFlight seulement)
//
// Règles suivies (swiftui-design-skill, licence MIT) : une seule couleur d'accent chaude sur des neutres chauds,
// titres en serif (New York) et texte en SF Pro, grille de 8 points, symboles SF (pas d'emoji), cibles de 44 points,
// du vrai contenu tout de suite (pas de « Bienvenue »), une mise en page asymétrique et UN détail signature :
// la carte « ta main », qui montre ce que le clavier a appris de ta prise en main.

enum Atelier {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let bg = dyn(0xF5F3EF, 0x151412)
    static let surface = dyn(0xFFFFFF, 0x1F1E1B)
    static let sunk = dyn(0xEBE8E1, 0x2A2925)
    static let ink = dyn(0x1A1917, 0xF2F0EB)
    static let muted = dyn(0x75716A, 0x9C978E)
    static let accent = dyn(0xC4532F, 0xE2774F)     // terre cuite : la seule couleur
    static let accentSoft = dyn(0xF6E4DC, 0x3A2620)
    static let line = dyn(0xE3DFD6, 0x2E2C28)
    // Grille de 8 points.
    static let s1: CGFloat = 8, s2: CGFloat = 16, s3: CGFloat = 24, s4: CGFloat = 32
    static let radius: CGFloat = 16
}

/// Version d'essai (TestFlight) : on peut y montrer des choses en avant-première.
enum KBBuild {
    static let isTest: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}

struct AtelierHome: View {
    @Environment(SettingsModel.self) private var model
    @Environment(Store.self) private var store
    @Binding var showPro: Bool
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("atelierHome") private var atelier = true
    @State private var learn = KBVault.loadLearn()
    @State private var tryText = ""
    @FocusState private var tryFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Atelier.s3) {
                header
                hand
                HStack(alignment: .top, spacing: Atelier.s2) {
                    setupTile
                    proTile
                }
                .fixedSize(horizontal: false, vertical: true)
                tryField
                settings
                Label("Foldboard never sends what you type anywhere. It has no internet access, no account and no ads.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(Atelier.muted)
                Button { atelier = false } label: {
                    Text("Back to the classic design")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(Atelier.muted)
            }
            .padding(.horizontal, Atelier.s2)
            .padding(.top, Atelier.s1)
            .padding(.bottom, Atelier.s4)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenDuo()
        .background(Atelier.bg.ignoresSafeArea())
        .tint(Atelier.accent)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { learn = KBVault.loadLearn() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            learn = KBVault.loadLearn()
        }
    }

    // MARK: En haut : le nom, petit, et la date.

    private var header: some View {
        HStack(alignment: .center, spacing: Atelier.s2) {
            Image("Logo")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Foldboard")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(Atelier.ink)
                Text("The keyboard made for iPhone Duo")
                    .font(.footnote)
                    .foregroundStyle(Atelier.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Atelier.s2)
    }

    // MARK: Le détail signature : ta main

    private var hand: some View {
        let goal = LearningRow.goal
        let progress = Double(min(learn.all, goal)) / Double(goal)
        return VStack(alignment: .leading, spacing: Atelier.s2) {
            Text("Your hand")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Atelier.accent)
            HStack(alignment: .firstTextBaseline, spacing: Atelier.s1) {
                if let a = learn.accuracy {
                    Text(a, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 64, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(Atelier.ink)
                    Text("right side on its own")
                        .font(.subheadline)
                        .foregroundStyle(Atelier.muted)
                } else {
                    Text(verbatim: "\(learn.all)")
                        .font(.system(size: 64, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(Atelier.ink)
                    Text("habits learned")
                        .font(.subheadline)
                        .foregroundStyle(Atelier.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Une règle graduée : 25 habitudes, et le clavier te connaît.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<goal, id: \.self) { i in
                            Rectangle()
                                .fill(Atelier.line)
                                .frame(width: 1, height: i % 5 == 0 ? 12 : 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Capsule()
                        .fill(Atelier.accent)
                        .frame(width: max(4, g.size.width * progress), height: 4)
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
                .frame(height: 12, alignment: .bottom)
            }
            .frame(height: 12)
            HStack(spacing: Atelier.s2) {
                level("Duo closed", learn.closed)
                Rectangle().fill(Atelier.line).frame(width: 1, height: 32)
                level("Duo open", learn.open)
                Spacer(minLength: 0)
            }
            Text("Each time you type, or move the keyboard to the other side, Foldboard learns how you hold your Duo. The more you use it, the less you need to.")
                .font(.footnote)
                .foregroundStyle(Atelier.muted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { GripSetup().fullScreenDuo() } label: {
                Label { Text("Teach your thumbs · 30 s") } icon: { Image(systemName: "touchid") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Atelier.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(Atelier.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
    }

    private func level(_ name: LocalizedStringKey, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(Atelier.muted)
            Text(n == 0 ? LocalizedStringKey("Not yet") : (n < 10 ? LocalizedStringKey("Learning") : LocalizedStringKey("Knows you well")))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(n >= 10 ? Atelier.accent : Atelier.ink)
        }
    }

    // MARK: Deux tuiles : l'installation et Pro

    private var setupTile: some View {
        NavigationLink {
            SetupView(done: $setupDone).fullScreenDuo()
        } label: {
            tile(icon: setupDone ? "checkmark" : "keyboard.badge.ellipsis",
                 title: Text("Add Foldboard to your keyboards"),
                 detail: setupDone ? Text("Done") : Text("1 minute, 3 steps"),
                 filled: !setupDone)
        }
        .buttonStyle(.plain)
    }

    private var proTile: some View {
        Button { showPro = true } label: {
            tile(icon: store.access.purchased ? "checkmark.seal" : "sparkle",
                 title: Text(proTitle),
                 detail: Text(proDetail),
                 filled: false)
        }
        .buttonStyle(.plain)
    }

    private func tile(icon: String, title: Text, detail: Text, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(filled ? Color.white : Atelier.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? Atelier.accent : Atelier.accentSoft))
            Spacer(minLength: Atelier.s1)
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Atelier.ink)
                .fixedSize(horizontal: false, vertical: true)
            detail
                .font(.caption)
                .foregroundStyle(Atelier.muted)
                .lineLimit(3)
        }
        .padding(Atelier.s2)
        .frame(maxWidth: .infinity, minHeight: 136, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
        .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
        .contentShape(Rectangle())
    }

    private var proTitle: LocalizedStringKey {
        if store.access.purchased { return "Foldboard Pro is unlocked" }
        if store.isPro { return "Free trial in progress" }
        if store.access.trialOver() { return "Your free trial is over" }
        return "Try everything free for 3 days"
    }

    private var proDetail: String {
        if store.access.purchased { return NSLocalizedString("Thank you!", comment: "") }
        if store.isPro, let end = store.access.trialEnd {
            return String(format: NSLocalizedString("Until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened))
        }
        if store.access.trialOver() { return NSLocalizedString("Unlock Foldboard Pro to keep two hands, follow-your-hand, colors and phrases.", comment: "") }
        return NSLocalizedString("Two hands, follow-your-hand, colors, fonts, sounds and your phrases.", comment: "")
    }

    // MARK: Essayer

    private var tryField: some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            sectionTitle(Text("Try it"))
            HStack(alignment: .top, spacing: Atelier.s1) {
                TextField("Type here to try Foldboard", text: $tryText, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($tryFocus)
                    .foregroundStyle(Atelier.ink)
                if !tryText.isEmpty {
                    Button { tryText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Atelier.muted).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, Atelier.s2)
            .padding(.vertical, 12)
            .frame(minHeight: 88, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.sunk))
            .onTapGesture { tryFocus = true }
            Text("Tap the field, then hold the globe key and pick Foldboard.")
                .font(.caption)
                .foregroundStyle(Atelier.muted)
        }
    }

    // MARK: Réglages : une seule liste, des icônes de même poids

    private var settings: some View {
        VStack(alignment: .leading, spacing: Atelier.s1) {
            sectionTitle(Text("Make it yours"))
            VStack(spacing: 0) {
                link("hand.raised.fingers.spread", "Position and size") { PositionView().fullScreenDuo() }
                divider
                link("character.cursor.ibeam", "Typing") { TypingView().fullScreenDuo() }
                divider
                link("paintpalette", "Colors and font") { LookView().fullScreenDuo() }
                divider
                link("waveform", "Sound, vibrations and swipe") { FeelView().fullScreenDuo() }
                divider
                link("text.bubble", "Phrases and emoji") { PhrasesView().fullScreenDuo() }
            }
            .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
            .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
            sectionTitle(Text("Learn"))
                .padding(.top, Atelier.s2)
            VStack(spacing: 0) {
                link("touchid", "Teach your thumbs") { GripSetup().fullScreenDuo() }
                divider
                link("hand.tap", "How it works") { PlaceTutorial().fullScreenDuo() }
                divider
                link("play.rectangle", "Guided tour") { KeyboardTourScreen() }
                divider
                link("rectangle.topthird.inset.filled", "The keyboard buttons") { ButtonsGuide().fullScreenDuo() }
            }
            .background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
            .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
        }
    }

    private var divider: some View {
        Rectangle().fill(Atelier.line).frame(height: 1).padding(.leading, 56)
    }

    private func link<D: View>(_ icon: String, _ title: LocalizedStringKey, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: Atelier.s2) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Atelier.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Atelier.ink)
                Spacer(minLength: Atelier.s1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Atelier.muted.opacity(0.6))
            }
            .padding(.horizontal, Atelier.s2)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ t: Text) -> some View {
        t.font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(Atelier.ink)
    }
}
