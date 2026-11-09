import Observation
import StoreKit
import SwiftUI

/// Les réglages du clavier, modifiés dans l'app et partagés avec le clavier.
@Observable
final class SettingsModel {
    var settings: KBSettings {
        didSet {
            guard settings != oldValue else { return }
            var s = settings
            s.clamp()
            KBVault.save(s)
        }
    }

    init() {
        settings = KBVault.loadSettings()
    }

    func reload() {
        settings = KBVault.loadSettings()
    }
}

/// L'essai gratuit de 3 jours et l'achat de Foldboard Pro.
@Observable
final class Store {
    var access = KBVault.loadAccess()
    var products: [String: Product] = [:]
    var busy = false
    var message: String?
    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
        Task { await refresh() }
    }

    var isPro: Bool { access.isPro() }

    func price(_ id: String) -> String? { products[id]?.displayPrice }

    @MainActor
    func load() async {
        if let list = try? await Product.products(for: [KBProducts.trial, KBProducts.pro]) {
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
    }

    @MainActor
    func refresh() async {
        var a = KBAccess()
        a.trialStart = access.trialStart
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == KBProducts.pro { a.purchased = true }
            if t.productID == KBProducts.trial {
                a.trialStart = min(a.trialStart ?? t.originalPurchaseDate, t.originalPurchaseDate)
            }
        }
        if a.purchased != access.purchased || a.trialStart != access.trialStart || access.stamp == .distantPast {
            access = a
            KBVault.save(a)
        }
    }

    @MainActor
    func buy(_ id: String) async {
        if products[id] == nil { await load() }
        guard let product = products[id] else {
            message = NSLocalizedString("The App Store isn’t reachable right now. Try again in a moment.", comment: "")
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase()
            if case .success(let v) = result, case .verified(let t) = v {
                await t.finish()
                message = nil
            }
        } catch {
            message = error.localizedDescription
        }
        await refresh()
    }

    @MainActor
    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = isPro ? nil : NSLocalizedString("No purchase found for this Apple account.", comment: "")
    }
}
