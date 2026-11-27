import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var router: Router
    @State private var tab = 0
    @State private var open: [APIMatch] = []
    @State private var mine: [APIMatch] = []
    @State private var leaders: [APILeader] = []
    @State private var error: String? = nil
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(intensity: 0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(title: "Matchs", subtitle: "Trouve des joueurs de ton niveau, rejoins une partie, grimpe au classement.")
                        Picker("", selection: $tab) {
                            Text("Ouverts").tag(0); Text("Les miens").tag(1); Text("Classement").tag(2)
                        }.pickerStyle(.segmented)
                        if !server.isLoggedIn && ShotMode.current == nil {
                            EmptyStateView(systemImage: "person.crop.circle.badge.plus", title: "Connecte-toi à PadelUp",
                                           message: "Les matchs et le classement utilisent ton compte PadelUp (onglet Profil).")
                            Button { router.tab = .profile } label: { Text("Se connecter") }.buttonStyle(NeonButtonStyle(color: Neo.volt))
                        } else if let error {
                            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Serveur indisponible", message: error)
                        } else if loading && open.isEmpty && mine.isEmpty && leaders.isEmpty {
                            ProgressView().tint(Neo.volt).frame(maxWidth: .infinity).padding(40)
                        } else if tab == 2 {
                            leaderboard
                        } else {
                            let list = tab == 0 ? open : mine
                            if list.isEmpty {
                                EmptyStateView(systemImage: "sportscourt", title: tab == 0 ? "Aucun match ouvert" : "Aucun match prévu",
                                               message: "Crée un match depuis la fiche d'un club : n'importe quel club du monde.")
                            }
                            ForEach(list) { m in MatchCard(match: m, joined: tab == 1) { await reload() } }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .refreshable { await reload() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: server.isLoggedIn) { await reload() }
    }

    private var leaderboard: some View {
        VStack(spacing: 8) {
            ForEach(Array(leaders.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(Neo.title(18)).foregroundStyle(i < 3 ? Neo.volt : Neo.cyan).frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(Neo.label(14)).foregroundStyle(Neo.text)
                        Text("\(p.matchesPlayed ?? 0) matchs · \(Int((p.winRate ?? 0).rounded())) % de victoires").font(Neo.body(12)).foregroundStyle(Neo.dim)
                    }
                    Spacer()
                    Text("\(p.matchesWon ?? 0)").font(Neo.mono(18)).foregroundStyle(Neo.volt)
                }
                .glassCard(radius: 16, glow: i < 3 ? Neo.volt : Neo.cyan, padding: 12)
            }
        }
    }

    private func reload() async {
        if ShotMode.current != nil {
            open = ShotMode.demoMatches()
            return
        }
        guard server.isLoggedIn else { return }
        loading = true
        defer { loading = false }
        do {
            async let a = server.matches(mine: false)
            async let b = server.matches(mine: true)
            async let c = server.leaderboard()
            (open, mine, leaders) = try await (a, b, c)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MatchCard: View {
    var match: APIMatch
    var joined: Bool
    var onChange: () async -> Void
    @EnvironmentObject private var server: ServerAPI
    @State private var busy = false
    @State private var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Chip(text: match.typeLabel, color: Neo.cyan)
                if match.isPublic == false { Chip(text: "Privé", systemImage: "lock.fill", color: Neo.magenta) }
                Spacer()
                Text(match.spotsLeft == 0 ? "Complet" : "\(match.spotsLeft) place\(match.spotsLeft > 1 ? "s" : "")")
                    .font(Neo.label(12)).foregroundStyle(match.spotsLeft == 0 ? Neo.faint : Neo.volt)
            }
            Text(match.title ?? "Match de padel").font(Neo.label(16)).foregroundStyle(Neo.text)
            if let d = match.date {
                Text(d.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: "fr_FR"))))
                    .font(Neo.mono(13)).foregroundStyle(Neo.cyan)
            }
            Text([match.clubName, match.location?.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Neo.body(13)).foregroundStyle(Neo.dim).lineLimit(2)
            HStack(spacing: -8) {
                ForEach((match.participants ?? []).prefix(4)) { p in
                    Text(String((p.userName ?? "?").prefix(1)).uppercased()).font(Neo.label(12)).foregroundStyle(Neo.night)
                        .frame(width: 30, height: 30).background(Circle().fill(Neo.neonGradient)).overlay(Circle().stroke(Neo.night, lineWidth: 2))
                }
                ForEach(0..<match.spotsLeft, id: \.self) { _ in
                    Circle().strokeBorder(Neo.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3])).frame(width: 30, height: 30)
                }
                Spacer()
                Text("Niv. \(match.minSkillLevel ?? 1)–\(match.maxSkillLevel ?? 8)").font(Neo.label(11)).foregroundStyle(Neo.dim)
            }
            if let message { Text(message).font(Neo.body(12)).foregroundStyle(Neo.volt) }
            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        if joined { try await server.leave(matchID: match.id); message = "Tu as quitté le match." }
                        else { try await server.join(matchID: match.id); message = "C'est noté, tu joues ! 🎾" }
                        await onChange()
                    } catch { message = error.localizedDescription }
                }
            } label: {
                if busy { ProgressView().tint(Neo.night) } else { Text(joined ? "Quitter le match" : "Rejoindre") }
            }
            .buttonStyle(NeonButtonStyle(color: joined ? Neo.magenta : Neo.volt, filled: !joined))
            .disabled(busy || (!joined && match.spotsLeft == 0))
        }
        .glassCard(radius: 20, padding: 14)
    }
}

