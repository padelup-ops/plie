import SwiftUI
import StoreKit
import UIKit

// MARK: - Le look de l'app, au choix
//
// « Classique » : comme l'app Santé, clair ou sombre selon l'iPhone.
// « Moderne » : sombre, grands chiffres, jauge, onglets Aujourd'hui / Semaine.
// « Épuré » : noir sur blanc (ou blanc sur noir), un grand chiffre fin, aucune carte ni couleur.
// Choisi au premier lancement, modifiable dans les Réglages.

enum DFLook: String, CaseIterable, Identifiable {
    case classic, night, minimal, aurora, custom

    /// Les looks sombres (Moderne et Aurore) partagent la mise en page du Moderne.
    var isDark: Bool { self == .night || self == .aurora || (self == .custom && CustomTheme.isDark) }

    /// « Mon thème » demande Foldly+ ; sans lui, on revient au Moderne.
    static func resolved(_ raw: String) -> DFLook {
        let look = DFLook(rawValue: raw) ?? .classic
        return look == .custom && !UserDefaults.standard.bool(forKey: "plusActive") ? .night : look
    }

    var id: String { rawValue }

    static let key = "look"

    static var current: DFLook { resolved(UserDefaults.standard.string(forKey: key) ?? "") }

    var title: Text {
        switch self {
        case .classic: return Text("Classic")
        case .night: return Text("Modern")
        case .minimal: return Text("Minimal")
        case .aurora: return Text("Aurora")
        case .custom: return Text("My theme")
        }
    }

    var subtitle: Text {
        switch self {
        case .classic: return Text("Cards and a ring, like the Health app")
        case .night: return Text("Big numbers, hinge gauge, Today and Week tabs")
        case .minimal: return Text("Just your numbers, nothing else")
        case .aurora: return Text("Northern lights that move with your hinge")
        case .custom: return Text("Your own colors, with Foldly+")
        }
    }
}

/// Les couleurs suivent le look choisi.
extension Color {
    private static var night: Bool { DFLook.current == .night }
    private static var minimal: Bool { DFLook.current == .minimal }
    private static var aurora: Bool { DFLook.current == .aurora }
    private static var custom: Bool { DFLook.current == .custom }

    static var dfAccent: Color {
        if minimal { return Color.primary }
        if aurora { return Aurora.accent }
        if custom { return CustomTheme.accent }
        return night ? Color(red: 0.36, green: 0.89, blue: 0.78) : Color.accentColor
    }
    static var dfBackground: Color {
        if minimal { return Color(uiColor: .systemBackground) }
        if aurora { return Aurora.night }
        if custom { return CustomTheme.solid }
        return night ? Color(red: 0.055, green: 0.078, blue: 0.078) : Color(uiColor: .systemGroupedBackground)
    }
    static var dfCard: Color {
        if minimal { return Color(uiColor: .secondarySystemBackground) }
        if aurora { return Color.white.opacity(0.075) }
        if custom { return CustomTheme.card }
        return night ? Color(red: 0.135, green: 0.16, blue: 0.157) : Color(uiColor: .secondarySystemGroupedBackground)
    }
    static var dfFill: Color {
        if minimal { return Color.primary.opacity(0.08) }
        if aurora { return Color.white.opacity(0.09) }
        if custom { return CustomTheme.card }
        return night ? Color.white.opacity(0.08) : Color(uiColor: .tertiarySystemFill)
    }
    static var dfOutline: Color {
        if minimal { return Color.primary.opacity(0.14) }
        if aurora { return Color.white.opacity(0.16) }
        if custom { return Color.primary.opacity(0.16) }
        return night ? Color.white.opacity(0.17) : Color(uiColor: .separator)
    }
    static var dfBar: Color {
        if minimal { return Color.primary.opacity(0.22) }
        if aurora { return Aurora.violet.opacity(0.55) }
        if custom { return CustomTheme.accent.opacity(0.45) }
        return night ? Color(red: 0.08, green: 0.36, blue: 0.32) : Color.accentColor.opacity(0.55)
    }
    static var dfWarning: Color { night || aurora || custom ? Color(red: 1.0, green: 0.71, blue: 0.36) : Color.orange }
    static var dfOver: Color { night || aurora || custom ? Color(red: 1.0, green: 0.45, blue: 0.42) : Color.red }
    /// Le texte posé sur la couleur d'accent (boutons pleins).
    static var dfOnAccent: Color {
        if minimal { return Color(uiColor: .systemBackground) }
        if aurora { return Aurora.night }
        if custom { return CustomTheme.accent.luminance > 0.6 ? Color.black : Color.white }
        return night ? Color.black : Color.white
    }
}

