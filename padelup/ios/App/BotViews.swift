import CoreLocation
import SwiftUI

struct BotView: View {
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @State private var showEditor = false
    @State private var web: URL? = nil
    @State private var login: BotProvider? = nil
    @State private var accountsVersion = 0

    var body: some View {
        Screen(title: "Bot", eyebrow: "Surveille · prévient · réserve", accessory: {
            RoundIconButton(systemImage: "plus", filled: true) { showEditor = true }.accessibilityLabel("Nouveau bot")
        }) {
            if let snipe = bot.snipe { SnipePanel(snipe: snipe) }
            rulesBlock
            accountsBlock
            journalBlock
        }
        .refreshable { await bot.runAll() }
        .onReceive(NotificationCenter.default.publisher(for: .webAccountChanged)) { _ in accountsVersion += 1 }
        .sheet(isPresented: $showEditor) { RuleEditorView(prefill: nil) }
        .sheet(item: $web) { url in ProviderWebSheet(provider: WebAccount.owns(url), url: url) }
        .sheet(item: $login) { p in ProviderWebSheet(provider: p, url: WebAccount.loginURL(p), title: "Connexion \(p.name)") }
    }

    // MARK: Mes bots

    private var rulesBlock: some View {
        let active = bot.rules.filter { $0.active }.count
        return Block(title: "Mes bots", meta: bot.running ? "vérification…" : bot.lastRun.map { "vérifié " + FR.relative($0) },
                     live: active > 0) {
            if bot.rules.isEmpty {
                EmptyNote(title: "Aucun bot pour l'instant.",
                          message: "Par exemple : mardi et jeudi, entre 19 h et 21 h, 90 minutes, dans ton club. Le bot lit les créneaux en direct et te prévient dès que ça se libère.",
                          actionTitle: "Créer mon premier bot") { showEditor = true }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bot.rules.enumerated()), id: \.element.id) { i, rule in
                        RuleRow(rule: rule)
                        if i < bot.rules.count - 1 { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Comptes

    private var accountsBlock: some View {
        let _ = accountsVersion
        return Block(title: "Comptes") {
            VStack(spacing: 0) {
                accountRow(.playtomic, detail: "Créneaux en direct, réservation en un geste")
                Hairline()
                accountRow(.anybuddy, detail: "Page du club et réservation automatique Anybuddy")
                Text("Tu te connectes sur le site de la plateforme, dans l'app. PadelUp ne voit jamais ton mot de passe : seule la session reste sur cet iPhone.")
                    .font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func accountRow(_ p: BotProvider, detail: String) -> some View {
        let connected = WebAccount.isConnected(p) || (ShotMode.current != nil && p == .playtomic)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(p.name).font(UI.headline()).foregroundStyle(UI.ink)
                    if connected { Stamp(text: "Connecté") }
                }
                Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(2)
            }
            Spacer(minLength: 8)
            if connected {
                Menu {
                    Button("Ouvrir \(p.name)") { web = WebAccount.loginURL(p) }
                    Button("Déconnecter", role: .destructive) { Task { await WebAccount.disconnect(p); accountsVersion += 1 } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink).frame(width: 36, height: 36)
                }
            } else {
                Button("Connecter") { login = p }.buttonStyle(LinkButtonStyle())
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: Journal

    @ViewBuilder private var journalBlock: some View {
        if !bot.log.isEmpty {
            Block(title: "Journal", meta: "\(bot.log.count) événement\(bot.log.count > 1 ? "s" : "")") {
                VStack(spacing: 0) {
                    let items = Array(bot.log.prefix(12))
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                        JournalRow(entry: entry, last: i == items.count - 1) { url in web = url }
                    }
                }
            }
        }
    }
}

/// Une règle : club, quand, plateforme, état en direct.
struct RuleRow: View {
    var rule: BotRule
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.clubName).font(UI.title(19)).foregroundStyle(UI.ink).lineLimit(1)
                    Text(rule.summary.uppercased(with: UI.fr)).font(UI.score(15)).tracking(0.3).foregroundStyle(UI.muted)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { rule.active }, set: { v in
                    if let i = bot.rules.firstIndex(where: { $0.id == rule.id }) { bot.rules[i].active = v }
                }))
                .labelsHidden().tint(UI.court)
            }
            FlowLayout(spacing: 6) {
                Stamp(text: rule.provider.name, style: .outline)
                if let release = rule.releaseLabel { Stamp(text: "Ouverture " + release, style: .ink) }
                if rule.provider == .padelup && rule.autoBook { Stamp(text: "Réserve seul", style: .ink) }
                Stamp(text: rule.maxBookings == 0 ? "Chaque semaine" : "\(rule.bookingsMade)/\(rule.maxBookings)", style: .outline)
                if rule.serverRuleID != nil { Stamp(text: "24 h/24", style: .outline) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if rule.active && !rule.isPaused { LiveDot(size: 6).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 } }
                Text(rule.lastStatus).font(UI.callout()).foregroundStyle(rule.isPaused ? UI.clay : UI.ink).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 18) {
                Button { Task { await bot.run(ruleID: rule.id) } } label: { Label("Vérifier", systemImage: "arrow.clockwise") }
                    .buttonStyle(LinkButtonStyle())
                if let next = rule.upcomingReleases(limit: 1).first {
                    Text("ouverture " + FR.string(next.release, "EEE d MMM HH:mm", tz: rule.tz))
                        .font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Supprimer ce bot", role: .destructive) {
                        if let id = rule.serverRuleID { Task { await server.deleteServerRule(id) } }
                        bot.rules.removeAll { $0.id == rule.id }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.muted).frame(width: 32, height: 28)
                }
            }
        }
        .padding(.vertical, 16)
        .opacity(rule.active ? 1 : 0.5)
    }
}

