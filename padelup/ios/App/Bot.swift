import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

// Règle du bot : « mardi et jeudi entre 19 h et 21 h, 90 min, au club X ».
// Option « ouverture des réservations » (dossier Padel Sniper) : le club ouvre ses créneaux J-x à hh:mm ; le bot
// prévient une minute avant, puis scrute à l'heure pile et ouvre la page de réservation dès que le créneau apparaît.
struct BotRule: Identifiable, Codable, Hashable {
    enum Court: String, Codable, CaseIterable { case any, indoor, outdoor
        var label: String { self == .any ? "Peu importe" : (self == .indoor ? "Couvert" : "Extérieur") }
    }

    var id = UUID()
    var provider: BotProvider
    var clubID: String
    var clubName: String
    var clubCity: String = ""
    var timezone: String = TimeZone.current.identifier
    var weekdays: Set<Int> = [1]          // 0 = lundi ... 6 = dimanche
    var timeFrom: Int = 19 * 60            // minutes depuis minuit (heure du club)
    var timeTo: Int = 21 * 60
    var durations: [Int] = [90]
    var court: Court = .any
    var maxPrice: Double? = nil
    var daysAhead: Int = 7
    var minNoticeMinutes: Int = 120
    var autoBook = true
    var active = true
    var maxBookings = 1                   // 0 = sans limite (chaque semaine)
    var bookingsMade = 0
    var bookedDays: [String] = []
    var notifiedSlots: [String] = []
    var lastCheck: Date? = nil
    var lastStatus: String = "Pas encore lancé"
    var serverRuleID: Int? = nil          // règle prise en charge 24 h/24 par le serveur PadelUp
    // Ajouts (optionnels pour relire les règles déjà enregistrées)
    var clubSlug: String? = nil           // page playtomic.com/clubs/<slug>
    var releaseDays: Int? = nil           // ouverture des réservations : J-x…
    var releaseMinutes: Int? = nil        // … à hh:mm (heure du club)
    var pausedUntil: Date? = nil          // pause après un refus de la plateforme

    var isExhausted: Bool { maxBookings > 0 && bookingsMade >= maxBookings }
    var hasRelease: Bool { releaseDays != nil && releaseMinutes != nil }
    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    static let dayNames = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"]

    var daysLabel: String {
        if weekdays.count == 7 { return "tous les jours" }
        if weekdays == [0, 1, 2, 3, 4] { return "en semaine" }
        if weekdays == [5, 6] { return "le week-end" }
        return weekdays.sorted().map { Self.dayNames[$0] }.joined(separator: " · ")
    }

    var hoursLabel: String { "\(Self.hhmm(timeFrom))–\(Self.hhmm(timeTo))" }
    var durationsLabel: String { durations.sorted().map { "\($0)" }.joined(separator: "/") + " min" }
    var summary: String { "\(daysLabel)  ·  \(hoursLabel)  ·  \(durationsLabel)" }
    var releaseLabel: String? {
        guard let d = releaseDays, let m = releaseMinutes else { return nil }
        return "J-\(d) à \(Self.hhmm(m))"
    }

    var tz: TimeZone { TimeZone(identifier: timezone) ?? .current }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    /// Prochaines ouvertures de réservation : (moment d'ouverture, jour visé).
    func upcomingReleases(from now: Date = Date(), limit: Int = 6) -> [(release: Date, day: Date)] {
        guard let d = releaseDays, let m = releaseMinutes else { return [] }
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let key = DateFormatter()
        key.timeZone = tz
        key.dateFormat = "yyyy-MM-dd"
        var out: [(release: Date, day: Date)] = []
        for offset in 0...(d + 21) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains((cal.component(.weekday, from: day) + 5) % 7),
                  !bookedDays.contains(key.string(from: day)),
                  let releaseDay = cal.date(byAdding: .day, value: -d, to: day) else { continue }
            let release = releaseDay.addingTimeInterval(Double(m) * 60)
            if release > now.addingTimeInterval(-60) { out.append((release: release, day: day)) }
            if out.count >= limit { break }
        }
        return out
    }
}