/// L'écran principal, dans le look choisi.
struct ContentView: View {
    @Environment(ClapetModel.self) private var model
    @AppStorage(DFLook.key) private var lookRaw = ""
    @State private var askLook = false
    @Environment(ClapetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var showSurvey = false
    @State private var showTour = false
    /// Écran extérieur : « Voir le détail » montre l'accueil complet (jusqu'au prochain pli).
    @State private var outerDetails = false
    @AppStorage(GlanceRule.key) private var glanceOn = true
    @State private var tourPending: TourTarget?
    @State private var tourTarget: TourTarget?
    @AppStorage(DeskRule.key) private var deskOn = true
    /// L'animation d'ouverture, au lancement de l'app seulement.
    @State private var opening = OpeningRule.shouldShow(lookChosen: !(UserDefaults.standard.string(forKey: DFLook.key) ?? "").isEmpty)

    var body: some View {
        let look = DFLook.resolved(lookRaw)
        GeometryReader { g in
            let desk = DeskRule.active(degrees: model.degrees, size: g.size) && deskOn
            let outer = max(g.size.width, g.size.height) < 800 && glanceOn && Demo.screen == nil && !Demo.seeded
            ZStack {
                Group {
                    switch look {
                    case .classic: ClassicHomeView()
                    case .night, .aurora, .custom: NightHomeView()
                    case .minimal: MinimalHomeView()
                    }
                }
                // Petit écran extérieur : l'essentiel par-dessus (la vue d'accueil reste dessous).
                if outer && !outerDetails && !desk {
                    OuterGlance(look: look) { withAnimation { outerDetails = true } }
                        .transition(.opacity)
                }
                // Mode bureau : la vue d'accueil reste dessous (elle lit la charnière et ouvre les feuilles).
                if desk {
                    DeskModeView(look: look)
                        .transition(.opacity)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.3), value: desk)
            .onChange(of: max(g.size.width, g.size.height) >= 800) { _, _ in
                outerDetails = false
                FoldlyAppDelegate.refreshOrientations()
            }
        }
        .overlay {
            if opening {
                OpeningView(today: model.stats.today, look: look, haptics: model.hapticsOn) {
                    opening = false
                }
            }
        }
        .preferredColorScheme(look.isDark ? .dark : (look == .custom ? .light : nil))
        .onAppear {
            // Première ouverture : on propose de choisir (pas pendant le tournage des vidéos).
            if lookRaw.isEmpty && !Demo.seeded && Demo.screen == nil { askLook = true }
        }
        // Bêta : « Ton avis en 1 minute », une fois par jour au plus, tant que le testeur n'a pas répondu.
        .fullScreenCover(isPresented: $showSurvey) {
            SurveyScreen {
                showSurvey = false
                openURL(SurveyRule.url)
            } onLater: {
                showSurvey = false
            }
        }
        .fullScreenCover(isPresented: $showTour, onDismiss: {
            if let t = tourPending { tourPending = nil; tourTarget = t } else { checkSurvey() }
        }) { FeatureTour { tourPending = $0 } }
        .sheet(item: $tourTarget) { target in
            switch target {
            case .autoCount: AutoCountView().environment(model)
            case .settings: SettingsView().environment(model).environment(store)
            case .leaderboards: LeaderboardView().environment(model).environment(store)
            }
        }
        .sheet(isPresented: $askLook, onDismiss: {
            if lookRaw.isEmpty { lookRaw = DFLook.classic.rawValue }
            if !TourRule.seen { showTour = true } else { checkSurvey() }
        }) {
            LookPickerView()
                .presentationDetents([.medium, .large])
        }
        .task {
            // Après l'animation d'ouverture.
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            // Après une mise à jour : la visite guidée, une fois (pas pendant le choix du thème ni le tournage).
            if !askLook && !lookRaw.isEmpty && !TourRule.seen && !Demo.seeded && Demo.screen == nil { showTour = true }
            checkSurvey()
            // La note sur l'App Store : un peu plus tard, si rien d'autre n'est ouvert.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !askLook && !showSurvey && !showTour && ReviewRule.shouldAsk(model.stats, isTestBuild: store.isTestBuild) {
                ReviewRule.markAsked()
                requestReview()
            }
            WeekRecapNotice.schedule(model.stats)
            MonthRecapNotice.schedule()
            WatchSync.shared.start(model.stats)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            InstalledWidgets.shared.refresh()
            checkSurvey()
        }
    }

    private func checkSurvey() {
        guard !askLook, !showSurvey, !opening, !showTour else { return }
        if SurveyRule.shouldPresent(isTestBuild: store.isTestBuild) {
            SurveyRule.markPresented()
            showSurvey = true
        }
    }

    static func duration(_ t: TimeInterval) -> String { NightHomeView.duration(t) }
    static func hourLabel(_ h: Int) -> String { NightHomeView.hourLabel(h) }
}

