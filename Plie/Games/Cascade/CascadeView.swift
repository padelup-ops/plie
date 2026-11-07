import SwiftUI

// MARK: - CASCADE, en pixel art
//
// Le Duo plié en L : la charnière tombe pile au milieu de l'écran entier. Le terrain est donc
// calculé sur l'écran entier (sans les marges du système), pour que la ligne de pli du dessin
// soit exactement sur le pli du téléphone.

struct CascadeView: View {
    @Environment(AppState.self) private var app
    @State private var game = CascadeGame()
    @State private var renderer = CascadeRenderer()
    @State private var fullSize: CGSize = .zero

    /// Hauteur du tableau de bord, en points, au bas de la moitié à plat.
    private let panelHeight: CGFloat = 200

    var body: some View {
        GeometryReader { safe in
            ZStack {
                // Le terrain, sur l'écran entier
                GeometryReader { full in
                    CascadeField(game: game, renderer: renderer)
                        .frame(width: full.size.width, height: full.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { game.drop() }
                        .onAppear { layout(full.size, safe.safeAreaInsets.bottom) }
                        .onChange(of: full.size) { _, s in layout(s, safe.safeAreaInsets.bottom) }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    Spacer()
                }

                if let banner = game.banner {
                    // Au-dessus de la charnière, dans la moitié debout
                    Text(banner)
                        .font(PixelFont.font(26))
                        .foregroundStyle(Color(hex: 0xFFE066))
                        .shadow(color: Color(hex: 0x07040F), radius: 0, x: 3, y: 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Rectangle().fill(Color(hex: 0x07040F).opacity(0.82)))
                        .overlay(Rectangle().strokeBorder(Color(hex: 0xFFE066), lineWidth: 3))
                        .padding(.horizontal, 16)
                        .position(x: safe.size.width / 2, y: max(80, fullSize.height / 2 - safe.safeAreaInsets.top - 60))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    panel
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }

                if let gain = game.welcomeBack {
                    welcome(gain)
                }
            }
        }
        .foregroundStyle(.white)
        .background(Color(hex: 0x07040F).ignoresSafeArea())
        .onFrame { dt in game.tick(dt: dt) }
        .onHingeAngle { game.hinge($0) }
        .onDisappear { game.save() }
        .onAppear {
            PixelFont.register()
            #if DEBUG
            Demo.schedule("cascade", [(0.0, { game.demoRich() })])
            if UserDefaults.standard.string(forKey: "boardDemo") == "rich" { game.demoRich() }
            #endif
        }
    }

    private func layout(_ size: CGSize, _ safeBottom: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        fullSize = size
        let halfPts = size.height / 2
        game.edgeFraction = Double(max(0.42, 1 - (panelHeight + max(8, safeBottom) + 34) / max(1, halfPts)))
        game.height = Double(size.height / size.width)
    }

    // MARK: En haut : le titre et le compteur

    private var topBar: some View {
        HStack(spacing: 8) {
            PixelButton(fill: Color(hex: 0x2C1B5C)) {
                game.save()
                app.route = .hub
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .black)).frame(width: 34, height: 34)
            }
            .accessibilityLabel(L("Retour"))
            HowToButton(game: .cascade)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("CASCADE")).font(PixelFont.font(14))
                Text(game.frenzy > 0 ? L("Cascade : ×2 pendant \(Int(game.frenzy.rounded(.up))) s") : L("Combo \(game.combo) · ×\(String(format: "%.1f", game.comboMultiplier))"))
                    .font(PixelFont.font(8))
                    .foregroundStyle(game.frenzy > 0 ? Color(hex: 0xFF7BEA) : Color.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    CoinDot().frame(width: 16, height: 16)
                    Text(verbatim: CascadeGame.format(game.balance))
                        .font(PixelFont.font(18))
                        .foregroundStyle(Color(hex: 0xFFE066))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(L("+\(CascadeGame.format(game.perSecond)) / s"))
                    .font(PixelFont.font(8))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(CascadeGame.format(game.balance)) pièces"))
        }
        .padding(8)
        .pixelBox(fill: Color(hex: 0x120B26).opacity(0.92), border: Color(hex: 0xF2A33A))
    }

    // MARK: En bas : lâcher et améliorer

    private var panel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PixelButton(fill: Color(hex: 0xFFC93C), border: Color(hex: 0x8A4B0C)) {
                    game.drop()
                } label: {
                    VStack(spacing: 4) {
                        Text(L("LÂCHER")).font(PixelFont.font(16))
                        Text(L("Touche aussi le plateau")).font(PixelFont.font(7)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(Color(hex: 0x3A1D00))
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                PixelButton(fill: Color(hex: game.shakeReady ? 0x2C1B5C : 0x18102F)) {
                    game.shake()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down").font(.system(size: 15, weight: .black))
                        Text(L("Secouer")).font(PixelFont.font(7)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(width: 70, height: 50)
                    .opacity(game.shakeReady ? 1 : 0.45)
                }
                .disabled(!game.shakeReady)
                .accessibilityHint(L("Ou plie et déplie le Duo d'un coup"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CascadeUpgrade.allCases) { u in
                    upgradeButton(u)
                }
            }
        }
        .frame(height: panelHeight - 8)
        .frame(maxWidth: 640)
    }

    private func upgradeButton(_ u: CascadeUpgrade) -> some View {
        let lvl = game.level(u)
        let maxed = lvl >= u.maxLevel
        let ok = game.canBuy(u)
        return PixelButton(fill: Color(hex: ok ? 0x3B2A7A : 0x1A1236), border: ok ? Color(hex: 0xF2A33A) : Color(hex: 0x3A2C66)) {
            game.buy(u)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(u.title).font(PixelFont.font(8)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(maxed ? L("MAX") : L("niv. \(lvl)")).font(PixelFont.font(6)).opacity(0.7).lineLimit(1)
                }
                Text(effect(u)).font(PixelFont.font(6)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 4) {
                    if !maxed { CoinDot().frame(width: 9, height: 9) }
                    Text(verbatim: maxed ? "-" : CascadeGame.format(u.cost(lvl)))
                        .font(PixelFont.font(9))
                        .foregroundStyle(Color(hex: ok ? 0xFFE066 : 0xB9A8FF))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(ok || maxed ? 1 : 0.65)
        }
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
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                CoinDot().frame(width: 44, height: 44)
                Text(L("Pendant ton absence")).font(PixelFont.font(12)).multilineTextAlignment(.center)
                Text(verbatim: "+" + CascadeGame.format(gain)).font(PixelFont.font(28)).foregroundStyle(Color(hex: 0xFFE066))
                Text(L("Le lâcher automatique a continué sans toi.")).font(PixelFont.font(8)).lineSpacing(6).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                PixelButton(fill: Color(hex: 0xFFC93C), border: Color(hex: 0x8A4B0C)) {
                    game.dismissWelcome()
                } label: {
                    Text(L("Super !")).font(PixelFont.font(12)).foregroundStyle(Color(hex: 0x3A1D00)).frame(maxWidth: .infinity, minHeight: 46)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .pixelBox(fill: Color(hex: 0x1E1640), border: Color(hex: 0xF2A33A))
        }
    }
}

// MARK: - Pièces d'interface pixel

/// Une boîte pixel : fond plein, bordure épaisse, ombre dure décalée (pas de flou, pas d'arrondi).
struct PixelBox: ViewModifier {
    var fill: Color
    var border: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Rectangle().fill(Color(hex: 0x07040F)).offset(x: 3, y: 3)
                    Rectangle().fill(fill)
                    Rectangle().strokeBorder(border, lineWidth: 3)
                }
            )
    }
}

