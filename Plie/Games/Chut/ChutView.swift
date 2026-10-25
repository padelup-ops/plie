import SwiftUI
import QuartzCore

extension Theme {
    static let chut = Color(hex: 0x8F7BFF)
}

// MARK: - CHUT !
//
// Le Duo fermé, c'est un coffre au trésor… sur lequel dort un dragon (écran extérieur).
// On ouvre le Duo tout doucement : trop vite, le dragon se réveille.
// Dedans, on ramasse les gemmes (chaque geste fait un peu de bruit), puis on referme pour s'enfuir.

struct ChutNight {
    let number: Int

    /// Vitesse d'ouverture (degrés par seconde) que le dragon supporte.
    var quietSpeed: Double { max(14, 45 - Double(number - 1) * 1.6) }
    /// Bruit d'une gemme ramassée.
    var tapNoise: Double { 0.05 + Double(number) * 0.003 }
    /// Temps avant que le jour se lève, une fois le coffre ouvert.
    var lootTime: Double { max(8, 16 - Double(number) * 0.35) }
    /// Le dragon renifle à partir de la 4e nuit.
    var sniffs: Bool { number >= 4 }
    var gemCount: Int { min(16, 6 + number / 2) }
    var hasCrown: Bool { number >= 5 }

    static let count = 20
}

struct ChutGem: Identifiable {
    let id: Int
    let spot: CGPoint
    let crown: Bool
    var taken = false
    var value: Int { crown ? 3 : 1 }
}

@Observable
final class ChutGame {
    enum Phase { case menu, sleeping, opening, loot, escaped, awake }

    static let openAngle = 20.0
    static let treasureAngle = 120.0

    private(set) var phase: Phase = .menu
    private(set) var night = ChutNight(number: 1)
    private(set) var angle: Double = 0
    private(set) var speed: Double = 0
    private(set) var wake: Double = 0
    private(set) var hasHinge = false
    private(set) var closedSeen = false
    private(set) var gems: [ChutGem] = []
    private(set) var lootClock: Double = 0
    private(set) var sniffing = false
    private(set) var clock: Double = 0
    private(set) var tooFast = false

    @ObservationIgnored private var samples: [(t: Double, a: Double)] = []
    @ObservationIgnored private var nextSniff: Double = 5
    @ObservationIgnored private var sniffEnd: Double = 0
    @ObservationIgnored private var nextSnore: Double = 0

    var collected: Int { gems.filter(\.taken).reduce(0) { $0 + $1.value } }
    var total: Int { gems.reduce(0) { $0 + $1.value } }
    var isClosed: Bool { angle < Self.openAngle }
    /// Le couvercle compte : le dragon dort, on ouvre, ou on pille.
    var lidInPlay: Bool { phase == .sleeping || phase == .opening || phase == .loot }
    var dawn: Double { min(1, lootClock / night.lootTime) }

    var stars: Int {
        guard phase == .escaped, collected > 0 else { return 0 }
        let ratio = Double(collected) / Double(max(1, total))
        return ratio >= 0.9 ? 3 : (ratio >= 0.5 ? 2 : 1)
    }

    func start(_ number: Int) {
        night = ChutNight(number: number)
        wake = 0
        speed = 0
        gems = []
        lootClock = 0
        sniffing = false
        tooFast = false
        samples = []
        if !hasHinge { angle = 0 }
        closedSeen = isClosed
        phase = .sleeping
    }

    func backToMenu() {
        phase = .menu
    }

    // MARK: La charnière (ou le curseur, sans Duo)

    func setAngle(_ degrees: Double, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        let now = CACurrentMediaTime()
        angle = max(0, min(180, degrees))
        samples.append((t: now, a: angle))
        samples.removeAll { now - $0.t > 0.3 }
        if let first = samples.first, now - first.t > 0.05 {
            speed = abs(angle - first.a) / (now - first.t)
        }
        if isClosed { closedSeen = true }

        switch phase {
        case .sleeping:
            if closedSeen && !isClosed {
                phase = .opening
                SoundPlayer.shared.play(.clunk, volume: 0.25)
            }
        case .opening:
            if isClosed {
                phase = .sleeping
            } else if angle >= Self.treasureAngle {
                openTreasure()
            }
        case .loot:
            if isClosed { escape() }
        default:
            break
        }
    }

