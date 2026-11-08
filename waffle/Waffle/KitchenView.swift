import SwiftUI

// MARK: - La cuisine, à l'écran
//
// Duo ouvert : en haut le client, son ticket, et le couvercle de l'appareil (sa charnière tombe
// pile sur celle du Duo). En bas la plaque avec la gaufre, puis le plateau des garnitures.
// Duo fermé : l'écran extérieur montre le gaufrier fermé qui grésille et la jauge de cuisson.

struct KitchenView: View {
    @Environment(Career.self) private var progress
    @State private var kitchen: Kitchen
    let onExit: () -> Void
    let onNext: () -> Void

    init(kitchen: Kitchen, onExit: @escaping () -> Void, onNext: @escaping () -> Void) {
        _kitchen = State(initialValue: kitchen)
        self.onExit = onExit
        self.onNext = onNext
    }

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if kitchen.closed {
                    CookingView(kitchen: kitchen)
                } else {
                    openKitchen(size, safe: geo.safeAreaInsets)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .onReceive(ticker) { _ in kitchen.tick(1.0 / 30.0) }
        .onHinge { kitchen.hinge($0) }
        .onDisappear { Sound.stopLoop() }
        .onChange(of: kitchen.phase) { _, p in
            if p == .dayOver {
                if kitchen.rush { progress.recordRush(kitchen.coins) } else { progress.record(day: kitchen.day, stars: kitchen.dayStars) }
            }
        }
        .onAppear {
            #if DEBUG
            if let shot = UserDefaults.standard.string(forKey: "shot"), shot != "menu", shot != "paywall", shot != "ready" { kitchen.demo(shot) }
            #endif
        }
    }

    // MARK: Duo ouvert (posé en L)
    //
    // En haut (l'écran debout) : le client, son ticket, et le comptoir avec les garnitures.
    // En bas (l'écran à plat sur la table) : le gaufrier ouvert, avec la gaufre en grand.

