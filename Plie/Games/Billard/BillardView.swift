import SwiftUI
import Combine

extension Theme {
    static let billard = Color(hex: 0x2FD08C)
}

// MARK: - Partie

@Observable
final class BillardMatch {
    enum Phase: Equatable {
        case menu, aiming, rolling, over
    }

    private(set) var phase: Phase = .menu
    private(set) var solo = true
    private(set) var world = BillardWorld(width: 0.7, balls: BillardWorld.rack(width: 0.7))
    private(set) var current = 0
    private(set) var groups: [BGroup] = [.open, .open]
    private(set) var ballInHand = false
    private(set) var winner: Int?
    private(set) var message: String?
    private(set) var messageAt: Double = 0
    private(set) var clock: Double = 0
    private(set) var aiThinking = false
    private(set) var shots = [0, 0]
    /// Visée en cours : direction du tir et puissance (0 à 1), ou nil.
    private(set) var aim: BVec?
    private(set) var power: Double = 0

    @ObservationIgnored private var log = BShotLog()
    @ObservationIgnored private var ballsBefore: [BBall] = []
    @ObservationIgnored private var isBreak = true
    @ObservationIgnored private var lastClack: Double = 0
    @ObservationIgnored private var lastCushion: Double = 0
    @ObservationIgnored private var aiToken = 0

    var isComputerTurn: Bool { solo && current == 1 }

    var turnText: String {
        if solo { return current == 0 ? L("À toi !") : L("À l'ordi") }
        return current == 0 ? L("Au joueur 1") : L("Au joueur 2")
    }

    func playerName(_ p: Int) -> String {
        if solo { return p == 0 ? L("Toi") : L("L'ordi") }
        return p == 0 ? L("Joueur 1") : L("Joueur 2")
    }

    func start(solo: Bool, width: Double) {
        self.solo = solo
        world = BillardWorld(width: width, balls: BillardWorld.rack(width: width))
        current = 0
        groups = [.open, .open]
        ballInHand = true
        winner = nil
        shots = [0, 0]
        isBreak = true
        aim = nil
        power = 0
        phase = .aiming
        say(solo ? L("À toi de casser !") : L("À \(playerName(0)) de casser !"))
        SoundPlayer.shared.play(.go, volume: 0.6)
    }

    func backToMenu() {
        aiToken += 1
        aiThinking = false
        phase = .menu
        message = nil
    }

    /// La table change de forme (rotation, ouverture du Duo) : on garde les billes dans la table.
    func resize(width: Double) {
        guard abs(width - world.width) > 0.001 else { return }
        let k = width / world.width
        world.width = width
        for i in world.balls.indices {
            world.balls[i].p.y *= k
        }
    }

    private func say(_ text: String) {
        message = text
        messageAt = clock
    }

    // MARK: Commandes

    func moveCueBall(to p: BVec) {
        guard phase == .aiming, ballInHand, !isComputerTurn else { return }
        // Avant la casse, la blanche reste dans le quart gauche de la table.
        var q = p
        if isBreak { q.x = min(q.x, 0.3) }
        if world.canPlace(q, ignoring: 0) {
            world.balls[0].p = q
        }
    }

    func setAim(direction: BVec, power: Double) {
        guard phase == .aiming, !isComputerTurn else { return }
        aim = direction.normalized
        self.power = min(1, max(0, power))
    }

    func cancelAim() {
        aim = nil
        power = 0
    }

    func shoot() {
        guard phase == .aiming, let direction = aim, power > 0.04 else {
            cancelAim()
            return
        }
        fire(direction: direction, power: power)
    }

    private func fire(direction: BVec, power: Double) {
        ballsBefore = world.balls
        log = BShotLog()
        world.balls[0].v = direction * (max(0.06, power) * BillardWorld.maxSpeed)
        shots[current] += 1
        phase = .rolling
        ballInHand = false
        aim = nil
        self.power = 0
        message = nil
        SoundPlayer.shared.play(.pok, volume: Float(0.4 + 0.6 * power))
        Haptics.tap()
    }

    // MARK: Boucle

