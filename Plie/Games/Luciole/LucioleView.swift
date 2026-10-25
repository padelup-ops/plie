import SwiftUI
import Combine

extension Theme {
    static let luciole = Color(hex: 0xC6F25A)
}

// MARK: - Le voyage de la luciole
//
// Un voyage = 3 prairies (Duo ouvert, écran intérieur) et 3 grottes (Duo fermé, écran extérieur).
// À l'entrée de chaque grotte, on ferme le Duo ; à la sortie, on le rouvre. Puis le grand arbre.
// Les positions sont en coordonnées de l'écran, de 0 à 1 dans chaque sens.

@Observable
final class LucioleGame {
    enum Phase: Equatable {
        case menu, meadow, toCave, waitClose, cave, waitOpen, finale, over
    }

    struct Mote: Identifiable {
        let id: Int
        var x: Double
        var y: Double
        let phase: Double
    }

    struct Bat: Identifiable {
        let id: Int
        var x: Double
        var baseY: Double
        let speed: Double
        let wobble: Double
    }

    struct Gem: Identifiable {
        let id: Int
        let depth: Double
        let x: Double
        var taken = false
    }

    struct Sparkle: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let time: Double
        let good: Bool
    }

    static let legs = 3

    private(set) var phase: Phase = .menu
    private(set) var leg = 0
    private(set) var lights = 0
    private(set) var gemsTaken = 0
    private(set) var hits = 0
    private(set) var fly = CGPoint(x: 0.25, y: 0.5)
    private(set) var clock: Double = 0
    private(set) var scroll: Double = 0
    private(set) var legTime: Double = 0
    private(set) var motes: [Mote] = []
    private(set) var bats: [Bat] = []
    private(set) var archX: Double?
    private(set) var caveDepth: Double = 0
    private(set) var gems: [Gem] = []
    private(set) var sparkles: [Sparkle] = []
    private(set) var flashAt: Double = -10
    private(set) var finaleTime: Double = 0
    /// Le Duo est-il fermé (ou, sans charnière, le joueur a-t-il touché « Entrer ») ?
    private(set) var isClosed = false
    private(set) var hasHinge = false

    var size = CGSize(width: 800, height: 600)
    @ObservationIgnored var target: CGPoint?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var spawnMote: Double = 0
    @ObservationIgnored private var spawnBat: Double = 0
    @ObservationIgnored private var hurtUntil: Double = 0
    @ObservationIgnored private var seed: Double = 0

    var meadowDuration: Double { 24 + Double(leg) * 4 }
    var caveLength: Double { 5.5 + Double(leg) * 1.2 }
    var caveSpeed: Double { 0.27 + Double(leg) * 0.04 }
    static let flyRow = 0.74

    /// Le jeu attend que le Duo soit dans la bonne position.
    var paused: Bool {
        guard hasHinge else { return false }
        switch phase {
        case .meadow, .toCave, .finale: return isClosed
        case .cave: return !isClosed
        default: return false
        }
    }

    var stars: Int {
        var s = 1
        if lights >= 45 { s += 1 }
        if hits <= 3 && gemsTaken >= 12 { s += 1 }
        return s
    }

    // MARK: Partie

    func start() {
        leg = 0
        lights = 0
        gemsTaken = 0
        hits = 0
        seed = Double.random(in: 0...100)
        startMeadow()
        SoundPlayer.shared.play(.go, volume: 0.6)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func quit() {
        phase = .menu
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func startMeadow() {
        phase = .meadow
        legTime = 0
        motes = []
        bats = []
        archX = nil
        sparkles = []
        fly = CGPoint(x: 0.22, y: 0.5)
        spawnMote = 0
        spawnBat = 4
    }

    private func startCave() {
        phase = .cave
        caveDepth = 0
        fly = CGPoint(x: wall(at: 0).center, y: Self.flyRow)
        target = nil
        gems = []
        var d = 1.0
        while d < caveLength - 0.4 {
            let w = wall(at: d)
            gems.append(Gem(id: newID(), depth: d, x: w.center + (w.right - w.left) * Double.random(in: -0.25...0.25)))
            d += Double.random(in: 0.32...0.55)
        }
        SoundPlayer.shared.play(.cave, volume: 0.8)
        Haptics.tap()
    }

    private func newID() -> Int {
        nextID += 1
        return nextID
    }

    /// Le Duo vient d'être fermé ou ouvert.
    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        if closed && phase == .waitClose { startCave() }
        if !closed && phase == .waitOpen { nextLeg() }
    }

    /// Sans charnière : le bouton « Entrer dans la grotte » / « Sortir ».
    func pressPortal() {
        if phase == .waitClose { isClosed = true; startCave() }
        else if phase == .waitOpen { isClosed = false; nextLeg() }
    }

    private func nextLeg() {
        leg += 1
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        if leg >= Self.legs {
            phase = .finale
            finaleTime = 0
            fly = CGPoint(x: 0.2, y: 0.55)
        } else {
            startMeadow()
        }
    }

    /// Les parois de la grotte à une profondeur donnée (en hauteurs d'écran).
    func wall(at depth: Double) -> (left: Double, right: Double, center: Double) {
        let c = 0.5 + 0.2 * sin(depth * 2.1 + seed) + 0.07 * sin(depth * 5.3 + seed * 2)
        let half = max(0.17, 0.3 - 0.035 * Double(leg) - 0.025 * sin(depth * 3.7 + seed))
        let left = max(0.03, c - half)
        let right = min(0.97, c + half)
        return (left, right, (left + right) / 2)
    }

    // MARK: Boucle

    func tick(dt: Double) {
        clock += dt
        sparkles.removeAll { clock - $0.time > 0.7 }
        guard !paused else { return }
        switch phase {
        case .meadow, .toCave, .waitClose:
            tickMeadow(dt)
        case .cave, .waitOpen:
            tickCave(dt)
        case .finale:
            finaleTime += dt
            fly.x += (0.5 - fly.x) * min(1, dt * 1.2)
            fly.y += (0.42 - fly.y) * min(1, dt * 1.2)
            if finaleTime > 6 {
                phase = .over
                UIApplication.shared.isIdleTimerDisabled = false
                SoundPlayer.shared.play(.win, volume: 0.8)
                Haptics.success()
            }
        default:
            break
        }
    }

    private func follow(_ goal: CGPoint, rate: Double, dt: Double) {
        let k = min(1, rate * dt)
        fly.x += (goal.x - fly.x) * k
        fly.y += (goal.y - fly.y) * k
    }

    private func pointsDistance(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = (ax - bx) * Double(size.width)
        let dy = (ay - by) * Double(size.height)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func tickMeadow(_ dt: Double) {
        let speed = (phase == .meadow ? 0.16 + 0.03 * Double(leg) : (phase == .toCave ? 0.1 : 0)) * 1
        scroll += speed * dt
        legTime += dt

        if phase == .meadow {
            if let t = target {
                follow(CGPoint(x: min(0.72, max(0.06, t.x)), y: min(0.88, max(0.1, t.y))), rate: 7, dt: dt)
            } else {
                fly.y += sin(clock * 2) * 0.0008
            }
            // Lucioles à ramasser, chauves-souris à éviter
            spawnMote -= dt
            if spawnMote <= 0 {
                spawnMote = Double.random(in: 0.35...0.75)
                motes.append(Mote(id: newID(), x: 1.06, y: Double.random(in: 0.14...0.82), phase: Double.random(in: 0...6)))
            }
            spawnBat -= dt
            if spawnBat <= 0 {
                spawnBat = Double.random(in: max(1.1, 2.6 - 0.5 * Double(leg))...max(1.8, 3.6 - 0.6 * Double(leg)))
                bats.append(Bat(id: newID(), x: 1.1, baseY: Double.random(in: 0.18...0.78),
                                speed: Double.random(in: 0.26...0.36) + 0.04 * Double(leg), wobble: Double.random(in: 0.04...0.12)))
            }
            if legTime > meadowDuration {
                phase = .toCave
                archX = 1.3
            }
        } else if phase == .toCave {
            if let a = archX {
                archX = max(0.8, a - 0.25 * dt)
                follow(CGPoint(x: (archX ?? 0.8) - 0.02, y: 0.62), rate: 2.2, dt: dt)
                if (archX ?? 1) <= 0.8 && pointsDistance(fly.x, fly.y, 0.78, 0.62) < 30 {
                    phase = .waitClose
                    SoundPlayer.shared.play(.chime, volume: 0.5)
                    Haptics.warning()
                }
            }
        } else {
            fly.y = 0.62 + sin(clock * 3) * 0.01
        }

        for i in motes.indices { motes[i].x -= speed * dt }
        for i in bats.indices { bats[i].x -= (bats[i].speed + speed * 0.5) * dt }
        let flyX = fly.x, flyY = fly.y
        var keep: [Mote] = []
        for m in motes {
            if pointsDistance(m.x, m.y + sin(clock * 2 + m.phase) * 0.02, flyX, flyY) < 36 {
                lights += 1
                sparkles.append(Sparkle(id: newID(), x: m.x, y: m.y, time: clock, good: true))
                SoundPlayer.shared.play(.chime, volume: 0.45)
                Haptics.correct(subtle: true)
            } else if m.x > -0.05 {
                keep.append(m)
            }
        }
        motes = keep
        bats.removeAll { $0.x < -0.1 }
        if clock > hurtUntil {
            for b in bats {
                let by = b.baseY + sin(clock * 3 + Double(b.id)) * b.wobble
                if pointsDistance(b.x, by, flyX, flyY) < 34 {
                    hurt()
                    break
                }
            }
        }
    }

    private func hurt() {
        hits += 1
        let lost = min(lights, 3)
        lights -= lost
        hurtUntil = clock + 1.1
        flashAt = clock
        sparkles.append(Sparkle(id: newID(), x: fly.x, y: fly.y, time: clock, good: false))
        SoundPlayer.shared.play(.wrong, volume: 0.45)
        Haptics.warning()
    }

    private func tickCave(_ dt: Double) {
        if phase == .cave {
            caveDepth += caveSpeed * dt
            let w = wall(at: caveDepth)
            if let t = target {
                fly.x += (t.x - fly.x) * min(1, 9 * dt)
            }
            // Les parois : on rebondit, et on perd un peu de lumière.
            let margin = 26 / max(1, Double(size.width))
            if fly.x < w.left + margin {
                fly.x = w.left + margin
                if clock > hurtUntil { hurt() }
            } else if fly.x > w.right - margin {
                fly.x = w.right - margin
                if clock > hurtUntil { hurt() }
            }
            for i in gems.indices where !gems[i].taken {
                let dy = (gems[i].depth - caveDepth) * Double(size.height)
                let dx = (gems[i].x - fly.x) * Double(size.width)
                if (dx * dx + dy * dy).squareRoot() < 34 {
                    gems[i].taken = true
                    gemsTaken += 1
                    lights += 2
                    sparkles.append(Sparkle(id: newID(), x: gems[i].x, y: Self.flyRow, time: clock, good: true))
                    SoundPlayer.shared.play(.chime, volume: 0.55)
                    Haptics.correct(subtle: true)
                }
            }
            if caveDepth >= caveLength {
                phase = .waitOpen
                SoundPlayer.shared.play(.chime, volume: 0.5)
                Haptics.warning()
            }
        } else {
            fly.x += (wall(at: caveDepth).center - fly.x) * min(1, 2 * dt)
        }
    }
}

// MARK: - Écran

struct LucioleView: View {
    @Environment(AppState.self) private var app
    @State private var game = LucioleGame()
    @State private var recorded = false


    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LucioleScene(game: game)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                game.target = CGPoint(x: value.location.x / max(1, proxy.size.width),
                                                      y: value.location.y / max(1, proxy.size.height))
                            }
                            .onEnded { _ in game.target = nil }
                    )

                VStack {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Retour")) {
                            game.quit()
                            app.route = .hub
                        }
                        HowToButton(game: .luciole)
                        Spacer()
                        if game.phase != .menu && game.phase != .over {
                            Label("\(game.lights)", systemImage: "sparkle")
                                .font(.plie(17))
                                .foregroundStyle(Theme.luciole)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(Color.black.opacity(0.4)))
                                .accessibilityLabel(L("\(game.lights) lumières"))
                            Text(L("Étape \(min(game.leg + 1, LucioleGame.legs)) / \(LucioleGame.legs)"))
                                .font(.plie(14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(Color.black.opacity(0.4)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, max(10, proxy.safeAreaInsets.top))
                    Spacer()
                }

                prompt(proxy: proxy)

                if game.phase == .menu || game.phase == .over {
                    menu
                }
            }
            .onAppear { game.size = proxy.size }
            .onChange(of: proxy.size) { _, s in game.size = s }
        }
        .ignoresSafeArea()
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onFrame { _ in
            game.tick(dt: 1.0 / 60.0)
            if game.phase == .over && !recorded {
                recorded = true
                app.recordLuciole(lights: game.lights, stars: game.stars)
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private func prompt(proxy: GeometryProxy) -> some View {
        let duo = game.hasHinge
        if game.paused {
            promptCard(icon: game.phase == .cave ? .closed : .flat,
                       title: game.phase == .cave ? L("Referme ton Duo") : L("Rouvre ton Duo"),
                       detail: game.phase == .cave ? L("La grotte continue sur l'écran extérieur.") : L("La prairie t'attend sur le grand écran."),
                       button: nil)
        } else if game.phase == .waitClose {
            promptCard(icon: .closed,
                       title: duo ? L("Ferme ton Duo !") : L("La grotte !"),
                       detail: duo ? L("La luciole entre dans la grotte : le voyage continue sur l'écran extérieur.") : L("Entre dans la grotte : touche à gauche ou à droite pour éviter les parois."),
                       button: duo ? nil : L("Entrer dans la grotte"))
        } else if game.phase == .waitOpen {
            promptCard(icon: .flat,
                       title: duo ? L("Rouvre ton Duo !") : L("La sortie !"),
                       detail: duo ? L("La lune brille au bout de la grotte : ouvre le Duo pour retrouver la prairie.") : L("Sors de la grotte pour retrouver la prairie."),
                       button: duo ? nil : L("Sortir de la grotte"))
        }
    }

    private func promptCard(icon: Posture, title: String, detail: String, button: String?) -> some View {
        VStack(spacing: 10) {
            PostureIcon(posture: icon, color: Theme.luciole, lineWidth: 4)
                .frame(width: 90, height: 60)
            Text(title)
                .font(.plie(26))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            if let button {
                Button(button) { game.pressPortal() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.luciole, textColor: Theme.ink, height: 54))
                    .frame(maxWidth: 300)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.luciole.opacity(0.5), lineWidth: 1.5))
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var menu: some View {
        VStack(spacing: 14) {
            if game.phase == .over {
                WinIcon(systemName: "tree.fill", color: Theme.luciole)
                Text(L("Le voyage est fini !"))
                    .font(.plie(30))
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < game.stars ? "star.fill" : "star")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .accessibilityLabel(L("\(game.stars) étoiles sur 3"))
                Text(L("\(game.lights) lumières ramenées au grand arbre · \(game.gemsTaken) cristaux"))
                    .font(.plie(16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                ShareResultButton(game: L("LUCIOLE"), result: L("\(game.lights) lumières ramenées au grand arbre"), accent: Theme.luciole)
                Button(L("Repartir")) { recorded = false; game.start() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.luciole, textColor: Theme.ink))
            } else {
                WinIcon(systemName: "sparkles", color: Theme.luciole)
                Text(L("Le voyage de la luciole"))
                    .font(.plie(26))
                    .multilineTextAlignment(.center)
                Text(L("Ramasse la lumière dans la prairie, traverse la grotte sur l'écran extérieur, et ramène tout au grand arbre."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                if app.lucioleBest > 0 {
                    Text(L("Record : \(app.lucioleBest) lumières"))
                        .font(.plie(14, weight: .bold))
                        .foregroundStyle(Theme.luciole)
                }
                Button(L("Partir")) { recorded = false; game.start() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.luciole, textColor: Theme.ink))
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 440)
        .winCard(accent: Theme.luciole)
        .padding(20)
    }
}

// MARK: - Dessin

struct LucioleScene: View {
    let game: LucioleGame

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            Canvas { context, size in
                switch game.phase {
                case .cave, .waitOpen:
                    drawCave(&context, size)
                default:
                    drawMeadow(&context, size)
                }
                drawSparkles(&context, size)
                if game.phase != .menu && game.phase != .over {
                    drawFly(&context, size)
                }
                // Choc : l'écran clignote en rouge
                let flash = max(0, 1 - (game.clock - game.flashAt) / 0.35)
                if flash > 0 {
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFF3B5C).opacity(0.25 * flash)))
                }
            }
        }
        .accessibilityLabel(L("La luciole, \(game.lights) lumières"))
    }

    private func p(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    private func glow(_ context: inout GraphicsContext, at c: CGPoint, radius: CGFloat, color: Color, strength: Double) {
        context.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(strength), color.opacity(strength * 0.35), .clear]),
                                           center: c, startRadius: 0, endRadius: radius))
    }

    private func drawMeadow(_ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let t = game.clock
        // Ciel de nuit
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x0B0F3A), Color(hex: 0x2A1B5E), Color(hex: 0x5B2C6F)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        for i in 0..<70 {
            let sx = CGFloat(Draw.hash(i, 3)) * w
            let sy = CGFloat(Draw.hash(i, 4)) * h * 0.6
            let tw = 0.4 + 0.6 * abs(sin(t * (0.6 + Draw.hash(i, 5)) + Double(i)))
            let r = CGFloat(0.6 + 1.4 * Draw.hash(i, 6))
            context.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7 * tw)))
        }
        // La lune
        let moon = CGPoint(x: w * 0.82, y: h * 0.18)
        glow(&context, at: moon, radius: h * 0.22, color: Color(hex: 0xFFF3C4), strength: 0.35)
        context.fill(Path(ellipseIn: CGRect(x: moon.x - h * 0.06, y: moon.y - h * 0.06, width: h * 0.12, height: h * 0.12)), with: .color(Color(hex: 0xFFF6D8)))

        // Collines en trois plans (défilement à des vitesses différentes)
        let layers: [(Double, UInt32, Double, Double)] = [(0.15, 0x231648, 0.62, 0.08), (0.4, 0x170F35, 0.72, 0.07), (1.0, 0x0C0820, 0.83, 0.06)]
        for (k, layer) in layers.enumerated() {
            let (speed, color, base, amp) = layer
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h))
            var x: CGFloat = 0
            while x <= w + 8 {
                let u = Double(x / w) + game.scroll * speed * 3
                let y = base + amp * sin(u * 4.1 + Double(k) * 2) + amp * 0.5 * sin(u * 9.3 + Double(k))
                hill.addLine(to: CGPoint(x: x, y: CGFloat(y) * h))
                x += 8
            }
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.closeSubpath()
            context.fill(hill, with: .color(Color(hex: color)))
        }
        // Herbes et fleurs au premier plan
        for i in 0..<60 {
            let gx = (Draw.hash(i, 11) - game.scroll * 1.6).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(gx < 0 ? gx + 1 : gx) * w
            let gh = h * CGFloat(0.05 + 0.06 * Draw.hash(i, 12))
            let sway = CGFloat(sin(t * 1.6 + Double(i))) * gh * 0.25
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: h))
            blade.addQuadCurve(to: CGPoint(x: x + sway, y: h - gh), control: CGPoint(x: x - gh * 0.1, y: h - gh * 0.5))
            context.stroke(blade, with: .color(Color(hex: 0x1D4A3A)), lineWidth: 2)
            if i % 7 == 0 {
                context.fill(Path(ellipseIn: CGRect(x: x + sway - 3, y: h - gh - 3, width: 6, height: 6)), with: .color(Color(hex: 0xFF8FC7).opacity(0.8)))
            }
        }

        // L'entrée de la grotte
        if let a = game.archX {
            let cx = CGFloat(a) * w + w * 0.06
            let base = h * 0.9
            let rw = h * 0.34
            var rock = Path()
            rock.move(to: CGPoint(x: cx - rw, y: base))
            rock.addCurve(to: CGPoint(x: cx + rw * 1.1, y: base), control1: CGPoint(x: cx - rw * 0.9, y: base - rw * 1.9), control2: CGPoint(x: cx + rw * 1.2, y: base - rw * 1.8))
            rock.closeSubpath()
            context.fill(rock, with: .linearGradient(Gradient(colors: [Color(hex: 0x4A3E5C), Color(hex: 0x241C33)]),
                                                     startPoint: CGPoint(x: cx, y: base - rw * 1.4), endPoint: CGPoint(x: cx, y: base)))
            var mouth = Path()
            mouth.move(to: CGPoint(x: cx - rw * 0.45, y: base))
            mouth.addCurve(to: CGPoint(x: cx + rw * 0.5, y: base), control1: CGPoint(x: cx - rw * 0.42, y: base - rw * 1.05), control2: CGPoint(x: cx + rw * 0.48, y: base - rw * 1.05))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Color(hex: 0x05030A)))
            if game.phase == .waitClose {
                let pulse = 0.5 + 0.5 * sin(game.clock * 4)
                glow(&context, at: CGPoint(x: cx, y: base - rw * 0.5), radius: rw * 0.9, color: Theme.luciole, strength: 0.15 + 0.15 * pulse)
            }
        }

        // Lucioles amies
        for m in game.motes {
            let c = p(m.x, m.y + sin(t * 2 + m.phase) * 0.02, size)
            let blink = 0.6 + 0.4 * sin(t * 5 + m.phase)
            glow(&context, at: c, radius: 22, color: Color(hex: 0xE6FF7A), strength: 0.55 * blink)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }
        // Chauves-souris
        for b in game.bats {
            let c = p(b.x, b.baseY + sin(t * 3 + Double(b.id)) * b.wobble, size)
            let flap = CGFloat(sin(t * 14 + Double(b.id)))
            var bat = Path()
            bat.move(to: c)
            bat.addQuadCurve(to: CGPoint(x: c.x - 26, y: c.y - 6 - flap * 10), control: CGPoint(x: c.x - 12, y: c.y - 16 - flap * 8))
            bat.addQuadCurve(to: CGPoint(x: c.x - 6, y: c.y + 6), control: CGPoint(x: c.x - 18, y: c.y + 2))
            bat.addLine(to: c)
            bat.addQuadCurve(to: CGPoint(x: c.x + 26, y: c.y - 6 - flap * 10), control: CGPoint(x: c.x + 12, y: c.y - 16 - flap * 8))
            bat.addQuadCurve(to: CGPoint(x: c.x + 6, y: c.y + 6), control: CGPoint(x: c.x + 18, y: c.y + 2))
            bat.closeSubpath()
            context.fill(bat, with: .color(Color(hex: 0x05030A)))
            context.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 5, width: 14, height: 12)), with: .color(Color(hex: 0x05030A)))
            for side: CGFloat in [-1, 1] {
                context.fill(Path(ellipseIn: CGRect(x: c.x + side * 3 - 1.5, y: c.y - 2, width: 3, height: 3)), with: .color(Color(hex: 0xFF5C6E)))
            }
        }

        // Le grand arbre (fin du voyage)
        if game.phase == .finale || game.phase == .over {
            let grow = min(1, game.finaleTime / 3)
            let trunkBase = CGPoint(x: w * 0.5, y: h * 0.95)
            var trunk = Path()
            trunk.move(to: CGPoint(x: trunkBase.x - w * 0.025, y: trunkBase.y))
            trunk.addLine(to: CGPoint(x: trunkBase.x - w * 0.012, y: trunkBase.y - h * 0.35 * CGFloat(grow)))
            trunk.addLine(to: CGPoint(x: trunkBase.x + w * 0.012, y: trunkBase.y - h * 0.35 * CGFloat(grow)))
            trunk.addLine(to: CGPoint(x: trunkBase.x + w * 0.025, y: trunkBase.y))
            trunk.closeSubpath()
            context.fill(trunk, with: .color(Color(hex: 0x3A2414)))
            let crown = CGPoint(x: w * 0.5, y: h * 0.42)
            let cr = h * 0.3 * CGFloat(grow)
            glow(&context, at: crown, radius: cr * 1.6, color: Theme.luciole, strength: 0.35 * grow)
            context.fill(Path(ellipseIn: CGRect(x: crown.x - cr, y: crown.y - cr * 0.8, width: cr * 2, height: cr * 1.6)), with: .color(Color(hex: 0x163A2A).opacity(0.95)))
            // Les lumières ramenées s'accrochent aux branches
            let shown = Int(Double(min(game.lights, 120)) * min(1, game.finaleTime / 4.5))
            for i in 0..<shown {
                let a = Draw.hash(i, 21) * 2 * .pi
                let rr = cr * CGFloat(Draw.hash(i, 22)).squareRoot() * 0.95
                let c = CGPoint(x: crown.x + CGFloat(cos(a)) * rr, y: crown.y + CGFloat(sin(a)) * rr * 0.8)
                let blink = 0.6 + 0.4 * sin(t * 4 + Double(i))
                glow(&context, at: c, radius: 10, color: Color(hex: 0xE6FF7A), strength: 0.7 * blink)
            }
        }
    }

    private func drawCave(_ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let depth = game.caveDepth
        let row = LucioleGame.flyRow
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0E0A16)))
        // Parois : on échantillonne la grotte de haut en bas de l'écran.
        var left = Path(), right = Path()
        left.move(to: CGPoint(x: 0, y: 0))
        right.move(to: CGPoint(x: w, y: 0))
        var y: CGFloat = 0
        while y <= h + 6 {
            let d = depth + (row - Double(y / h))
            let wall = game.wall(at: d)
            left.addLine(to: CGPoint(x: CGFloat(wall.left) * w, y: y))
            right.addLine(to: CGPoint(x: CGFloat(wall.right) * w, y: y))
            y += 6
        }
        left.addLine(to: CGPoint(x: 0, y: h))
        left.closeSubpath()
        right.addLine(to: CGPoint(x: w, y: h))
        right.closeSubpath()
        let rock = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(hex: 0x3B3050), Color(hex: 0x241C33)]),
                                                          startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
        context.fill(left, with: rock)
        context.fill(right, with: rock)
        context.stroke(left, with: .color(Color(hex: 0x6A5A8A).opacity(0.5)), lineWidth: 2)
        context.stroke(right, with: .color(Color(hex: 0x6A5A8A).opacity(0.5)), lineWidth: 2)

        // La sortie : la lune au bout de la grotte
        let exitY = CGFloat(row - (game.caveLength - depth)) * h
        if exitY > -h * 0.3 {
            glow(&context, at: CGPoint(x: CGFloat(game.wall(at: game.caveLength).center) * w, y: exitY), radius: w * 0.5,
                 color: Color(hex: 0xFFF3C4), strength: 0.5)
        }
        // Cristaux
        for g in game.gems where !g.taken {
            let gy = CGFloat(row - (g.depth - depth)) * h
            guard gy > -20, gy < h + 20 else { continue }
            let c = CGPoint(x: CGFloat(g.x) * w, y: gy)
            glow(&context, at: c, radius: 26, color: Color(hex: 0x5CE1FF), strength: 0.5)
            var gem = Path()
            gem.move(to: CGPoint(x: c.x, y: c.y - 11))
            gem.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            gem.addLine(to: CGPoint(x: c.x, y: c.y + 11))
            gem.addLine(to: CGPoint(x: c.x - 8, y: c.y))
            gem.closeSubpath()
            context.fill(gem, with: .linearGradient(Gradient(colors: [.white, Color(hex: 0x5CE1FF)]), startPoint: CGPoint(x: c.x, y: c.y - 11), endPoint: CGPoint(x: c.x, y: c.y + 11)))
        }
        // Obscurité : seule la lumière de la luciole éclaire la grotte.
        let fc = p(game.fly.x, game.fly.y, size)
        let reach = max(w, h) * 0.55
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.45),
                        .init(color: .black.opacity(0.88), location: 1)
                     ]), center: fc, startRadius: 0, endRadius: reach))
    }

    private func drawFly(_ context: inout GraphicsContext, _ size: CGSize) {
        let c = p(game.fly.x, game.fly.y, size)
        let t = game.clock
        let pulse = 0.75 + 0.25 * sin(t * 6)
        glow(&context, at: c, radius: 60, color: Color(hex: 0xE6FF7A), strength: 0.45 * pulse)
        // Ailes
        let flap = CGFloat(abs(sin(t * 22))) * 6
        for side: CGFloat in [-1, 1] {
            context.fill(Path(ellipseIn: CGRect(x: c.x + side * 4 - 7, y: c.y - 14 - flap, width: 14, height: 12 + flap)),
                         with: .color(.white.opacity(0.35)))
        }
        context.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 6, width: 14, height: 14)), with: .color(Color(hex: 0x3A3420)))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y, width: 12, height: 12)), with: .color(Color(hex: 0xF4FF9A)))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y + 3, width: 6, height: 6)), with: .color(.white))
    }

    private func drawSparkles(_ context: inout GraphicsContext, _ size: CGSize) {
        for s in game.sparkles {
            let age = (game.clock - s.time) / 0.7
            let c = p(s.x, s.y, size)
            let r = CGFloat(10 + 30 * age)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color((s.good ? Color(hex: 0xE6FF7A) : Color(hex: 0xFF5C6E)).opacity(0.8 * (1 - age))), lineWidth: 2)
        }
    }
}
