// Store.swift — Twinfold
//
// Twinfold Pro: one purchase, for good (no subscription). The free app does everything a browser needs with two
// pages; Pro adds the extras: AI beside the page, unlimited pairs, your own gestures, scrolling together, followed
// sites, read aloud and PDF.

import StoreKit
import SwiftUI

@MainActor @Observable
final class Store {
    static let shared = Store()
    static let proID = "com.padelup.twinfold.pro"

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var busy = false
    var message: String?

    /// What asked for Pro (shown at the top of the screen).
    var asking: ProFeature?

    private var updates: Task<Void, Never>?

    private init() {
        if let shot = ShotMode.current { isPro = shot != "paywall"; return }
        isPro = UserDefaults.standard.bool(forKey: "pro.cached")
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    func load() async {
        product = try? await Product.products(for: [Self.proID]).first
        await refresh()
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.proID, t.revocationDate == nil { owned = true }
        }
        isPro = owned
        UserDefaults.standard.set(owned, forKey: "pro.cached")
    }

    func buy() async {
        guard let product else {
            message = String(localized: "The App Store can't be reached. Try again in a moment.")
            await load()
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish() }
                await refresh()
                if isPro { asking = nil; Browser.shared.flash(String(localized: "Welcome to Twinfold Pro")) }
            case .pending:
                message = String(localized: "Your purchase is waiting for approval.")
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
        message = isPro ? nil : String(localized: "No purchase to restore on this Apple Account.")
        if isPro { asking = nil }
    }

    /// Runs `action` with Pro, or shows what Pro brings.
    func gate(_ feature: ProFeature, _ action: () -> Void) {
        if isPro { action(); return }
        let browser = Browser.shared
        if browser.sheet != nil {
            browser.sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.asking = feature }
        } else {
            asking = feature
        }
    }
}

enum ProFeature: String, Identifiable, CaseIterable {
    case ai, pairs, gestures, syncScroll, follow, readAloud, pdf, bilingual, general
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .ai: return "AI beside the page"
        case .pairs: return "Unlimited pairs"
        case .gestures: return "Your own gestures"
        case .syncScroll: return "Scroll together"
        case .follow: return "Followed sites"
        case .readAloud: return "Read aloud"
        case .pdf: return "Save as PDF"
        case .bilingual: return "Bilingual reading"
        case .general: return "Twinfold Pro"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .ai: return "ChatGPT, Claude, Gemini, Le Chat, Perplexity or Copilot in the other pane, already asked about your page."
        case .pairs: return "Save every duo of pages you love, and open them from the Home Screen."
        case .gestures: return "Seven gestures, fifteen actions: make Twinfold yours."
        case .syncScroll: return "Two pages that move as one: translations, comparisons, notes."
        case .follow: return "New articles from the sites you follow, in one list."
        case .readAloud: return "Any article, read to you while you do something else."
        case .pdf: return "Keep a whole page, exactly as it looks."
        case .bilingual: return "Any page and its translation, side by side, scrolling together."
        case .general: return "Everything Twinfold can do, for good."
        }
    }

    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .pairs: return "square.on.square"
        case .gestures: return "hand.draw"
        case .syncScroll: return "arrow.up.and.down.text.horizontal"
        case .follow: return "newspaper"
        case .readAloud: return "waveform"
        case .pdf: return "doc.richtext"
        case .bilingual: return "character.book.closed"
        case .general: return "crown"
        }
    }

    static let showcase: [ProFeature] = [.ai, .bilingual, .pairs, .gestures, .syncScroll, .follow, .readAloud, .pdf]
}

// MARK: - The Pro screen

struct ProSheet: View {
    @Environment(\.dismiss) private var dismiss
    let feature: ProFeature
    @State private var phase = false

    var body: some View {
        let store = Store.shared
        ZStack {
            LinearGradient(colors: [Brand.ink, Color(red: 0.03, green: 0.27, blue: 0.26)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    ProHero(phase: phase)
                        .frame(height: 210)
                        .padding(.top, 34)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("Twinfold Pro")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        if feature != .general {
                            Label { Text(feature.title) } icon: { Image(systemName: feature.symbol) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Brand.mint)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Brand.mint.opacity(0.14), in: Capsule())
                        }
                        Text("Two pages were only the start.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    VStack(spacing: 0) {
                        ForEach(ProFeature.showcase) { f in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: f.symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(f == feature ? Brand.coral : Brand.mint)
                                    .frame(width: 34, height: 34)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.headline).foregroundStyle(.white)
                                    Text(f.detail).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 12) {
                        Button {
                            Task { await store.buy() }
                        } label: {
                            HStack {
                                if store.busy { ProgressView().tint(Brand.ink) }
                                Text(store.product.map { String(localized: "Unlock for \($0.displayPrice)") } ?? String(localized: "Unlock Twinfold Pro"))
                            }
                            .font(.headline)
                            .foregroundStyle(Brand.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Brand.mint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Brand.mint.opacity(0.45), radius: 18, y: 8)
                        }
                        .disabled(store.busy)
                        Text("One purchase. Yours for good. No subscription.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                        if let m = store.message {
                            Text(m).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
                        }
                        Button("Restore Purchase") { Task { await store.restore() } }
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .disabled(store.busy)
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .padding(16)
            .accessibilityLabel(Text("Close"))
        }
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { phase = true }
            }
        }
        .task { if store.product == nil { await store.load() } }
    }
}

/// Two pages breathing on either side of a fold: what Twinfold is, drawn.
struct ProHero: View {
    let phase: Bool

    var body: some View {
        HStack(spacing: 10) {
            page(colors: [Brand.coral, Color(red: 0.99, green: 0.66, blue: 0.42)], lines: [0.8, 0.6, 0.7], tilt: phase ? -8 : -3)
            Capsule().fill(.white.opacity(0.35)).frame(width: 3, height: phase ? 120 : 150)
            page(colors: [Brand.mint, Brand.accent], lines: [0.55, 0.85, 0.65], tilt: phase ? 8 : 3)
        }
    }

    private func page(colors: [Color], lines: [CGFloat], tilt: Double) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.white)
            .frame(width: 118, height: 176)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 72)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, w in
                        Capsule().fill(Color(white: 0.88)).frame(width: 94 * w, height: 7)
                    }
                }
                .padding(12)
            }
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}