    private func openKitchen(_ size: CGSize, safe: EdgeInsets) -> some View {
        let W = size.width, H = size.height, half = H / 2
        let top = max(safe.top, 12) + 54
        let trayH = min(half * 0.4, 150)
        let counterTop = half - trayH - 6
        let bottomPad = max(safe.bottom, 8) + 4
        let ironRect = CGRect(x: 10, y: half + 10, width: W - 20, height: half - 10 - bottomPad)
        let waffle = min(ironRect.width * 0.86, ironRect.height * 0.86)
        return ZStack(alignment: .topLeading) {
            // ----- En haut : le mur, le client, le ticket, le comptoir et les garnitures
            WallBackground()
                .frame(width: W, height: half)
            if let order = kitchen.order {
                let custH = max(60, min(counterTop - top + 14, W * 0.36 * 1.0667))
                let custW = custH / 1.0667
                Image("cust\(order.customer)_\(kitchen.customerMood)")
                    .resizable().scaledToFit()
                    .frame(width: custW)
                    .position(x: W * 0.2, y: counterTop - custH / 2 + custH * 0.08)
                    .id(order.customer)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                PatienceBar(value: kitchen.patienceLeft)
                    .frame(width: min(custW * 0.9, 110), height: 10)
                    .position(x: W * 0.2, y: max(top - 4, counterTop - custH + 2))
                TicketView(kitchen: kitchen, order: order, height: counterTop - top - 4)
                    .frame(width: W * 0.56)
                    .position(x: W * 0.69, y: (top + counterTop - 4) / 2)
                    .id(order.number)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            Counter()
                .frame(width: W, height: half - counterTop)
                .offset(y: counterTop)
            TrayView(kitchen: kitchen)
                .frame(width: W - 20, height: trayH - 16)
                .position(x: W / 2, y: counterTop + 16 + (trayH - 16) / 2)

            // ----- En bas : le gaufrier ouvert, en grand
            Worktop()
                .frame(width: W, height: half)
                .offset(y: half)
            IronPlate()
                .frame(width: ironRect.width, height: ironRect.height)
                .position(x: ironRect.midX, y: ironRect.midY)
            PlateView(kitchen: kitchen, size: waffle, lift: ironRect.midY - top - (counterTop - top) * 0.45)
                .position(x: ironRect.midX, y: ironRect.midY)
                .modifier(Shake(amount: 8, shakes: CGFloat(kitchen.shake)))
                .animation(.default, value: kitchen.shake)

            // ----- Par-dessus
            HUD(kitchen: kitchen, onExit: onExit)
                .padding(.leading, 14)
                .padding(.trailing, 52)   // la caméra du Duo, en haut à droite
                .padding(.top, max(safe.top, 12) + 4)
                .frame(width: W)
            if let hint = kitchen.hint {
                Bubble(text: hint)
                    .position(x: W / 2, y: half + 30)
                    .transition(.scale.combined(with: .opacity))
            }
            if kitchen.phase == .served || kitchen.phase == .gone, let s = kitchen.last {
                ResultCard(served: s)
                    .position(x: W / 2, y: (top + counterTop) / 2)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if kitchen.phase == .ready {
                StartCard(kitchen: kitchen)
                    .frame(width: W, height: H)
            }
            if kitchen.phase == .dayOver {
                SummaryCard(kitchen: kitchen, onExit: onExit, onNext: onNext, onAgain: { kitchen = Kitchen(day: kitchen.day, rush: kitchen.rush) })
                    .frame(width: W, height: H)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: kitchen.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: kitchen.hint)
    }
}

/// La moitié basse du gaufrier ouvert : elle remplit l'écran du bas, posé sur la table.
struct IronPlate: View {
    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let inset: CGFloat = min(W, H) * 0.06
            ZStack {
                // l'ombre et le corps
                RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Ink.line).offset(y: 6)
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x7FE0D6), Color(hex: 0x2FA79E)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Ink.line, lineWidth: 5)
                // reflet
                Capsule().fill(.white.opacity(0.35))
                    .frame(width: W * 0.5, height: 7)
                    .position(x: W * 0.4, y: inset * 0.55)
                // la plaque
                let pr = CGRect(x: inset, y: inset, width: W - inset * 2, height: H - inset * 2)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A4650), Color(hex: 0x2B2830)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        Canvas { ctx, size in
                            let n = 9.0
                            let cell = min(size.width, size.height) / n
                            let cols = Int(size.width / cell), rows = Int(size.height / cell)
                            let ox = (size.width - Double(cols) * cell) / 2, oy = (size.height - Double(rows) * cell) / 2
                            for c in 0..<cols { for r in 0..<rows {
                                let rect = CGRect(x: ox + Double(c) * cell + cell * 0.12, y: oy + Double(r) * cell + cell * 0.12, width: cell * 0.76, height: cell * 0.76)
                                ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.14), with: .color(Color(hex: 0x1E1C22)))
                                ctx.fill(Path(roundedRect: rect.insetBy(dx: cell * 0.1, dy: cell * 0.1).offsetBy(dx: 0, dy: -cell * 0.04), cornerRadius: cell * 0.1), with: .color(Color(hex: 0x57525E).opacity(0.5)))
                            } }
                        }
                        .padding(8)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Ink.line, lineWidth: 4))
                    .frame(width: pr.width, height: pr.height)
                    .position(x: pr.midX, y: pr.midY)
                // la charnière, contre le pli du Duo
                Capsule().fill(LinearGradient(colors: [Color(hex: 0xF4F6FA), Color(hex: 0xA8AEBC)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Ink.line, lineWidth: 4))
                    .frame(width: W * 0.34, height: 18)
                    .position(x: W / 2, y: 0)
                // le voyant
                Circle().fill(Color(hex: 0xFF6B5A)).overlay(Circle().strokeBorder(Ink.line, lineWidth: 4))
                    .overlay(Circle().fill(.white.opacity(0.8)).frame(width: 6, height: 6).offset(x: -3, y: -3))
                    .frame(width: 22, height: 22)
                    .position(x: W - inset * 0.5, y: H - inset * 0.5)
            }
        }
    }
}

// MARK: - Le décor

