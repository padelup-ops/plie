import SwiftUI
import Combine

extension Theme {
    static let pliou = Color(hex: 0xFF9EC7)
}

// MARK: - Pliou, la petite bête en papier
//
// Un œuf de papier : ferme le Duo pour le garder au chaud, il éclot. Ensuite Pliou vit sur le grand
// écran : on le nourrit, on joue, on le lave. Quand on ferme le Duo, c'est la nuit : il dort sur
// l'écran extérieur et reprend des forces. Plus on s'en occupe de jours d'affilée, plus il grandit.

struct PliouState: Codable, Equatable {
    var hatched = false
    var warmth: Double = 0
    var color = 0
    var hunger: Double = 0.75
    var fun: Double = 0.75
    var clean: Double = 0.8
    var energy: Double = 0.8
    var lastUpdate = Date()
    var careDays: [String] = []
    var streak = 0
    var lastCareDay = ""
    var hat = 0
    var hatchDate: Date?
}

@Observable
final class PliouPet {
    enum Stage: Int { case egg, baby, kid, adult }

    static let colors: [UInt32] = [0xFF9EC7, 0x7FC8FF, 0xFFD166, 0x8BE08B]
    /// Chapeaux débloqués selon la série de jours : 0 rien, puis nœud, fleur, couronne, chapeau.
    static let hats: [(String, Int)] = [("", 0), ("🎀", 2), ("🌸", 4), ("👑", 7), ("🎩", 14)]

    private(set) var state = PliouState()
    private(set) var asleep = false
    private(set) var bounceAt: Double = -10
    private(set) var munchAt: Double = -10
    private(set) var bubbles: [CGPoint] = []
    @ObservationIgnored private(set) var clock: Double = 0
    private(set) var message: String?

