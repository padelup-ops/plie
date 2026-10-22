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
            GameHeader(title: L("BASCULE"),
                       subtitle: L("\(app.basculeStars.count) / \(BasculeLevel.all.count) paniers réussis"),
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(DuoSupport.apisAvailable
                         ? L("Plie ton iPhone Duo pour régler le tremplin, puis lâche la bille. Fais-la tomber dans le panier en ramassant les étoiles.")
                         : L("Glisse ton doigt vers le haut ou le bas pour régler le tremplin, puis lâche la bille. Fais-la tomber dans le panier en ramassant les étoiles."))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)

                    ForEach(1...BasculeLevel.worldCount, id: \.self) { world in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionTitle(text: L("Monde \(world) · \(BasculeLevel.worldName(world))"))
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
                LevelTile(done: false, accent: Theme.bascule)
                if stars != nil {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.bascule.opacity(0.7), lineWidth: 1.5)
                        .shadow(color: Theme.bascule.opacity(0.5), radius: 6)
                }
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
        .accessibilityLabel(L("Niveau \(number)\(stars != nil ? L(", réussi") : "")\(unlocked ? "" : L(", verrouillé"))"))
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
            GameHeader(title: L("Niveau \(number)"),
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
                                          ? L("Plie ou déplie ton Duo pour régler le tremplin.")
                                          : L("Glisse vers le haut ou le bas pour régler le tremplin.")))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.message != nil ? Theme.coral : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(Int(session.alpha.rounded()))°")
                    .font(.plie(16, weight: .bold))
                    .monospacedDigit()
            }
            .padding(12)
            .background(GlassPanel(cornerRadius: 16))

            Button {
                showTip = false
                session.launch()
            } label: {
                Label(session.phase == .missed ? L("Relancer la bille") : L("Lâcher la bille"), systemImage: "circle.fill")
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
            CelebrationBackdrop(accent: Theme.gold)
            VStack(spacing: 14) {
                WinIcon(systemName: "basketball.fill", color: Theme.bascule)
                Text(L("Dans le panier !"))
                    .font(.plie(34))
                StarsView(count: session.collected.count, size: 28)
                Text(session.attempts == 1 ? L("Du premier coup !") : L("En \(session.attempts) essais"))
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if session.collected.count < 3 {
                    Text(L("Les 3 étoiles sont sur le même trajet : il existe un angle qui les prend toutes."))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                if number < BasculeLevel.all.count {
                    if app.basculeNeedsPass(number + 1, hasPass: store.ownsPass) {
                        Text(L("\(BasculeLevel.all.count - AppState.freeBasculeLevels) niveaux de plus, avec le vent et les ressorts, dans le Pass Plié."))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button(L("Débloquer la suite")) { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button(L("Niveau suivant")) { app.route = .bascule(number + 1) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.bascule, textColor: Theme.ink))
                    }
                }
                HStack(spacing: 10) {
                    Button(L("Rejouer")) {
                        app.route = .basculeLevels
                        DispatchQueue.main.async { app.route = .bascule(number) }
                    }
                    .buttonStyle(GhostButtonStyle())
                    Button(L("Les niveaux")) { app.route = .basculeLevels }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 420)
            .winCard(accent: Theme.gold)
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

            // Ciel de fin de journée, soleil, nuages et collines
            let board = Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.04)
            context.fill(board, with: .linearGradient(Gradient(colors: [Color(hex: 0x1A2A5E), Color(hex: 0x3B3B8F), Color(hex: 0x8C4F8F), Color(hex: 0xF08A5D)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: side)))
            context.drawLayer { sky in
                sky.clip(to: board)
                let sun = pt(0.78, 0.2)
                sky.drawLayer { glow in
                    glow.addFilter(.blur(radius: side * 0.06))
                    glow.fill(Path(ellipseIn: CGRect(x: sun.x - side * 0.16, y: sun.y - side * 0.16, width: side * 0.32, height: side * 0.32)),
                              with: .color(Color(hex: 0xFFD28A).opacity(0.55)))
                }
                sky.fill(Path(ellipseIn: CGRect(x: sun.x - side * 0.06, y: sun.y - side * 0.06, width: side * 0.12, height: side * 0.12)),
                         with: .color(Color(hex: 0xFFE3A8).opacity(0.9)))
                // Nuages qui dérivent
                for i in 0..<4 {
                    let speed = 0.008 + Draw.hash(i, 5) * 0.01
                    var x = (Draw.hash(i, level.number) + clock * speed).truncatingRemainder(dividingBy: 1.4) - 0.2
                    if x < -0.2 { x += 1.4 }
                    let y = 0.62 + Draw.hash(i, level.number + 3) * 0.32
                    let c = pt(x, y)
                    let w = side * CGFloat(0.16 + Draw.hash(i, 9) * 0.1)
                    var cloud = Path()
                    cloud.addEllipse(in: CGRect(x: c.x - w / 2, y: c.y - w * 0.12, width: w, height: w * 0.28))
                    cloud.addEllipse(in: CGRect(x: c.x - w * 0.28, y: c.y - w * 0.26, width: w * 0.42, height: w * 0.36))
                    cloud.addEllipse(in: CGRect(x: c.x - w * 0.02, y: c.y - w * 0.2, width: w * 0.34, height: w * 0.3))
                    sky.fill(cloud, with: .color(.white.opacity(0.12)))
                }
                // Collines au loin
                for layerIndex in 0..<2 {
                    var hills = Path()
                    let base = 0.07 + 0.04 * Double(1 - layerIndex)
                    hills.move(to: pt(0, 0))
                    for k in 0...40 {
                        let x = Double(k) / 40
                        let y = base + 0.025 * sin(x * 7 + Double(layerIndex) * 2 + Double(level.number)) + 0.015 * sin(x * 17)
                        hills.addLine(to: pt(x, y))
                    }
                    hills.addLine(to: pt(1, 0))
                    hills.closeSubpath()
                    sky.fill(hills, with: .color(Color(hex: layerIndex == 0 ? 0x4A2E5C : 0x2A1B3D).opacity(0.85)))
                }
            }
            context.stroke(board, with: .color(.white.opacity(0.12)), lineWidth: 1.5)

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
            let slopeA = pt(start.x, start.y - 0.015)
            let slopeB = pt(0.5, level.pivotY - 0.015)
            context.stroke(line(slopeA, slopeB).offsetBy(dx: 0, dy: side * 0.008), with: .color(.black.opacity(0.25)),
                           style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))
            context.stroke(line(slopeA, slopeB),
                           with: .linearGradient(Gradient(colors: [Color(hex: 0xE0A867), Color(hex: 0xB0743C)]), startPoint: slopeA, endPoint: slopeB),
                           style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))
            context.stroke(line(slopeA, slopeB).offsetBy(dx: 0, dy: -side * 0.005), with: .color(.white.opacity(0.25)),
                           style: StrokeStyle(lineWidth: side * 0.004, lineCap: .round))

            // Tremplin
            let tip = BasculeEngine.rampTip(level, alpha: alpha)
            let rampA = pt(0.5, level.pivotY)
            let rampB = pt(tip.x, tip.y)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: side * 0.012))
                glow.stroke(line(rampA, rampB), with: .color(Theme.bascule.opacity(0.6)), style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
            }
            context.stroke(line(rampA, rampB),
                           with: .linearGradient(Gradient(colors: [Theme.bascule, .white.opacity(0.9), Theme.bascule]), startPoint: rampA, endPoint: rampB),
                           style: StrokeStyle(lineWidth: side * 0.02, lineCap: .round))
            let pivot = pt(0.5, level.pivotY)
            let pr = side * 0.018
            Draw.shadedBall(&context, center: pivot, radius: pr, color: Color(hex: 0xC9CFE6))

            // Aide à la visée
            if aiming {
                for (i, p) in preview.enumerated() {
                    let c = pt(p.x, p.y)
                    let fade = 1 - Double(i) / Double(max(1, preview.count))
                    let r = 1.5 + 1.5 * fade
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.2 + 0.45 * fade)))
                }
            }

            // Murs
            for w in level.walls {
                let wa = pt(w.ax, w.ay), wb = pt(w.bx, w.by)
                context.stroke(line(wa, wb).offsetBy(dx: 0, dy: side * 0.006), with: .color(.black.opacity(0.3)),
                               style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
                context.stroke(line(wa, wb), with: .linearGradient(Gradient(colors: [Color(hex: 0x7A84AE), Color(hex: 0x4A5278)]), startPoint: wa, endPoint: wb),
                               style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
                context.stroke(line(wa, wb), with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: side * 0.003, lineCap: .round))
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
                         with: .linearGradient(Gradient(colors: [Theme.gold.opacity(0.05), Theme.gold.opacity(0.3)]),
                                               startPoint: pt(basket.x1, basket.top), endPoint: pt(basket.x1, bottom)))
            // Tressage du panier
            var weave = Path()
            let rows = 3
            for k in 1..<rows {
                let y = basket.top - BasculeEngine.basketDepth * Double(k) / Double(rows)
                weave.move(to: pt(basket.x1, y))
                weave.addLine(to: pt(basket.x2, y))
            }
            context.stroke(weave, with: .color(Theme.gold.opacity(0.45)), lineWidth: 1)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: side * 0.01))
                glow.stroke(cup, with: .color(Theme.gold.opacity(0.7)), style: StrokeStyle(lineWidth: side * 0.02, lineCap: .round, lineJoin: .round))
            }
            context.stroke(cup, with: .color(Theme.gold), style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round, lineJoin: .round))

            // Étoiles
            for (index, s) in level.stars.enumerated() where !collected.contains(index) {
                let c = pt(s.x, s.y)
                let sr = BasculeEngine.starRadius * side
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: sr * 0.6))
                    glow.fill(Path(ellipseIn: CGRect(x: c.x - sr * 1.3, y: c.y - sr * 1.3, width: sr * 2.6, height: sr * 2.6)),
                              with: .color(Theme.gold.opacity(0.35 + 0.15 * sin(clock * 4 + Double(index)))))
                }
                let starPath = Draw.star(center: c, radius: sr, rotation: sin(clock * 1.5 + Double(index)) * 0.25)
                context.fill(starPath, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF1B8), Theme.gold, Color(hex: 0xF0A020)]),
                                                             startPoint: CGPoint(x: c.x, y: c.y - sr), endPoint: CGPoint(x: c.x, y: c.y + sr)))
                context.stroke(starPath, with: .color(.white.opacity(0.6)), lineWidth: 1)
            }

            // Bille
            let b = pt(ballX, ballY)
            let br = BasculeEngine.ballRadius * side
            Draw.shadedBall(&context, center: b, radius: br, color: Color(hex: 0xFF7A2F))
        }
        .accessibilityLabel(L("Plateau : tremplin à \(Int(alpha.rounded())) degrés"))
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
