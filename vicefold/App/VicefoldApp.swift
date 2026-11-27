// VicefoldApp.swift — Vicefold
//
// Le compagnon non officiel de GTA VI. Sur l'iPhone Duo ouvert, chaque écran a deux moitiés : la liste d'un côté du pli,
// le détail (ou la carte) de l'autre. Sur iPad pareil, sur iPhone une seule page à la fois.
// Au démarrage : l'animation d'ouverture (Launch.swift), puis, la première fois, la présentation (Onboarding.swift).

import SwiftUI

@main
struct VicefoldApp: App {
    @State private var content = ContentStore.shared
    @State private var progress = Progress.shared
    @State private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Alerts.shared.register()
        VFStyle.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(content)
                .environment(progress)
                .environment(store)
                .tint(VF.flamingo)
                .task {
                    // Déjà venu dans la communauté : Game Center se reconnecte en silence.
                    if GameCenterHub.shared.used { GameCenterHub.shared.authenticate() }
                    progress.writeSnapshot()
                    if ShotMode.route == nil { _ = await content.refresh() }
                    await Alerts.shared.check()
                }
                .onChange(of: phase) { _, p in
                    if p == .active { progress.pullCloud(); Task { await store.refresh() } }
                }
        }
    }
}

enum AppTab: Hashable { case home, guides, map, tracker, more, search }

struct RootView: View {
    @State private var tab: AppTab = ShotMode.initialTab
    @AppStorage("vicefold.onboarded") private var onboarded = false
    @State private var launching = LaunchView.wanted
    @State private var router = AppRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// La présentation : à la première ouverture, ou rouverte depuis les réglages. Elle ne bloque jamais quelqu'un
    /// qui l'a déjà vue.
    private var introShown: Bool {
        ShotMode.onboardingPage != nil || router.showIntro || (!onboarded && ShotMode.route == nil)
    }

    var body: some View {
        ZStack {
            tabs
                .accessibilityHidden(introShown || launching)
            if introShown {
                OnboardingFlow {
                    onboarded = true
                    router.showIntro = false
                }
                .transition(.opacity)
                .zIndex(1)
            }
            if launching {
                LaunchView { launching = false }
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: introShown)
        // L'app est toujours sombre : le néon et la carte holographique sont pensés pour la nuit.
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "sun.horizon", value: AppTab.home) { HomeView(tab: $tab) }
            Tab("Guides", systemImage: "book.pages", value: AppTab.guides) { GuidesView() }
            Tab("Map", systemImage: "map", value: AppTab.map) { MapTab() }
            Tab("Tracker", systemImage: "checklist", value: AppTab.tracker) { TrackerView() }
            Tab("More", systemImage: "square.grid.2x2", value: AppTab.more) { MoreView() }
            // Cinq onglets au plus sur iPhone : au-delà, iOS range les autres dans un onglet « Autre » qui empile
            // deux barres de navigation. Sur iPhone, la recherche s'ouvre depuis l'accueil.
            if sizeClass != .compact {
                Tab(value: AppTab.search, role: .search) {
                    DualLayout { SearchView() } secondary: {
                        EmptyDetail(icon: "magnifyingglass", text: "Search", message: "Search guides, missions, places, vehicles, easter eggs, characters and cheat codes.")
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: sizeClass, initial: true) { _, c in if c == .compact && tab == .search { tab = .home } }
        .tint(VF.flamingo)
        .onChange(of: router.mapPlace) { _, p in if p != nil { tab = .map } }
        .onOpenURL { url in
            switch url.host() {
            case "tracker": tab = .tracker
            case "map": tab = .map
            case "guides": tab = .guides
            default: tab = .home
            }
        }
        .fullScreenCover(isPresented: .constant(ShotMode.route == "widgets")) { NavigationStack { WidgetGallery() }.preferredColorScheme(.dark) }
    }
}

// MARK: - Deux moitiés (Duo, iPad)

private struct WideKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// La page est en deux moitiés : la liste ne pousse pas le détail, elle le montre à côté.
    var vfWide: Bool {
        get { self[WideKey.self] }
        set { self[WideKey.self] = newValue }
    }
}

/// La liste d'un côté, le détail de l'autre. Sur le Duo ouvert, la séparation tombe exactement sur le pli : rien
/// n'est jamais coupé en deux. Le pli garde la couleur du fond (pas de bande noire au milieu de l'écran).
struct DualLayout<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        GeometryReader { geo in
            let fold = Self.fold(geo)
            if let fold, fold.height >= geo.size.height * 0.9 {
                HStack(spacing: 0) {
                    primary.environment(\.vfWide, true).frame(width: fold.minX)
                    VFBackdrop().frame(width: fold.width)
                    secondary.environment(\.vfWide, true).frame(maxWidth: .infinity)
                }
            } else if geo.size.width >= 740 {
                HStack(spacing: 0) {
                    primary.environment(\.vfWide, true).frame(width: min(440, geo.size.width * 0.42))
                    Rectangle().fill(VF.hairline).frame(width: 1).ignoresSafeArea()
                    secondary.environment(\.vfWide, true).frame(maxWidth: .infinity)
                }
            } else {
                primary.environment(\.vfWide, false)
            }
        }
    }

    static func fold(_ geo: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            guard let f = geo.reservedRegions(kind: .division, options: .includeInactive).first?.frame else { return nil }
            let s = geo.size
            guard s.width > 0, f.height >= s.height * 0.9, f.width < s.width * 0.2,
                  f.midX > s.width * 0.25, f.midX < s.width * 0.75 else { return nil }
            return CGRect(x: f.minX, y: 0, width: max(0, f.width), height: s.height)
        }
        return nil
    }
}

/// Le côté « détail » quand rien n'est choisi.
struct EmptyDetail: View {
    var icon: String
    var text: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VFEmptyState(icon: icon, title: text, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VFBackdrop())
    }
}

// MARK: - Captures (simulateur)

enum ShotMode {
    static let route: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()

    static var initialTab: AppTab {
        switch route {
        case "guides", "guide": return .guides
        case "map", "mappins", "mycard", "place", "layers", "cars", "car": return .map
        case "tracker", "missions", "mission", "share", "collectibles", "challenges": return .tracker
        case "more", "characters", "radio", "profile", "pro", "cheats", "eggs", "community", "friends", "thread", "settings", "vehicles": return .more
        case "search": return .search
        default: return .home
        }
    }

    /// « launch » : l'animation d'ouverture figée sur le nom allumé ; « launchsun » : pendant le lever du soleil ;
    /// « launchfold » : pendant l'ouverture en deux.
    static var launchFrame: Double? {
        switch route {
        case "launch": return 1.70
        case "launchsun": return 0.62
        case "launchfold": return 2.25
        default: return nil
        }
    }

    /// « onb1 » … « onb5 » : une page de la présentation.
    static var onboardingPage: Int? {
        guard let r = route, r.hasPrefix("onb"), let n = Int(r.dropFirst(3)), n >= 1 else { return nil }
        return n - 1
    }
}
