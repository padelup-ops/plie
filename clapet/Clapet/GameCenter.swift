import GameKit
import SwiftUI
import Observation

/// Les classements Game Center, au choix (rien n'est envoyé sans l'avoir activé).
/// Deux classements : la plus longue série de jours sous la limite, et les jours sous la limite ce mois-ci.
/// Les comptes et les scores sont gérés par Apple ; Foldly n'a pas de serveur.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()
    static let streakID = "foldly.streak"
    static let monthID = "foldly.month"

    private(set) var on = UserDefaults.standard.bool(forKey: "gameCenterOn")
    private(set) var signedIn = false
    /// Les classements font partie de Foldly+.
    var plus = UserDefaults.standard.bool(forKey: "plusActive")
    var problem: String?

    /// À l'ouverture de l'app : reconnecte le joueur s'il a activé le classement.
    func start() {
        guard on, plus else { return }
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
                    self.problem = String(localized: "Sign in to Game Center in the Settings app to join the leaderboard.")
                } else {
                    self.problem = nil
                    self.lastSent = nil
                }
            }
        }
    }

    @ObservationIgnored private var lastSent: (streak: Int, month: Int, monthKey: String)?
    @ObservationIgnored private var periodStart: Date?
    @ObservationIgnored private var periodEnd: Date?

    /// Envoie les scores du jour (seulement s'ils ont changé).
    func submit(_ stats: ClapetStats, now: Date = Date()) {
        guard plus, on, GKLocalPlayer.local.isAuthenticated, stats.goalOn else { return }
        let streak = stats.leaderboardStreak(now: now)
        Task {
            // Le classement « 30 jours » repart à zéro tous les 30 jours : on compte depuis le début de la période en cours.
            if periodStart == nil || (periodEnd.map { now >= $0 } ?? true) {
                if let board = try? await GKLeaderboard.loadLeaderboards(IDs: [Self.monthID]).first {
                    periodStart = board.startDate
                    periodEnd = board.startDate.map { $0.addingTimeInterval(board.duration) }
                }
            }
            let month = stats.daysUnderLimit(since: periodStart ?? Calendar.current.date(byAdding: .day, value: -29, to: now)!, now: now)
            let monthKey = periodStart.map { ClapetStats.key($0) } ?? ""
            if let last = lastSent, last.streak == streak, last.month == month, last.monthKey == monthKey { return }
            lastSent = (streak, month, monthKey)
            do {
                try await GKLeaderboard.submitScore(streak, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.streakID])
                try await GKLeaderboard.submitScore(month, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.monthID])
            } catch {
                await MainActor.run { self.lastSent = nil }
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
