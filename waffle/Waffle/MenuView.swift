import SwiftUI
import StoreKit

// MARK: - Le menu

/// Un texte blanc avec un gros contour brun (titres).
struct Outlined: View {
    let text: String
    let size: CGFloat
    var fill: Color = .white

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { k in
                let a = Double(k) / 12 * 2 * .pi
                Text(text).font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundStyle(Ink.line)
                    .offset(x: cos(a) * size * 0.07, y: sin(a) * size * 0.07)
            }
            Text(text).font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(Ink.line)
                .offset(y: size * 0.1)
            Text(text).font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(fill)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Fond orange avec des rayons de soleil qui tournent doucement.
struct Sunburst: View {
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.36)
                let r = max(size.width, size.height) * 1.2
                let t = tl.date.timeIntervalSinceReferenceDate * 0.05
                for k in 0..<16 {
                    let a0 = Double(k) / 16 * 2 * .pi + t, a1 = a0 + .pi / 16
                    var p = Path()
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a0) * r, y: c.y + sin(a0) * r))
                    p.addLine(to: CGPoint(x: c.x + cos(a1) * r, y: c.y + sin(a1) * r))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(.white.opacity(0.09)))
                }
            }
        }
        .background(RadialGradient(colors: [Color(hex: 0xFFC46B), Color(hex: 0xFF7A3D)], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 20, endRadius: 600))
        .ignoresSafeArea()
    }
}

struct MenuView: View {
    @Environment(Store.self) private var store
    @Environment(Career.self) private var progress
    let onPlay: (Int) -> Void
    let onRush: () -> Void
    let onShop: () -> Void
    @State private var float = false

    /// Le prochain jour à jouer : le premier ouvert qui n'a pas 3 étoiles.
    private var nextDay: Int {
        (1...Kitchen.lastDay).first { progress.isOpen($0) && (progress.stars[$0] ?? 0) < 3 && (store.purchased || $0 <= Kitchen.freeDays) }
            ?? min(Kitchen.lastDay, max(1, progress.stars.keys.max() ?? 1))
    }

    var body: some View {
        ZStack {
            Sunburst()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: -6) {
                        Outlined(text: "Waffle", size: 58)
                        Text("FOLD")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .kerning(6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 4)
                            .background(Capsule().fill(Ink.red))
                            .overlay(Capsule().strokeBorder(Ink.line, lineWidth: 3))
                            .rotationEffect(.degrees(-3))
                    }
                    .padding(.top, 30)

                    ZStack {
                        Steam(active: true, burnt: false).frame(width: 220, height: 120).offset(y: -96)
                        Image("iron_closed").resizable().scaledToFit().frame(width: 250)
                            .offset(y: 46)
                        ZStack {
                            Image("waffle2").resizable().scaledToFit()
                            Image("ing_spread").resizable().scaledToFit()
                            Image("ing_banana").resizable().scaledToFit()
                        }
                        .frame(width: 150)
                            .rotationEffect(.degrees(float ? -6 : 6))
                            .offset(y: float ? -40 : -24)
                    }
                    .frame(height: 230)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { float = true }
                    }

                    Button {
                        onPlay(nextDay)
                    } label: {
                        VStack(spacing: 0) {
                            Text(T("JOUER", "PLAY")).font(.toon(30, .black))
                            Text(T("Jour \(nextDay)", "Day \(nextDay)")).font(.toon(15, .bold)).opacity(0.9)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .buttonStyle(ToonButton(color: Ink.green, radius: 26, depth: 7))
                    .padding(.horizontal, 30)

                    daysGrid
                        .padding(.horizontal, 20)

                    Button(action: onRush) {
                        HStack(spacing: 10) {
                            Image(systemName: store.purchased ? "flame.fill" : "crown.fill").font(.system(size: 22, weight: .black))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(T("Rush infini", "Endless rush")).font(.toon(20))
                                Text(progress.bestRush > 0 ? T("Record : \(progress.bestRush) pièces", "Best: \(progress.bestRush) coins") : T("Jusqu'à 3 ratés", "Until 3 misses"))
                                    .font(.toon(13, .bold)).opacity(0.85)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(ToonButton(color: Ink.red, radius: 22))
                    .padding(.horizontal, 30)

                    if !store.purchased {
                        Button(action: onShop) {
                            Label(T("La cuisine complète · \(store.price)", "Full kitchen · \(store.price)"), systemImage: "crown.fill")
                                .font(.toon(17)).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(ToonButton(color: Ink.gold, text: Ink.line, radius: 20))
                        .padding(.horizontal, 30)
                    }
                    Spacer(minLength: 30)
                }
            }
        }
    }

    private var daysGrid: some View {
        VStack(spacing: 10) {
            HStack {
                Text(T("Les journées", "Days")).font(.toon(18)).foregroundStyle(Ink.line)
                Spacer()
                Image("star_on").resizable().frame(width: 20, height: 20)
                Text("\(progress.totalStars) / \(Kitchen.lastDay * 3)").font(.toon(15)).foregroundStyle(Ink.line)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(1...Kitchen.lastDay, id: \.self) { day in
                    dayTile(day)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26).fill(Ink.paper))
        .background(RoundedRectangle(cornerRadius: 26).fill(Ink.line).offset(y: 5))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Ink.line, lineWidth: 3))
    }