struct WallBackground: View {
    var body: some View {
        ZStack {
            Color(hex: 0xF4E6CF)
            Image("wall_tile").resizable(resizingMode: .tile).opacity(0.9)
            LinearGradient(colors: [Color(hex: 0xFFE2B0).opacity(0.5), .clear, Color(hex: 0x8A5530).opacity(0.18)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }
}

struct Counter: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle().fill(LinearGradient(colors: [Color(hex: 0xE6B07A), Ink.wood], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(.white.opacity(0.35)).frame(height: 3).offset(y: 3)
            }
            .frame(height: 16)
            .overlay(Rectangle().frame(height: 3).foregroundStyle(Ink.line), alignment: .top)
            .overlay(Rectangle().frame(height: 3).foregroundStyle(Ink.line), alignment: .bottom)
            ZStack {
                Color(hex: 0xE8453C)
                HStack(spacing: 18) {
                    ForEach(0..<30, id: \.self) { _ in Rectangle().fill(.white.opacity(0.9)).frame(width: 18) }
                }
                .rotationEffect(.degrees(0))
                .opacity(0.9)
            }
            .clipped()
        }
    }
}

struct Worktop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xEDE4D6), Color(hex: 0xDCCDB8)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var seed: UInt64 = 7
                func r() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(UInt32.max) }
                for _ in 0..<160 {
                    let p = CGPoint(x: r() * size.width, y: r() * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 2 + r() * 3, height: 2 + r() * 2)),
                             with: .color(Color(hex: r() > 0.5 ? 0xB8A68C : 0xFFFFFF).opacity(0.5)))
                }
            }
            VStack { Rectangle().fill(Ink.line.opacity(0.35)).frame(height: 2); Spacer() }
        }
        .clipped()
    }
}

// MARK: - La gaufre sur la plaque

struct PlateView: View {
    let kitchen: Kitchen
    let size: CGFloat
    /// De combien la gaufre monte quand on la sert (vers le client, en haut).
    var lift: CGFloat = 300

    var body: some View {
        ZStack {
            switch kitchen.phase {
            case .poured, .cooking:
                Image("batter").resizable().scaledToFit()
                    .frame(width: size * 0.92)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            case .topping, .served:
                ZStack {
                    Image(kitchen.cooked.image).resizable().scaledToFit()
                    ForEach(Array(kitchen.stack.enumerated()), id: \.offset) { _, ing in
                        Image(ing.image).resizable().scaledToFit()
                            .transition(.asymmetric(insertion: .scale(scale: 1.5).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(width: size, height: size)
                // Servie : la gaufre rapetisse et monte vers le client, par-dessus la charnière.
                .scaleEffect(kitchen.phase == .served ? 0.4 : 1)
                .offset(y: kitchen.phase == .served ? -lift : 0)
                .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: kitchen.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: kitchen.stack.count)
    }
}

// MARK: - Le ticket de commande

struct TicketView: View {
    let kitchen: Kitchen
    let order: Order
    var height: CGFloat = 200

    var body: some View {
        let n = CGFloat(order.layers.count)
        let row = max(14, min(28, (height - 44) / max(1, n)))
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(order.recipe.name)
                    .font(.toon(min(16, row * 0.75)))
                    .foregroundStyle(Ink.line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
            }
            ForEach(Array(order.layers.enumerated()), id: \.offset) { i, ing in
                HStack(spacing: 5) {
                    ZStack {
                        if i < kitchen.stack.count {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green)
                        } else if i == kitchen.stack.count && kitchen.phase == .topping {
                            Image(systemName: "arrowtriangle.right.fill").foregroundStyle(Ink.orange)
                        } else {
                            Text("\(i + 1)").font(.toon(row * 0.45)).foregroundStyle(Ink.line.opacity(0.5))
                        }
                    }
                    .font(.system(size: row * 0.5, weight: .black))
                    .frame(width: row * 0.6)
                    Image(ing.image).resizable().scaledToFit().frame(width: row, height: row)
                    Text(ing.name).font(.toon(row * 0.52, .bold)).foregroundStyle(Ink.line.opacity(i < kitchen.stack.count ? 0.4 : 1))
                        .strikethrough(i < kitchen.stack.count, color: Ink.line.opacity(0.4))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(height: row)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxHeight: height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Ink.line).offset(x: 3, y: 4)
                RoundedRectangle(cornerRadius: 10).fill(Ink.paper)
                RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 3)
            }
        )
        .overlay(alignment: .top) {
            Circle().fill(Ink.red).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Ink.line, lineWidth: 3))
                .overlay(Circle().fill(.white.opacity(0.6)).frame(width: 4, height: 4).offset(x: -2, y: -2))
                .offset(y: -5)
        }
        .rotationEffect(.degrees(1.5))
    }
}

