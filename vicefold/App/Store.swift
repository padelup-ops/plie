// Store.swift — Vicefold
//
// Pro : achat unique, ou abonnement mensuel / annuel. Tous les guides restent gratuits.
// Pro débloque : épingles et lieux visités illimités, couches de la carte (objets, activités, événements),
// ta propre carte, synchronisation iCloud, widgets de progression, heures PlayStation.

import Foundation
import Observation
import StoreKit

@MainActor @Observable
final class Store {
    static let shared = Store()

    static let lifetime = "com.padelup.vicefold.pro.lifetime"
    static let monthly = "com.padelup.vicefold.pro.monthly"
    static let yearly = "com.padelup.vicefold.pro.yearly"
    static let ids = [lifetime, yearly, monthly]

    private(set) var products: [Product] = []
    private(set) var isPro = UserDefaults.standard.bool(forKey: "vicefold.pro")
    var busy = false
    var message: String?
    private var updates: Task<Void, Never>?

    init() {
        // Les captures d'écran, et les versions de test TestFlight, montrent l'app complète.
        if Self.unlocked { isPro = true }
        updates = Task { [weak self] in
            for await r in Transaction.updates {
                if case .verified(let t) = r { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    func load() async {
        if let p = try? await Product.products(for: Self.ids) {
            products = p.sorted { Self.ids.firstIndex(of: $0.id) ?? 0 < Self.ids.firstIndex(of: $1.id) ?? 0 }
        }
        await refresh()
    }

    /// Captures du simulateur et TestFlight (reçu « sandbox ») : tout est ouvert.
    static var unlocked: Bool {
        ProcessInfo.processInfo.arguments.contains("-shot") || Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    func refresh() async {
        if Self.unlocked { set(true); return }
        var pro = false
        for await r in Transaction.currentEntitlements {
            if case .verified(let t) = r, Self.ids.contains(t.productID), t.revocationDate == nil { pro = true }
        }
        set(pro)
    }

    private func set(_ pro: Bool) {
        guard pro != isPro else { return }
        isPro = pro
        UserDefaults.standard.set(pro, forKey: "vicefold.pro")
        if pro { Progress.shared.pushCloud(); Progress.shared.pullCloud() }
        Progress.shared.writeSnapshot()
    }

    func buy(_ p: Product) async {
        busy = true
        defer { busy = false }
        do {
            switch try await p.purchase() {
            case .success(let r):
                if case .verified(let t) = r { await t.finish(); set(true) }
            case .pending:
                message = String(localized: "Purchase pending approval.")
            default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if !isPro { message = String(localized: "No purchase to restore on this Apple Account.") }
    }
}
