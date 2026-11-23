// VicefoldApp.swift — Vicefold
//
// Le compagnon non officiel de GTA VI. Sur l'iPhone Duo ouvert, chaque écran a deux moitiés : la liste d'un côté du pli,
// le détail (ou la carte) de l'autre. Sur iPad pareil, sur iPhone une seule page à la fois.

import SwiftUI

@main
struct VicefoldApp: App {
    @State private var content = ContentStore.shared
    @State private var progress = Progress.shared
    @State private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Alerts.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(content)
                .environment(progress)
                .environment(store)
                .tint(VF.coral)
                .task {
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

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "sun.horizon", value: AppTab.home) { HomeView(tab: $tab) }
            Tab("Guides", systemImage: "book.pages", value: AppTab.guides) { GuidesView() }
            Tab("Map", systemImage: "map", value: AppTab.map) { MapTab() }
            Tab("Tracker", systemImage: "checklist", value: AppTab.tracker) { TrackerView() }
            Tab("More", systemImage: "square.grid.2x2", value: AppTab.more) { MoreView() }
            Tab(value: AppTab.search, role: .search) { SearchView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onOpenURL { url in
            switch url.host() {
            case "tracker": tab = .tracker
            case "map": tab = .map
            case "guides": tab = .guides
            default: tab = .home
            }
        }
        .sheet(isPresented: Binding(get: { !onboarded && ShotMode.route == nil }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
                .interactiveDismissDisabled()
        }
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
/// n'est jamais coupé en deux.
struct DualLayout<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        GeometryReader { geo in
            let fold = Self.fold(geo)
            if let fold, fold.height >= geo.size.height * 0.9 {
                HStack(spacing: 0) {
                    primary.environment(\.vfWide, true).frame(width: fold.minX)
                    Color.black.frame(width: fold.width)
                    secondary.environment(\.vfWide, true).frame(maxWidth: .infinity)
                }
            } else if geo.size.width >= 740 {
                HStack(spacing: 0) {
                    primary.environment(\.vfWide, true).frame(width: min(440, geo.size.width * 0.42))
                    Divider()
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
    var body: some View {
        ContentUnavailableView {
            Label(text, systemImage: icon)
        }
        .foregroundStyle(.secondary)
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
        case "map", "mappins", "mycard": return .map
        case "tracker", "missions", "mission", "share": return .tracker
        case "more", "characters", "radio", "profile", "pro", "cheats": return .more
        case "search": return .search
        default: return .home
        }
    }
}
