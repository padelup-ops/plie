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
    @State private var history: [APIMatch] = []

    var body: some View {
        Screen(title: "Matchs", eyebrow: "Joue à ton niveau") {
            VStack(alignment: .leading, spacing: 22) {
                UnderlineTabs(items: ["Ouverts", "Les miens", "Radar", "Top"], selection: $tab)
                if let pending, pending.hasPendingRating, let m = pending.match { pendingRow(pending, m) }
                content
            }
        }
        .refreshable { await reload() }
        .task(id: server.isLoggedIn) { await reload() }
    }

    @ViewBuilder private var content: some View {
        if !server.isLoggedIn && ShotMode.current == nil {
            EmptyNote(title: "Connecte-toi à PadelUp.", message: "Les matchs, les joueurs de ton niveau et le classement utilisent ton compte PadelUp.",
                      actionTitle: "Se connecter") { router.tab = .profile }
        } else if let error {
            EmptyNote(title: "Serveur indisponible.", message: error, actionTitle: "Réessayer") { Task { await reload() } }
        } else if loading && open.isEmpty && mine.isEmpty && leaders.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        } else if tab == 2 {
            RadarSection()
        } else if tab == 3 {
            leaderboard
        } else {
            let list = tab == 0 ? open : mine
            if tab == 1 && list.isEmpty && !history.isEmpty {
                EmptyNote(title: "Aucun match à venir.", message: "Ton historique est juste en dessous.")
            } else if list.isEmpty {
                EmptyNote(title: tab == 0 ? "Aucun match ouvert pour l'instant." : "Aucun match prévu.",
                          message: "Crée un match depuis la fiche de n'importe quel club : les joueurs de ton niveau le verront ici.",
                          actionTitle: "Choisir un club") { router.tab = .clubs }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                        Button { router.openMatch = m } label: { MatchRow(match: m) }.buttonStyle(.plain)
                        if i < list.count - 1 { Hairline(inset: 70) }
                    }
                }
            }
            if tab == 1 && !history.isEmpty {
                Block(title: "Historique", meta: "\(history.count) match\(history.count > 1 ? "s" : "")") {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(20).enumerated()), id: \.element.id) { i, m in
                            Button { router.openMatch = m } label: { MatchRow(match: m).opacity(0.75) }.buttonStyle(.plain)
                            if i < min(history.count, 20) - 1 { Hairline(inset: 70) }
                        }
                    }
                }
            }
        }
    }

    private func pendingRow(_ pending: APIPendingRating, _ m: APIMatch) -> some View {
        Button { router.openMatch = m } label: {
            HStack(spacing: 12) {
                Stamp(text: "À faire", style: .clay)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.isOrganizer == true && pending.winnerDefined != true ? "Saisis le résultat" : "Note les joueurs")
                        .font(UI.headline()).foregroundStyle(UI.ink)
                    Text(m.title ?? "Match de padel").font(UI.caption()).foregroundStyle(UI.muted)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(UI.ink)
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.clay.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var leaderboard: some View {
        VStack(spacing: 0) {
            if leaders.isEmpty {
                EmptyNote(title: "Pas encore de classement.", message: "Termine un match et saisis le résultat pour y entrer.")
            }
            ForEach(Array(leaders.enumerated()), id: \.element.id) { i, p in
                Button { if let uid = p.user?.id { router.sheet = .player(uid) } } label: {
                HStack(spacing: 16) {
                    Text("\(i + 1)").font(UI.scoreHeavy(32)).foregroundStyle(i < 3 ? UI.ink : UI.faint).frame(width: 40, alignment: .leading)
                    Avatar(name: p.displayName, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(p.displayName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                            if i == 0 { Stamp(text: "1er") }
                        }
                        Text("\(p.matchesPlayed ?? 0) matchs · \(Int((p.winRate ?? 0).rounded())) % de victoires").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(p.matchesWon ?? 0)").font(UI.score(24)).foregroundStyle(UI.ink)
                        Eyebrow(text: "victoires")
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < leaders.count - 1 { Hairline(inset: 56) }
            }
        }
    }

    private func reload() async {
        if ShotMode.current != nil {
            open = ShotMode.demoMatches()
            mine = Array(open.prefix(1))
            history = ShotMode.demoHistory()
            leaders = ShotMode.demoLeaders()
            if ShotMode.current == "radar" { tab = 2 }
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
            history = (try? await server.matchHistory()) ?? history
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Un match : le jour en grand à gauche (calendrier), l'heure, le club, les places, le niveau.
struct MatchRow: View {
    var match: APIMatch

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DateBlock(date: match.date)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(match.date.map { FR.time($0) } ?? "–").font(UI.score(18)).foregroundStyle(UI.ink)
                    Text(match.typeLabel.uppercased(with: UI.fr)).font(UI.label()).tracking(0.8).foregroundStyle(UI.muted)
                    if match.isPublic == false { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(UI.muted) }
                    Spacer(minLength: 6)
                    if match.spotsLeft == 0 { Stamp(text: "Complet", style: .outline) }
                    else { Stamp(text: "\(match.spotsLeft) place\(match.spotsLeft > 1 ? "s" : "")") }
                }
                Text(match.title ?? "Match de padel").font(UI.headline()).foregroundStyle(UI.ink).multilineTextAlignment(.leading)
                Text([match.clubName, match.location?.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                HStack {
                    PlayerDots(match: match)
                    Spacer()
                    HStack(spacing: 6) {
                        LevelBars(level: match.maxSkillLevel ?? 8, height: 12, barWidth: 2.5)
                        Text("Niv. \(match.minSkillLevel ?? 1)–\(match.maxSkillLevel ?? 8)").font(UI.score(14)).foregroundStyle(UI.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// Bloc date façon calendrier : SAM / 28 / NOV.
struct DateBlock: View {
    var date: Date?

    var body: some View {
        VStack(spacing: 0) {
            Text(date.map { FR.string($0, "EEE").replacingOccurrences(of: ".", with: "") }?.uppercased(with: UI.fr) ?? "")
                .font(UI.label()).tracking(0.8).foregroundStyle(UI.muted)
            Text(date.map { FR.string($0, "d") } ?? "–").font(UI.scoreHeavy(40)).foregroundStyle(UI.ink)
            Text(date.map { FR.string($0, "MMM").replacingOccurrences(of: ".", with: "") }?.uppercased(with: UI.fr) ?? "")
                .font(UI.label()).tracking(0.8).foregroundStyle(UI.muted)
        }
        .frame(width: 54)
    }
}

/// Joueurs inscrits (initiales) et places libres (cercles en pointillés).
struct PlayerDots: View {
    var match: APIMatch
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -7) {
            ForEach((match.participants ?? []).prefix(4)) { p in
                Avatar(name: p.userName ?? "?", size: size).overlay(Circle().stroke(UI.paper, lineWidth: 2))
            }
            ForEach(0..<match.spotsLeft, id: \.self) { _ in
                Circle().strokeBorder(UI.faint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .frame(width: size, height: size)
                    .background(Circle().fill(UI.paper))
            }
        }
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
            Screen(title: "Nouveau match", eyebrow: club.displayName, seasonal: false) {
                if !server.isLoggedIn {
                    EmptyNote(title: "Compte PadelUp requis.", message: "Connecte-toi dans l'onglet Profil pour créer un match.")
                } else {
                    Block(title: "Le match") {
                        VStack(alignment: .leading, spacing: 16) {
                            InputField(title: "Titre", text: $title)
                            DatePicker("Date et heure", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .environment(\.locale, UI.fr).font(UI.body())
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "Durée")
                                InlinePicker(options: [(60, "60 min"), (90, "90 min"), (120, "120 min")], selection: $duration)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "Joueurs")
                                InlinePicker(options: [(2, "2 joueurs"), (4, "4 joueurs")], selection: $players)
                            }
                        }
                    }
                    Block(title: "Niveau") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 0) {
                                levelStepper("Minimum", value: $minLevel, range: 1...maxLevel)
                                Rectangle().fill(UI.rule).frame(width: 0.5, height: 56).padding(.horizontal, 14)
                                levelStepper("Maximum", value: $maxLevel, range: minLevel...8)
                            }
                            Stepper(value: $price, in: 0...60, step: 1) {
                                Text("\(Int(price)) € par joueur").font(UI.score(20)).foregroundStyle(UI.ink)
                            }
                            Toggle("Match public", isOn: $isPublic).tint(UI.court).font(UI.body())
                        }
                    }
                    if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                    if done { Text("Match publié. Il apparaît dans l'onglet Matchs.").font(UI.callout()).foregroundStyle(UI.success) }
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
                    } label: { if busy { ProgressView().tint(UI.onCourt) } else { Text("Publier le match") } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || done)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
    }

    private func levelStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label)
            HStack(spacing: 10) {
                Text("\(value.wrappedValue)").font(UI.score(30)).foregroundStyle(UI.ink)
                Stepper("", value: value, in: range).labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
