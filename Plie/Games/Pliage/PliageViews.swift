import SwiftUI
import Combine

// MARK: - Choix du niveau

struct PliageLevelsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: "PLIAGE",
                       subtitle: "\(app.pliageSolved.count) / \(PliageLevel.all.count) pliages réussis",
                       onBack: { app.route = .hub }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(DuoSupport.apisAvailable
                         ? "La peinture est fraîche : plie la feuille (ou ton iPhone Duo) et elle se décalque de l'autre côté. Reproduis le modèle avec le nombre de plis indiqué."
                         : "La peinture est fraîche : plie la feuille et elle se décalque de l'autre côté. Reproduis le modèle avec le nombre de plis indiqué.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)

                    ForEach(1...PliageLevel.worldCount, id: \.self) { world in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionTitle(text: "Monde \(world) · \(PliageLevel.worldName(world))")
                                if PliageLevel.all.contains(where: { $0.world == world && app.pliageNeedsPass($0.number, hasPass: store.ownsPass) }) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 10)], spacing: 10) {
                                ForEach(PliageLevel.all.filter { $0.world == world }, id: \.number) { level in
                                    levelButton(level)
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

    private func levelButton(_ level: PliageLevel) -> some View {
        let number = level.number
        let solved = app.pliageSolved.contains(number)
        let needsPass = app.pliageNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.pliageIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                app.route = .pliage(number)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(solved ? Theme.paint : Theme.card)
                if unlocked {
                    VStack(spacing: 1) {
                        Text("\(number)")
                            .font(.plie(22))
                        Text("\(level.par) pli\(level.par > 1 ? "s" : "")")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .opacity(0.75)
                    }
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
        .accessibilityLabel("Pliage \(number), \(level.par) plis\(solved ? ", réussi" : "")\(unlocked ? "" : ", verrouillé")")
    }
}

// MARK: - Partie

struct PliagePlayView: View {
    let number: Int

    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var session: PliageSession
    @State private var recorded = false
    @State private var showTip = true

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    init(number: Int) {
        self.number = number
        let index = max(0, min(PliageLevel.all.count - 1, number - 1))
        _session = State(initialValue: PliageSession(level: PliageLevel.all[index]))
    }

    var body: some View {
        VStack(spacing: 12) {
            GameHeader(title: "Pliage n° \(number)",
                       subtitle: PliageLevel.worldName(session.level.world),
                       onBack: { app.route = .pliageLevels }) {
                FoldCounter(used: session.foldsUsed, par: session.level.par)
            }

            if showTip, let tip = session.level.tip {
                TipBanner(text: tip) { showTip = false }
            }

            GeometryReader { proxy in
                let wide = proxy.size.width > proxy.size.height * 1.15
                if wide {
                    HStack(spacing: 16) {
                        ModelPanel(level: session.level)
                            .frame(width: min(proxy.size.width * 0.32, 300))
                        board
                    }
                } else {
                    VStack(spacing: 12) {
                        ModelPanel(level: session.level, compact: true)
                            .frame(height: min(proxy.size.height * 0.36, 210))
                        board
                    }
                }
            }

            statusLine

            HStack(spacing: 10) {
                Button {
                    session.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                }
                .accessibilityLabel("Annuler le dernier pli")
                .disabled(session.foldsUsed == 0 || session.isAnimating)
                .opacity(session.foldsUsed == 0 ? 0.4 : 1)

                Button {
                    session.performFold()
                } label: {
                    Label("Plier", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.paint, height: 58))
                .disabled(!session.canFold)
                .opacity(session.canFold ? 1 : 0.45)

                Button {
                    session.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                }
                .accessibilityLabel("Recommencer le pliage")
                .disabled(session.foldsUsed == 0 || session.isAnimating)
                .opacity(session.foldsUsed == 0 ? 0.4 : 1)
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHingeAngle { degrees in
            session.hingeChanged(degrees)
        }
        .onAppear {
            #if DEBUG
            let demo = UserDefaults.standard.double(forKey: "pliageDemo")
            if demo > 0 {
                showTip = false
                session.debugFreeze(progress: demo, stampedAlready: UserDefaults.standard.bool(forKey: "pliageDemoStamped"))
            }
            #endif
        }
        .onReceive(ticker) { _ in
            session.tick(dt: 1.0 / 60.0)
            if session.solved && !recorded {
                recorded = true
                app.recordPliage(number, time: session.elapsed)
            }
        }
        .overlay {
            if session.solved && !session.isAnimating {
                successOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.solved)
        .animation(.easeOut(duration: 0.2), value: showTip)
        .onChange(of: session.foldsUsed) { _, _ in showTip = false }
    }

    private var board: some View {
        PliageBoard(session: session)
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 10) {
            Image(systemName: session.outOfFolds ? "exclamationmark.circle.fill" :
                    (session.selected == nil ? "hand.tap.fill" : (session.hingeReady ? "rectangle.portrait.on.rectangle.portrait" : "checkmark.circle.fill")))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(session.outOfFolds ? Theme.coral : Theme.paint)
            Text(statusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(session.outOfFolds ? Theme.coral : Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private var statusText: String {
        if session.outOfFolds && !session.solved {
            return "Tous les plis sont utilisés. Annule un pli pour essayer autrement."
        }
        if session.selected == nil {
            return "Touche une ligne pointillée pour choisir où plier."
        }
        if session.hingeReady {
            return "Plie ton iPhone Duo pour plier la feuille, ou touche « Plier »."
        }
        return "Touche « Plier », ou touche à nouveau la ligne."
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.paint)
                Text("Pliage réussi !")
                    .font(.plie(34))
                Text("En \(session.foldsUsed) pli\(session.foldsUsed > 1 ? "s" : "") · \(formatSeconds(session.elapsed))")
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                if number < PliageLevel.all.count {
                    if app.pliageNeedsPass(number + 1, hasPass: store.ownsPass) {
                        Text("\(PliageLevel.all.count - AppState.freePliageLevels) pliages de plus, avec les mélanges de couleurs, dans le Pass Plié.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Débloquer la suite") { app.showPass = true }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink))
                    } else {
                        Button("Pliage suivant") { app.route = .pliage(number + 1) }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.paint))
                    }
                } else {
                    Text("Tu as réussi tous les pliages. Maître origami !")
                        .font(.plie(17, weight: .bold))
                        .multilineTextAlignment(.center)
                }
                Button("Tous les pliages") { app.route = .pliageLevels }
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

// MARK: - Éléments

struct FoldCounter: View {
    let used: Int
    let par: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<par, id: \.self) { index in
                Capsule()
                    .fill(index < used ? Theme.paint : Theme.faint)
                    .frame(width: 14, height: 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Capsule().fill(Theme.card))
        .accessibilityLabel("\(used) pli\(used > 1 ? "s" : "") sur \(par)")
    }
}

struct ModelPanel: View {
    let level: PliageLevel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Modèle · \(level.par) pli\(level.par > 1 ? "s" : "")")
            }
            HStack(alignment: .center, spacing: 12) {
                PaintGrid(grid: level.target, width: level.width, height: level.height)
                    .aspectRatio(CGFloat(level.width) / CGFloat(level.height), contentMode: .fit)
                if level.world >= 2 {
                    MixLegend(world: level.world)
                        .frame(maxWidth: compact ? CGFloat(150) : CGFloat.infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
    }
}

struct MixLegend: View {
    let world: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mix(1, 2, 3)
            mix(2, 4, 6)
            mix(1, 4, 5)
            if world >= 3 {
                mix(3, 4, 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mélanges : rouge et jaune donnent orange, jaune et bleu donnent vert, rouge et bleu donnent violet")
    }

    private func mix(_ a: UInt8, _ b: UInt8, _ result: UInt8) -> some View {
        HStack(spacing: 4) {
            dot(a)
            Text("+").font(.system(size: 11, weight: .bold))
            dot(b)
            Text("=").font(.system(size: 11, weight: .bold))
            dot(result)
        }
        .foregroundStyle(Theme.muted)
    }

    private func dot(_ value: UInt8) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(PliageEngine.color(value))
            .frame(width: 16, height: 16)
    }
}

/// Grille peinte, sans interaction (modèle).
struct PaintGrid: View {
    let grid: [UInt8]
    let width: Int
    let height: Int

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(width), size.height / CGFloat(height))
            let origin = CGPoint(x: (size.width - cell * CGFloat(width)) / 2, y: (size.height - cell * CGFloat(height)) / 2)
            let sheet = CGRect(x: origin.x, y: origin.y, width: cell * CGFloat(width), height: cell * CGFloat(height))
            context.fill(Path(roundedRect: sheet, cornerRadius: cell * 0.12), with: .color(PliageEngine.paper))
            for r in 0..<height {
                for c in 0..<width {
                    let value = grid[r * width + c]
                    guard value != 0 else { continue }
                    let rect = CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell, height: cell)
                        .insetBy(dx: cell * 0.08, dy: cell * 0.08)
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.2), with: .color(PliageEngine.color(value)))
                }
            }
        }
    }
}

