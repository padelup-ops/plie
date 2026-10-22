import StoreKit
import Observation

/// Un seul achat intégré : le Pass Plié, qui débloque tous les niveaux des trois jeux.
@Observable
final class StoreManager {
    static let passID = "plie.pass.complet"

    var pass: Product?
    var ownsPass = false
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
            message = "La boutique ne répond pas pour le moment."
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
            message = "Le Pass n'est pas disponible pour le moment."
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
                    message = "Merci ! Tout est débloqué."
                } else {
                    message = "L'achat n'a pas pu être vérifié."
                }
            case .pending:
                message = "Achat en attente de validation."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "L'achat n'a pas abouti. Réessaie dans un instant."
        }
    }

    @MainActor
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = "Impossible de restaurer les achats pour le moment."
        }
        await refreshEntitlements()
        if ownsPass {
            message = "Pass restauré."
        }
    }
}