/// Ligne du journal, sur une frise : point coloré selon l'issue.
struct JournalRow: View {
    var entry: BotLogEntry
    var last: Bool
    var open: (URL) -> Void

    private var color: Color {
        switch entry.kind {
        case .booked: return UI.ball
        case .found: return UI.court
        case .needsAction: return UI.clay
        case .failed: return UI.danger
        case .info: return UI.faint
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(UI.ink.opacity(entry.kind == .booked ? 0.4 : 0), lineWidth: 0.75))
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.clubName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(FR.relative(entry.date)).font(UI.small()).foregroundStyle(UI.faint)
                }
                if let start = entry.slotStart {
                    Text(FR.string(start, "EEE d MMM · HH:mm").uppercased(with: UI.fr) + (entry.court.isEmpty ? "" : " · " + entry.court.uppercased(with: UI.fr)))
                        .font(UI.score(14)).foregroundStyle(UI.ink)
                }
                Text(entry.message).font(UI.caption()).foregroundStyle(UI.muted)
                if let s = entry.actionURL, let url = URL(string: s), (entry.slotStart ?? .distantFuture) > Date() {
                    Button { open(url) } label: { Label("Réserver maintenant", systemImage: "arrow.right") }
                        .buttonStyle(LinkButtonStyle()).padding(.top, 4)
                }
            }
            .padding(.bottom, last ? 0 : 18)
        }
        // La frise : un filet vertical qui relie les points (dessiné en fond, à la hauteur de la ligne).
        .background(alignment: .topLeading) {
            if !last {
                Rectangle().fill(UI.rule).frame(width: 1).frame(maxHeight: .infinity).padding(.top, 17).offset(x: 4.5)
            }
        }
    }
}

/// Ouverture des réservations en direct : compte à rebours, scan, résultat. Un tableau de score, à l'encre.
struct SnipePanel: View {
    var snipe: Snipe
    @EnvironmentObject private var bot: BotEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "Ouverture · " + snipe.clubName, color: UI.paper.opacity(0.7))
                Spacer()
                Button { bot.cancelSnipe() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .foregroundStyle(UI.paper.opacity(0.7))
            }
            switch snipe.phase {
            case .countdown:
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = max(0, snipe.release.timeIntervalSince(context.date))
                    Text(String(format: "%02d:%02d.%d", Int(left) / 60, Int(left) % 60, Int((left * 10).truncatingRemainder(dividingBy: 10))))
                        .font(UI.scoreHeavy(72)).foregroundStyle(UI.paper)
                        .contentTransition(.numericText(countsDown: true))
                }
                Text("Créneaux du \(FR.longDay(snipe.day, tz: TimeZone(identifier: snipe.timezone) ?? .current)). Garde l'app ouverte : le bot lit les créneaux à l'heure pile.")
                    .font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .scanning(let n):
                HStack(spacing: 10) {
                    LiveDot(size: 10)
                    Text("Lecture \(n)").font(UI.scoreHeavy(56)).foregroundStyle(UI.paper)
                }
                Text("Une lecture par seconde, puis toutes les 3 s pendant 45 s. Le bot s'arrête si Playtomic refuse.")
                    .font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .found(let what):
                Stamp(text: "Trouvé")
                Text(what).font(UI.title(22)).foregroundStyle(UI.paper)
                Text("La page de réservation s'est ouverte, déjà connectée.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .missed:
                Text("Rien n'est apparu.").font(UI.title(22)).foregroundStyle(UI.paper)
                Text("Le club n'a pas encore publié ce créneau. Le bot continue de surveiller.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            case .blocked:
                Text("Arrêté.").font(UI.title(22)).foregroundStyle(UI.paper)
                Text("Playtomic a limité les requêtes : le bot s'est arrêté, comme prévu.").font(UI.callout()).foregroundStyle(UI.paper.opacity(0.75))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(UI.ink))
    }
}

