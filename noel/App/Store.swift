// Store.swift — Allô Père Noël
//
// La « magie complète » : un achat unique (StoreKit 2), sans abonnement. Elle débloque les quatre autres histoires,
// les appels pour frères et sœurs, l'anecdote, le cadeau et les cartes souvenirs premium.
// L'achat passe par une question pour les grands : un enfant ne peut pas acheter par accident.

import StoreKit
import SwiftUI

@MainActor @Observable
final class MagicStore {
    static let productID = "com.padelup.allonoel.magie"

    private(set) var owned = false
    private(set) var product: Product?
    private(set) var busy = false
    var message: LocalizedStringKey?
    private var updates: Task<Void, Never>?

    /// Le prix affiché (celui de l'App Store ; un exemple dans les captures).
    var price: String {
        if let product { return product.displayPrice }
        if ShotMode.route != nil {
            return Decimal(string: "3.99")!.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
        }
        return "…"
    }

    func start() async {
        if ShotMode.route == "owned" { owned = true }
        guard ShotMode.route == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    await self?.refresh()
                }
            }
        }
        await refresh()
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refresh() async {
        var has = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { has = true }
        }
        owned = has
    }

    func buy() async {
        if product == nil { product = try? await Product.products(for: [Self.productID]).first }
        guard let product else { message = "The App Store can't be reached. Try again in a moment."; return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v {
                    await t.finish()
                    owned = true
                }
            case .pending:
                message = "The purchase is waiting for approval."
            default: break
            }
        } catch {
            message = "The purchase didn't go through. Nothing was charged."
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = owned ? "The full magic is back! ✨" : "No purchase to restore on this Apple account."
    }
}

// MARK: - La page d'achat

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gate = false

    var body: some View {
        ZStack {
            NightScene(moon: false, trees: false)
            Snowfall(count: 40, opacity: 0.6)
            ScrollView {
                VStack(spacing: 0) {
                    SantaMedallion(size: 120)
                        .padding(.top, 34)
                    Text("The full magic")
                        .font(.tale(36))
                        .foregroundStyle(Noel.cream)
                        .padding(.top, 22)
                    Text("One purchase for all your children. No subscription.")
                        .font(.ui(16))
                        .foregroundStyle(Noel.cream.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 30)

                    VStack(alignment: .leading, spacing: 18) {
                        perk("book.closed.fill", "4 more stories, including the Christmas Eve call")
                        perk("person.2.fill", "One call for brothers and sisters together")
                        perk("sparkles", "Santa mentions a special moment of the year")
                        perk("gift.fill", "Santa knows the Christmas wish")
                        perk("photo.on.rectangle.angled", "Premium keepsake cards")
                    }
                    .padding(22)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Noel.night.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Noel.gold.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.top, 26)

                    if store.owned {
                        Label("Unlocked. Thank you! ✨", systemImage: "checkmark.seal.fill")
                            .font(.ui(18, .bold))
                            .foregroundStyle(Noel.goldLight)
                            .padding(.top, 28)
                        Button { dismiss() } label: { Text("Continue ✨") }
                            .buttonStyle(MagicButtonStyle())
                            .padding(.horizontal, 28)
                            .padding(.top, 18)
                    } else {
                        Button { gate = true } label: {
                            if store.busy { ProgressView().tint(Noel.night) } else { Text("Unlock for \(store.price)") }
                        }
                        .buttonStyle(MagicButtonStyle())
                        .disabled(store.busy)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        Text("One-time purchase. The free magic call stays free.")
                            .font(.ui(13))
                            .foregroundStyle(Noel.cream.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                        HStack(spacing: 22) {
                            Button("Restore purchases") { Task { await store.restore() } }
                            Button("Not now") { dismiss() }
                        }
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Noel.cream.opacity(0.85))
                        .padding(.top, 18)
                    }
                    if let m = store.message {
                        Text(m).font(.ui(14)).foregroundStyle(Noel.goldLight).multilineTextAlignment(.center).padding(.top, 14).padding(.horizontal, 30)
                    }
                    Link("Privacy policy", destination: URL(string: "https://foldly.netlify.app/allonoel/privacy")!)
                        .font(.ui(13))
                        .foregroundStyle(Noel.cream.opacity(0.5))
                        .padding(.top, 22)
                        .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $gate) {
            ParentalGate {
                gate = false
                Task { await store.buy() }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
        .onDisappear { store.message = nil }
    }

    private func perk(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Noel.goldGradient)
                .frame(width: 26)
            Text(text)
                .font(.ui(16, .medium))
                .foregroundStyle(Noel.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// « Pour les grands » : une multiplication à taper avant tout achat.
struct ParentalGate: View {
    var onPass: () -> Void
    @State private var a = Int.random(in: 6...9)
    @State private var b = Int.random(in: 6...9)
    @State private var answer = ""
    @State private var wrong = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("For grown-ups")
                .font(.tale(28))
                .foregroundStyle(Noel.cream)
                .padding(.top, 28)
            Text("To continue, type the answer:")
                .font(.ui(16))
                .foregroundStyle(Noel.cream.opacity(0.75))
            HStack(spacing: 12) {
                Text("\(a) × \(b) =").font(.tale(34)).foregroundStyle(Noel.goldLight)
                TextField("?", text: $answer)
                    .font(.tale(34))
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .frame(width: 90)
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Noel.gold).frame(height: 1.5) }
                    .multilineTextAlignment(.center)
            }
            .modifier(Shake(amount: CGFloat(wrong)))
            .animation(.default, value: wrong)
            Button {
                if Int(answer) == a * b {
                    onPass()
                } else {
                    wrong += 1
                    answer = ""
                    a = Int.random(in: 6...9); b = Int.random(in: 6...9)
                }
            } label: { Text("Continue") }
                .buttonStyle(MagicButtonStyle(glow: false))
                .disabled(answer.isEmpty)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Noel.night.ignoresSafeArea())
        .onAppear { focused = true }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}
