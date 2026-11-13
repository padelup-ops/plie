import Foundation
import Security
import SwiftUI

// MARK: - Les chiffres de Clapet
//
// Partagés entre l'app et ses widgets dans le trousseau (un groupe de trousseau commun aux deux) :
// pas besoin de groupe d'app à déclarer chez Apple.

/// Une ouverture : quand elle a commencé, et combien de secondes le Duo est resté ouvert.
struct OpenSession: Codable, Equatable {
    var t: Date
    var s: Double
}

/// Une période de repos.
struct RestSpan: Codable, Equatable {
    var a: Date
    var b: Date
}

struct DayCount: Codable, Equatable {
    var closes = 0
    var opens = 0
    /// Temps passé ouvert ce jour-là, en secondes.
    var openSeconds: Double = 0
    /// Coups d'œil : ouvert puis refermé en moins de 10 secondes.
    var peeks = 0
    /// La plus longue pause (téléphone fermé), en secondes.
    var longestBreak: Double = 0
    /// Ouvertures évitées : après la pause de Foldly, le téléphone a été refermé.
    var resisted = 0
    /// Téléphone posé : le temps passé fermé, en secondes, et les plantes qui ont poussé (une toutes les 25 min d'affilée).
    var downSeconds: Double = 0
    var plants = 0
    /// Temps ouvert « au repos » (Sommeil, via le raccourci clapet://repos), en secondes. Inclus dans openSeconds.
    var restSeconds: Double = 0

    init(closes: Int = 0, opens: Int = 0, openSeconds: Double = 0, peeks: Int = 0, longestBreak: Double = 0) {
        self.closes = closes
        self.opens = opens
        self.openSeconds = openSeconds
        self.peeks = peeks
        self.longestBreak = longestBreak
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closes = try c.decodeIfPresent(Int.self, forKey: .closes) ?? 0
        opens = try c.decodeIfPresent(Int.self, forKey: .opens) ?? 0
        openSeconds = try c.decodeIfPresent(Double.self, forKey: .openSeconds) ?? 0
        peeks = try c.decodeIfPresent(Int.self, forKey: .peeks) ?? 0
        longestBreak = try c.decodeIfPresent(Double.self, forKey: .longestBreak) ?? 0
        resisted = try c.decodeIfPresent(Int.self, forKey: .resisted) ?? 0
        downSeconds = try c.decodeIfPresent(Double.self, forKey: .downSeconds) ?? 0
        plants = try c.decodeIfPresent(Int.self, forKey: .plants) ?? 0
        restSeconds = try c.decodeIfPresent(Double.self, forKey: .restSeconds) ?? 0
    }
}

/// « Pourquoi tu l'ouvres ? » : la raison donnée en un toucher quand on déplie le Duo (Foldly+).
enum WhyReason: Int, CaseIterable, Codable {
    case notification, boredom, work, someone

    var emoji: String {
        switch self {
        case .notification: return "🔔"
        case .boredom: return "😴"
        case .work: return "💼"
        case .someone: return "❤️"
        }
    }

    /// L'icône (SF Symbols) affichée dans l'app ; l'emoji reste pour les notifications.
    var symbol: String {
        switch self {
        case .notification: return "bell"
        case .boredom: return "moon.zzz"
        case .work: return "briefcase"
        case .someone: return "person.2"
        }
    }
}

struct WhyEntry: Codable, Equatable {
    var t: Date
    var r: Int
}

/// Comment on affiche les plis. Par défaut, 1 pli = 1 ouverture + 1 fermeture.
/// Avec « chaque mouvement compte », ouvrir et fermer comptent chacun : les nombres affichés
/// sont doublés (aujourd'hui, l'historique, les widgets, la montre). Les données ne changent pas,
/// et les classements Game Center restent en plis complets.
enum FoldUnit {
    static var eachMove = false
    static func shown(_ n: Int) -> Int { eachMove ? n * 2 : n }
}

struct ClapetStats: Codable, Equatable {
    var days: [String: DayCount] = [:]
    /// Réglage : chaque mouvement compte (voir FoldUnit).
    var eachMove = false { didSet { FoldUnit.eachMove = eachMove } }
    var goal = 100
    var totalCloses = 0
    var totalOpens = 0
    /// Nouveau Duo : le total au moment du changement (les pliages d'avant restent dans l'historique et le total).
    var duoStart = 0
    var duoSince: Date?
    /// Les pliages de ce Duo-ci (la charnière qu'on a en main).
    var duoCloses: Int { max(0, totalCloses - duoStart) }
    var firstDay: String?
    /// Les clapets d'aujourd'hui, heure par heure.
    var hourlyDay: String?
    var hourly: [Int] = Array(repeating: 0, count: 24)
    var lastClose: Date?
    /// La dernière ouverture comptée (pour reconnaître un même pli compté deux fois).
    var lastOpen: Date?
    /// Les raisons données à l'ouverture (60 derniers jours).
    var whyLog: [WhyEntry] = []
    /// Chaque ouverture vue de bout en bout (début, durée en secondes) : 90 derniers jours.
    var sessionLog: [OpenSession] = []
    /// Le record de plis en une heure.
    var recordHour = 0
    /// Foldly+ acheté (écrit par l'app, lu par les widgets).
    var plus = false
    /// Couleur des widgets (Foldly+).
    var theme = 0
    /// Apparence des widgets : 0 comme l'iPhone (clair le jour en mode auto), 1 clair, 2 sombre.
    var widgetLook = 0
    /// Parmi les 2 000 premiers : l'app a été ouverte avant le 1er décembre 2026 (badge Fondateur, couleur Or 2K).
    var founder = false
    /// Dernier pli compté par l'automatisation Raccourcis (app fermée).
    var autoLast: Date?
    /// Depuis quand le Duo est ouvert (nil : fermé, ou on ne sait pas).
    var openSince: Date?
    /// Début du repos en cours (raccourci clapet://repos), ou nil.
    var restSince: Date?
    /// Périodes de repos (mode Repos) pendant l'ouverture en cours.
    var focusSpans: [RestSpan] = []
    /// Heures de repos réglées dans l'app : le Duo ouvert pendant cette plage compte comme au repos.
    var nightOn = true
    var nightFrom = 23
    var nightTo = 7
    /// L'ouverture en cours a été vue (charnière ou automatisation), pas devinée au lancement de l'app.
    var openFromEvent = false
    /// Téléphone posé : objectif du jour (minutes), et la dernière fermeture déjà comptée.
    var downGoalMinutes = 180
    var downCredited: Date?
    /// Une plante pousse toutes les 25 minutes d'affilée téléphone fermé.
    static let plantMinutes: Double = 25
    /// Limite du jour activée ? Par défaut non : chaque journée est comparée à la moyenne.
    var goalOn = false
    /// Les plis par jour de la semaine et par heure, depuis le début : 7 × 24 cases (dimanche d'abord).
    var weekHours: [Int] = Array(repeating: 0, count: 168)
    /// Au-delà, une ouverture sans fermeture vue est oubliée (une fermeture a dû nous échapper).
    static let maxOpenSession: TimeInterval = 16 * 3600
    /// Une nuit entière passée ouvert : jusqu'à 3 h avant et après les heures de repos comptent aussi.
    static let restMargin: TimeInterval = 3 * 3600

