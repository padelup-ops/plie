import SwiftUI

struct CascadeView: View {
    @Environment(AppState.self) private var app
    @State private var game = CascadeGame()

    /// Hauteur du tableau de bord, en points, au bas de la moitié à plat.
    private let panelHeight: CGFloat = 196

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                CascadeField(game: game)
                    .ignoresSafeArea()
                    .onAppear { layout(size, proxy.safeAreaInsets.bottom) }
                    .onChange(of: size) { _, s in layout(s, proxy.safeAreaInsets.bottom) }
                    .onTapGesture { game.drop() }
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 14)
                        .padding(.top, max(8, proxy.safeAreaInsets.top))
                    Spacer()
                    if let banner = game.banner {
                        Text(banner)
                            .font(.plie(40, weight: .black))
                            .foregroundStyle(Theme.cascade)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                            .transition(.scale.combined(with: .opacity))
                            .frame(height: 60)
                    }
                    Spacer()
                    Color.clear.frame(height: size.height / 2)
                }
                VStack {
                    Spacer()
                    panel
                        .padding(.horizontal, 12)
                        .padding(.bottom, max(10, proxy.safeAreaInsets.bottom))
                }
                if let gain = game.welcomeBack {
                    welcome(gain)
                }
            }
            .animation(.spring(duration: 0.3), value: game.banner)
        }
        .foregroundStyle(.white)
        .onFrame { dt in game.tick(dt: dt) }
        .onHingeAngle { game.hinge($0) }
        .onDisappear { game.save() }
        .onAppear {
            #if DEBUG
            Demo.schedule("cascade", [(0.0, { game.demoRich() })])
            #endif
        }
    }

    private func layout(_ size: CGSize, _ safeBottom: CGFloat) {
        guard size.width > 0 else { return }
        let halfPts = size.height / 2
        game.edgeFraction = Double(max(0.45, 1 - (panelHeight + max(10, safeBottom) + 8) / max(1, halfPts)))
        game.height = Double(size.height / size.width)
    }

    // MARK: En haut : le titre et le compteur

    private var topBar: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                game.save()
                app.route = .hub
            }
            HowToButton(game: .cascade)
            VStack(alignment: .leading, spacing: 0) {
                Text(L("CASCADE")).font(.plie(18, weight: .black))
                Text(game.frenzy > 0 ? L("Cascade : ×2 pendant \(Int(game.frenzy.rounded(.up))) s") : L("Combo \(game.combo) · ×\(String(format: "%.1f", game.comboMultiplier))"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(game.frenzy > 0 ? Theme.cascade : .white.opacity(0.7))
                    .monospacedDigit()
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 5) {
                    CoinDot(gold: true).frame(width: 18, height: 18)
                    Text(verbatim: CascadeGame.format(game.balance))
                        .font(.plie(26, weight: .black))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(L("+\(CascadeGame.format(game.perSecond)) / s"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(CascadeGame.format(game.balance)) pièces"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.35)))
    }

    // MARK: En bas : lâcher et améliorer

    private var panel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { game.drop() } label: {
                    VStack(spacing: 1) {
                        Text(L("LÂCHER")).font(.plie(24, weight: .black))
                        Text(L("Touche aussi le plateau")).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xFFC94D), Color(hex: 0xFF8A2F)], startPoint: .top, endPoint: .bottom)))
                    .foregroundStyle(Color(hex: 0x3A1D00))
                }
                .buttonStyle(PressableStyle())
                Button { game.shake() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.up.and.down.and.sparkles").font(.system(size: 20, weight: .bold))
                        Text(L("Secouer")).font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .frame(width: 76, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(game.shakeReady ? 0.16 : 0.06)))
                    .opacity(game.shakeReady ? 1 : 0.45)
                }
                .buttonStyle(PressableStyle())
                .disabled(!game.shakeReady)
                .accessibilityHint(L("Ou plie et déplie le Duo d'un coup"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CascadeUpgrade.allCases) { u in
                    upgradeButton(u)
                }
            }
        }
        .frame(height: panelHeight - 10)
        .frame(maxWidth: 640)
    }

    private func upgradeButton(_ u: CascadeUpgrade) -> some View {
        let lvl = game.level(u)
        let maxed = lvl >= u.maxLevel
        let ok = game.canBuy(u)
        return Button { game.buy(u) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: u.symbol).font(.system(size: 11, weight: .bold))
                    Text(u.title).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(maxed ? L("MAX") : L("niv. \(lvl)")).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.7)
                }
                Text(effect(u)).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 3) {
                    if !maxed { CoinDot(gold: true).frame(width: 10, height: 10) }
                    Text(verbatim: maxed ? "—" : CascadeGame.format(u.cost(lvl)))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ok ? Color(hex: 0x3B2A7A) : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ok ? Theme.cascade.opacity(0.7) : .clear, lineWidth: 1.5))
            .opacity(ok || maxed ? 1 : 0.6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(L("\(u.title), niveau \(lvl)"))
    }

    private func effect(_ u: CascadeUpgrade) -> String {
        switch u {
        case .dropSpeed: return L("\(String(format: "%.2f", game.dropInterval)) s entre deux")
        case .auto: return L("\(String(format: "%.1f", Double(game.level(.auto)) * 0.55)) pièces / s")
        case .pushSpeed: return L("Un aller-retour en \(String(format: "%.1f", game.pushPeriod)) s")
        case .pushReach: return L("Pousse plus loin")
        case .value: return L("×\(CascadeGame.format(game.coinValue)) par pièce")
        case .gold: return L("\(Int((game.goldChance * 100).rounded())) % de pièces d'or")
        }
    }

    private func welcome(_ gain: Double) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                CoinDot(gold: true).frame(width: 56, height: 56)
                Text(L("Pendant ton absence")).font(.plie(22))
                Text(verbatim: "+" + CascadeGame.format(gain)).font(.plie(40, weight: .black)).foregroundStyle(Theme.cascade)
                Text(L("Le lâcher automatique a continué sans toi.")).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                Button { game.dismissWelcome() } label: {
                    Text(L("Super !")).font(.plie(18)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(Theme.cascade)).foregroundStyle(Color(hex: 0x3A1D00))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x1E1640)))
        }
    }
}

