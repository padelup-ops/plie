import SwiftUI

enum AppTab: Hashable { case home, clubs, bot, matches, profile }

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var openClub: Club? = nil
}

struct RootView: View {
    @StateObject private var router = Router()
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"

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
        .sheet(item: $router.openClub) { club in
            ClubDetailView(club: club).environmentObject(router)
        }
        .onAppear {
            if let shot = ShotMode.current { ShotMode.route(shot, router: router) }
        }
    }
}
