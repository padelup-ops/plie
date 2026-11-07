import SwiftUI

// MARK: - PÊCHE : l'écran
//
// Comme CASCADE, le dessin couvre l'écran entier : la ligne de l'eau tombe pile sur la charnière.

struct PecheView: View {
    @Environment(AppState.self) private var app
    @State private var game = PecheGame()
    @State private var renderer = PecheRenderer()
    @State private var showBook = false

    /// Hauteur du tableau de bord, en points, en bas de la moitié à plat.
    private let panelHeight: CGFloat = 150

    var body: some View {
        GeometryReader { safe in
            ZStack {
                GeometryReader { full in
                    PecheField(game: game, renderer: renderer)
                        .frame(width: full.size.width, height: full.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { game.primary() }
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

                if let message = game.message {
                    banner(message)
                        .position(x: safe.size.width / 2, y: safe.size.height * 0.62)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    panel
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }

                if game.phase == .caught, let c = game.catchResult {
                    catchCard(c)
                }
                if showBook { book }
            }
        }
        .foregroundStyle(.white)
        .background(Color(hex: 0x0A0A1E).ignoresSafeArea())
        .onFrame { dt in game.tick(dt: dt) }
        .onHingeAngle { game.hinge($0) }
        .onChange(of: game.phase) { _, phase in
            if phase == .caught {
                app.gamePlayed()
                if game.catchResult?.isNew == true { app.celebrate() }
            }
        }
        .onAppear {
            PixelFont.register()
            #if DEBUG
            Demo.schedule("peche", [
                (0.3, { game.demo() }),
                (4.5, { game.demoBite() }),
                (5.2, { game.strike() }),
                (5.4, { game.reelHeld = true }),
            ])
            #endif
        }
        .onDisappear { game.reelHeld = false }
    }

    private func layout(_ size: CGSize, _ safeBottom: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let ptPerPx = size.width / CGFloat(game.cols)
        let rows = Int((size.height / ptPerPx).rounded())
        let reserve = (panelHeight + max(8, safeBottom) + 14) / ptPerPx
        game.configure(rows: rows, bottomReserve: Double(reserve))
    }

    // MARK: En haut

    private var topBar: some View {
        PixelTopBar(title: L("PÊCHE"), subtitle: L("\(game.speciesCaught) / \(FishSpecies.all.count) espèces"), game: .peche,
                    border: Color(hex: 0x3FB5E8), onBack: { app.route = .hub }) {
            HStack(spacing: 8) {
                PixelButton(fill: Color(hex: 0x2C1B5C), border: Color(hex: 0x3FB5E8)) {
                    showBook = true
                } label: {
                    Image(systemName: "book.closed.fill").font(.system(size: 15, weight: .black)).frame(width: 34, height: 34)
                }
                .accessibilityLabel(L("Carnet de pêche"))
                HStack(spacing: 6) {
                    CoinDot().frame(width: 16, height: 16)
                    Text(verbatim: "\(game.coins)")
                        .font(PixelFont.font(14))
                        .foregroundStyle(Color(hex: 0xFFE066))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(game.coins) pièces"))
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(PixelFont.font(12))
            .foregroundStyle(Color(hex: 0xFFE066))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .pixelBox(fill: Color(hex: 0x07040F).opacity(0.85), border: Color(hex: 0xFFE066))
    }

    // MARK: En bas : lancer, ferrer, mouliner

    private var reelBinding: Binding<Bool> {
        Binding(get: { game.reelHeld }, set: { game.reelHeld = $0 })
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 8) {
            switch game.phase {
            case .ready:
                bigButton(L("LANCER"), hint: L("Ou referme et rouvre le Duo d'un coup"), color: 0xFFC93C, ink: 0x3A1D00) { game.primary() }
                upgrades
            case .aiming:
                PixelGauge(value: game.gauge, color: Color(hex: 0xFFE066), blocks: 14).frame(height: 18)
                bigButton(L("STOP !"), hint: L("Plus la jauge est pleine, plus tu lances loin"), color: 0xFFC93C, ink: 0x3A1D00) { game.primary() }
            case .flying, .sinking:
                HStack {
                    Text(L("Profondeur : \(game.meters) m")).font(PixelFont.font(9))
                    Spacer()
                    Text(L("Plus c'est profond, plus c'est rare")).font(PixelFont.font(6)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.5)
                }
                holdButton(L("REMONTER"), hint: L("Garde appuyé, ou plie et déplie doucement"))
            case .bite:
                bigButton(L("FERRER !"), hint: L("Vite ! Touche, ou donne un coup de charnière"), color: 0xFF4F4F, ink: 0xFFFFFF) { game.primary() }
            case .fighting:
                HStack(spacing: 8) {
                    Text(L("Tension")).font(PixelFont.font(8))
                    PixelGauge(value: min(1, game.tension), color: tensionColor, blocks: 12).frame(height: 16)
                }
                Text(game.tooFastWarning ? L("Trop vite ! Doucement…") : L("Mouline, mais relâche quand la ligne est rouge"))
                    .font(PixelFont.font(7))
                    .foregroundStyle(game.tooFastWarning ? Color(hex: 0xFF6A6A) : .white.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.5)
                holdButton(L("MOULINER"), hint: L("Garde appuyé, ou plie et déplie doucement"))
            case .snapped, .escaped, .caught:
                Text(game.phase == .snapped ? L("La ligne a cassé !") : (game.phase == .escaped ? L("Le poisson s'est échappé.") : ""))
                    .font(PixelFont.font(11))
                    .foregroundStyle(Color(hex: 0xFFE066))
                bigButton(L("RELANCER"), hint: "", color: 0xFFC93C, ink: 0x3A1D00) { game.again() }
            }
        }
        .frame(height: panelHeight - 8)
        .frame(maxWidth: 640)
    }

    private var tensionColor: Color {
        game.tension > 0.85 ? Color(hex: 0xFF4F4F) : (game.tension > 0.6 ? Color(hex: 0xFFC93C) : Color(hex: 0x5FD38A))
    }

    private func bigButton(_ title: String, hint: String, color: UInt32, ink: UInt32, action: @escaping () -> Void) -> some View {
        PixelButton(fill: Color(hex: color), border: Color(hex: PixelArt.mix(color, 0x07040F, 0.5)), action: action) {
            VStack(spacing: 5) {
                Text(title).font(PixelFont.font(16))
                if !hint.isEmpty {
                    Text(hint).font(PixelFont.font(6)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(Color(hex: ink))
            .frame(maxWidth: .infinity, minHeight: 54)
        }
    }

    private func holdButton(_ title: String, hint: String) -> some View {
        PixelHoldButton(fill: Color(hex: 0x3FB5E8), border: Color(hex: 0x1A5A80), held: reelBinding) {
            VStack(spacing: 5) {
                Text(title).font(PixelFont.font(16))
                Text(hint).font(PixelFont.font(6)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.5)
            }
            .foregroundStyle(Color(hex: 0x07203A))
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .accessibilityLabel(title)
    }

    private var upgrades: some View {
        HStack(spacing: 8) {
            ForEach(PecheUpgrade.allCases) { u in
                let lvl = game.level(u)
                let maxed = lvl >= PecheUpgrade.maxLevel
                let ok = game.canBuy(u)
                PixelButton(fill: Color(hex: ok ? 0x1F4F7A : 0x14223A), border: ok ? Color(hex: 0x3FB5E8) : Color(hex: 0x2A3A5C)) {
                    game.buy(u)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(u.title).font(PixelFont.font(7)).lineLimit(1).minimumScaleFactor(0.5)
                            Spacer(minLength: 0)
                            Text(maxed ? L("MAX") : L("niv. \(lvl)")).font(PixelFont.font(5)).opacity(0.7).lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            if !maxed { CoinDot().frame(width: 9, height: 9) }
                            Text(verbatim: maxed ? "-" : "\(u.cost(lvl))")
                                .font(PixelFont.font(8))
                                .foregroundStyle(Color(hex: ok ? 0xFFE066 : 0x8FA8C8))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(ok || maxed ? 1 : 0.65)
                }
                .accessibilityLabel(L("\(u.title), niveau \(lvl)"))
            }
        }
    }

    // MARK: La prise

    private func catchCard(_ c: PecheGame.Catch) -> some View {
        let sp = FishSpecies.all[c.species]
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                if c.isNew {
                    Text(L("NOUVELLE ESPÈCE !")).font(PixelFont.font(10)).foregroundStyle(Color(hex: 0xFF7BEA))
                } else if c.record {
                    Text(L("RECORD !")).font(PixelFont.font(10)).foregroundStyle(Color(hex: 0xFF7BEA))
                }
                PixelImage(image: renderer.sprite(c.species, facingRight: true))
                    .aspectRatio(CGFloat(renderer.sprite(c.species, facingRight: true).width) / CGFloat(renderer.sprite(c.species, facingRight: true).height), contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 120)
                Text(sp.title).font(PixelFont.font(14)).multilineTextAlignment(.center)
                if !sp.junk {
                    Text(L("\(c.size) cm")).font(PixelFont.font(10)).foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 6) {
                    CoinDot().frame(width: 18, height: 18)
                    Text(verbatim: "+\(c.value)").font(PixelFont.font(18)).foregroundStyle(Color(hex: 0xFFE066))
                }
                PixelButton(fill: Color(hex: 0xFFC93C), border: Color(hex: 0x8A4B0C)) {
                    game.again()
                } label: {
                    Text(L("Encore !")).font(PixelFont.font(12)).foregroundStyle(Color(hex: 0x3A1D00)).frame(maxWidth: .infinity, minHeight: 46)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .pixelBox(fill: Color(hex: 0x10203A), border: Color(hex: 0x3FB5E8))
        }
    }

    // MARK: Le carnet

    private var book: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { showBook = false }
            VStack(spacing: 12) {
                HStack {
                    Text(L("CARNET")).font(PixelFont.font(14))
                    Spacer()
                    Text(verbatim: "\(game.speciesCaught) / \(FishSpecies.all.count)").font(PixelFont.font(10)).foregroundStyle(Color(hex: 0xFFE066))
                }
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(FishSpecies.all.indices, id: \.self) { i in
                            bookCell(i)
                        }
                    }
                }
                PixelButton(fill: Color(hex: 0x2C1B5C), border: Color(hex: 0x3FB5E8)) {
                    showBook = false
                } label: {
                    Text(L("Fermer")).font(PixelFont.font(11)).frame(maxWidth: .infinity, minHeight: 42)
                }
            }
            .padding(16)
            .frame(maxWidth: 420, maxHeight: 560)
            .pixelBox(fill: Color(hex: 0x10203A), border: Color(hex: 0x3FB5E8))
            .padding(16)
        }
    }

    private func bookCell(_ i: Int) -> some View {
        let sp = FishSpecies.all[i]
        let size = game.best[sp.id]
        let img = size != nil ? renderer.sprite(i, facingRight: true) : FishArt.sprite(sp, silhouette: true)
        return VStack(spacing: 6) {
            PixelImage(image: img)
                .aspectRatio(CGFloat(img.width) / CGFloat(img.height), contentMode: .fit)
                .frame(height: 34)
            Text(size != nil ? sp.title : "???").font(PixelFont.font(6)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.6)
            if let size, !sp.junk {
                Text(L("\(size) cm")).font(PixelFont.font(6)).foregroundStyle(Color(hex: 0xFFE066))
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(Rectangle().fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

struct PecheField: View {
    let game: PecheGame
    let renderer: PecheRenderer

    var body: some View {
        let _ = game.frame
        PixelImage(image: renderer.render(game), label: L("La mer et ta ligne"))
    }
}
