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

    // MARK: Duo ouvert

    private func openKitchen(_ size: CGSize, safe: EdgeInsets) -> some View {
        let W = size.width, H = size.height, half = H / 2
        let plateW = min(W * 0.9, half * 0.84)
        let plateH = plateW / 2
        let counterTop = half - plateH - 22
        return ZStack(alignment: .topLeading) {
            // ----- En haut : le mur, le client, le comptoir, le couvercle
            WallBackground()
                .frame(width: W, height: half)
            if let order = kitchen.order {
                let custW = min(W * 0.44, (counterTop - safe.top - 60) * 0.95)
                Image("cust\(order.customer)_\(kitchen.customerMood)")
                    .resizable().scaledToFit()
                    .frame(width: custW)
                    .position(x: W * 0.27, y: counterTop - custW * 1.0667 / 2 + custW * 0.12)
                    .id(order.customer)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                TicketView(kitchen: kitchen, order: order)
                    .frame(width: W * 0.46)
                    .position(x: W * 0.73, y: (safe.top + 58 + counterTop) / 2 + 4)
                    .id(order.number)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            Counter()
                .frame(width: W, height: half - counterTop)
                .offset(y: counterTop)
            Image("iron_lid")
                .resizable().scaledToFit()
                .frame(width: plateW, height: plateH)
                .position(x: W / 2, y: half - plateH / 2)

            // ----- En bas : le plan de travail, la plaque, le plateau
            Worktop()
                .frame(width: W, height: half)
                .offset(y: half)
            Image("iron_base")
                .resizable().scaledToFit()
                .frame(width: plateW, height: plateH)
                .position(x: W / 2, y: half + plateH / 2)
            PlateView(kitchen: kitchen, size: plateH * 0.98)
                .position(x: W / 2, y: half + plateH * 0.53)
                .modifier(Shake(amount: 8, shakes: CGFloat(kitchen.shake)))
                .animation(.default, value: kitchen.shake)
            TrayView(kitchen: kitchen)
                .frame(width: W - 24, height: H - (half + plateH + 10) - max(safe.bottom, 10) - 8)
                .position(x: W / 2, y: (half + plateH + 10 + H - max(safe.bottom, 10)) / 2)

            // ----- Par-dessus
            HUD(kitchen: kitchen, onExit: onExit)
                .padding(.horizontal, 14)
                .padding(.top, max(safe.top, 12) + 4)
                .frame(width: W)
            if let hint = kitchen.hint {
                Bubble(text: hint)
                    .position(x: W / 2, y: half + plateH + 2)
                    .transition(.scale.combined(with: .opacity))
            }
            if kitchen.phase == .served || kitchen.phase == .gone, let s = kitchen.last {
                ResultCard(served: s)
                    .position(x: W / 2, y: counterTop * 0.55 + 30)
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

    var body: some View {
        ZStack {
            switch kitchen.phase {
            case .poured, .cooking:
                Image("batter").resizable().scaledToFit()
                    .frame(width: size * 0.85)
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
                // Servie : la gaufre monte vers le client, par-dessus la charnière.
                .offset(y: kitchen.phase == .served ? -size * 1.7 : 0)
                .scaleEffect(kitchen.phase == .served ? 0.75 : 1)
                .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: kitchen.phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: kitchen.stack.count)
    }
}

// MARK: - Le ticket de commande

struct TicketView: View {
    let kitchen: Kitchen
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(order.recipe.name)
                .font(.toon(16))
                .foregroundStyle(Ink.line)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            ForEach(Array(order.layers.enumerated()), id: \.offset) { i, ing in
                HStack(spacing: 6) {
                    ZStack {
                        if i < kitchen.stack.count {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green)
                        } else if i == kitchen.stack.count {
                            Image(systemName: "arrowtriangle.right.fill").foregroundStyle(Ink.orange)
                        } else {
                            Text("\(i + 1)").font(.toon(12)).foregroundStyle(Ink.line.opacity(0.5))
                        }
                    }
                    .font(.system(size: 13, weight: .black))
                    .frame(width: 16)
                    Image(ing.image).resizable().scaledToFit().frame(width: 26, height: 26)
                    Text(ing.name).font(.toon(13, .bold)).foregroundStyle(Ink.line.opacity(i < kitchen.stack.count ? 0.4 : 1))
                        .strikethrough(i < kitchen.stack.count, color: Ink.line.opacity(0.4))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            HStack(spacing: 6) {
                Image(order.wish.image).resizable().scaledToFit().frame(width: 24, height: 24)
                Text(order.wish.label).font(.toon(13)).foregroundStyle(order.wish == .dark ? Color(hex: 0xA8601F) : Color(hex: 0xD98A1E))
            }
            .padding(.top, 2)
            PatienceBar(value: kitchen.patienceLeft)
                .frame(height: 12)
                .padding(.top, 2)
        }
        .padding(12)
        .padding(.top, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Ink.line).offset(x: 3, y: 4)
                RoundedRectangle(cornerRadius: 10).fill(Ink.paper)
                RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 3)
                VStack(spacing: 5) {
                    ForEach(0..<10, id: \.self) { _ in Rectangle().fill(Color(hex: 0x9CC8E8).opacity(0.22)).frame(height: 1) }
                }
                .padding(.horizontal, 10).padding(.vertical, 26)
            }
        )
        .overlay(alignment: .top) {
            Circle().fill(Ink.red).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Ink.line, lineWidth: 3))
                .overlay(Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5).offset(x: -2, y: -2))
                .offset(y: -6)
        }
        .rotationEffect(.degrees(2))
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
                    VStack(spacing: 6) {
                        Image("jug").resizable().scaledToFit().frame(height: 120)
                            .rotationEffect(.degrees(-14))
                        Text(T("Verser la pâte", "Pour the batter")).font(.toon(22)).foregroundStyle(Ink.line)
                    }
                    .padding(.horizontal, 30).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color(hex: 0xFFE3A8)))
                    .background(RoundedRectangle(cornerRadius: 28).fill(Ink.line).offset(y: 5))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Ink.line, lineWidth: 3))
                }
                .buttonStyle(Squish())
                .transition(.scale.combined(with: .opacity))
            case .poured:
                VStack(spacing: 14) {
                    if kitchen.hasHinge {
                        Image(systemName: "iphone.gen3").font(.system(size: 44, weight: .bold)).foregroundStyle(Ink.line)
                            .symbolEffect(.bounce, options: .repeating)
                        Text(T("Ferme le Duo pour fermer le gaufrier", "Close the Duo to close the waffle iron"))
                            .font(.toon(20)).foregroundStyle(Ink.line).multilineTextAlignment(.center)
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
        let cols = items.count > 8 ? 5 : 4
        return GeometryReader { g in
            let rows = Int(ceil(Double(items.count) / Double(cols)))
            let cell = min((g.size.width - CGFloat(cols - 1) * 10) / CGFloat(cols), (g.size.height - CGFloat(max(0, rows - 1)) * 8) / CGFloat(max(1, rows)), 96)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 10), count: cols), spacing: 8) {
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
                    Circle().fill(highlight ? Color(hex: 0xFFE3A8) : Ink.paper)
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
                Text(T("Verse la pâte, ferme le Duo pour cuire, rouvre quand c'est doré, puis garnis comme sur le ticket !",
                       "Pour the batter, close the Duo to cook, open it when it's golden, then top it like the ticket!"))
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

// MARK: - Duo fermé : la cuisson, sur l'écran extérieur

struct CookingView: View {
    let kitchen: Kitchen

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let unit = min(W, H * 0.7)
            ZStack {
                RadialGradient(colors: [Color(hex: 0xFFD08A), Color(hex: 0xFF8A3D)], center: .center, startRadius: 10, endRadius: max(W, H))
                    .ignoresSafeArea()
                VStack(spacing: unit * 0.04) {
                    if let order = kitchen.order, kitchen.phase == .cooking {
                        HStack(spacing: 6) {
                            Text(T("Il veut :", "They want:")).font(.toon(unit * 0.055, .bold))
                            Image(order.wish.image).resizable().scaledToFit().frame(width: unit * 0.08)
                            Text(order.wish.label).font(.toon(unit * 0.065))
                        }
                        .foregroundStyle(Ink.line)
                    } else {
                        Text(T("Verse la pâte d'abord !", "Pour the batter first!")).font(.toon(unit * 0.06)).foregroundStyle(Ink.line)
                    }
                    ZStack {
                        Steam(active: kitchen.phase == .cooking, burnt: Doneness.of(kitchen.cook) == .burnt)
                            .frame(width: unit * 0.8, height: unit * 0.35)
                            .offset(y: -unit * 0.3)
                        Image("iron_closed").resizable().scaledToFit().frame(width: unit * 0.85)
                    }
                    if kitchen.phase == .cooking, let order = kitchen.order {
                        CookMeter(cook: kitchen.cook, wish: order.wish)
                            .frame(width: unit * 0.88, height: unit * 0.13)
                        Text(Doneness.of(kitchen.cook) == order.wish ? T("C'est prêt ! Ouvre !", "Ready! Open it!") : T("Rouvre au bon moment", "Open at the right moment"))
                            .font(.toon(unit * 0.06))
                            .foregroundStyle(Doneness.of(kitchen.cook) == order.wish ? Color(hex: 0x1F7A2E) : Ink.line)
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

struct CookMeter: View {
    let cook: Double
    let wish: Doneness

    private let stops: [(Doneness, ClosedRange<Double>, UInt32)] = [
        (.raw, 0...0.3, 0xF8E6BC), (.light, 0.3...0.5, 0xF4D08E), (.golden, 0.5...0.7, 0xE8A24C), (.dark, 0.7...0.9, 0xBE6A28), (.burnt, 0.9...1.1, 0x4A2E1E),
    ]

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let scale = W / 1.1
            ZStack(alignment: .leading) {
                ForEach(0..<stops.count, id: \.self) { i in
                    let s = stops[i]
                    Rectangle().fill(Color(hex: s.2))
                        .frame(width: (s.1.upperBound - s.1.lowerBound) * scale, height: H)
                        .overlay {
                            if s.0 == wish { Rectangle().strokeBorder(Color(hex: 0x1F7A2E), lineWidth: 4) }
                        }
                        .offset(x: s.1.lowerBound * scale)
                }
                RoundedRectangle(cornerRadius: H / 3).strokeBorder(Ink.line, lineWidth: 3).frame(width: W, height: H)
                // l'aiguille
                VStack(spacing: 0) {
                    Triangle().fill(Ink.line).frame(width: 16, height: 12)
                    Rectangle().fill(Ink.line).frame(width: 4, height: H + 6)
                }
                .offset(x: min(W, cook * scale) - 8, y: -10)
                .animation(.linear(duration: 0.1), value: cook)
            }
        }
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
