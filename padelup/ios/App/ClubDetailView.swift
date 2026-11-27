import MapKit
import SafariServices
import SwiftUI

struct ClubDetailView: View {
    @State var club: Club
    @EnvironmentObject private var bot: BotEngine
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var server: ServerAPI
    @Environment(\.dismiss) private var dismiss

    @State private var weather: [WeatherHour] = []
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var slots: [BookingSlot] = []
    @State private var loadingSlots = false
    @State private var slotError: String? = nil
    @State private var duration = 90
    @State private var confirm: BookingSlot? = nil
    @State private var outcome: BookingOutcome? = nil
    @State private var booking = false
    @State private var showRuleEditor = false
    @State private var showConnect = false
    @State private var showCreateMatch = false
    @State private var anybuddyLink = ""
    @State private var safariURL: URL? = nil
    @State private var findingPlaytomic = false

    private var provider: BotProvider? {
        if club.playtomicTenantID != nil { return .playtomic }
        if club.anybuddySlug != nil { return .anybuddy }
        if club.backendID != nil { return .padelup }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground(intensity: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        infoGrid
                        if !weather.isEmpty { weatherSection }
                        availabilitySection
                        actionsSection
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Neo.faint) }
                }
            }
        }
        .task {
            if ShotMode.current != nil {
                weather = ShotMode.demoWeather()
                slots = ShotMode.demoSlots(for: club)
                day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? day
                return
            }
            await loadWeather()
            await linkPlaytomicIfNeeded()
            await loadSlots()
        }
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorView(prefill: BotRule(provider: provider ?? .playtomic, clubID: club.playtomicTenantID ?? club.anybuddySlug ?? club.backendID.map(String.init) ?? "",
                                            clubName: club.displayName, clubCity: club.city, timezone: club.timezone ?? TimeZone.current.identifier,
                                            durations: [duration]))
        }
        .sheet(isPresented: $showConnect) { ConnectPlaytomicView() }
        .sheet(isPresented: $showCreateMatch) { CreateMatchView(club: club) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
        .alert("Le bot réserve ce créneau ?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Réserver", role: .none) { if let s = confirm { Task { await book(s) } } }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let s = confirm {
                Text("\(club.displayName)\n\(BotEngine.when(s)) · \(s.duration) min · \(s.courtName)\(s.priceLabel.isEmpty ? "" : " · " + s.priceLabel)\nPaiement : sur place, crédit club ou ton moyen enregistré.")
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Chip(text: club.source.label, systemImage: club.source == .playtomic ? "bolt.fill" : "map", color: Neo.cyan)
                if club.canBookWithBot { Chip(text: "Bot ⚡︎", selected: true, color: Neo.volt) }
                if club.indoor > 0 { Chip(text: "Couvert", systemImage: "building.2", color: Neo.magenta) }
            }
            Text(club.displayName).font(Neo.title(28)).foregroundStyle(Neo.text).fixedSize(horizontal: false, vertical: true)
            Text(club.place).font(Neo.body(14)).foregroundStyle(Neo.dim)
            Map(initialPosition: .region(MKCoordinateRegion(center: club.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                Annotation(club.displayName, coordinate: club.coordinate) { ClubPin(club: club) }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Neo.cyan.opacity(0.4), lineWidth: 1))
            .allowsHitTesting(false)
        }
    }

    private var infoGrid: some View {
        HStack(spacing: 12) {
            StatTile(value: club.courts > 0 ? "\(club.courts)" : "?", label: "terrains", color: Neo.cyan)
            StatTile(value: club.indoor > 0 ? "\(club.indoor)" : "–", label: "couverts", color: Neo.magenta)
            StatTile(value: club.openingHours.isEmpty ? "–" : "✓", label: club.openingHours.isEmpty ? "horaires ?" : "horaires", color: Neo.volt)
        }
    }

    // MARK: Météo de jeu

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Météo du court", trailing: club.isMostlyIndoor ? "terrains couverts" : "indice padel /100")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(weather.prefix(30)) { h in
                        VStack(spacing: 6) {
                            Text(Self.hourLabel(h.time))
                                .font(Neo.label(11)).foregroundStyle(Neo.dim)
                            Image(systemName: h.symbol).symbolRenderingMode(.multicolor).font(.system(size: 20))
                            Text("\(Int(h.temperature.rounded()))°").font(Neo.mono(14)).foregroundStyle(Neo.text)
                            Text("\(h.playScore)").font(Neo.mono(12))
                                .foregroundStyle(h.playScore >= 70 ? Neo.volt : (h.playScore >= 40 ? Color.orange : Neo.danger))
                        }
                        .frame(width: 52)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
        .glassCard()
    }

    private static func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH'h'"
        return f.string(from: date)
    }

    private func loadWeather() async {
        weather = (try? await WeatherAPI.forecast(latitude: club.latitude, longitude: club.longitude)) ?? weather
    }

    // MARK: Disponibilités et réservation par le bot

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    @ViewBuilder private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Disponibilités", trailing: provider.map { "via \($0.name)" })
            if provider == nil {
                notLinked
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { d in
                            Button { day = d; Task { await loadSlots() } } label: {
                                VStack(spacing: 2) {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR"))).uppercased()).font(Neo.label(10))
                                    Text(d.formatted(.dateTime.day())).font(Neo.title(18))
                                }
                                .frame(width: 50, height: 58)
                                .foregroundStyle(Calendar.current.isDate(d, inSameDayAs: day) ? Neo.night : Neo.text)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Calendar.current.isDate(d, inSameDayAs: day) ? Neo.volt : Color.white.opacity(0.06)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Picker("Durée", selection: $duration) {
                    Text("60 min").tag(60); Text("90 min").tag(90); Text("120 min").tag(120)
                }
                .pickerStyle(.segmented)
                if loadingSlots {
                    HStack { ProgressView().tint(Neo.volt); Text("Le bot interroge \(provider?.name ?? "")…").font(Neo.body(13)).foregroundStyle(Neo.dim) }
                } else if let slotError {
                    Text(slotError).font(Neo.body(13)).foregroundStyle(Neo.danger)
                } else {
                    let list = slots.filter { $0.duration == duration && $0.start > Date() }
                    if list.isEmpty {
                        Text("Aucun créneau de \(duration) min ce jour-là. Le bot peut surveiller et réserver dès qu'un créneau se libère.")
                            .font(Neo.body(13)).foregroundStyle(Neo.dim)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(list) { s in
                                Button { confirm = s } label: { SlotCell(slot: s) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let outcome { outcomeBanner(outcome) }
                if provider == .playtomic && !PlaytomicAPI.shared.isConnected {
                    Button { showConnect = true } label: { Label("Connecter Playtomic pour que le bot réserve", systemImage: "link") }
                        .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
                }
                Text(provider?.automationNote ?? "").font(Neo.body(12)).foregroundStyle(Neo.faint)
            }
        }
        .glassCard(glow: Neo.volt)
    }

    private var notLinked: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(findingPlaytomic ? "Recherche de ce club sur Playtomic…" : "Ce club n'est pas (encore) relié à une plateforme de réservation.")
                .font(Neo.body(14)).foregroundStyle(Neo.dim)
            Text("Il est sur Anybuddy ? Colle le lien de sa page :").font(Neo.body(13)).foregroundStyle(Neo.faint)
            HStack {
                TextField("anybuddyapp.com/fr/club/…", text: $anybuddyLink).font(Neo.body(14)).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                Button("Relier") {
                    if let slug = AnybuddyAPI.slug(from: anybuddyLink) {
                        club.anybuddySlug = slug
                        club.timezone = "Europe/Paris"
                        Task { await loadSlots() }
                    }
                }.font(Neo.label(13)).foregroundStyle(Neo.volt)
            }
        }
    }

    private func outcomeBanner(_ o: BookingOutcome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: o.status == .booked ? "checkmark.seal.fill" : (o.status == .needsAction ? "hand.tap.fill" : "xmark.octagon.fill"))
                .foregroundStyle(o.status == .booked ? Neo.volt : (o.status == .needsAction ? Neo.cyan : Neo.danger)).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(o.message).font(Neo.body(14)).foregroundStyle(Neo.text)
                if let url = o.actionURL {
                    Button("Terminer en un geste") { safariURL = url }.font(Neo.label(13)).foregroundStyle(Neo.volt)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private func linkPlaytomicIfNeeded() async {
        guard club.playtomicTenantID == nil, club.anybuddySlug == nil, club.backendID == nil, ShotMode.current == nil else { return }
        findingPlaytomic = true
        defer { findingPlaytomic = false }
        guard let tenants = try? await PlaytomicAPI.shared.tenants(near: club.coordinate, radiusKm: 1) else { return }
        if let match = tenants.first(where: { ClubDirectory.similar($0.name, club.name) || $0.location.distance(from: club.location) < 150 }) {
            club.playtomicTenantID = match.playtomicTenantID
            club.timezone = match.timezone
            if club.courts == 0 { club.courts = match.courts }
            directory.merge(playtomic: match)
        }
    }

    private func loadSlots() async {
        guard let provider, ShotMode.current == nil else { return }
        loadingSlots = true
        slotError = nil
        defer { loadingSlots = false }
        do {
            switch provider {
            case .playtomic: slots = try await PlaytomicAPI.shared.slots(tenantID: club.playtomicTenantID ?? "", day: day)
            case .anybuddy: slots = try await AnybuddyAPI.slots(slug: club.anybuddySlug ?? "", day: day)
            case .padelup: slots = try await server.botSlots(provider: .padelup, clubID: String(club.backendID ?? 0), day: day)
            }
            if !slots.contains(where: { $0.duration == duration }), let first = slots.first { duration = first.duration }
        } catch {
            slots = []
            slotError = error.localizedDescription
        }
    }

    private func book(_ slot: BookingSlot) async {
        if slot.provider == .playtomic && !PlaytomicAPI.shared.isConnected { showConnect = true; return }
        booking = true
        outcome = await bot.book(slot, clubName: club.displayName)
        booking = false
        if outcome?.status == .booked { await loadSlots() }
        if outcome?.status == .needsAction, let url = outcome?.actionURL { safariURL = url }
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if provider != nil {
                Button { showRuleEditor = true } label: { Label("Le bot surveille et réserve pour moi", systemImage: "bolt.badge.clock.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.volt))
            }
            HStack(spacing: 12) {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: club.coordinate))
                    item.name = club.displayName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                } label: { Label("Itinéraire", systemImage: "car.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
                Button { showCreateMatch = true } label: { Label("Créer un match", systemImage: "person.3.fill") }
                    .buttonStyle(NeonButtonStyle(color: Neo.cyan, filled: false))
            }
            HStack(spacing: 12) {
                if let url = URL(string: club.website), !club.website.isEmpty {
                    Button { safariURL = url } label: { Label("Site", systemImage: "safari.fill") }
                        .buttonStyle(NeonButtonStyle(color: Neo.magenta, filled: false))
                }
                if !club.phone.isEmpty, let tel = URL(string: "tel:" + club.phone.filter { "+0123456789".contains($0) }) {
                    Link(destination: tel) { Label("Appeler", systemImage: "phone.fill") }
                        .buttonStyle(NeonButtonStyle(color: Neo.magenta, filled: false))
                }
            }
            if !club.openingHours.isEmpty {
                Text("Horaires (OSM) : \(club.openingHours)").font(Neo.body(12)).foregroundStyle(Neo.faint)
            }
        }
    }
}

struct SlotCell: View {
    var slot: BookingSlot

    var body: some View {
        VStack(spacing: 4) {
            Text(slot.localTime).font(Neo.mono(18)).foregroundStyle(Neo.text)
            Text(slot.courtName).font(Neo.body(11)).foregroundStyle(Neo.dim).lineLimit(1)
            if !slot.priceLabel.isEmpty { Text(slot.priceLabel).font(Neo.label(11)).foregroundStyle(Neo.volt) }
            if let indoor = slot.indoor {
                Image(systemName: indoor ? "building.2.fill" : "sun.max.fill").font(.system(size: 10)).foregroundStyle(Neo.cyan)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neo.court.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Neo.cyan.opacity(0.45), lineWidth: 1))
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.83, green: 1.0, blue: 0.23, alpha: 1)
        vc.preferredBarTintColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