    @ObservationIgnored private var playTaps: [Double] = []
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private let key = "pliou.state"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(PliouState.self, from: data) {
            state = saved
        }
        catchUp()
    }

    var stage: Stage {
        guard state.hatched else { return .egg }
        let days = state.careDays.count
        if days >= 5 { return .adult }
        if days >= 2 { return .kid }
        return .baby
    }

    var mood: Double { (state.hunger + state.fun + state.clean + state.energy) / 4 }

    var need: String? {
        guard state.hatched else { return nil }
        let needs: [(Double, String)] = [(state.hunger, L("J'ai faim !")), (state.energy, L("Je suis fatigué… ferme le Duo pour que je dorme.")),
                                         (state.fun, L("On joue ? Touche-moi !")), (state.clean, L("Je suis tout sale, frotte-moi !"))]
        guard let worst = needs.min(by: { $0.0 < $1.0 }), worst.0 < 0.45 else { return nil }
        return worst.1
    }

    var color: Color { Color(hex: Self.colors[state.color % Self.colors.count]) }

    static var today: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// Le temps a passé depuis la dernière visite : les besoins baissent (sans jamais tomber à zéro).
    func catchUp() {
        let hours = max(0, Date().timeIntervalSince(state.lastUpdate) / 3600)
        if state.hatched {
            state.hunger = max(0.05, state.hunger - 0.06 * hours)
            state.fun = max(0.05, state.fun - 0.07 * hours)
            state.clean = max(0.05, state.clean - 0.04 * hours)
            state.energy = max(0.05, state.energy - 0.03 * hours)
        }
        state.lastUpdate = Date()
        save(force: true)
    }

    private func save(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSave) > 2 else { return }
        lastSave = Date()
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func say(_ text: String) {
        message = text
        let current = clock
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.clock ?? 0 >= current, self?.message == text { self?.message = nil }
        }
    }

    /// Un soin compte pour la journée : c'est ce qui fait grandir Pliou et allonge la série.
    private func cared() {
        let day = Self.today
        guard state.lastCareDay != day else { return }
        let yesterday: String = {
            let d = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        }()
        state.streak = state.lastCareDay == yesterday ? state.streak + 1 : 1
        state.lastCareDay = day
        if !state.careDays.contains(day) { state.careDays.append(day) }
        if let unlocked = Self.hats.last(where: { $0.1 == state.streak }), !unlocked.0.isEmpty {
            say(L("Série de \(state.streak) jours : nouveau chapeau \(unlocked.0) !"))
            SoundPlayer.shared.play(.promote, volume: 0.8)
        }
        save(force: true)
    }

    // MARK: Soins

    func feed() {
        guard state.hatched, !asleep else { return }
        if state.hunger > 0.95 {
            say(L("Je n'ai plus faim, merci !"))
            return
        }
        state.hunger = min(1, state.hunger + 0.25)
        munchAt = clock
        SoundPlayer.shared.play(.pop, volume: 0.8)
        Haptics.tap()
        say([L("Miam !"), L("Délicieux !"), L("Encore un peu ?")].randomElement() ?? L("Miam !"))
        cared()
    }

    func play() {
        guard state.hatched, !asleep else { return }
        playTaps = playTaps.filter { clock - $0 < 60 }
        bounceAt = clock
        SoundPlayer.shared.play(.chime, volume: 0.6)
        Haptics.tap()
        if playTaps.count < 8 {
            playTaps.append(clock)
            state.fun = min(1, state.fun + 0.06)
            state.energy = max(0.05, state.energy - 0.01)
            cared()
        } else if Int.random(in: 0..<3) == 0 {
            say(L("Pfiou, je suis essoufflé !"))
        }
        save()
    }

    func scrub(at p: CGPoint) {
        guard state.hatched, !asleep else { return }
        state.clean = min(1, state.clean + 0.004)
        if bubbles.count > 18 { bubbles.removeFirst() }
        bubbles.append(p)
        if state.clean >= 0.999 { cared() }
        save()
    }

    func chooseColor(_ i: Int) {
        state.color = i
        save(force: true)
    }

    func chooseHat(_ i: Int) {
        guard Self.hats.indices.contains(i), state.streak >= Self.hats[i].1 else { return }
        state.hat = i
        save(force: true)
    }

    // MARK: Le Duo

    func setClosed(_ closed: Bool) {
        guard closed != asleep else { return }
        asleep = closed
        if !closed && state.hatched {
            say(L("Bonjour ! J'ai bien dormi."))
            SoundPlayer.shared.play(.bloom, volume: 0.6)
        }
        save(force: true)
    }

    /// Sans charnière : on maintient le bouton pour couver ou endormir.
    func holdNight(_ on: Bool) {
        setClosed(on)
    }

    func tick(dt: Double) {
        clock += dt
        if !bubbles.isEmpty && Int(clock * 10) % 3 == 0 { bubbles.removeFirst() }
        if asleep {
            if state.hatched {
                state.energy = min(1, state.energy + dt / 90)
            } else {
                // Couver l'œuf : une minute au chaud, Duo fermé.
                state.warmth = min(1, state.warmth + dt / 60)
                if state.warmth >= 1 { hatch() }
            }
            save()
        }
    }

    private func hatch() {
        state.hatched = true
        state.hatchDate = Date()
        state.hunger = 0.6
        state.fun = 0.7
        state.energy = 0.9
        state.clean = 0.9
        SoundPlayer.shared.play(.win, volume: 0.9)
        Haptics.success()
        say(L("Coucou ! Je suis né !"))
        save(force: true)
    }
}

// MARK: - Écran

struct PliouView: View {
    @Environment(AppState.self) private var app
    @State private var pet = PliouPet()
    @State private var hasHinge = false
    @State private var wardrobe = false


