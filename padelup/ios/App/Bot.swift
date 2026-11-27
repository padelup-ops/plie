import BackgroundTasks
import Foundation
import UserNotifications

// Règle du bot : « réserve-moi le mardi entre 19 h et 21 h, 90 min, au club X ».
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

    var isExhausted: Bool { maxBookings > 0 && bookingsMade >= maxBookings }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    var summary: String {
        let names = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"]
        let days = weekdays.sorted().map { names[$0] }.joined(separator: " · ")
        let dur = durations.map { "\($0) min" }.joined(separator: " / ")
        return "\(days)  ·  \(Self.hhmm(timeFrom))–\(Self.hhmm(timeTo))  ·  \(dur)"
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

@MainActor
final class BotEngine: ObservableObject {
    static let shared = BotEngine()
    static let backgroundTaskID = "com.padelup.neo.bot"

    @Published var rules: [BotRule] = [] { didSet { save() } }
    @Published var log: [BotLogEntry] = [] { didSet { save() } }
    @Published private(set) var running = false
    @Published var lastRun: Date? = nil

    private var timer: Timer?
    private var loading = false

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
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let store = Store(rules: rules, log: Array(log.prefix(200)))
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: Self.storeURL, options: .atomic) }
    }

    // MARK: Cycle de vie : toutes les 60 s quand l'app est ouverte, et en arrière-plan quand iOS le permet

    func startForeground() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await BotEngine.shared.runAll() }
        }
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
        requestNotificationPermission()  // pour prévenir le joueur dès que le bot a réservé
        rules.insert(rule, at: 0)
        Task { await run(ruleID: rule.id) }
    }

    func runAll() async {
        guard !running else { return }
        running = true
        defer { running = false; lastRun = Date() }
        for rule in rules where rule.active && !rule.isExhausted && rule.serverRuleID == nil {
            await run(ruleID: rule.id)
        }
    }

    private func update(_ id: UUID, _ change: (inout BotRule) -> Void) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[i])
    }

    // MARK: Une règle : dates candidates, créneaux libres, meilleur choix, réservation

    func run(ruleID: UUID) async {
        guard let rule = rules.first(where: { $0.id == ruleID }), rule.active, !rule.isExhausted else { return }
        let tz = TimeZone(identifier: rule.timezone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        let dayKey = DateFormatter()
        dayKey.timeZone = tz
        dayKey.dateFormat = "yyyy-MM-dd"
        let days: [Date] = (0...max(0, rule.daysAhead)).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .filter { rule.weekdays.contains((cal.component(.weekday, from: $0) + 5) % 7) }
            .filter { !rule.bookedDays.contains(dayKey.string(from: $0)) }
        var candidates: [BookingSlot] = []
        do {
            for day in days {
                let slots: [BookingSlot]
                switch rule.provider {
                case .playtomic: slots = try await PlaytomicAPI.shared.slots(tenantID: rule.clubID, day: day)
                case .anybuddy: slots = try await AnybuddyAPI.slots(slug: rule.clubID, day: day)
                case .padelup: slots = try await ServerAPI.shared.botSlots(provider: .padelup, clubID: rule.clubID, day: day)
                }
                candidates += slots.filter { matches(rule, $0) }
            }
        } catch {
            update(ruleID) { $0.lastCheck = Date(); $0.lastStatus = error.localizedDescription }
            return
        }
        let prefs = rule.durations
        candidates.sort { a, b in
            let pa = prefs.firstIndex(of: a.duration) ?? prefs.count, pb = prefs.firstIndex(of: b.duration) ?? prefs.count
            return (a.localDayKey, pa, a.start, a.price ?? 0) < (b.localDayKey, pb, b.start, b.price ?? 0)
        }
        guard !candidates.isEmpty else {
            update(ruleID) { $0.lastCheck = Date(); $0.lastStatus = "Aucun créneau libre pour l'instant (\(days.count) date(s) surveillée(s))" }
            return
        }
        // Anybuddy, ou mode « me prévenir » : alerte instantanée avec le lien direct du créneau.
        if !rule.autoBook || rule.provider == .anybuddy {
            let fresh = candidates.filter { !rule.notifiedSlots.contains($0.id) }
            if let best = fresh.first {
                let url = rule.provider == .anybuddy ? AnybuddyAPI.clubURL(rule.clubID)?.absoluteString : nil
                record(.found, rule: rule, slot: best, message: "Créneau libre repéré", url: url)
                notify(title: "Créneau libre 🎾 \(rule.clubName)", body: "\(Self.when(best)) · \(best.duration) min · \(best.courtName) \(best.priceLabel)")
                update(ruleID) { $0.notifiedSlots.append(best.id); $0.notifiedSlots = Array($0.notifiedSlots.suffix(200)) }
            }
            update(ruleID) { $0.lastCheck = Date(); $0.lastStatus = "\(candidates.count) créneau(x) libre(s) repéré(s)" }
            return
        }
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

    private func matches(_ rule: BotRule, _ slot: BookingSlot) -> Bool {
        let m = slot.minutesOfDay
        guard m >= rule.timeFrom, m <= rule.timeTo else { return false }
        guard rule.durations.isEmpty || rule.durations.contains(slot.duration) else { return false }
        if rule.court == .indoor, slot.indoor == false { return false }
        if rule.court == .outdoor, slot.indoor == true { return false }
        if let max = rule.maxPrice, let p = slot.price, p > max { return false }
        return slot.start > Date().addingTimeInterval(Double(rule.minNoticeMinutes) * 60)
    }

    /// Réservation d'un créneau (bouton « Le bot réserve » ou règle automatique) : tout le parcours est fait ici.
    @discardableResult
    func book(_ slot: BookingSlot, clubName: String, ruleID: UUID? = nil) async -> BookingOutcome {
        let outcome: BookingOutcome
        do {
            switch slot.provider {
            case .playtomic:
                outcome = try await PlaytomicAPI.shared.book(slot)
            case .anybuddy:
                if ServerAPI.shared.botServerEnabled {
                    outcome = try await ServerAPI.shared.botBook(slot, clubName: clubName)
                } else {
                    outcome = BookingOutcome(status: .needsAction, message: "Termine en un geste sur Anybuddy (carte enregistrée).",
                                             actionURL: AnybuddyAPI.clubURL(slot.clubID))
                }
            case .padelup:
                outcome = try await ServerAPI.shared.botBook(slot, clubName: clubName)
            }
        } catch PlaytomicError.slotTaken {
            outcome = BookingOutcome(status: .failed, message: "Créneau pris juste avant : le bot passe au suivant.")
        } catch PlaytomicError.sessionExpired, PlaytomicError.notConnected {
            outcome = BookingOutcome(status: .authError, message: "Reconnecte ton compte \(slot.provider.name).")
        } catch {
            outcome = BookingOutcome(status: .failed, message: error.localizedDescription)
        }
        let rule = ruleID.flatMap { id in rules.first { $0.id == id } }
        switch outcome.status {
        case .booked:
            record(.booked, rule: rule, clubName: clubName, slot: slot, message: outcome.message)
            notify(title: "Le bot a réservé ✅", body: "\(clubName) · \(Self.when(slot)) · \(slot.duration) min · \(slot.courtName)")
        case .needsAction:
            record(.needsAction, rule: rule, clubName: clubName, slot: slot, message: outcome.message, url: outcome.actionURL?.absoluteString)
            notify(title: "Le bot a besoin de toi", body: "\(clubName) · \(Self.when(slot)) : \(outcome.message)")
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = slot.timeZoneValue
        f.dateFormat = "EEEE d MMM 'à' HH:mm"
        return f.string(from: slot.start)
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
