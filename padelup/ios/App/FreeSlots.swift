import CoreLocation
import SwiftUI

// « Libre près de toi » : tout de suite, sans bot, les créneaux libres de ce soir et de demain (matin, après-midi,
// soir) dans tes clubs favoris et les clubs proches. Lecture en direct sur Playtomic (et clubs partenaires PadelUp).

enum FreePeriod: String, CaseIterable, Identifiable {
    case tonight, tomorrowMorning, tomorrowAfternoon, tomorrowEvening
    var id: String { rawValue }

    var label: String {
        switch self {
        case .tonight: return "Ce soir"
        case .tomorrowMorning: return "Demain matin"
        case .tomorrowAfternoon: return "Demain aprèm"
        case .tomorrowEvening: return "Demain soir"
        }
    }

    var dayOffset: Int { self == .tonight ? 0 : 1 }

    /// Minutes depuis minuit (heure du club).
    var range: ClosedRange<Int> {
        switch self {
        case .tonight, .tomorrowEvening: return (17 * 60)...(23 * 60 + 30)
        case .tomorrowMorning: return (7 * 60)...(11 * 60 + 59)
        case .tomorrowAfternoon: return (12 * 60)...(16 * 60 + 59)
        }
    }

    /// Le moment le plus utile maintenant : ce soir avant 21 h, sinon demain soir.
    static var suggested: FreePeriod {
        Calendar.current.component(.hour, from: Date()) < 21 ? .tonight : .tomorrowEvening
    }
}

@MainActor
final class FreeSlotsModel: ObservableObject {
    static let shared = FreeSlotsModel()

    /// Créneaux d'aujourd'hui et de demain, par club (identifiant du club de la carte).
    @Published private(set) var slots: [String: [BookingSlot]] = [:]
    @Published private(set) var clubs: [Club] = []
    @Published private(set) var status = ""
    @Published private(set) var loading = false
    private var lastLoad: Date? = nil
    private var task: Task<Void, Never>? = nil

    private var anybuddyRead: [String: Date] = [:]     // « slug|jour » → dernière lecture
    @Published private(set) var lastError: String? = nil

    private func missKey(_ club: Club) -> String { "playtomicMiss." + club.id }

