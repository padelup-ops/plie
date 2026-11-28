import SwiftUI

// MARK: - Niveaux de jeu (mêmes noms que le serveur : Profile.get_tier_name)

enum PadelLevel {
    static let fft = ["Débutant", "Perfectionnement", "Élémentaire", "Intermédiaire", "Confirmé", "Avancé", "Expert", "Élite"]
    static let classic = ["Découverte", "Initiation", "Loisir", "Partenaire", "Adversaire", "Stratège", "Perfectionniste",
                          "Challenger", "Compétiteur", "Élite"]

    /// Description du jeu pour chaque niveau FFT (mêmes textes que l'app PadelUp actuelle, d'après les niveaux de padel 2025).
    static let fftHints = [
        "Je commence à jouer. J'apprends les coups de base.",
        "Je joue les coups de base. Je joue lentement des échanges courts. Je commence à voler.",
        "Je joue en loisir. Je sais servir et je joue des matches avec échanges, en essayant de garder la balle en jeu. Je commence à jouer avec la vitre du fond.",
        "Je joue des matches avec de longs échanges et montées-descentes répétées au filet. Je monte au filet au service et après un lob. Je redescends en défense sur lob adverse pour rejouer la balle. Je joue la balle après rebond sur la vitre. Je maîtrise le placement, notamment en fonction de mon partenaire, que j'accompagne au filet ou en recul du fond de court.",
        "Je maîtrise mon jeu, avec service-volée, repli sur les lobs, remontée en contre-attaque, coups avec effets, retours de service en lob dans les pieds, et placement en phase avec mon partenaire. Je monte toujours au filet après un lob. Je finis des points à la volée et en smash. Je joue avec les vitres en défense, et remets la balle en jeu sur 360 et doubles vitres.",
        "Je maîtrise le jeu rapide et les effets, au service ou dans le jeu. Je varie les zones et vitesses de mes volées. Je défends les doubles vitres. Je maîtrise parfaitement le 360. Je contre-attaque les smashs de l'adversaire.",
        "Je maîtrise tous les aspects du jeu et les tactiques. J'utilise un jeu avec des effets maîtrisés, comme la bandeja et la vibora. Je maîtrise parfaitement les doubles vitres, et j'utilise les vitres en contre-attaque.",
        "Joueuse experte : top 150 française. Joueur expert : top 100 française.",
    ]