struct PatienceBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xEADFCC))
                Capsule().fill(value > 0.5 ? Ink.green : (value > 0.25 ? Ink.gold : Ink.red))
                    .frame(width: max(8, g.size.width * value))
                Capsule().strokeBorder(Ink.line, lineWidth: 2.5)
            }
        }
        .animation(.linear(duration: 0.1), value: value)
        .accessibilityLabel(T("Patience du client", "Customer's patience"))
    }
}

// MARK: - Le plateau des garnitures

struct TrayView: View {
    let kitchen: Kitchen

    var body: some View {
        ZStack {
            switch kitchen.phase {
            case .pour:
                Button {
                    kitchen.pour()
                } label: {
                    HStack(spacing: 12) {
                        Image("jug").resizable().scaledToFit().frame(height: 74)
                            .rotationEffect(.degrees(-14))
                        Text(T("Verser la pâte", "Pour the batter")).font(.toon(22)).foregroundStyle(Ink.line)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color(hex: 0xFFE3A8)))
                    .background(RoundedRectangle(cornerRadius: 28).fill(Ink.line).offset(y: 5))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Ink.line, lineWidth: 3))
                }
                .buttonStyle(Squish())
                .transition(.scale.combined(with: .opacity))
            case .poured:
                VStack(spacing: 14) {
                    if kitchen.hasHinge {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone.gen3").font(.system(size: 34, weight: .bold)).foregroundStyle(Ink.line)
                                .symbolEffect(.bounce, options: .repeating)
                            Text(T("Ferme le Duo pour fermer le gaufrier", "Close the Duo to close the waffle iron"))
                                .font(.toon(19)).foregroundStyle(Ink.line).multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Ink.paper))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.line, lineWidth: 3))
                    } else {
                        Button {
                            kitchen.toggleLid()
                        } label: {
                            Label(T("FERMER LE GAUFRIER", "CLOSE THE IRON"), systemImage: "arrow.down.to.line")
                                .font(.toon(20)).frame(maxWidth: .infinity, minHeight: 62)
                        }
                        .buttonStyle(ToonButton(color: Ink.red))
                    }
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            default:
                toppings
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: kitchen.phase)
    }

    private var toppings: some View {
        let items = kitchen.tray
        let cols = max(1, min(6, items.count <= 6 ? items.count : Int(ceil(Double(items.count) / 2))))
        return GeometryReader { g in
            let rows = Int(ceil(Double(items.count) / Double(cols)))
            let cell = min((g.size.width - CGFloat(cols - 1) * 10) / CGFloat(cols), (g.size.height - CGFloat(max(0, rows - 1)) * 4) / CGFloat(max(1, rows)), 92)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 10), count: cols), spacing: 4) {
                ForEach(items) { ing in
                    IngredientButton(image: ing.image, name: ing.name, highlight: false, size: cell) { kitchen.add(ing) }
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .center)
        }
        .opacity(kitchen.phase == .topping ? 1 : 0.45)
        .allowsHitTesting(kitchen.phase == .topping)
    }
}

struct IngredientButton: View {
    let image: String
    let name: String
    let highlight: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(Ink.line).offset(y: 4)
                    Circle().fill(highlight ? Color(hex: 0xFFE3A8) : Color(hex: 0xF3DFC0))
                    Circle().strokeBorder(highlight ? Ink.orange : Ink.line, lineWidth: highlight ? 4 : 3)
                    Image(image).resizable().scaledToFit().padding(size * 0.12)
                }
                .frame(width: size * 0.78, height: size * 0.78)
                .scaleEffect(highlight ? 1.06 : 1)
                Text(name)
                    .font(.toon(max(9, size * 0.14), .bold))
                    .foregroundStyle(Ink.line)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(Squish())
        .accessibilityLabel(name)
    }
}

struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Le haut de l'écran