struct CreateMatchView: View {
    var club: Club
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: ServerAPI
    @State private var title = "Match amical"
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var duration = 90
    @State private var players = 4
    @State private var minLevel = 2
    @State private var maxLevel = 6
    @State private var isPublic = true
    @State private var price = 10.0
    @State private var busy = false
    @State private var error: String? = nil
    @State private var done = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(intensity: 0.35)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ScreenHeader(title: "Créer un match", subtitle: club.displayName)
                        if !server.isLoggedIn && ShotMode.current == nil {
                            EmptyStateView(systemImage: "person.crop.circle", title: "Compte PadelUp requis", message: "Connecte-toi dans l'onglet Profil.")
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                TextField("Titre", text: $title).font(Neo.body(16)).padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                                DatePicker("Date et heure", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                    .environment(\.locale, Locale(identifier: "fr_FR"))
                                Picker("Durée", selection: $duration) { Text("60 min").tag(60); Text("90 min").tag(90); Text("120 min").tag(120) }
                                    .pickerStyle(.segmented)
                                Stepper("\(players) joueurs", value: $players, in: 2...4, step: 2)
                                Stepper("Niveau min \(minLevel)", value: $minLevel, in: 1...8)
                                Stepper("Niveau max \(maxLevel)", value: $maxLevel, in: minLevel...8)
                                Stepper("\(Int(price)) € par joueur", value: $price, in: 0...60, step: 1)
                                Toggle("Match public", isOn: $isPublic).tint(Neo.volt)
                            }
                            .font(Neo.body(14))
                            .glassCard()
                            if let error { Text(error).font(Neo.body(13)).foregroundStyle(Neo.danger) }
                            if done { Text("Match créé ✅ Il apparaît dans « Matchs ».").font(Neo.body(14)).foregroundStyle(Neo.volt) }
                            Button {
                                Task {
                                    busy = true
                                    defer { busy = false }
                                    do {
                                        _ = try await server.createMatch(club: club, date: date, duration: duration, title: title, maxPlayers: players,
                                                                         minLevel: minLevel, maxLevel: maxLevel, isPublic: isPublic, price: price)
                                        done = true
                                        try? await Task.sleep(nanoseconds: 900_000_000)
                                        dismiss()
                                    } catch { self.error = error.localizedDescription }
                                }
                            } label: { if busy { ProgressView().tint(Neo.night) } else { Text("Publier le match") } }
                            .buttonStyle(NeonButtonStyle(color: Neo.volt))
                            .disabled(busy || done)
                        }
                    }
                    .padding(18)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() }.foregroundStyle(Neo.volt) } }
        }
    }
}