    private func openTreasure() {
        phase = .loot
        lootClock = 0
        nextSniff = Double.random(in: 3...6)
        var list: [ChutGem] = []
        let spots = BoitePuzzle.scatter(night.gemCount, cols: 5, rows: 4)
        for (i, spot) in spots.enumerated() {
            list.append(ChutGem(id: i, spot: CGPoint(x: 0.08 + spot.x * 0.84, y: 0.36 + spot.y * 0.58), crown: false))
        }
        if night.hasCrown {
            // La couronne vaut 3, mais elle est tout près du museau du dragon.
            list.append(ChutGem(id: list.count, spot: CGPoint(x: 0.5, y: 0.3), crown: true))
        }
        gems = list
        SoundPlayer.shared.play(.chime, volume: 0.4)
        Haptics.success()
    }

    private func escape() {
        phase = .escaped
        SoundPlayer.shared.play(collected > 0 ? .win : .thud, volume: 0.8)
        Haptics.success()
    }

    private func wakeUp() {
        phase = .awake
        SoundPlayer.shared.play(.roar)
        Haptics.error()
    }

    // MARK: Les gemmes

    func take(_ gem: ChutGem) {
        guard phase == .loot, let i = gems.firstIndex(where: { $0.id == gem.id }), !gems[i].taken else { return }
        gems[i].taken = true
        var noise = night.tapNoise * (gem.crown ? 2.2 : 1)
        if sniffing { noise += 0.35 }
        wake += noise
        SoundPlayer.shared.play(.gem, volume: 0.5)
        Haptics.tap()
        if wake >= 1 { wakeUp() }
    }

    // MARK: Le temps qui passe

    func tick(dt: Double) {
        clock += dt
        let now = CACurrentMediaTime()
        // Plus de nouvelle mesure : la charnière ne bouge plus.
        if let last = samples.last, now - last.t > 0.15 { speed *= pow(0.02, dt) }

        switch phase {
        case .opening, .loot:
            let quiet = night.quietSpeed
            tooFast = speed > quiet
            if tooFast {
                wake += (speed - quiet) / quiet * dt * 0.9
            } else {
                wake = max(0, wake - (phase == .loot ? 0.02 : 0.05) * dt)
            }
            if phase == .loot {
                lootClock += dt
                if lootClock >= night.lootTime {
                    // Le jour se lève : le dragon se réveille vite.
                    wake += 0.5 * dt
                }
                if night.sniffs {
                    if sniffing {
                        if speed > 4 { wake += 1.5 * dt }
                        if lootClock >= sniffEnd { sniffing = false }
                    } else if lootClock >= nextSniff {
                        sniffing = true
                        sniffEnd = lootClock + 1.6
                        nextSniff = lootClock + Double.random(in: 4...7)
                        Haptics.warning()
                    }
                }
            }
            if wake >= 1 { wakeUp() }
        default:
            tooFast = false
        }

        // Le ronflement : il s'arrête quand le dragon est presque réveillé (c'est là qu'il faut s'inquiéter).
        if lidInPlay && clock >= nextSnore {
            nextSnore = clock + 2.8
            if wake < 0.55 { SoundPlayer.shared.play(.snore, volume: Float(0.35 + 0.3 * wake)) }
        }
    }
}

// MARK: - Écran