struct HUD: View {
    let kitchen: Kitchen
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onExit) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .black)).frame(width: 40, height: 38)
            }
            .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line, radius: 19, depth: 3))
            .accessibilityLabel(T("Quitter", "Quit"))
            Pill {
                if kitchen.rush {
                    Image(systemName: "flame.fill").foregroundStyle(Ink.orange)
                    Text("Rush")
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(i < 3 - kitchen.lostCount ? Ink.red : Ink.line.opacity(0.2))
                    }
                } else {
                    Text(T("Jour \(kitchen.day)", "Day \(kitchen.day)"))
                    Image(systemName: "clock.fill").foregroundStyle(kitchen.shiftLeft < 15 ? Ink.red : Ink.orange)
                    Text("\(Int(kitchen.shiftLeft.rounded(.up)))").monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            Pill {
                Image("coin").resizable().frame(width: 22, height: 22)
                Text("\(kitchen.coins)").monospacedDigit().contentTransition(.numericText())
                if !kitchen.rush {
                    Text("/ \(kitchen.target)").font(.toon(13, .bold)).foregroundStyle(Ink.line.opacity(0.5))
                }
            }
            .animation(.spring, value: kitchen.coins)
        }
    }
}

struct Bubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.toon(15))
            .foregroundStyle(Ink.line)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Ink.paper))
            .overlay(Capsule().strokeBorder(Ink.line, lineWidth: 3))
            .background(Capsule().fill(Ink.line).offset(y: 3))
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(shakes * .pi * 4), y: 0))
    }
}

// MARK: - Le résultat d'une commande

struct ResultCard: View {
    let served: Served

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Image(i < served.stars ? "star_on" : "star_off").resizable().frame(width: 40, height: 40)
                        .scaleEffect(i < served.stars ? 1 : 0.85)
                }
            }
            Text(served.comment).font(.toon(24)).foregroundStyle(Ink.line)
            if served.coins > 0 {
                HStack(spacing: 6) {
                    Image("coin").resizable().frame(width: 26, height: 26)
                    Text("+\(served.coins)").font(.toon(24)).foregroundStyle(Color(hex: 0xD98A1E))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 22).fill(Ink.paper))
        .background(RoundedRectangle(cornerRadius: 22).fill(Ink.line).offset(y: 5))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.line, lineWidth: 3))
    }
}

// MARK: - Début et fin de journée

struct StartCard: View {
    let kitchen: Kitchen

    var body: some View {
        let fresh = Recipe.all.filter { $0.day == kitchen.day }
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(kitchen.rush ? "Rush" : T("Jour \(kitchen.day)", "Day \(kitchen.day)"))
                    .font(.toon(40, .black)).foregroundStyle(Ink.line)
                Text(kitchen.rush ? T("Les clients arrivent de plus en plus vite. 3 ratés et c'est fini.", "Customers come faster and faster. 3 misses and it's over.")
                                  : T("Objectif : \(kitchen.target) pièces en 100 secondes", "Goal: \(kitchen.target) coins in 100 seconds"))
                    .font(.toon(16, .bold)).foregroundStyle(Ink.line.opacity(0.8)).multilineTextAlignment(.center)
                if !fresh.isEmpty && !kitchen.rush {
                    VStack(spacing: 8) {
                        Text(T("Nouveau au menu", "New on the menu")).font(.toon(13)).foregroundStyle(Ink.orange)
                        ForEach(fresh) { r in
                            HStack(spacing: 6) {
                                Text(r.name).font(.toon(17)).foregroundStyle(Ink.line)
                                ForEach(Array(r.layers.enumerated()), id: \.offset) { _, ing in
                                    Image(ing.image).resizable().scaledToFit().frame(width: 30, height: 30)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xFFF1D6)))
                }
                Text(T("Verse la pâte, ferme le Duo pour cuire, rouvre quand le curseur est dans le vert, puis garnis comme sur le ticket !",
                       "Pour the batter, close the Duo to cook, open it when the cursor is in the green, then top it like the ticket!"))
                    .font(.toon(14, .semibold)).foregroundStyle(Ink.line.opacity(0.75)).multilineTextAlignment(.center)
                Button {
                    kitchen.start()
                } label: {
                    Text(T("C'est parti !", "Let's cook!")).font(.toon(24)).frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(ToonButton(color: Ink.orange))
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.paper))
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.line).offset(y: 6))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Ink.line, lineWidth: 3.5))
            .padding(22)
        }
    }
}