    /// Repères de classement et de tournois (vides pour les premiers niveaux).
    static let fftCriteria = [
        "",
        "",
        "",
        "Matches gagnés en P25 et P100 avec classement en fin de tableau de P100. Moyenne de points par tournoi joué : de 5 à 25 points.",
        "Joueuse confirmée : top 1.050 française (jusqu'à 900€). Joueur confirmé : top 10.000 française (jusqu'à 6.000€). P100 : classement en fin de tableau, 50 % de matches gagnés. P250 : classement en fin de tableau. + de 12 tournois joués — moyenne points/tournoi : 25 à 50 pts.",
        "Joueuse avancée : top 900 française (jusqu'à 450€). Joueur avancé : top 6.000 française (jusqu'à 3.000€). P100 : à ce titre, tournoi (semi)régulier, 70 % de victoires. P250 : classement en milieu de tableau, 50 % de victoires. P500 : à ce titre, 50 % de victoires et classement en fin de tableau. + de 12 tournois joués — moyenne points/tournoi : 50 pts et +.",
        "Joueuse avancée : top 450 française (jusqu'à 1.500€). Joueur avancé : top 3.000 française (jusqu'à 3.000€). P250 : à ce titre, tournoi en fin de tableau de série. P500 : matchs gagnés, classement en fin de tableau. + de 12 tournois joués — moyenne points/tournoi : 100 pts et +.",
        "Joueuses et joueurs de P1000, P1500 et P2000.",
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

    private var names: [String] { PadelLevel.names(scale) }

    var body: some View {
        NavigationStack {
            Screen(title: "Ton niveau", eyebrow: "Pour des matchs équilibrés", seasonal: false) {
                VStack(alignment: .leading, spacing: 22) {
                    UnderlineTabs(items: ["Échelle FFT · 1 à 8", "Échelle 1 à 10"], selection: Binding(
                        get: { scale == "old" ? 1 : 0 },
                        set: { scale = $0 == 1 ? "old" : "new"; level = min(level, PadelLevel.names(scale).count) }))
                    gauge
                }
                Block(title: "Ton jeu") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Main")
                            InlinePicker(options: [(true, "Droitier"), (false, "Gaucher")], selection: $rightHanded)
                        }
                        InputField(title: "Ville, pour les matchs près de chez toi", text: $city, systemImage: "mappin")
                    }
                }
                if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                Button { Task { await save() } } label: {
                    if busy { ProgressView().tint(UI.onCourt) } else { Text("Enregistrer mon niveau") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Plus tard") { dismiss() } } }
        }
        .tint(UI.court)
        .onAppear {
            if let p = server.me?.profile {
                scale = p.evaluationType ?? "new"
                level = p.skillLevel ?? 3
                rightHanded = p.rightHanded ?? true
                city = p.location ?? ""
            }
        }
    }

    /// Le niveau en très grand, puis une échelle de barres à toucher (comme un indicateur de réseau).
    private var gauge: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text("\(level)").font(UI.scoreHeavy(112)).foregroundStyle(UI.ink).contentTransition(.numericText()).frame(minWidth: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PadelLevel.name(level, scale: scale)).font(UI.title(24)).foregroundStyle(UI.ink)
                    Text("sur \(names.count)").font(UI.score(16)).foregroundStyle(UI.muted)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(1...names.count, id: \.self) { i in
                    Button { withAnimation(.snappy(duration: 0.25)) { level = i } } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(i == level ? UI.ball : (i < level ? UI.ink : UI.sunken))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(i == level ? UI.ink.opacity(0.4) : Color.clear, lineWidth: 1))
                                .frame(height: 22 + CGFloat(i) * (names.count > 8 ? 7 : 9))
                            Text("\(i)").font(UI.score(13)).foregroundStyle(i == level ? UI.ink : UI.faint)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Niveau \(i), \(names[i - 1])")
                }
            }
            if scale == "new", level <= PadelLevel.fftHints.count {
                Text(PadelLevel.fftHints[level - 1]).font(UI.body()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if !PadelLevel.fftCriteria[level - 1].isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Repères en compétition")
                        Text(PadelLevel.fftCriteria[level - 1]).font(UI.caption()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
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
        HStack(spacing: 14) {
            Avatar(name: person.name, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                HStack(spacing: 6) {
                    if let lvl = person.skillLevel {
                        LevelBars(level: lvl, count: person.evaluationType == "old" ? 10 : 8, height: 11, barWidth: 2.5)
                    }
                    let detail = [person.levelLabel, person.city ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty { Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1) }
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 12)
    }
}

struct FriendsView: View {
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss
    @State private var playerRef: PlayerRef? = nil
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
            Screen(title: "Amis", eyebrow: friends.isEmpty ? "Tes partenaires de jeu" : "\(friends.count) partenaire\(friends.count > 1 ? "s" : "")", seasonal: false) {
                VStack(alignment: .leading, spacing: 18) {
                    UnderlineTabs(items: ["Mes amis", requests.received.isEmpty ? "Demandes" : "Demandes · \(requests.received.count)", "Ajouter"], selection: $tab)
                    if let error { Text(error).font(UI.callout()).foregroundStyle(UI.danger) }
                    switch tab {
                    case 0: friendsList
                    case 1: requestsList
                    default: addList
                    }
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
            .sheet(item: $playerRef) { ref in PlayerProfileView(userID: ref.id) }
        }
        .tint(UI.court)
        .task { await load() }
    }

    @ViewBuilder private var friendsList: some View {
        if friends.isEmpty {
            EmptyNote(title: "Pas encore d'amis.", message: "Retrouve tes partenaires par leur nom ou leur pseudo.", actionTitle: "Ajouter des amis") { tab = 2 }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(friends.enumerated()), id: \.element.id) { i, f in
                    if let p = f.friend {
                        PersonRow(person: p) {
                            Menu {
                                Button("Retirer de mes amis", role: .destructive) { Task { try? await server.removeFriend(p.id); await load() } }
                            } label: { Image(systemName: "ellipsis").foregroundStyle(UI.muted).frame(width: 32, height: 32) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { playerRef = PlayerRef(id: p.id) }
                        if i < friends.count - 1 { Hairline(inset: 56) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var requestsList: some View {
        if requests.received.isEmpty && requests.sent.isEmpty {
            EmptyNote(title: "Aucune demande.", message: "Les demandes d'amis reçues apparaissent ici.")
        } else {
            if !requests.received.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Reçues")
                    ForEach(requests.received) { r in
                        if let p = r.senderInfo {
                            PersonRow(person: p) {
                                HStack(spacing: 8) {
                                    Button { Task { try? await server.answerFriendRequest(r.id, accept: false); await load() } } label: {
                                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
                                            .overlay(Circle().strokeBorder(UI.rule, lineWidth: 1))
                                    }
                                    .foregroundStyle(UI.muted)
                                    .accessibilityLabel("Refuser")
                                    Button { Task { try? await server.answerFriendRequest(r.id, accept: true); await load() } } label: {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                                            .background(Circle().fill(UI.court))
                                    }
                                    .foregroundStyle(UI.onCourt)
                                    .accessibilityLabel("Accepter")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if !requests.sent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Envoyées").padding(.top, 8)
                    ForEach(requests.sent) { r in
                        if let p = r.receiverInfo {
                            PersonRow(person: p) { Text("En attente").font(UI.small()).foregroundStyle(UI.muted) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var addList: some View {
        InputField(title: "Nom ou pseudo d'un joueur", text: $query, systemImage: "magnifyingglass")
            .onSubmit { Task { await search() } }
            .onChange(of: query) { _, text in
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if text == query { await search() }
                }
            }
        let list = query.count >= 2 ? results : suggestions
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: query.count >= 2 ? "Résultats" : "Ils jouent à ton niveau")
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    PersonRow(person: p) {
                        if p.isFriend == true {
                            Stamp(text: "Ami", style: .outline)
                        } else if p.hasPendingRequest == true || sentTo.contains(p.id) {
                            Text("Demande envoyée").font(UI.small()).foregroundStyle(UI.muted)
                        } else {
                            Button {
                                Task {
                                    do { try await server.sendFriendRequest(to: p.id); sentTo.insert(p.id) } catch { self.error = error.localizedDescription }
                                }
                            } label: { Text("Ajouter") }
                            .buttonStyle(LinkButtonStyle())
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { playerRef = PlayerRef(id: p.id) }
                    if i < list.count - 1 { Hairline(inset: 56) }
                }
            }
        } else if query.count >= 2 {
            EmptyNote(title: "Personne sous ce nom.", message: "Essaie le pseudo PadelUp de ton partenaire.")
        }
    }

    private func load() async {
        if ShotMode.current != nil {
            friends = ShotMode.demoFriends()
            suggestions = ShotMode.demoFriends().compactMap { $0.friend }
            return
        }
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

// MARK: - Fiche match : le terrain, les joueurs, le résultat, les notes, la discussion

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
    @State private var editing = false
    @State private var inviting = false
    @State private var confirmCancel = false
    @State private var playerRef: PlayerRef? = nil

    private var players: [APIParticipant] { (match.participants ?? []).filter { $0.status == nil || $0.status == "confirmed" } }
    private var isMember: Bool { flags.isOrganizer == true || flags.isParticipant == true || ShotMode.current != nil }
    private var started: Bool { (match.date ?? .distantFuture) < Date() }
    private var completed: Bool { match.status == "completed" }
    private var myID: Int? { server.me?.id }

    var body: some View {
        NavigationStack {
            Screen(title: match.title ?? "Match de padel",
                   eyebrow: [match.typeLabel, match.clubName].compactMap { $0 }.joined(separator: " · "), seasonal: false) {
                scoreboard
                Block(title: "Sur le terrain", meta: "\(players.count)/\(match.maxPlayers ?? 4)") {
                    VStack(spacing: 0) {
                        CourtDiagram(players: players.map { $0.userName ?? "Joueur" }, capacity: match.maxPlayers ?? 4, organizer: match.organizerName)
                            .padding(.bottom, 8)
                        ForEach(players) { p in
                            HStack(spacing: 12) {
                                Button { if let uid = p.user { playerRef = PlayerRef(id: uid) } } label: {
                                    HStack(spacing: 12) {
                                        Avatar(name: p.userName ?? "Joueur", size: 32)
                                        Text(p.userName ?? "Joueur").font(UI.headline()).foregroundStyle(UI.ink)
                                        if p.user == match.organizer { Stamp(text: "Organise", style: .outline) }
                                        Spacer()
                                        if let lvl = p.userSkillLevel { LevelBars(level: lvl, height: 11, barWidth: 2.5) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if flags.isOrganizer == true && p.user != match.organizer && !started {
                                    Menu {
                                        Button("Retirer du match", role: .destructive) {
                                            Task {
                                                do { try await server.removeParticipant(match: match.id, participant: p.id); await load() }
                                                catch { info = error.localizedDescription }
                                            }
                                        }
                                    } label: { Image(systemName: "ellipsis").foregroundStyle(UI.muted).frame(width: 30, height: 30) }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                if !isMember && match.spotsLeft > 0 && !started { joinButton }
                if isMember && started && flags.isOrganizer == true && !completedWithResult { resultBlock }
                if isMember && completed { ratingBlock }
                if isMember { chatBlock }
                if isMember && !started && flags.isOrganizer != true && ShotMode.current == nil {
                    Button("Quitter le match") { Task { try? await server.leave(matchID: match.id); await load() } }
                        .buttonStyle(LinkButtonStyle(color: UI.danger))
                }
                if let info { Text(info).font(UI.callout()).foregroundStyle(UI.success) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if flags.isOrganizer == true && !completed {
                        Menu {
                            if !started {
                                Button { editing = true } label: { Label("Modifier le match", systemImage: "pencil") }
                                Button { inviting = true } label: { Label("Inviter des amis", systemImage: "person.badge.plus") }
                            }
                            Button(role: .destructive) { confirmCancel = true } label: { Label("Annuler le match", systemImage: "xmark.circle") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .sheet(isPresented: $editing) { EditMatchView(match: match) { Task { await load() } } }
            .sheet(isPresented: $inviting) { InviteFriendsView(match: match) }
            .sheet(item: $playerRef) { ref in PlayerProfileView(userID: ref.id) }
            .confirmationDialog("Annuler ce match ?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Annuler le match", role: .destructive) {
                    Task {
                        do { try await server.cancelMatch(match.id); info = "Match annulé, les joueurs sont prévenus."; await load() }
                        catch { info = error.localizedDescription }
                    }
                }
                Button("Garder le match", role: .cancel) {}
            } message: { Text("Les joueurs inscrits reçoivent une notification.") }
        }
        .tint(UI.court)
        .task { await load() }
    }

    private var completedWithResult: Bool { completed && info == "Résultat enregistré." }

    /// Le tableau de score du match : jour, heure, durée, niveau.
    private var scoreboard: some View {
        StatsRow(items: [
            (match.date.map { FR.string($0, "d MMM").replacingOccurrences(of: ".", with: "") } ?? "–", match.date.map { FR.string($0, "EEEE") } ?? "date"),
            (match.date.map { FR.time($0) } ?? "–", "\(match.duration ?? 90) min"),
            ("\(match.minSkillLevel ?? 1)–\(match.maxSkillLevel ?? 8)", "niveau"),
        ])
    }

    private var joinLabel: String {
        var label = "Rejoindre · \(match.spotsLeft) place" + (match.spotsLeft > 1 ? "s" : "")
        if let raw = match.pricePerPlayer, let price = Double(raw), price > 0 { label += " · \(Int(price)) €" }
        return label
    }

    private var joinButton: some View {
        Button {
            Task {
                busy = true
                defer { busy = false }
                do { try await server.join(matchID: match.id); info = "C'est noté, tu joues."; await load() }
                catch { info = error.localizedDescription }
            }
        } label: {
            if busy { ProgressView().tint(UI.onCourt) } else {
                Text(joinLabel)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var resultBlock: some View {
        Block(title: "Résultat") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Touche les vainqueurs : les autres sont comptés perdants.").font(UI.callout()).foregroundStyle(UI.muted)
                FlowRow(players.compactMap { p in p.user.map { ($0, p.userName ?? "Joueur") } }) { id, name in
                    Button {
                        if winners.contains(id) { winners.remove(id) } else { winners.insert(id) }
                    } label: { Chip(text: name, systemImage: winners.contains(id) ? "trophy.fill" : nil, active: winners.contains(id)) }
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
                .opacity(winners.isEmpty ? 0.4 : 1)
            }
        }
    }

    private var ratingBlock: some View {
        Block(title: "Notes") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ta note de 1 à 10 affine le niveau public de chacun. Elle reste anonyme.").font(UI.callout()).foregroundStyle(UI.muted)
                ForEach(players.filter { $0.user != nil && $0.user != myID }) { p in
                    let uid = p.user ?? 0
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Avatar(name: p.userName ?? "Joueur", size: 30)
                            Text(p.userName ?? "Joueur").font(UI.headline()).foregroundStyle(UI.ink)
                            Spacer()
                            if rated.contains(uid) {
                                Stamp(text: "Noté")
                            } else {
                                Text("\(ratings[uid] ?? 6)").font(UI.score(24)).foregroundStyle(UI.ink) + Text("/10").font(UI.score(14)).foregroundStyle(UI.muted)
                            }
                        }
                        if !rated.contains(uid) {
                            HStack(spacing: 4) {
                                ForEach(1...10, id: \.self) { n in
                                    Button { ratings[uid] = n } label: {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(n <= (ratings[uid] ?? 6) ? UI.ink : UI.sunken)
                                            .frame(height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(n) sur 10")
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
                }
                if let court = match.court {
                    Hairline()
                    HStack {
                        Text("Le terrain").font(UI.headline()).foregroundStyle(UI.ink)
                        Spacer()
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                courtStars = n
                                Task { try? await server.rateCourt(match: match.id, court: court, rating: n) }
                            } label: {
                                Image(systemName: n <= courtStars ? "star.fill" : "star").foregroundStyle(n <= courtStars ? UI.ink : UI.faint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var chatBlock: some View {
        Block(title: "Discussion") {
            VStack(alignment: .leading, spacing: 10) {
                if messages.isEmpty {
                    Text("Pas encore de message. Qui apporte les balles ?").font(UI.callout()).foregroundStyle(UI.muted)
                }
                ForEach(messages.suffix(30)) { m in
                    let mine = m.sender != nil && m.sender == myID
                    HStack(alignment: .bottom, spacing: 8) {
                        if mine { Spacer(minLength: 48) } else { Avatar(name: m.senderName ?? "Joueur", size: 26) }
                        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                            if !mine { Text(m.senderName ?? "Joueur").font(UI.small()).foregroundStyle(UI.muted) }
                            Text(m.content).font(UI.callout()).foregroundStyle(mine ? UI.paper : UI.ink)
                                .padding(.vertical, 9).padding(.horizontal, 13)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(mine ? UI.ink : UI.raised))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(mine ? Color.clear : UI.rule, lineWidth: 1))
                        }
                        if !mine { Spacer(minLength: 48) }
                    }
                }
                HStack(spacing: 8) {
                    InputField(title: "Message", text: $draft)
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        draft = ""
                        Task { try? await server.sendChat(match.id, text: text); messages = (try? await server.chat(match.id)) ?? messages }
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(UI.onCourt)
                            .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.court))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Envoyer")
                }
                .padding(.top, 4)
            }
        }
    }

    private func load() async {
        if ShotMode.current != nil {
            messages = ShotMode.demoMessages()
            return
        }
        guard server.isLoggedIn else { return }
        if let detail = try? await server.matchDetail(match.id) {
            match = detail.0
            flags = detail.1
        }
        if isMember { messages = (try? await server.chat(match.id)) ?? [] }
    }
}

/// Le terrain vu de haut : filet au milieu, deux joueurs par camp, places libres en pointillés.
struct CourtDiagram: View {
    var players: [String]
    var capacity: Int
    var organizer: String?

    private var spots: [String?] {
        var s: [String?] = players.map { Optional($0) }
        while s.count < max(capacity, 2) { s.append(nil) }
        return Array(s.prefix(4))
    }

    var body: some View {
        let half = max(1, spots.count / 2)
        HStack(spacing: 0) {
            side(Array(spots.prefix(half)))
            Rectangle().fill(UI.paper.opacity(0.9)).frame(width: 3)
            side(Array(spots.dropFirst(half)))
        }
        .frame(height: 178)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.court)
                // Lignes de service
                GeometryReader { g in
                    Path { p in
                        let w = g.size.width, h = g.size.height
                        for x in [w * 0.2, w * 0.8] { p.move(to: CGPoint(x: x, y: 10)); p.addLine(to: CGPoint(x: x, y: h - 10)) }
                        p.move(to: CGPoint(x: w * 0.2, y: h / 2)); p.addLine(to: CGPoint(x: w * 0.8, y: h / 2))
                    }
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                }
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5).padding(6)
            }
        )
    }

    private func side(_ list: [String?]) -> some View {
        VStack(spacing: 0) {
            ForEach(list.indices, id: \.self) { i in
                VStack(spacing: 6) {
                    if let name = list[i] {
                        Avatar(name: name, size: 40).overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Text(name.split(separator: " ").first.map(String.init) ?? name)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if name == organizer {
                            Text("organise").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7)).padding(.top, -4)
                        }
                    } else {
                        Circle().strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).frame(width: 40, height: 40)
                        Text("Libre").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
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
            Screen(title: "Notifications", seasonal: false) {
                if loaded && items.isEmpty {
                    EmptyNote(title: "Rien de neuf.", message: "Invitations, matchs, amis et réservations automatiques apparaissent ici.")
                }
                if !items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                            HStack(alignment: .top, spacing: 14) {
                                Circle().fill(n.isRead == false ? UI.clay : Color.clear).frame(width: 8, height: 8).padding(.top, 7)
                                Image(systemName: icon(n.type)).font(.system(size: 16)).foregroundStyle(UI.ink).frame(width: 22).padding(.top, 1)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.message).font(UI.body()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                                    if let d = n.date { Text(FR.relative(d)).font(UI.small()).foregroundStyle(UI.faint) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 14)
                            if i < items.count - 1 { Hairline(inset: 44) }
                        }
                    }
                }
            }
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.court)
        .task { await load() }
    }

    private func icon(_ type: String?) -> String {
        switch type ?? "" {
        case let t where t.hasPrefix("friend"): return "person.badge.plus"
        case let t where t.hasPrefix("bot"): return "scope"
        case let t where t.hasPrefix("booking") || t == "new_booking": return "calendar"
        default: return "figure.tennis"
        }
    }

    private func load() async {
        guard server.isLoggedIn else { loaded = true; return }
        items = (try? await server.notifications()) ?? items
        loaded = true
        await server.markNotificationsRead()
    }
}