// MARK: - Créer un bot

struct RuleEditorView: View {
    var prefill: BotRule?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var location: LocationManager

    @State private var rule = BotRule(provider: .playtomic, clubID: "", clubName: "")
    @State private var clubQuery = ""
    @State private var results: [PlaytomicClub] = []
    @State private var searching = false
    @State private var limitPrice = false
    @State private var price = 40.0
    @State private var useRelease = false
    @State private var releaseDays = 7
    @State private var releaseMinutes = 8 * 60
    @State private var saving = false
    @State private var info: String? = nil
    @State private var web: URL? = nil
    @State private var pickOnSite = false
    @State private var link = ""

    private let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Screen(title: "Nouveau bot", eyebrow: prefill?.clubName, seasonal: false) {
                clubBlock
                if rule.provider == .anybuddy {
                    anybuddyBlock
                } else {
                    whenBlock
                    if rule.provider == .playtomic { releaseBlock }
                    optionsBlock
                    if let info { Text(info).font(UI.callout()).foregroundStyle(UI.danger) }
                    VStack(alignment: .leading, spacing: 12) {
                        Button { Task { await save() } } label: {
                            if saving { ProgressView().tint(UI.onCourt) } else { Text("Lancer le bot") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(rule.clubID.isEmpty || rule.weekdays.isEmpty || saving)
                        .opacity(rule.clubID.isEmpty || rule.weekdays.isEmpty ? 0.4 : 1)
                        Text(rule.provider.automationNote).font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
            .sheet(item: $web) { url in ProviderWebSheet(provider: WebAccount.owns(url), url: url) }
            .sheet(isPresented: $pickOnSite) { PlaytomicPickerSheet(query: clubQuery) { c in pick(c) } }
        }
        .tint(UI.court)
        .onAppear {
            if let prefill {
                rule = prefill
                if let d = prefill.releaseDays, let m = prefill.releaseMinutes { useRelease = true; releaseDays = d; releaseMinutes = m }
            }
        }
    }

    // MARK: Club

    private var clubBlock: some View {
        Block(title: "Club") {
            VStack(alignment: .leading, spacing: 14) {
                if !rule.clubID.isEmpty {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.clubName).font(UI.headline()).foregroundStyle(UI.ink)
                            Text([rule.provider.name, rule.clubCity].filter { !$0.isEmpty }.joined(separator: " · ")).font(UI.caption()).foregroundStyle(UI.muted)
                        }
                        Spacer()
                        if prefill == nil { Button("Changer") { rule.clubID = "" }.buttonStyle(LinkButtonStyle()) }
                    }
                } else {
                    InlinePicker(options: [(BotProvider.playtomic, "Playtomic"), (BotProvider.anybuddy, "Anybuddy")], selection: $rule.provider)
                    if rule.provider == .playtomic {
                        HStack(spacing: 10) {
                            InputField(title: "Nom du club ou ville", text: $clubQuery, systemImage: "magnifyingglass")
                                .onSubmit { Task { await searchClubs() } }
                            Button { Task { await searchClubs() } } label: {
                                if searching { ProgressView() } else { Text("Chercher") }
                            }
                            .buttonStyle(LinkButtonStyle())
                        }
                        if let info, results.isEmpty { Text(info).font(UI.callout()).foregroundStyle(UI.muted) }
                        Button { pickOnSite = true } label: { Label("Choisir sur le site Playtomic", systemImage: "safari") }
                            .buttonStyle(SecondaryButtonStyle())
                        HStack(spacing: 10) {
                            InputField(title: "…ou colle le lien Playtomic du club", text: $link, keyboard: .URL, systemImage: "link")
                            Button("Ajouter") { Task { await useLink() } }.buttonStyle(LinkButtonStyle())
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(results.prefix(10).enumerated()), id: \.element.key) { i, c in
                                Button { pick(c) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                                            Text([c.street, c.postalCode, c.countryCode].filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle").foregroundStyle(UI.court)
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if i < min(results.count, 10) - 1 { Hairline() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func pick(_ c: PlaytomicClub) {
        guard !c.id.isEmpty else {
            // Club lu à l'écran : son identifiant se trouve sur sa page.
            Task {
                searching = true
                info = "Identification de \(c.name)…"
                defer { searching = false }
                var id = await HiddenPlaytomic.shared.tenantID(slug: c.slug)
                if id == nil { id = await PlaytomicWeb.resolve(link: "https://playtomic.com/clubs/\(c.slug)")?.id }
                if let id {
                    info = nil
                    pick(PlaytomicClub(id: id, name: c.name, slug: c.slug, countryCode: c.countryCode, street: c.street, postalCode: c.postalCode))
                } else {
                    info = "Impossible d'identifier ce club. Choisis-le sur le site Playtomic (bouton ci-dessous)."
                }
            }
            return
        }
        rule.clubID = c.id
        rule.clubName = c.name
        rule.clubSlug = c.slug
        rule.clubCity = c.postalCode
        rule.timezone = Self.timezone(country: c.countryCode)
        results = []
    }

    static func timezone(country: String) -> String {
        switch country.uppercased() {
        case "MA": return "Africa/Casablanca"
        case "DZ": return "Africa/Algiers"
        case "TN": return "Africa/Tunis"
        case "ES": return "Europe/Madrid"
        case "IT": return "Europe/Rome"
        case "DE": return "Europe/Berlin"
        case "BE": return "Europe/Brussels"
        case "CH": return "Europe/Zurich"
        case "LU": return "Europe/Luxembourg"
        case "MC": return "Europe/Monaco"
        case "AD": return "Europe/Andorra"
        default: return "Europe/Paris"
        }
    }

    private func useLink() async {
        searching = true
        defer { searching = false }
        if let c = await PlaytomicWeb.resolve(link: link) {
            pick(c)
            link = ""
        } else {
            info = "Lien non reconnu. Dans l'app Playtomic, ouvre le club puis « Partager », et colle le lien ici."
        }
    }

    private func searchClubs() async {
        searching = true
        defer { searching = false }
        info = nil
        var q = clubQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty, let loc = location.location, let city = try? await CLGeocoder().reverseGeocodeLocation(loc).first?.locality { q = city }
        guard q.count >= 2 else { info = "Tape le nom du club ou une ville."; return }
        results = (try? await PlaytomicWeb.search(q)) ?? []
        if results.isEmpty {
            // Le site affiche ses résultats avec JavaScript : on les lit dans un navigateur invisible, comme Safari.
            info = "Recherche sur le site Playtomic…"
            results = PlaytomicWeb.rank(await HiddenPlaytomic.shared.search(q + " france"), query: q)
            if results.isEmpty { results = PlaytomicWeb.rank(await HiddenPlaytomic.shared.search(q), query: q) }
        }
        info = results.isEmpty ? "Rien trouvé pour « \(q) » : essaie le nom exact du club, ou choisis-le sur le site Playtomic." : nil
    }

    // MARK: Anybuddy

    private var anybuddyBlock: some View {
        Block(title: "Sur Anybuddy") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Anybuddy protège ses créneaux contre les robots, et propose sa propre réservation automatique. On l'ouvre ici, déjà connecté à ton compte : choisis ton club, tes jours et tes heures, Anybuddy réserve pour toi.")
                    .font(UI.callout()).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                Button { web = AnybuddyAPI.autoBookingURL } label: { Label("Ouvrir la réservation automatique", systemImage: "scope") }
                    .buttonStyle(PrimaryButtonStyle())
                if !rule.clubID.isEmpty, let url = AnybuddyAPI.clubURL(rule.clubID) {
                    Button { web = url } label: { Text("Voir les créneaux de \(rule.clubName)") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: Quand

    private var whenBlock: some View {
        Block(title: "Quand") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { d in
                        let on = rule.weekdays.contains(d)
                        Button {
                            if on { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) }
                        } label: {
                            Text(dayLetters[d]).font(.system(size: 15, weight: .semibold).width(.expanded))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(on ? UI.paper : UI.ink)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? UI.ink : UI.raised))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.clear : UI.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(BotRule.dayNames[d])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                HStack(spacing: 0) {
                    TimeField(label: "Début dès", minutes: $rule.timeFrom, range: 6 * 60...23 * 60)
                    Rectangle().fill(UI.rule).frame(width: 0.5, height: 90).padding(.horizontal, 14)
                    TimeField(label: "au plus tard", minutes: $rule.timeTo, range: rule.timeFrom...(23 * 60 + 30))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Durée")
                    HStack(spacing: 8) {
                        ForEach([60, 90, 120], id: \.self) { d in
                            Button {
                                if rule.durations.contains(d) { if rule.durations.count > 1 { rule.durations.removeAll { $0 == d } } } else { rule.durations.append(d) }
                            } label: { Chip(text: "\(d) min", active: rule.durations.contains(d)) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Ouverture des réservations

    private var releaseBlock: some View {
        Block(title: "Ouverture") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $useRelease.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Le club ouvre ses créneaux à l'avance").font(UI.body()).foregroundStyle(UI.ink)
                        Text("Le bot te prévient une minute avant et lit les créneaux à l'heure pile.").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                }
                .tint(UI.court)
                if useRelease {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: "Jours avant")
                            Text("J-\(releaseDays)").font(UI.score(34)).foregroundStyle(UI.ink).lineLimit(1).fixedSize()
                            Stepper("", value: $releaseDays, in: 1...30).labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(UI.rule).frame(width: 0.5, height: 90).padding(.horizontal, 14)
                        TimeField(label: "à", minutes: $releaseMinutes, range: 0...(23 * 60 + 45), step: 15)
                    }
                }
            }
        }
    }

    // MARK: Réglages

    private var optionsBlock: some View {
        Block(title: "Réglages") {
            VStack(alignment: .leading, spacing: 16) {
                if rule.provider == .padelup {
                    Toggle("Réserver tout seul (sinon : me prévenir)", isOn: $rule.autoBook).tint(UI.court).font(UI.body())
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Terrain")
                    InlinePicker(options: BotRule.Court.allCases.map { ($0, $0.label) }, selection: $rule.court)
                }
                Stepper(value: $rule.daysAhead, in: 1...21) {
                    Text("Surveiller les \(rule.daysAhead) prochains jours").font(UI.body())
                }
                Stepper(value: $rule.maxBookings, in: 0...10) {
                    Text(rule.maxBookings == 0 ? "Chaque semaine, sans limite" : "S'arrêter après \(rule.maxBookings) réservation\(rule.maxBookings > 1 ? "s" : "")").font(UI.body())
                }
                Toggle("Prix maximum", isOn: $limitPrice.animation(.snappy)).tint(UI.court).font(UI.body())
                if limitPrice {
                    Stepper(value: $price, in: 5...200, step: 5) {
                        Text("\(Int(price)) € maximum").font(UI.score(20))
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var r = rule
        r.maxPrice = limitPrice ? price : nil
        r.releaseDays = useRelease ? releaseDays : nil
        r.releaseMinutes = useRelease ? releaseMinutes : nil
        r.lastStatus = "Lancé, première lecture…"
        // Le serveur PadelUp ne lit que les clubs partenaires (Playtomic refuse les serveurs) : le reste tourne sur l'iPhone.
        if r.provider == .padelup, server.botServerEnabled, let id = try? await server.pushRule(r) { r.serverRuleID = id }
        bot.addRule(r)
        dismiss()
    }
}

/// Heure réglable au quart d'heure ou à la demi-heure, affichée en chiffres de tableau de score.
struct TimeField: View {
    var label: String
    @Binding var minutes: Int
    var range: ClosedRange<Int>
    var step = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label)
            Text(BotRule.hhmm(minutes)).font(UI.score(34)).foregroundStyle(UI.ink)
                .lineLimit(1).fixedSize().contentTransition(.numericText())
            Stepper("", value: Binding(get: { minutes }, set: { minutes = min(max($0, range.lowerBound), range.upperBound) }),
                    in: range, step: step).labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