struct ChutView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @State private var game = ChutGame()

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            switch game.phase {
            case .menu:
                ChutMenu(game: game)
            case .sleeping:
                if game.closedSeen && game.isClosed {
                    sleeping
                } else {
                    closeFirst
                }
            case .opening, .loot:
                ChutTreasureView(game: game)
            case .escaped:
                result(won: true)
            case .awake:
                result(won: false)
            }
            if !game.hasHinge && game.lidInPlay {
                HStack {
                    Spacer()
                    ChutLidSlider(angle: game.angle) { game.setAngle($0, fromHinge: false) }
                        .frame(width: 70)
                        .padding(.trailing, 10)
                        .padding(.vertical, 90)
                }
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setAngle(degrees, fromHinge: true)
        }
        .onReceive(ticker) { _ in game.tick(dt: 1.0 / 30.0) }
        .onChange(of: game.phase) { _, phase in
            if phase == .escaped { app.recordChut(game.night.number, stars: game.stars, gems: game.collected) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
            HowToButton(game: .chut)
            Spacer()
            Text(L("Nuit \(game.night.number)"))
                .font(.plie(17))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Duo fermé : le dragon dort sur le coffre (écran extérieur).
    private var sleeping: some View {
        ZStack {
            ChutCave()
            VStack(spacing: 14) {
                topBar
                Spacer()
                ChutDragon(wake: 0, awake: false, clock: game.clock)
                    .frame(height: 230)
                Text(L("Chut… le dragon dort sur le trésor."))
                    .font(.plie(24))
                    .multilineTextAlignment(.center)
                Text(game.hasHinge ? L("Ouvre ton Duo tout, tout doucement, jusqu'au bout.")
                                   : L("Monte le couvercle tout doucement avec le curseur."))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private var closeFirst: some View {
        ZStack {
            ChutCave()
            VStack(spacing: 18) {
                topBar
                Spacer()
                Image(systemName: "lizard.fill")
                    .font(.system(size: 70, weight: .bold))
                    .foregroundStyle(Theme.chut)
                    .accessibilityHidden(true)
                Text(L("Ferme ton Duo"))
                    .font(.plie(30))
                Text(L("Le trésor est enfermé, et le dragon dort dessus. Ferme le Duo pour commencer, puis rouvre-le très lentement."))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private func result(won: Bool) -> some View {
        ZStack {
            ChutCave()
            if won && game.collected > 0 {
                ConfettiView().ignoresSafeArea().allowsHitTesting(false)
            }
            ScrollView {
                VStack(spacing: 14) {
                    if won {
                        Text(verbatim: game.collected > 0 ? "💎" : "😮‍💨").font(.system(size: 72)).accessibilityHidden(true)
                        Text(game.collected > 0 ? L("Ouf, tu t'es échappé !") : L("Sauvé… mais les mains vides"))
                            .font(.plie(30))
                            .multilineTextAlignment(.center)
                        if game.collected > 0 {
                            Text(L("\(game.collected) / \(game.total) gemmes"))
                                .font(.plie(20, weight: .bold))
                                .foregroundStyle(Theme.gold)
                            StarsView(count: game.stars, size: 28)
                        }
                    } else {
                        ChutDragon(wake: 1, awake: true, clock: game.clock)
                            .frame(height: 170)
                        Text(L("Le dragon s'est réveillé !"))
                            .font(.plie(30))
                            .multilineTextAlignment(.center)
                        Text(L("Il garde son trésor. La prochaine fois : plus doucement, et pars avant le lever du jour."))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 10) {
                        if won && game.stars > 0 && game.night.number < ChutNight.count {
                            Button {
                                let next = game.night.number + 1
                                if app.chutNeedsPass(next, hasPass: store.ownsPass) {
                                    app.showPass = true
                                } else {
                                    game.start(next)
                                }
                            } label: {
                                Label(L("Nuit suivante"), systemImage: "moon.stars.fill")
                            }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.chut, textColor: Theme.ink, height: 58))
                        }
                        Button(L("Recommencer cette nuit")) { game.start(game.night.number) }
                            .buttonStyle(GhostButtonStyle())
                        Button(L("Toutes les nuits")) { game.backToMenu() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    .frame(maxWidth: 380)
                }
                .padding(26)
                .winCard(accent: won ? Theme.gold : Theme.coral)
                .padding(20)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity, minHeight: 500)
            }
        }
    }
}

// MARK: - Le coffre ouvert (écran intérieur)

struct ChutTreasureView: View {
    let game: ChutGame

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ChutCave()
                // Lueur dorée du trésor, de plus en plus forte avec l'ouverture
                RadialGradient(colors: [Theme.gold.opacity(0.45 * min(1, game.angle / ChutGame.treasureAngle)), .clear],
                               center: UnitPoint(x: 0.5, y: 0.7), startRadius: 10, endRadius: max(size.width, size.height) * 0.6)
                    .ignoresSafeArea()

                ChutDragon(wake: game.wake, awake: false, clock: game.clock)
                    .frame(width: min(size.width * 0.7, 520), height: min(size.height * 0.32, 260))
                    .position(x: size.width / 2, y: size.height * 0.16)

                if game.phase == .loot {
                    ForEach(game.gems) { gem in
                        if !gem.taken {
                            Button { game.take(gem) } label: {
                                Text(verbatim: gem.crown ? "👑" : (gem.id % 3 == 0 ? "🪙" : "💎"))
                                    .font(.system(size: gem.crown ? 54 : 44))
                                    .shadow(color: Theme.gold.opacity(0.8), radius: 10)
                                    .frame(width: 72, height: 72)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .position(x: gem.spot.x * size.width, y: gem.spot.y * size.height)
                            .accessibilityLabel(gem.crown ? L("Couronne") : L("Gemme"))
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                        HowToButton(game: .chut)
                        Spacer()
                        if game.phase == .loot {
                            Label("\(game.collected)", systemImage: "diamond.fill")
                                .font(.plie(18))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .accessibilityLabel(L("\(game.collected) gemmes"))
                        }
                    }
                    Spacer()
                    status
                }
                .padding(.horizontal, 16)
                .padding(.top, max(10, proxy.safeAreaInsets.top))
                .padding(.bottom, max(14, proxy.safeAreaInsets.bottom))
                .padding(.trailing, game.hasHinge ? 0 : 80)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: game.collected)
        }
        .ignoresSafeArea()
    }

    private var status: some View {
        VStack(spacing: 10) {
            if game.phase == .opening {
                Text(game.tooFast ? L("Trop vite ! Doucement…") : L("Doucement… continue d'ouvrir"))
                    .font(.plie(22))
                    .foregroundStyle(game.tooFast ? Theme.coral : .white)
                meter(L("Ouverture"), value: game.angle / ChutGame.treasureAngle, color: Theme.gold)
            } else {
                Text(game.sniffing ? L("👃 Il renifle… ne bouge plus !")
                     : (game.dawn >= 1 ? L("Le jour se lève : referme vite !") : L("Prends les gemmes, puis referme doucement pour t'enfuir.")))
                    .font(.plie(20))
                    .foregroundStyle(game.sniffing || game.dawn >= 1 ? Theme.coral : .white)
                    .multilineTextAlignment(.center)
                meter(L("Lever du jour"), value: game.dawn, color: Theme.sun)
            }
            meter(L("Réveil du dragon"), value: game.wake, color: game.wake > 0.6 ? Theme.coral : Theme.chut)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.5)))
    }

    private func meter(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.muted)
                .frame(width: 120, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: max(8, g.size.width * CGFloat(min(1, max(0, value)))))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(label) : \(Int(min(1, max(0, value)) * 100)) %"))
    }
}

// MARK: - Sans charnière : le couvercle au doigt

struct ChutLidSlider: View {
    let angle: Double
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let y = h * (1 - CGFloat(angle / 180))
            ZStack(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule().strokeBorder(Theme.chut.opacity(0.6), lineWidth: 2)
                Circle()
                    .fill(Theme.chut)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "hand.point.up.fill").foregroundStyle(Theme.ink))
                    .position(x: g.size.width / 2, y: min(h - 29, max(29, y)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = 1 - min(1, max(0, value.location.y / max(1, h)))
                        onChange(Double(fraction) * 180)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(L("Couvercle du coffre"))
        .accessibilityValue(L("\(Int(angle)) degrés"))
        .accessibilityAdjustableAction { direction in
            onChange(direction == .increment ? min(180, angle + 10) : max(0, angle - 10))
        }
    }
}

// MARK: - Menu

struct ChutMenu: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    let game: ChutGame

    var body: some View {
        VStack(spacing: 0) {
            GameHeader(title: L("CHUT !"),
                       subtitle: L("Ton trésor : \(app.chutGems) gemmes"),
                       onBack: { app.route = .hub }) {
                HowToButton(game: .chut)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 18) {
                    ChutDragon(wake: 0, awake: false, clock: 0)
                        .frame(height: 150)
                    Text(L("Un dragon dort sur le coffre. Ouvre le Duo sans le réveiller, ramasse les gemmes et referme avant le lever du jour. Chaque nuit, il a le sommeil plus léger."))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SectionTitle(text: L("Les nuits"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(1...ChutNight.count, id: \.self) { number in
                            nightButton(number)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ChutCave().opacity(0.7))
    }

    private func nightButton(_ number: Int) -> some View {
        let done = app.chutStars[number] != nil
        let needsPass = app.chutNeedsPass(number, hasPass: store.ownsPass)
        let unlocked = app.chutIsUnlocked(number, hasPass: store.ownsPass)

        return Button {
            if needsPass {
                app.showPass = true
            } else if unlocked {
                game.start(number)
            }
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    Text(verbatim: "\(number)")
                        .font(.plie(24))
                        .foregroundStyle(.white)
                    StarsView(count: app.chutStars[number] ?? 0, size: 11)
                } else {
                    Image(systemName: needsPass ? "crown.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(needsPass ? Theme.gold : Theme.muted)
                    Text(verbatim: "\(number)")
                        .font(.plie(13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(LevelTile(done: done, accent: Theme.chut, cornerRadius: 18))
        }
        .buttonStyle(PressableStyle())
        .disabled(!unlocked && !needsPass)
        .accessibilityLabel(unlocked ? L("Nuit \(number)") : (needsPass ? L("Nuit \(number), avec le Pass") : L("Nuit \(number), verrouillée")))
    }
}

// MARK: - Le décor

struct ChutCave: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x0D0A24), Color(hex: 0x1E1238)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // Stalactites
            for i in 0..<14 {
                let x = CGFloat(Draw.hash(i, 31)) * size.width
                let w = CGFloat(20 + Draw.hash(i, 32) * 40)
                let h = CGFloat(30 + Draw.hash(i, 33) * 90)
                var p = Path()
                p.move(to: CGPoint(x: x - w / 2, y: 0))
                p.addLine(to: CGPoint(x: x + w / 2, y: 0))
                p.addLine(to: CGPoint(x: x, y: h))
                p.closeSubpath()
                context.fill(p, with: .color(Color(hex: 0x2B1D4D).opacity(0.9)))
            }
            // Pièces d'or éparpillées au sol
            for i in 0..<30 {
                let x = CGFloat(Draw.hash(i, 41)) * size.width
                let y = size.height * (0.82 + CGFloat(Draw.hash(i, 42)) * 0.16)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10, height: 5)), with: .color(Theme.gold.opacity(0.35)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Le dragon, roulé en boule. `wake` (0…1) entrouvre son œil ; `awake` : il crache du feu.
struct ChutDragon: View {
    let wake: Double
    let awake: Bool
    let clock: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let breathe = CGFloat(sin(clock * (awake ? 6 : 1.6))) * h * 0.015
            let green = Color(hex: 0x4FBF6A)
            let dark = Color(hex: 0x2E7D45)
            let belly = Color(hex: 0xC9E67A)

            // Queue
            var tail = Path()
            tail.move(to: CGPoint(x: w * 0.78, y: h * 0.82))
            tail.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.55), control: CGPoint(x: w * 1.0, y: h * 0.9))
            context.stroke(tail, with: .color(dark), style: StrokeStyle(lineWidth: h * 0.09, lineCap: .round))
            var tip = Path()
            tip.move(to: CGPoint(x: w * 0.98, y: h * 0.45))
            tip.addLine(to: CGPoint(x: w * 0.93, y: h * 0.6))
            tip.addLine(to: CGPoint(x: w * 1.0, y: h * 0.62))
            tip.closeSubpath()
            context.fill(tip, with: .color(dark))

            // Corps
            let body = CGRect(x: w * 0.3, y: h * 0.35 - breathe, width: w * 0.55, height: h * 0.55 + breathe)
            context.fill(Path(ellipseIn: body), with: .color(green))
            context.fill(Path(ellipseIn: body.insetBy(dx: body.width * 0.2, dy: body.height * 0.25).offsetBy(dx: 0, dy: body.height * 0.15)), with: .color(belly.opacity(0.7)))
            // Piquants du dos
            for k in 0..<5 {
                let x = body.minX + body.width * (0.2 + 0.15 * CGFloat(k))
                let y = body.minY + body.height * (k == 2 ? 0.0 : 0.05)
                var spike = Path()
                spike.move(to: CGPoint(x: x - w * 0.025, y: y + h * 0.04))
                spike.addLine(to: CGPoint(x: x, y: y - h * 0.08))
                spike.addLine(to: CGPoint(x: x + w * 0.025, y: y + h * 0.04))
                spike.closeSubpath()
                context.fill(spike, with: .color(dark))
            }
            // Tête posée sur les pattes
            let head = CGRect(x: w * 0.08, y: h * 0.48, width: w * 0.32, height: h * 0.36)
            context.fill(Path(ellipseIn: head), with: .color(green))
            let snout = CGRect(x: w * 0.02, y: h * 0.6, width: w * 0.18, height: h * 0.2)
            context.fill(Path(ellipseIn: snout), with: .color(green))
            // Narines
            for dx in [0.05, 0.09] {
                context.fill(Path(ellipseIn: CGRect(x: w * CGFloat(dx), y: h * 0.66, width: w * 0.02, height: h * 0.03)), with: .color(dark))
            }
            // Cornes
            for (x, lean) in [(0.2, -0.04), (0.3, 0.03)] {
                var horn = Path()
                horn.move(to: CGPoint(x: w * CGFloat(x - 0.03), y: h * 0.52))
                horn.addLine(to: CGPoint(x: w * CGFloat(x + lean), y: h * 0.32))
                horn.addLine(to: CGPoint(x: w * CGFloat(x + 0.03), y: h * 0.52))
                horn.closeSubpath()
                context.fill(horn, with: .color(Color(hex: 0xF3E3B0)))
            }
            // Œil : une paupière qui s'ouvre avec le réveil
            let eye = CGRect(x: w * 0.24, y: h * 0.56, width: w * 0.09, height: h * 0.11)
            let open = awake ? 1.0 : min(1, max(0, (wake - 0.25) / 0.75))
            if open <= 0.02 {
                var lid = Path()
                lid.addArc(center: CGPoint(x: eye.midX, y: eye.midY), radius: eye.width / 2, startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
                context.stroke(lid, with: .color(Color(hex: 0x1B3A24)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            } else {
                let shown = CGRect(x: eye.minX, y: eye.midY - eye.height * 0.5 * CGFloat(open), width: eye.width, height: eye.height * CGFloat(open))
                context.fill(Path(ellipseIn: shown), with: .color(Color(hex: 0xFFE14D)))
                context.fill(Path(ellipseIn: CGRect(x: eye.midX - eye.width * 0.12, y: shown.minY, width: eye.width * 0.24, height: shown.height)),
                             with: .color(awake ? Color(hex: 0xD62828) : .black))
            }
            // Zzz… ou flammes
            if awake {
                for k in 0..<7 {
                    let t = (clock * 2 + Double(k) / 7).truncatingRemainder(dividingBy: 1)
                    let x = w * 0.02 - CGFloat(t) * w * 0.25
                    let y = h * 0.7 + CGFloat(sin(Double(k) * 1.7)) * h * 0.08
                    let r = h * (0.05 + 0.08 * CGFloat(t))
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color((k % 2 == 0 ? Theme.sun : Theme.gold).opacity(1 - t)))
                }
            } else if wake < 0.55 {
                for k in 0..<3 {
                    let t = (clock * 0.45 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    let text = Text(verbatim: "z").font(.system(size: h * (0.08 + 0.05 * CGFloat(k)), weight: .black, design: .rounded))
                    context.opacity = 1 - t
                    context.draw(text.foregroundColor(.white), at: CGPoint(x: w * (0.1 + 0.05 * CGFloat(k)), y: h * (0.45 - 0.35 * CGFloat(t))))
                    context.opacity = 1
                }
            }
        }
        .accessibilityLabel(awake ? L("Le dragon est réveillé") : (wake > 0.5 ? L("Le dragon remue") : L("Le dragon dort")))
    }
}
