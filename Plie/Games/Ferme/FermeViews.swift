import SwiftUI
import Combine

extension Theme {
    static let ferme = Color(hex: 0x5FD3A0)
}

// MARK: - Plantes

struct FermePlant: Identifiable, Hashable {
    let id: String
    let name: String
    let stem: UInt32
    let flower: UInt32
    let leafCount: Int
    let free: Bool
    let shape: Form

    enum Form: Hashable {
        case flower, cactus, tree, tulip
    }

    var stemColor: Color { Color(hex: stem) }
    var displayName: String { L(key: name) }
    var flowerColor: Color { Color(hex: flower) }

    static let all: [FermePlant] = [
        FermePlant(id: "pousse", name: "Pousse", stem: 0x5BBF6A, flower: 0xFFD447, leafCount: 2, free: true, shape: .flower),
        FermePlant(id: "tournesol", name: "Tournesol", stem: 0x4FA65C, flower: 0xFFC233, leafCount: 4, free: true, shape: .flower),
        FermePlant(id: "cactus", name: "Cactus", stem: 0x3E9B6B, flower: 0xFF6FA8, leafCount: 2, free: true, shape: .cactus),
        FermePlant(id: "tulipe", name: "Tulipe", stem: 0x58B060, flower: 0xFF4F6A, leafCount: 2, free: false, shape: .tulip),
        FermePlant(id: "lavande", name: "Lavande", stem: 0x6A9F6E, flower: 0x9B7BEA, leafCount: 3, free: false, shape: .flower),
        FermePlant(id: "bonsai", name: "Bonsaï", stem: 0x8A5A3C, flower: 0x4FB86A, leafCount: 3, free: false, shape: .tree),
        FermePlant(id: "cerisier", name: "Cerisier", stem: 0x7A4E3A, flower: 0xFFB3CF, leafCount: 3, free: false, shape: .tree),
        FermePlant(id: "rose", name: "Rose", stem: 0x4C9A58, flower: 0xE23B5A, leafCount: 4, free: false, shape: .tulip)
    ]

    static func named(_ id: String) -> FermePlant {
        all.first { $0.id == id } ?? all[0]
    }
}

struct FermeRecord: Codable, Hashable {
    let plant: String
    let minutes: Int
    let date: Date
}

// MARK: - Séance

@Observable
final class FermeSession {
    enum Phase: Equatable {
        case setup
        case armed
        case running
        case reopened
        case done
        case wilted
    }

    var phase: Phase = .setup
    var minutes = 25
    var plantID = "pousse"
    private(set) var endDate: Date?
    private(set) var startDate: Date?
    private(set) var reopenDeadline: Date?
    private(set) var now = Date()
    private(set) var hingeAvailable = false
    private(set) var isClosed = false

    @ObservationIgnored private var backgroundSince: Date?
    static let grace = 10.0

    var total: Double { Double(minutes) * 60 }

    var remaining: Double {
        guard let endDate else { return total }
        return max(0, endDate.timeIntervalSince(now))
    }

    var growth: Double {
        switch phase {
        case .running, .reopened: return min(1, 1 - remaining / total)
        case .done: return 1
        case .wilted:
            guard let startDate, let endDate else { return 0.3 }
            return min(1, now.timeIntervalSince(startDate) / endDate.timeIntervalSince(startDate))
        default: return 0.04
        }
    }

    var reopenLeft: Double {
        guard let reopenDeadline else { return 0 }
        return max(0, reopenDeadline.timeIntervalSince(now))
    }

    // MARK: Actions

    func plant() {
        if hingeAvailable {
            phase = isClosed ? .running : .armed
            if phase == .running { begin() }
        } else {
            begin()
            phase = .running
        }
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.tap()
    }

    private func begin() {
        startDate = Date()
        endDate = Date().addingTimeInterval(total)
        SoundPlayer.shared.play(.go, volume: 0.6)
    }

