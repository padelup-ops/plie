// Store.swift — Allô Père Noël
//
// La « magie complète » : un achat unique (StoreKit 2), sans abonnement. Elle débloque les quatre autres histoires,
// les appels pour frères et sœurs, l'anecdote, le cadeau et les cartes souvenirs premium.
// L'achat passe par une question pour les grands : un enfant ne peut pas acheter par accident.

import StoreKit
import SwiftUI
import UIKit

@MainActor @Observable
final class MagicStore {
    /// Le Pass Noël (saison, achat unique). L'ancien achat « magie » ouvre les mêmes portes.
    static let passID = "com.padelup.allonoel.pass"
    static let legacyID = "com.padelup.allonoel.magie"
    /// Lot consommable : 3 messages personnalisés de plus (un autre enfant).
    static let messagesID = "com.padelup.allonoel.messages"
    static let messagesPerPack = 3

    /// Vrai si le Pass Noël ou l'ancienne magie complète est acheté.
    private(set) var owned = false
    private(set) var credits = UserDefaults.standard.integer(forKey: creditsKey)
    private(set) var passProduct: Product?
    private(set) var messagesProduct: Product?
    private(set) var busy = false
    var message: LocalizedStringKey?
    private var updates: Task<Void, Never>?
    private static let creditsKey = "allonoel.messageCredits"
    private static let finishedKey = "allonoel.finishedTransactions"

    var price: String { passPrice }
    var passPrice: String { priceText(passProduct, fallback: "6.99") }
    var messagesPrice: String { priceText(messagesProduct, fallback: "2.99") }

    private func priceText(_ product: Product?, fallback: String) -> String {
        if let product { return product.displayPrice }
        if ShotMode.route != nil {
            return Decimal(string: fallback)!.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR"))
        }
        return "…"
    }

    func start() async {
        if ShotMode.route == "owned" { owned = true }
        guard ShotMode.route == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await self?.grant(t)
                    await t.finish()
                }
            }
        }
        for await result in Transaction.unfinished {
            if case .verified(let t) = result {
                await grant(t)
                await t.finish()
            }
        }
        await refresh()
        let found = (try? await Product.products(for: [Self.passID, Self.legacyID, Self.messagesID])) ?? []
        passProduct = found.first { $0.id == Self.passID }
        messagesProduct = found.first { $0.id == Self.messagesID }
    }

    func refresh() async {
        var has = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil,
               t.productID == Self.passID || t.productID == Self.legacyID {
                has = true
            }
        }
        owned = has
    }

    func buy() async { await buy(passProduct, id: Self.passID) }
    func buyMessages() async { await buy(messagesProduct, id: Self.messagesID) }

    private func buy(_ loaded: Product?, id: String) async {
        let product = loaded ?? (try? await Product.products(for: [id]))?.first
        guard let product else { message = "The App Store can't be reached. Try again in a moment."; return }
        if product.id == Self.passID { passProduct = product }
        if product.id == Self.messagesID { messagesProduct = product }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v {
                    await grant(t)
                    await t.finish()
                }
            case .pending:
                message = "The purchase is waiting for approval."
            default: break
            }
        } catch {
            message = "The purchase didn't go through. Nothing was charged."
        }
    }

    /// Un message de plus pour un autre enfant. Rien n'est dépensé si le compteur est à zéro.
    func spendCredit() -> Bool {
        guard credits > 0 else { return false }
        credits -= 1
        UserDefaults.standard.set(credits, forKey: Self.creditsKey)
        return true
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = owned ? "Pass unlocked. Thank you! ✨" : "No purchase to restore on this Apple account."
    }

    private func grant(_ t: StoreKit.Transaction) async {
        if t.revocationDate != nil { await refresh(); return }
        if t.productID == Self.passID || t.productID == Self.legacyID {
            owned = true
            return
        }
        guard t.productID == Self.messagesID else { return }
        var done = Set(UserDefaults.standard.stringArray(forKey: Self.finishedKey) ?? [])
        let id = String(t.id)
        guard !done.contains(id) else { return }
        done.insert(id)
        UserDefaults.standard.set(Array(done), forKey: Self.finishedKey)
        credits += Self.messagesPerPack
        UserDefaults.standard.set(credits, forKey: Self.creditsKey)
    }
}

