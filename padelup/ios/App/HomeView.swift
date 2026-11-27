import CoreLocation
import MapKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var router: Router
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"

    private var nearby: [Club] {
        guard let loc = location.location else { return [] }
        _ = directory.revision
        return directory.nearest(to: loc, limit: 6, maxKm: 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                hero
                metrics
                if let last = bot.log.first { lastBotAction(last) }
                nearbySection
                Text("Clubs © contributeurs OpenStreetMap (ODbL) et Playtomic · Météo Open-Meteo")
                    .font(UI.small()).foregroundStyle(UI.faint).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(UI.bg.ignoresSafeArea())
        .task(id: location.location.map { "\(Int($0.coordinate.latitude * 50)):\(Int($0.coordinate.longitude * 50))" }) {
            // Les clubs autour du joueur sont actualisés tout de suite, sans passer par la carte.
            guard let loc = location.location, ShotMode.current == nil else { return }
            let region = MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.7))
            await directory.refreshLive(region: region)
        }
        .onAppear { if location.location == nil && location.status != .notDetermined { location.request() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BallMark(size: 26)
            Text("PadelUp").font(.system(size: 20, weight: .bold)).foregroundStyle(UI.ink)
            Spacer()
            if let season = SeasonSetting.resolve(seasonMode) { SeasonBadge(season: season) }
            if server.isLoggedIn {
                Button { router.showNotifications = true } label: {
                    Image(systemName: "bell").font(.system(size: 17, weight: .medium)).foregroundStyle(UI.ink)
                        .frame(width: 38, height: 38).background(Circle().fill(UI.card))
                        .overlay(Circle().strokeBorder(UI.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = server.me?.profile?.fullName?.split(separator: " ").first.map(String.init) ?? server.me?.firstName
        let hello = h < 5 ? "Bonne nuit" : (h < 18 ? "Bonjour" : "Bonsoir")
        if let name, !name.isEmpty { return "\(hello) \(name)" }
        return hello
    }

    // La carte héros : bleu PadelUp, une phrase, une action.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(greeting).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            Text("Prêt pour un match ?").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text("Les clubs de France, des pays voisins et du Maghreb, la météo du court, et un bot qui réserve à ta place.")
                .font(UI.callout()).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { router.tab = .clubs } label: { Label("Trouver un club", systemImage: "magnifyingglass") }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.hero)
                    .padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(.white))
                Button { router.tab = .bot } label: { Label("Bot", systemImage: "bolt.fill") }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 44).background(Capsule().fill(.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(UI.hero))
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            Metric(value: directory.totalCount > 0 ? directory.totalCount.formatted(.number.locale(Locale(identifier: "fr_FR"))) : "…",
                   label: "clubs")
            Metric(value: "\(bot.rules.filter { $0.active }.count)", label: "bots actifs")
            Metric(value: "\(bot.log.filter { $0.kind == .booked }.count)", label: "réservés")
        }
    }

    private func lastBotAction(_ last: BotLogEntry) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: last.kind == .booked ? "checkmark" : (last.kind == .found ? "eye" : "exclamationmark"),
                      color: last.kind == .booked ? UI.success : (last.kind == .found ? UI.accent : UI.warning))
            VStack(alignment: .leading, spacing: 2) {
                Text(last.clubName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                Text(last.message).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(2)
            }
            Spacer()
            Text(last.date.formatted(.relative(presentation: .named))).font(UI.small()).foregroundStyle(UI.faint)
        }
        .card(padding: 14)
        .onTapGesture { router.tab = .bot }
    }

    @ViewBuilder private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Autour de toi",
                          trailing: location.location == nil ? nil : (directory.liveStatus.isEmpty ? "\(nearby.count) clubs" : directory.liveStatus))
            if location.location == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active la localisation pour voir les clubs près de chez toi.").font(UI.callout()).foregroundStyle(UI.muted)
                    Button { location.request() } label: { Label("Activer la localisation", systemImage: "location") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .card()
            } else if nearby.isEmpty {
                EmptyStateView(systemImage: "mappin.slash", title: "Recherche des clubs proches…",
                               message: "Ouvre la carte pour explorer ta région ou une autre ville.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(nearby.enumerated()), id: \.element.id) { i, club in
                        Button { router.openClub = club } label: { ClubRow(club: club, distance: club.distance(from: location.location)) }
                            .buttonStyle(.plain)
                        if i < nearby.count - 1 { Divider().overlay(UI.line).padding(.leading, 62) }
                    }
                }
                .card(padding: 6)
            }
        }
    }
}

struct ClubRow: View {
    var club: Club
    var distance: Double?

    private var subtitle: String {
        var parts: [String] = []
        if !club.city.isEmpty { parts.append(club.city) }
        if club.courts > 0 { parts.append(club.courtsLabel) }
        if club.indoor > 0 { parts.append("couvert") }
        return parts.isEmpty ? club.source.label : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: club.isMostlyIndoor ? "building.2" : "sportscourt", color: club.canBookWithBot ? UI.accent : UI.muted)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(club.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink).lineLimit(1)
                    if club.canBookWithBot { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(UI.accent) }
                }
                Text(subtitle).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(formatDistance(distance)).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(UI.muted)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}