    func giveUp() {
        guard phase == .running || phase == .reopened || phase == .armed else { return }
        if phase == .armed {
            backToSetup()
            return
        }
        wilt()
    }

    func backToSetup() {
        phase = .setup
        endDate = nil
        startDate = nil
        reopenDeadline = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func wilt() {
        phase = .wilted
        reopenDeadline = nil
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.error()
        SoundPlayer.shared.play(.wrong, volume: 0.7)
    }

    // MARK: Temps, charnière, arrière-plan

    /// Renvoie vrai quand la séance vient de se terminer.
    func tick() -> Bool {
        now = Date()
        switch phase {
        case .running:
            if remaining <= 0 {
                phase = .done
                UIApplication.shared.isIdleTimerDisabled = false
                Haptics.success()
                SoundPlayer.shared.play(.bloom)
                return true
            }
        case .reopened:
            if remaining <= 0 {
                // Le temps est écoulé pendant la tolérance : la plante a quand même poussé.
                phase = .done
                UIApplication.shared.isIdleTimerDisabled = false
                Haptics.success()
                SoundPlayer.shared.play(.bloom)
                return true
            }
            if reopenLeft <= 0 { wilt() }
        default:
            break
        }
        return false
    }

    func hingeChanged(_ degrees: Double?) {
        guard let degrees else {
            hingeAvailable = false
            return
        }
        hingeAvailable = true
        let closed = degrees < 15
        guard closed != isClosed else { return }
        isClosed = closed
        switch phase {
        case .armed where closed:
            begin()
            phase = .running
        case .running where !closed:
            // Ouvert pendant la séance : 10 secondes pour refermer.
            phase = .reopened
            reopenDeadline = Date().addingTimeInterval(Self.grace)
            Haptics.warning()
            SoundPlayer.shared.play(.caught, volume: 0.5)
        case .reopened where closed:
            phase = .running
            reopenDeadline = nil
            Haptics.tap()
        default:
            break
        }
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        guard phase == .running || phase == .reopened else { return }
        switch scenePhase {
        case .background:
            backgroundSince = Date()
        case .active:
            if let since = backgroundSince, Date().timeIntervalSince(since) > Self.grace, remaining > 0 {
                wilt()
            }
            backgroundSince = nil
        default:
            break
        }
    }
}

// MARK: - Écran

struct FermeView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = FermeSession()
    @State private var showGarden = false
    @State private var confirmGiveUp = false

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let durations = [15, 25, 45, 60, 90]

