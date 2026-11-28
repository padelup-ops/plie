import CoreLocation
import MapKit
import SafariServices
import SwiftUI

/// Créneaux d'une même heure regroupés (plusieurs terrains libres à 19:30 = une seule case).
struct SlotGroup: Identifiable, Hashable {
    var time: String
    var slots: [BookingSlot]
    var id: String { time + ":" + (slots.first?.id ?? "") }
    var first: BookingSlot { slots[0] }
    var minPrice: String { slots.min { ($0.price ?? .infinity) < ($1.price ?? .infinity) }?.priceLabel ?? "" }
}

struct ClubDetailView: View {
    @State var club: Club
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var server: ServerAPI
    @EnvironmentObject private var favorites: Favorites
    @Environment(\.dismiss) private var dismiss

    @State private var weather: [WeatherHour] = []
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var slots: [BookingSlot] = []
    @State private var loadingSlots = false
    @State private var slotError: String? = nil
    @State private var duration = 90
    @State private var picked: SlotGroup? = nil
    @State private var outcome: BookingOutcome? = nil
    @State private var showRuleEditor = false
    @State private var showCreateMatch = false
    @State private var anybuddyLink = ""
    @State private var web: URL? = nil
    @State private var login: BotProvider? = nil
    @State private var findingPlaytomic = false
    @State private var lastRefresh: Date? = nil
    @State private var address: String? = nil
    @State private var accountsVersion = 0
    @State private var pickOnSite = false
    @State private var booking: BookingRequest? = nil
    @State private var window: BookingWindow? = nil
    @State private var watchRelease = false