    func tick(dt: Double) {
        clock += dt
        if let m = message, !m.isEmpty, clock - messageAt > 2.4, phase != .over { message = nil }
        guard phase == .rolling else { return }
        let events = world.step(dt)
        log.record(events)
        for e in events {
            switch e {
            case .ballHit(_, _, let speed):
                if clock - lastClack > 0.035 {
                    lastClack = clock
                    SoundPlayer.shared.play(.clack, volume: Float(min(1, 0.15 + speed / 2.2)))
                }
            case .cushion(_, let speed):
                if speed > 0.08 && clock - lastCushion > 0.05 {
                    lastCushion = clock
                    SoundPlayer.shared.play(.tock, volume: Float(min(0.6, speed / 3)))
                }
            case .pocket(let ball):
                SoundPlayer.shared.play(.pocket, volume: 0.9)
                if ball != 0 { Haptics.correct(subtle: true) }
            }
        }
        if !world.moving { resolve() }
    }

    private func resolve() {
        let shooter = current
        let judged = BillardRules.judge(log: log, shooter: shooter, groups: &groups, ballsBefore: ballsBefore, isBreak: isBreak)
        isBreak = false
        var verdict = judged
        if verdict.assigned {
            let solids = groups[shooter] == .solids
            if solo {
                verdict.message = shooter == 0 ? (solids ? L("Tu joues les pleines") : L("Tu joues les rayées"))
                                               : (solids ? L("L'ordi joue les pleines") : L("L'ordi joue les rayées"))
            } else {
                verdict.message = solids ? L("\(playerName(shooter)) joue les pleines") : L("\(playerName(shooter)) joue les rayées")
            }
        }
        if let w = verdict.winner {
            winner = w
            phase = .over
            say(verdict.message)
            SoundPlayer.shared.play(.win, volume: 0.9)
            if !(solo && w == 1) {
                SoundPlayer.shared.play(.applause, volume: 0.8)
                Haptics.success()
            }
            return
        }
        if log.scratch {
            world.balls[0].pocketed = false
            world.balls[0].v = .zero
            world.balls[0].p = freeSpot()
        }
        if verdict.foul {
            current = 1 - shooter
            ballInHand = true
            say(verdict.message + " · " + (solo && current == 0 ? L("Tu places la blanche") : L("\(playerName(current)) place la blanche")))
            SoundPlayer.shared.play(.wrong, volume: 0.5)
            Haptics.warning()
        } else if verdict.keepsTurn {
            say(verdict.message.isEmpty ? L("Rejoue !") : verdict.message)
        } else {
            current = 1 - shooter
            say(verdict.assigned ? verdict.message : turnText)
        }
        phase = .aiming
        if isComputerTurn { computerTurn() }
    }

    /// Une place libre pour la blanche, le plus près possible de son point de départ.
    private func freeSpot() -> BVec {
        let r = BillardWorld.radius
        let start = BVec(x: 0.25, y: world.width / 2)
        if world.canPlace(start, ignoring: 0) { return start }
        for ring in 1..<30 {
            for k in 0..<12 {
                let a = Double(k) * .pi / 6
                let p = BVec(x: start.x + cos(a) * r * 2.2 * Double(ring), y: start.y + sin(a) * r * 2.2 * Double(ring))
                if world.canPlace(p, ignoring: 0) { return p }
            }
        }
        return start
    }

    private func computerTurn() {
        aiToken += 1
        let token = aiToken
        aiThinking = true
        // Bille en main : l'ordinateur la replace au centre de sa zone avant de jouer.
        if ballInHand {
            world.balls[0].p = freeSpot()
        }
        let snapshot = world
        let group = groups[1]
        DispatchQueue.global(qos: .userInitiated).async {
            let shot = BillardAI.choose(world: snapshot, group: group, skill: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, token == self.aiToken, self.phase == .aiming, self.isComputerTurn else { return }
                self.aim = shot.direction
                self.power = shot.power
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, token == self.aiToken, self.phase == .aiming else { return }
                    self.aiThinking = false
                    self.fire(direction: shot.direction, power: shot.power)
                }
            }
        }
    }

    /// Billes rentrées par groupe, pour la rangée de chaque joueur.
    func remaining(for player: Int) -> [Int] {
        let g = groups[player]
        guard g != .open else { return [] }
        return world.balls.filter { g.owns($0.number) && !$0.pocketed }.map(\.number)
    }
}

// MARK: - Géométrie à l'écran

struct BillardLayout {
    let size: CGSize
    let rail: CGFloat
    let felt: CGRect

    init(size: CGSize) {
        self.size = size
        rail = max(26, min(size.height * 0.075, 54))
        felt = CGRect(x: rail, y: rail, width: size.width - rail * 2, height: size.height - rail * 2)
    }

