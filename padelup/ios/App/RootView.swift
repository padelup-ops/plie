import SwiftUI

enum AppTab: Hashable { case home, clubs, bot, matches, profile }

enum RootSheet: Identifiable {
    case club(Club), match(APIMatch), level, friends, notifications

    var id: String {
        switch self {
        case .club(let c): return "club:" + c.id
        case .match(let m): return "match:\(m.id)"
        case .level: return "level"
        case .friends: return "friends"
        case .notifications: return "notifications"
        }
    }
}

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var sheet: RootSheet? = nil

    var openClub: Club? {
        get { if case .club(let c) = sheet { return c }; return nil }
        set { sheet = newValue.map { .club($0) } }
    }
    var openMatch: APIMatch? {
        get { if case .match(let m) = sheet { return m }; return nil }
        set { sheet = newValue.map { .match($0) } }
    }
    var showLevel: Bool {
        get { if case .level = sheet { return true }; return false }
        set { sheet = newValue ? .level : nil }
    }
    var showFriends: Bool {
        get { if case .friends = sheet { return true }; return false }
        set { sheet = newValue ? .friends : nil }
    }
    var showNotifications: Bool {
        get { if case .notifications = sheet { return true }; return false }
        set { sheet = newValue ? .notifications : nil }
    }
}

struct RootView: View {
    @StateObject private var router = Router()
    @EnvironmentObject private var server: ServerAPI
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"
    @AppStorage("levelAsked") private var levelAsked = false

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                Tab("Accueil", systemImage: "house", value: AppTab.home) { HomeView() }
                Tab("Clubs", systemImage: "map", value: AppTab.clubs) { ClubsView() }
                Tab("Bot", systemImage: "bolt", value: AppTab.bot) { BotView() }
                Tab("Matchs", systemImage: "figure.tennis", value: AppTab.matches) { MatchesView() }
                Tab("Profil", systemImage: "person", value: AppTab.profile) { ProfileView() }
            }
            if let season = SeasonSetting.resolve(seasonMode) {
                SeasonalOverlay(season: season)
            }
        }
        .environmentObject(router)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .club(let club): ClubDetailView(club: club).environmentObject(router)
            case .match(let match): MatchDetailView(match: match)
            case .level: LevelPickerView()
            case .friends: FriendsView()
            case .notifications: NotificationsView()
            }
        }
        // Après l'inscription : choisir son niveau (une seule fois, modifiable ensuite dans Profil).
        .onChange(of: server.me?.profile?.isCompleted) { _, completed in
            if completed == false && !levelAsked {
                levelAsked = true
                router.showLevel = true
            }
        }
        .onAppear {
            if let shot = ShotMode.current { ShotMode.route(shot, router: router) }
        }
    }
}
