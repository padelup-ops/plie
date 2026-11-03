import StoreKit
import SwiftUI

// MARK: - L'achat de l'histoire complète (un seul achat, non consommable)

@MainActor
@Observable
final class Store {
    static let fullStoryID = "com.padelup.unlocked.nina.full"

    private(set) var product: Product?
    private(set) var purchased = false
    private(set) var busy = false
    var message: String?

    private var updates: Task<Void, Never>?

    func start() async {
        updates?.cancel()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    await self?.refresh()
                }
            }
        }
        await refresh()
        if product == nil {
            product = try? await Product.products(for: [Store.fullStoryID]).first
        }
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Store.fullStoryID, t.revocationDate == nil { owned = true }
        }
        purchased = owned
    }

    /// Le prix affiché, tel que l'App Store le donne (3,99 € par défaut).
    var price: String { product?.displayPrice ?? T("3,99 €", "$3.99") }

    func buy() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if product == nil { product = try? await Product.products(for: [Store.fullStoryID]).first }
        guard let product else {
            message = T("L'App Store ne répond pas. Réessaie dans un moment.", "The App Store isn't answering. Try again in a moment.")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    purchased = true
                }
            case .pending:
                message = T("Achat en attente d'accord.", "Purchase waiting for approval.")
            default:
                break
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
        if !purchased { message = T("Aucun achat à restaurer.", "No purchase to restore.") }
    }
}

/// L'offre : la suite de l'histoire.
struct PaywallCard: View {
    @Environment(GameState.self) private var state
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
                .onTapGesture { state.showPaywall = false }
            VStack(spacing: 14) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .semibold))
                Text(T("La suite de l'histoire", "The rest of the story"))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    Label(T("Chapitres 2, 3 et 4 : l'album masqué, la carte, le dossier", "Chapters 2, 3 and 4: the hidden album, the map, the file"), systemImage: "book.pages.fill")
                    Label(T("Agenda, Plans, Réglages et Mail s'ouvrent", "Calendar, Maps, Settings and Mail open up"), systemImage: "square.grid.2x2.fill")
                    Label(T("Trois fins, dont une cachée", "Three endings, one of them hidden"), systemImage: "sparkles")
                    Label(T("Un seul achat. Pas d'abonnement, pas de pub.", "One purchase. No subscription, no ads."), systemImage: "checkmark.seal.fill")
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))

                Button {
                    Task { await store.buy() }
                } label: {
                    Group {
                        if store.busy { ProgressView().tint(.black) } else { Text(T("Débloquer pour \(store.price)", "Unlock for \(store.price)")) }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.white))
                    .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .disabled(store.busy)

                HStack(spacing: 18) {
                    Button(T("Restaurer l'achat", "Restore purchase")) { Task { await store.restore() } }
                    Button(T("Plus tard", "Later")) { state.showPaywall = false }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

                if let m = store.message {
                    Text(m).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(26)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.12)))
            .foregroundStyle(.white)
            .padding(20)
        }
    }
}
