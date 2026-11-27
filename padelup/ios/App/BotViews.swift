import CoreLocation
import SwiftUI

struct BotView: View {
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI
    @State private var showConnect = false
    @State private var showAnybuddy = false
    @State private var showEditor = false
    @State private var safariURL: URL? = nil
    @State private var playtomicConnected = PlaytomicAPI.shared.isConnected

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(intensity: 0.45)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ScreenHeader(title: "Bot de résa", subtitle: "Connecte ton compte, choisis ton créneau idéal : le bot surveille et réserve à ta place.")
                        accounts
                        Button { showEditor = true } label: { Label("Nouveau bot de réservation", systemImage: "plus.circle.fill") }
                            .buttonStyle(NeonButtonStyle(color: Neo.volt))
                        rulesSection
                        journal
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .refreshable { await bot.runAll() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showConnect, onDismiss: { playtomicConnected = PlaytomicAPI.shared.isConnected }) { ConnectPlaytomicView() }
        .sheet(isPresented: $showEditor) { RuleEditorView(prefill: nil) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Comptes connectés")
            accountRow(name: "Playtomic", detail: playtomicConnected ? (PlaytomicAPI.shared.connectedEmail ?? "Connecté") : "Réservation automatique",
                       connected: playtomicConnected, color: Color(red: 0.2, green: 0.85, blue: 0.6)) {
                if playtomicConnected {
                    Task { await PlaytomicAPI.shared.disconnect(); playtomicConnected = false }
                } else { showConnect = true }
            }
            accountRow(name: "Anybuddy", detail: "Surveillance + paiement en un geste", connected: false, color: Color(red: 1.0, green: 0.45, blue: 0.35),
                       actionTitle: "Se connecter") {
                safariURL = URL(string: "https://www.anybuddyapp.com/fr/compte")
            }
            HStack(spacing: 8) {
                Image(systemName: server.botServerEnabled ? "server.rack" : "iphone")
                    .foregroundStyle(server.botServerEnabled ? Neo.volt : Neo.cyan)
                Text(server.botServerEnabled
                     ? "Bot 24 h/24 actif : le serveur PadelUp réserve même iPhone éteint."
                     : "Le bot tourne sur l'iPhone (app ouverte ou en arrière-plan). Connecte ton compte PadelUp pour le 24 h/24.")
                    .font(Neo.body(12)).foregroundStyle(Neo.dim)
            }
        }
        .glassCard()
    }

    private func accountRow(name: String, detail: String, connected: Bool, color: Color, actionTitle: String? = nil,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10).neonGlow(color, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Neo.label(14)).foregroundStyle(Neo.text)
                Text(detail).font(Neo.body(12)).foregroundStyle(Neo.dim)
            }
            Spacer()
            Button(actionTitle ?? (connected ? "Déconnecter" : "Connecter"), action: action)
                .font(Neo.label(12)).foregroundStyle(connected ? Neo.faint : Neo.volt)
        }
    }

    @ViewBuilder private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Mes bots", trailing: bot.running ? "analyse en cours…" : bot.lastRun.map { "vérifié " + $0.formatted(.relative(presentation: .named)) })
            if bot.rules.isEmpty {
                EmptyStateView(systemImage: "bolt.horizontal.circle", title: "Aucun bot pour l'instant",
                               message: "Exemple : « Mardi et jeudi, entre 19 h et 21 h, 90 min, au club le plus proche ». Le bot réserve dès qu'un créneau se libère.")
            } else {
                ForEach(bot.rules) { rule in RuleCard(rule: rule) }
            }
        }
    }

    @ViewBuilder private var journal: some View {
        if !bot.log.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Journal du bot")
                ForEach(bot.log.prefix(15)) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(entry.kind)).foregroundStyle(color(entry.kind)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.clubName) · \(entry.slotStart.map { $0.formatted(.dateTime.weekday(.wide).day().hour().minute().locale(Locale(identifier: "fr_FR"))) } ?? "")")
                                .font(Neo.label(12)).foregroundStyle(Neo.text)
                            Text(entry.message).font(Neo.body(12)).foregroundStyle(Neo.dim)
                            if let s = entry.actionURL, let url = URL(string: s) {
                                Button("Terminer en un geste") { safariURL = url }.font(Neo.label(12)).foregroundStyle(Neo.volt)
                            }
                        }
                        Spacer()
                        Text(entry.date.formatted(.relative(presentation: .numeric))).font(Neo.body(10)).foregroundStyle(Neo.faint)
                    }
                    Divider().overlay(Neo.line)
                }
            }
            .glassCard()
        }
    }

    private func icon(_ k: BotLogEntry.Kind) -> String {
        switch k {
        case .booked: return "checkmark.seal.fill"
        case .found: return "eye.fill"
        case .needsAction: return "hand.tap.fill"
        case .failed: return "xmark.octagon"
        case .info: return "info.circle"
        }
    }

    private func color(_ k: BotLogEntry.Kind) -> Color {
        switch k {
        case .booked: return Neo.volt
        case .found, .info: return Neo.cyan
        case .needsAction: return Color.orange
        case .failed: return Neo.danger
        }
    }
}

