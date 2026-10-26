import SwiftUI

// MARK: - DUELS : les 8 duels du Pass

/// Signale quand au moins un doigt est posé, et quand le dernier se lève (NERFS D'ACIER).
struct HoldPad: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        view.onChange = onChange
    }

    final class PadView: UIView {
        var onChange: ((Bool) -> Void)?
        private var count = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let wasDown = count > 0
            count += touches.count
            if !wasDown { onChange?(true) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            lift(touches.count)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            lift(touches.count)
        }

        private func lift(_ n: Int) {
            count = max(0, count - n)
            if count == 0 { onChange?(false) }
        }
    }
}

// MARK: Pierre-feuille-ciseaux

struct DuelsRPSPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 14) {
            if let reveal = game.rpsRevealAt, let mine = game.rpsPick[seat], let theirs = game.rpsPick[1 - seat] {
                let k = min(1, (game.t - reveal) / 0.6)
                HStack(spacing: 26) {
                    VStack(spacing: 4) {
                        Text(DuelsGame.rpsEmoji[mine]).font(.system(size: 76))
                        Text(L("Toi")).font(.plie(15, weight: .bold)).foregroundStyle(DuelsGame.color(seat))
                    }
                    Text(verbatim: "vs").font(.plie(20)).foregroundStyle(Theme.muted)
                    VStack(spacing: 4) {
                        Text(DuelsGame.rpsEmoji[theirs]).font(.system(size: 76))
                        Text(L("L'autre")).font(.plie(15, weight: .bold)).foregroundStyle(DuelsGame.color(1 - seat))
                    }
                }
                .scaleEffect(0.7 + 0.3 * k)
                .opacity(k)
            } else if game.rpsPick[seat] != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(DuelsGame.color(seat))
                Text(L("Choisi ! On attend l'autre…"))
                    .font(.plie(20))
            } else {
                if let tie = game.rpsTieAt, game.t - tie < 1.4 {
                    Text(L("Égalité ! On rejoue"))
                        .font(.plie(20))
                        .foregroundStyle(Theme.gold)
                }
                Text(L("Choisis en secret"))
                    .font(.plie(17, weight: .bold))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { k in
                        VStack(spacing: 4) {
                            Text(DuelsGame.rpsEmoji[k]).font(.system(size: 48))
                            Text(DuelsGame.rpsName(k)).font(.plie(13, weight: .bold))
                        }
                        .frame(width: 96, height: 104)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DuelsGame.color(seat).opacity(0.5), lineWidth: 2))
                        .onPressDown { game.rps(seat, k) }
                        .accessibilityLabel(DuelsGame.rpsName(k))
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }
}

// MARK: Nerfs d'acier

struct DuelsNervePanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 12) {
            if let fuse = game.fuseStart {
                let shake = CGFloat(sin(game.t * 40)) * CGFloat(min(6, (game.t - fuse) * 0.8))
                Text(verbatim: "💣")
                    .font(.system(size: 80))
                    .offset(x: shake)
                if let r = game.releasedAfter[seat] {
                    Text(L("Lâché à \(DuelsGame.secs(r)) s"))
                        .font(.plie(22))
                        .foregroundStyle(DuelsGame.color(seat))
                    Text(game.releasedAfter[1 - seat] == nil ? L("L'autre tient encore…") : "")
                        .font(.plie(15, weight: .bold))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text(L("Tiens bon… ou lâche !"))
                        .font(.plie(24))
                    Text(L("\(DuelsGame.secs(game.t - fuse)) s"))
                        .font(.plie(20))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Image(systemName: "hand.point.down.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(game.holding[seat] ? DuelsGame.color(seat) : .white.opacity(0.6))
                Text(game.holding[seat] ? L("Garde ton doigt posé…") : L("Pose un doigt sur ta moitié"))
                    .font(.plie(22))
                    .multilineTextAlignment(.center)
                Text(game.holding[1 - seat] ? L("L'autre est prêt") : L("On attend l'autre…"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: 1 à 9

struct DuelsOrderPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(game.orderNext[seat] <= 9 ? L("Touche le \(game.orderNext[seat])") : L("Fini !"))
                .font(.plie(20))
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { col in
                            tile(row * 3 + col)
                        }
                    }
                }
            }
            .frame(maxWidth: 280)
            .offset(x: shake)
        }
    }

    private var shake: CGFloat {
        guard let m = game.orderMiss[seat], game.t - m < 0.35 else { return 0 }
        return CGFloat(sin((game.t - m) * 70) * 9 * (1 - (game.t - m) / 0.35))
    }

    private func tile(_ cell: Int) -> some View {
        let n = cell < game.orderLayout.count ? game.orderLayout[cell] : 0
        let done = n < game.orderNext[seat]
        return Text("\(n)")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(done ? DuelsGame.color(seat).opacity(0.25) : Color.white.opacity(0.12)))
            .foregroundStyle(done ? .white.opacity(0.3) : .white)
            .onPressDown { game.orderTap(seat, cell: cell) }
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: L'intrus

struct DuelsOddPanel: View {
    let game: DuelsGame
    let seat: Int

    private var locked: Bool { game.t < game.lockedUntil[seat] }

