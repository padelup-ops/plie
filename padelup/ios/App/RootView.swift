import SwiftUI

enum AppTab: Hashable { case home, clubs, bot, matches, profile }

enum RootSheet: Identifiable {
    case club(Club), match(APIMatch), level, friends, notifications, web(URL), player(Int), community, bookings, editProfile

    var id: String {
        switch self {
        case .club(let c): return "club:" + c.id
        case .match(let m): return "match:\(m.id)"
        case .level: return "level"
        case .friends: return "friends"
        case .notifications: return "notifications"
        case .web(let u): return "web:" + u.absoluteString
        case .player(let id): return "player:\(id)"
        case .community: return "community"
        case .bookings: return "bookings"
        case .editProfile: return "editProfile"
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
    @EnvironmentObject private var bot: BotEngine
    @AppStorage("levelAsked") private var levelAsked = false

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Accueil", systemImage: "circle.grid.2x2", value: AppTab.home) { HomeView() }
            Tab("Clubs", systemImage: "map", value: AppTab.clubs) { ClubsView() }
            Tab("Bot", systemImage: "scope", value: AppTab.bot) { BotView() }
            Tab("Matchs", systemImage: "figure.tennis", value: AppTab.matches) { MatchesView() }
            Tab("Profil", systemImage: "person", value: AppTab.profile) { ProfileView() }
        }
        .tint(UI.court)
        .environmentObject(router)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .club(let club): ClubDetailView(club: club).environmentObject(router)
            case .match(let match): MatchDetailView(match: match)
            case .level: LevelPickerView()
            case .friends: FriendsView()
            case .notifications: NotificationsView()
            case .web(let url): ProviderWebSheet(provider: WebAccount.owns(url), url: url)
            case .player(let id): PlayerProfileView(userID: id)
            case .community: CommunityView()
            case .bookings: BookingsView()
            case .editProfile: EditProfileView()
            }
        }
        // Le bot (ou une notification touchée) demande d'ouvrir une page de réservation, déjà connectée.
        .onChange(of: bot.openURL) { _, url in
            guard let url else { return }
            bot.openURL = nil
            router.sheet = .web(url)
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
