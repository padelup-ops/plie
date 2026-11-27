import CoreLocation
import SwiftUI

struct BotView: View {
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @State private var showConnect = false
    @State private var showEditor = false
    @State private var safariURL: URL? = nil
    @State private var playtomicConnected = PlaytomicAPI.shared.isConnected

    var body: some View {
        Screen(title: "Bot", subtitle: "Choisis ton créneau idéal : le bot surveille et réserve à ta place.") {
            accounts
            Button { showEditor = true } label: { Label("Nouveau bot", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
            rulesSection
            journal
        }
        .refreshable { await bot.runAll() }
        .sheet(isPresented: $showConnect, onDismiss: { playtomicConnected = PlaytomicAPI.shared.isConnected }) { ConnectPlaytomicView() }
        .sheet(isPresented: $showEditor) { RuleEditorView(prefill: nil) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Comptes")
            VStack(spacing: 0) {
                accountRow(name: "Playtomic", detail: playtomicConnected ? (PlaytomicAPI.shared.connectedEmail ?? "Connecté") : "Réservation automatique",
                           connected: playtomicConnected) {
                    if playtomicConnected {
                        Task { await PlaytomicAPI.shared.disconnect(); playtomicConnected = false }
                    } else { showConnect = true }
                }
                Divider().overlay(UI.line).padding(.leading, 52)
                accountRow(name: "Anybuddy", detail: "Alerte instantanée, paiement en un geste", connected: false, actionTitle: "Se connecter") {
                    safariURL = URL(string: "https://www.anybuddyapp.com/fr/compte")
                }
            }
            .card(padding: 6)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: server.botServerEnabled ? "checkmark.circle.fill" : "iphone").foregroundStyle(server.botServerEnabled ? UI.success : UI.muted)
                Text(server.botServerEnabled
                     ? "Bot 24 h/24 actif : le serveur PadelUp réserve même iPhone éteint."
                     : "Le bot tourne sur l'iPhone. Connecte ton compte PadelUp (Profil) pour qu'il tourne 24 h/24.")
                    .font(UI.caption()).foregroundStyle(UI.muted)
            }
            .padding(.horizontal, 4)
        }
    }

    private func accountRow(name: String, detail: String, connected: Bool, actionTitle: String? = nil,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: connected ? "checkmark" : "link", color: connected ? UI.success : UI.muted, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(1)
            }
            Spacer()
            Button(actionTitle ?? (connected ? "Déconnecter" : "Connecter"), action: action)
                .buttonStyle(LinkButtonStyle(color: connected ? UI.muted : UI.accent))
        }
        .padding(10)
    }

    @ViewBuilder private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mes bots", trailing: bot.running ? "vérification…" : bot.lastRun.map { "vérifié " + $0.formatted(.relative(presentation: .named)) })
            if bot.rules.isEmpty {
                EmptyStateView(systemImage: "bolt", title: "Aucun bot pour l'instant",
                               message: "Par exemple : mardi et jeudi, entre 19 h et 21 h, 90 minutes, au club le plus proche.")
            } else {
                ForEach(bot.rules) { rule in RuleCard(rule: rule) }
            }
        }
    }

    @ViewBuilder private var journal: some View {
        if !bot.log.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Journal")
                VStack(spacing: 0) {
                    ForEach(Array(bot.log.prefix(12).enumerated()), id: \.element.id) { i, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(color(entry.kind)).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.clubName).font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.ink)
                                if let start = entry.slotStart {
                                    Text(start.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: "fr_FR"))))
                                        .font(UI.caption()).foregroundStyle(UI.ink.opacity(0.8))
                                }
                                Text(entry.message).font(UI.caption()).foregroundStyle(UI.muted)
                                if let s = entry.actionURL, let url = URL(string: s) {
                                    Button("Terminer en un geste") { safariURL = url }.buttonStyle(LinkButtonStyle()).padding(.top, 2)
                                }
                            }
                            Spacer()
                            Text(entry.date.formatted(.relative(presentation: .numeric))).font(UI.small()).foregroundStyle(UI.faint)
                        }
                        .padding(.vertical, 10)
                        if i < min(bot.log.count, 12) - 1 { Divider().overlay(UI.line) }
                    }
                }
                .padding(.horizontal, 14)
                .card(padding: 0)
            }
        }
    }

    private func color(_ k: BotLogEntry.Kind) -> Color {
        switch k {
        case .booked: return UI.success
        case .found, .info: return UI.accent
        case .needsAction: return UI.warning
        case .failed: return UI.danger
        }
    }
}