    init() {}

    enum CodingKeys: String, CodingKey {
        case days, eachMove, goal, totalCloses, totalOpens, duoStart, duoSince, firstDay, hourlyDay, hourly, lastClose, recordHour, plus, theme, widgetLook, founder, autoLast, openSince, weekHours, openFromEvent, downGoalMinutes, downCredited, goalOn, lastOpen, whyLog, sessionLog, restSince, focusSpans, nightOn, nightFrom, nightTo
    }

    /// Chaque champ est facultatif : une ancienne sauvegarde se relit toujours.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String: DayCount].self, forKey: .days) ?? [:]
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 100
        totalCloses = try c.decodeIfPresent(Int.self, forKey: .totalCloses) ?? 0
        totalOpens = try c.decodeIfPresent(Int.self, forKey: .totalOpens) ?? 0
        duoStart = try c.decodeIfPresent(Int.self, forKey: .duoStart) ?? 0
        duoSince = try c.decodeIfPresent(Date.self, forKey: .duoSince)
        firstDay = try c.decodeIfPresent(String.self, forKey: .firstDay)
        hourlyDay = try c.decodeIfPresent(String.self, forKey: .hourlyDay)
        hourly = try c.decodeIfPresent([Int].self, forKey: .hourly) ?? Array(repeating: 0, count: 24)
        if hourly.count != 24 { hourly = Array(repeating: 0, count: 24) }
        lastClose = try c.decodeIfPresent(Date.self, forKey: .lastClose)
        lastOpen = try c.decodeIfPresent(Date.self, forKey: .lastOpen)
        whyLog = try c.decodeIfPresent([WhyEntry].self, forKey: .whyLog) ?? []
        sessionLog = try c.decodeIfPresent([OpenSession].self, forKey: .sessionLog) ?? []
        recordHour = try c.decodeIfPresent(Int.self, forKey: .recordHour) ?? 0
        plus = try c.decodeIfPresent(Bool.self, forKey: .plus) ?? false
        theme = try c.decodeIfPresent(Int.self, forKey: .theme) ?? 0
        widgetLook = try c.decodeIfPresent(Int.self, forKey: .widgetLook) ?? 0
        founder = try c.decodeIfPresent(Bool.self, forKey: .founder) ?? false
        autoLast = try c.decodeIfPresent(Date.self, forKey: .autoLast)
        openSince = try c.decodeIfPresent(Date.self, forKey: .openSince)
        restSince = try c.decodeIfPresent(Date.self, forKey: .restSince)
        focusSpans = try c.decodeIfPresent([RestSpan].self, forKey: .focusSpans) ?? []
        nightOn = try c.decodeIfPresent(Bool.self, forKey: .nightOn) ?? true
        nightFrom = min(23, max(0, try c.decodeIfPresent(Int.self, forKey: .nightFrom) ?? 23))
        nightTo = min(23, max(0, try c.decodeIfPresent(Int.self, forKey: .nightTo) ?? 7))
        openFromEvent = try c.decodeIfPresent(Bool.self, forKey: .openFromEvent) ?? false
        downGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .downGoalMinutes) ?? 180
        downCredited = try c.decodeIfPresent(Date.self, forKey: .downCredited)
        goalOn = try c.decodeIfPresent(Bool.self, forKey: .goalOn) ?? false
        eachMove = try c.decodeIfPresent(Bool.self, forKey: .eachMove) ?? false
        FoldUnit.eachMove = eachMove
        if let saved = try c.decodeIfPresent([Int].self, forKey: .weekHours), saved.count == 168 {
            weekHours = saved
        } else if let key = hourlyDay, let d = Self.date(key) {
            // Première ouverture de cette version : on part des plis d'aujourd'hui, heure par heure.
            let row = (Calendar.current.component(.weekday, from: d) - 1) * 24
            for h in 0..<24 { weekHours[row + h] = hourly[h] }
        }
    }

    /// Les clapets d'une journée, heure par heure (seulement pour aujourd'hui).
    func hours(_ date: Date = Date()) -> [Int] {
        hourlyDay == Self.key(date) ? hourly : Array(repeating: 0, count: 24)
    }

    func yesterday(_ date: Date = Date()) -> Int {
        guard let y = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return 0 }
        return day(y).closes
    }

    var level: ClapetLevel { ClapetLevel.of(totalCloses) }

    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func day(_ date: Date = Date()) -> DayCount { days[Self.key(date)] ?? DayCount() }

    /// Un « clapet », c'est une fermeture du téléphone.
    var today: Int { day().closes }

    var progress: Double { refProgress() }

    /// La limite, seulement si elle est activée (0 sinon).
    var activeLimit: Int { goalOn ? goal : 0 }

    /// La moyenne par jour, arrondie (30 derniers jours) : le repère quand la limite est désactivée. nil le premier jour.
    func averageRef(now: Date = Date()) -> Int? {
        recentAverage(now: now).map { max(1, Int($0.rounded())) }
    }

    /// Le repère du jour : la limite si elle est activée, sinon la moyenne.
    func reference(now: Date = Date()) -> Int? {
        goalOn ? (goal > 0 ? goal : nil) : averageRef(now: now)
    }

    /// Aujourd'hui comparé au repère, de 0 à 1.
    func refProgress(now: Date = Date()) -> Double {
        guard let r = reference(now: now), r > 0 else { return 0 }
        return min(1, Double(day(now).closes) / Double(r))
    }

    var best: Int { days.values.map(\.closes).max() ?? 0 }

    /// Les 7 derniers jours, du plus ancien à aujourd'hui.
    func lastWeek(now: Date = Date()) -> [(date: Date, closes: Int)] {
        (0..<7).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: now) else { return nil }
            return (d, day(d).closes)
        }
    }

    var weekTotal: Int { lastWeek().reduce(0) { $0 + $1.closes } }

    mutating func addClose(_ date: Date = Date()) {
        var d = day(date)
        d.closes += 1
        days[Self.key(date)] = d
        totalCloses += 1
        let key = Self.key(date)
        if hourlyDay != key {
            hourlyDay = key
            hourly = Array(repeating: 0, count: 24)
        }
        let h = Calendar.current.component(.hour, from: date)
        hourly[h] += 1
        recordHour = max(recordHour, hourly[h])
        let cell = (Calendar.current.component(.weekday, from: date) - 1) * 24 + h
        if weekHours.count == 168 { weekHours[cell] += 1 }
        lastClose = date
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    /// Corrige à la main le nombre de plis d'une journée (le total suit de la même différence).
    mutating func setCloses(_ value: Int, on date: Date = Date()) {
        let key = Self.key(date)
        var d = day(date)
        let target = max(0, min(100_000, value))
        let delta = target - d.closes
        guard delta != 0 else { return }
        d.closes = target
        days[key] = d
        totalCloses = max(target, totalCloses + delta)
        // Heure par heure : on ne garde que des plis vraiment vus, en retirant d'abord les plus récents.
        if delta < 0, hourlyDay == key {
            var excess = hourly.reduce(0, +) - target
            for h in stride(from: 23, through: 0, by: -1) where excess > 0 {
                let cut = min(hourly[h], excess)
                hourly[h] -= cut
                excess -= cut
            }
        }
        if firstDay == nil && target > 0 { firstDay = key }
        trim()
    }

    /// Corrige à la main le total depuis le début (jamais moins que les plis d'aujourd'hui).
    mutating func setTotal(_ value: Int, now: Date = Date()) {
        totalCloses = max(day(now).closes, min(10_000_000, value))
        if firstDay == nil && totalCloses > 0 { firstDay = Self.key(now) }
    }

    /// Ajoute ou corrige une journée passée (stats d'avant Foldly) : plis et ouvertures, les totaux suivent.
    mutating func setPastDay(closes: Int, opens: Int, on date: Date) {
        let key = Self.key(date)
        var d = day(date)
        let c = max(0, min(100_000, closes)), o = max(0, min(100_000, opens))
        totalCloses = max(0, totalCloses + c - d.closes)
        totalOpens = max(0, totalOpens + o - d.opens)
        d.closes = c
        d.opens = o
        days[key] = d
        if c > 0 || o > 0, firstDay.map({ key < $0 }) ?? true { firstDay = key }
        trim()
    }

    /// Corrige à la main le total des ouvertures depuis le début.
    mutating func setTotalOpens(_ value: Int, now: Date = Date()) {
        totalOpens = max(day(now).opens, min(10_000_000, value))
    }

    /// Une ouverture arrive alors qu'aucune fermeture n'a été vue depuis la précédente : le téléphone a forcément
    /// été fermé entre les deux (cas de l'automatisation « Ouvert » seule). On compte ce pli, juste avant l'ouverture.
    mutating func closeIfMissed(before date: Date = Date()) {
        guard let o = lastOpen, (lastClose ?? .distantPast) < o, date.timeIntervalSince(o) > 2 else { return }
        addClose(date.addingTimeInterval(-1))
    }

    mutating func addOpen(_ date: Date = Date()) {
        var d = day(date)
        d.opens += 1
        days[Self.key(date)] = d
        totalOpens += 1
        lastOpen = date
        if firstDay == nil { firstDay = Self.key(date) }
        trim()
    }

    // MARK: Pourquoi tu l'ouvres ?

    mutating func addWhy(_ reason: WhyReason, _ date: Date = Date()) {
        whyLog.append(WhyEntry(t: date, r: reason.rawValue))
        let cut = date.addingTimeInterval(-60 * 86400)
        whyLog.removeAll { $0.t < cut }
        if whyLog.count > 1500 { whyLog.removeFirst(whyLog.count - 1500) }
    }

    /// Les réponses des `days` derniers jours.
    func whyEntries(days: Int = 7, now: Date = Date()) -> [WhyEntry] {
        let cut = now.addingTimeInterval(-Double(days) * 86400)
        return whyLog.filter { $0.t >= cut && $0.t <= now }
    }

    /// Le nombre de réponses par raison, dans l'ordre de WhyReason.
    func whyCounts(days: Int = 7, now: Date = Date()) -> [Int] {
        var c = Array(repeating: 0, count: WhyReason.allCases.count)
        for e in whyEntries(days: days, now: now) where c.indices.contains(e.r) { c[e.r] += 1 }
        return c
    }

    /// L'heure de début des deux heures où cette raison revient le plus (au moins 3 réponses).
    func whyPeak(_ reason: WhyReason, days: Int = 7, now: Date = Date()) -> Int? {
        var h = Array(repeating: 0, count: 24)
        for e in whyEntries(days: days, now: now) where e.r == reason.rawValue {
            h[Calendar.current.component(.hour, from: e.t)] += 1
        }
        guard h.reduce(0, +) >= 3 else { return nil }
        var best = 0
        var bestScore = -1
        for start in 0..<24 {
            let score: Int = h[start] + h[(start + 1) % 24]
            if score > bestScore {
                bestScore = score
                best = start
            }
        }
        return best
    }

    /// Une fermeture arrive alors qu'un pli vient d'être compté, sans ouverture entre les deux :
    /// c'est le même pli, vu deux fois (l'app qui quitte l'écran puis l'automatisation Raccourcis, en retard).
    func isRepeatClose(_ date: Date = Date(), within seconds: TimeInterval = 10) -> Bool {
        guard let closed = lastClose, date.timeIntervalSince(closed) >= 0, date.timeIntervalSince(closed) < seconds else { return false }
        if let opened = lastOpen, opened > closed { return false }
        return true
    }

    // MARK: Temps ouvert

    /// Le Duo vient de s'ouvrir.
    /// `event` : une vraie ouverture (charnière ou automatisation), pas un Duo trouvé ouvert au lancement.
    mutating func startOpen(_ date: Date = Date(), event: Bool = false) {
        if let s = openSince, date.timeIntervalSince(s) < Self.maxOpenSession { return }
        openSince = date
        openFromEvent = event
    }

    /// Une vraie ouverture : la pause qui vient de finir compte pour la plus longue pause du jour.
    mutating func noteOpen(_ date: Date = Date()) {
        guard let closed = lastClose else { return }
        let gap = date.timeIntervalSince(closed)
        guard gap > 0, gap < 24 * 3600 else { return }
        var d = day(date)
        d.longestBreak = max(d.longestBreak, gap)
        days[Self.key(date)] = d
        // Téléphone posé : une seule fois par fermeture (la charnière et l'automatisation peuvent toutes deux signaler l'ouverture).
        guard downCredited != closed else { return }
        downCredited = closed
        let cal = Calendar.current
        var s = closed
        while s < date {
            let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: s)) ?? date
            let end = min(date, midnight)
            var part = day(s)
            part.downSeconds += end.timeIntervalSince(s)
            days[Self.key(s)] = part
            s = end
        }
        let grown = Int(gap / (Self.plantMinutes * 60))
        if grown > 0 {
            var e = day(date)
            e.plants += grown
            days[Self.key(date)] = e
        }
    }

    /// Le téléphone est posé (fermé) depuis cette date, d'après les automatisations. nil : ouvert, ou on ne sait pas.
    func downSince(now: Date = Date()) -> Date? {
        guard autoLast != nil, openSince == nil, let closed = lastClose,
              now.timeIntervalSince(closed) >= 0, now.timeIntervalSince(closed) < 24 * 3600 else { return nil }
        return closed
    }

    /// Temps fermé d'une journée (même chose que `downTime`).
    func closedTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval { downTime(date, now: now) }

    /// Temps posé (fermé) d'une journée, en comptant la session en cours pour aujourd'hui.
    func downTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        var t = day(date).downSeconds
        if Self.key(date) == Self.key(now), let since = downSince(now: now), downCredited != since {
            t += max(0, now.timeIntervalSince(max(since, Calendar.current.startOfDay(for: now))))
        }
        return t
    }

    /// Les plantes qui ont déjà poussé pendant la session en cours (pas encore comptées : elles le seront à l'ouverture).
    func growingPlants(now: Date = Date()) -> Int {
        guard let since = downSince(now: now), downCredited != since else { return 0 }
        return Int(now.timeIntervalSince(since) / (Self.plantMinutes * 60))
    }

    /// Les plantes d'une journée, session en cours comprise pour aujourd'hui.
    func plants(_ date: Date = Date(), now: Date = Date()) -> Int {
        day(date).plants + (Self.key(date) == Self.key(now) ? growingPlants(now: now) : 0)
    }

    /// Toutes les plantes du jardin, session en cours comprise.
    var totalPlants: Int { days.values.reduce(0) { $0 + $1.plants } + growingPlants() }

    /// Une ouverture évitée grâce à la pause.
    mutating func addResisted(_ date: Date = Date()) {
        var d = day(date)
        d.resisted += 1
        days[Self.key(date)] = d
    }

    /// Les coups d'œil (ouvert moins de 10 s) d'une journée.
    func peeks(_ date: Date = Date()) -> Int { day(date).peeks }

    /// La plus longue pause d'une journée, en comptant la pause en cours si le téléphone est fermé.
    func longestBreak(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        var best = day(date).longestBreak
        if Self.key(date) == Self.key(now), autoLast != nil, openSince == nil,
           let closed = lastClose, Self.key(closed) == Self.key(now) {
            best = max(best, now.timeIntervalSince(closed))
        }
        return best
    }

    /// Le Duo vient de se fermer : on ajoute la durée d'ouverture (répartie sur les jours traversés).
    /// `event` : une vraie fermeture ; si l'ouverture a duré moins de 10 s, c'est un coup d'œil.
    mutating func endOpen(_ date: Date = Date(), event: Bool = false) {
        guard let start = openSince else { return }
        openSince = nil
        let total = date.timeIntervalSince(start)
        if event && openFromEvent && total > 0 && total < 10 {
            var d = day(start)
            d.peeks += 1
            days[Self.key(start)] = d
        }
        let seen = event && openFromEvent
        openFromEvent = false
        guard total > 0, total < Self.maxOpenSession else { return }
        creditRest(from: start, to: date)
        // Une vraie ouverture, vue du début à la fin : on la garde pour les stats de sessions.
        if seen { addSession(start: start, seconds: total) }
        let cal = Calendar.current
        var s = start
        while s < date {
            let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: s)) ?? date
            let end = min(date, midnight)
            var d = day(s)
            d.openSeconds += end.timeIntervalSince(s)
            days[Self.key(s)] = d
            s = end
        }
    }

    mutating func addSession(start: Date, seconds: Double) {
        sessionLog.append(OpenSession(t: start, s: seconds))
        let cut = start.addingTimeInterval(-90 * 86400)
        sessionLog.removeAll { $0.t < cut }
        if sessionLog.count > 6000 { sessionLog.removeFirst(sessionLog.count - 6000) }
    }

    /// Temps ouvert d'une journée, en comptant l'ouverture en cours pour aujourd'hui.
    /// Le temps ouvert sans le repos (heures de repos, mode Repos) : c'est celui qu'on montre.
    /// Les heures d'éveil d'aujourd'hui : en dehors des heures de repos si elles sont réglées (et de jour),
    /// sinon de 7 h à 23 h.
    func awakeWindow(now: Date = Date()) -> (start: Date, end: Date) {
        let d0 = Calendar.current.startOfDay(for: now)
        var a = 7, b = 23
        if nightOn, nightTo < nightFrom, nightTo >= 4, nightFrom >= 18 { a = nightTo; b = nightFrom }
        return (d0.addingTimeInterval(Double(a) * 3600), d0.addingTimeInterval(Double(b) * 3600))
    }

    /// Ouvert et fermé pendant les heures d'éveil d'aujourd'hui seulement (la nuit ne pèse plus sur le fermé).
    func awakeSplit(now: Date = Date()) -> (open: TimeInterval, closed: TimeInterval)? {
        let w = awakeWindow(now: now)
        let end = min(now, w.end)
        let elapsed = end.timeIntervalSince(w.start)
        guard elapsed > 60 else { return nil }
        var open = 0.0
        func add(_ a: Date, _ b: Date) { open += max(0, min(b, end).timeIntervalSince(max(a, w.start))) }
        for x in sessionLog where x.t < end && x.t.addingTimeInterval(x.s) > w.start { add(x.t, x.t.addingTimeInterval(x.s)) }
        if let o = openSince, now.timeIntervalSince(o) < Self.maxOpenSession { add(o, now) }
        open = min(open, elapsed)
        return (open, elapsed - open)
    }

    func openTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        max(0, rawOpenTime(date, now: now) - restTime(date, now: now))
    }

    /// Tout le temps ouvert, repos compris.
    func rawOpenTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        var t = day(date).openSeconds
        if Self.key(date) == Self.key(now), let s = openSince, now.timeIntervalSince(s) < Self.maxOpenSession {
            t += max(0, now.timeIntervalSince(max(s, Calendar.current.startOfDay(for: now))))
        }
        return t
    }


    // MARK: Repos (ouvert mais pas utilisé)

    /// Le repos commence (raccourci « Foldly repos »).
    mutating func startRest(_ date: Date = Date()) {
        if restSince == nil { restSince = date }
    }

    /// Le repos finit (raccourci « Foldly utilisé ») : on garde la période si le Duo est ouvert.
    mutating func endRest(_ date: Date = Date()) {
        guard let r = restSince else { return }
        restSince = nil
        if openSince != nil {
            focusSpans.append(RestSpan(a: r, b: date))
            if focusSpans.count > 40 { focusSpans.removeFirst(focusSpans.count - 40) }
        }
    }

    /// Les périodes de repos comprises entre `start` et `end`, sans chevauchement :
    /// celles du raccourci (mode Repos) et les heures de repos réglées dans l'app (la nuit, par exemple).
    /// Une ouverture qui couvre toutes les heures de repos (couché avant, levé après) compte en entier
    /// comme du repos (jusqu'à 3 h avant et après) : ouvert de 22 h à 6 h avec des heures de repos de 0 h à 5 h, c'est 8 h de repos.
    /// `openStart` : le vrai début de l'ouverture quand `start` a été coupé à minuit.
    func restSpans(from start: Date, to end: Date, openStart: Date? = nil) -> [RestSpan] {
        guard end > start else { return [] }
        var all = focusSpans
        if let r = restSince { all.append(RestSpan(a: r, b: end)) }
        let hours = nightTo > nightFrom ? nightTo - nightFrom : 24 - nightFrom + nightTo
        if nightOn, nightFrom != nightTo, hours > 0 {
            let cal = Calendar.current
            var day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: start)) ?? start
            while day < end {
                if let a = cal.date(bySettingHour: nightFrom, minute: 0, second: 0, of: day),
                   let b = cal.date(byAdding: .hour, value: hours, to: a) {
                    all.append(RestSpan(a: a, b: b))
                    // Toute la nuit passée ouvert : l'ouverture compte comme du repos, jusqu'à 3 h
                    // avant et après les heures de repos (une soirée passée à s'en servir reste du temps utilisé).
                    if (openStart ?? start) <= a && end >= b {
                        all.append(RestSpan(a: max(openStart ?? start, a.addingTimeInterval(-Self.restMargin)),
                                            b: min(end, b.addingTimeInterval(Self.restMargin))))
                    }
                }
                day = cal.date(byAdding: .day, value: 1, to: day) ?? end
            }
        }
        let clipped = all.map { RestSpan(a: max($0.a, start), b: min($0.b, end)) }.filter { $0.b > $0.a }.sorted { $0.a < $1.a }
        var merged: [RestSpan] = []
        for sp in clipped {
            if var last = merged.last, sp.a <= last.b {
                last.b = max(last.b, sp.b)
                merged[merged.count - 1] = last
            } else {
                merged.append(sp)
            }
        }
        return merged
    }

    /// À la fin d'une ouverture : la part passée au repos, répartie sur les jours traversés.
    private mutating func creditRest(from start: Date, to end: Date) {
        let cal = Calendar.current
        for sp in restSpans(from: start, to: end) {
            var s = sp.a
            while s < sp.b {
                let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: s)) ?? sp.b
                let e = min(sp.b, midnight)
                var d = day(s)
                d.restSeconds += e.timeIntervalSince(s)
                days[Self.key(s)] = d
                s = e
            }
        }
        focusSpans = []
        if restSince != nil { restSince = end }
    }

    /// Temps ouvert au repos d'une journée (l'ouverture en cours comprise pour aujourd'hui).
    func restTime(_ date: Date = Date(), now: Date = Date()) -> TimeInterval {
        var t = day(date).restSeconds
        if Self.key(date) == Self.key(now), let s = openSince, now.timeIntervalSince(s) < Self.maxOpenSession {
            let from = max(s, Calendar.current.startOfDay(for: now))
            t += restSpans(from: from, to: now, openStart: s).reduce(0) { $0 + $1.b.timeIntervalSince($1.a) }
        }
        return min(t, rawOpenTime(date, now: now))
    }

    /// Moyenne de temps ouvert par jour, sur les jours mesurés des `count` derniers jours.
    func averageOpen(days count: Int = 30, now: Date = Date()) -> TimeInterval {
        let values = lastDays(count, now: now).map { openTime($0.date, now: now) }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: Historique (Foldly+)

    /// Les `count` derniers jours, du plus ancien à aujourd'hui.
    func lastDays(_ count: Int, now: Date = Date()) -> [(date: Date, closes: Int)] {
        (0..<count).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: now) else { return nil }
            return (d, day(d).closes)
        }
    }

    /// Les 12 derniers mois (total des plis), du plus ancien au mois en cours.
    func lastMonths(now: Date = Date()) -> [(date: Date, closes: Int)] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var totals: [String: Int] = [:]
        for (key, value) in days { totals[String(key.prefix(7)), default: 0] += value.closes }
        return (0..<12).reversed().compactMap { back in
            guard let m = cal.date(byAdding: .month, value: -back, to: start) else { return nil }
            return (m, totals[String(Self.key(m).prefix(7))] ?? 0)
        }
    }

    /// Le jour le plus chargé et sa date.
    var bestDay: (date: Date, closes: Int)? {
        guard let top = days.max(by: { $0.value.closes < $1.value.closes || ($0.value.closes == $1.value.closes && $0.key > $1.key) }),
              top.value.closes > 0, let d = Self.date(top.key) else { return nil }
        return (d, top.value.closes)
    }

    /// `goal` est la limite du jour : on cherche à rester en dessous.
    var limit: Int { goal }

    /// Ce qui reste avant la limite aujourd'hui (négatif : dépassée).
    func left(now: Date = Date()) -> Int { goal - day(now).closes }

    /// Jours d'affilée sous la limite, depuis le premier jour suivi (aujourd'hui compte s'il est encore sous la limite).
    func currentStreak(now: Date = Date()) -> Int {
        guard goal > 0, let first = firstDay else { return 0 }
        let cal = Calendar.current
        var d = now
        var n = 0
        while Self.key(d) >= first && day(d).closes <= goal {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return n
    }

    /// La plus longue série de jours sous la limite.
    func longestStreak(now: Date = Date()) -> Int {
        guard goal > 0, let first = firstDay.flatMap(Self.date) else { return 0 }
        let cal = Calendar.current
        var d = first
        var best = 0, run = 0
        while Self.key(d) <= Self.key(now) {
            run = day(d).closes <= goal ? run + 1 : 0
            best = max(best, run)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return best
    }

    /// Le jour le plus calme (le moins de plis, aujourd'hui exclu).
    func calmestDay(now: Date = Date()) -> (date: Date, closes: Int)? {
        let today = Self.key(now)
        guard let low = days.filter({ $0.key != today && $0.value.closes > 0 })
            .min(by: { $0.value.closes < $1.value.closes }), let d = Self.date(low.key) else { return nil }
        return (d, low.value.closes)
    }

    /// Les 7 derniers jours comparés aux 7 d'avant, en pourcentage (nil sans semaine d'avant).
    func weekChange(now: Date = Date()) -> Double? {
        let recent = lastDays(14, now: now)
        let previous = recent.prefix(7).reduce(0) { $0 + $1.closes }
        let current = recent.suffix(7).reduce(0) { $0 + $1.closes }
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }

    /// Moyenne par jour sur les 30 jours avant aujourd'hui (depuis le premier jour suivi). nil le premier jour.
    func recentAverage(now: Date = Date()) -> Double? {
        guard let first = firstDay else { return nil }
        let past = lastDays(31, now: now).dropLast().filter { Self.key($0.date) >= first }
        guard !past.isEmpty else { return nil }
        return Double(past.reduce(0) { $0 + $1.closes }) / Double(past.count)
    }

    /// La case la plus chargée de la semaine type : (jour 0 = dimanche, heure).
    var busiestSlot: (weekday: Int, hour: Int)? {
        guard weekHours.count == 168, let top = weekHours.max(), top > 0,
              let i = weekHours.firstIndex(of: top) else { return nil }
        return (i / 24, i % 24)
    }

    /// Moyenne par jour depuis le premier jour compté.
    func dailyAverage(now: Date = Date()) -> Double {
        guard let first = firstDay.flatMap(Self.date) else { return 0 }
        let n = (Calendar.current.dateComponents([.day], from: first, to: now).day ?? 0) + 1
        return Double(totalCloses) / Double(max(1, n))
    }

    var daysCounted: Int { days.values.filter { $0.closes > 0 }.count }

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// L'historique en tableur : date, fermetures, ouvertures.
    func csv() -> String {
        var out = "date,folds,opens\n"
        for key in days.keys.sorted() {
            let d = days[key] ?? DayCount()
            out += "\(key),\(d.closes),\(d.opens)\n"
        }
        return out
    }

    /// On garde environ trois ans d'historique (assez pour un historique importé).
    mutating func keepRecentDays() { trim() }

    private mutating func trim() {
        guard days.count > 1120 else { return }
        let keep = Set(days.keys.sorted().suffix(1100))
        days = days.filter { keep.contains($0.key) }
    }
}

// MARK: - Les couleurs des widgets (Foldly+)

enum ClapetTheme: Int, CaseIterable, Identifiable {
    case mint, orange, pink, blue, lemon
    /// Or 2K : offerte aux Fondateurs (les 2 000 premiers), sans Foldly+.
    case gold

    var id: Int { rawValue }

    /// Rouge, vert, bleu entre 0 et 1.
    var rgb: (Double, Double, Double) {
        switch self {
        case .mint: return (0.43, 0.84, 0.65)
        case .orange: return (1.0, 0.58, 0.28)
        case .pink: return (1.0, 0.42, 0.62)
        case .blue: return (0.40, 0.70, 1.0)
        case .lemon: return (0.95, 0.88, 0.32)
        case .gold: return (0.89, 0.71, 0.33)
        }
    }

    var name: String {
        switch self {
        case .mint: return String(localized: "Mint")
        case .orange: return String(localized: "Orange")
        case .pink: return String(localized: "Pink")
        case .blue: return String(localized: "Blue")
        case .lemon: return String(localized: "Lemon")
        case .gold: return String(localized: "Gold 2K")
        }
    }
}

/// Les Fondateurs : ceux qui ont ouvert Foldly avant le 1er décembre 2026 (les 2 000 premiers et un peu plus).
enum FounderRule {
    static let deadline = DateComponents(calendar: .current, year: 2026, month: 12, day: 1).date ?? .distantFuture
    static var open: Bool { Date() < deadline }
}

extension ClapetStats {
    /// La couleur des widgets : celle choisie (Foldly+, ou l'Or 2K des Fondateurs), menthe sinon.
    var widgetColor: ClapetTheme {
        let t = ClapetTheme(rawValue: theme) ?? .mint
        if t == .gold { return founder ? .gold : .mint }
        return plus || DuoFolds.paidApp ? t : .mint
    }
}

extension ClapetTheme {
    var color: Color {
        let (r, g, b) = rgb
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Les niveaux (sur le total de plis)

struct ClapetLevel {
    let number: Int
    let start: Int
    let next: Int?

    static let thresholds = [0, 500, 1500, 4000, 10_000, 25_000, 60_000, 150_000]

    static func of(_ total: Int) -> ClapetLevel {
        var i = 0
        while i + 1 < thresholds.count && total >= thresholds[i + 1] { i += 1 }
        return ClapetLevel(number: i + 1, start: thresholds[i], next: i + 1 < thresholds.count ? thresholds[i + 1] : nil)
    }

    func progress(_ total: Int) -> Double {
        guard let next else { return 1 }
        return min(1, Double(total - start) / Double(max(1, next - start)))
    }
}

// MARK: - Le coffre (trousseau partagé)

enum ClapetVault {
    private static let service = "com.padelup.clapet"
    private static let account = "stats"

    /// Groupe de trousseau commun à l'app et aux widgets (« ÉQUIPE.com.padelup.clapet.shared »).
    private static var group: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "ClapetKeychainGroup") as? String,
              !g.hasPrefix("."), !g.isEmpty else { return nil }
        return g
    }

    private static func query(_ group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func load() -> ClapetStats {
        for g in [group, nil] {
            var q = query(g)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
               let stats = try? JSONDecoder().decode(ClapetStats.self, from: data) {
                return stats
            }
            if group == nil { break }
        }
        // Secours : la copie de l'app
        if let data = UserDefaults.standard.data(forKey: "clapet.stats"),
           let stats = try? JSONDecoder().decode(ClapetStats.self, from: data) {
            return stats
        }
        return ClapetStats()
    }

    static func save(_ stats: ClapetStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: "clapet.stats")
        if write(data, group: group) != errSecSuccess && group != nil {
            // Sans le groupe partagé (développement), on garde au moins une copie pour l'app.
            _ = write(data, group: nil)
        }
    }

    private static func write(_ data: Data, group: String?) -> OSStatus {
        let q = query(group)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Le bilan de la semaine

struct WeekRecap {
    struct Day {
        let date: Date
        let closes: Int
        let open: TimeInterval
        let closed: TimeInterval
    }

    /// Le dernier jour de la semaine résumée (sert d'identifiant).
    let id: String
    let days: [Day]
    let total: Int
    let previousTotal: Int
    let open: TimeInterval
    let previousOpen: TimeInterval
    let closed: TimeInterval
    let peeks: Int
    let longestBreak: TimeInterval
    /// Jours où au moins un pli a été compté.
    let tracked: Int

    var start: Date { days.first?.date ?? Date() }
    var end: Date { days.last?.date ?? Date() }

    /// Par jour suivi.
    var perDay: Int { tracked > 0 ? Int((Double(total) / Double(tracked)).rounded()) : 0 }

    /// Comparé à la semaine d'avant (nil sans semaine d'avant).
    var change: Double? { previousTotal > 0 ? Double(total - previousTotal) / Double(previousTotal) : nil }

    var openChange: Double? { previousOpen > 60 ? (open - previousOpen) / previousOpen : nil }

    /// Le jour où l'on a le plus plié, et le plus calme (parmi les jours suivis).
    var busiest: Day? { days.filter { $0.closes > 0 }.max { $0.closes < $1.closes } }
    var calmest: Day? {
        let counted = days.filter { $0.closes > 0 }
        guard counted.count > 1 else { return nil }
        return counted.min { $0.closes < $1.closes }
    }

    var isEmpty: Bool { tracked == 0 }
}

extension ClapetStats {
    /// Le dernier jour de la semaine à résumer : aujourd'hui si c'est le dernier jour de la semaine et qu'il est 18 h passées,
    /// sinon le dernier jour de la semaine précédente.
    static func recapEnd(now: Date = Date()) -> Date {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now),
              let lastDay = cal.date(byAdding: .day, value: -1, to: week.end),
              let previous = cal.date(byAdding: .day, value: -1, to: week.start) else { return now }
        if cal.isDate(now, inSameDayAs: lastDay) && cal.component(.hour, from: now) >= 18 { return now }
        return previous
    }

    /// Le jour de la semaine (1 = dimanche … 7 = samedi) où tombe le bilan : le dernier jour de la semaine.
    static var recapWeekday: Int { (Calendar.current.firstWeekday + 5) % 7 + 1 }

    /// Les 7 jours qui finissent `end` (compris), comparés aux 7 d'avant.
    func weekRecap(endingOn end: Date, now: Date = Date()) -> WeekRecap {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: end).addingTimeInterval(12 * 3600)
        func dates(from back: Int) -> [Date] {
            (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -(back + $0), to: anchor) }
        }
        let current = dates(from: 0).map { d in
            WeekRecap.Day(date: d, closes: day(d).closes, open: openTime(d, now: now), closed: downTime(d, now: now))
        }
        let previous = dates(from: 7)
        return WeekRecap(
            id: Self.key(end),
            days: current,
            total: current.reduce(0) { $0 + $1.closes },
            previousTotal: previous.reduce(0) { $0 + day($1).closes },
            open: current.reduce(0) { $0 + $1.open },
            previousOpen: previous.reduce(0) { $0 + openTime($1, now: now) },
            closed: current.reduce(0) { $0 + $1.closed },
            peeks: current.reduce(0) { $0 + day($1.date).peeks },
            longestBreak: current.map { longestBreak($0.date, now: now) }.max() ?? 0,
            tracked: current.filter { $0.closes > 0 }.count)
    }
}


