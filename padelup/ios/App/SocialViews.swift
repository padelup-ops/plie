import SwiftUI

// MARK: - Niveaux de jeu (mêmes noms que le serveur : Profile.get_tier_name)

enum PadelLevel {
    static let fft = ["Débutant", "Perfectionnement", "Élémentaire", "Intermédiaire", "Confirmé", "Avancé", "Expert", "Élite"]
    static let classic = ["Découverte", "Initiation", "Loisir", "Partenaire", "Adversaire", "Stratège", "Perfectionniste",
                          "Challenger", "Compétiteur", "Élite"]

    /// Repères indicatifs pour l'échelle en 8 niveaux.
    static let fftHints = [
        "Je découvre le padel : règles, prise de raquette, premiers échanges.",
        "Je tiens l'échange sur des balles faciles et je découvre le jeu avec les vitres.",
        "Je joue régulièrement ; la volée et la sortie de vitre de fond arrivent.",
        "Je place la balle, je lobe et je défends avec les vitres.",
        "Bandeja maîtrisée, je construis les points et je joue des tournois loisirs.",
        "Jeu complet et varié (víbora, effets) ; tournois de bon niveau régional.",
        "Très bon niveau de compétition, régulier dans les grands tournois.",
        "Niveau national ou international.",
    ]

    static func names(_ scale: String) -> [String] { scale == "old" ? classic : fft }

    static func name(_ level: Int, scale: String) -> String {
        let list = names(scale)
        return list[max(0, min(list.count - 1, level - 1))]
    }
}

// MARK: - Choix du niveau (après l'inscription, ou depuis le profil)

