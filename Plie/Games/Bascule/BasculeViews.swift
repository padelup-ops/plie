import SwiftUI
import Combine

extension Theme {
    static let bascule = Color(hex: 0x8BDB4F)
}

// MARK: - Choix du niveau

struct BasculeLevelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: "BASCULE",
                       subtitle: "\(app.basculeStars.count) / \(BasculeLevel.all.count) paniers réussis",
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(DuoSupport.apisAvailable
                         ? "Plie ton iPhone Duo pour régler le tremplin, puis lâche la bille. Fais-la tomber dans le panier en ramassant les étoiles."
                         : "Glisse ton doigt vers le haut ou le bas pour régler le tremplin, puis lâche la bille. Fais-la tomber dans le panier en ramassant les étoiles.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)

                    ForEach(1...BasculeLevel.worldCount, id: \.self) { world in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionTitle(text: "Monde \(world) · \(BasculeLevel.worldName(world))")
                                if BasculeLevel.all.contains(where: { $0.world == world && app.basculeNeedsPass($0.number, hasPass: store.ownsPass) }) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
                                ForEach(BasculeLevel.all.filter { $0.world == world }, id: \.number) { level in
                                    levelButton(level.number)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func levelButton(_ number: Int) -> some View {
        let stars = app.basculeStars[number]
        let needsPass = app.basculeNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.basculeIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                app.route = .bascule(number)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(stars != nil ? Theme.cardHigh : Theme.card)
                if unlocked {
                    VStack(spacing: 3) {
                        Text("\(number)")
                            .font(.plie(22))
                            .foregroundStyle(.white)
                        StarsView(count: stars ?? 0, size: 9)
                    }
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                }
            }
            .frame(height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(stars != nil ? Theme.bascule.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Niveau \(number)\(stars != nil ? ", réussi" : "")\(unlocked ? "" : ", verrouillé")")
    }
}

// MARK: - Partie

struct BasculePlayView: View {
    let number: Int

    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var session: BasculeSession
    @State private var dragStart: Double?
    @State private var showTip = true
    @State private var usesHinge = false
    @State private var recorded = false

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(number: Int) {
        self.number = number
        let index = max(0, min(BasculeLevel.all.count - 1, number - 1))
        _session = State(initialValue: BasculeSession(level: BasculeLevel.all[index]))
    }

    var body: some View {
        VStack(spacing: 12) {
            GameHeader(title: "Niveau \(number)",
                       subtitle: BasculeLevel.worldName(session.level.world),
                       onBack: { app.route = .basculeLevels }) {
                StarsView(count: session.collected.count, size: 16)
            }

            if showTip, let tip = session.level.tip {
                TipBanner(text: tip) { showTip = false }
            }

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                BasculeBoard(session: session)
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                guard !usesHinge else { return }
                                if dragStart == nil { dragStart = session.targetAlpha }
                                let delta = -Double(value.translation.height) / Double(side) * 110
                                session.setTarget((dragStart ?? 0) + delta)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }

            HStack(spacing: 10) {
                Image(systemName: usesHinge ? "rectangle.portrait.on.rectangle.portrait" : "hand.draw.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.bascule)
                Text(session.message ?? (usesHinge
                                          ? "Plie ou déplie ton Duo pour régler le tremplin."
                                          : "Glisse vers le haut ou le bas pour régler le tremplin."))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.message != nil ? Theme.coral : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(Int(session.alpha.rounded()))°")
                    .font(.plie(16, weight: .bold))
                    .monospacedDigit()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))

            Button {
                showTip = false
                session.launch()
            } label: {
                Label(session.phase == .missed ? "Relancer la bille" : "Lâcher la bille", systemImage: "circle.fill")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.bascule, textColor: Theme.ink, height: 58))
            .disabled(!session.canLaunch)
            .opacity(session.canLaunch ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHingeAngle { degrees in
            guard let degrees, HingeMapping.isOpen(degrees) else {
                usesHinge = false
                return
            }
            usesHinge = true
            session.setTarget(BasculeEngine.alpha(fromFraction: HingeMapping.fraction(fromDegrees: degrees)))
        }
        .onReceive(ticker) { _ in
            session.tick(dt: 1.0 / 60.0)
            if session.phase == .won && !recorded {
                recorded = true
                app.recordBascule(number, stars: session.collected.count)
            }
        }
        .overlay {
            if session.phase == .won {
                successOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.phase == .won)
        .animation(.easeOut(duration: 0.2), value: showTip)
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.bascule)
                Text("Dans le panier !")
                    .font(.plie(34))
                StarsView(count: session.collected.count, size: 28)
                Text(session.attempts == 1 ? "Du premier coup !" : "En \(session.attempts) essais")
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if session.collected.count < 3 {
                    Text("Les 3 étoiles sont sur le même trajet : il existe un angle qui les prend toutes.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                if number < BasculeLevel.all.count {
                    if app.basculeNeedsPass(number + 1, hasPass: store.ownsPass) {
                        Text("\(BasculeLevel.all.count - AppState.freeBasculeLevels) niveaux de plus, avec le vent et les ressorts, dans le Pass Plié.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Débloquer la suite") { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button("Niveau suivant") { app.route = .bascule(number + 1) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.bascule, textColor: Theme.ink))
                    }
                }
                HStack(spacing: 10) {
                    Button("Rejouer") {
                        app.route = .basculeLevels
                        DispatchQueue.main.async { app.route = .bascule(number) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Button("Les niveaux") { app.route = .basculeLevels }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.ink))
            .padding(24)
        }
    }
}

// MARK: - Dessin

struct BasculeBoard: View {
    let session: BasculeSession

    var body: some View {
        let level = session.level
        let alpha = session.alpha
        let ballX = session.ballX
        let ballY = session.ballY
        let collected = session.collected
        let clock = session.clock
        let preview = session.previewPoints
        let aiming = session.phase == .aiming || session.phase == .missed

        Canvas { context, size in
            let side = min(size.width, size.height)
            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * side, y: (1 - y) * side)
            }
            func line(_ a: CGPoint, _ b: CGPoint) -> Path {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                return p
            }

            // Ciel
            let board = Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.04)
            context.fill(board, with: .linearGradient(Gradient(colors: [Color(hex: 0x1B3358), Color(hex: 0x0F1B33)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: side)))
            context.fill(Path(CGRect(x: 0, y: side * 0.985, width: side, height: side * 0.015)), with: .color(Color(hex: 0x0A0F1E)))

            // Pliure du Duo
            context.stroke(line(pt(0.5, 0.02), pt(0.5, 0.98)), with: .color(.white.opacity(0.07)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

            // Vent
            if level.wind != 0 {
                let dir: Double = level.wind > 0 ? 1 : -1
                let speed = abs(level.wind) * 0.12
                for row in 0..<5 {
                    let y = 0.15 + Double(row) * 0.17
                    for k in 0..<4 {
                        var x = (Double(k) * 0.27 + clock * speed * dir + Double(row) * 0.11).truncatingRemainder(dividingBy: 1.08)
                        if x < 0 { x += 1.08 }
                        x -= 0.04
                        let a = pt(x, y)
                        let b = pt(x + 0.05 * dir, y)
                        var arrow = line(a, b)
                        arrow.move(to: b)
                        arrow.addLine(to: pt(x + 0.035 * dir, y + 0.012))
                        arrow.move(to: b)
                        arrow.addLine(to: pt(x + 0.035 * dir, y - 0.012))
                        context.stroke(arrow, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
            }

            // Pente de départ
            let start = level.startPoint
            context.stroke(line(pt(start.x, start.y - 0.015), pt(0.5, level.pivotY - 0.015)),
                           with: .color(Color(hex: 0xC98A4B)), style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))

            // Tremplin
            let tip = BasculeEngine.rampTip(level, alpha: alpha)
            context.stroke(line(pt(0.5, level.pivotY), pt(tip.x, tip.y)),
                           with: .color(Theme.bascule), style: StrokeStyle(lineWidth: side * 0.02, lineCap: .round))
            let pivot = pt(0.5, level.pivotY)
            let pr = side * 0.018
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - pr, y: pivot.y - pr, width: pr * 2, height: pr * 2)), with: .color(.white))

            // Aide à la visée
            if aiming {
                for p in preview {
                    let c = pt(p.x, p.y)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.45)))
                }
            }

            // Murs
            for w in level.walls {
                context.stroke(line(pt(w.ax, w.ay), pt(w.bx, w.by)), with: .color(Color(hex: 0x5A6488)),
                               style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
            }

            // Ressorts
            for pad in level.pads {
                let a = pt(pad.x1, pad.y)
                let b = pt(pad.x2, pad.y)
                var spring = Path()
                let n = 8
                for i in 0...n {
                    let x = a.x + (b.x - a.x) * CGFloat(i) / CGFloat(n)
                    let y = a.y + side * 0.012 + (i % 2 == 0 ? 0 : side * 0.018)
                    if i == 0 { spring.move(to: CGPoint(x: x, y: y)) } else { spring.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(spring, with: .color(Color(hex: 0x3CDC78).opacity(0.7)), lineWidth: 2)
                context.stroke(line(a, b), with: .color(Color(hex: 0x3CDC78)), style: StrokeStyle(lineWidth: side * 0.014, lineCap: .round))
            }

            // Panier
            let basket = level.basket
            let bottom = basket.top - BasculeEngine.basketDepth
            var cup = Path()
            cup.move(to: pt(basket.x1, basket.top))
            cup.addLine(to: pt(basket.x1, bottom))
            cup.addLine(to: pt(basket.x2, bottom))
            cup.addLine(to: pt(basket.x2, basket.top))
            context.fill(Path(CGRect(x: pt(basket.x1, basket.top).x, y: pt(basket.x1, basket.top).y,
                                     width: (basket.x2 - basket.x1) * side, height: BasculeEngine.basketDepth * side)),
                         with: .color(Theme.gold.opacity(0.15)))
            context.stroke(cup, with: .color(Theme.gold), style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round, lineJoin: .round))

            // Étoiles
            for (index, s) in level.stars.enumerated() where !collected.contains(index) {
                let c = pt(s.x, s.y)
                context.fill(BasculeBoard.star(center: c, radius: BasculeEngine.starRadius * side), with: .color(Theme.gold))
            }

            // Bille
            let b = pt(ballX, ballY)
            let br = BasculeEngine.ballRadius * side
            context.fill(Path(ellipseIn: CGRect(x: b.x - br, y: b.y - br, width: br * 2, height: br * 2)), with: .color(Color(hex: 0xFF7A2F)))
            context.fill(Path(ellipseIn: CGRect(x: b.x - br * 0.45, y: b.y - br * 0.6, width: br * 0.6, height: br * 0.6)), with: .color(.white.opacity(0.6)))
        }
        .accessibilityLabel("Plateau : tremplin à \(Int(alpha.rounded())) degrés")
    }

    static func star(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * 0.45
            let a = Double(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}
