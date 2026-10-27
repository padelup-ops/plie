import StoreKit
import Observation

/// Un seul achat : FoldCount+, une fois pour toutes (pas d'abonnement).
@Observable
final class ClapetStore {
    static let plusID = "com.padelup.clapet.plus"

    var product: Product?
    /// FoldCount+ vraiment acheté.
    private(set) var owned = false
    var isPurchasing = false
    var message: String?

    /// Version de test (TestFlight ou Xcode) : on peut simuler l'achat pour voir les deux modes.
    let isTestBuild: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    private(set) var simulatePlus = UserDefaults.standard.bool(forKey: "tester.simulatePlus")

    /// FoldCount+ : acheté, ou simulé dans une version de test.
    var hasPlus: Bool { DuoFolds.paidApp || owned || (isTestBuild && simulatePlus) || Demo.plus }

    /// Appelé quand `hasPlus` change (pour prévenir les widgets).
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    func setSimulatePlus(_ on: Bool) {
        simulatePlus = on
        UserDefaults.standard.set(on, forKey: "tester.simulatePlus")
        onChange?(hasPlus)
    }

    /// Le prix affiché par l'App Store, dans la monnaie du pays.
    var price: String? { product?.displayPrice }

    @MainActor
    func load() async {
        if product == nil {
            product = try? await Product.products(for: [Self.plusID]).first
        }
        await refresh()
    }

    @MainActor
    func refresh() async {
        var has = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.plusID,
               transaction.revocationDate == nil {
                has = true
            }
        }
        owned = has
        onChange?(hasPlus)
    }

    @MainActor
    func buy() async {
        if product == nil { await load() }
        guard let product else {
            message = String(localized: "The App Store isn't answering right now. Try again in a moment.")
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                } else {
                    message = String(localized: "The purchase couldn't be verified.")
                }
            case .pending:
                message = String(localized: "Your purchase is waiting for approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "The purchase didn't go through. Try again in a moment.")
        }
    }

    @MainActor
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = String(localized: "Purchases can't be restored right now.")
        }
        await refresh()
        if !owned && message == nil {
            message = String(localized: "No purchase to restore on this Apple Account.")
        }
    }
}