struct LevelPickerView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var scale = "new"
    @State private var level = 3
    @State private var rightHanded = true
    @State private var city = ""
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Ton niveau", subtitle: "Il sert à te proposer des matchs équilibrés. Tu pourras le changer quand tu veux.") {
                Picker("Échelle", selection: $scale) {
                    Text("Échelle FFT (1 à 8)").tag("new")
                    Text("Échelle 1 à 10").tag("old")
                }
                .pickerStyle(.segmented)
                .onChange(of: scale) { _, s in level = min(level, PadelLevel.names(s).count) }
                VStack(spacing: 0) {
                    let names = PadelLevel.names(scale)
                    ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                        Button { level = i + 1 } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(i + 1)").font(UI.number(18)).foregroundStyle(level == i + 1 ? UI.onAccent : UI.ink)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(level == i + 1 ? UI.accent : UI.tray))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                                    if scale == "new" {
                                        Text(PadelLevel.fftHints[i]).font(UI.caption()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                                if level == i + 1 { Image(systemName: "checkmark").foregroundStyle(UI.accent).padding(.top, 8) }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < names.count - 1 { Divider().overlay(UI.line).padding(.leading, 50) }
                    }
                }
                .padding(.horizontal, 14)
                .card(padding: 0)
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Main", selection: $rightHanded) {
                        Text("Droitier").tag(true)
                        Text("Gaucher").tag(false)
                    }
                    .pickerStyle(.segmented)
                    InputField(title: "Ville (pour les matchs près de chez toi)", text: $city)
                }
                .card()
                if let error { Text(error).font(UI.caption()).foregroundStyle(UI.danger) }
                Button { Task { await save() } } label: {
                    if busy { ProgressView().tint(UI.onAccent) } else { Text("Enregistrer mon niveau") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Plus tard") { dismiss() } } }
        }
        .tint(UI.accent)
        .onAppear {
            if let p = server.me?.profile {
                scale = p.evaluationType ?? "new"
                level = p.skillLevel ?? 3
                rightHanded = p.rightHanded ?? true
                city = p.location ?? ""
            }
        }
    }

    private func save() async {
        if ShotMode.current != nil { dismiss(); return }
        busy = true
        defer { busy = false }
        do {
            try await server.updateProfile(skillLevel: level, scale: scale, rightHanded: rightHanded, location: city)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Amis

struct PersonRow<Trailing: View>: View {
    var person: APIPerson
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(person.initial).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(Circle().fill(UI.hero))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink).lineLimit(1)
                let detail = [person.levelLabel, person.city ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
    }
}

struct FriendsView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var friends: [APIFriendship] = []
    @State private var requests = APIFriendRequests(received: [], sent: [])
    @State private var suggestions: [APIPerson] = []
    @State private var query = ""
    @State private var results: [APIPerson] = []
    @State private var sentTo: Set<Int> = []
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Amis", subtitle: "Retrouve tes partenaires et invite-les à jouer.") {
                Picker("", selection: $tab) {
                    Text("Mes amis").tag(0)
                    Text(requests.received.isEmpty ? "Demandes" : "Demandes (\(requests.received.count))").tag(1)
                    Text("Ajouter").tag(2)
                }
                .pickerStyle(.segmented)
                if let error { Text(error).font(UI.caption()).foregroundStyle(UI.danger) }
                switch tab {
                case 0: friendsList
                case 1: requestsList
                default: addList
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
        .task { await load() }
    }

    @ViewBuilder private var friendsList: some View {
        if friends.isEmpty {
            EmptyStateView(systemImage: "person.2", title: "Pas encore d'amis", message: "Cherche tes partenaires dans « Ajouter ».")
        } else {
            VStack(spacing: 0) {
                ForEach(friends) { f in
                    if let p = f.friend {
                        PersonRow(person: p) {
                            Menu {
                                Button("Retirer de mes amis", role: .destructive) { Task { try? await server.removeFriend(p.id); await load() } }
                            } label: { Image(systemName: "ellipsis").foregroundStyle(UI.muted).frame(width: 32, height: 32) }
                        }
                        Divider().overlay(UI.line).padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 14)
            .card(padding: 0)
        }
    }

    @ViewBuilder private var requestsList: some View {
        if requests.received.isEmpty && requests.sent.isEmpty {
            EmptyStateView(systemImage: "tray", title: "Aucune demande", message: "Les demandes d'amis reçues apparaissent ici.")
        } else {
            if !requests.received.isEmpty {
                SectionHeader(title: "Reçues")
                VStack(spacing: 0) {
                    ForEach(requests.received) { r in
                        if let p = r.senderInfo {
                            PersonRow(person: p) {
                                HStack(spacing: 8) {
                                    Button { Task { try? await server.answerFriendRequest(r.id, accept: false); await load() } } label: {
                                        Image(systemName: "xmark").frame(width: 34, height: 34).background(Circle().fill(UI.tray))
                                    }.foregroundStyle(UI.muted)
                                    Button { Task { try? await server.answerFriendRequest(r.id, accept: true); await load() } } label: {
                                        Image(systemName: "checkmark").frame(width: 34, height: 34).background(Circle().fill(UI.accent))
                                    }.foregroundStyle(UI.onAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .card(padding: 0)
            }
            if !requests.sent.isEmpty {
                SectionHeader(title: "Envoyées")
                VStack(spacing: 0) {
                    ForEach(requests.sent) { r in
                        if let p = r.receiverInfo {
                            PersonRow(person: p) { Text("En attente").font(UI.small()).foregroundStyle(UI.muted) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .card(padding: 0)
            }
        }
    }

    @ViewBuilder private var addList: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(UI.muted)
            TextField("Nom ou pseudo d'un joueur", text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onSubmit { Task { await search() } }
                .onChange(of: query) { _, text in
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if text == query { await search() }
                    }
                }
        }
        .padding(.horizontal, 16).frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.tray))
        let list = query.count >= 2 ? results : suggestions
        if !list.isEmpty {
            SectionHeader(title: query.count >= 2 ? "Résultats" : "Suggestions")
            VStack(spacing: 0) {
                ForEach(list) { p in
                    PersonRow(person: p) {
                        if p.isFriend == true {
                            Text("Ami").font(UI.small()).foregroundStyle(UI.success)
                        } else if p.hasPendingRequest == true || sentTo.contains(p.id) {
                            Text("Demande envoyée").font(UI.small()).foregroundStyle(UI.muted)
                        } else {
                            Button {
                                Task {
                                    do { try await server.sendFriendRequest(to: p.id); sentTo.insert(p.id) } catch { self.error = error.localizedDescription }
                                }
                            } label: { Label("Ajouter", systemImage: "person.badge.plus") }
                            .buttonStyle(LinkButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .card(padding: 0)
        }
    }

    private func load() async {
        guard server.isLoggedIn else { return }
        do {
            async let a = server.friends()
            async let b = server.friendRequests()
            (friends, requests) = try await (a, b)
            suggestions = (try? await server.suggestions()) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        results = (try? await server.searchPlayers(q)) ?? []
    }
}

// MARK: - Fiche match : joueurs, chat, résultat, notes

struct MatchDetailView: View {
    @State var match: APIMatch
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var flags = APIMatchFlags(isOrganizer: nil, isParticipant: nil)
    @State private var messages: [APIMessage] = []
    @State private var draft = ""
    @State private var winners: Set<Int> = []
    @State private var ratings: [Int: Int] = [:]
    @State private var rated: Set<Int> = []
    @State private var courtStars = 0
    @State private var info: String? = nil
    @State private var busy = false

    private var players: [APIParticipant] { (match.participants ?? []).filter { $0.status == nil || $0.status == "confirmed" } }
    private var isMember: Bool { flags.isOrganizer == true || flags.isParticipant == true || ShotMode.current != nil }
    private var started: Bool { (match.date ?? .distantFuture) < Date() }
    private var completed: Bool { match.status == "completed" }
    private var myID: Int? { server.me?.id }

    var body: some View {
        NavigationStack {
            Screen(title: match.title ?? "Match de padel", subtitle: [match.clubName, match.courtName].compactMap { $0 }.joined(separator: " · ")) {
                summary
                playersCard
                if isMember && started && flags.isOrganizer == true && !completedWithResult { resultCard }
                if isMember && completed { ratingCard }
                if isMember { chatCard }
                if let info { Text(info).font(UI.caption()).foregroundStyle(UI.success).padding(.horizontal, 4) }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
        .task { await load() }
    }

    private var completedWithResult: Bool { completed && info == "Résultat enregistré." }

    private var summary: some View {
        HStack(spacing: 10) {
            Metric(value: match.date.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))) } ?? "–", label: "date")
            Metric(value: match.date.map { $0.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR"))) } ?? "–", label: "heure")
            Metric(value: "\(match.minSkillLevel ?? 1)–\(match.maxSkillLevel ?? 8)", label: "niveaux")
        }
    }

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Joueurs").font(UI.headline()).foregroundStyle(UI.ink)
                Spacer()
                Text("\(players.count)/\(match.maxPlayers ?? 4)").font(UI.caption()).foregroundStyle(UI.muted)
            }
            .padding(.bottom, 4)
            ForEach(players) { p in
                HStack(spacing: 12) {
                    Text(String((p.userName ?? "?").prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(UI.hero))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.userName ?? "Joueur").font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                        if let lvl = p.userSkillLevel { Text("Niveau \(lvl)").font(UI.caption()).foregroundStyle(UI.muted) }
                    }
                    Spacer()
                    if p.user == match.organizer { Tag(text: "Organisateur", color: UI.accent) }
                }
                .padding(.vertical, 6)
            }
            ForEach(0..<max(0, (match.maxPlayers ?? 4) - players.count), id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().strokeBorder(UI.faint, style: StrokeStyle(lineWidth: 1.2, dash: [3])).frame(width: 36, height: 36)
                    Text("Place libre").font(UI.callout()).foregroundStyle(UI.faint)
                }
                .padding(.vertical, 6)
            }
        }
        .card()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Résultat").font(UI.headline()).foregroundStyle(UI.ink)
            Text("Touche les vainqueurs : les autres joueurs sont comptés perdants.").font(UI.caption()).foregroundStyle(UI.muted)
            FlowRow(players.compactMap { p in p.user.map { ($0, p.userName ?? "Joueur") } }) { id, name in
                Button {
                    if winners.contains(id) { winners.remove(id) } else { winners.insert(id) }
                } label: { Pill(text: name, systemImage: winners.contains(id) ? "trophy.fill" : nil, active: winners.contains(id)) }
                .buttonStyle(.plain)
            }
            Button {
                Task {
                    let all = Set(players.compactMap { $0.user })
                    do {
                        try await server.finish(match.id, winners: Array(winners), losers: Array(all.subtracting(winners)))
                        info = "Résultat enregistré."
                        await load()
                    } catch { info = error.localizedDescription }
                }
            } label: { Text("Enregistrer le résultat") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(winners.isEmpty)
        }
        .card()
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note les joueurs").font(UI.headline()).foregroundStyle(UI.ink)
            Text("Ta note (de 1 à 10) affine le niveau public de chacun. Elle reste anonyme.").font(UI.caption()).foregroundStyle(UI.muted)
            ForEach(players.filter { $0.user != nil && $0.user != myID }) { p in
                let uid = p.user ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(p.userName ?? "Joueur").font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                        Spacer()
                        if rated.contains(uid) {
                            Label("Noté", systemImage: "checkmark").font(UI.small()).foregroundStyle(UI.success)
                        } else {
                            Text("\(ratings[uid] ?? 6)/10").font(UI.number(15)).foregroundStyle(UI.accent)
                        }
                    }
                    if !rated.contains(uid) {
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { n in
                                Button { ratings[uid] = n } label: {
                                    Capsule().fill(n <= (ratings[uid] ?? 6) ? UI.accent : UI.tray).frame(height: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Envoyer la note") {
                            Task {
                                do { try await server.ratePlayer(match: match.id, user: uid, rating: ratings[uid] ?? 6); rated.insert(uid) }
                                catch { info = error.localizedDescription }
                            }
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            if let court = match.court {
                Divider().overlay(UI.line)
                HStack {
                    Text("Le terrain").font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                    Spacer()
                    ForEach(1...5, id: \.self) { n in
                        Button {
                            courtStars = n
                            Task { try? await server.rateCourt(match: match.id, court: court, rating: n) }
                        } label: { Image(systemName: n <= courtStars ? "star.fill" : "star").foregroundStyle(n <= courtStars ? UI.warning : UI.faint) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discussion").font(UI.headline()).foregroundStyle(UI.ink)
            if messages.isEmpty {
                Text("Pas encore de message. Organise-toi avec les autres joueurs ici.").font(UI.caption()).foregroundStyle(UI.muted)
            }
            ForEach(messages.suffix(30)) { m in
                let mine = m.sender != nil && m.sender == myID
                HStack {
                    if mine { Spacer(minLength: 40) }
                    VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                        if !mine { Text(m.senderName ?? "Joueur").font(UI.small()).foregroundStyle(UI.muted) }
                        Text(m.content).font(UI.callout()).foregroundStyle(mine ? UI.onAccent : UI.ink)
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(mine ? UI.accent : UI.tray))
                    }
                    if !mine { Spacer(minLength: 40) }
                }
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft).font(UI.body()).padding(.horizontal, 14).frame(height: 44)
                    .background(Capsule().fill(UI.tray))
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft = ""
                    Task { try? await server.sendChat(match.id, text: text); messages = (try? await server.chat(match.id)) ?? messages }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(UI.onAccent)
                        .frame(width: 44, height: 44).background(Circle().fill(UI.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func load() async {
        guard ShotMode.current == nil, server.isLoggedIn else { return }
        if let detail = try? await server.matchDetail(match.id) {
            match = detail.0
            flags = detail.1
        }
        if isMember { messages = (try? await server.chat(match.id)) ?? [] }
    }
}

/// Rangée qui passe à la ligne (choix des vainqueurs).
struct FlowRow<Content: View>: View {
    var items: [(Int, String)]
    var content: (Int, String) -> Content

    init(_ items: [(Int, String)], @ViewBuilder content: @escaping (Int, String) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in content(items[i].0, items[i].1) }
        }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var items: [APINotification] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Screen(title: "Notifications") {
                if loaded && items.isEmpty {
                    EmptyStateView(systemImage: "bell", title: "Rien de neuf", message: "Invitations, matchs, amis et réservations du bot apparaissent ici.")
                }
                if !items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(items) { n in
                            HStack(alignment: .top, spacing: 12) {
                                IconBadge(systemImage: icon(n.type), color: n.isRead == false ? UI.accent : UI.muted, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.message).font(UI.callout()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                                    if let d = n.date { Text(d.formatted(.relative(presentation: .named))).font(UI.small()).foregroundStyle(UI.faint) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            Divider().overlay(UI.line).padding(.leading, 46)
                        }
                    }
                    .padding(.horizontal, 14)
                    .card(padding: 0)
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
        .task { await load() }
    }

    private func icon(_ type: String?) -> String {
        switch type ?? "" {
        case let t where t.hasPrefix("friend"): return "person.badge.plus"
        case let t where t.hasPrefix("bot"): return "bolt"
        case "new_booking": return "calendar"
        case let t where t.hasPrefix("booking"): return "calendar"
        default: return "sportscourt"
        }
    }

    private func load() async {
        guard server.isLoggedIn else { loaded = true; return }
        items = (try? await server.notifications()) ?? items
        loaded = true
        await server.markNotificationsRead()
    }
}