    var body: some View {
        ZStack {
            if pet.asleep {
                PliouNightView(pet: pet)
                if !hasHinge {
                    VStack {
                        Spacer()
                        Button { pet.holdNight(false) } label: {
                            Label(pet.state.hatched ? L("Réveiller Pliou") : L("Arrêter de couver"), systemImage: "sun.max.fill")
                        }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.pliou, textColor: Theme.ink, height: 56))
                        .frame(maxWidth: 320)
                        .padding(.bottom, 40)
                    }
                }
            } else {
                room
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            hasHinge = true
            pet.setClosed(degrees < 20)
        }
        .onFrame(step: 1.0 / 30.0) { _ in pet.tick(dt: 1.0 / 30.0) }
        .onAppear { pet.catchUp() }
        .onDisappear { app.recordPliou(days: pet.state.careDays.count) }
        .sheet(isPresented: $wardrobe) { wardrobeSheet }
    }

    // MARK: La chambre (écran intérieur)

    private var room: some View {
        GeometryReader { proxy in
            ZStack {
                PliouRoom()
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                        HowToButton(game: .pliou)
                        Spacer()
                        if pet.state.streak > 0 {
                            Label(L("\(pet.state.streak) j"), systemImage: "flame.fill")
                                .font(.plie(16))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(Color.black.opacity(0.35)))
                                .accessibilityLabel(L("Série de \(pet.state.streak) jours"))
                        }
                        if pet.state.hatched {
                            IconButton(symbol: "tshirt.fill", label: L("Garde-robe")) { wardrobe = true }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, max(8, proxy.safeAreaInsets.top))

                    if pet.state.hatched { needsBar }

                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        PliouCreature(pet: pet, sleeping: false)
                            .frame(width: min(proxy.size.width, proxy.size.height) * 0.55,
                                   height: min(proxy.size.width, proxy.size.height) * 0.55)
                            .contentShape(Rectangle())
                            .onTapGesture { pet.play() }
                            .gesture(
                                DragGesture(minimumDistance: 12)
                                    .onChanged { value in pet.scrub(at: value.location) }
                            )
                            .accessibilityLabel(pet.state.hatched ? L("Pliou. Touche pour jouer, frotte pour laver.") : L("L'œuf de Pliou"))
                        if let message = pet.message ?? pet.need {
                            Text(message)
                                .font(.plie(16, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                                .offset(y: -50)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pet.message)
                    Spacer(minLength: 0)

                    if pet.state.hatched {
                        actions
                    } else {
                        eggPanel
                    }
                }
                .padding(.bottom, max(14, proxy.safeAreaInsets.bottom))
            }
        }
        .ignoresSafeArea()
    }

    private var needsBar: some View {
        HStack(spacing: 10) {
            gauge("fork.knife", pet.state.hunger, L("Faim"))
            gauge("face.smiling", pet.state.fun, L("Jeu"))
            gauge("drop.fill", pet.state.clean, L("Propreté"))
            gauge("moon.zzz.fill", pet.state.energy, L("Sommeil"))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 560)
    }

    private func gauge(_ symbol: String, _ value: Double, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.35))
                    Capsule().fill(value < 0.3 ? Theme.coral : (value < 0.6 ? Theme.gold : Theme.go))
                        .frame(width: max(6, g.size.width * CGFloat(value)))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(label) : \(Int(value * 100)) %"))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            actionButton("🍎", L("Nourrir")) { pet.feed() }
            actionButton("⭐️", L("Jouer")) { pet.play() }
            actionButton("🫧", L("Laver")) { for _ in 0..<40 { pet.scrub(at: CGPoint(x: CGFloat.random(in: 40...200), y: CGFloat.random(in: 40...200))) } }
            if !hasHinge {
                actionButton("🌙", L("Dodo")) { pet.holdNight(true) }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 560)
    }

    private func actionButton(_ emoji: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(verbatim: emoji).font(.system(size: 30))
                Text(label).font(.plie(14, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(PressableStyle())
    }

    private var eggPanel: some View {
        VStack(spacing: 10) {
            Text(L("Un œuf de papier !")).font(.plie(24))
            Text(hasHinge ? L("Ferme ton Duo pour le garder au chaud : il éclot au bout d'une minute.") : L("Touche « Couver » pour le garder au chaud : il éclot au bout d'une minute."))
                .font(.system(.body, design: .rounded, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            ProgressView(value: pet.state.warmth).tint(Theme.pliou).frame(maxWidth: 300)
            HStack(spacing: 10) {
                ForEach(PliouPet.colors.indices, id: \.self) { i in
                    Button { pet.chooseColor(i) } label: {
                        Circle().fill(Color(hex: PliouPet.colors[i])).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(.white, lineWidth: pet.state.color == i ? 3 : 0))
                    }
                    .accessibilityLabel(L("Couleur"))
                }
            }
            if !hasHinge {
                Button { pet.holdNight(true) } label: {
                    Label(L("Couver"), systemImage: "flame.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.pliou, textColor: Theme.ink, height: 56))
                .frame(maxWidth: 300)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.35)))
        .padding(.horizontal, 16)
    }

    private var wardrobeSheet: some View {
        VStack(spacing: 18) {
            Text(L("Garde-robe")).font(.plie(28))
            Text(L("Occupe-toi de Pliou chaque jour : les chapeaux se débloquent avec ta série."))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                ForEach(PliouPet.hats.indices, id: \.self) { i in
                    let hat = PliouPet.hats[i]
                    let open = pet.state.streak >= hat.1
                    Button { pet.chooseHat(i) } label: {
                        VStack(spacing: 4) {
                            Text(verbatim: hat.0.isEmpty ? "🙂" : hat.0).font(.system(size: 36)).opacity(open ? 1 : 0.3)
                            Text(hat.1 == 0 ? L("Sans chapeau") : L("\(hat.1) jours"))
                                .font(.plie(13, weight: .bold))
                            if !open { Image(systemName: "lock.fill").font(.system(size: 12)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pet.state.hat == i ? Theme.pliou.opacity(0.5) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!open)
                }
            }
        }
        .padding(24)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

// MARK: - La nuit (écran extérieur, Duo fermé)

struct PliouNightView: View {
    let pet: PliouPet

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0B0F3A), Color(hex: 0x241A4F)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Canvas { context, size in
                    for i in 0..<50 {
                        let x = CGFloat(Draw.hash(i, 7)) * size.width
                        let y = CGFloat(Draw.hash(i, 8)) * size.height * 0.6
                        let a = 0.3 + 0.7 * abs(sin(t * (0.5 + Draw.hash(i, 9)) + Double(i)))
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(a)))
                    }
                }
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        PliouCreature(pet: pet, sleeping: true)
                            .frame(width: 200, height: 200)
                        if pet.state.hatched {
                            ForEach(0..<3, id: \.self) { k in
                                let phase = (t * 0.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                                Text(verbatim: "z")
                                    .font(.plie(CGFloat(18 + 10 * k)))
                                    .foregroundStyle(.white.opacity(1 - phase))
                                    .offset(x: CGFloat(60 + 18 * k) + CGFloat(sin(t + Double(k))) * 6, y: CGFloat(-40 - 90 * phase))
                            }
                        }
                    }
                    if pet.state.hatched {
                        Text(L("Chut… Pliou dort.")).font(.plie(24))
                        ProgressView(value: pet.state.energy).tint(Theme.pliou).frame(maxWidth: 220)
                        Text(L("Rouvre le Duo pour le réveiller."))
                            .font(.plie(15, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text(L("L'œuf est au chaud…")).font(.plie(24))
                        ProgressView(value: pet.state.warmth).tint(Theme.pliou).frame(maxWidth: 220)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Le décor

struct PliouRoom: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE3D3), Color(hex: 0xFFC9B5)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Papier peint à motifs pliés
            for i in 0..<30 {
                let x = CGFloat(Draw.hash(i, 61)) * w
                let y = CGFloat(Draw.hash(i, 62)) * h * 0.65
                var tri = Path()
                tri.move(to: CGPoint(x: x, y: y))
                tri.addLine(to: CGPoint(x: x + 10, y: y + 16))
                tri.addLine(to: CGPoint(x: x - 10, y: y + 16))
                tri.closeSubpath()
                context.fill(tri, with: .color(.white.opacity(0.25)))
            }
            // Fenêtre
            let win = CGRect(x: w * 0.68, y: h * 0.12, width: w * 0.22, height: h * 0.22)
            context.fill(Path(roundedRect: win, cornerRadius: 10), with: .linearGradient(Gradient(colors: [Color(hex: 0x8FD3FF), Color(hex: 0xD8F1FF)]), startPoint: CGPoint(x: 0, y: win.minY), endPoint: CGPoint(x: 0, y: win.maxY)))
            context.stroke(Path(roundedRect: win, cornerRadius: 10), with: .color(.white), lineWidth: 6)
            var bars = Path()
            bars.move(to: CGPoint(x: win.midX, y: win.minY)); bars.addLine(to: CGPoint(x: win.midX, y: win.maxY))
            bars.move(to: CGPoint(x: win.minX, y: win.midY)); bars.addLine(to: CGPoint(x: win.maxX, y: win.midY))
            context.stroke(bars, with: .color(.white), lineWidth: 4)
            // Sol
            let floor = CGRect(x: 0, y: h * 0.68, width: w, height: h * 0.32)
            context.fill(Path(floor), with: .linearGradient(Gradient(colors: [Color(hex: 0xC98F55), Color(hex: 0xA8703E)]), startPoint: CGPoint(x: 0, y: floor.minY), endPoint: CGPoint(x: 0, y: floor.maxY)))
            // Tapis rond
            context.fill(Path(ellipseIn: CGRect(x: w * 0.2, y: h * 0.72, width: w * 0.6, height: h * 0.1)), with: .color(Color(hex: 0xFF8FC7).opacity(0.6)))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Pliou, en origami

struct PliouCreature: View {
    let pet: PliouPet
    let sleeping: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let s = min(size.width, size.height)
                let bounce = max(0, 1 - (pet.clock - pet.bounceAt) / 0.5)
                let hop = CGFloat(sin(bounce * .pi)) * s * 0.12
                let breathe = CGFloat(sin(t * (sleeping ? 1.2 : 2.4))) * s * 0.01
                let c = CGPoint(x: size.width / 2, y: size.height * 0.62 - hop + breathe)
                let base = pet.color
                let dark = base.opacity(0.75)
                // Ombre
                context.fill(Path(ellipseIn: CGRect(x: size.width / 2 - s * 0.25, y: size.height * 0.9, width: s * 0.5, height: s * 0.07)),
                             with: .color(.black.opacity(0.18)))
                func tri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint) -> Path {
                    var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: d); p.closeSubpath(); return p
                }
                switch pet.stage {
                case .egg:
                    let wobble = sleeping ? CGFloat(sin(t * 8)) * 0.04 : CGFloat(sin(t * 2)) * 0.02
                    var egg = context
                    egg.translateBy(x: c.x, y: c.y)
                    egg.rotate(by: .radians(Double(wobble)))
                    let rect = CGRect(x: -s * 0.24, y: -s * 0.32, width: s * 0.48, height: s * 0.62)
                    egg.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [.white, base]), startPoint: CGPoint(x: -s * 0.2, y: -s * 0.3), endPoint: CGPoint(x: s * 0.2, y: s * 0.3)))
                    var zig = Path()
                    zig.move(to: CGPoint(x: -s * 0.24, y: 0))
                    for k in 0..<8 { zig.addLine(to: CGPoint(x: -s * 0.24 + CGFloat(k + 1) * s * 0.06, y: k % 2 == 0 ? -s * 0.04 : 0)) }
                    egg.stroke(zig, with: .color(dark), lineWidth: 3)
                case .baby, .kid, .adult:
                    let r = s * (pet.stage == .baby ? 0.22 : (pet.stage == .kid ? 0.26 : 0.3))
                    // Corps : facettes de papier plié
                    let top = CGPoint(x: c.x, y: c.y - r)
                    let left = CGPoint(x: c.x - r, y: c.y + r * 0.2)
                    let right = CGPoint(x: c.x + r, y: c.y + r * 0.2)
                    let bottom = CGPoint(x: c.x, y: c.y + r * 0.95)
                    context.fill(tri(top, left, c), with: .color(base))
                    context.fill(tri(top, right, c), with: .color(dark))
                    context.fill(tri(left, bottom, c), with: .color(dark))
                    context.fill(tri(right, bottom, c), with: .color(base))
                    // Oreilles (renard dès le stade enfant) ou ailes (adulte)
                    if pet.stage == .adult {
                        let flap = sleeping ? 0 : CGFloat(sin(t * 3)) * r * 0.15
                        context.fill(tri(CGPoint(x: c.x - r * 0.6, y: c.y), CGPoint(x: c.x - r * 1.9, y: c.y - r * 0.9 - flap), CGPoint(x: c.x - r * 0.9, y: c.y + r * 0.3)), with: .color(base.opacity(0.9)))
                        context.fill(tri(CGPoint(x: c.x + r * 0.6, y: c.y), CGPoint(x: c.x + r * 1.9, y: c.y - r * 0.9 - flap), CGPoint(x: c.x + r * 0.9, y: c.y + r * 0.3)), with: .color(dark))
                    }
                    let earH = pet.stage == .baby ? r * 0.45 : r * 0.75
                    context.fill(tri(CGPoint(x: c.x - r * 0.75, y: c.y - r * 0.45), CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.45 - earH), CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.8)), with: .color(dark))
                    context.fill(tri(CGPoint(x: c.x + r * 0.75, y: c.y - r * 0.45), CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.45 - earH), CGPoint(x: c.x + r * 0.25, y: c.y - r * 0.8)), with: .color(base))
                    // Plis
                    var folds = Path()
                    folds.move(to: top); folds.addLine(to: bottom)
                    folds.move(to: left); folds.addLine(to: right)
                    context.stroke(folds, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                    // Visage
                    let eyeY = c.y - r * 0.2
                    let happy = pet.mood > 0.6
                    for side: CGFloat in [-1, 1] {
                        let e = CGPoint(x: c.x + side * r * 0.32, y: eyeY)
                        if sleeping {
                            var lid = Path()
                            lid.addArc(center: e, radius: r * 0.09, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                            context.stroke(lid, with: .color(Color(hex: 0x2A1A2E)), lineWidth: 2.5)
                        } else {
                            let er = r * 0.1
                            context.fill(Path(ellipseIn: CGRect(x: e.x - er, y: e.y - er, width: er * 2, height: er * 2.2)), with: .color(Color(hex: 0x2A1A2E)))
                            context.fill(Path(ellipseIn: CGRect(x: e.x - er * 0.2, y: e.y - er * 0.6, width: er * 0.6, height: er * 0.6)), with: .color(.white))
                        }
                    }
                    // Joues et bouche
                    for side: CGFloat in [-1, 1] {
                        context.fill(Path(ellipseIn: CGRect(x: c.x + side * r * 0.55 - r * 0.1, y: eyeY + r * 0.12, width: r * 0.2, height: r * 0.12)), with: .color(Color(hex: 0xFF6B8A).opacity(0.5)))
                    }
                    let munch = max(0, 1 - (pet.clock - pet.munchAt) / 0.8)
                    var mouth = Path()
                    if munch > 0 {
                        let open = r * 0.08 * CGFloat(abs(sin(munch * 18)))
                        mouth.addEllipse(in: CGRect(x: c.x - r * 0.08, y: eyeY + r * 0.25, width: r * 0.16, height: r * 0.06 + open))
                        context.fill(mouth, with: .color(Color(hex: 0x2A1A2E)))
                    } else {
                        mouth.addArc(center: CGPoint(x: c.x, y: eyeY + r * (happy ? 0.22 : 0.36)), radius: r * 0.12,
                                     startAngle: .degrees(happy ? 20 : 200), endAngle: .degrees(happy ? 160 : 340), clockwise: false)
                        context.stroke(mouth, with: .color(Color(hex: 0x2A1A2E)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    // Chapeau
                    let hat = PliouPet.hats[min(pet.state.hat, PliouPet.hats.count - 1)].0
                    if !hat.isEmpty {
                        context.draw(Text(verbatim: hat).font(.system(size: r * 0.6)), at: CGPoint(x: c.x, y: c.y - r * 1.05))
                    }
                    // Saleté (taches) quand il n'est pas propre
                    if pet.state.clean < 0.5 {
                        for k in 0..<Int((0.5 - pet.state.clean) * 16) {
                            let x = c.x + CGFloat(Draw.hash(k, 91) - 0.5) * r * 1.2
                            let y = c.y + CGFloat(Draw.hash(k, 92) - 0.2) * r * 0.9
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 0.12, height: r * 0.09)), with: .color(Color(hex: 0x6B4E2E).opacity(0.45)))
                        }
                    }
                }
                // Bulles de savon
                for (k, b) in pet.bubbles.enumerated() {
                    let br = CGFloat(6 + (k % 4) * 3)
                    context.stroke(Path(ellipseIn: CGRect(x: b.x - br, y: b.y - br - CGFloat(k) * 2, width: br * 2, height: br * 2)),
                                   with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                }
            }
        }
    }
}
