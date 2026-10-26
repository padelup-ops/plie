import StoreKit
import Observation

/// Un seul achat intégré : le Pass Origamo, qui débloque tous les niveaux des trois jeux.
@Observable
final class StoreManager {
    static let passID = "plie.pass.complet"

    var pass: Product?
    /// Le Pass a vraiment été acheté.
    var ownsPass = false

    /// Version de test (TestFlight, ou Xcode) : tout est offert aux testeurs.
    /// Jamais sur l'App Store : le reçu y est un reçu de production.
    let isTestBuild: Bool = {
        guard BuildFlags.testersGetEverything else { return false }
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    /// Pour voir l'app comme un nouveau joueur (cadenas, clés, Pass), même en version de test.
    private(set) var simulateFree = UserDefaults.standard.bool(forKey: "tester.simulateFree")

    /// Tous les jeux et tous les niveaux : Pass acheté, ou version de test.
    var hasEverything: Bool { ownsPass || (isTestBuild && !simulateFree) }

    func setSimulateFree(_ on: Bool) {
        simulateFree = on
        UserDefaults.standard.set(on, forKey: "tester.simulateFree")
    }
    var isLoading = false
    var isPurchasing = false
    var message: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pass = try await Product.products(for: [Self.passID]).first
        } catch {
            message = L("La boutique ne répond pas pour le moment.")
        }
        await refreshEntitlements()
    }

    @MainActor
    func refreshEntitlements() async {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.passID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        ownsPass = owned
    }

    @MainActor
    func buyPass() async {
        guard let pass else {
            message = L("Le Pass n'est pas disponible pour le moment.")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await pass.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    message = L("Merci ! Tout est débloqué.")
                } else {
                    message = L("L'achat n'a pas pu être vérifié.")
                }
            case .pending:
                message = L("Achat en attente de validation.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = L("L'achat n'a pas abouti. Réessaie dans un instant.")
        }
    }

    @MainActor
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = L("Impossible de restaurer les achats pour le moment.")
        }
        await refreshEntitlements()
        if ownsPass {
            message = L("Pass restauré.")
        }
    }
}