/// Une petite pièce dessinée (compteur, prix).
struct CoinDot: View {
    var gold: Bool

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: gold ? [Color(hex: 0xFFE07A), Color(hex: 0xE0921C)] : [Color(hex: 0xF2F4FA), Color(hex: 0x9AA3B8)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Circle().inset(by: 2.5).stroke(.white.opacity(0.55), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Le dessin de la machine

struct CascadeField: View {
    let game: CascadeGame

    var body: some View {
        Canvas { context, size in
            let s = size.width
            let halfY = size.height / 2
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Le fond : la vitrine debout, puis le plateau à plat.
            context.fill(Path(CGRect(x: 0, y: 0, width: s, height: halfY)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x231650), Color(hex: 0x3A1F6B)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: halfY)))
            context.fill(Path(CGRect(x: 0, y: halfY, width: s, height: halfY)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x0F4A52), Color(hex: 0x0A2F3A)]),
                                               startPoint: CGPoint(x: 0, y: halfY), endPoint: CGPoint(x: 0, y: size.height)))
            if game.frenzy > 0 {
                let pulse = 0.12 + 0.08 * sin(game.time * 10)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.cascade.opacity(pulse)))
            }

            // Les rails sur les côtés
            let wall = CascadeGame.wall * s
            for x in [0, s - wall] {
                context.fill(Path(CGRect(x: x, y: 0, width: wall, height: size.height)),
                             with: .linearGradient(Gradient(colors: [Color(hex: 0xFFB13D), Color(hex: 0xC2661A)]),
                                                   startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + wall, y: 0)))
            }

            // Les clous
            for p in game.pegs {
                let r = CascadeGame.pegR * s
                context.fill(Path(ellipseIn: CGRect(x: p.x * s - r, y: p.y * s - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0xBFD7FF)))
                context.fill(Path(ellipseIn: CGRect(x: p.x * s - r * 0.4, y: p.y * s - r * 0.7, width: r * 0.8, height: r * 0.6)), with: .color(.white.opacity(0.8)))
            }

            // La trémie, en haut
            let dw = 0.12 * s
            let dy = game.half * 0.1 * s
            context.fill(Path(roundedRect: CGRect(x: game.dropperX * s - dw / 2, y: dy - 10, width: dw, height: 16), cornerRadius: 6),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF8A2F)]),
                                               startPoint: CGPoint(x: 0, y: dy - 10), endPoint: CGPoint(x: 0, y: dy + 6)))

            // La cible mobile
            let gy = game.half * 0.92 * s
            let gw = 0.14 * s
            let gate = Path(roundedRect: CGRect(x: game.gateX * s - gw / 2, y: gy - 4, width: gw, height: 8), cornerRadius: 4)
            context.fill(gate, with: .color(Color(hex: 0xFF4FD8)))
            context.stroke(gate, with: .color(Color(hex: 0xFF4FD8).opacity(0.4)), lineWidth: 6)
            context.draw(Text(verbatim: "×4").font(.system(size: 11, weight: .black, design: .rounded)).foregroundColor(.white),
                         at: CGPoint(x: game.gateX * s, y: gy - 14))

            // La charnière
            var hinge = Path()
            hinge.move(to: CGPoint(x: 0, y: halfY))
            hinge.addLine(to: CGPoint(x: s, y: halfY))
            context.stroke(hinge, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 2, dash: [8, 10]))

            // Le plateau : le bord avant, et les trous sur les côtés
            let edgeY = game.bedEdge * s
            context.fill(Path(CGRect(x: wall, y: edgeY, width: s - 2 * wall, height: size.height - edgeY)), with: .color(.black.opacity(0.45)))
            for x in [wall, s - wall - 0.09 * s] {
                context.fill(Path(CGRect(x: x, y: edgeY - 0.06 * s, width: 0.09 * s, height: 0.06 * s)), with: .color(.black.opacity(0.35)))
            }
            var edge = Path()
            edge.move(to: CGPoint(x: wall, y: edgeY))
            edge.addLine(to: CGPoint(x: s - wall, y: edgeY))
            context.stroke(edge, with: .color(Theme.cascade.opacity(0.9)), lineWidth: 3)

            // Les pièces sur le plateau
            for c in game.bed { drawCoin(&context, c, at: pt(c.x, c.y), r: CascadeGame.coinR * s, squash: 1) }

            // Le poussoir
            let front = game.pusherFront * s
            let pusher = CGRect(x: wall, y: halfY, width: s - 2 * wall, height: max(0, front - halfY))
            context.fill(Path(pusher), with: .linearGradient(Gradient(colors: [Color(hex: 0x6E7A99), Color(hex: 0xC9D2E8)]),
                                                             startPoint: CGPoint(x: 0, y: halfY), endPoint: CGPoint(x: 0, y: front)))
            context.fill(Path(CGRect(x: wall, y: front - 4, width: s - 2 * wall, height: 4)), with: .color(.white.opacity(0.85)))

            // Les pièces qui tombent
            for c in game.falling {
                drawCoin(&context, c, at: pt(c.x, c.y), r: CascadeGame.coinR * 0.8 * s, squash: max(0.25, abs(cos(c.spin))))
            }

            // Les gains qui s'envolent
            for p in game.pops {
                context.opacity = min(1, p.life * 2)
                context.draw(Text(verbatim: p.text).font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(p.gold ? Color(hex: 0xFFE07A) : .white), at: pt(p.x, p.y))
            }
            context.opacity = 1
        }
        .accessibilityLabel(L("La machine à pièces"))
    }

    private func drawCoin(_ context: inout GraphicsContext, _ c: CascadeCoin, at p: CGPoint, r: CGFloat, squash: Double) {
        let rect = CGRect(x: p.x - r * squash, y: p.y - r, width: 2 * r * squash, height: 2 * r)
        switch c.kind {
        case .gem:
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - r * 1.1))
            d.addLine(to: CGPoint(x: p.x + r * squash, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + r * 1.1))
            d.addLine(to: CGPoint(x: p.x - r * squash, y: p.y))
            d.closeSubpath()
            context.fill(d, with: .linearGradient(Gradient(colors: [Color(hex: 0xFF9BFF), Color(hex: 0x7A3DFF)]),
                                                  startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r)))
            context.stroke(d, with: .color(.white.opacity(0.7)), lineWidth: 1)
        case .gold, .silver:
            let colors = c.kind == .gold ? [Color(hex: 0xFFE07A), Color(hex: 0xD98A16)] : [Color(hex: 0xF4F6FB), Color(hex: 0x8C96AD)]
            context.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: r * 0.18)), with: .color(.black.opacity(0.25)))
            context.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: colors),
                                                                      startPoint: CGPoint(x: p.x, y: rect.minY), endPoint: CGPoint(x: p.x, y: rect.maxY)))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.28 * squash, dy: r * 0.28)), with: .color(.white.opacity(0.45)), lineWidth: 1)
        }
    }
}
