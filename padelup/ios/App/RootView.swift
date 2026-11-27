import SwiftUI

enum AppTab: Hashable { case home, clubs, bot, matches, profile }

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var openClub: Club? = nil
    @Published var newRuleFor: Club? = nil
}

struct RootView: View {
    @StateObject private var router = Router()
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                Tab("Accueil", systemImage: "sparkles", value: AppTab.home) { HomeView() }
                Tab("Clubs", systemImage: "map.fill", value: AppTab.clubs) { ClubsView() }
                Tab("Bot", systemImage: "bolt.horizontal.circle.fill", value: AppTab.bot) { BotView() }
                Tab("Matchs", systemImage: "figure.tennis", value: AppTab.matches) { MatchesView() }
                Tab("Profil", systemImage: "person.crop.circle", value: AppTab.profile) { ProfileView() }
            }
            if let season = SeasonSetting.resolve(seasonMode) {
                SeasonalOverlay(season: season)
            }
        }
        .environmentObject(router)
        .sheet(item: $router.openClub) { club in
            ClubDetailView(club: club).environmentObject(router)
        }
        .onAppear {
            if let shot = ShotMode.current { ShotMode.route(shot, router: router) }
        }
    }
}

/// Fond commun des écrans : terrain néon discret.
struct ScreenBackground: View {
    var intensity: Double = 0.55
    var body: some View { CourtBackdrop(intensity: intensity) }
}

/// En-tête d'écran : grand titre élargi + sous-titre.
struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Neo.title(30)).foregroundStyle(Neo.text)
            if let subtitle { Text(subtitle).font(Neo.body(15)).foregroundStyle(Neo.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