struct BotLogEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case booked, found, needsAction, failed, info }
    var id = UUID()
    var date = Date()
    var kind: Kind
    var clubName: String
    var message: String
    var slotStart: Date? = nil
    var court: String = ""
    var price: String = ""
    var actionURL: String? = nil
}

/// Ce que l'assistant de réservation doit choisir sur la page (heure, durée).
struct BookingTarget: Hashable {
    let time: String        // « 19:30 »
    let duration: Int?      // 90, ou nil si la durée se choisit sur la page

    init(time: String, duration: Int?) {
        self.time = time
        self.duration = (duration ?? 0) > 0 ? duration : nil
    }

    init(slot: BookingSlot) { self.init(time: slot.localTime, duration: slot.duration) }
}

/// Une page de réservation à ouvrir, avec l'assistant qui choisit le créneau.
struct BookingRequest: Identifiable, Hashable {
    let url: URL
    let target: BookingTarget?
    var id: String { url.absoluteString + "|" + (target?.time ?? "") }
}

/// Une ouverture de réservation suivie en direct (compte à rebours, puis scan rapide).
struct Snipe: Equatable {
    enum Phase: Equatable { case countdown, scanning(Int), found(String), missed, blocked }
    var ruleID: UUID
    var clubName: String
    var release: Date
    var day: Date
    var timezone: String
    var phase: Phase = .countdown
}

@MainActor
final class BotEngine: ObservableObject {
    static let shared = BotEngine()
    static let backgroundTaskID = "com.padelup.neo.bot"

    @Published var rules: [BotRule] = [] { didSet { save(); rescheduleAlarmsIfNeeded() } }
    @Published var log: [BotLogEntry] = [] { didSet { save() } }
    @Published private(set) var running = false
    @Published var lastRun: Date? = nil
    @Published var snipe: Snipe? = nil
    /// Page de réservation à ouvrir dans l'app (connectée), avec l'assistant : la vue racine la présente.
    @Published var openBooking: BookingRequest? = nil