    var scale: CGFloat { felt.width }
    var tableWidth: Double { Double(felt.height / max(1, felt.width)) }

    func screen(_ p: BVec) -> CGPoint {
        CGPoint(x: felt.minX + CGFloat(p.x) * scale, y: felt.minY + CGFloat(p.y) * scale)
    }

    func table(_ p: CGPoint) -> BVec {
        BVec(x: Double((p.x - felt.minX) / scale), y: Double((p.y - felt.minY) / scale))
    }
}

// MARK: - Écran

struct BillardView: View {
    @Environment(AppState.self) private var app
    @State private var match = BillardMatch()
    @State private var landscape = true
    @State private var dragMode = DragMode.none

    enum DragMode { case none, placing, aiming }


    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = BillardLayout(size: size)
            ZStack {
                if size.width >= size.height {
                    BillardTableView(match: match, layout: layout)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(layout))

                    hud(layout: layout, safeTop: proxy.safeAreaInsets.top)

                    if match.phase == .menu || match.phase == .over {
                        menu(width: layout.tableWidth)
                    }
                } else {
                    RotateToLandscapePrompt(color: Theme.billard,
                                            text: L("Le billard se joue sur tout l'écran, à l'horizontale. Pose le Duo ouvert à plat : la charnière passe par les poches du milieu.")) {
                        app.route = .hub
                    }
                }
            }
            .onAppear {
                landscape = size.width >= size.height
                if landscape { match.resize(width: layout.tableWidth) }
            }
            .onChange(of: size) { _, newSize in
                landscape = newSize.width >= newSize.height
                if landscape { match.resize(width: BillardLayout(size: newSize).tableWidth) }
            }
        }
        .ignoresSafeArea()
        .onFrame { _ in
            if landscape { match.tick(dt: 1.0 / 60.0) }
        }
        .onChange(of: match.phase) { _, phase in
            if phase == .over, let w = match.winner {
                app.recordBillard(won: !(match.solo && w == 1))
            }
        }
    }

    private func dragGesture(_ layout: BillardLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard match.phase == .aiming, !match.isComputerTurn else { return }
                let start = layout.table(value.startLocation)
                let now = layout.table(value.location)
                if dragMode == .none {
                    let cue = match.world.balls[0].p
                    dragMode = match.ballInHand && (start - cue).length < BillardWorld.radius * 3.2 ? .placing : .aiming
                }
                switch dragMode {
                case .placing:
                    match.moveCueBall(to: now)
                case .aiming:
                    // On tire vers l'arrière, comme avec une queue : le tir part à l'opposé du geste.
                    let pull = start - now
                    let length = pull.length
                    if length > 0.012 {
                        match.setAim(direction: pull, power: (length - 0.012) / 0.3)
                    }
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if dragMode == .aiming { match.shoot() }
                dragMode = .none
            }
    }

    private func hud(layout: BillardLayout, safeTop: CGFloat) -> some View {
        VStack {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                HowToButton(game: .billard)
                Spacer()
                if match.phase != .menu {
                    playerTag(0)
                    Text(verbatim: "·").foregroundStyle(Theme.muted)
                    playerTag(1)
                }
                Spacer()
                Color.clear.frame(width: 98, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, max(4, (layout.rail - 44) / 2))
            Spacer()
            if let message = match.message, match.phase != .menu {
                Text(message)
                    .font(.plie(18, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .transition(.opacity)
                    .padding(.bottom, layout.rail + 10)
            } else if match.phase == .aiming && !match.isComputerTurn {
                Text(match.ballInHand ? L("Déplace la blanche, puis tire vers l'arrière et lâche") : L("Tire vers l'arrière et lâche pour jouer"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .padding(.bottom, layout.rail + 10)
            } else if match.aiThinking {
                Label(L("L'ordi réfléchit…"), systemImage: "brain.head.profile")
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .padding(.bottom, layout.rail + 10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: match.message)
    }

    private func playerTag(_ p: Int) -> some View {
        let active = match.current == p && match.phase != .over
        let group = match.groups[p]
        return HStack(spacing: 6) {
            Circle()
                .fill(group == .stripes ? Color.white : (group == .solids ? Theme.gold : Color.white.opacity(0.3)))
                .overlay(Circle().strokeBorder(group == .stripes ? Theme.gold : .clear, lineWidth: 3))
                .frame(width: 14, height: 14)
            Text(match.playerName(p))
                .font(.plie(15, weight: .heavy))
            if group != .open {
                Text("\(match.remaining(for: p).count)")
                    .font(.plie(13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(active ? Theme.billard.opacity(0.9) : Color.black.opacity(0.45)))
        .foregroundStyle(active ? Theme.ink : .white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(active ? L("\(match.playerName(p)) : c'est son tour") : match.playerName(p))
    }

    private func menu(width: Double) -> some View {
        VStack(spacing: 14) {
            if match.phase == .over, let w = match.winner {
                WinIcon(systemName: "trophy.fill", color: Theme.gold)
                Text(match.solo ? (w == 0 ? L("Tu as gagné !") : L("L'ordinateur gagne")) : L("\(match.playerName(w)) gagne !"))
                    .font(.plie(30))
                if let message = match.message {
                    Text(message)
                        .font(.plie(16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                if !(match.solo && w == 1) {
                    ShareResultButton(game: L("BILLARD"), result: L("Partie gagnée en \(match.shots[w]) coups"), accent: Theme.billard)
                }
            } else {
                WinIcon(systemName: "circle.grid.cross.fill", color: Theme.billard)
                Text(L("Billard à 8 billes"))
                    .font(.plie(26))
                Text(L("Rentre toutes tes billes, pleines ou rayées, puis la noire. Tire vers l'arrière et lâche pour jouer."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button(L("Contre l'ordi")) { match.start(solo: true, width: width) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.billard, textColor: Theme.ink))
                Button(L("À deux")) { match.start(solo: false, width: width) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
            }
            .frame(maxWidth: 380)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 480)
        .winCard(accent: Theme.billard)
        .padding(20)
        .overlay {
            if match.phase == .over, let w = match.winner, !(match.solo && w == 1) {
                ConfettiView().allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Dessin de la table

struct BillardTableView: View {
    let match: BillardMatch
    let layout: BillardLayout

    var body: some View {
        let balls = match.world.balls
        let aim = match.aim
        let power = match.power
        let phase = match.phase
        let ballInHand = match.ballInHand
        let pockets = match.world.pockets
        let width = match.world.width
        let world = match.world
        let showCue = phase == .aiming

        Canvas { context, size in
            let L0 = layout
            let felt = L0.felt
            let r = CGFloat(BillardWorld.radius) * L0.scale

            // Bois des bandes
            let outer = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: outer, cornerRadius: L0.rail * 0.6),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x6B3A1F), Color(hex: 0x3E1F0E)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for i in 0..<14 {
                let y = CGFloat(Draw.hash(i, 71)) * size.height
                var grain = Path()
                grain.move(to: CGPoint(x: 0, y: y))
                grain.addCurve(to: CGPoint(x: size.width, y: y + 6),
                               control1: CGPoint(x: size.width * 0.3, y: y - 5), control2: CGPoint(x: size.width * 0.7, y: y + 9))
                context.stroke(grain, with: .color(.black.opacity(0.08)), lineWidth: 1.2)
            }
            // Mouches (repères en nacre) sur les bandes
            for k in 1..<8 where k != 4 {
                let x = felt.minX + felt.width * CGFloat(k) / 8
                for y in [L0.rail * 0.5, size.height - L0.rail * 0.5] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(Color(hex: 0xF4E9D0)))
                }
            }
            for k in 1..<4 {
                let y = felt.minY + felt.height * CGFloat(k) / 4
                for x in [L0.rail * 0.5, size.width - L0.rail * 0.5] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(Color(hex: 0xF4E9D0)))
                }
            }

            // Tapis
            let cushion = felt.insetBy(dx: -L0.rail * 0.22, dy: -L0.rail * 0.22)
            context.fill(Path(roundedRect: cushion, cornerRadius: 6), with: .color(Color(hex: 0x0C6B47)))
            context.fill(Path(felt), with: .linearGradient(Gradient(colors: [Color(hex: 0x14A06B), Color(hex: 0x0E8558)]),
                                                         startPoint: CGPoint(x: 0, y: felt.minY), endPoint: CGPoint(x: 0, y: felt.maxY)))
            context.fill(Path(felt), with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .clear]),
                                                         center: CGPoint(x: felt.midX, y: felt.midY), startRadius: 0, endRadius: felt.width * 0.55))
            // Ligne de casse et point de la pyramide
            var head = Path()
            head.move(to: CGPoint(x: felt.minX + felt.width * 0.3, y: felt.minY))
            head.addLine(to: CGPoint(x: felt.minX + felt.width * 0.3, y: felt.maxY))
            context.stroke(head, with: .color(.white.opacity(0.12)), lineWidth: 1)
            let spot = L0.screen(BVec(x: 0.72, y: width / 2))
            context.fill(Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.25)))

            // Poches
            for (k, pc) in pockets.enumerated() {
                let c = L0.screen(pc)
                let pr = CGFloat(BillardWorld.pocketRadius(k)) * L0.scale * 0.95
                context.fill(Path(ellipseIn: CGRect(x: c.x - pr - 4, y: c.y - pr - 4, width: pr * 2 + 8, height: pr * 2 + 8)),
                             with: .color(Color(hex: 0x2A1A10)))
                context.fill(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)),
                             with: .radialGradient(Gradient(colors: [.black, Color(hex: 0x111111)]), center: c, startRadius: 0, endRadius: pr))
            }

            // Guide de visée : jusqu'à la première bille ou la première bande
            if showCue, let dir = aim, !balls[0].pocketed {
                let cue = balls[0].p
                let hit = BillardTableView.firstContact(world: world, from: cue, dir: dir)
                let a = L0.screen(cue)
                let b = L0.screen(hit.point)
                var guide = Path()
                guide.move(to: a)
                guide.addLine(to: b)
                context.stroke(guide, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7]))
                context.stroke(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                if let target = hit.ball {
                    // Direction que prendra la bille touchée
                    let t = balls[target].p
                    let n = (t - hit.point).normalized
                    let tp = L0.screen(t)
                    var line = Path()
                    line.move(to: tp)
                    line.addLine(to: CGPoint(x: tp.x + CGFloat(n.x) * r * 5, y: tp.y + CGFloat(n.y) * r * 5))
                    context.stroke(line, with: .color(Theme.gold.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }

            // Billes : ombre, couleur, bande des rayées, numéro
            for b in balls where !b.pocketed {
                let c = L0.screen(b.p)
                context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.95 + r * 0.3, y: c.y - r * 0.8 + r * 0.4, width: r * 1.9, height: r * 1.6)),
                             with: .color(.black.opacity(0.3)))
                BillardTableView.drawBall(&context, number: b.number, center: c, radius: r, spin: b.spin)
            }

            // Bille en main : halo autour de la blanche
            if ballInHand && phase == .aiming && !balls[0].pocketed {
                let c = L0.screen(balls[0].p)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 1.9, width: r * 3.8, height: r * 3.8)),
                               with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }

            // La queue, derrière la blanche, reculée selon la puissance
            if showCue, let dir = aim, !balls[0].pocketed {
                let c = L0.screen(balls[0].p)
                let back = CGPoint(x: -CGFloat(dir.x), y: -CGFloat(dir.y))
                let gap = r * 1.4 + CGFloat(power) * r * 6
                let tip = CGPoint(x: c.x + back.x * gap, y: c.y + back.y * gap)
                let length = L0.scale * 0.55
                let butt = CGPoint(x: tip.x + back.x * length, y: tip.y + back.y * length)
                var shadowPath = Path()
                shadowPath.move(to: CGPoint(x: tip.x + 4, y: tip.y + 6))
                shadowPath.addLine(to: CGPoint(x: butt.x + 4, y: butt.y + 6))
                context.stroke(shadowPath, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: r * 0.8, lineCap: .round))
                var stick = Path()
                stick.move(to: tip)
                stick.addLine(to: butt)
                context.stroke(stick, with: .linearGradient(Gradient(colors: [Color(hex: 0xF3DDB0), Color(hex: 0xC8924F), Color(hex: 0x3B1E0E)]),
                                                            startPoint: tip, endPoint: butt),
                               style: StrokeStyle(lineWidth: r * 0.62, lineCap: .round))
                var chalk = Path()
                chalk.move(to: tip)
                chalk.addLine(to: CGPoint(x: tip.x + back.x * r * 0.5, y: tip.y + back.y * r * 0.5))
                context.stroke(chalk, with: .color(Color(hex: 0x4D8BFF)), style: StrokeStyle(lineWidth: r * 0.62, lineCap: .round))
                // Jauge de puissance
                let gauge = CGRect(x: felt.midX - 80, y: felt.maxY - 18, width: 160, height: 8)
                context.fill(Path(roundedRect: gauge, cornerRadius: 4), with: .color(.black.opacity(0.35)))
                context.fill(Path(roundedRect: CGRect(x: gauge.minX, y: gauge.minY, width: gauge.width * CGFloat(power), height: gauge.height), cornerRadius: 4),
                             with: .linearGradient(Gradient(colors: [Theme.go, Theme.gold, Theme.stop]),
                                                   startPoint: CGPoint(x: gauge.minX, y: 0), endPoint: CGPoint(x: gauge.maxX, y: 0)))
            }
        }
        .accessibilityLabel(L("Table de billard"))
    }

    static func ballColor(_ n: Int) -> Color {
        switch n % 8 {
        case 1: return Color(hex: 0xF7C531)
        case 2: return Color(hex: 0x2457D6)
        case 3: return Color(hex: 0xE5332A)
        case 4: return Color(hex: 0x6A2C91)
        case 5: return Color(hex: 0xF28A1E)
        case 6: return Color(hex: 0x1E8A4C)
        case 7: return Color(hex: 0x8B2B1E)
        default: return n == 8 ? Color(hex: 0x141414) : .white
        }
    }

    static func drawBall(_ context: inout GraphicsContext, number: Int, center c: CGPoint, radius r: CGFloat, spin: Double) {
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let striped = number >= 9
        let base = number == 0 ? Color(hex: 0xFBF7EC) : (striped ? Color(hex: 0xFBF7EC) : ballColor(number))
        context.fill(disc, with: .color(base))
        if striped {
            var band = context
            band.clip(to: disc)
            let wobble = CGFloat(sin(spin)) * r * 0.25
            band.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.52 + wobble, width: r * 2, height: r * 1.04)), with: .color(ballColor(number)))
        }
        if number != 0 {
            let off = CGPoint(x: CGFloat(cos(spin * 0.7)) * r * 0.22, y: CGFloat(sin(spin * 0.7)) * r * 0.22)
            let nc = CGPoint(x: c.x + off.x, y: c.y + off.y)
            let nr = r * 0.46
            context.fill(Path(ellipseIn: CGRect(x: nc.x - nr, y: nc.y - nr, width: nr * 2, height: nr * 2)), with: .color(Color(hex: 0xFBF7EC)))
            context.draw(Text("\(number)").font(.system(size: nr * 1.25, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0x141414)), at: nc)
        }
        // Volume : ombre et reflet
        context.fill(disc, with: .radialGradient(Gradient(colors: [.white.opacity(0.0), .black.opacity(0.32)]),
                                                 center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: r * 0.2, endRadius: r * 1.25))
        context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.68, width: r * 0.5, height: r * 0.34)), with: .color(.white.opacity(0.7)))
    }

    /// Où s'arrête la ligne de visée : première bille touchée (bille fantôme), ou bande.
    static func firstContact(world: BillardWorld, from p: BVec, dir: BVec) -> (point: BVec, ball: Int?) {
        let r = BillardWorld.radius
        var bestT = Double.infinity
        var bestBall: Int?
        for (i, b) in world.balls.enumerated() where i != 0 && !b.pocketed {
            // Intersection du trajet de la blanche avec un cercle de rayon 2r autour de la bille.
            let m = p - b.p
            let bq = m.dot(dir)
            let cq = m.dot(m) - 4 * r * r
            let disc = bq * bq - cq
            guard disc >= 0 else { continue }
            let t = -bq - disc.squareRoot()
            if t > 0 && t < bestT {
                bestT = t
                bestBall = i
            }
        }
        // Bandes
        var tWall = Double.infinity
        if dir.x > 0 { tWall = min(tWall, (1 - r - p.x) / dir.x) }
        if dir.x < 0 { tWall = min(tWall, (r - p.x) / dir.x) }
        if dir.y > 0 { tWall = min(tWall, (world.width - r - p.y) / dir.y) }
        if dir.y < 0 { tWall = min(tWall, (r - p.y) / dir.y) }
        if tWall < bestT {
            return (p + dir * max(0, tWall), nil)
        }
        return (p + dir * bestT, bestBall)
    }
}

/// Écran affiché quand un jeu à l'horizontale est tenu en portrait.
struct RotateToLandscapePrompt: View {
    let color: Color
    let text: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                IconButton(symbol: "chevron.left", label: L("Retour"), action: onBack)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            Spacer()
            Image(systemName: "rotate.right.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(color)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            Text(L("Tourne ton téléphone à l'horizontale"))
                .font(.plie(26))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
    }
}
