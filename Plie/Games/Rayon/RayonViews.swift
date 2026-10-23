import SwiftUI
import Combine

// MARK: - Choix du niveau

struct RayonLevelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: L("RAYON"),
                       subtitle: L("\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux réussis"),
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(DuoSupport.apisAvailable
                         ? L("Plie ton iPhone Duo pour faire tourner le miroir bleu, touche les miroirs ronds pour les faire pivoter. Garde le laser sur la cible pour valider.")
                         : L("Glisse ton doigt pour faire tourner le miroir bleu, touche les miroirs ronds pour les faire pivoter. Garde le laser sur la cible pour valider."))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)

                    ForEach(1...RayonLevel.worldCount, id: \.self) { world in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionTitle(text: L("Monde \(world) · \(RayonLevel.worldName(world))"))
                                if RayonLevel.all.contains(where: { $0.world == world && app.rayonNeedsPass($0.number, hasPass: store.ownsPass) }) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
                                ForEach(RayonLevel.all.filter { $0.world == world }, id: \.number) { level in
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
        let solved = app.rayonSolved.contains(number)
        let needsPass = app.rayonNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.rayonIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                app.route = .rayon(number)
            }
        } label: {
            ZStack {
                LevelTile(done: solved, accent: Theme.laser)
                if unlocked {
                    Text("\(number)")
                        .font(.plie(22))
                        .foregroundStyle(solved ? Theme.ink : .white)
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                }
            }
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Niveau \(number)\(solved ? L(", réussi") : "")\(unlocked ? "" : L(", verrouillé"))"))
    }
}

// MARK: - Partie

@Observable
final class RayonSession {
    let level: RayonLevel
    var t: Double
    var targetT: Double
    var hold: Double = 0
    var solved = false
    var elapsed: Double = 0
    var result: RayonEngine.Result
    var hingeDegrees: Double?
    /// Nombre de quarts de tour (45°) de chaque pivot depuis l'angle 0. Ne fait qu'augmenter.
    var rotorSteps: [Int]
    /// Angles affichés, qui rejoignent les angles réels en douceur.
    var rotorAngles: [Double]
    var taps = 0

    init(level: RayonLevel) {
        self.level = level
        self.t = level.startT
        self.targetT = level.startT
        self.rotorSteps = level.rotors.map(\.start)
        self.rotorAngles = level.startRotorAngles
        self.result = RayonEngine.trace(level, t: level.startT, rotorAngles: level.startRotorAngles)
    }

    func tapRotor(_ index: Int) {
        guard !solved, rotorSteps.indices.contains(index) else { return }
        rotorSteps[index] += 1
        taps += 1
        Haptics.tap()
        SoundPlayer.shared.play(.notch, volume: 0.7)
    }

    /// Pivot sous le doigt (coordonnées du plateau, de 0 à 1), s'il y en a un.
    func rotorIndex(at point: Pt) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, rotor) in level.rotors.enumerated() {
            let d = ((rotor.cx - point.x) * (rotor.cx - point.x) + (rotor.cy - point.y) * (rotor.cy - point.y)).squareRoot()
            if d <= max(rotor.length / 2 + 0.03, 0.09), best == nil || d < best!.distance {
                best = (index, d)
            }
        }
        return best?.index
    }

    /// Avance d'une image : le miroir suit la charnière en douceur, et on mesure le temps passé sur la cible.
    func tick(dt: Double) {
        guard !solved else { return }
        elapsed += dt
        let follow = min(1, dt * 16)
        let next = t + (targetT - t) * follow
        var changed = false
        if abs(next - t) > 0.00002 {
            t = next
            changed = true
        }
        for index in rotorAngles.indices {
            let goal = Double(rotorSteps[index]) * Rotor.stepDegrees
            let gap = goal - rotorAngles[index]
            if abs(gap) > 0.01 {
                rotorAngles[index] = abs(gap) < 0.6 ? goal : rotorAngles[index] + gap * min(1, dt * 18)
                changed = true
            }
        }
        if changed {
            let newResult = RayonEngine.trace(level, t: t, rotorAngles: rotorAngles)
            if newResult.hit && !result.hit {
                Haptics.tap()
                SoundPlayer.shared.play(.beam, volume: 0.6)
            }
            result = newResult
        }
        if result.hit {
            hold = min(1, hold + dt / 0.7)
            if hold >= 1 {
                solved = true
                Haptics.success()
                SoundPlayer.shared.play(.win)
            }
        } else {
            hold = max(0, hold - dt * 2.5)
        }
    }
}