    /// Clubs à lire : favoris d'abord, puis les plus proches ; ceux qu'on sait lire en premier.
    func candidates(directory: ClubDirectory, favorites: [Club], location: CLLocation?) -> [Club] {
        var list: [Club] = favorites.map { directory.club(id: $0.id) ?? $0 }
        if let location {
            for c in directory.nearest(to: location, limit: 14, maxKm: 30) where !list.contains(where: { $0.id == c.id }) { list.append(c) }
        }
        // Reconnaissance Anybuddy immédiate (liste publique de leurs clubs, embarquée).
        list = list.map { c in
            guard c.playtomicTenantID == nil, c.anybuddySlug == nil, c.backendID == nil, let slug = AnybuddyDirectory.match(c) else { return c }
            var linked = c
            linked.anybuddySlug = slug
            directory.linkAnybuddy(clubID: c.id, slug: slug)
            return linked
        }
        let recentMiss: (Club) -> Bool = { c in
            guard let d = UserDefaults.standard.object(forKey: "playtomicMiss." + c.id) as? Date else { return false }
            return d.timeIntervalSinceNow > -7 * 86_400
        }
        list = list.filter { $0.playtomicTenantID != nil || $0.backendID != nil || $0.anybuddySlug != nil || !recentMiss($0) }
        func rank(_ c: Club) -> Int { c.playtomicTenantID != nil ? 0 : (c.anybuddySlug != nil ? 1 : (c.backendID != nil ? 1 : 2)) }
        return Array(list.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element).prefix(10))
    }

    func refresh(directory: ClubDirectory, favorites: [Club], location: CLLocation?, period: FreePeriod, force: Bool = false) {
        if ShotMode.current != nil { installDemo(); return }
        let fresh = !force && (lastLoad?.timeIntervalSinceNow ?? -1000) > -90 && !slots.isEmpty
        task?.cancel()
        let list = fresh ? clubs : candidates(directory: directory, favorites: favorites, location: location)
        clubs = list
        guard !list.isEmpty else { status = location == nil ? "" : "Aucun club proche à lire."; return }
        if force { anybuddyRead = [:] }
        loading = true
        status = "Lecture des créneaux…"
        task = Task {
            // 1) Playtomic et clubs PadelUp déjà reliés : lus en parallèle (aujourd'hui et demain).
            if !fresh {
                await withTaskGroup(of: (String, [BookingSlot], String?).self) { group in
                    for club in list where club.playtomicTenantID != nil || club.backendID != nil {
                        group.addTask { await Self.read(club) }
                    }
                    for await (id, s, err) in group {
                        self.slots[id] = s
                        if let err { self.lastError = err }
                    }
                }
            }
            // 2) Anybuddy : la page de chaque club, pour le jour du moment choisi (une page à la fois).
            await self.readAnybuddy(list, period: period)
            // 3) Clubs pas encore reliés : retrouvés sur Playtomic un par un (la première fois seulement).
            if !fresh {
                for var club in list where club.playtomicTenantID == nil && club.backendID == nil && club.anybuddySlug == nil {
                    if Task.isCancelled { break }
                    self.status = "Recherche de \(club.displayName) sur Playtomic…"
                    if let match = await PlaytomicWeb.match(for: club) {
                        club.playtomicTenantID = match.id
                        club.playtomicSlug = match.slug
                        if club.timezone == nil { club.timezone = club.longitude > 8 && club.latitude < 38 ? "Africa/Tunis" : "Europe/Paris" }
                        directory.link(clubID: club.id, tenantID: match.id, slug: match.slug, timezone: club.timezone)
                        if let i = self.clubs.firstIndex(where: { $0.id == club.id }) { self.clubs[i] = club }
                        let (_, s, err) = await Self.read(club)
                        self.slots[club.id] = s
                        if let err { self.lastError = err }
                    } else {
                        UserDefaults.standard.set(Date(), forKey: self.missKey(club))
                    }
                }
                self.lastLoad = Date()
            }
            self.loading = false
            self.status = ""
        }
    }

    private func readAnybuddy(_ list: [Club], period: FreePeriod) async {
        guard let day = Calendar.current.date(byAdding: .day, value: period.dayOffset, to: Calendar.current.startOfDay(for: Date())) else { return }
        let dayKey = FR.string(day, "yyyy-MM-dd")
        for club in list where club.playtomicTenantID == nil {
            guard let slug = club.anybuddySlug, !Task.isCancelled else { continue }
            let key = slug + "|" + dayKey
            if let last = anybuddyRead[key], last.timeIntervalSinceNow > -180 { continue }
            status = "Lecture de \(club.displayName) sur Anybuddy…"
            do {
                let found = try await AnybuddyAPI.slots(slug: slug, day: day)
                let others = (slots[club.id] ?? []).filter { $0.localDayKey != dayKey }
                slots[club.id] = others + found
                anybuddyRead[key] = Date()
            } catch {
                lastError = error.localizedDescription
                if error.localizedDescription.contains("vérification") { break }   // Anybuddy demande une vérification : on s'arrête
            }
        }
    }

    private static func read(_ club: Club) async -> (String, [BookingSlot], String?) {
        var out: [BookingSlot] = []
        var err: String? = nil
        for offset in 0...1 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) else { continue }
            do {
                if let tenant = club.playtomicTenantID {
                    out += try await PlaytomicWeb.slots(tenantID: tenant, day: day, timezone: club.timezone)
                } else if let id = club.backendID, ServerAPI.shared.isLoggedIn {
                    out += try await ServerAPI.shared.botSlots(provider: .padelup, clubID: String(id), day: day)
                }
            } catch {
                err = "\(club.displayName) : \(error.localizedDescription)"
            }
        }
        return (club.id, out, err)
    }

    /// Créneaux libres d'un club pour un moment, regroupés par heure.
    func groups(for club: Club, period: FreePeriod, duration: Int?) -> [SlotGroup] {
        let tz = TimeZone(identifier: club.timezone ?? "Europe/Paris") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let day = cal.date(byAdding: .day, value: period.dayOffset, to: cal.startOfDay(for: Date())) else { return [] }
        let key = FR.string(day, "yyyy-MM-dd", tz: tz)
        let list = (slots[club.id] ?? []).filter {
            $0.localDayKey == key && period.range.contains($0.minutesOfDay) && $0.start > Date().addingTimeInterval(15 * 60)
                && (duration == nil || $0.duration == duration || $0.duration == 0)
        }
        var byTime: [String: [BookingSlot]] = [:]
        for s in list { byTime[s.localTime, default: []].append(s) }
        return byTime.keys.sorted().map { SlotGroup(time: $0, slots: (byTime[$0] ?? []).sorted { ($0.price ?? 0) < ($1.price ?? 0) }) }
    }

    private func installDemo() {
        let demo = Array(ShotMode.demoClubs.prefix(3))
        clubs = demo
        for c in demo {
            let base = ShotMode.demoSlots(for: c)
            let today = base.map { s -> BookingSlot in
                var t = s
                t.start = s.start.addingTimeInterval(-86_400)
                return t
            }
            slots[c.id] = (today + base).map { s in var t = s; t.clubID = c.playtomicTenantID ?? c.id; return t }
        }
    }
}