/// Le choix du look, au premier lancement.
struct LookPickerView: View {
    @AppStorage(DFLook.key) private var lookRaw = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose your theme")
                        .font(.title2.weight(.bold))
                    Text("You can change it anytime in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LookChoice(lookRaw: $lookRaw)
                Button {
                    if lookRaw.isEmpty { lookRaw = DFLook.classic.rawValue }
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.2, green: 0.72, blue: 0.63))
            }
            .padding(24)
        }
    }
}

/// Les looks côte à côte, avec un aperçu (deux colonnes sur l'écran extérieur).
struct LookChoice: View {
    @Binding var lookRaw: String

    var body: some View {
        let current = DFLook(rawValue: lookRaw) ?? .classic
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
            ForEach(DFLook.allCases.filter { $0 != .custom }) { look in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { lookRaw = look.rawValue }
                } label: {
                    VStack(spacing: 8) {
                        LookThumbnail(look: look)
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                        look.title
                            .font(.headline)
                            .foregroundStyle(.primary)
                        look.subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(red: 0.2, green: 0.72, blue: 0.63), lineWidth: current == look ? 3 : 0)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(current == look ? .isSelected : [])
            }
        }
    }
}

/// Un petit dessin de chaque look (couleurs fixes, pour qu'on voie la différence).
struct LookThumbnail: View {
    let look: DFLook

    var body: some View {
        if look == .minimal {
            minimalThumb
        } else if look == .aurora {
            auroraThumb
        } else {
            cardsThumb
        }
    }

    /// Aurore : un ciel de nuit, des aurores boréales et un grand chiffre lumineux.
    private var auroraThumb: some View {
        ZStack {
            AuroraBackdrop(animated: false)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 6) {
                Text(verbatim: "12")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(Aurora.glow)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == 6 ? AnyShapeStyle(Aurora.glow) : AnyShapeStyle(Color.white.opacity(0.22)))
                            .frame(width: 6, height: CGFloat([18, 12, 10, 20, 11, 16, 7][i]))
                    }
                }
                .frame(height: 22, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    /// Épuré : un grand chiffre fin, un trait, sept traits pour la semaine.
    private var minimalThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: .systemBackground))
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            VStack(spacing: 7) {
                Text(verbatim: "12")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Color.primary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.primary).frame(width: 30)
                }
                .frame(width: 52, height: 2)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule()
                            .fill(Color.primary.opacity(i == 6 ? 1 : 0.3))
                            .frame(width: 2, height: CGFloat([14, 9, 8, 16, 9, 12, 6][i]))
                    }
                }
                .frame(height: 16, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var cardsThumb: some View {
        let night = look == .night
        let background = night ? Color(red: 0.055, green: 0.078, blue: 0.078) : Color(uiColor: .systemGroupedBackground)
        let card = night ? Color(red: 0.135, green: 0.16, blue: 0.157) : Color(uiColor: .secondarySystemGroupedBackground)
        let accent = night ? Color(red: 0.36, green: 0.89, blue: 0.78) : Color(red: 0.2, green: 0.72, blue: 0.63)
        let ink = night ? Color.white : Color.primary
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background)
            VStack(alignment: .leading, spacing: 6) {
                if night {
                    HStack(spacing: 4) {
                        Capsule().fill(accent).frame(width: 26, height: 9)
                        Capsule().fill(card).frame(width: 26, height: 9)
                    }
                    HStack(alignment: .center) {
                        Text(verbatim: "12")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(ink)
                        Spacer(minLength: 0)
                        arc(accent, width: 30)
                    }
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == 6 ? accent : Color(red: 0.08, green: 0.36, blue: 0.32))
                                .frame(height: CGFloat([18, 12, 10, 20, 11, 16, 7][i]))
                        }
                    }
                    .frame(height: 22, alignment: .bottom)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(card)
                        .frame(height: 46)
                        .overlay(
                            HStack(spacing: 6) {
                                Circle().stroke(accent, lineWidth: 4).frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Capsule().fill(accent).frame(width: 26, height: 4)
                                    Capsule().fill(Color.gray.opacity(0.4)).frame(width: 18, height: 4)
                                }
                                Spacer(minLength: 0)
                                arc(accent, width: 24)
                            }
                            .padding(.horizontal, 8)
                        )
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(card)
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(card)
                    }
                    .frame(height: 20)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(card)
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(card)
                    }
                    .frame(height: 20)
                }
            }
            .padding(10)
        }
        .accessibilityHidden(true)
    }

    private func arc(_ color: Color, width: CGFloat) -> some View {
        Circle()
            .trim(from: 0.5, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: width, height: width)
            .frame(height: width / 2 + 2, alignment: .top)
    }
}

/// L'essentiel sur l'écran extérieur (réglable dans Réglages > Avancé).
enum GlanceRule {
    static let key = "outerGlance"
}