    private func dayTile(_ day: Int) -> some View {
        let open = progress.isOpen(day)
        let paid = day > Kitchen.freeDays && !store.purchased
        let stars = progress.stars[day] ?? 0
        return Button {
            if open || paid { onPlay(day) }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(Ink.line).offset(y: 3)
                    Circle().fill(open && !paid ? Color(hex: 0xFFE3A8) : Color(hex: 0xE8DCC8))
                    Circle().strokeBorder(Ink.line, lineWidth: 3)
                    if paid {
                        Image(systemName: "crown.fill").font(.system(size: 15, weight: .black)).foregroundStyle(Color(hex: 0xD98A1E))
                    } else if !open {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .black)).foregroundStyle(Ink.line.opacity(0.5))
                    } else {
                        Text("\(day)").font(.toon(20, .black)).foregroundStyle(Ink.line)
                    }
                }
                .frame(width: 46, height: 46)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(i < stars ? "star_on" : "star_off").resizable().frame(width: 13, height: 13)
                    }
                }
            }
        }
        .buttonStyle(Squish())
        .disabled(!open && !paid)
        .accessibilityLabel(T("Jour \(day), \(stars) étoiles", "Day \(day), \(stars) stars"))
    }
}

// MARK: - La cuisine complète (achat)

struct PaywallView: View {
    @Environment(Store.self) private var store
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .black)).frame(width: 36, height: 34)
                    }
                    .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line, radius: 17, depth: 3))
                    .accessibilityLabel(T("Fermer", "Close"))
                }
                HStack(spacing: -18) {
                    ZStack { Image("waffle2").resizable().scaledToFit(); Image("ing_strawberry").resizable().scaledToFit(); Image("ing_cream").resizable().scaledToFit() }
                        .frame(width: 96).rotationEffect(.degrees(-10))
                    ZStack { Image("waffle2").resizable().scaledToFit(); Image("ing_icecream").resizable().scaledToFit(); Image("ing_chocmelt").resizable().scaledToFit() }
                        .frame(width: 96).rotationEffect(.degrees(10)).offset(y: -8)
                }
                Text(T("La cuisine complète", "The full kitchen")).font(.toon(28, .black)).foregroundStyle(Ink.line).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    perk("calendar", T("12 journées de plus, jusqu'au jour 15", "12 more days, up to day 15"))
                    perk("fork.knife", T("Toutes les gaufres : la gourmande, dame blanche, miel-amandes, la totale…", "Every waffle: the greedy one, sundae, honey & almonds, the works…"))
                    perk("flame.fill", T("Le rush infini, pour battre ton record", "Endless rush, to beat your best"))
                    perk("checkmark.seal.fill", T("Un seul achat. Pas d'abonnement, pas de pub.", "One purchase. No subscription, no ads."))
                }
                Button {
                    Task { await store.buy() }
                } label: {
                    Group {
                        if store.busy { ProgressView().tint(.white) } else { Text(T("Tout débloquer · \(store.price)", "Unlock all · \(store.price)")) }
                    }
                    .font(.toon(21))
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(ToonButton(color: Ink.green))
                .disabled(store.busy)
                HStack(spacing: 20) {
                    Button(T("Restaurer l'achat", "Restore purchase")) { Task { await store.restore() } }
                    Button(T("Plus tard", "Later"), action: onClose)
                }
                .font(.toon(14, .bold))
                .foregroundStyle(Ink.line.opacity(0.7))
                if let m = store.message {
                    Text(m).font(.toon(13, .semibold)).foregroundStyle(Ink.red).multilineTextAlignment(.center)
                }
            }
            .padding(22)
            .frame(maxWidth: 390)
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.paper))
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.line).offset(y: 6))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Ink.line, lineWidth: 3.5))
            .padding(20)
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 17, weight: .black)).foregroundStyle(Ink.orange).frame(width: 24)
            Text(text).font(.toon(15, .semibold)).foregroundStyle(Ink.line).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - L'achat (un seul, non consommable)

@MainActor
@Observable
final class Store {
    static let fullID = "com.padelup.waffle.full"

    private(set) var product: Product?
    private(set) var purchased = UserDefaults.standard.bool(forKey: "waffle.owned")
    private(set) var busy = false
    var message: String?
    private var updates: Task<Void, Never>?

    func start() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "unlockAll") { purchased = true }
        #endif
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
        if product == nil { product = try? await Product.products(for: [Store.fullID]).first }
    }

    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Store.fullID, t.revocationDate == nil { owned = true }
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "unlockAll") { owned = true }
        #endif
        purchased = owned
        UserDefaults.standard.set(owned, forKey: "waffle.owned")
    }

    var price: String { product?.displayPrice ?? T("2,99 €", "$2.99") }

    func buy() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if product == nil { product = try? await Product.products(for: [Store.fullID]).first }
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
                    UserDefaults.standard.set(true, forKey: "waffle.owned")
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