struct SummaryCard: View {
    let kitchen: Kitchen
    let onExit: () -> Void
    let onNext: () -> Void
    let onAgain: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(kitchen.rush ? T("Fin du rush", "Rush over") : T("Fin de la journée", "Day over"))
                    .font(.toon(30, .black)).foregroundStyle(Ink.line)
                if !kitchen.rush {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(i < kitchen.dayStars ? "star_on" : "star_off").resizable().frame(width: 58, height: 58)
                                .rotationEffect(.degrees(Double(i - 1) * 10))
                                .offset(y: i == 1 ? -8 : 0)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image("coin").resizable().frame(width: 34, height: 34)
                    Text("\(kitchen.coins)").font(.toon(38, .black)).foregroundStyle(Color(hex: 0xD98A1E))
                    if !kitchen.rush { Text("/ \(kitchen.target)").font(.toon(20, .bold)).foregroundStyle(Ink.line.opacity(0.5)) }
                }
                Text(T("\(kitchen.servedCount) gaufres servies · \(kitchen.perfectCount) parfaites", "\(kitchen.servedCount) served · \(kitchen.perfectCount) perfect"))
                    .font(.toon(15, .bold)).foregroundStyle(Ink.line.opacity(0.75))
                if !kitchen.rush && kitchen.dayStars > 0 && kitchen.day < Kitchen.lastDay {
                    Button(action: onNext) {
                        Text(T("Jour suivant", "Next day")).font(.toon(22)).frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(ToonButton(color: Ink.green))
                }
                if !kitchen.rush && kitchen.dayStars == 0 {
                    Text(T("Il faut au moins une étoile pour ouvrir le jour suivant.", "You need at least one star to open the next day."))
                        .font(.toon(14, .semibold)).foregroundStyle(Ink.red).multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button(action: onAgain) {
                        Text(T("Rejouer", "Again")).font(.toon(18)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(ToonButton(color: Ink.orange))
                    Button(action: onExit) {
                        Text(T("Menu", "Menu")).font(.toon(18)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line))
                }
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.paper))
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.line).offset(y: 6))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Ink.line, lineWidth: 3.5))
            .padding(22)
        }
    }
}

// MARK: - Duo fermé : la cuisson
//
// Le gaufrier fermé grésille. Sa jauge : rouge aux bouts, jaune, vert au milieu ; le curseur va et vient.
// Le voyant du gaufrier passe au vert quand le curseur est dans le vert : c'est là qu'il faut ouvrir.

struct CookingView: View {
    let kitchen: Kitchen

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let unit = min(W, H * 0.7)
            let cooking = kitchen.phase == .cooking
            let zone = kitchen.cursorZone
            ZStack {
                RadialGradient(colors: [Color(hex: 0xFFD08A), Color(hex: 0xFF8A3D)], center: .center, startRadius: 10, endRadius: max(W, H))
                    .ignoresSafeArea()
                VStack(spacing: unit * 0.05) {
                    Text(cooking ? (zone == .green ? T("MAINTENANT ! Ouvre !", "NOW! Open it!") : T("Ouvre quand c'est vert", "Open when it's green"))
                                 : T("Verse la pâte d'abord !", "Pour the batter first!"))
                        .font(.toon(unit * 0.075, .black))
                        .foregroundStyle(cooking && zone == .green ? Color(hex: 0x1F7A2E) : Ink.line)
                        .scaleEffect(cooking && zone == .green ? 1.08 : 1)
                        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: zone == .green)
                    ZStack {
                        Steam(active: cooking, burnt: false)
                            .frame(width: unit * 0.8, height: unit * 0.35)
                            .offset(y: -unit * 0.3)
                        IronClosed(light: cooking ? zone : .red, width: unit * 0.9)
                    }
                    if cooking, kitchen.order != nil {
                        TimingGauge(kitchen: kitchen)
                            .frame(width: unit * 0.92, height: unit * 0.14)
                        PatienceBar(value: kitchen.patienceLeft).frame(width: unit * 0.6, height: unit * 0.035)
                    }
                    if !kitchen.hasHinge {
                        Button {
                            kitchen.toggleLid()
                        } label: {
                            Label(T("OUVRIR", "OPEN"), systemImage: "arrow.up.to.line").font(.toon(22)).frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .buttonStyle(ToonButton(color: Ink.green))
                        .frame(width: unit * 0.8)
                        .padding(.top, 6)
                    }
                }
                .frame(width: W, height: H)
            }
        }
    }
}