    private var provider: BotProvider? {
        if club.playtomicTenantID != nil { return .playtomic }
        if club.anybuddySlug != nil { return .anybuddy }
        if club.backendID != nil { return .padelup }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mapHeader
                VStack(alignment: .leading, spacing: 30) {
                    titleBlock
                    if club.courts > 0 || Self.compactHours(club.openingHours) != nil { facts }
                    quickActions
                    bookingBlock
                    if !weather.isEmpty {
                        Block(title: "Météo de jeu", meta: club.isMostlyIndoor ? "couvert" : nil) {
                            PlayWeatherChart(hours: Array(weather.prefix(12)), indoor: club.isMostlyIndoor)
                        }
                    }
                    moreBlock
                }
                .padding(.horizontal, UI.margin)
                .padding(.top, 22)
                .padding(.bottom, 48)
            }
        }
        .background(UI.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            RoundIconButton(systemImage: "xmark") { dismiss() }.padding(16).accessibilityLabel("Fermer")
        }
        .task {
            if ShotMode.current != nil {
                weather = ShotMode.demoWeather()
                slots = ShotMode.demoSlots(for: club)
                window = BookingWindow(days: 7, rolling: true, lastDay: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(), checked: Date())
                day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? day
                lastRefresh = Date()
                return
            }
            async let w: Void = loadWeather()
            async let a: Void = loadAddress()
            await linkPlaytomicIfNeeded()
            await loadSlots()
            if let tenant = club.playtomicTenantID {
                window = await PlaytomicWeb.bookingWindow(tenantID: tenant, timezone: club.timezone)
            }
            _ = await (w, a)
            // Temps réel : les créneaux sont relus chaque minute tant que la fiche est ouverte.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await loadSlots(quiet: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .webAccountChanged)) { _ in accountsVersion += 1 }
        .sheet(item: $web) { url in ProviderWebSheet(provider: WebAccount.owns(url), url: url) }
        .sheet(item: $booking) { r in BookingFlowSheet(request: r) }
        .sheet(item: $login) { p in ProviderWebSheet(provider: p, url: WebAccount.loginURL(p), title: "Connexion \(p.name)") }
        .sheet(item: $picked) { group in
            BookingSheet(club: club, group: group, duration: duration) { action in
                picked = nil
                switch action {
                case .book(let slot): Task { await book(slot) }
                case .watch: showRuleEditor = true
                }
            }
            .presentationDetents([.height(480)])
            .presentationBackground(UI.paper)
        }
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorView(prefill: BotRule(provider: provider ?? .playtomic, clubID: club.playtomicTenantID ?? club.anybuddySlug ?? club.backendID.map(String.init) ?? "",
                                            clubName: club.displayName, clubCity: club.city, timezone: club.timezone ?? TimeZone.current.identifier,
                                            durations: [duration], clubSlug: club.playtomicSlug))
        }
        .sheet(isPresented: $showCreateMatch) { CreateMatchView(club: club) }
        .sheet(isPresented: $watchRelease) {
            RuleEditorView(prefill: BotRule(provider: .playtomic, clubID: club.playtomicTenantID ?? "", clubName: club.displayName, clubCity: club.city,
                                            timezone: club.timezone ?? TimeZone.current.identifier, durations: [duration], clubSlug: club.playtomicSlug,
                                            releaseDays: window?.days ?? 7, releaseMinutes: (window?.rolling ?? false) ? 19 * 60 : 0))
        }
        .sheet(isPresented: $pickOnSite) {
            PlaytomicPickerSheet(query: club.name) { match in
                club.playtomicTenantID = match.id
                club.playtomicSlug = match.slug
                if club.timezone == nil { club.timezone = club.longitude > 8 && club.latitude < 38 ? "Africa/Tunis" : "Europe/Paris" }
                directory.link(clubID: club.id, tenantID: match.id, slug: match.slug, timezone: club.timezone)
                Task { await loadSlots() }
            }
        }
    }

    // MARK: En-tête

    private var mapHeader: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: club.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
            Annotation(club.displayName, coordinate: club.coordinate) { ClubPin(club: club) }.annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 190)
        .allowsHitTesting(false)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [UI.paper.opacity(0), UI.paper], startPoint: .top, endPoint: .bottom).frame(height: 56)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: [club.city, provider?.name ?? (club.source == .osm ? "OpenStreetMap" : club.source.label)].filter { !$0.isEmpty }.joined(separator: " · "))
            Text(club.displayName).font(UI.display(30)).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
            Text(address ?? club.place).font(UI.callout()).foregroundStyle(UI.muted)
        }
    }

    private var facts: some View {
        var items: [(String, String)] = []
        if club.courts > 0 { items.append(("\(club.courts)", club.courts > 1 ? "terrains" : "terrain")) }
        if club.indoor > 0 { items.append(("\(club.indoor)", club.indoor > 1 ? "couverts" : "couvert")) }
        if club.outdoor > 0 { items.append(("\(club.outdoor)", "dehors")) }
        if let hours = Self.compactHours(club.openingHours) { items.append((hours, "horaires")) }
        return StatsRow(items: Array(items.prefix(3)))
    }

    /// « Mo-Su 07:00-23:30 » → « 7–23 h ».
    static func compactHours(_ raw: String) -> String? {
        guard let r = raw.range(of: #"(\d{1,2}):\d{2}\s*-\s*(\d{1,2}):\d{2}"#, options: .regularExpression) else { return nil }
        let parts = raw[r].split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = Int(parts[0].prefix(while: { $0 != ":" })), let b = Int(parts[1].prefix(while: { $0 != ":" })) else { return nil }
        return "\(a)–\(b) h"
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction("Itinéraire", "arrow.triangle.turn.up.right.diamond") {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: club.coordinate))
                item.name = club.displayName
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            }
            if !club.phone.isEmpty, let tel = URL(string: "tel:" + club.phone.filter { "+0123456789".contains($0) }) {
                quickAction("Appeler", "phone") { UIApplication.shared.open(tel) }
            }
            if let url = URL(string: club.website), !club.website.isEmpty {
                quickAction("Site", "safari") { web = url }
            }
            quickAction("Match", "person.2") { showCreateMatch = true }
            quickAction(favorites.contains(club) ? "Favori" : "Garder", favorites.contains(club) ? "heart.fill" : "heart") { favorites.toggle(club) }
        }
    }

    private func quickAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(UI.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Réservation

    private var days: [Date] {
        (0..<10).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    @ViewBuilder private var bookingBlock: some View {
        let _ = accountsVersion
        if let provider {
            slotsBlock(provider)
            if provider == .anybuddy { anybuddyBlock }
        } else {
            notLinked
        }
    }

    private func slotsBlock(_ provider: BotProvider) -> some View {
        Block(title: "Créneaux", meta: provider == .playtomic ? "en direct" + (lastRefresh.map { " · " + FR.time($0) } ?? "") : provider.name,
              live: provider == .playtomic && slotError == nil) {
            VStack(alignment: .leading, spacing: 18) {
                dayStrip
                InlinePicker(options: [(60, "60 min"), (90, "90 min"), (120, "120 min")], selection: $duration)
                if provider == .playtomic, let window { windowNote(window) }
                slotsContent
                if provider == .playtomic && !PlaytomicWeb.connected && ShotMode.current == nil {
                    HStack(spacing: 12) {
                        Text("Connecte Playtomic pour réserver en un geste.").font(UI.callout()).foregroundStyle(UI.muted)
                        Spacer(minLength: 8)
                        Button("Connecter") { login = .playtomic }.buttonStyle(LinkButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
                if let outcome, outcome.status != .needsAction { outcomeNote(outcome) }
                Button { showRuleEditor = true } label: { Label("Réserver automatiquement ici", systemImage: "bolt.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Text(provider.automationNote).font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Quand ouvrent les créneaux de ce club (détecté en lisant ses créneaux).
    private func windowNote(_ w: BookingWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(w.title).font(UI.headline()).foregroundStyle(UI.ink)
                Stamp(text: w.rolling ? "Glissant" : "Jour entier", style: .outline)
            }
            Text("Jusqu'au \(FR.longDay(w.lastDay)). " + w.explanation()).font(UI.caption()).foregroundStyle(UI.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { watchRelease = true } label: { Label("Être prévenu à l'ouverture", systemImage: "alarm") }
                .buttonStyle(LinkButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let selected = Calendar.current.isDate(d, inSameDayAs: day)
                    let today = Calendar.current.isDateInToday(d)
                    Button { day = d; Task { await loadSlots() } } label: {
                        VStack(spacing: 4) {
                            Text(today ? "AUJ." : FR.string(d, "EEE").replacingOccurrences(of: ".", with: "").uppercased(with: UI.fr))
                                .font(UI.label()).tracking(0.6)
                            Text(FR.string(d, "d")).font(UI.score(22))
                        }
                        .frame(width: 50, height: 62)
                        .foregroundStyle(selected ? UI.paper : UI.ink)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? UI.ink : UI.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.clear : UI.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groups: [(String, [SlotGroup])] {
        let list = slots.filter { ($0.duration == duration || $0.duration == 0) && $0.start > Date() }
        var byTime: [String: [BookingSlot]] = [:]
        for s in list { byTime[s.localTime, default: []].append(s) }
        let all = byTime.keys.sorted().map { SlotGroup(time: $0, slots: (byTime[$0] ?? []).sorted { ($0.price ?? 0) < ($1.price ?? 0) }) }
        let periods: [(String, ClosedRange<Int>)] = [("Matin", 0...719), ("Après-midi", 720...1079), ("Soir", 1080...1439)]
        return periods.compactMap { name, range in
            let g = all.filter { range.contains($0.first.minutesOfDay) }
            return g.isEmpty ? nil : (name, g)
        }
    }

    @ViewBuilder private var slotsContent: some View {
        if loadingSlots && slots.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Lecture des créneaux…").font(UI.callout()).foregroundStyle(UI.muted)
            }
            .padding(.vertical, 8)
        } else if let slotError {
            EmptyNote(title: "Créneaux indisponibles", message: slotError, actionTitle: "Réessayer") { Task { await loadSlots() } }
        } else if groups.isEmpty {
            EmptyNote(title: "Rien de libre en \(duration) min ce jour-là.",
                      message: "La résa auto peut guetter ce club et te préparer la réservation dès qu'un créneau se libère.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { name, list in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: name)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(list) { g in
                                Button { picked = g } label: { SlotCell(group: g) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var anybuddyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !WebAccount.isConnected(.anybuddy) {
                HStack(spacing: 12) {
                    Text("Compte Anybuddy non connecté.").font(UI.callout()).foregroundStyle(UI.ink)
                    Spacer(minLength: 8)
                    Button("Connecter") { login = .anybuddy }.buttonStyle(LinkButtonStyle())
                }
            }
            Button { web = AnybuddyAPI.clubURL(club.anybuddySlug ?? "", day: day) } label: { Label("Ouvrir la page Anybuddy du club", systemImage: "calendar") }
                .buttonStyle(SecondaryButtonStyle())
            Button { web = AnybuddyAPI.autoBookingURL } label: { Label("Réservation automatique Anybuddy", systemImage: "scope") }
                .buttonStyle(LinkButtonStyle())
        }
    }

    private var notLinked: some View {
        Block(title: "Réservation") {
            VStack(alignment: .leading, spacing: 12) {
                if findingPlaytomic {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recherche de ce club sur Playtomic…").font(UI.callout()).foregroundStyle(UI.muted)
                    }
                } else {
                    Text("Ce club n'est pas encore relié à une plateforme de réservation.").font(UI.callout()).foregroundStyle(UI.muted)
                    Button { pickOnSite = true } label: { Label("Le trouver sur Playtomic", systemImage: "safari") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Text("Il est sur Anybuddy ? Colle le lien de sa page.").font(UI.caption()).foregroundStyle(UI.faint)
                HStack(spacing: 10) {
                    InputField(title: "anybuddyapp.com/fr/club/…", text: $anybuddyLink, keyboard: .URL)
                    Button("Relier") {
                        if let slug = AnybuddyAPI.slug(from: anybuddyLink) {
                            club.anybuddySlug = slug
                            club.timezone = "Europe/Paris"
                        }
                    }
                    .buttonStyle(LinkButtonStyle())
                }
            }
        }
    }

    private func outcomeNote(_ o: BookingOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if o.status == .booked { Stamp(text: "Réservé") } else { Stamp(text: "Échec", style: .clay) }
            Text(o.message).font(UI.callout()).foregroundStyle(UI.ink)
            Spacer(minLength: 0)
        }
    }

    // MARK: Plus

    @ViewBuilder private var moreBlock: some View {
        if !club.openingHours.isEmpty || !club.email.isEmpty {
            Block(title: "Infos") {
                VStack(spacing: 0) {
                    if !club.openingHours.isEmpty {
                        ListRow(title: "Horaires", detail: club.openingHours, systemImage: "clock", chevron: false)
                    }
                    if !club.email.isEmpty, let mail = URL(string: "mailto:" + club.email) {
                        if !club.openingHours.isEmpty { Hairline(inset: 36) }
                        Link(destination: mail) { ListRow(title: club.email, systemImage: "envelope") }
                    }
                }
            }
        }
    }

    // MARK: Données

    private func loadWeather() async {
        weather = (try? await WeatherAPI.forecast(latitude: club.latitude, longitude: club.longitude)) ?? weather
    }

    /// Adresse lisible quand OpenStreetMap n'en donne pas (géocodage inverse d'Apple, sans clé).
    private func loadAddress() async {
        guard club.street.isEmpty || club.city.isEmpty else { return }
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(club.location).first else { return }
        let line = [[mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " "),
                    [mark.postalCode, mark.locality].compactMap { $0 }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: ", ")
        if !line.isEmpty { address = line }
        if club.city.isEmpty, let city = mark.locality { club.city = city }
    }

    private func linkPlaytomicIfNeeded() async {
        guard club.playtomicTenantID == nil, club.anybuddySlug == nil, club.backendID == nil else { return }
        // Anybuddy d'abord : reconnu tout de suite par son nom dans la liste publique de leurs clubs.
        if let slug = AnybuddyDirectory.match(club) {
            club.anybuddySlug = slug
            if club.timezone == nil { club.timezone = "Europe/Paris" }
            directory.linkAnybuddy(clubID: club.id, slug: slug)
            return
        }
        findingPlaytomic = true
        defer { findingPlaytomic = false }
        // Recherche du club sur le site Playtomic (nom + ville).
        if let match = await PlaytomicWeb.match(for: club) {
            club.playtomicTenantID = match.id
            club.playtomicSlug = match.slug
            if club.timezone == nil { club.timezone = club.longitude > 8 && club.latitude < 38 ? "Africa/Tunis" : "Europe/Paris" }
            directory.link(clubID: club.id, tenantID: match.id, slug: match.slug, timezone: club.timezone)
        }
    }

    private func loadSlots(quiet: Bool = false) async {
        guard let provider, ShotMode.current == nil else { return }
        if provider == .padelup && !server.isLoggedIn {
            slotError = "Connecte-toi à ton compte PadelUp (onglet Profil) pour voir et réserver les créneaux de ce club partenaire."
            return
        }
        if !quiet { loadingSlots = true }
        defer { loadingSlots = false; lastRefresh = Date() }
        do {
            switch provider {
            case .playtomic: slots = try await PlaytomicWeb.slots(tenantID: club.playtomicTenantID ?? "", day: day, timezone: club.timezone)
            case .anybuddy: slots = try await AnybuddyAPI.slots(slug: club.anybuddySlug ?? "", day: day)
            case .padelup: slots = try await server.botSlots(provider: .padelup, clubID: String(club.backendID ?? 0), day: day)
            }
            slotError = nil
            if !slots.contains(where: { $0.duration == duration || $0.duration == 0 }), let first = slots.first(where: { $0.duration > 0 }) {
                duration = first.duration
            }
        } catch {
            if !quiet { slots = [] }
            slotError = error.localizedDescription
        }
    }

    private func book(_ slot: BookingSlot) async {
        let result = await bot.book(slot, clubName: club.displayName, slug: club.playtomicSlug)
        if result.status == .needsAction, let url = result.actionURL {
            // Page déjà connectée ; l'assistant choisit l'heure et la durée, tu confirmes.
            booking = BookingRequest(url: url, target: BookingTarget(time: slot.localTime, duration: slot.duration > 0 ? slot.duration : duration,
                                                                     direct: DirectPay(slot: slot), start: slot.start, clubName: club.displayName,
                                                                     court: slot.courtName, price: slot.priceLabel, timezone: slot.timezone,
                                                                     amount: slot.price, currency: slot.currency))
        } else {
            outcome = result
            if result.status == .booked { await loadSlots() }
        }
    }
}

/// Case d'un créneau : l'heure en grand, le prix et le nombre de terrains libres.
struct SlotCell: View {
    var group: SlotGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.time).font(UI.score(22)).foregroundStyle(UI.ink)
            HStack(spacing: 4) {
                Text(group.minPrice.isEmpty ? "—" : group.minPrice).font(.system(size: 12, weight: .medium)).foregroundStyle(UI.muted)
                Spacer(minLength: 0)
                if group.slots.count > 1 {
                    Text("×\(group.slots.count)").font(UI.score(12)).foregroundStyle(UI.muted)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.raised))
        .overlay(alignment: .topTrailing) {
            Circle().fill(UI.ball).frame(width: 7, height: 7).overlay(Circle().strokeBorder(UI.ink.opacity(0.3), lineWidth: 0.5)).padding(8)
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.time), dès \(group.minPrice), \(group.slots.count) terrain\(group.slots.count > 1 ? "s" : "") libre\(group.slots.count > 1 ? "s" : "")")
    }
}

/// Feuille de réservation : le billet du créneau, puis réserver ou confier au bot.
struct BookingSheet: View {
    enum Action { case book(BookingSlot), watch }
    var club: Club
    var group: SlotGroup
    var duration: Int
    var onAction: (Action) -> Void
    @State private var courtIndex = 0

    private var slot: BookingSlot { group.slots[min(courtIndex, group.slots.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Ticket {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Eyebrow(text: slot.provider.name)
                        Spacer()
                        Stamp(text: "Libre")
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(group.time).font(UI.scoreHeavy(64)).foregroundStyle(UI.ink)
                        Text(FR.longDay(slot.start, tz: slot.timeZoneValue)).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(2)
                    }
                    Text(club.displayName).font(UI.headline()).foregroundStyle(UI.ink)
                    Text("\(slot.courtName) · \(slot.duration == 0 ? "durée au choix" : "\(duration) min")\(slot.priceLabel.isEmpty ? "" : " · " + slot.priceLabel)")
                        .font(UI.callout()).foregroundStyle(UI.muted)
                }
            } stub: {
                Text(slot.provider == .padelup ? "Réservation directe, club partenaire PadelUp."
                     : "Paiement sur \(slot.provider.name), avec ton compte déjà connecté.")
                    .font(UI.caption()).foregroundStyle(UI.muted)
            }
            if group.slots.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(group.slots.indices, id: \.self) { i in
                            Button { courtIndex = i } label: {
                                Chip(text: group.slots[i].courtName + (group.slots[i].priceLabel.isEmpty ? "" : " · " + group.slots[i].priceLabel), active: courtIndex == i)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button { onAction(.book(slot)) } label: {
                Text(slot.provider == .padelup ? "Réserver" : "Réserver sur \(slot.provider.name)")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button { onAction(.watch) } label: { Text("Résa auto sur ce club") }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, UI.margin)
        .padding(.top, 28)
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UI.uiColor(0x094A73)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
