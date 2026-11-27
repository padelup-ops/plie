import CoreLocation
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
    @State private var showRuleEditor = false
    @State private var showConnect = false
    @State private var showCreateMatch = false
    @State private var anybuddyLink = ""
    @State private var safariURL: URL? = nil
    @State private var findingPlaytomic = false
    @State private var address: String? = nil

    private var provider: BotProvider? {
        if club.playtomicTenantID != nil { return .playtomic }
        if club.anybuddySlug != nil { return .anybuddy }
        if club.backendID != nil { return .padelup }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    facts
                    availabilitySection
                    if !weather.isEmpty { weatherSection }
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(UI.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.tint(UI.ink)
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
            async let w: Void = loadWeather()
            async let a: Void = loadAddress()
            await linkPlaytomicIfNeeded()
            await loadSlots()
            _ = await (w, a)
        }
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorView(prefill: BotRule(provider: provider ?? .playtomic, clubID: club.playtomicTenantID ?? club.anybuddySlug ?? club.backendID.map(String.init) ?? "",
                                            clubName: club.displayName, clubCity: club.city, timezone: club.timezone ?? TimeZone.current.identifier,
                                            durations: [duration]))
        }
        .sheet(isPresented: $showConnect) { ConnectPlaytomicView() }
        .sheet(isPresented: $showCreateMatch) { CreateMatchView(club: club) }
        .sheet(item: $safariURL) { url in SafariView(url: url).ignoresSafeArea() }
        .alert("Réserver ce créneau ?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Réserver") { if let s = confirm { Task { await book(s) } } }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let s = confirm {
                Text("\(club.displayName)\n\(BotEngine.when(s)) · \(s.duration) min · \(s.courtName)\(s.priceLabel.isEmpty ? "" : " · " + s.priceLabel)\nLe bot fait toute la réservation avec ton compte.")
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(initialPosition: .region(MKCoordinateRegion(center: club.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))) {
                Annotation(club.displayName, coordinate: club.coordinate) { ClubPin(club: club) }.annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: UI.radius, style: .continuous))
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Text(club.displayName).font(.system(size: 28, weight: .bold)).foregroundStyle(UI.ink).fixedSize(horizontal: false, vertical: true)
                Text(address ?? club.place).font(UI.callout()).foregroundStyle(UI.muted)
                HStack(spacing: 6) {
                    if club.canBookWithBot { Tag(text: "Réservable par le bot", systemImage: "bolt.fill", color: UI.accent) }
                    Tag(text: club.source.label, color: UI.muted)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private var facts: some View {
        HStack(spacing: 10) {
            Metric(value: club.courts > 0 ? "\(club.courts)" : "–", label: "terrains")
            Metric(value: club.indoor > 0 ? "\(club.indoor)" : "–", label: "couverts")
            Metric(value: club.outdoor > 0 ? "\(club.outdoor)" : "–", label: "extérieurs")
        }
    }

    // MARK: Disponibilités et réservation par le bot

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date())) }
    }

    @ViewBuilder private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Disponibilités").font(UI.headline()).foregroundStyle(UI.ink)
                Spacer()
                if let provider { Text(provider.name).font(UI.caption()).foregroundStyle(UI.muted) }
            }
            if provider == nil {
                notLinked
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { d in
                            let selected = Calendar.current.isDate(d, inSameDayAs: day)
                            Button { day = d; Task { await loadSlots() } } label: {
                                VStack(spacing: 3) {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR"))).capitalized)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(d.formatted(.dateTime.day())).font(UI.number(18))
                                }
                                .frame(width: 48, height: 58)
                                .foregroundStyle(selected ? UI.onAccent : UI.ink)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? UI.accent : UI.tray))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Picker("Durée", selection: $duration) {
                    Text("60 min").tag(60); Text("90 min").tag(90); Text("120 min").tag(120)
                }
                .pickerStyle(.segmented)
                if loadingSlots {
                    HStack(spacing: 10) { ProgressView(); Text("Le bot interroge \(provider?.name ?? "")…").font(UI.caption()).foregroundStyle(UI.muted) }
                } else if let slotError {
                    Text(slotError).font(UI.caption()).foregroundStyle(UI.warning)
                } else {
                    let list = slots.filter { $0.duration == duration && $0.start > Date() }
                    if list.isEmpty {
                        Text("Aucun créneau de \(duration) min ce jour-là. Le bot peut surveiller et réserver dès qu'un créneau se libère.")
                            .font(UI.caption()).foregroundStyle(UI.muted)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(list) { s in
                                Button { confirm = s } label: { SlotCell(slot: s) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let outcome { outcomeBanner(outcome) }
                if provider == .playtomic && !PlaytomicAPI.shared.isConnected {
                    Button { showConnect = true } label: { Text("Connecter Playtomic pour réserver") }
                        .buttonStyle(SecondaryButtonStyle(color: UI.accent))
                }
                Button { showRuleEditor = true } label: { Label("Le bot surveille et réserve pour moi", systemImage: "bolt.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Text(provider?.automationNote ?? "").font(UI.small()).foregroundStyle(UI.faint)
            }
        }
        .card()
    }

    private var notLinked: some View {
        VStack(alignment: .leading, spacing: 10) {
            if findingPlaytomic {
                HStack(spacing: 10) { ProgressView(); Text("Recherche de ce club sur Playtomic…").font(UI.caption()).foregroundStyle(UI.muted) }
            } else {
                Text("Ce club n'est pas relié à une plateforme de réservation.").font(UI.callout()).foregroundStyle(UI.muted)
            }
            Text("Il est sur Anybuddy ? Colle le lien de sa page :").font(UI.caption()).foregroundStyle(UI.faint)
            HStack(spacing: 8) {
                InputField(title: "anybuddyapp.com/fr/club/…", text: $anybuddyLink)
                Button("Relier") {
                    if let slug = AnybuddyAPI.slug(from: anybuddyLink) {
                        club.anybuddySlug = slug
                        club.timezone = "Europe/Paris"
                        Task { await loadSlots() }
                    }
                }
                .buttonStyle(LinkButtonStyle())
            }
        }
    }

    private func outcomeBanner(_ o: BookingOutcome) -> some View {
        let color = o.status == .booked ? UI.success : (o.status == .needsAction ? UI.accent : UI.danger)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: o.status == .booked ? "checkmark.circle.fill" : (o.status == .needsAction ? "hand.tap.fill" : "xmark.circle.fill"))
                .foregroundStyle(color).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(o.message).font(UI.callout()).foregroundStyle(UI.ink)
                if let url = o.actionURL {
                    Button("Terminer en un geste") { safariURL = url }.buttonStyle(LinkButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.10)))
    }

    // MARK: Météo de jeu

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Météo du court").font(UI.headline()).foregroundStyle(UI.ink)
                Spacer()
                Text(club.isMostlyIndoor ? "terrains couverts" : "indice de jeu /100").font(UI.caption()).foregroundStyle(UI.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(weather.prefix(30)) { h in
                        VStack(spacing: 6) {
                            Text(Self.hourLabel(h.time)).font(UI.small()).foregroundStyle(UI.muted)
                            Image(systemName: h.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                            Text("\(Int(h.temperature.rounded()))°").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(UI.ink)
                            Text("\(h.playScore)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(h.playScore >= 70 ? UI.success : (h.playScore >= 40 ? UI.warning : UI.danger))
                        }
                        .frame(width: 40)
                    }
                }
            }
        }
        .card()
    }

    private static func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH'h'"
        return f.string(from: date)
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            actionRow("Itinéraire", "arrow.triangle.turn.up.right.diamond") {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: club.coordinate))
                item.name = club.displayName
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            }
            Divider().overlay(UI.line).padding(.leading, 48)
            actionRow("Créer un match ici", "person.2") { showCreateMatch = true }
            if let url = URL(string: club.website), !club.website.isEmpty {
                Divider().overlay(UI.line).padding(.leading, 48)
                actionRow("Site du club", "safari") { safariURL = url }
            }
            if !club.phone.isEmpty, let tel = URL(string: "tel:" + club.phone.filter { "+0123456789".contains($0) }) {
                Divider().overlay(UI.line).padding(.leading, 48)
                Link(destination: tel) { rowLabel("Appeler", "phone") }
            }
            if !club.openingHours.isEmpty {
                Divider().overlay(UI.line).padding(.leading, 48)
                HStack(spacing: 14) {
                    Image(systemName: "clock").foregroundStyle(UI.muted).frame(width: 22)
                    Text(club.openingHours).font(UI.caption()).foregroundStyle(UI.muted)
                    Spacer()
                }
                .padding(.vertical, 13)
            }
        }
        .padding(.horizontal, 14)
        .card(padding: 0)
    }

    private func actionRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, icon) }.buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(UI.accent).frame(width: 22)
            Text(title).font(UI.body()).foregroundStyle(UI.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(UI.faint)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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
        findingPlaytomic = true
        defer { findingPlaytomic = false }
        guard let tenants = try? await PlaytomicAPI.shared.tenants(near: club.coordinate, radiusKm: 2) else { return }
        if let match = tenants.first(where: { ClubDirectory.similar($0.name, club.name) || $0.location.distance(from: club.location) < 250 }) {
            club.playtomicTenantID = match.playtomicTenantID
            club.timezone = match.timezone
            if club.courts == 0 { club.courts = match.courts }
            directory.merge(playtomic: match)
        }
    }

    private func loadSlots() async {
        guard let provider, ShotMode.current == nil else { return }
        if provider == .padelup && !server.isLoggedIn {
            slotError = "Connecte-toi à ton compte PadelUp (onglet Profil) pour voir et réserver les créneaux de ce club partenaire."
            return
        }
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
        outcome = await bot.book(slot, clubName: club.displayName)
        if outcome?.status == .booked { await loadSlots() }
        if outcome?.status == .needsAction, let url = outcome?.actionURL { safariURL = url }
    }
}

struct SlotCell: View {
    var slot: BookingSlot

    var body: some View {
        VStack(spacing: 3) {
            Text(slot.localTime).font(UI.number(18)).foregroundStyle(UI.ink)
            Text(slot.courtName).font(.system(size: 11)).foregroundStyle(UI.muted).lineLimit(1)
            if !slot.priceLabel.isEmpty { Text(slot.priceLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(UI.accent) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.tray))
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct SafariView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.035, green: 0.29, blue: 0.45, alpha: 1)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