    var body: some View {
        VStack(spacing: 8) {
            Text(locked ? L("Bloqué !") : L("Trouve l'intrus"))
                .font(.plie(19))
                .foregroundStyle(locked ? Theme.coral : .white)
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { col in
                            let cell = row * 4 + col
                            Text(cell == game.oddIndex ? game.oddPair[1] : game.oddPair[0])
                                .font(.system(size: 34))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(game.wrongPick[seat] == cell && locked ? Theme.stop.opacity(0.6) : Color.white.opacity(0.08)))
                                .onPressDown { game.oddTap(seat, cell: cell) }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
            .opacity(locked ? 0.5 : 1)
        }
    }
}

// MARK: Cercle parfait

/// Les traits des deux joueurs, dessinés dans le repère de l'écran entier, et les zones où l'on dessine.
struct DuelsCircleLayer: View {
    let game: DuelsGame
    let interactive: Bool

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for seat in 0..<2 {
                    let pts = game.strokes[seat]
                    guard pts.count > 1 else { continue }
                    let color = DuelsGame.color(seat)
                    if game.circleScore[seat] != nil {
                        let n = CGFloat(pts.count)
                        let cx = pts.reduce(0) { $0 + $1.x } / n
                        let cy = pts.reduce(0) { $0 + $1.y } / n
                        let r = pts.reduce(0) { $0 + hypot($1.x - cx, $1.y - cy) } / n
                        context.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                                       with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    }
                    var path = Path()
                    path.addLines(pts)
                    context.stroke(path, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .allowsHitTesting(false)
            if interactive {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        zone(1)
                            .frame(height: proxy.size.height / 2)
                        zone(0)
                            .frame(height: proxy.size.height / 2)
                    }
                }
            }
        }
        .coordinateSpace(.named("duels.circle"))
        .ignoresSafeArea()
    }

    private func zone(_ seat: Int) -> some View {
        Color.white.opacity(0.001)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("duels.circle"))
                    .onChanged { value in game.circleAdd(seat, value.location) }
                    .onEnded { _ in game.circleEnd(seat) }
            )
    }
}

struct DuelsCirclePanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 6) {
            if let score = game.circleScore[seat] {
                Text(DuelsGame.percent(score))
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(DuelsGame.color(seat))
                Text(game.circleScore[1 - seat] == nil ? L("On attend l'autre…") : "")
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(L("Dessine un cercle d'un seul trait"))
                    .font(.plie(20))
                    .multilineTextAlignment(.center)
                Text(L("Lève le doigt quand tu as fini le tour"))
                    .font(.plie(14, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(maxHeight: .infinity)
    }
}

// MARK: Ballon

struct DuelsBalloonPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                if game.balloonBurst[seat] {
                    Text(verbatim: "💥").font(.system(size: 90))
                } else {
                    let size = 50 + CGFloat(game.balloon[seat]) * 7
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.9), DuelsGame.color(seat)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: size * 0.7))
                        .frame(width: size, height: size * 1.12)
                        .overlay(alignment: .bottom) {
                            DuelsTriangle().fill(DuelsGame.color(seat)).frame(width: 14, height: 10).offset(y: 8)
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: game.balloon[seat])
                }
            }
            .frame(width: 210, height: 230)
            .contentShape(Rectangle())
            .onPressDown { game.pump(seat) }
            .accessibilityLabel(L("Gonfler"))
            .accessibilityAddTraits(.isButton)
            VStack(spacing: 10) {
                Text("\(game.balloon[seat])")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(status)
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(width: 130)
                if !game.balloonDone[seat] {
                    Button {
                        game.stopBalloon(seat)
                    } label: {
                        Text(L("Stop !"))
                            .font(.plie(20))
                            .frame(width: 110, height: 52)
                            .background(Capsule().fill(Theme.go))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(game.balloon[seat] == 0)
                }
            }
        }
    }

    private var status: String {
        if game.balloonBurst[seat] { return L("Éclaté !") }
        if game.balloonDone[seat] { return L("Gardé ! On attend l'autre…") }
        return L("Touche le ballon pour gonfler")
    }
}

struct DuelsTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Pile au centre

struct DuelsTargetPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        let pos = game.targetStop[seat] ?? game.needle
        VStack(spacing: 14) {
            Text(game.targetStop[seat] == nil ? L("Touche pour arrêter l'aiguille") : L("Précision : \(DuelsGame.precision(game.targetStop[seat]))"))
                .font(.plie(19))
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Theme.coral.opacity(0.5)).frame(width: w * 0.3)
                    Capsule().fill(Theme.gold.opacity(0.8)).frame(width: w * 0.12)
                    Rectangle().fill(.white).frame(width: 2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DuelsGame.color(seat))
                        .frame(width: 8, height: 62)
                        .shadow(color: DuelsGame.color(seat).opacity(0.8), radius: 6)
                        .offset(x: CGFloat(pos) * (w / 2 - 6))
                }
            }
            .frame(height: 46)
            .frame(maxWidth: 380)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: Mémo-grille

struct DuelsGridPanel: View {
    let game: DuelsGame
    let seat: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.plie(19))
                .foregroundStyle(game.gridOut[seat] ? Theme.coral : .white)
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { col in
                            cell(row * 4 + col)
                        }
                    }
                }
            }
            .frame(maxWidth: 260)
            .opacity(game.gridOut[seat] ? 0.4 : 1)
        }
    }

    private var title: String {
        if game.gridOut[seat] { return L("Raté… l'autre peut encore gagner") }
        if game.gridShown { return L("Retiens bien !") }
        return L("\(game.gridPicked[seat].count) sur \(game.gridCells.count)")
    }

    private func cell(_ c: Int) -> some View {
        let lit = (game.gridShown && game.gridCells.contains(c)) || game.gridPicked[seat].contains(c)
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(lit ? DuelsGame.color(seat) : Color.white.opacity(0.1))
            .shadow(color: DuelsGame.color(seat).opacity(lit ? 0.7 : 0), radius: 8)
            .frame(height: 52)
            .onPressDown { game.gridTap(seat, cell: c) }
            .accessibilityAddTraits(.isButton)
    }
}