struct RuleCard: View {
    var rule: BotRule
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.clubName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                    Text(rule.summary).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(UI.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { rule.active }, set: { v in
                    if let i = bot.rules.firstIndex(where: { $0.id == rule.id }) { bot.rules[i].active = v }
                })).labelsHidden().tint(UI.accent)
            }
            HStack(spacing: 6) {
                Tag(text: rule.provider.name, color: UI.muted)
                Tag(text: rule.autoBook && rule.provider != .anybuddy ? "Réserve seul" : "Me prévient", color: UI.accent)
                Tag(text: rule.maxBookings == 0 ? "Chaque semaine" : "\(rule.bookingsMade)/\(rule.maxBookings)", color: UI.muted)
                if rule.serverRuleID != nil { Tag(text: "24 h/24", color: UI.success) }
            }
            Text(rule.lastStatus).font(UI.caption()).foregroundStyle(UI.muted)
            HStack {
                Button { Task { await bot.run(ruleID: rule.id) } } label: { Label("Vérifier", systemImage: "arrow.clockwise") }
                    .buttonStyle(LinkButtonStyle())
                Spacer()
                Button {
                    if let id = rule.serverRuleID { Task { await server.deleteServerRule(id) } }
                    bot.rules.removeAll { $0.id == rule.id }
                } label: { Image(systemName: "trash") }
                    .buttonStyle(LinkButtonStyle(color: UI.danger))
            }
        }
        .card()
        .opacity(rule.active ? 1 : 0.55)
    }
}