struct RuleCard: View {
    var rule: BotRule
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var server: ServerAPI

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.clubName).font(Neo.label(15)).foregroundStyle(Neo.text).lineLimit(1)
                    Text(rule.summary).font(Neo.mono(12)).foregroundStyle(Neo.cyan)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { rule.active }, set: { v in
                    if let i = bot.rules.firstIndex(where: { $0.id == rule.id }) { bot.rules[i].active = v }
                })).labelsHidden().tint(Neo.volt)
            }
            HStack(spacing: 6) {
                Chip(text: rule.provider.name, color: Neo.cyan)
                Chip(text: rule.autoBook && rule.provider != .anybuddy ? "Réserve seul" : "Me prévient", color: Neo.volt)
                Chip(text: rule.maxBookings == 0 ? "Chaque semaine" : "\(rule.bookingsMade)/\(rule.maxBookings)", color: Neo.magenta)
                if rule.serverRuleID != nil { Chip(text: "24 h/24", systemImage: "server.rack", color: Neo.volt) }
            }
            Text(rule.lastStatus).font(Neo.body(12)).foregroundStyle(Neo.dim)
            HStack {
                Button { Task { await bot.run(ruleID: rule.id) } } label: { Label("Vérifier maintenant", systemImage: "arrow.clockwise") }
                    .font(Neo.label(12)).foregroundStyle(Neo.volt)
                Spacer()
                Button(role: .destructive) {
                    if let id = rule.serverRuleID { Task { await server.deleteServerRule(id) } }
                    bot.rules.removeAll { $0.id == rule.id }
                } label: { Image(systemName: "trash") }.foregroundStyle(Neo.danger)
            }
        }
        .glassCard(radius: 20, glow: rule.active ? Neo.volt : Neo.faint, padding: 14)
        .opacity(rule.active ? 1 : 0.6)
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
            ZStack {
                ScreenBackground(intensity: 0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(title: "Playtomic", subtitle: "Connecte ton compte : le bot voit les disponibilités et réserve avec ton compte.")
                        VStack(spacing: 12) {
                            field("E-mail Playtomic", text: $email, secure: false)
                            field("Mot de passe", text: $password, secure: true)
                        }
                        if server.isLoggedIn {
                            Toggle(isOn: $alsoServer) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Bot 24 h/24 sur le serveur PadelUp").font(Neo.label(13))
                                    Text("Réserve même quand ton iPhone est éteint.").font(Neo.body(12)).foregroundStyle(Neo.dim)
                                }
                            }.tint(Neo.volt)
                        }
                        if let error { Text(error).font(Neo.body(13)).foregroundStyle(Neo.danger) }
                        Button { Task { await connect() } } label: {
                            if busy { ProgressView().tint(Neo.night) } else { Text("Connecter mon compte") }
                        }
                        .buttonStyle(NeonButtonStyle(color: Neo.volt))
                        .disabled(busy || email.isEmpty || password.isEmpty)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Ton mot de passe n'est jamais enregistré : seuls les jetons de session Playtomic sont gardés, chiffrés dans le trousseau de l'iPhone.", systemImage: "lock.shield.fill")
                            Label("Le bot paie avec ce que le club accepte sans carte (sur place, crédit club). Sinon il bloque le créneau et te demande de valider.", systemImage: "creditcard.fill")
                            Label("Playtomic n'a pas d'API publique pour les apps tierces : PadelUp utilise les mêmes appels que leur app, ce qui peut évoluer.", systemImage: "info.circle")
                        }
                        .font(Neo.body(12)).foregroundStyle(Neo.dim)
                    }
                    .padding(18)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() }.foregroundStyle(Neo.volt) } }
        }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else {
                TextField(title, text: text).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .font(Neo.body(16)).padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Neo.cyan.opacity(0.35), lineWidth: 1))
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
            ZStack {
                ScreenBackground(intensity: 0.35)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(title: "Nouveau bot", subtitle: "Dis-lui ce que tu veux, il s'occupe du reste.")
                        clubSection
                        whenSection
                        optionsSection
                        if let info { Text(info).font(Neo.body(13)).foregroundStyle(Neo.danger) }
                        Button { Task { await save() } } label: {
                            if saving { ProgressView().tint(Neo.night) } else {
                                Text(rule.autoBook && rule.provider != .anybuddy ? "Lancer le bot : il réserve pour moi" : "Lancer le bot : il me prévient")
                            }
                        }
                        .buttonStyle(NeonButtonStyle(color: Neo.volt))
                        .disabled(rule.clubID.isEmpty || rule.weekdays.isEmpty || saving)
                        Text(rule.provider.automationNote).font(Neo.body(12)).foregroundStyle(Neo.faint)
                    }
                    .padding(18)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() }.foregroundStyle(Neo.volt) } }
        }
        .onAppear { if let prefill { rule = prefill } }
    }

    private var clubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Club")
            if !rule.clubID.isEmpty {
                HStack {
                    Image(systemName: "sportscourt.fill").foregroundStyle(Neo.volt)
                    VStack(alignment: .leading) {
                        Text(rule.clubName).font(Neo.label(14)).foregroundStyle(Neo.text)
                        Text("\(rule.provider.name)\(rule.clubCity.isEmpty ? "" : " · " + rule.clubCity)").font(Neo.body(12)).foregroundStyle(Neo.dim)
                    }
                    Spacer()
                    if prefill == nil { Button("Changer") { rule.clubID = "" }.font(Neo.label(12)).foregroundStyle(Neo.cyan) }
                }
            } else {
                Picker("Plateforme", selection: $rule.provider) {
                    Text("Playtomic").tag(BotProvider.playtomic)
                    Text("Anybuddy").tag(BotProvider.anybuddy)
                }.pickerStyle(.segmented)
                TextField(rule.provider == .anybuddy ? "Lien de la page Anybuddy du club" : "Ville ou nom du club (vide = autour de moi)", text: $clubQuery)
                    .font(Neo.body(15)).autocorrectionDisabled().textInputAutocapitalization(.never).padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                Button { Task { await searchClubs() } } label: {
                    if searching { ProgressView().tint(Neo.cyan) } else { Label("Chercher", systemImage: "magnifyingglass") }
                }.buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
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
        .glassCard()
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Quand")
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { d in
                    Button {
                        if rule.weekdays.contains(d) { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) }
                    } label: {
                        Text(dayNames[d]).font(Neo.label(14)).frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(rule.weekdays.contains(d) ? Neo.night : Neo.text)
                            .background(Circle().fill(rule.weekdays.contains(d) ? Neo.volt : Color.white.opacity(0.07)))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text("Début au plus tôt").font(Neo.body(12)).foregroundStyle(Neo.dim)
                    Stepper(BotRule.hhmm(rule.timeFrom), value: $rule.timeFrom, in: 6 * 60...23 * 60, step: 30).font(Neo.mono(16))
                }
                VStack(alignment: .leading) {
                    Text("Début au plus tard").font(Neo.body(12)).foregroundStyle(Neo.dim)
                    Stepper(BotRule.hhmm(rule.timeTo), value: $rule.timeTo, in: 6 * 60...23 * 60 + 30, step: 30).font(Neo.mono(16))
                }
            }
            HStack(spacing: 8) {
                ForEach([60, 90, 120], id: \.self) { d in
                    Button {
                        if rule.durations.contains(d) { if rule.durations.count > 1 { rule.durations.removeAll { $0 == d } } } else { rule.durations.append(d) }
                    } label: { Chip(text: "\(d) min", selected: rule.durations.contains(d), color: Neo.cyan) }.buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Réglages")
            Toggle("Réserver tout seul (sinon : me prévenir)", isOn: $rule.autoBook).tint(Neo.volt).font(Neo.body(14))
            Picker("Terrain", selection: $rule.court) {
                ForEach(BotRule.Court.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Stepper("Surveiller les \(rule.daysAhead) prochains jours", value: $rule.daysAhead, in: 1...21).font(Neo.body(14))
            Stepper(rule.maxBookings == 0 ? "Chaque semaine, sans limite" : "S'arrêter après \(rule.maxBookings) réservation(s)",
                    value: $rule.maxBookings, in: 0...10).font(Neo.body(14))
            Toggle("Prix maximum", isOn: $limitPrice).tint(Neo.volt).font(Neo.body(14))
            if limitPrice {
                Stepper("\(Int(price)) € max", value: $price, in: 5...200, step: 5).font(Neo.mono(14))
            }
        }
        .glassCard()
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
            var found = try await PlaytomicAPI.shared.tenants(near: center, radiusKm: 25)
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