// MARK: - Sessions (Foldly+) : combien de temps le Duo reste ouvert à chaque fois

struct SessionSummary {
    var count = 0
    var average: TimeInterval = 0
    var median: TimeInterval = 0
    var longest: OpenSession?
    /// Moins d'1 min, 1 à 10 min, plus de 10 min (nombre de sessions).
    var short = 0, medium = 0, long = 0
    var weekdayAverage: TimeInterval?
    var weekendAverage: TimeInterval?
    /// Part du temps éveillé (7 h – 23 h) passée ouvert, sur les jours mesurés.
    var awakeShare: Double?
    /// Calculé à partir des totaux du jour (ouvertures d'avant la mise à jour) : moyenne seulement.
    var estimated = false
}

extension ClapetStats {
    func sessionSummary(days count: Int = 7, now: Date = Date()) -> SessionSummary {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -(count - 1), to: cal.startOfDay(for: now)) ?? now
        let list = sessionLog.filter { $0.t >= from }
        var r = SessionSummary()
        guard !list.isEmpty else {
            // Pas encore de sessions enregistrées : la moyenne vient des totaux du jour.
            let ds = lastDays(count, now: now).map { day($0.date) }.filter { $0.opens > 0 && $0.openSeconds > 0 }
            let opens = ds.reduce(0) { $0 + $1.opens }
            if opens > 0 {
                r.count = opens
                r.average = ds.reduce(0) { $0 + $1.openSeconds } / Double(opens)
                r.estimated = true
            }
            return r
        }
        let secs = list.map(\.s).sorted()
        r.count = list.count
        r.average = secs.reduce(0, +) / Double(secs.count)
        r.median = secs.count % 2 == 1 ? secs[secs.count / 2] : (secs[secs.count / 2 - 1] + secs[secs.count / 2]) / 2
        r.longest = list.max { $0.s < $1.s }
        for x in secs {
            if x < 60 { r.short += 1 } else if x <= 600 { r.medium += 1 } else { r.long += 1 }
        }
        let weekend = list.filter { cal.isDateInWeekend($0.t) }, weekday = list.filter { !cal.isDateInWeekend($0.t) }
        if !weekday.isEmpty { r.weekdayAverage = weekday.reduce(0) { $0 + $1.s } / Double(weekday.count) }
        if !weekend.isEmpty { r.weekendAverage = weekend.reduce(0) { $0 + $1.s } / Double(weekend.count) }
        // Temps éveillé : de 7 h à 23 h, sur les jours où au moins une session a été vue.
        var awake: [String: Double] = [:]
        for x in list {
            var a = x.t
            let end = x.t.addingTimeInterval(x.s)
            while a < end {
                let dayStart = cal.startOfDay(for: a)
                let w0 = dayStart.addingTimeInterval(7 * 3600), w1 = dayStart.addingTimeInterval(23 * 3600)
                let next = cal.date(byAdding: .day, value: 1, to: dayStart) ?? end
                let segEnd = min(end, next)
                let overlap = max(0, min(segEnd, w1).timeIntervalSince(max(a, w0)))
                awake[Self.key(a), default: 0] += overlap
                a = segEnd
            }
        }
        if !awake.isEmpty {
            // Aujourd'hui ne compte que jusqu'à maintenant.
            var possible = 0.0
            for k in awake.keys {
                if k == Self.key(now) {
                    let d0 = cal.startOfDay(for: now)
                    possible += max(60, min(now, d0.addingTimeInterval(23 * 3600)).timeIntervalSince(d0.addingTimeInterval(7 * 3600)))
                } else { possible += 16 * 3600 }
            }
            r.awakeShare = min(1, awake.values.reduce(0, +) / max(1, possible))
        }
        return r
    }
}