    var body: some View {
        VStack(spacing: 14) {
            GameHeader(title: L("FERME"), subtitle: L("Ferme ton Duo, fais pousser ta plante"), onBack: {
                if session.phase == .setup || session.phase == .done || session.phase == .wilted {
                    app.route = .hub
                }
            }) {
                Button {
                    showGarden = true
                } label: {
                    Label("\(app.fermeGarden.count)", systemImage: "leaf.fill")
                        .font(.plie(15, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.card))
                }
                .accessibilityLabel(L("Mon jardin, \(app.fermeGarden.count) plantes"))
            }

            switch session.phase {
            case .setup:
                setupView
            case .armed, .running, .reopened:
                runningView
            case .done, .wilted:
                resultView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .onHingeAngle { degrees in session.hingeChanged(degrees) }
        .onReceive(ticker) { _ in
            if session.tick() {
                app.recordFerme(FermeRecord(plant: session.plantID, minutes: session.minutes, date: Date()))
            }
        }
        .onChange(of: scenePhase) { _, newValue in session.scenePhaseChanged(newValue) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showGarden) {
            FermeGardenView()
                .environment(app)
        }
    }

    // MARK: Préparation

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                PlantCanvas(plant: FermePlant.named(session.plantID), growth: 1, wilted: false)
                    .frame(height: 170)

                VStack(spacing: 10) {
                    SectionTitle(text: L("Durée"))
                    HStack(spacing: 8) {
                        ForEach(durations, id: \.self) { m in
                            let locked = m > 25 && !store.ownsPass
                            Button {
                                if locked { app.showPass = true } else { session.minutes = m }
                            } label: {
                                VStack(spacing: 2) {
                                    if locked {
                                        Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(Theme.gold)
                                    }
                                    Text("\(m)").font(.plie(20))
                                    Text("min").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(session.minutes == m ? Theme.ferme : Theme.card))
                                .foregroundStyle(session.minutes == m ? Theme.ink : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle(text: L("Plante"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(FermePlant.all) { plant in
                                let locked = !plant.free && !store.ownsPass
                                Button {
                                    if locked { app.showPass = true } else { session.plantID = plant.id }
                                } label: {
                                    VStack(spacing: 6) {
                                        PlantCanvas(plant: plant, growth: 1, wilted: false)
                                            .frame(width: 70, height: 70)
                                            .opacity(locked ? 0.4 : 1)
                                        HStack(spacing: 3) {
                                            if locked { Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Theme.gold) }
                                            Text(plant.displayName).font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                    }
                                    .padding(10)
                                    .background(GlassPanel(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(session.plantID == plant.id ? Theme.ferme : Color.clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text(session.hingeAvailable
                     ? L("Touche « Planter », puis ferme ton iPhone Duo. Si tu le rouvres avant la fin, tu as 10 secondes pour le refermer, sinon ta plante fane.")
                     : L("Touche « Planter » et pose ton téléphone. Si tu quittes Plié plus de 10 secondes, ta plante fane."))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                Button {
                    session.plant()
                } label: {
                    Label(L("Planter · \(session.minutes) min"), systemImage: "leaf.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.ferme, textColor: Theme.ink, height: 60))

                todayLine
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var todayLine: some View {
        let today = app.fermeGarden.filter { Calendar.current.isDateInToday($0.date) }
        let minutes = today.reduce(0) { $0 + $1.minutes }
        return Text(today.isEmpty ? L("Aucune plante aujourd'hui pour l'instant.")
                    : L("Aujourd'hui : \(today.count) plante\(today.count > 1 ? "s" : ""), \(minutes) min de concentration."))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.muted)
    }

    // MARK: Séance en cours

    private var runningView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            PlantCanvas(plant: FermePlant.named(session.plantID), growth: session.growth, wilted: false)
                .frame(maxWidth: 360, maxHeight: 360)
            if session.phase == .armed {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ferme)
                Text(L("Ferme ton iPhone Duo pour commencer"))
                    .font(.plie(24))
                    .multilineTextAlignment(.center)
                Text(L("La plante poussera sur l'écran extérieur."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(timeText(session.remaining))
                    .font(.plie(64))
                    .monospacedDigit()
                if session.phase == .reopened {
                    Text(L("Referme vite ! \(Int(session.reopenLeft.rounded(.up))) s"))
                        .font(.plie(22))
                        .foregroundStyle(Theme.coral)
                } else {
                    Text(encouragement)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)
            Button(confirmGiveUp ? L("Vraiment abandonner ? La plante fanera") : (session.phase == .armed ? L("Annuler") : L("Abandonner"))) {
                if session.phase == .armed || confirmGiveUp {
                    confirmGiveUp = false
                    session.giveUp()
                } else {
                    confirmGiveUp = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmGiveUp = false }
                }
            }
            .buttonStyle(GhostButtonStyle())
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private var encouragement: String {
        let g = session.growth
        if g < 0.25 { return L("La graine germe. Reste concentré.") }
        if g < 0.5 { return L("Les premières feuilles sortent.") }
        if g < 0.8 { return L("Elle grandit bien. Continue.") }
        return L("Presque en fleur !")
    }

    private func timeText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Fin

    private var resultView: some View {
        let done = session.phase == .done
        return VStack(spacing: 16) {
            Spacer(minLength: 0)
            PlantCanvas(plant: FermePlant.named(session.plantID), growth: session.growth, wilted: !done)
                .frame(maxWidth: 320, maxHeight: 320)
                .overlay {
                    if done {
                        ConfettiView(colors: [FermePlant.named(session.plantID).flowerColor, Theme.ferme, Color(hex: 0xFFE27A), .white], count: 60)
                            .frame(width: 420, height: 520)
                    }
                }
            Text(done ? L("Ta \(FermePlant.named(session.plantID).displayName.lowercased()) a fleuri !") : L("Ta plante a fané…"))
                .font(.plie(28))
                .multilineTextAlignment(.center)
            Text(done ? L("\(session.minutes) minutes de concentration. Elle rejoint ton jardin.")
                      : L("Ce n'est pas grave : replante-en une et tiens jusqu'au bout."))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button(done ? L("Planter encore") : L("Réessayer")) { session.backToSetup() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.ferme, textColor: Theme.ink))
                .frame(maxWidth: 420)
            Button(L("Voir mon jardin")) { showGarden = true }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Jardin

struct FermeGardenView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let totalMinutes = app.fermeGarden.reduce(0) { $0 + $1.minutes }
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        stat("\(app.fermeGarden.count)", L("plantes"))
                        stat(L("\(totalMinutes / 60) h \(totalMinutes % 60)"), L("de concentration"))
                        stat("\(app.fermeStreak)", L("jours d'affilée"))
                    }
                    if app.fermeGarden.isEmpty {
                        Text(L("Ton jardin est vide. Ferme ton Duo pour faire pousser ta première plante."))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                            ForEach(Array(app.fermeGarden.reversed().enumerated()), id: \.offset) { item in
                                VStack(spacing: 4) {
                                    PlantCanvas(plant: FermePlant.named(item.element.plant), growth: 1, wilted: false)
                                        .frame(width: 64, height: 64)
                                    Text(L("\(item.element.minutes) min"))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.muted)
                                }
                                .padding(6)
                                .background(GlassPanel(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(L("Mon jardin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.plie(22)).foregroundStyle(.white)
            Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(GlassPanel(cornerRadius: 16))
    }
}

// MARK: - Dessin d'une plante

struct PlantCanvas: View {
    let plant: FermePlant
    let growth: Double
    let wilted: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let g = max(0.02, min(1, growth))
            let stemColor = wilted ? Color(hex: 0x8A7A4A) : plant.stemColor
            let flowerColor = wilted ? Color(hex: 0x7A5A3A) : plant.flowerColor

            let potW = w * 0.34
            let potH = h * 0.2
            let potTop = h - potH
            let base = CGPoint(x: w / 2, y: potTop - h * 0.02)
            let maxStem = h * 0.62
            let stemH = maxStem * g
            let lean = wilted ? w * 0.18 : 0
            let topPoint = CGPoint(x: base.x + lean, y: base.y - stemH * (wilted ? 0.7 : 1))

            // Halo de lumière derrière la plante qui fleurit
            if !wilted && g > 0.6 {
                let glow = w * 0.42 * CGFloat(g)
                context.fill(Path(ellipseIn: CGRect(x: topPoint.x - glow, y: topPoint.y - glow, width: glow * 2, height: glow * 2)),
                             with: .radialGradient(Gradient(colors: [flowerColor.opacity(0.3), .clear]),
                                                   center: topPoint, startRadius: 0, endRadius: glow))
            }

            // Ombre et pot en terre cuite
            context.fill(Path(ellipseIn: CGRect(x: w / 2 - potW * 0.6, y: h - h * 0.035, width: potW * 1.2, height: h * 0.05)),
                         with: .color(.black.opacity(0.3)))
            var pot = Path()
            pot.move(to: CGPoint(x: w / 2 - potW / 2, y: potTop))
            pot.addLine(to: CGPoint(x: w / 2 + potW / 2, y: potTop))
            pot.addLine(to: CGPoint(x: w / 2 + potW * 0.38, y: h - h * 0.01))
            pot.addQuadCurve(to: CGPoint(x: w / 2 - potW * 0.38, y: h - h * 0.01), control: CGPoint(x: w / 2, y: h + h * 0.01))
            pot.closeSubpath()
            context.fill(pot, with: .linearGradient(Gradient(colors: [Color(hex: 0xE08A5C), Color(hex: 0xC8673E), Color(hex: 0x8F4426)]),
                                                    startPoint: CGPoint(x: w / 2 - potW / 2, y: 0), endPoint: CGPoint(x: w / 2 + potW / 2, y: 0)))
            var band = Path()
            band.move(to: CGPoint(x: w / 2 - potW * 0.46, y: potTop + potH * 0.35))
            band.addLine(to: CGPoint(x: w / 2 + potW * 0.46, y: potTop + potH * 0.35))
            context.stroke(band, with: .color(.white.opacity(0.18)), lineWidth: 1.5)
            let rim = CGRect(x: w / 2 - potW * 0.55, y: potTop - h * 0.035, width: potW * 1.1, height: h * 0.05)
            context.fill(Path(roundedRect: rim, cornerRadius: h * 0.012),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xF09A6A), Color(hex: 0xD9784D), Color(hex: 0x9E4E2C)]),
                                               startPoint: CGPoint(x: rim.minX, y: 0), endPoint: CGPoint(x: rim.maxX, y: 0)))
            // Terreau
            let soil = CGRect(x: w / 2 - potW * 0.48, y: potTop - h * 0.03, width: potW * 0.96, height: h * 0.022)
            context.fill(Path(ellipseIn: soil), with: .color(Color(hex: 0x3B2416)))
            for i in 0..<10 {
                let x = soil.minX + CGFloat(Draw.hash(i, 77)) * soil.width
                let y = soil.minY + CGFloat(Draw.hash(i, 78)) * soil.height
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color(hex: 0x6B4A30)))
            }

            func leafPath(at p: CGPoint, side: CGFloat, length: CGFloat) -> Path {
                var leaf = Path()
                leaf.move(to: p)
                leaf.addQuadCurve(to: CGPoint(x: p.x + side * length, y: p.y - h * 0.04),
                                  control: CGPoint(x: p.x + side * length * 0.5, y: p.y - h * 0.09))
                leaf.addQuadCurve(to: p, control: CGPoint(x: p.x + side * length * 0.62, y: p.y + h * 0.02))
                return leaf
            }

            switch plant.shape {
            case .cactus:
                let bodyW = w * 0.16
                let bodyRect = CGRect(x: base.x - bodyW / 2, y: topPoint.y, width: bodyW, height: base.y - topPoint.y)
                var parts = [Path(roundedRect: bodyRect, cornerRadius: bodyW / 2)]
                if g > 0.45 {
                    let armH = stemH * 0.35
                    parts.append(Path(roundedRect: CGRect(x: base.x - bodyW * 1.3, y: base.y - stemH * 0.65, width: bodyW * 0.6, height: armH),
                                      cornerRadius: bodyW * 0.3))
                    parts.append(Path(roundedRect: CGRect(x: base.x + bodyW * 0.7, y: base.y - stemH * 0.8, width: bodyW * 0.6, height: armH),
                                      cornerRadius: bodyW * 0.3))
                }
                for part in parts {
                    let r = part.boundingRect
                    context.fill(part, with: .linearGradient(Gradient(colors: [stemColor.opacity(0.75), stemColor, stemColor.opacity(0.8)]),
                                                            startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
                    var ribs = Path()
                    for k in 1..<3 {
                        let x = r.minX + r.width * CGFloat(k) / 3
                        ribs.move(to: CGPoint(x: x, y: r.minY + r.width * 0.3))
                        ribs.addLine(to: CGPoint(x: x, y: r.maxY - r.width * 0.1))
                    }
                    context.stroke(ribs, with: .color(.black.opacity(0.15)), lineWidth: 1)
                    for k in 0..<Int(r.height / 10) {
                        let x = r.minX + r.width * CGFloat(Draw.hash(k, Int(r.minX)))
                        let y = r.minY + CGFloat(k) * 10 + 5
                        context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.6)))
                    }
                }
                if g > 0.85 {
                    let r = w * 0.05
                    let c = CGPoint(x: topPoint.x, y: topPoint.y - r * 0.4)
                    for k in 0..<6 {
                        let a = Double(k) * .pi / 3
                        let pc = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.7, y: c.y + CGFloat(sin(a)) * r * 0.7)
                        context.fill(Path(ellipseIn: CGRect(x: pc.x - r * 0.55, y: pc.y - r * 0.55, width: r * 1.1, height: r * 1.1)),
                                     with: .color(flowerColor))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 0.4, width: r * 0.8, height: r * 0.8)),
                                 with: .color(Color(hex: 0xFFE27A)))
                }
            case .tree:
                var trunk = Path()
                trunk.move(to: base)
                trunk.addQuadCurve(to: topPoint, control: CGPoint(x: base.x - w * 0.12, y: (base.y + topPoint.y) / 2))
                context.stroke(trunk, with: .color(stemColor), style: StrokeStyle(lineWidth: max(3, w * 0.05), lineCap: .round))
                context.stroke(trunk.offsetBy(dx: -w * 0.01, dy: 0), with: .color(.white.opacity(0.15)),
                               style: StrokeStyle(lineWidth: max(1, w * 0.012), lineCap: .round))
                if g > 0.3 {
                    let crown = w * 0.16 * min(1, (g - 0.3) / 0.6 + 0.3)
                    let blobs: [(Double, Double)] = [(-0.9, 0.2), (0.9, 0.1), (0.0, -0.5), (-0.4, -0.2), (0.5, -0.25)]
                    // Couche sombre derrière, couche claire devant : du volume
                    for (layer, shade) in [(0, 0.75), (1, 1.0)] {
                        for (i, (dx, dy)) in blobs.enumerated() where (i + layer) % 2 == 0 || layer == 1 {
                            let k = layer == 0 ? 1.12 : 0.92
                            let c = CGPoint(x: topPoint.x + CGFloat(dx) * crown, y: topPoint.y + CGFloat(dy) * crown + (layer == 0 ? crown * 0.12 : 0))
                            let rect = CGRect(x: c.x - crown * CGFloat(k), y: c.y - crown * 0.8 * CGFloat(k), width: crown * 2 * CGFloat(k), height: crown * 1.6 * CGFloat(k))
                            context.fill(Path(ellipseIn: rect),
                                         with: .radialGradient(Gradient(colors: [flowerColor.opacity(wilted ? 0.6 : 1), flowerColor.opacity((wilted ? 0.5 : 0.85) * shade)]),
                                                               center: CGPoint(x: rect.midX - rect.width * 0.2, y: rect.midY - rect.height * 0.25),
                                                               startRadius: 0, endRadius: rect.width * 0.7))
                        }
                    }
                }
            case .flower, .tulip:
                var stem = Path()
                stem.move(to: base)
                stem.addQuadCurve(to: topPoint, control: CGPoint(x: base.x + w * 0.06 + lean, y: (base.y + topPoint.y) / 2))
                context.stroke(stem, with: .color(stemColor), style: StrokeStyle(lineWidth: max(2.5, w * 0.03), lineCap: .round))
                let leaves = Int(Double(plant.leafCount) * min(1, g * 1.3))
                for i in 0..<leaves {
                    let t = 0.25 + Double(i) * 0.5 / Double(max(1, plant.leafCount))
                    let p = CGPoint(x: base.x + (topPoint.x - base.x) * CGFloat(t), y: base.y + (topPoint.y - base.y) * CGFloat(t))
                    let side: CGFloat = i % 2 == 0 ? -1 : 1
                    let leaf = leafPath(at: p, side: side, length: w * 0.16)
                    context.fill(leaf, with: .linearGradient(Gradient(colors: [stemColor.opacity(0.8), stemColor, .white.opacity(0.5)]),
                                                            startPoint: p, endPoint: CGPoint(x: p.x + side * w * 0.2, y: p.y - h * 0.05)))
                    var vein = Path()
                    vein.move(to: p)
                    vein.addQuadCurve(to: CGPoint(x: p.x + side * w * 0.14, y: p.y - h * 0.04),
                                      control: CGPoint(x: p.x + side * w * 0.07, y: p.y - h * 0.05))
                    context.stroke(vein, with: .color(.black.opacity(0.18)), lineWidth: 1)
                }
                if g > 0.7 {
                    let bloom = min(1, (g - 0.7) / 0.3)
                    let r = w * 0.09 * CGFloat(0.4 + 0.6 * bloom)
                    if plant.shape == .tulip {
                        var cup = Path()
                        cup.move(to: CGPoint(x: topPoint.x - r, y: topPoint.y - r))
                        cup.addQuadCurve(to: CGPoint(x: topPoint.x + r, y: topPoint.y - r), control: CGPoint(x: topPoint.x, y: topPoint.y + r * 1.6))
                        cup.addLine(to: CGPoint(x: topPoint.x + r * 0.5, y: topPoint.y - r * 1.7))
                        cup.addLine(to: CGPoint(x: topPoint.x, y: topPoint.y - r * 1.1))
                        cup.addLine(to: CGPoint(x: topPoint.x - r * 0.5, y: topPoint.y - r * 1.7))
                        cup.closeSubpath()
                        context.fill(cup, with: .linearGradient(Gradient(colors: [.white.opacity(0.6), flowerColor, flowerColor.opacity(0.75)]),
                                                                startPoint: CGPoint(x: topPoint.x - r, y: topPoint.y - r * 1.7),
                                                                endPoint: CGPoint(x: topPoint.x + r, y: topPoint.y + r)))
                        var fold = Path()
                        fold.move(to: CGPoint(x: topPoint.x, y: topPoint.y - r * 1.1))
                        fold.addLine(to: CGPoint(x: topPoint.x, y: topPoint.y + r * 0.4))
                        context.stroke(fold, with: .color(.black.opacity(0.15)), lineWidth: 1.2)
                    } else {
                        for k in 0..<8 {
                            let a = Double(k) * .pi / 4
                            let c = CGPoint(x: topPoint.x + CGFloat(cos(a)) * r, y: topPoint.y + CGFloat(sin(a)) * r)
                            let petal = CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24)
                            context.fill(Path(ellipseIn: petal),
                                         with: .radialGradient(Gradient(colors: [flowerColor.opacity(0.75), flowerColor, flowerColor.opacity(0.85)]),
                                                               center: topPoint, startRadius: r * 0.3, endRadius: r * 1.6))
                        }
                        let heart = CGRect(x: topPoint.x - r * 0.62, y: topPoint.y - r * 0.62, width: r * 1.24, height: r * 1.24)
                        context.fill(Path(ellipseIn: heart),
                                     with: .radialGradient(Gradient(colors: [Color(hex: 0x9A6A3A), Color(hex: 0x5A3A1E)]),
                                                           center: CGPoint(x: heart.midX - r * 0.15, y: heart.midY - r * 0.15),
                                                           startRadius: 0, endRadius: r * 0.7))
                        for k in 0..<7 {
                            let a = Double(k) * 2.4
                            let d = r * 0.35 * CGFloat(Draw.hash(k, 3))
                            let c = CGPoint(x: topPoint.x + CGFloat(cos(a)) * d, y: topPoint.y + CGFloat(sin(a)) * d)
                            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)),
                                         with: .color(Color(hex: 0xFFD27A).opacity(0.8)))
                        }
                    }
                }
            }
        }
        .accessibilityLabel(L("\(plant.displayName), \(Int(growth * 100)) % de croissance"))
    }
}
