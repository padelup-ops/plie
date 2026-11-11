import GameKit
import SwiftUI
import Observation

/// Les classements Game Center, au choix (rien n'est envoyé sans l'avoir activé), ouverts à tous.
/// - Sous la limite : la plus longue série, et les jours sous la limite sur 30 jours (il faut une limite).
/// - Qui plie le plus : aujourd'hui, cette semaine, depuis le début.
/// - Le concours du mois : le plus de plis, le plus de temps déplié, et le plus zen (le moins de plis par jour).
/// Les comptes et les scores sont gérés par Apple ; Foldly n'a pas de serveur.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()
    static let streakID = "foldly.streak"
    static let monthID = "foldly.month"
    static let todayID = "foldly.folds.day"
    static let weekID = "foldly.folds.week"
    static let totalID = "foldly.folds.total"
    static let contestFoldsID = "foldly.contest.folds"
    static let contestOpenID = "foldly.contest.open"
    static let contestCalmID = "foldly.contest.calm"
    static let recurring = [monthID, todayID, weekID, contestFoldsID, contestOpenID, contestCalmID]
    static let all = [streakID, monthID, todayID, weekID, totalID, contestFoldsID, contestOpenID, contestCalmID]
    /// Le plus zen : il faut au moins ce nombre de jours avec des plis dans la période.
    static let calmMinDays = 7

    private(set) var on = UserDefaults.standard.bool(forKey: "gameCenterOn")
    private(set) var signedIn = false
    /// Gardé pour l'app (les classements sont maintenant ouverts à tous).
    var plus = UserDefaults.standard.bool(forKey: "plusActive")
    var problem: String?
    /// Début et fin de la période en cours de chaque classement qui se renouvelle.
    private(set) var periods: [String: DateInterval] = [:]

    /// À l'ouverture de l'app : reconnecte le joueur s'il a activé le classement.
    func start() {
        guard on else { return }
        authenticate()
    }

    func setOn(_ value: Bool) {
        on = value
        UserDefaults.standard.set(value, forKey: "gameCenterOn")
        problem = nil
        if value { authenticate() }
    }

    private func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    Self.topController()?.present(controller, animated: true)
                    return
                }
                self.signedIn = GKLocalPlayer.local.isAuthenticated
                if !self.signedIn && self.on {
                    // Le vrai message d'Apple aide à comprendre (compte pas connecté, jeu pas encore reconnu…).
                    let base = String(localized: "Sign in to Game Center in the Settings app to join the leaderboard.")
                    self.problem = error.map { base + "\n(" + $0.localizedDescription + ")" } ?? base
                } else {
                    self.problem = nil
                    self.lastSent = [:]
                }
            }
        }
    }

    @ObservationIgnored private var lastSent: [String: Int] = [:]

    /// Les périodes en cours (rechargées quand l'une est finie).
    func loadPeriods(now: Date = Date()) async {
        let stale = Self.recurring.contains { id in periods[id].map { now >= $0.end } ?? true }
        guard stale, let boards = try? await GKLeaderboard.loadLeaderboards(IDs: Self.recurring) else { return }
        for b in boards {
            if let start = b.startDate, b.duration > 0 {
                periods[b.baseLeaderboardID] = DateInterval(start: start, duration: b.duration)
            }
        }
    }

    /// Les scores à envoyer, classement par classement.
    func scores(_ stats: ClapetStats, now: Date = Date()) -> [String: Int] {
        var out: [String: Int] = [:]
        if stats.goalOn {
            out[Self.streakID] = stats.leaderboardStreak(now: now)
            let since = periods[Self.monthID]?.start ?? Calendar.current.date(byAdding: .day, value: -29, to: now)!
            out[Self.monthID] = stats.daysUnderLimit(since: since, now: now)
        }
        out[Self.todayID] = stats.day(now).closes
        out[Self.weekID] = stats.closes(since: periods[Self.weekID]?.start ?? Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now, now: now)
        out[Self.totalID] = stats.totalCloses
        let contest = periods[Self.contestFoldsID]?.start ?? Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        out[Self.contestFoldsID] = stats.closes(since: contest, now: now)
        out[Self.contestOpenID] = Int(stats.openMinutes(since: periods[Self.contestOpenID]?.start ?? contest, now: now))
        if let calm = stats.calmScore(since: periods[Self.contestCalmID]?.start ?? contest, now: now, minDays: Self.calmMinDays) {
            out[Self.contestCalmID] = calm
        }
        return out
    }

    /// Envoie les scores (seulement ceux qui ont changé).
    func submit(_ stats: ClapetStats, now: Date = Date()) {
        guard on, GKLocalPlayer.local.isAuthenticated else { return }
        Task {
            await loadPeriods(now: now)
            let all = scores(stats, now: now)
            // Un score à 0 n'apporte rien au classement (et encombre la liste) : on ne l'envoie pas.
            for (id, value) in all where lastSent[id] != value && value > 0 {
                lastSent[id] = value
                do {
                    try await GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [id])
                } catch {
                    lastSent[id] = nil
                }
            }
        }
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension ClapetStats {
    /// Les plis (fermetures) depuis une date, jour par jour.
    func closes(since start: Date, now: Date = Date()) -> Int {
        let from = Self.key(start), to = Self.key(now)
        return days.filter { $0.key >= from && $0.key <= to }.reduce(0) { $0 + $1.value.closes }
    }

    /// Les minutes passées Duo déplié depuis une date.
    func openMinutes(since start: Date, now: Date = Date()) -> Double {
        let cal = Calendar.current
        var d = cal.startOfDay(for: start), total: TimeInterval = 0
        while d <= now {
            total += openTime(d, now: now)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return total / 60
    }

    /// Le plus zen : la moyenne de plis par jour utilisé (×10), s'il y a assez de jours.
    func calmScore(since start: Date, now: Date = Date(), minDays: Int) -> Int? {
        let from = Self.key(start), to = Self.key(now)
        let used = days.filter { $0.key >= from && $0.key <= to && $0.value.closes > 0 }
        guard used.count >= minDays else { return nil }
        let avg = Double(used.reduce(0) { $0 + $1.value.closes }) / Double(used.count)
        return Int((avg * 10).rounded())
    }

    /// Pour le classement : la plus longue série de jours sous la limite, en ne comptant que les jours où le Duo a servi
    /// (un jour sans aucun pli ne compte pas, pour que le classement reste juste).
    func leaderboardStreak(now: Date = Date()) -> Int {
        guard goal > 0, let first = firstDay.flatMap(Self.date) else { return 0 }
        let cal = Calendar.current
        var d = first, best = 0, run = 0
        while Self.key(d) <= Self.key(now) {
            let c = day(d).closes
            if c > 0 && c <= goal { run += 1 } else if c > goal { run = 0 }
            best = max(best, run)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return best
    }

    /// Pour le classement « 30 jours » : les jours sous la limite (avec au moins un pli) depuis le début de la période.
    func daysUnderLimit(since start: Date, now: Date = Date()) -> Int {
        guard goal > 0 else { return 0 }
        let from = Self.key(start), to = Self.key(now)
        return days.filter { $0.key >= from && $0.key <= to && $0.value.closes > 0 && $0.value.closes <= goal }.count
    }
}

/// L'écran des classements de Game Center.
struct LeaderboardScreen: UIViewControllerRepresentable {
    var leaderboardID: String = GameCenter.streakID
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(leaderboardID: leaderboardID, playerScope: .global, timeScope: .allTime)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) { dismiss() }
    }
}
