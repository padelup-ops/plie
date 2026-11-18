//
//  StoreManager.swift
//  RetroCartridge
//

import Foundation
import StoreKit
import SwiftUI

@MainActor
@Observable
final class StoreManager {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []

    /// True while products are loading or purchases are being restored.
    var isLoading: Bool = false

    /// The product whose purchase is in flight, if any.
    var purchasingProductID: String?

    /// True while `restorePurchases()` runs.
    var isRestoring: Bool = false

    /// Purchase / restore failures, shown inline by the store screen.
    var errorMessage: String?

    /// Why the last product load came back empty (nil when products loaded).
    var productLoadError: String?

    /// Whether `loadProducts()` has finished at least once.
    var hasAttemptedProductLoad: Bool = false

    /// Listens for purchases, refunds and revocations made outside the app.
    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?

    /// When the free 1-day trial was started (its first purchase), kept on device too.
    var trialStart: Date? = UserDefaults.standard.object(forKey: "retrofold.trialStart") as? Date

    /// Moves forward every 30 s, so the screens notice when the trial ends.
    var now = Date()
    @ObservationIgnored private var clock: Task<Void, Never>?

    init() {
        transactionUpdates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: result)
            }
        }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.now = Date()
            }
        }
    }

    /// When the trial ends, once started.
    var trialEnd: Date? { trialStart.map { $0.addingTimeInterval(ProductIdentifiers.trialLength) } }

    /// Everything is unlocked during the 24 hours after the trial starts.
    var isTrialActive: Bool { trialEnd.map { now < $0 } ?? false }

    /// The trial can be started once.
    var canStartTrial: Bool { trialStart == nil && !purchasedProductIDs.contains(ProductIdentifiers.pro) }

    /// Whole hours left in the trial (at least 1 while it runs).
    var trialHoursLeft: Int { max(1, Int(ceil((trialEnd?.timeIntervalSince(now) ?? 0) / 3600))) }

    func startTrial() async {
        if product(for: ProductIdentifiers.trial) == nil { await loadProducts() }
        guard let product = product(for: ProductIdentifiers.trial) else {
            errorMessage = String(localized: "The App Store didn't return any products.")
            return
        }
        await purchase(product)
    }

    private func noteTrial(_ transaction: StoreKit.Transaction) {
        guard transaction.productID == ProductIdentifiers.trial else { return }
        let start = min(trialStart ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
        trialStart = start
        now = Date()
        UserDefaults.standard.set(start, forKey: "retrofold.trialStart")
    }

    isolated deinit {
        transactionUpdates?.cancel()
        clock?.cancel()
    }

    /// Whether RetroFold Pro, the one purchase, is owned.
    var hasPro: Bool {
        isPurchased(ProductIdentifiers.pro)
    }

    /// Products loaded, but none came back (offline, or IDs unknown to the store).
    var productsUnavailable: Bool {
        hasAttemptedProductLoad && !isLoading && products.isEmpty
    }

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        productLoadError = nil
        defer {
            isLoading = false
            hasAttemptedProductLoad = true
        }

        do {
            let loaded = try await Product.products(for: ProductIdentifiers.allProductIDs)
            products = loaded.sorted {
                (ProductIdentifiers.displayOrder.firstIndex(of: $0.id) ?? .max)
                    < (ProductIdentifiers.displayOrder.firstIndex(of: $1.id) ?? .max)
            }
            if loaded.isEmpty {
                productLoadError = String(localized: "The App Store didn't return any products.")
            }
        } catch {
            productLoadError = error.localizedDescription
        }

        // Entitlements are cached on device, so refresh them even when offline.
        await updatePurchasedProducts()
    }

    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        errorMessage = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                if case .unverified = verificationResult {
                    errorMessage = String(localized: "The purchase couldn't be verified.")
                }
                await handle(transactionResult: verificationResult)
            case .pending:
                errorMessage = String(localized: "Purchase pending approval. It will unlock once approved.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = String(localized: "Purchase failed: \(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = String(localized: "Failed to restore purchases: \(error.localizedDescription)")
        }
    }

    func isPurchased(_ productID: String) -> Bool {
        if ShotMode.unlockAll || purchasedProductIDs.contains(productID) { return true }
        return productID == ProductIdentifiers.pro && isTrialActive
    }

    func isUnlocked(_ skinType: ConsoleSkinType) -> Bool {
        guard let productID = skinType.requiredProductID else { return true }
        return isPurchased(productID)
    }

    /// The skin to draw: a locked choice (e.g. after a refund) falls back
    /// to Classic Grey, as the sound pack and the screen fall back too.
    func effectiveSkin(_ skin: ConsoleSkinType) -> ConsoleSkinType {
        isUnlocked(skin) ? skin : .classicGrey
    }

    func isUnlocked(_ soundPack: SoundPack) -> Bool {
        guard let productID = soundPack.requiredProductID else { return true }
        return isPurchased(productID)
    }

    /// The sound pack to play: a locked choice falls back to Classic.
    func effectiveSoundPack(_ pack: SoundPack) -> SoundPack {
        isUnlocked(pack) ? pack : .classic
    }

    func isUnlocked(_ gameType: GameType) -> Bool {
        guard let productID = gameType.info.requiredProductID else { return true }
        return isPurchased(productID)
    }

    func isUnlocked(_ screenMode: ScreenMode) -> Bool {
        guard let productID = screenMode.requiredProductID else { return true }
        return isPurchased(productID)
    }

    /// Whether the screen tuning controls are available (RetroFold Pro).
    var canTuneScreen: Bool { hasPro }

    /// The screen to actually draw: locked modes fall back to Color CRT and
    /// locked tuning to the designed look, e.g. after a refund.
    func effectiveScreenSettings(_ settings: ScreenSettings) -> ScreenSettings {
        var effective = canTuneScreen ? settings : ScreenSettings(mode: settings.mode)
        if !isUnlocked(effective.mode) {
            effective.mode = .crt
        }
        return effective
    }

    /// Rebuilds the owned set from current entitlements, so refunds and
    /// revocations drop out as well.
    private func updatePurchasedProducts() async {
        var owned: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                owned.insert(transaction.productID)
                noteTrial(transaction)
            }
        }
        purchasedProductIDs = owned
    }

    private func handle(transactionResult result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            return // Ignore unverified transactions
        }

        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
            noteTrial(transaction)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }

        await transaction.finish()
    }
}