struct ConnectPlaytomicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var server: ServerAPI
    @State private var email = ""
    @State private var password = ""
    @State private var alsoServer = true
    @State private var busy = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Screen(title: "Playtomic", subtitle: "Connecte ton compte : le bot voit les disponibilités et réserve pour toi.") {
                VStack(spacing: 10) {
                    InputField(title: "E-mail Playtomic", text: $email, keyboard: .emailAddress)
                    InputField(title: "Mot de passe", text: $password, secure: true)
                }
                if server.isLoggedIn {
                    Toggle(isOn: $alsoServer) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bot 24 h/24 sur le serveur PadelUp").font(.system(size: 15, weight: .semibold))
                            Text("Réserve même quand ton iPhone est éteint.").font(UI.caption()).foregroundStyle(UI.muted)
                        }
                    }
                    .tint(UI.accent)
                    .card()
                }
                if let error { Text(error).font(UI.caption()).foregroundStyle(UI.danger) }
                Button { Task { await connect() } } label: {
                    if busy { ProgressView().tint(UI.onAccent) } else { Text("Connecter mon compte") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || email.isEmpty || password.isEmpty)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ton mot de passe n'est jamais enregistré : seuls les jetons de session sont gardés, dans le trousseau de l'iPhone.", systemImage: "lock")
                    Label("Le bot paie avec ce que le club accepte sans carte (sur place, crédit club). Sinon il te demande de valider.", systemImage: "creditcard")
                    Label("Playtomic n'a pas d'API publique : PadelUp utilise les mêmes appels que leur app, qui peuvent évoluer.", systemImage: "info.circle")
                }
                .font(UI.caption()).foregroundStyle(UI.muted)
                .padding(.horizontal, 4)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await PlaytomicAPI.shared.connect(email: email.trimmingCharacters(in: .whitespaces), password: password)
            if server.isLoggedIn && alsoServer {
                UserDefaults.standard.set(true, forKey: "botServer")
                try? await server.connectBotAccount(provider: .playtomic, email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
            password = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RuleEditorView: View {
    var prefill: BotRule?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var location: LocationManager

    @State private var rule = BotRule(provider: .playtomic, clubID: "", clubName: "")
    @State private var clubQuery = ""
    @State private var clubResults: [Club] = []
    @State private var searching = false
    @State private var limitPrice = false
    @State private var price = 40.0
    @State private var saving = false
    @State private var info: String? = nil

    private let dayNames = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Screen(title: "Nouveau bot", subtitle: "Dis-lui ce que tu veux, il s'occupe du reste.") {
                clubSection
                whenSection
                optionsSection
                if let info { Text(info).font(UI.caption()).foregroundStyle(UI.danger).padding(.horizontal, 4) }
                Button { Task { await save() } } label: {
                    if saving { ProgressView().tint(UI.onAccent) } else {
                        Text(rule.autoBook && rule.provider != .anybuddy ? "Lancer : il réserve pour moi" : "Lancer : il me prévient")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(rule.clubID.isEmpty || rule.weekdays.isEmpty || saving)
                Text(rule.provider.automationNote).font(UI.small()).foregroundStyle(UI.faint).padding(.horizontal, 4)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
        .tint(UI.accent)
        .onAppear { if let prefill { rule = prefill } }
    }

    private var clubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Club").font(UI.headline()).foregroundStyle(UI.ink)
            if !rule.clubID.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "sportscourt")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.clubName).font(.system(size: 16, weight: .semibold)).foregroundStyle(UI.ink)
                        Text("\(rule.provider.name)\(rule.clubCity.isEmpty ? "" : " · " + rule.clubCity)").font(UI.caption()).foregroundStyle(UI.muted)
                    }
                    Spacer()
                    if prefill == nil { Button("Changer") { rule.clubID = "" }.buttonStyle(LinkButtonStyle()) }
                }
            } else {
                Picker("Plateforme", selection: $rule.provider) {
                    Text("Playtomic").tag(BotProvider.playtomic)
                    Text("Anybuddy").tag(BotProvider.anybuddy)
                }.pickerStyle(.segmented)
                InputField(title: rule.provider == .anybuddy ? "Lien de la page Anybuddy du club" : "Ville ou club (vide : autour de moi)", text: $clubQuery)
                Button { Task { await searchClubs() } } label: {
                    if searching { ProgressView() } else { Label("Chercher", systemImage: "magnifyingglass") }
                }
                .buttonStyle(SecondaryButtonStyle())
                ForEach(clubResults) { c in
                    Button {
                        rule.clubID = c.playtomicTenantID ?? c.anybuddySlug ?? c.id
                        rule.clubName = c.displayName
                        rule.clubCity = c.city
                        rule.timezone = c.timezone ?? TimeZone.current.identifier
                    } label: { ClubRow(club: c, distance: c.distance(from: location.location)) }.buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quand").font(UI.headline()).foregroundStyle(UI.ink)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let on = rule.weekdays.contains(d)
                    Button {
                        if on { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) }
                    } label: {
                        Text(dayNames[d]).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(on ? UI.onAccent : UI.ink)
                            .background(Circle().fill(on ? UI.accent : UI.tray))
                    }.buttonStyle(.plain)
                }
            }
            Stepper("Début au plus tôt  \(BotRule.hhmm(rule.timeFrom))", value: $rule.timeFrom, in: 6 * 60...23 * 60, step: 30)
                .font(UI.callout())
            Stepper("Début au plus tard  \(BotRule.hhmm(rule.timeTo))", value: $rule.timeTo, in: 6 * 60...23 * 60 + 30, step: 30)
                .font(UI.callout())
            HStack(spacing: 8) {
                ForEach([60, 90, 120], id: \.self) { d in
                    Button {
                        if rule.durations.contains(d) { if rule.durations.count > 1 { rule.durations.removeAll { $0 == d } } } else { rule.durations.append(d) }
                    } label: { Pill(text: "\(d) min", active: rule.durations.contains(d)) }.buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Réglages").font(UI.headline()).foregroundStyle(UI.ink)
            Toggle("Réserver tout seul (sinon : me prévenir)", isOn: $rule.autoBook).tint(UI.accent).font(UI.callout())
            Picker("Terrain", selection: $rule.court) {
                ForEach(BotRule.Court.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Stepper("Surveiller les \(rule.daysAhead) prochains jours", value: $rule.daysAhead, in: 1...21).font(UI.callout())
            Stepper(rule.maxBookings == 0 ? "Chaque semaine, sans limite" : "S'arrêter après \(rule.maxBookings) réservation(s)",
                    value: $rule.maxBookings, in: 0...10).font(UI.callout())
            Toggle("Prix maximum", isOn: $limitPrice).tint(UI.accent).font(UI.callout())
            if limitPrice {
                Stepper("\(Int(price)) € maximum", value: $price, in: 5...200, step: 5).font(UI.callout())
            }
        }
        .card()
    }

    private func searchClubs() async {
        searching = true
        defer { searching = false }
        info = nil
        if rule.provider == .anybuddy {
            if let slug = AnybuddyAPI.slug(from: clubQuery) {
                clubResults = [Club(id: "ab:" + slug, name: slug.replacingOccurrences(of: "-", with: " ").capitalized, latitude: 0, longitude: 0,
                                    source: .osm, anybuddySlug: slug, timezone: "Europe/Paris")]
            } else { info = "Colle le lien de la page du club sur anybuddyapp.com." }
            return
        }
        var center = location.location?.coordinate
        if !clubQuery.trimmingCharacters(in: .whitespaces).isEmpty, let place = await PlaceSearch.search(clubQuery).first {
            center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        }
        guard let center else { info = "Active la localisation ou tape une ville."; location.request(); return }
        do {
            var found = try await PlaytomicAPI.shared.tenants(near: center, radiusKm: 30)
            let q = clubQuery.lowercased()
            if !q.isEmpty, found.contains(where: { $0.name.lowercased().contains(q) }) { found = found.filter { $0.name.lowercased().contains(q) } }
            clubResults = Array(found.prefix(12))
            if clubResults.isEmpty { info = "Aucun club Playtomic dans cette zone." }
        } catch {
            info = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var r = rule
        r.maxPrice = limitPrice ? price : nil
        r.lastStatus = "Lancé, première vérification…"
        if r.provider == .playtomic && !PlaytomicAPI.shared.isConnected && r.autoBook {
            info = "Connecte d'abord ton compte Playtomic (onglet Bot)."
            return
        }
        if server.botServerEnabled, let id = try? await server.pushRule(r) { r.serverRuleID = id }
        bot.addRule(r)
        dismiss()
    }
}