/// Le gaufrier fermé, avec son voyant qui change de couleur (rouge, jaune, vert).
struct IronClosed: View {
    let light: Kitchen.Zone
    let width: CGFloat

    var body: some View {
        let h = width * 350 / 600
        let r = width * 0.055
        let color: Color = light == .green ? Color(hex: 0x3DDC5A) : (light == .yellow ? Color(hex: 0xFFD23C) : Color(hex: 0xFF5A4A))
        ZStack {
            Image("iron_closed").resizable().scaledToFit().frame(width: width, height: h)
            // le voyant, en bas à droite de l'appareil
            ZStack {
                Circle().fill(color.opacity(0.45)).frame(width: r * 4, height: r * 4).blur(radius: r * 0.8)
                Circle().fill(color).overlay(Circle().strokeBorder(Ink.line, lineWidth: max(3, r * 0.3)))
                    .frame(width: r * 2, height: r * 2)
                Circle().fill(.white.opacity(0.8)).frame(width: r * 0.6, height: r * 0.6).offset(x: -r * 0.35, y: -r * 0.35)
            }
            .offset(x: width * (470.0 / 600 - 0.5), y: h * (270.0 / 350 - 0.5))
            .animation(.easeOut(duration: 0.08), value: light)
        }
        .frame(width: width, height: h)
    }
}

/// La jauge de cuisson : rouge | jaune | vert | jaune | rouge, et le curseur qui va et vient.
struct TimingGauge: View {
    let kitchen: Kitchen

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let gh = kitchen.greenHalf, yh = kitchen.yellowHalf
            let parts: [(Double, Double, Color)] = [
                (0, 0.5 - yh, Color(hex: 0xF0483E)),
                (0.5 - yh, 0.5 - gh, Color(hex: 0xFFC93C)),
                (0.5 - gh, 0.5 + gh, Color(hex: 0x3DC85A)),
                (0.5 + gh, 0.5 + yh, Color(hex: 0xFFC93C)),
                (0.5 + yh, 1, Color(hex: 0xF0483E)),
            ]
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: H / 2.4).fill(Ink.line).offset(y: 5)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<parts.count, id: \.self) { i in
                        Rectangle().fill(parts[i].2)
                            .frame(width: (parts[i].1 - parts[i].0) * W, height: H)
                            .offset(x: parts[i].0 * W)
                    }
                    // un reflet
                    Rectangle().fill(.white.opacity(0.3)).frame(width: W, height: H * 0.22).offset(y: H * 0.12)
                }
                .clipShape(RoundedRectangle(cornerRadius: H / 2.4))
                RoundedRectangle(cornerRadius: H / 2.4).strokeBorder(Ink.line, lineWidth: 4)
                // le curseur
                let x = 8 + kitchen.cursor * (W - 16)
                VStack(spacing: 0) {
                    Triangle().fill(Ink.line).frame(width: 22, height: 14)
                    RoundedRectangle(cornerRadius: 3).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Ink.line, lineWidth: 3))
                        .frame(width: 12, height: H + 8)
                }
                .offset(x: x - 11, y: -16)
            }
        }
        .accessibilityLabel(T("Jauge de cuisson", "Cooking gauge"))
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() }
    }
}

/// De la vapeur (ou de la fumée noire si ça brûle) qui monte de l'appareil.
struct Steam: View {
    let active: Bool
    let burnt: Bool

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                guard active else { return }
                let t = tl.date.timeIntervalSinceReferenceDate
                for k in 0..<9 {
                    let p = (t * 0.45 + Double(k) / 9).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.15 + 0.7 * Double(k % 3) / 2) + sin(t * 2 + Double(k)) * 10
                    let y = size.height * (1 - p)
                    let r = 10 + p * 26
                    let c: Color = burnt ? Color(hex: 0x3A3A3A) : .white
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c.opacity((1 - p) * 0.65)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
