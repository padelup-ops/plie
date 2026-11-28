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

    private func missKey(_ club: Club) -> String { "playtomicMiss." + club.id }

    /// Clubs à lire : favoris d'abord, puis les plus proches ; ceux qu'on sait lire en premier.
    func candidates(directory: ClubDirectory, favorites: [Club], location: CLLocation?) -> [Club] {
        var list: [Club] = favorites.map { directory.club(id: $0.id) ?? $0 }
        if let location {
            for c in directory.nearest(to: location, limit: 14, maxKm: 30) where !list.contains(where: { $0.id == c.id }) { list.append(c) }
        }
        let recentMiss: (Club) -> Bool = { c in
            guard let d = UserDefaults.standard.object(forKey: "playtomicMiss." + c.id) as? Date else { return false }
            return d.timeIntervalSinceNow > -7 * 86_400
        }
        list = list.filter { $0.playtomicTenantID != nil || $0.backendID != nil || ($0.anybuddySlug == nil && !recentMiss($0)) }
        return Array(list.sorted { ($0.playtomicTenantID != nil ? 0 : 1) < ($1.playtomicTenantID != nil ? 0 : 1) }.prefix(10))
    }

    func refresh(directory: ClubDirectory, favorites: [Club], location: CLLocation?, force: Bool = false) {
        if ShotMode.current != nil { installDemo(); return }
        if !force, let lastLoad, lastLoad.timeIntervalSinceNow > -90, !slots.isEmpty { return }
        task?.cancel()
        let list = candidates(directory: directory, favorites: favorites, location: location)
        clubs = list
        guard !list.isEmpty else { status = location == nil ? "" : "Aucun club proche à lire."; return }
        loading = true
        status = "Lecture des créneaux…"
        task = Task {
            // Clubs déjà reliés : lus tout de suite, en parallèle (deux jours chacun).
            await withTaskGroup(of: (String, [BookingSlot]).self) { group in
                for club in list where club.playtomicTenantID != nil || club.backendID != nil {
                    group.addTask { (club.id, await Self.read(club)) }
                }
                for await (id, s) in group { self.slots[id] = s }
            }
            // Clubs pas encore reliés : retrouvés sur Playtomic un par un (quelques secondes chacun, la première fois).
            for var club in list where club.playtomicTenantID == nil && club.backendID == nil {
                if Task.isCancelled { break }
                self.status = "Recherche de \(club.displayName) sur Playtomic…"
                if let match = await PlaytomicWeb.match(for: club) {
                    club.playtomicTenantID = match.id
                    club.playtomicSlug = match.slug
                    if club.timezone == nil { club.timezone = club.longitude > 8 && club.latitude < 38 ? "Africa/Tunis" : "Europe/Paris" }
                    directory.link(clubID: club.id, tenantID: match.id, slug: match.slug, timezone: club.timezone)
                    if let i = self.clubs.firstIndex(where: { $0.id == club.id }) { self.clubs[i] = club }
                    self.slots[club.id] = await Self.read(club)
                } else {
                    UserDefaults.standard.set(Date(), forKey: self.missKey(club))
                }
            }
            self.loading = false
            self.lastLoad = Date()
            self.status = ""
        }
    }

    private static func read(_ club: Club) async -> [BookingSlot] {
        var out: [BookingSlot] = []
        for offset in 0...1 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) else { continue }
            if let tenant = club.playtomicTenantID {
                out += (try? await PlaytomicWeb.slots(tenantID: tenant, day: day, timezone: club.timezone)) ?? []
            } else if let id = club.backendID, await ServerAPI.shared.isLoggedIn {
                out += (try? await ServerAPI.shared.botSlots(provider: .padelup, clubID: String(id), day: day)) ?? []
            }
        }
        return out
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
                && (duration == nil || $0.duration == duration)
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
                                : "Dans \(model.clubs.count) club\(model.clubs.count > 1 ? "s" : "") proches. Essaie un autre moment, ou lance un bot : il te prévient dès qu'un créneau se libère.")
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
    }

    private func reload(force: Bool) {
        model.refresh(directory: directory, favorites: favorites.clubs, location: location.location, force: force)
    }

    /// Une heure touchée : la page de réservation du club s'ouvre à la bonne date, déjà connectée.
    private func book(_ club: Club, _ g: SlotGroup) {
        let s = g.first
        if s.provider == .playtomic {
            router.sheet = .web(PlaytomicWeb.bookingURL(slug: club.playtomicSlug, tenantID: s.clubID, day: s.start, timezone: s.timezone))
        } else {
            router.openClub = club
        }
    }
}