struct FreeRow: Identifiable {
    let club: Club
    let groups: [SlotGroup]
    var id: String { club.id }
}

/// Le bloc de l'accueil.
struct FreeNowBlock: View {
    @EnvironmentObject private var directory: ClubDirectory
    @EnvironmentObject private var favorites: Favorites
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var router: Router
    @ObservedObject private var model = FreeSlotsModel.shared
    @State private var period: FreePeriod = .suggested
    @State private var duration: Int? = 90

    private var rows: [FreeRow] {
        model.clubs.compactMap { c in
            let g = model.groups(for: c, period: period, duration: duration)
            return g.isEmpty ? nil : FreeRow(club: c, groups: g)
        }
    }

    var body: some View {
        Block(title: "Libre près de toi", meta: model.loading ? nil : (rows.isEmpty ? nil : "\(rows.count) club\(rows.count > 1 ? "s" : "")"),
              live: !model.loading, actionTitle: "Actualiser", action: { reload(force: true) }) {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FreePeriod.allCases) { p in
                            Button { withAnimation(.snappy(duration: 0.2)) { period = p } } label: { Chip(text: p.label, active: period == p) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                InlinePicker(options: [(Int?.none, "Toutes"), (Int?.some(60), "60 min"), (Int?.some(90), "90 min"), (Int?.some(120), "120 min")],
                             selection: $duration)
                if model.loading && rows.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(model.status).font(UI.callout()).foregroundStyle(UI.muted).lineLimit(2)
                    }
                    .padding(.vertical, 6)
                } else if location.location == nil && favorites.clubs.isEmpty && ShotMode.current == nil {
                    EmptyNote(title: "Où joues-tu ?", message: "Active la localisation ou ajoute un club en favori pour voir ses créneaux libres ici.",
                              actionTitle: "Activer la localisation") { location.request() }
                } else if rows.isEmpty {
                    EmptyNote(title: "Rien de libre \(period.label.lowercased()).",
                              message: model.clubs.isEmpty ? "Aucun club lisible près de toi pour l'instant."
                                : "Dans \(model.clubs.count) club\(model.clubs.count > 1 ? "s" : "") proches. Essaie un autre moment, ou lance une résa auto : je te préviens dès qu'un créneau se libère.")
                    if let err = model.lastError {
                        Text(err).font(UI.small()).foregroundStyle(UI.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Pourquoi rien ? Lancer le diagnostic") { router.sheet = .diagnostic }.buttonStyle(LinkButtonStyle())
                }
                ForEach(rows) { row in
                    let club = row.club
                    VStack(alignment: .leading, spacing: 8) {
                        Button { router.openClub = club } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(club.displayName).font(UI.headline()).foregroundStyle(UI.ink).lineLimit(1)
                                Spacer()
                                if let d = club.distance(from: location.location) {
                                    Text(formatDistance(d)).font(UI.score(15)).foregroundStyle(UI.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(row.groups) { g in
                                    Button { book(club, g) } label: { SlotCell(group: g).frame(width: 96) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if model.loading && !rows.isEmpty {
                    Text(model.status).font(UI.small()).foregroundStyle(UI.faint)
                }
            }
        }
        .onAppear { reload(force: false) }
        .onChange(of: location.location == nil) { _, _ in reload(force: false) }
        .onChange(of: period) { _, _ in reload(force: false) }
    }

    private func reload(force: Bool) {
        model.refresh(directory: directory, favorites: favorites.clubs, location: location.location, period: period, force: force)
    }

    /// Une heure touchée : la page de réservation du club s'ouvre à la bonne date, déjà connectée.
    private func book(_ club: Club, _ g: SlotGroup) {
        // Le créneau exact de la durée choisie (sinon le premier) : la page de paiement peut s'ouvrir directement.
        let s = g.slots.first { duration == nil || $0.duration == duration } ?? g.first
        // La page s'ouvre déjà connectée, et l'assistant touche l'heure choisie et la durée à ta place.
        let target = BookingTarget(time: g.time, duration: duration ?? (s.duration > 0 ? s.duration : nil), direct: DirectPay(slot: s))
        if s.provider == .playtomic {
            let url = PlaytomicWeb.bookingURL(slug: club.playtomicSlug, tenantID: s.clubID, day: s.start, timezone: s.timezone)
            router.sheet = .booking(BookingRequest(url: url, target: target))
        } else if s.provider == .anybuddy, let url = AnybuddyAPI.clubURL(s.clubID, day: s.start) {
            router.sheet = .booking(BookingRequest(url: url, target: target))
        } else {
            router.openClub = club
        }
    }
}