// MARK: - La page d'achat

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gate = false
    @State private var messagesGate = false

    var body: some View {
        ZStack {
            NightScene(moon: false, trees: false)
            Snowfall(count: 40, opacity: 0.6)
            ScrollView {
                VStack(spacing: 0) {
                    SantaMedallion(size: 120)
                        .padding(.top, 34)
                    Text("Christmas Pass")
                        .font(.tale(36))
                        .foregroundStyle(Noel.cream)
                        .padding(.top, 22)
                    Text("One purchase for the whole season. No subscription.")
                        .font(.ui(16))
                        .foregroundStyle(Noel.cream.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 30)

                    VStack(alignment: .leading, spacing: 18) {
                        perk("phone.fill", "Personalized calls, in Santa's voice")
                        perk("person.fill", "Santa says their name, age and what you told him")
                        perk("envelope.fill", "A letter from Santa to print or share")
                        perk("rosette", "A good-child certificate")
                        perk("calendar", "An advent calendar, one message a day")
                        perk("square.and.arrow.up", "Cards you can share, with the app's name")
                    }
                    .padding(22)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Noel.night.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Noel.gold.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.top, 26)

                    if store.owned {
                        Label("Pass unlocked. Thank you! ✨", systemImage: "checkmark.seal.fill")
                            .font(.ui(18, .bold))
                            .foregroundStyle(Noel.goldLight)
                            .padding(.top, 28)
                        Button { dismiss() } label: { Text("Continue ✨") }
                            .buttonStyle(MagicButtonStyle())
                            .padding(.horizontal, 28)
                            .padding(.top, 18)
                    } else {
                        Button { gate = true } label: {
                            if store.busy { ProgressView().tint(Noel.night) } else { Text("Unlock the Pass for \(store.passPrice)") }
                        }
                        .buttonStyle(MagicButtonStyle())
                        .disabled(store.busy)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        Text("One-time purchase. A short preview stays free. No ads, no account.")
                            .font(.ui(13))
                            .foregroundStyle(Noel.cream.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .padding(.horizontal, 28)
                        Button { messagesGate = true } label: {
                            Text("3 extra messages for \(store.messagesPrice)")
                        }
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Noel.goldLight)
                        .padding(.top, 16)
                        Text("Messages left: \(store.credits)")
                            .font(.ui(13))
                            .foregroundStyle(Noel.cream.opacity(0.55))
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
                    GatedLink(title: "Privacy policy", url: NoelLinks.privacy)
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
        .sheet(isPresented: $messagesGate) {
            ParentalGate {
                messagesGate = false
                Task { await store.buyMessages() }
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

enum ReviewPrompt {
    private static let key = "allonoel.reviewAsked"
    /// Une seule fois, après un appel complet (pas l'aperçu).
    static func ask() {
        guard ShotMode.route == nil, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        AppStore.requestReview(in: scene)
    }
}

enum NoelLinks {
    static let privacy = URL(string: "https://foldly.netlify.app/allonoel/privacy")!
    /// Pas d'identifiant d'app en dur : la recherche App Store, dans l'image partagée.
    static let storeSearch = URL(string: "https://apps.apple.com/search?term=All%C3%B4%20P%C3%A8re%20No%C3%ABl")!
    static let watermark = "Allô Père Noël  ·  apps.apple.com"
}

/// Un lien vers l'extérieur : la question pour les grands d'abord (règle de la catégorie Enfants).
struct GatedLink: View {
    var title: LocalizedStringKey
    var url: URL
    @State private var gate = false

    var body: some View {
        Button(title) { gate = true }
            .sheet(isPresented: $gate) {
                ParentalGate {
                    gate = false
                    UIApplication.shared.open(url)
                }
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
            }
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