struct RayonPlayView: View {
    let number: Int

    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var session: RayonSession
    @State private var dragStartT: Double?
    @State private var recorded = false
    @State private var hingeBaseline: Double?
    @State private var hingeActive = false
    @State private var touchedRotor: Int?
    @State private var touchDecided = false
    @State private var showTip = true

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(number: Int) {
        self.number = number
        let index = max(0, min(RayonLevel.all.count - 1, number - 1))
        _session = State(initialValue: RayonSession(level: RayonLevel.all[index]))
    }

    var body: some View {
        VStack(spacing: 12) {
            GameHeader(title: L("Niveau \(number)"),
                       subtitle: RayonLevel.worldName(session.level.world),
                       onBack: { app.route = .rayonLevels }) {
                Text(formatSeconds(session.elapsed))
                    .font(.plie(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }

            if showTip, let tip = session.level.tip {
                TipBanner(text: tip) { showTip = false }
            }

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                RayonBoard(session: session)
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let originX = (proxy.size.width - side) / 2
                                let originY = (proxy.size.height - side) / 2
                                if !touchDecided {
                                    touchDecided = true
                                    let start = Pt(Double((value.startLocation.x - originX) / side),
                                                   Double((value.startLocation.y - originY) / side))
                                    touchedRotor = session.rotorIndex(at: start)
                                }
                                // Un doigt posé sur un pivot sert à le tourner, pas à viser.
                                guard touchedRotor == nil else { return }
                                if dragStartT == nil { dragStartT = session.targetT }
                                let delta = Double(value.translation.width + value.translation.height * 0.35) / Double(side) * 0.9
                                session.targetT = min(1, max(0, (dragStartT ?? 0) + delta))
                            }
                            .onEnded { value in
                                if let rotor = touchedRotor,
                                   abs(value.translation.width) < 24, abs(value.translation.height) < 24 {
                                    session.tapRotor(rotor)
                                    showTip = false
                                }
                                touchedRotor = nil
                                touchDecided = false
                                dragStartT = nil
                            }
                    )
            }

            controlHint
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHingeAngle { degrees in
            session.hingeDegrees = degrees
            guard let degrees, HingeMapping.isOpen(degrees), dragStartT == nil else { return }
            // Le miroir ne suit la charnière qu'une fois qu'on a commencé à plier :
            // sinon la position de départ du téléphone pourrait résoudre le niveau toute seule.
            if !hingeActive {
                if let baseline = hingeBaseline {
                    if abs(degrees - baseline) > 4 { hingeActive = true }
                } else {
                    hingeBaseline = degrees
                }
            }
            if hingeActive {
                session.targetT = HingeMapping.fraction(fromDegrees: degrees)
            }
        }
        .onReceive(ticker) { _ in
            session.tick(dt: 1.0 / 60.0)
            if session.solved && !recorded {
                recorded = true
                app.recordRayon(number, time: session.elapsed)
            }
        }
        .overlay {
            if session.solved {
                successOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.solved)
        .animation(.easeOut(duration: 0.2), value: showTip)
    }

    private var controlHint: some View {
        HStack(spacing: 10) {
            Image(systemName: HingeMapping.isOpen(session.hingeDegrees) ? "rectangle.portrait.on.rectangle.portrait" : "hand.draw.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.laser)
            Text(hintText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            if let degrees = session.hingeDegrees, HingeMapping.isOpen(degrees) {
                Text("\(Int(degrees.rounded()))°")
                    .font(.plie(15, weight: .bold))
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(GlassPanel(cornerRadius: 16))
    }

    private var hintText: String {
        if HingeMapping.isOpen(session.hingeDegrees) {
            return L("Plie ou déplie ton iPhone Duo pour tourner le miroir")
        }
        if session.hingeDegrees != nil {
            return L("Ouvre ton iPhone Duo pour jouer avec la charnière, ou glisse ton doigt sur le plateau")
        }
        return L("Glisse ton doigt sur le plateau pour tourner le miroir")
    }

    private var nextNumber: Int? {
        number < RayonLevel.all.count ? number + 1 : nil
    }

    private var successOverlay: some View {
        ZStack {
            CelebrationBackdrop(accent: Theme.laser)
            VStack(spacing: 14) {
                WinIcon(systemName: "scope", color: Theme.laser)
                Text(L("Dans le mille !"))
                    .font(.plie(34))
                Text(session.level.rotors.isEmpty
                     ? L("Niveau \(number) en \(formatSeconds(session.elapsed))")
                     : L("Niveau \(number) en \(formatSeconds(session.elapsed)) · \(session.taps) tap\(session.taps > 1 ? "s" : "")"))
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if let next = nextNumber {
                    if app.rayonNeedsPass(next, hasPass: store.ownsPass) {
                        Text(L("La suite t'attend : \(RayonLevel.all.count - AppState.freeRayonLevels) niveaux de plus avec le Pass Origamo."))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.muted)
                        Button(L("Débloquer la suite")) { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button(L("Niveau suivant")) { app.route = .rayon(next) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.laser, textColor: Theme.ink))
                    }
                } else {
                    Text(L("Tu as fini tous les niveaux. Chapeau."))
                        .font(.plie(17, weight: .bold))
                }
                Button(L("Tous les niveaux")) { app.route = .rayonLevels }
                    .buttonStyle(GhostButtonStyle())
                ShareResultButton(game: L("RAYON"), result: L("Niveau \(number) en \(formatSeconds(session.elapsed))"), accent: Theme.laser)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 420)
            .winCard(accent: Theme.laser)
            .padding(24)
        }
    }
}

// MARK: - Dessin du plateau

struct RayonBoard: View {
    let session: RayonSession

    var body: some View {
        // Lues ici (et non dans Canvas) pour que SwiftUI redessine le plateau à chaque mouvement.
        let level = session.level
        let t = session.t
        let result = session.result
        let hold = session.hold
        let rotorAngles = session.rotorAngles
        let clock = session.elapsed
        let number = session.level.number

        Canvas { context, size in
            let side = min(size.width, size.height)

            func point(_ p: Pt) -> CGPoint {
                CGPoint(x: p.x * side, y: p.y * side)
            }

            func segmentPath(_ a: Pt, _ b: Pt) -> Path {
                var path = Path()
                path.move(to: point(a))
                path.addLine(to: point(b))
                return path
            }

            // Fond : ciel profond, nébuleuses et étoiles
            let boardRect = CGRect(x: 0, y: 0, width: side, height: side)
            let board = Path(roundedRect: boardRect, cornerRadius: side * 0.04)
            context.fill(board, with: .radialGradient(Gradient(colors: [Color(hex: 0x1E2150), Color(hex: 0x0C0E22)]),
                                                     center: CGPoint(x: side * 0.5, y: side * 0.45), startRadius: 0, endRadius: side * 0.75))
            context.drawLayer { layer in
                layer.clip(to: board)
                layer.addFilter(.blur(radius: side * 0.09))
                let nebula: [(Double, Double, Color)] = [(0.25, 0.3, Color(hex: 0x6A3DE8)), (0.78, 0.72, Color(hex: 0x1FA2C9)), (0.7, 0.2, Color(hex: 0xC93D8B))]
                for (i, n) in nebula.enumerated() {
                    let r = side * CGFloat(0.22 + 0.06 * Draw.hash(number, i))
                    let c = CGPoint(x: side * CGFloat(n.0), y: side * CGFloat(n.1))
                    layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(n.2.opacity(0.22)))
                }
            }
            for i in 0..<70 {
                let x = Draw.hash(i, number) * Double(side)
                let y = Draw.hash(i, number + 7) * Double(side)
                let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(clock * (1 + Draw.hash(i, 3) * 2) + Double(i)))
                let r = CGFloat(0.6 + Draw.hash(i, 11) * 1.4)
                context.fill(Path(ellipseIn: CGRect(x: CGFloat(x) - r, y: CGFloat(y) - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.55 * twinkle)))
            }
            var grid = Path()
            for i in 1..<10 {
                let v = side * CGFloat(i) / 10
                grid.move(to: CGPoint(x: v, y: 0)); grid.addLine(to: CGPoint(x: v, y: side))
                grid.move(to: CGPoint(x: 0, y: v)); grid.addLine(to: CGPoint(x: side, y: v))
            }
            context.stroke(grid, with: .color(.white.opacity(0.025)), lineWidth: 1)
            context.stroke(board, with: .linearGradient(Gradient(colors: [Theme.laser.opacity(0.5), Theme.paint.opacity(0.3)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: side, y: side)), lineWidth: 2)

            // Pliure (là où se trouve la charnière)
            var fold = Path()
            fold.move(to: CGPoint(x: side / 2, y: side * 0.02))
            fold.addLine(to: CGPoint(x: side / 2, y: side * 0.98))
            context.stroke(fold, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

            // Murs : blocs de pierre avec un liseré
            for w in level.walls {
                let (a, b) = RayonEngine.endpoints(cx: w.cx, cy: w.cy, length: w.length, angle: w.angle)
                context.stroke(segmentPath(a, b), with: .color(.black.opacity(0.35)),
                               style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
                context.stroke(segmentPath(a, b), with: .linearGradient(Gradient(colors: [Color(hex: 0x5C6390), Color(hex: 0x3A3F63)]),
                                                                       startPoint: point(a), endPoint: point(b)),
                               style: StrokeStyle(lineWidth: side * 0.024, lineCap: .round))
                context.stroke(segmentPath(a, b), with: .color(.white.opacity(0.18)),
                               style: StrokeStyle(lineWidth: side * 0.004, lineCap: .round))
            }

            // Miroirs fixes : argent poli
            for m in level.mirrors {
                let (a, b) = RayonEngine.endpoints(cx: m.cx, cy: m.cy, length: m.length, angle: m.angle)
                context.stroke(segmentPath(a, b), with: .linearGradient(Gradient(colors: [Color(hex: 0x9FA8C7), .white, Color(hex: 0xB9C2DD), .white]),
                                                                       startPoint: point(a), endPoint: point(b)),
                               style: StrokeStyle(lineWidth: side * 0.013, lineCap: .round))
            }

            // Miroirs pilotés par la charnière
            for c in level.controls {
                let (a, b) = RayonEngine.endpoints(cx: c.cx, cy: c.cy, length: c.length, angle: level.controlAngle(c, t: t))
                let center = point(Pt(c.cx, c.cy))
                let ring = Path(ellipseIn: CGRect(x: center.x - c.length * side / 2, y: center.y - c.length * side / 2,
                                                  width: c.length * side, height: c.length * side))
                context.stroke(ring, with: .color(Theme.laser.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: side * 0.01))
                    layer.stroke(segmentPath(a, b), with: .color(Theme.laser.opacity(0.7)),
                                 style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
                }
                context.stroke(segmentPath(a, b), with: .linearGradient(Gradient(colors: [Theme.laser, .white, Theme.laser]),
                                                                       startPoint: point(a), endPoint: point(b)),
                               style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                             with: .color(.white))
            }

            // Pivots : un disque qu'on touche, un miroir qui tourne de 45°
            for (index, r) in level.rotors.enumerated() {
                let angle = index < rotorAngles.count ? rotorAngles[index] : 0
                let center = point(Pt(r.cx, r.cy))
                let radius = r.length * side / 2 + side * 0.012
                let disk = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(disk, with: .radialGradient(Gradient(colors: [Color(hex: 0x3A4170), Color(hex: 0x1D2140)]),
                                                        center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.35),
                                                        startRadius: 0, endRadius: radius * 1.4))
                context.stroke(disk, with: .color(Theme.gold.opacity(0.55)), lineWidth: max(1.5, side * 0.004))
                // 4 repères : les orientations possibles
                for k in 0..<8 {
                    let a = Double(k) * 45 * .pi / 180
                    let inner = CGPoint(x: center.x + cos(a) * radius * 0.84, y: center.y + sin(a) * radius * 0.84)
                    let outer = CGPoint(x: center.x + cos(a) * radius * 0.96, y: center.y + sin(a) * radius * 0.96)
                    var tick = Path()
                    tick.move(to: inner)
                    tick.addLine(to: outer)
                    context.stroke(tick, with: .color(.white.opacity(0.28)), lineWidth: 1)
                }
                let (a, b) = RayonEngine.endpoints(cx: r.cx, cy: r.cy, length: r.length, angle: angle)
                context.stroke(segmentPath(a, b), with: .color(Color(hex: 0xF4F1FF)),
                               style: StrokeStyle(lineWidth: side * 0.013, lineCap: .round))
                let pin = side * 0.011
                context.fill(Path(ellipseIn: CGRect(x: center.x - pin, y: center.y - pin, width: pin * 2, height: pin * 2)),
                             with: .color(Theme.gold))
                // Petite flèche : « touche-moi pour tourner »
                var badge = context.resolve(Image(systemName: "arrow.clockwise"))
                badge.shading = .color(Theme.gold)
                let badgeSize = side * 0.03
                context.draw(badge, in: CGRect(x: center.x + radius * 0.62 - badgeSize / 2,
                                               y: center.y + radius * 0.62 - badgeSize / 2,
                                               width: badgeSize, height: badgeSize))
            }

            // Cible (anneaux qui pulsent)
            let target = point(level.target)
            let r = level.targetRadius * side
            let pulse = CGFloat(0.5 + 0.5 * sin(clock * 3))
            for k in 0..<2 {
                let rr = r * (1.25 + 0.35 * CGFloat(k) + 0.15 * pulse)
                context.stroke(Path(ellipseIn: CGRect(x: target.x - rr, y: target.y - rr, width: rr * 2, height: rr * 2)),
                               with: .color(Theme.gold.opacity(0.18 - 0.07 * Double(k))), lineWidth: 1.5)
            }
            if result.hit {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: r * 0.8))
                    layer.fill(Path(ellipseIn: CGRect(x: target.x - r * 1.4, y: target.y - r * 1.4, width: r * 2.8, height: r * 2.8)),
                               with: .color(Theme.gold.opacity(0.55)))
                }
            }
            let targetRect = CGRect(x: target.x - r, y: target.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: targetRect), with: .color(Theme.gold), lineWidth: max(2, side * 0.008))
            let innerR = r * 0.45
            context.fill(Path(ellipseIn: CGRect(x: target.x - innerR, y: target.y - innerR, width: innerR * 2, height: innerR * 2)),
                         with: .color(Theme.gold.opacity(0.35)))
            if hold > 0 {
                var arc = Path()
                arc.addArc(center: target, radius: r + side * 0.012,
                           startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * hold), clockwise: false)
                context.stroke(arc, with: .color(Theme.gold), style: StrokeStyle(lineWidth: side * 0.01, lineCap: .round))
            }

            // Rayon laser
            let points = result.points.map(point)
            if points.count > 1 {
                var beam = Path()
                beam.move(to: points[0])
                for p in points.dropFirst() { beam.addLine(to: p) }
                let color = result.hit ? Theme.gold : Color(hex: 0xFF3B5C)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: side * 0.012))
                    layer.stroke(beam, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round, lineJoin: .round))
                }
                context.stroke(beam, with: .color(color), style: StrokeStyle(lineWidth: side * 0.007, lineCap: .round, lineJoin: .round))
                context.stroke(beam, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: side * 0.0025, lineCap: .round, lineJoin: .round))
            }

            // Émetteur
            let e = point(level.emitter)
            let er = side * 0.026
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: er * 0.7))
                let g = er * (1.6 + 0.25 * pulse)
                layer.fill(Path(ellipseIn: CGRect(x: e.x - g, y: e.y - g, width: g * 2, height: g * 2)), with: .color(Theme.coral.opacity(0.6)))
            }
            var core = context
            Draw.shadedBall(&core, center: e, radius: er, color: Theme.coral)
            context.stroke(Path(ellipseIn: CGRect(x: e.x - er, y: e.y - er, width: er * 2, height: er * 2)), with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
        .accessibilityLabel(result.hit ? L("Plateau de jeu : le laser touche la cible") : L("Plateau de jeu : le laser ne touche pas la cible"))
    }
}
