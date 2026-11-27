import CoreLocation
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
        ZStack {
            ScreenBackground(intensity: 0.9)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if let season = SeasonSetting.resolve(seasonMode) { SeasonBadge(season: season) }
                    stats
                    actions
                    botCard
                    nearbySection
                    Text("Clubs : © contributeurs OpenStreetMap (ODbL) et Playtomic · Météo : Open-Meteo")
                        .font(Neo.body(11)).foregroundStyle(Neo.faint)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BallMark(size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PADELUP").font(Neo.title(26)).foregroundStyle(Neo.text)
                    Text("NEO").font(Neo.label(13)).foregroundStyle(Neo.volt).tracking(6)
                }
                Spacer()
                if let me = server.me {
                    Text(String((me.profile?.fullName ?? me.username).prefix(1)).uppercased())
                        .font(Neo.title(18)).foregroundStyle(Neo.night)
                        .frame(width: 40, height: 40).background(Circle().fill(Neo.neonGradient))
                }
            }
            Text(greeting).font(Neo.title(32)).foregroundStyle(Neo.text).fixedSize(horizontal: false, vertical: true)
            Text("Les clubs de France, des pays voisins et du Maghreb, la météo du court, et un bot qui réserve à ta place.")
                .font(Neo.body(15)).foregroundStyle(Neo.dim)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let name = server.me?.profile?.fullName?.split(separator: " ").first.map(String.init) ?? server.me?.firstName
        let hello = h < 5 ? "Bonne nuit" : (h < 18 ? "Salut" : "Bonsoir")
        if let name, !name.isEmpty { return "\(hello) \(name),\nprêt pour un match ?" }
        return "\(hello),\nprêt pour un match ?"
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatTile(value: directory.totalCount > 0 ? directory.totalCount.formatted(.number.locale(Locale(identifier: "fr_FR"))) : "…",
                     label: "clubs couverts", color: Neo.cyan)
            StatTile(value: "\(bot.rules.filter { $0.active }.count)", label: "bots en veille", color: Neo.volt)
            StatTile(value: "\(bot.log.filter { $0.kind == .booked }.count)", label: "réservés par le bot", color: Neo.magenta)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { router.tab = .clubs } label: {
                Label("Trouver un club", systemImage: "globe.europe.africa.fill")
            }.buttonStyle(NeonButtonStyle(color: Neo.volt))
            HStack(spacing: 12) {
                Button { router.tab = .bot } label: { Label("Bot de résa", systemImage: "bolt.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
                Button { router.tab = .matches } label: { Label("Matchs", systemImage: "person.2.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
            }
        }
    }

    @ViewBuilder private var botCard: some View {
        if let last = bot.log.first {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Dernière action du bot", trailing: last.date.formatted(.relative(presentation: .named)))
                HStack(spacing: 12) {
                    Image(systemName: last.kind == .booked ? "checkmark.seal.fill" : (last.kind == .found ? "eye.fill" : "exclamationmark.triangle.fill"))
                        .font(.system(size: 26)).foregroundStyle(last.kind == .booked ? Neo.volt : Neo.cyan).neonGlow(Neo.volt, radius: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(last.clubName).font(Neo.label(14)).foregroundStyle(Neo.text)
                        Text(last.message).font(Neo.body(13)).foregroundStyle(Neo.dim).lineLimit(2)
                    }
                }
            }
            .glassCard(glow: Neo.volt)
        }
    }

    @ViewBuilder private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Autour de toi", trailing: location.location == nil ? nil : "\(nearby.count) clubs")
            if location.location == nil {
                Button { location.request() } label: { Label("Activer la localisation", systemImage: "location.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
            } else if nearby.isEmpty {
                EmptyStateView(systemImage: "mappin.slash", title: "Aucun club repéré tout près",
                               message: "Ouvre la carte pour explorer les clubs de la région ou d'un autre pays.")
            } else {
                ForEach(nearby) { club in
                    Button { router.openClub = club } label: { ClubRow(club: club, distance: club.distance(from: location.location)) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ClubRow: View {
    var club: Club
    var distance: Double?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neo.court.opacity(0.35))
                Image(systemName: club.isMostlyIndoor ? "building.2.fill" : "sportscourt.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Neo.cyan)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(club.displayName).font(Neo.label(14)).foregroundStyle(Neo.text).lineLimit(1)
                Text([club.city, club.courts > 0 ? club.courtsLabel : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Neo.body(13)).foregroundStyle(Neo.dim).lineLimit(1)
                if club.canBookWithBot {
                    Text("Réservable par le bot").font(Neo.label(10)).foregroundStyle(Neo.volt)
                }
            }
            Spacer()
            Text(formatDistance(distance)).font(Neo.mono(13)).foregroundStyle(Neo.cyan)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Neo.faint)
        }
        .glassCard(radius: 18, padding: 12)
    }
}
