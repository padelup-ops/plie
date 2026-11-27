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
    @State private var pending: APIPendingRating? = nil

    var body: some View {
        Screen(title: "Matchs", subtitle: "Trouve des joueurs de ton niveau et grimpe au classement.") {
            Picker("", selection: $tab) {
                Text("Ouverts").tag(0); Text("Les miens").tag(1); Text("Classement").tag(2)
            }
            .pickerStyle(.segmented)
            if let pending, pending.hasPendingRating, let m = pending.match {
                Button { router.openMatch = m } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: pending.isOrganizer == true && pending.winnerDefined != true ? "trophy" : "star", color: UI.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pending.isOrganizer == true && pending.winnerDefined != true ? "Saisis le résultat de ton match" : "Note les joueurs de ton dernier match")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                            Text(m.title ?? "Match de padel").font(UI.caption()).foregroundStyle(UI.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(UI.faint)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(.plain)
            }
            if !server.isLoggedIn && ShotMode.current == nil {
                EmptyStateView(systemImage: "person.crop.circle", title: "Connecte-toi à PadelUp",
                               message: "Les matchs et le classement utilisent ton compte PadelUp.")
                Button { router.tab = .profile } label: { Text("Se connecter") }.buttonStyle(PrimaryButtonStyle())
            } else if let error {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Serveur indisponible", message: error)
            } else if loading && open.isEmpty && mine.isEmpty && leaders.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else if tab == 2 {
                leaderboard
            } else {
                let list = tab == 0 ? open : mine
                if list.isEmpty {
                    EmptyStateView(systemImage: "sportscourt", title: tab == 0 ? "Aucun match ouvert" : "Aucun match prévu",
                                   message: "Crée un match depuis la fiche de n'importe quel club de la carte.")
                }
                ForEach(list) { m in
                    MatchCard(match: m, joined: tab == 1) { await reload() }
                        .contentShape(Rectangle())
                        .onTapGesture { router.openMatch = m }
                }
            }
        }
        .refreshable { await reload() }
        .task(id: server.isLoggedIn) { await reload() }
    }

    private var leaderboard: some View {
        VStack(spacing: 0) {
            ForEach(Array(leaders.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 14) {
                    Text("\(i + 1)").font(UI.number(17)).foregroundStyle(i < 3 ? UI.accent : UI.muted).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                        Text("\(p.matchesPlayed ?? 0) matchs · \(Int((p.winRate ?? 0).rounded())) % de victoires").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                    Spacer()
                    Text("\(p.matchesWon ?? 0)").font(UI.number(18)).foregroundStyle(UI.ink)
                }
                .padding(.vertical, 12)
                if i < leaders.count - 1 { Divider().overlay(UI.line) }
            }
        }
        .padding(.horizontal, 14)
        .card(padding: 0)
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
            pending = await server.pendingRating()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Tag(text: match.typeLabel, color: UI.accent)
                if match.isPublic == false { Tag(text: "Privé", systemImage: "lock.fill", color: UI.muted) }
                Spacer()
                Text(match.spotsLeft == 0 ? "Complet" : "\(match.spotsLeft) place\(match.spotsLeft > 1 ? "s" : "")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(match.spotsLeft == 0 ? UI.faint : UI.success)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(match.title ?? "Match de padel").font(UI.headline()).foregroundStyle(UI.ink)
                if let d = match.date {
                    Text(d.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: "fr_FR"))).capitalized)
                        .font(UI.callout()).foregroundStyle(UI.ink.opacity(0.8))
                }
                Text([match.clubName, match.location?.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(UI.caption()).foregroundStyle(UI.muted).lineLimit(2)
            }
            HStack(spacing: -6) {
                ForEach((match.participants ?? []).prefix(4)) { p in
                    Text(String((p.userName ?? "?").prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(UI.onAccent)
                        .frame(width: 30, height: 30).background(Circle().fill(UI.accent)).overlay(Circle().stroke(UI.card, lineWidth: 2))
                }
                ForEach(0..<match.spotsLeft, id: \.self) { _ in
                    Circle().strokeBorder(UI.faint, style: StrokeStyle(lineWidth: 1.2, dash: [3])).frame(width: 30, height: 30)
                        .background(Circle().fill(UI.card))
                }
                Spacer()
                Text("Niveau \(match.minSkillLevel ?? 1)–\(match.maxSkillLevel ?? 8)").font(UI.small()).foregroundStyle(UI.muted)
            }
            if let message { Text(message).font(UI.caption()).foregroundStyle(UI.success) }
            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        if joined { try await server.leave(matchID: match.id); message = "Tu as quitté le match." }
                        else { try await server.join(matchID: match.id); message = "C'est noté, tu joues !" }
                        await onChange()
                    } catch { message = error.localizedDescription }
                }
            } label: {
                if busy { ProgressView() } else { Text(joined ? "Quitter le match" : "Rejoindre") }
            }
            .buttonStyle(SecondaryButtonStyle(color: joined ? UI.danger : UI.accent))
            .disabled(busy || (!joined && match.spotsLeft == 0))
        }
        .card()
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
            Screen(title: "Créer un match", subtitle: club.displayName) {
                if !server.isLoggedIn {
                    EmptyStateView(systemImage: "person.crop.circle", title: "Compte PadelUp requis", message: "Connecte-toi dans l'onglet Profil.")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        InputField(title: "Titre", text: $title)
                        DatePicker("Date et heure", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Locale(identifier: "fr_FR"))
                        Picker("Durée", selection: $duration) { Text("60 min").tag(60); Text("90 min").tag(90); Text("120 min").tag(120) }
                            .pickerStyle(.segmented)
                        Stepper("\(players) joueurs", value: $players, in: 2...4, step: 2)
                        Stepper("Niveau minimum  \(minLevel)", value: $minLevel, in: 1...8)
                        Stepper("Niveau maximum  \(maxLevel)", value: $maxLevel, in: minLevel...8)
                        Stepper("\(Int(price)) € par joueur", value: $price, in: 0...60, step: 1)
                        Toggle("Match public", isOn: $isPublic).tint(UI.accent)
                    }
                    .font(UI.callout())
                    .card()
                    if let error { Text(error).font(UI.caption()).foregroundStyle(UI.danger) }
                    if done { Text("Match créé. Il apparaît dans l'onglet Matchs.").font(UI.callout()).foregroundStyle(UI.success) }
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
                    } label: { if busy { ProgressView().tint(UI.onAccent) } else { Text("Publier le match") } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || done)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
    }
}