    private var timer: Timer?
    private var loading = false
    private var snipeTask: Task<Void, Never>?
    private var alarmSignature = ""

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bot.json")
    }

    private struct Store: Codable { var rules: [BotRule]; var log: [BotLogEntry] }

    init() {
        loading = true
        if let data = try? Data(contentsOf: Self.storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) {
            rules = store.rules
            log = store.log
        }
        // Résas auto créées avec un club Playtomic mal reconnu (ancienne comparaison des noms) : mises en pause.
        if UserDefaults.standard.integer(forKey: "playtomicRuleCheck") < 2 {
            for i in rules.indices where rules[i].provider == .playtomic {
                guard let slug = rules[i].clubSlug, !slug.isEmpty,
                      !ClubDirectory.similar(rules[i].clubName, slug.replacingOccurrences(of: "-", with: " ")) else { continue }
                rules[i].active = false
                rules[i].lastStatus = "Club à revérifier : Playtomic m'a donné « \(slug.replacingOccurrences(of: "-", with: " ").capitalized) ». Supprime cette résa et reprogramme-la."
            }
            UserDefaults.standard.set(2, forKey: "playtomicRuleCheck")
        }
        loading = false
        save()
    }

    private func save() {
        guard !loading, ShotMode.current == nil else { return }
        let store = Store(rules: rules, log: Array(log.prefix(200)))
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: Self.storeURL, options: .atomic) }
    }

    // MARK: Cycle de vie : toutes les 60 s quand l'app est ouverte, et en arrière-plan quand iOS le permet

    func startForeground() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                BotEngine.shared.armImminentRelease()
                if (BotEngine.shared.lastRun ?? .distantPast).timeIntervalSinceNow < -25 { await BotEngine.shared.runAll() }
            }
        }
        armImminentRelease()
        Task { await runAll() }
    }

    func stopForeground() {
        timer?.invalidate()
        timer = nil
        scheduleBackground()
    }

    func scheduleBackground() {
        guard rules.contains(where: { $0.active && $0.serverRuleID == nil }) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func addRule(_ rule: BotRule) {
        requestNotificationPermission()
        rules.insert(rule, at: 0)
        Task { await run(ruleID: rule.id) }
    }

    func runAll() async {
        guard !running else { return }
        running = true
        defer { running = false; lastRun = Date() }
        for rule in rules where rule.active && !rule.isExhausted && !rule.isPaused && rule.serverRuleID == nil {
            await run(ruleID: rule.id)
        }
    }

    private func update(_ id: UUID, _ change: (inout BotRule) -> Void) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[i])
    }

    // MARK: Lecture des créneaux

    private func fetchSlots(_ rule: BotRule, day: Date) async throws -> [BookingSlot] {
        switch rule.provider {
        case .playtomic: return try await PlaytomicWeb.slots(tenantID: rule.clubID, day: day, timezone: rule.timezone)
        case .anybuddy: return try await AnybuddyAPI.slots(slug: rule.clubID, day: day)
        case .padelup: return try await ServerAPI.shared.botSlots(provider: .padelup, clubID: rule.clubID, day: day)
        }
    }

    /// Page où le joueur termine la réservation (déjà connecté, à la bonne date).
    func actionURL(for slot: BookingSlot, slug: String?) -> URL? {
        switch slot.provider {
        case .playtomic: return PlaytomicWeb.bookingURL(slug: slug, tenantID: slot.clubID, day: slot.start, timezone: slot.timezone)
        case .anybuddy: return AnybuddyAPI.clubURL(slot.clubID, day: slot.start)
        case .padelup: return nil
        }
    }

    // MARK: Une règle : dates candidates, créneaux libres, meilleur choix, réservation

    func run(ruleID: UUID, force: Bool = false) async {
        guard let rule = rules.first(where: { $0.id == ruleID }), rule.active, !rule.isExhausted, !rule.isPaused else { return }
        // Anybuddy : lecture de la page du club (une page à la fois) ; pas plus d'une fois toutes les 10 minutes.
        if rule.provider == .anybuddy, let last = rule.lastCheck, last.timeIntervalSinceNow > -600, !force { return }
        let cal = rule.calendar
        let today = cal.startOfDay(for: Date())
        let dayKey = DateFormatter()
        dayKey.timeZone = rule.tz
        dayKey.dateFormat = "yyyy-MM-dd"
        let days: [Date] = (0...max(0, rule.daysAhead)).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .filter { rule.weekdays.contains((cal.component(.weekday, from: $0) + 5) % 7) }
            .filter { !rule.bookedDays.contains(dayKey.string(from: $0)) }
        var candidates: [BookingSlot] = []
        // Anybuddy se lit page par page : les trois prochaines dates suffisent.
        let toRead = rule.provider == .anybuddy ? Array(days.prefix(3)) : days
        do {
            for day in toRead {
                candidates += try await fetchSlots(rule, day: day).filter { matches(rule, $0) }
            }
        } catch PlaytomicError.blockedByPlaytomic {
            // Règle du dossier : on ne contourne jamais, on s'arrête.
            update(ruleID) { $0.lastCheck = Date(); $0.pausedUntil = Date().addingTimeInterval(3600); $0.lastStatus = "Playtomic limite les lectures : je fais une pause d'une heure." }
            return
        } catch {
            update(ruleID) { $0.lastCheck = Date(); $0.lastStatus = error.localizedDescription }
            return
        }
        candidates.sort(by: preference(rule))
        guard !candidates.isEmpty else {
            update(ruleID) {
                $0.lastCheck = Date()
                $0.lastStatus = days.isEmpty ? "Aucune date à surveiller" : "Je guette… rien de libre pour l'instant."
            }
            return
        }
        // Playtomic et Anybuddy : le paiement se fait sur leur page. Le bot repère, prévient et ouvre la page déjà connectée.
        if !rule.autoBook || rule.provider != .padelup {
            let fresh = candidates.filter { !rule.notifiedSlots.contains($0.id) }
            if let best = fresh.first {
                let url = actionURL(for: best, slug: rule.clubSlug)
                let target = BookingTarget(slot: best)
                record(.found, rule: rule, slot: best, message: "Libre · \(best.duration > 0 ? "\(best.duration) min" : "durée au choix") · \(best.courtName)", url: url?.absoluteString)
                notify(title: "Créneau libre · \(rule.clubName)", body: "\(Self.when(best)) · \(best.courtName) \(best.priceLabel). Touche : l'assistant prépare la réservation.",
                       url: url, target: target)
                update(ruleID) { $0.notifiedSlots.append(best.id); $0.notifiedSlots = Array($0.notifiedSlots.suffix(200)) }
                // « Réserver tout seul » : si l'app est ouverte, la page s'ouvre et l'assistant choisit le créneau.
                if rule.autoBook, let url, UIApplication.shared.applicationState == .active, openBooking == nil {
                    openBooking = BookingRequest(url: url, target: target)
                }
            }
            update(ruleID) { $0.lastCheck = Date(); $0.lastStatus = "Trouvé ! \(candidates.count) créneau\(candidates.count > 1 ? "x" : "") libre\(candidates.count > 1 ? "s" : "")." }
            return
        }
        // Clubs partenaires PadelUp : réservation directe.
        var tries = 0
        var booked: Set<String> = Set(rule.bookedDays)
        for slot in candidates where !booked.contains(slot.localDayKey) {
            if tries >= 3 { break }
            if let r = rules.first(where: { $0.id == ruleID }), r.isExhausted { break }
            tries += 1
            let outcome = await book(slot, clubName: rule.clubName, ruleID: ruleID)
            if outcome.status == .booked {
                booked.insert(slot.localDayKey)
                update(ruleID) {
                    $0.bookedDays.append(slot.localDayKey)
                    $0.bookingsMade += 1
                    if $0.isExhausted { $0.active = false }
                    $0.lastStatus = "Réservé : \(Self.when(slot)), \(slot.courtName)"
                }
            } else if outcome.status == .needsAction || outcome.status == .authError {
                update(ruleID) { $0.lastStatus = outcome.message }
                break
            }
        }
        update(ruleID) { $0.lastCheck = Date() }
    }

    private func preference(_ rule: BotRule) -> (BookingSlot, BookingSlot) -> Bool {
        let prefs = rule.durations
        return { a, b in
            let pa = prefs.firstIndex(of: a.duration) ?? prefs.count, pb = prefs.firstIndex(of: b.duration) ?? prefs.count
            return (a.localDayKey, pa, a.start, a.price ?? 0) < (b.localDayKey, pb, b.start, b.price ?? 0)
        }
    }

    private func matches(_ rule: BotRule, _ slot: BookingSlot, minNotice: Bool = true) -> Bool {
        let m = slot.minutesOfDay
        guard m >= rule.timeFrom, m <= rule.timeTo else { return false }
        guard rule.durations.isEmpty || rule.durations.contains(slot.duration) else { return false }
        if rule.court == .indoor, slot.indoor == false { return false }
        if rule.court == .outdoor, slot.indoor == true { return false }
        if let max = rule.maxPrice, let p = slot.price, p > max { return false }
        return !minNotice || slot.start > Date().addingTimeInterval(Double(rule.minNoticeMinutes) * 60)
    }

    /// Réservation d'un créneau (bouton « Réserver » d'une fiche club ou règle automatique).
    @discardableResult
    func book(_ slot: BookingSlot, clubName: String, slug: String? = nil, ruleID: UUID? = nil) async -> BookingOutcome {
        let outcome: BookingOutcome
        do {
            switch slot.provider {
            case .playtomic:
                outcome = BookingOutcome(status: .needsAction, message: "Termine sur Playtomic, déjà connecté.",
                                         actionURL: actionURL(for: slot, slug: slug))
            case .anybuddy:
                outcome = BookingOutcome(status: .needsAction, message: "Termine sur Anybuddy, déjà connecté.",
                                         actionURL: AnybuddyAPI.clubURL(slot.clubID, day: slot.start))
            case .padelup:
                outcome = try await ServerAPI.shared.botBook(slot, clubName: clubName)
            }
        } catch {
            outcome = BookingOutcome(status: .failed, message: error.localizedDescription)
        }
        let rule = ruleID.flatMap { id in rules.first { $0.id == id } }
        switch outcome.status {
        case .booked:
            record(.booked, rule: rule, clubName: clubName, slot: slot, message: outcome.message)
            notify(title: "Réservé · \(clubName)", body: "\(Self.when(slot)) · \(slot.duration) min · \(slot.courtName)", url: nil, target: nil)
        case .needsAction:
            if ruleID != nil {
                record(.needsAction, rule: rule, clubName: clubName, slot: slot, message: outcome.message, url: outcome.actionURL?.absoluteString)
                notify(title: "À toi de jouer · \(clubName)", body: "\(Self.when(slot)) : \(outcome.message)", url: outcome.actionURL, target: BookingTarget(slot: slot))
            }
        case .authError, .failed:
            record(.failed, rule: rule, clubName: clubName, slot: slot, message: outcome.message)
        }
        return outcome
    }

    private func record(_ kind: BotLogEntry.Kind, rule: BotRule?, clubName: String? = nil, slot: BookingSlot, message: String, url: String? = nil) {
        log.insert(BotLogEntry(kind: kind, clubName: clubName ?? rule?.clubName ?? "", message: message, slotStart: slot.start,
                               court: slot.courtName, price: slot.priceLabel, actionURL: url), at: 0)
        if log.count > 200 { log = Array(log.prefix(200)) }
    }

    static func when(_ slot: BookingSlot) -> String {
        FR.string(slot.start, "EEEE d MMM 'à' HH:mm", tz: slot.timeZoneValue)
    }

    // MARK: Ouverture des réservations (mode « sniper »)

    /// Prochaine ouverture toutes règles confondues.
    var nextRelease: (rule: BotRule, release: Date, day: Date)? {
        rules.filter { $0.active && !$0.isExhausted && $0.hasRelease }
            .compactMap { r -> (rule: BotRule, release: Date, day: Date)? in
                guard let next = r.upcomingReleases(limit: 1).first else { return nil }
                return (rule: r, release: next.release, day: next.day)
            }
            .min { $0.release < $1.release }
    }

    /// Si une ouverture tombe dans les 3 prochaines minutes et que l'app est ouverte : compte à rebours puis scan.
    func armImminentRelease() {
        guard snipe == nil || snipe?.phase == .missed || snipe?.phase == .blocked || isFoundPhase, ShotMode.current == nil,
              let next = nextRelease, next.release.timeIntervalSinceNow < 180, next.release.timeIntervalSinceNow > -30 else { return }
        if let s = snipe, s.ruleID == next.rule.id, s.release == next.release { return }
        startSnipe(rule: next.rule, release: next.release, day: next.day)
    }

    private var isFoundPhase: Bool { if case .found = snipe?.phase { return true }; return false }

    func startSnipe(rule: BotRule, release: Date, day: Date) {
        snipeTask?.cancel()
        snipe = Snipe(ruleID: rule.id, clubName: rule.clubName, release: release, day: day, timezone: rule.timezone)
        snipeTask = Task { [weak self] in
            // Attendre l'heure pile (on commence 300 ms avant pour absorber la latence).
            let wait = release.timeIntervalSinceNow - 0.3
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            let start = Date()
            var attempt = 0
            // Cadence prudente, depuis l'iPhone du joueur : 1 lecture/s pendant 10 s, puis toutes les 3 s jusqu'à 45 s.
            while !Task.isCancelled, Date().timeIntervalSince(start) < 45 {
                attempt += 1
                self.snipe?.phase = .scanning(attempt)
                guard let current = self.rules.first(where: { $0.id == rule.id }) else { return }
                do {
                    let found = try await self.fetchSlots(current, day: day).filter { self.matches(current, $0, minNotice: false) }
                        .sorted(by: self.preference(current))
                    if let best = found.first {
                        let url = self.actionURL(for: best, slug: current.clubSlug)
                        self.snipe?.phase = .found(Self.when(best) + " · " + best.courtName)
                        self.record(.found, rule: current, slot: best, message: "Ouvert à l'instant · \(best.duration) min", url: url?.absoluteString)
                        self.update(rule.id) { $0.notifiedSlots.append(best.id); $0.lastStatus = "Ouverture : \(Self.when(best)) repéré" }
                        self.notify(title: "C'est ouvert · \(current.clubName)", body: "\(Self.when(best)) · \(best.courtName). Touche pour réserver.",
                                    url: url, target: BookingTarget(slot: best))
                        if let url { self.openBooking = BookingRequest(url: url, target: BookingTarget(slot: best)) }
                        return
                    }
                } catch PlaytomicError.blockedByPlaytomic {
                    self.snipe?.phase = .blocked
                    self.update(rule.id) { $0.lastStatus = "Playtomic limite les lectures : je me suis arrêté." }
                    return
                } catch {
                    // Erreur réseau passagère : on continue à la cadence prévue.
                }
                let elapsed = Date().timeIntervalSince(start)
                try? await Task.sleep(nanoseconds: elapsed < 10 ? 1_000_000_000 : 3_000_000_000)
            }
            if !Task.isCancelled {
                self.snipe?.phase = .missed
                self.update(rule.id) { $0.lastStatus = "Rien à l'ouverture. Je continue de guetter." }
            }
        }
    }

    func cancelSnipe() {
        snipeTask?.cancel()
        snipeTask = nil
        snipe = nil
    }

    /// Alarmes locales : une minute avant chaque ouverture (iOS ne laisse pas une app tourner à la seconde en veille).
    private func rescheduleAlarmsIfNeeded() {
        guard !loading, ShotMode.current == nil else { return }
        var releases: [(BotRule, Date, Date)] = []
        for r in rules where r.active && !r.isExhausted {
            for next in r.upcomingReleases(limit: 4) { releases.append((r, next.release, next.day)) }
        }
        let signature = releases.map { "\($0.0.id):\(Int($0.1.timeIntervalSince1970))" }.sorted().joined(separator: ",")
        guard signature != alarmSignature else { return }
        alarmSignature = signature
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("release-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for (rule, release, day) in releases.prefix(48) {
                let fire = release.addingTimeInterval(-60)
                guard fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Ouverture dans 1 minute · \(rule.clubName)"
                content.body = "Les créneaux du \(FR.string(day, "EEEE d MMM", tz: rule.tz)) ouvrent à \(FR.time(release, tz: rule.tz)). Ouvre PadelUp : je suis prêt."
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let request = UNNotificationRequest(identifier: "release-\(rule.id.uuidString)-\(Int(release.timeIntervalSince1970))",
                                                    content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                center.add(request)
            }
        }
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(title: String, body: String, url: URL?, target: BookingTarget?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            var info: [String: Any] = ["url": url.absoluteString]
            if let target { info["time"] = target.time; info["duration"] = target.duration ?? 0 }
            content.userInfo = info
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