// MARK: - Feuille de jeu

struct PliageBoard: View {
    let session: PliageSession

    var body: some View {
        // Lu ici pour que SwiftUI redessine à chaque image de l'animation.
        let level = session.level
        let grid = session.grid
        let selected = session.selected
        let active = session.active
        let progress = session.progress

        GeometryReader { proxy in
            let w = level.width
            let h = level.height
            let cell = min(proxy.size.width / CGFloat(w), proxy.size.height / CGFloat(h))
            let sheetW = cell * CGFloat(w)
            let sheetH = cell * CGFloat(h)
            let origin = CGPoint(x: (proxy.size.width - sheetW) / 2, y: (proxy.size.height - sheetH) / 2)
            let lifted = active.map { PliageEngine.flap(for: $0, width: w, height: h) }
            let highlight = (active ?? selected).map { PliageEngine.flap(for: $0, width: w, height: h) }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let sheet = CGRect(x: origin.x, y: origin.y, width: sheetW, height: sheetH)
                    context.fill(Path(roundedRect: sheet.insetBy(dx: -4, dy: -4).offsetBy(dx: 0, dy: 6), cornerRadius: 10),
                                 with: .color(.black.opacity(0.35)))

                    for r in 0..<h {
                        for c in 0..<w {
                            if let fold = active, let lifted, progress > 0, PliageBoard.isInFlap(r: r, c: c, fold: fold, flap: lifted) {
                                continue
                            }
                            let rect = CGRect(x: origin.x + CGFloat(c) * cell, y: origin.y + CGFloat(r) * cell, width: cell, height: cell)
                            context.fill(Path(rect), with: .color(PliageEngine.paper))
                            let value = grid[r * w + c]
                            if value != 0 {
                                context.fill(Path(roundedRect: rect.insetBy(dx: cell * 0.08, dy: cell * 0.08), cornerRadius: cell * 0.2),
                                             with: .color(PliageEngine.color(value)))
                            }
                        }
                    }

                    // Côté qui va se soulever
                    if let fold = selected ?? active, let highlight, progress == 0 {
                        let rect = PliageBoard.flapRect(fold: fold, flap: highlight, origin: origin, cell: cell, w: w, h: h)
                        context.fill(Path(rect), with: .color(Theme.paint.opacity(0.10)))
                    }

                    // Lignes de pli
                    for fold in level.allFolds {
                        var line = Path()
                        if fold.axis == .vertical {
                            let x = origin.x + CGFloat(fold.index) * cell
                            line.move(to: CGPoint(x: x, y: origin.y))
                            line.addLine(to: CGPoint(x: x, y: origin.y + sheetH))
                        } else {
                            let y = origin.y + CGFloat(fold.index) * cell
                            line.move(to: CGPoint(x: origin.x, y: y))
                            line.addLine(to: CGPoint(x: origin.x + sheetW, y: y))
                        }
                        if fold == selected || fold == active {
                            context.stroke(line, with: .color(Theme.paint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        } else {
                            context.stroke(line, with: .color(PliageEngine.paperLine), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                        }
                    }
                }
                .allowsHitTesting(false)

                // Rabat en mouvement
                if let fold = active, let lifted, progress > 0 {
                    let rect = PliageBoard.flapRect(fold: fold, flap: lifted, origin: origin, cell: cell, w: w, h: h)
                    let angle = Double.pi * progress
                    let scale = CGFloat(cos(angle))
                    let anchor = PliageBoard.hingeAnchor(fold: fold, leading: lifted.isLeadingSide)
                    FlapView(grid: grid, level: level, fold: fold, flap: lifted, showFront: scale >= 0, cell: cell)
                        .frame(width: rect.width, height: rect.height)
                        .overlay(Color.black.opacity(0.22 * sin(angle)))
                        .shadow(color: .black.opacity(0.35 * sin(angle)), radius: 10 * sin(angle))
                        .scaleEffect(x: fold.axis == .vertical ? scale : 1,
                                     y: fold.axis == .horizontal ? scale : 1,
                                     anchor: anchor)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                // Zones à toucher le long des lignes
                ForEach(level.allFolds, id: \.self) { fold in
                    let thickness = min(40, max(26, cell * 0.55))
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: fold.axis == .vertical ? thickness : sheetW,
                               height: fold.axis == .vertical ? sheetH : thickness)
                        .position(x: fold.axis == .vertical ? origin.x + CGFloat(fold.index) * cell : origin.x + sheetW / 2,
                                  y: fold.axis == .vertical ? origin.y + sheetH / 2 : origin.y + CGFloat(fold.index) * cell)
                        .onTapGesture { session.tapLine(fold) }
                        .accessibilityElement()
                        .accessibilityLabel(fold.axis == .vertical ? "Pli vertical \(fold.index)" : "Pli horizontal \(fold.index)")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    static func isInFlap(r: Int, c: Int, fold: PliageFold, flap: (range: Range<Int>, isLeadingSide: Bool)) -> Bool {
        fold.axis == .vertical ? flap.range.contains(c) : flap.range.contains(r)
    }

    static func flapRect(fold: PliageFold, flap: (range: Range<Int>, isLeadingSide: Bool),
                         origin: CGPoint, cell: CGFloat, w: Int, h: Int) -> CGRect {
        if fold.axis == .vertical {
            return CGRect(x: origin.x + CGFloat(flap.range.lowerBound) * cell, y: origin.y,
                          width: CGFloat(flap.range.count) * cell, height: CGFloat(h) * cell)
        }
        return CGRect(x: origin.x, y: origin.y + CGFloat(flap.range.lowerBound) * cell,
                      width: CGFloat(w) * cell, height: CGFloat(flap.range.count) * cell)
    }

    /// Le bord du rabat qui touche la ligne de pli.
    static func hingeAnchor(fold: PliageFold, leading: Bool) -> UnitPoint {
        switch (fold.axis, leading) {
        case (.vertical, true): return .trailing
        case (.vertical, false): return .leading
        case (.horizontal, true): return .bottom
        case (.horizontal, false): return .top
        }
    }
}

/// Le morceau de feuille qui se soulève : peinture visible côté face, papier nu côté dos.
struct FlapView: View {
    let grid: [UInt8]
    let level: PliageLevel
    let fold: PliageFold
    let flap: (range: Range<Int>, isLeadingSide: Bool)
    let showFront: Bool
    let cell: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(showFront ? PliageEngine.paper : PliageEngine.paperBack))
            guard showFront else {
                // Dos du papier : quelques fibres
                var fibers = Path()
                var y: CGFloat = 6
                while y < size.height {
                    fibers.move(to: CGPoint(x: 0, y: y))
                    fibers.addLine(to: CGPoint(x: size.width, y: y + 4))
                    y += 11
                }
                context.stroke(fibers, with: .color(PliageEngine.paperLine.opacity(0.5)), lineWidth: 1)
                return
            }
            let w = level.width
            let rows = fold.axis == .horizontal ? Array(flap.range) : Array(0..<level.height)
            let cols = fold.axis == .vertical ? Array(flap.range) : Array(0..<w)
            for (ri, r) in rows.enumerated() {
                for (ci, c) in cols.enumerated() {
                    let value = grid[r * w + c]
                    guard value != 0 else { continue }
                    let rect = CGRect(x: CGFloat(ci) * cell, y: CGFloat(ri) * cell, width: cell, height: cell)
                        .insetBy(dx: cell * 0.08, dy: cell * 0.08)
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.2), with: .color(PliageEngine.color(value)))
                }
            }
        }
    }
}
