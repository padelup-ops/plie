import CoreLocation
import MapKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var favorites: Favorites
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"
    @State private var posts: [APIPost] = []
    @State private var weather: [WeatherHour] = []
    @State private var weatherPlace = ""

    private var nearby: [Club] {
        guard let loc = location.location else { return [] }
        _ = directory.revision
        return directory.nearest(to: loc, limit: 5, maxKm: 60)
    }

    /// Prochaine partie réservée (par le bot ou depuis une fiche club).
    private var nextBooking: BotLogEntry? {
        bot.log.filter { $0.kind == .booked && ($0.slotStart ?? .distantPast) > Date() }
            .min { ($0.slotStart ?? .distantFuture) < ($1.slotStart ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                nextUp
                searchEntry
                if !weather.isEmpty { weatherBlock }
                if !favorites.clubs.isEmpty { favoritesBlock }
                nearbyBlock
                if !bot.rules.isEmpty { botsBlock }
                if server.isLoggedIn || ShotMode.current != nil { communityBlock }
                Text("Clubs © contributeurs OpenStreetMap · Météo Open-Meteo · PadelUp n'est affilié ni à Playtomic ni à Anybuddy.")
                    .font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, UI.margin)
            .padding(.top, 10)
            .padding(.bottom, 56)
        }
        .background(PageBackground())
        .task(id: location.location.map { "\(Int($0.coordinate.latitude * 50)):\(Int($0.coordinate.longitude * 50))" }) {
            if ShotMode.current != nil {
                weather = ShotMode.demoWeather()
                weatherPlace = "Paris"
                posts = ShotMode.demoPosts()
                return
            }
            if server.isLoggedIn { posts = (try? await server.posts(category: nil)) ?? posts }
            guard let loc = location.location else { return }
            // Les clubs autour du joueur sont actualisés tout de suite, sans passer par la carte.
            async let w = WeatherAPI.forecast(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            let region = MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.7))
            await directory.refreshLive(region: region)
            weather = (try? await w) ?? weather
            if let place = try? await CLGeocoder().reverseGeocodeLocation(loc).first?.locality { weatherPlace = place }
        }
        .onAppear { if location.location == nil && location.status != .notDetermined { location.request() } }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: FR.longDay(Date()) + (SeasonSetting.resolve(seasonMode).map { " · " + $0.name } ?? ""))
                Text(greeting).font(UI.display()).foregroundStyle(UI.ink).lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if server.isLoggedIn || ShotMode.current != nil {
                RoundIconButton(systemImage: "bell") { router.showNotifications = true }
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = server.me?.profile?.fullName?.split(separator: " ").first.map(String.init) ?? server.me?.firstName
            ?? (ShotMode.current != nil ? "Camille" : nil)
        let hello = h < 5 || h >= 18 ? "Bonsoir" : "Bonjour"
        if let name, !name.isEmpty { return "\(hello)\u{00A0}\(name)." }
        return hello + "."
    }

    // MARK: Prochaine partie (le billet)

    @ViewBuilder private var nextUp: some View {
        if let next = nextBooking, let start = next.slotStart {
            Button { router.tab = .bot } label: {
                Ticket {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: "Prochaine partie")
                            Spacer()
                            Stamp(text: "Réservé")
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            Text(FR.time(start)).font(UI.scoreHeavy(68)).foregroundStyle(UI.ink)
                            Text(FR.longDay(start)).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.clubName).font(UI.headline()).foregroundStyle(UI.ink)
                            Text([next.court, next.price].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(UI.callout()).foregroundStyle(UI.muted)
                        }
                    }
                } stub: {
                    HStack {
                        Text("Réservé \(FR.relative(next.date))").font(UI.caption()).foregroundStyle(UI.muted)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(UI.ink)
                    }
                }
            }
            .buttonStyle(.plain)
        } else if let release = bot.nextRelease {
            Button { router.tab = .bot } label: {
                Ticket {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: "Prochaine ouverture")
                            Spacer()
                            Stamp(text: release.rule.releaseLabel ?? "", style: .outline)
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            Text(FR.time(release.release, tz: release.rule.tz)).font(UI.scoreHeavy(68)).foregroundStyle(UI.ink)
                            Text(FR.relative(release.release)).font(UI.headline()).foregroundStyle(UI.ink)
                        }
                        Text(release.rule.clubName).font(UI.headline()).foregroundStyle(UI.ink)
                    }
                } stub: {
                    Text("Créneaux du \(FR.longDay(release.day, tz: release.rule.tz)) · le bot te prévient une minute avant.")
                        .font(UI.caption()).foregroundStyle(UI.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var searchEntry: some View {
        Button { router.tab = .clubs } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(UI.ink)
                Text("Un club, une ville…").font(UI.body()).foregroundStyle(UI.muted)
                Spacer()
                Text(directory.totalCount > 0 ? "\(directory.totalCount.formatted(.number.locale(UI.fr))) clubs" : "")
                    .font(UI.caption()).monospacedDigit().foregroundStyle(UI.faint)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Météo de jeu

    private var weatherBlock: some View {
        Block(title: "Météo de jeu", meta: weatherPlace) {
            PlayWeatherChart(hours: Array(weather.prefix(12)))
        }
    }

    // MARK: Près de toi

    @ViewBuilder private var nearbyBlock: some View {
        Block(title: "Près de toi", meta: location.location == nil ? nil : (directory.liveStatus.isEmpty ? (nearby.isEmpty ? nil : "\(nearby.count) clubs") : directory.liveStatus),
              actionTitle: nearby.isEmpty ? nil : "Carte", action: { router.tab = .clubs }) {
            if location.location == nil {
                EmptyNote(title: "Où joues-tu ?", message: "Active la localisation pour voir les clubs autour de toi, ou cherche une ville.",
                          actionTitle: "Activer la localisation") { location.request() }
            } else if nearby.isEmpty {
                EmptyNote(title: "Recherche des clubs proches…", message: "Ouvre la carte pour explorer ta région.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(nearby.enumerated()), id: \.element.id) { i, club in
                        Button { router.openClub = club } label: {
                            ClubRow(club: club, distance: club.distance(from: location.location), index: i + 1)
                        }
                        .buttonStyle(.plain)
                        if i < nearby.count - 1 { Hairline(inset: 38) }
                    }
                }
            }
        }
    }

    // MARK: Mes clubs

    private var favoritesBlock: some View {
        Block(title: "Mes clubs", meta: "\(favorites.clubs.count)") {
            VStack(spacing: 0) {
                ForEach(Array(favorites.clubs.prefix(4).enumerated()), id: \.element.id) { i, club in
                    Button { router.openClub = directory.club(id: club.id) ?? club } label: {
                        ClubRow(club: directory.club(id: club.id) ?? club, distance: club.distance(from: location.location))
                    }
                    .buttonStyle(.plain)
                    if i < min(favorites.clubs.count, 4) - 1 { Hairline() }
                }
            }
        }
    }

    // MARK: Communauté

    private var communityBlock: some View {
        Block(title: "Communauté", actionTitle: "Tout voir", action: { router.sheet = .community }) {
            if posts.isEmpty {
                EmptyNote(title: "Cherche un 4e, partage un conseil.", message: "Les joueurs PadelUp échangent ici.",
                          actionTitle: "Ouvrir la communauté") { router.sheet = .community }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(posts.prefix(2).enumerated()), id: \.element.id) { i, p in
                        Button { router.sheet = .community } label: { PostRow(post: p, compact: true) }.buttonStyle(.plain)
                        if i < min(posts.count, 2) - 1 { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Tes bots

    private var botsBlock: some View {
        let active = bot.rules.filter { $0.active }
        return Block(title: "Tes bots", meta: active.isEmpty ? "en pause" : "\(active.count) en veille", live: !active.isEmpty,
                     actionTitle: "Gérer", action: { router.tab = .bot }) {
            VStack(spacing: 0) {
                ForEach(Array(bot.rules.prefix(3).enumerated()), id: \.element.id) { i, rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.clubName).font(UI.headline()).foregroundStyle(rule.active ? UI.ink : UI.muted).lineLimit(1)
                        Text(rule.summary.uppercased(with: UI.fr)).font(UI.score(14)).tracking(0.3).foregroundStyle(UI.muted)
                        Text(rule.lastStatus).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    if i < min(bot.rules.count, 3) - 1 { Hairline() }
                }
            }
        }
    }
}

/// Ligne de club : numéro (liste éditoriale), nom, point balle si réservable en ligne, distance en chiffres.
struct ClubRow: View {
    var club: Club
    var distance: Double?
    var index: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let index {
                Text(String(format: "%02d", index)).font(UI.score(15)).foregroundStyle(UI.faint).frame(width: 24, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(club.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(UI.ink).lineLimit(1)
                HStack(spacing: 7) {
                    if club.canBookWithBot {
                        Circle().fill(UI.ball).frame(width: 8, height: 8).overlay(Circle().strokeBorder(UI.ink.opacity(0.35), lineWidth: 0.75))
                    }
                    Text(club.subtitle).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let distance {
                Text(formatDistance(distance)).font(UI.score(17)).foregroundStyle(UI.ink)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
