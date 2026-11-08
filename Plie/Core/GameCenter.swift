import SwiftUI
import GameKit

// MARK: - Les classements (Game Center)
//
// Les records des jeux à score partent dans les classements Game Center d'Apple : pas de serveur
// à nous, le pseudo Game Center du joueur, et Apple gère la vie privée. La connexion est discrète :
// on ne montre jamais d'écran de connexion au lancement, seulement quand le joueur touche
// « Classements ».

enum Leaderboard: String, CaseIterable {
    case comete = "origamo.comete"
    case golf = "origamo.golf"
    case minesKids = "origamo.mines.kids"
    case minesNormal = "origamo.mines.normal"
    case minesHard = "origamo.mines.hard"
    case peche = "origamo.peche"
    case croco = "origamo.croco"
    case bonneteau = "origamo.bonneteau"
    case luciole = "origamo.luciole"
    case rayon = "origamo.rayon"
}

@Observable
final class GameCenter {
    static let shared = GameCenter()

    private(set) var signedIn = false
    /// L'écran de connexion d'Apple, gardé pour le moment où le joueur touche « Classements ».
    @ObservationIgnored private var loginController: UIViewController?
    @ObservationIgnored private var onSignIn: (() -> Void)?

    func start(onSignIn: @escaping () -> Void) {
        self.onSignIn = onSignIn
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loginController = controller
                let now = GKLocalPlayer.local.isAuthenticated
                let wasSignedIn = self.signedIn
                self.signedIn = now
                // Le petit bouton flottant de Game Center : jamais.
                GKAccessPoint.shared.isActive = false
                if now && !wasSignedIn { self.onSignIn?() }
            }
        }
    }

    /// Un record : envoyé tel quel (Game Center garde le meilleur).
    func submit(_ value: Int, to board: Leaderboard) {
        guard signedIn, value > 0 else { return }
        Task {
            try? await GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board.rawValue])
        }
    }

    /// Ouvre les classements (ou l'écran de connexion d'Apple si le joueur n'est pas connecté).
    func show(_ board: Leaderboard? = nil) -> Bool {
        if signedIn {
            let vc: GKGameCenterViewController
            if let board {
                vc = GKGameCenterViewController(leaderboardID: board.rawValue, playerScope: .global, timeScope: .allTime)
            } else {
                vc = GKGameCenterViewController(state: .leaderboards)
            }
            vc.gameCenterDelegate = Dismisser.shared
            present(vc)
            return true
        }
        if let login = loginController {
            present(login)
            return true
        }
        return false
    }

    private func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene.windows.first?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(vc, animated: true)
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            controller.dismiss(animated: true)
        }
    }
}
