import SwiftUI
import Combine

// MARK: - Choix du niveau

struct RayonLevelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: "RAYON",
                       subtitle: "\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux réussis",
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(DuoSupport.apisAvailable
                         ? "Plie ton iPhone Duo pour faire tourner le miroir bleu. Garde le laser sur la cible pour valider."
                         : "Glisse ton doigt pour faire tourner le miroir bleu. Garde le laser sur la cible pour valider.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)

                    ForEach(1...3, id: \.self) { world in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionTitle(text: "Monde \(world) · \(RayonLevel.worldName(world))")
                                if world > 1 && !store.ownsPass {
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(solved ? Theme.laser : Theme.card)
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
        .accessibilityLabel("Niveau \(number)\(solved ? ", réussi" : "")\(unlocked ? "" : ", verrouillé")")
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

    init(level: RayonLevel) {
        self.level = level
        self.t = level.startT
        self.targetT = level.startT
        self.result = RayonEngine.trace(level, t: level.startT)
    }

    /// Avance d'une image : le miroir suit la charnière en douceur, et on mesure le temps passé sur la cible.
    func tick(dt: Double) {
        guard !solved else { return }
        elapsed += dt
        let follow = min(1, dt * 16)
        let next = t + (targetT - t) * follow
        if abs(next - t) > 0.00002 {
            t = next
            let newResult = RayonEngine.trace(level, t: t)
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

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(number: Int) {
        self.number = number
        let index = max(0, min(RayonLevel.all.count - 1, number - 1))
        _session = State(initialValue: RayonSession(level: RayonLevel.all[index]))
    }

    var body: some View {
        VStack(spacing: 12) {
            GameHeader(title: "Niveau \(number)",
                       subtitle: RayonLevel.worldName(session.level.world),
                       onBack: { app.route = .rayonLevels }) {
                Text(formatSeconds(session.elapsed))
                    .font(.plie(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
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
                                if dragStartT == nil { dragStartT = session.targetT }
                                let delta = Double(value.translation.width + value.translation.height * 0.35) / Double(side) * 0.9
                                session.targetT = min(1, max(0, (dragStartT ?? 0) + delta))
                            }
                            .onEnded { _ in dragStartT = nil }
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private var hintText: String {
        if HingeMapping.isOpen(session.hingeDegrees) {
            return "Plie ou déplie ton iPhone Duo pour tourner le miroir"
        }
        if session.hingeDegrees != nil {
            return "Ouvre ton iPhone Duo pour jouer avec la charnière, ou glisse ton doigt sur le plateau"
        }
        return "Glisse ton doigt sur le plateau pour tourner le miroir"
    }

    private var nextNumber: Int? {
        number < RayonLevel.all.count ? number + 1 : nil
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.laser)
                Text("Dans le mille !")
                    .font(.plie(34))
                Text("Niveau \(number) en \(formatSeconds(session.elapsed))")
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if let next = nextNumber {
                    if app.rayonNeedsPass(next, hasPass: store.ownsPass) {
                        Text("Le monde 2 t'attend : 30 niveaux de plus avec le Pass Plié.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.muted)
                        Button("Débloquer la suite") { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button("Niveau suivant") { app.route = .rayon(next) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.laser, textColor: Theme.ink))
                    }
                } else {
                    Text("Tu as fini tous les niveaux. Chapeau.")
                        .font(.plie(17, weight: .bold))
                }
                Button("Tous les niveaux") { app.route = .rayonLevels }
                    .buttonStyle(GhostButtonStyle())
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.ink))
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

            // Fond et quadrillage
            let board = Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.04)
            context.fill(board, with: .color(Color(hex: 0x13162B)))
            var grid = Path()
            for i in 1..<10 {
                let v = side * CGFloat(i) / 10
                grid.move(to: CGPoint(x: v, y: 0)); grid.addLine(to: CGPoint(x: v, y: side))
                grid.move(to: CGPoint(x: 0, y: v)); grid.addLine(to: CGPoint(x: side, y: v))
            }
            context.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 1)

            // Pliure (là où se trouve la charnière)
            var fold = Path()
            fold.move(to: CGPoint(x: side / 2, y: side * 0.02))
            fold.addLine(to: CGPoint(x: side / 2, y: side * 0.98))
            context.stroke(fold, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

            // Murs
            for w in level.walls {
                let (a, b) = RayonEngine.endpoints(cx: w.cx, cy: w.cy, length: w.length, angle: w.angle)
                context.stroke(segmentPath(a, b), with: .color(Color(hex: 0x4A4F6E)),
                               style: StrokeStyle(lineWidth: side * 0.024, lineCap: .round))
            }

            // Miroirs fixes
            for m in level.mirrors {
                let (a, b) = RayonEngine.endpoints(cx: m.cx, cy: m.cy, length: m.length, angle: m.angle)
                context.stroke(segmentPath(a, b), with: .color(Color(hex: 0xDDE3F5)),
                               style: StrokeStyle(lineWidth: side * 0.012, lineCap: .round))
            }

            // Miroirs pilotés par la charnière
            for c in level.controls {
                let (a, b) = RayonEngine.endpoints(cx: c.cx, cy: c.cy, length: c.length, angle: level.controlAngle(c, t: t))
                let center = point(Pt(c.cx, c.cy))
                let ring = Path(ellipseIn: CGRect(x: center.x - c.length * side / 2, y: center.y - c.length * side / 2,
                                                  width: c.length * side, height: c.length * side))
                context.stroke(ring, with: .color(Theme.laser.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                context.stroke(segmentPath(a, b), with: .color(Theme.laser),
                               style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                             with: .color(.white))
            }

            // Cible
            let target = point(level.target)
            let r = level.targetRadius * side
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
            context.fill(Path(ellipseIn: CGRect(x: e.x - er, y: e.y - er, width: er * 2, height: er * 2)), with: .color(Theme.coral))
            context.stroke(Path(ellipseIn: CGRect(x: e.x - er, y: e.y - er, width: er * 2, height: er * 2)), with: .color(.white), lineWidth: 2)
        }
        .accessibilityLabel("Plateau de jeu : le laser \(result.hit ? "touche" : "ne touche pas") la cible")
    }
}