extension View {
    func pixelBox(fill: Color, border: Color) -> some View { modifier(PixelBox(fill: fill, border: border)) }
}

/// Bouton pixel : il s'enfonce de 3 pixels quand on appuie.
struct PixelButton<Label: View>: View {
    var fill: Color
    var border: Color = Color(hex: 0x6E5BC4)
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(PixelPressStyle(fill: fill, border: border))
    }
}

struct PixelPressStyle: ButtonStyle {
    var fill: Color
    var border: Color

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .background(
                ZStack {
                    Rectangle().fill(fill)
                    Rectangle().strokeBorder(border, lineWidth: 3)
                    // Reflet en haut, comme un bouton de borne
                    VStack { Rectangle().fill(.white.opacity(down ? 0 : 0.18)).frame(height: 3).padding(.horizontal, 3).padding(.top, 3); Spacer() }
                }
            )
            .offset(x: down ? 3 : 0, y: down ? 3 : 0)
            .background(Rectangle().fill(Color(hex: 0x07040F)).offset(x: 3, y: 3))
            .animation(nil, value: down)
    }
}

/// Une petite pièce pixel (compteur, prix).
struct CoinDot: View {
    var body: some View {
        Canvas { ctx, size in
            let p = size.width / 7
            let rows = ["0011100", "0122210", "1223221", "1222221", "1222221", "0122210", "0011100"]
            let cols: [Character: Color] = ["1": Color(hex: 0x8A4B0C), "2": Color(hex: 0xFFC93C), "3": Color(hex: 0xFFF2A8)]
            for (y, line) in rows.enumerated() {
                for (x, ch) in line.enumerated() {
                    guard let c = cols[ch] else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p + 0.5, height: p + 0.5)), with: .color(c))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Le dessin de la machine

struct CascadeField: View {
    let game: CascadeGame
    let renderer: CascadeRenderer

    var body: some View {
        // `frame` change à chaque image : on redessine l'image pixel.
        let _ = game.frame
        if let img = renderer.render(game) {
            Image(decorative: img, scale: 1)
                .interpolation(.none)
                .resizable()
                .accessibilityLabel(L("La machine à pièces"))
        } else {
            Color(hex: 0x07040F)
        }
    }
}
