import SwiftUI

// MARK: - DUELS : l'écran

struct DuelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var game = DuelsGame()

    var body: some View {
        ZStack {
            Color(hex: 0x0B0D1E).ignoresSafeArea()
            if game.phase == .menu {
                menu
            } else {
                DuelsBoard(game: game)
            }
        }
        .foregroundStyle(.white)
        .onFrame { dt in game.tick(dt) }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordDuels() }
        }
        .onAppear { game.hasPass = store.hasEverything }
        .onChange(of: store.hasEverything) { _, owns in game.hasPass = owns }
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                    HowToButton(game: .duels)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                HStack(spacing: -14) {
                    Image(systemName: "hand.point.up.fill")
                        .foregroundStyle(Theme.duelsA)
                        .rotationEffect(.degrees(180))
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.duels)
                        .font(.system(size: 40, weight: .black))
                    Image(systemName: "hand.point.up.fill")
                        .foregroundStyle(Theme.duelsB)
                }
                .font(.system(size: 64, weight: .bold))
                .accessibilityHidden(true)
                Text(L("DUELS"))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .tracking(3)
                Text(L("Le Duo à plat entre vous deux, chacun sa moitié. Des mini-duels express tirés au hasard : réflexes, rapidité, mémoire, sang-froid."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(DuelsGame.Kind.allCases) { k in
                        let locked = k.needsPass && !store.hasEverything
                        HStack(spacing: 8) {
                            Image(systemName: locked ? "lock.fill" : k.symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(locked ? Theme.gold : Theme.duels)
                                .frame(width: 22)
                            Text(k.title)
                                .font(.plie(13, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .opacity(locked ? 0.6 : 1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                    }
                }
                .frame(maxWidth: 520)
                if !store.hasEverything {
                    Button {
                        app.showPass = true
                    } label: {
                        Label(L("+8 duels avec le Pass Origamo"), systemImage: "crown.fill")
                            .font(.plie(15, weight: .heavy))
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .background(Capsule().fill(Theme.gold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(PressableStyle())
                }

                Text(L("Points pour gagner"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    ForEach([3, 5, 7], id: \.self) { n in
                        Button {
                            game.target = n
                        } label: {
                            Text("\(n)")
                                .font(.plie(18, weight: .heavy))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(game.target == n ? Theme.duels : Color.white.opacity(0.1)))
                                .foregroundStyle(game.target == n ? Theme.ink : .white)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(game.target == n ? [.isSelected] : [])
                    }
                }
                .frame(maxWidth: 360)

                Button {
                    game.start()
                } label: {
                    Label(L("C'est parti !"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.duels, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)
                Text(L("Posez le Duo ouvert à plat, un joueur de chaque côté."))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Le plateau

struct DuelsBoard: View {
    let game: DuelsGame

    private var tapKinds: Bool {
        switch game.kind {
        case .draw, .tug, .stroop, .twins, .blind, .target: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            FaceToFace { seat in
                DuelsHalf(game: game, seat: seat)
            }
            if game.kind == .tug && (game.phase == .playing || game.phase == .result) {
                DuelsRope(rope: game.rope)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if game.kind == .circle && (game.phase == .playing || game.phase == .result) {
                DuelsCircleLayer(game: game, interactive: game.phase == .playing && !game.paused)
            }
            if game.phase == .playing && !game.paused {
                if tapKinds {
                    VStack(spacing: 0) {
                        MultiTapPad { game.tap(1) }
                        MultiTapPad { game.tap(0) }
                    }
                    .ignoresSafeArea()
                } else if game.kind == .nerve {
                    VStack(spacing: 0) {
                        HoldPad { down in game.hold(1, down) }
                        HoldPad { down in game.hold(0, down) }
                    }
                    .ignoresSafeArea()
                } else if game.kind == .arrows {
                    VStack(spacing: 0) {
                        // Le joueur d'en face est retourné : ce qui monte pour l'écran descend pour lui.
                        SwipeZone(threshold: 26, onSwipe: { d in game.swipe(1, d.opposite) })
                        SwipeZone(threshold: 26, onSwipe: { d in game.swipe(0, d) })
                    }
                    .ignoresSafeArea()
                }
            }
            if game.phase != .over {
                HStack {
                    HingeButton(symbol: game.paused ? "play.fill" : "pause.fill", label: L("Pause")) { game.togglePause() }
                        .padding(.leading, 10)
                    Spacer()
                }
            }
            if game.paused {
                VStack(spacing: 12) {
                    Text(L("Pause")).font(.plie(28))
                    Button {
                        game.togglePause()
                    } label: {
                        Label(L("Reprendre"), systemImage: "play.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.duels, textColor: Theme.ink, height: 54))
                    Button(L("Quitter la partie")) { game.backToMenu() }
                        .buttonStyle(GhostButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: 320)
                .winCard(accent: Theme.duels)
            }
        }
    }
}

/// La corde, à cheval sur la charnière. Le nœud rouge part vers celui qui tire le plus.
struct DuelsRope: View {
    let rope: Double

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let mid = size.height / 2
            let span = size.height * 0.33
            let knot = mid - CGFloat(rope) * span
            for (y, color) in [(mid - span, Theme.duelsB), (mid + span, Theme.duelsA)] {
                var line = Path()
                line.move(to: CGPoint(x: cx - 90, y: y))
                line.addLine(to: CGPoint(x: cx + 90, y: y))
                context.stroke(line, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 8]))
            }
            var cord = Path()
            cord.move(to: CGPoint(x: cx, y: size.height * 0.04 - CGFloat(rope) * span))
            cord.addLine(to: CGPoint(x: cx, y: size.height * 0.96 - CGFloat(rope) * span))
            context.stroke(cord, with: .color(Color(hex: 0x8A6A3C)), style: StrokeStyle(lineWidth: 16, lineCap: .round))
            context.stroke(cord, with: .color(Color(hex: 0xD9B27A)), style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [7, 7]))
            let r: CGFloat = 20
            context.fill(Path(ellipseIn: CGRect(x: cx - r, y: knot - r, width: 2 * r, height: 2 * r)), with: .color(Theme.coral))
            context.stroke(Path(ellipseIn: CGRect(x: cx - r, y: knot - r, width: 2 * r, height: 2 * r)), with: .color(.white), lineWidth: 3)
        }
    }
}

// MARK: - La moitié d'un joueur

struct DuelsHalf: View {
    let game: DuelsGame
    let seat: Int

    private var color: Color { DuelsGame.color(seat) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B0D1E), color.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                if game.phase == .over && seat == 0 {
                    overButtons
                        .padding(.bottom, 12)
                }
            }
        }
        .clipped()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 54)
            if game.phase != .over {
                Text(L("Manche \(game.round)"))
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text("\(game.score[seat])").foregroundStyle(color)
                Text(verbatim: "–").foregroundStyle(Theme.muted)
                Text("\(game.score[1 - seat])").foregroundStyle(DuelsGame.color(1 - seat))
                Circle().fill(DuelsGame.color(1 - seat)).frame(width: 10, height: 10)
            }
            .font(.plie(18))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Score : toi \(game.score[seat]), l'autre \(game.score[1 - seat])"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch game.phase {
        case .intro:
            DuelsIntro(game: game, seat: seat)
        case .playing:
            DuelsPanel(game: game, seat: seat)
        case .result:
            DuelsResult(game: game, seat: seat)
        case .over:
            VStack(spacing: 8) {
                Text(game.matchWinner == seat ? L("Gagné !") : L("Perdu…"))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(game.matchWinner == seat ? color : .white.opacity(0.75))
                    .shadow(color: color.opacity(game.matchWinner == seat ? 0.7 : 0), radius: 10)
                Text("\(game.score[seat]) – \(game.score[1 - seat])")
                    .font(.plie(24))
                    .foregroundStyle(Theme.muted)
                if game.matchWinner == seat {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }
        case .menu:
            EmptyView()
        }
    }

    private var overButtons: some View {
        HStack(spacing: 10) {
            Button {
                game.start()
            } label: {
                Label(L("Revanche"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.duels, textColor: Theme.ink, height: 50))
            Button(L("Menu")) { game.backToMenu() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 130)
        }
        .padding(.horizontal, 20)
    }
}

struct DuelsIntro: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: game.kind.symbol)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.duels)
            Text(game.kind.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(game.kind.rule)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            GeometryReader { proxy in
                Capsule().fill(Color.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(DuelsGame.color(seat))
                            .frame(width: proxy.size.width * CGFloat(min(1, game.t / DuelsGame.introLength)))
                    }
            }
            .frame(width: 180, height: 8)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }
}

struct DuelsResult: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 10) {
            if let w = game.winner {
                Text(w == seat ? L("+1 pour toi !") : L("Point pour \(DuelsGame.name(w))"))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(w == seat ? DuelsGame.color(seat) : .white.opacity(0.75))
                    .multilineTextAlignment(.center)
            } else {
                Text(L("Personne ne marque"))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(game.note)
                .font(.plie(17, weight: .bold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.45)))
        .padding(.horizontal, 20)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Les mini-jeux

struct DuelsPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        switch game.kind {
        case .draw: DuelsDrawPanel(game: game)
        case .tug: DuelsTugPanel(game: game, seat: seat)
        case .math, .count: DuelsChoicePanel(game: game, seat: seat)
        case .stroop, .twins: DuelsWordPanel(game: game)
        case .blind: DuelsBlindPanel(game: game, seat: seat)
        case .moles: DuelsMolesPanel(game: game, seat: seat)
        case .arrows: DuelsArrowsPanel(game: game, seat: seat)
        case .simon: DuelsSimonPanel(game: game, seat: seat)
        case .rps: DuelsRPSPanel(game: game, seat: seat)
        case .nerve: DuelsNervePanel(game: game, seat: seat)
        case .order: DuelsOrderPanel(game: game, seat: seat)
        case .odd: DuelsOddPanel(game: game, seat: seat)
        case .circle: DuelsCirclePanel(game: game, seat: seat)
        case .balloon: DuelsBalloonPanel(game: game, seat: seat)
        case .target: DuelsTargetPanel(game: game, seat: seat)
        case .grid: DuelsGridPanel(game: game, seat: seat)
        }
    }
}

struct DuelsDrawPanel: View {
    let game: DuelsGame

    var body: some View {
        let fired = game.t >= game.fireAt
        VStack(spacing: 10) {
            if fired {
                Text(L("FEU !"))
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .shadow(color: Theme.coral.opacity(0.9), radius: 12)
                    .scaleEffect(1 + 0.15 * max(0, 1 - (game.t - game.fireAt) * 6))
                Text(L("Touche !"))
                    .font(.plie(22))
            } else {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 3)
                        .frame(width: 120, height: 120)
                        .scaleEffect(1 + 0.08 * sin(game.t * 7))
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text(L("Attends…"))
                    .font(.plie(28))
                Text(L("Ne touche pas encore !"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct DuelsTugPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        HStack {
            VStack(spacing: 6) {
                Text(L("TAPE !"))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(DuelsGame.color(seat))
                    .scaleEffect(1 + 0.06 * sin(game.t * 14))
                Text("\(game.pulls[seat])")
                    .font(.plie(22))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(width: 80)
            VStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(L("Plus vite !"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
    }
}

/// Calcul éclair et bon compte : une question, des réponses à toucher.
struct DuelsChoicePanel: View {
    let game: DuelsGame
    let seat: Int

    private var locked: Bool { game.t < game.lockedUntil[seat] }

    var body: some View {
        VStack(spacing: 12) {
            if game.kind == .math {
                Text(game.question + " = ?")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
            } else {
                DuelsDots(game: game)
                    .frame(maxWidth: 380, maxHeight: 190)
                Text(L("Plus de \(game.countPair[0]) ou de \(game.countPair[1]) ?"))
                    .font(.plie(18, weight: .bold))
            }
            HStack(spacing: 10) {
                ForEach(Array(game.choices.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(size: game.kind == .math ? 30 : 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(game.wrongPick[seat] == item.offset && locked ? Theme.stop.opacity(0.7) : Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DuelsGame.color(seat).opacity(0.6), lineWidth: 2))
                        .onPressDown { game.pick(seat, item.offset) }
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(maxWidth: 420)
            .opacity(locked ? 0.45 : 1)
            .overlay {
                if locked {
                    Text(L("Bloqué !"))
                        .font(.plie(20))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.stop))
                }
            }
        }
        .padding(.horizontal, 18)
    }
}

struct DuelsDots: View {
    let game: DuelsGame

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.3))
                if game.dotsVisible {
                    ForEach(Array(game.dots.enumerated()), id: \.offset) { item in
                        Text(game.countPair[item.element.kind])
                            .font(.system(size: 22))
                            .position(x: proxy.size.width * item.element.x, y: proxy.size.height * item.element.y)
                    }
                } else {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Couleur piège et jumeaux : un mot ou un dessin qui change tout seul.
struct DuelsWordPanel: View {
    let game: DuelsGame

    var body: some View {
        VStack(spacing: 14) {
            if let w = game.currentWord {
                if game.kind == .stroop {
                    Text(w.text)
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: DuelsGame.inks[w.ink % DuelsGame.inks.count]))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .id(Int(game.t / game.slot))
                } else {
                    Text(w.text)
                        .font(.system(size: 92))
                        .id(Int(game.t / game.slot))
                }
            }
            Text(game.kind == .stroop ? L("Touche si le mot est écrit dans SA couleur") : L("Touche si c'est le même que juste avant"))
                .font(.plie(15, weight: .bold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}

struct DuelsBlindPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(L("Arrête-toi pile à \(Int(game.blindTarget)) s"))
                .font(.plie(22))
            if let s = game.stopped[seat] {
                Text(L("Arrêté !"))
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .foregroundStyle(DuelsGame.color(seat))
                Text(game.stopped[1 - seat] == nil ? L("On attend l'autre…") : DuelsGame.format(s))
                    .font(.plie(17, weight: .bold))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(game.blindShown ? DuelsGame.secs(game.t) : "?,??")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(game.blindShown ? .white : .white.opacity(0.5))
                Text(L("Touche ta moitié pour arrêter"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct DuelsMolesPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { k in
                    Image(systemName: k < game.hits[seat] ? "circle.fill" : "circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(k < game.hits[seat] ? DuelsGame.color(seat) : .white.opacity(0.3))
                }
                Text(L("l'autre : \(game.hits[1 - seat])"))
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(game.hits[seat]) taupes sur 6"))
            let side = 3
            VStack(spacing: 8) {
                ForEach(0..<side, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<side, id: \.self) { col in
                            DuelsHole(game: game, seat: seat, hole: row * side + col)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
            .offset(x: shake)
        }
    }

    private var shake: CGFloat {
        guard let b = game.boomAt[seat], game.t - b < 0.4 else { return 0 }
        return CGFloat(sin((game.t - b) * 60) * 8 * (1 - (game.t - b) / 0.4))
    }
}

struct DuelsHole: View {
    let game: DuelsGame
    let seat: Int
    let hole: Int

    var body: some View {
        let m = game.mole(at: hole, for: seat)
        ZStack {
            Ellipse().fill(Color(hex: 0x2A1A10))
                .frame(height: 30)
                .offset(y: 18)
            if let m {
                let rise = min(1, (game.t - m.at) / 0.12)
                Text(m.bomb ? "💣" : "🐹")
                    .font(.system(size: 40))
                    .offset(y: 14 - 22 * CGFloat(rise))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x3B6B2A).opacity(0.55)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onPressDown { game.whack(seat, hole: hole) }
        .accessibilityLabel(m == nil ? L("Trou vide") : (m?.bomb == true ? L("Bombe") : L("Taupe")))
        .accessibilityAddTraits(.isButton)
    }
}

struct DuelsArrowsPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(game.arrows.enumerated()), id: \.offset) { item in
                    let done = item.offset < game.arrowStep[seat]
                    let current = item.offset == game.arrowStep[seat]
                    Image(systemName: item.element.symbol)
                        .font(.system(size: current ? 40 : 28, weight: .black))
                        .foregroundStyle(done ? Theme.go : (current ? DuelsGame.color(seat) : .white.opacity(0.55)))
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(current ? 0.14 : 0.05)))
                }
            }
            .offset(x: shake)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Flèche \(min(game.arrows.count, game.arrowStep[seat] + 1)) sur \(game.arrows.count)"))
            Text(L("Glisse le doigt dans le sens de la flèche"))
                .font(.plie(15, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var shake: CGFloat {
        guard let m = game.arrowMiss[seat], game.t - m < 0.35 else { return 0 }
        return CGFloat(sin((game.t - m) * 70) * 10 * (1 - (game.t - m) / 0.35))
    }
}

struct DuelsSimonPanel: View {
    let game: DuelsGame
    let seat: Int

    static let pads: [UInt32] = [0x3DDB7A, 0xFF4D5E, 0xFFD23D, 0x4D8BFF]

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.plie(20))
            HStack(spacing: 6) {
                ForEach(0..<game.simon.count, id: \.self) { k in
                    Circle()
                        .fill(k < game.simonStep[seat] ? DuelsGame.color(seat) : Color.white.opacity(0.18))
                        .frame(width: 10, height: 10)
                }
            }
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<2, id: \.self) { col in
                            pad(row * 2 + col)
                        }
                    }
                }
            }
            .frame(maxWidth: 260)
            .opacity(game.simonOut[seat] ? 0.35 : 1)
        }
    }

    private var title: String {
        if game.simonOut[seat] { return L("Raté… l'autre peut encore gagner") }
        return game.simonInput ? L("À toi ! Rejoue la suite") : L("Regarde bien…")
    }

    private func lit(_ p: Int) -> Bool {
        if let k = game.simonFlash, game.simon[k] == p { return true }
        if let press = game.pressed[seat], press.pad == p, game.t - press.at < 0.22 { return true }
        return false
    }

    private func pad(_ p: Int) -> some View {
        let color = Color(hex: Self.pads[p])
        let on = lit(p)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(color.opacity(on ? 1 : 0.32))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(on ? 0.9 : 0.1), lineWidth: 3))
            .shadow(color: color.opacity(on ? 0.8 : 0), radius: 12)
            .frame(height: 74)
            .onPressDown { game.press(seat, pad: p) }
            .accessibilityLabel(L("Couleur \(p + 1)"))
            .accessibilityAddTraits(.isButton)
    }
}
