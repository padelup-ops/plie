import SwiftUI

extension Theme {
    static let peche = Color(hex: 0x3FB5E8)
}

// MARK: - PÊCHE
//
// Duo plié en L : la moitié debout montre le ciel et la barque, la moitié à plat le fond de l'eau.
// La charnière est la ligne de l'eau. On lance d'un coup de charnière (refermer puis rouvrir vite),
// on ferre quand ça mord, puis on mouline en pliant et dépliant doucement : trop vite, la ligne casse.
// Tout se calcule en pixels de l'image (160 de large).

struct FishSpecies: Identifiable {
    enum Shape { case fish, clown, stripes, round, sword, lantern, ray, shark, gold, boot, chest }

    let id: String
    /// Le nom en français (clé de traduction).
    let name: String
    /// Profondeur où on le trouve (0 = sous la surface, 1 = le fond).
    let depth: ClosedRange<Double>
    let weight: Double
    /// Force au combat (0,3 = facile, 1,6 = très dur).
    let strength: Double
    let value: Int
    let size: ClosedRange<Int>
    let body: UInt32
    let belly: UInt32
    let fin: UInt32
    let length: Int
    let height: Int
    let shape: Shape

    var title: String { L(key: name) }
    var rare: Bool { value >= 55 }
    var junk: Bool { shape == .boot || shape == .chest }

    static let all: [FishSpecies] = [
        FishSpecies(id: "sardine", name: "Sardine", depth: 0.0...0.4, weight: 30, strength: 0.3, value: 5, size: 12...20,
                    body: 0x9FB8D8, belly: 0xE8F0FF, fin: 0x5C7BA8, length: 9, height: 3, shape: .fish),
        FishSpecies(id: "clown", name: "Poisson-clown", depth: 0.0...0.35, weight: 10, strength: 0.35, value: 18, size: 8...12,
                    body: 0xFF7A1A, belly: 0xFFA54F, fin: 0x1A1030, length: 8, height: 5, shape: .clown),
        FishSpecies(id: "maquereau", name: "Maquereau", depth: 0.1...0.5, weight: 22, strength: 0.45, value: 9, size: 25...40,
                    body: 0x3A8F7A, belly: 0xDDEFE8, fin: 0x1F4F45, length: 11, height: 4, shape: .stripes),
        FishSpecies(id: "dorade", name: "Dorade", depth: 0.2...0.6, weight: 18, strength: 0.55, value: 14, size: 25...45,
                    body: 0xD9B66A, belly: 0xFFF0C8, fin: 0x9C7A3A, length: 10, height: 6, shape: .fish),
        FishSpecies(id: "rouget", name: "Rouget", depth: 0.3...0.7, weight: 14, strength: 0.5, value: 16, size: 15...30,
                    body: 0xE84A4A, belly: 0xFFC2B0, fin: 0xA82A2A, length: 9, height: 4, shape: .fish),
        FishSpecies(id: "bar", name: "Bar", depth: 0.35...0.8, weight: 12, strength: 0.7, value: 25, size: 40...80,
                    body: 0x8E9CB0, belly: 0xE6EBF2, fin: 0x5A6680, length: 13, height: 5, shape: .fish),
        FishSpecies(id: "lune", name: "Poisson-lune", depth: 0.3...0.9, weight: 4, strength: 0.6, value: 60, size: 60...120,
                    body: 0xB8B4A8, belly: 0xE2DED2, fin: 0x7E7A6E, length: 10, height: 10, shape: .round),
        FishSpecies(id: "thon", name: "Thon", depth: 0.4...0.9, weight: 7, strength: 0.95, value: 45, size: 80...180,
                    body: 0x2B4A8C, belly: 0xC8D4EA, fin: 0xFFD23A, length: 16, height: 6, shape: .fish),
        FishSpecies(id: "raie", name: "Raie", depth: 0.7...1.0, weight: 5, strength: 0.9, value: 55, size: 50...150,
                    body: 0x7A6A58, belly: 0xA8957E, fin: 0x4E4234, length: 14, height: 7, shape: .ray),
        FishSpecies(id: "lanterne", name: "Poisson-lanterne", depth: 0.75...1.0, weight: 6, strength: 0.5, value: 70, size: 10...20,
                    body: 0x3A2E5C, belly: 0x5A4A8A, fin: 0x241A40, length: 9, height: 5, shape: .lantern),
        FishSpecies(id: "espadon", name: "Espadon", depth: 0.5...1.0, weight: 4, strength: 1.15, value: 90, size: 150...300,
                    body: 0x3B5F8F, belly: 0xB8C8E0, fin: 0x22385A, length: 17, height: 5, shape: .sword),
        FishSpecies(id: "requin", name: "Requin", depth: 0.6...1.0, weight: 2, strength: 1.4, value: 150, size: 150...300,
                    body: 0x7C8A99, belly: 0xE3E8EE, fin: 0x4C5866, length: 21, height: 7, shape: .shark),
        FishSpecies(id: "dore", name: "Poisson doré", depth: 0.85...1.0, weight: 0.7, strength: 1.6, value: 400, size: 30...50,
                    body: 0xFFC93C, belly: 0xFFF2A8, fin: 0xE8941A, length: 10, height: 6, shape: .gold),
        FishSpecies(id: "botte", name: "Vieille botte", depth: 0.6...1.0, weight: 3, strength: 0.2, value: 1, size: 40...44,
                    body: 0x6B4A2A, belly: 0x8A6440, fin: 0x3A2616, length: 8, height: 7, shape: .boot),
        FishSpecies(id: "coffre", name: "Coffre au trésor", depth: 0.9...1.0, weight: 0.6, strength: 0.4, value: 250, size: 50...60,
                    body: 0xC27A45, belly: 0xFFD23A, fin: 0x6E4020, length: 10, height: 7, shape: .chest),
    ]
}

enum PecheUpgrade: Int, CaseIterable, Identifiable {
    case rod, reel, lead
    var id: Int { rawValue }
    static let maxLevel = 5
    static let costs = [30, 90, 240, 600, 1400]

    var title: String {
        switch self {
        case .rod: return L("Canne")
        case .reel: return L("Moulinet")
        case .lead: return L("Appât")
        }
    }

    func cost(_ level: Int) -> Int { level < Self.costs.count ? Self.costs[level] : 0 }
}

@Observable
final class PecheGame {
    enum Phase: Equatable { case ready, aiming, flying, sinking, bite, fighting, caught, snapped, escaped }

    struct Catch: Equatable {
        let species: Int
        let size: Int
        let value: Int
        let isNew: Bool
        let record: Bool
    }

    struct Fish {
        var species: Int
        var x: Double
        var y: Double
        var vx: Double
        var wobble: Double
        var age = 0.0
        var ignoreUntil = 0.0
        var attracted = false
    }

    struct Particle {
        var x: Double, y: Double, vx: Double, vy: Double, life: Double
        var color: UInt32
        var bubble: Bool
    }

    private(set) var phase: Phase = .ready
    private(set) var frame = 0
    private(set) var coins: Int
    private(set) var levels: [Int]
    private(set) var best: [String: Int]
    private(set) var tension: Double = 0
    private(set) var gauge: Double = 0
    private(set) var catchResult: Catch?
    private(set) var message: String?
    private(set) var tooFastWarning = false
    var reelHeld = false

    // Le dessin lit tout ceci à chaque image : pas besoin de le suivre un par un.
    @ObservationIgnored let cols = 160
    @ObservationIgnored private(set) var rows = 320
    @ObservationIgnored private(set) var floorY: Double = 280
    @ObservationIgnored private(set) var time: Double = 0
    @ObservationIgnored private(set) var fish: [Fish] = []
    @ObservationIgnored private(set) var particles: [Particle] = []
    @ObservationIgnored private(set) var lureX: Double = 0
    @ObservationIgnored private(set) var lureY: Double = 0
    @ObservationIgnored private(set) var hooked: Int?
    @ObservationIgnored private var tracker = HingeTracker()
    @ObservationIgnored private var flyT: Double = 0
    @ObservationIgnored private var flyFrom = (x: 0.0, y: 0.0)
    @ObservationIgnored private var landX: Double = 100
    @ObservationIgnored private var aimTime: Double = 0
    @ObservationIgnored private var flickClose: Double = -10
    @ObservationIgnored private var biteLeft: Double = 0
    @ObservationIgnored private var fightDist: Double = 0
    @ObservationIgnored private var fightStart: Double = 1
    @ObservationIgnored private var anchor = (x: 0.0, y: 0.0)
    @ObservationIgnored private var stamina: Double = 1
    @ObservationIgnored private var bursting = false
    @ObservationIgnored private var burstLeft: Double = 1.5
    @ObservationIgnored private var overload: Double = 0
    @ObservationIgnored private var messageLeft: Double = 0
    @ObservationIgnored private var spawnLeft: Double = 0
    @ObservationIgnored private var bubbleLeft: Double = 0

    private let defaults = UserDefaults.standard

    init() {
        let store = UserDefaults.standard
        coins = store.integer(forKey: "peche.coins")
        levels = PecheUpgrade.allCases.map { store.integer(forKey: "peche.lvl.\($0.rawValue)") }
        if let data = store.data(forKey: "peche.best"), let d = try? JSONDecoder().decode([String: Int].self, from: data) {
            best = d
        } else {
            best = [:]
        }
    }

    // MARK: Mise en page

    var half: Double { Double(rows) / 2 }
    var boatX: Double { 16 }
    var rodTip: (x: Double, y: Double) { (boatX + 36, half - 24 + bob) }
    var bob: Double { sin(time * 1.6) * 1.2 }

    func configure(rows: Int, bottomReserve: Double) {
        let newRows = max(160, rows)
        let changed = newRows != self.rows
        self.rows = newRows
        floorY = max(half + 50, Double(newRows) - bottomReserve)
        if changed || fish.isEmpty {
            fish.removeAll()
            populate(5)
            resetLure()
        }
    }

    func depthY(_ d: Double) -> Double { half + 8 + d * (floorY - half - 16) }
    var lureDepth: Double { min(1, max(0, (lureY - half - 8) / max(1, floorY - half - 16))) }
    /// Profondeur en mètres (pour l'affichage).
    var meters: Int { Int((lureDepth * 40).rounded()) }

    var speciesCaught: Int { FishSpecies.all.filter { best[$0.id] != nil }.count }

    // MARK: Améliorations

    var rodStrength: Double { 1 + 0.2 * Double(levels[0]) }
    var reelSpeed: Double { 20 + 6 * Double(levels[1]) }
    var attractRadius: Double { 14 + 3 * Double(levels[2]) }

    func level(_ u: PecheUpgrade) -> Int { levels[u.rawValue] }

    func canBuy(_ u: PecheUpgrade) -> Bool {
        let l = level(u)
        return l < PecheUpgrade.maxLevel && coins >= u.cost(l)
    }

    func buy(_ u: PecheUpgrade) {
        guard canBuy(u) else { return }
        coins -= u.cost(level(u))
        levels[u.rawValue] += 1
        defaults.set(levels[u.rawValue], forKey: "peche.lvl.\(u.rawValue)")
        save()
        SoundPlayer.shared.play(.chime, volume: 0.6)
        Haptics.success()
    }

    private func save() {
        defaults.set(coins, forKey: "peche.coins")
        if let data = try? JSONEncoder().encode(best) { defaults.set(data, forKey: "peche.best") }
    }

    // MARK: Commandes

    /// Le gros bouton (ou une touche sur l'eau) : lancer, arrêter la jauge, ferrer, relancer.
    func primary() {
        switch phase {
        case .ready:
            phase = .aiming
            aimTime = 0
            Haptics.tap()
        case .aiming:
            cast(power: gauge)
        case .bite:
            strike()
        case .caught, .snapped, .escaped:
            again()
        default:
            break
        }
    }

    func again() {
        catchResult = nil
        hooked = nil
        tension = 0
        phase = .ready
        resetLure()
    }

    private func resetLure() {
        lureX = rodTip.x
        lureY = rodTip.y + 4
    }

    func cast(power: Double) {
        guard phase == .ready || phase == .aiming else { return }
        let p = min(1, max(0.15, power))
        flyFrom = rodTip
        landX = rodTip.x + 12 + p * (Double(cols) - rodTip.x - 20)
        flyT = 0
        phase = .flying
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        Haptics.tap()
    }

    func strike() {
        guard phase == .bite, let h = hooked else { return }
        phase = .fighting
        anchor = (x: fish[h].x, y: fish[h].y)
        let entry = surfaceEntry
        fightStart = max(8, hypot(anchor.x - entry.x, anchor.y - entry.y))
        fightDist = fightStart
        stamina = 1
        bursting = false
        burstLeft = 1.2
        overload = 0
        tension = 0.2
        SoundPlayer.shared.play(.clunk, volume: 0.7)
        Haptics.success()
    }

    /// Là où la ligne entre dans l'eau pendant le combat.
    private var surfaceEntry: (x: Double, y: Double) { (rodTip.x + 18, half + 2) }

    // MARK: Charnière

    func hinge(_ degrees: Double?) {
        tracker.update(degrees)
        guard tracker.hasHinge else { return }
        let s = tracker.speed
        switch phase {
        case .ready, .aiming:
            // Refermer vite, puis rouvrir vite : le lancer.
            if s < -150 { flickClose = time }
            if s > 150 && time - flickClose < 0.7 {
                flickClose = -10
                cast(power: min(1, max(0.3, s / 450)))
            }
        case .bite:
            if abs(s) > 150 { strike() }
        default:
            break
        }
    }

    /// De 0 à 1 : la force avec laquelle on mouline (bouton tenu, ou charnière qui bouge).
    var reelInput: Double {
        var r = reelHeld ? 1.0 : 0
        if tracker.hasHinge && (phase == .fighting || phase == .sinking) {
            let h = abs(tracker.speed)
            if h > 12 { r = max(r, min(1, h / 110)) }
        }
        return r
    }

    private var tooFast: Bool { tracker.hasHinge && phase == .fighting && abs(tracker.speed) > 320 }

    // MARK: Le temps qui passe

    func tick(dt: Double) {
        frame &+= 1
        time += dt
        tracker.decay(dt)
        if messageLeft > 0 {
            messageLeft -= dt
            if messageLeft <= 0 { message = nil }
        }
        moveFish(dt)
        moveParticles(dt)

        switch phase {
        case .ready:
            resetLure()
        case .aiming:
            aimTime += dt
            let t = (aimTime / 1.1).truncatingRemainder(dividingBy: 2)
            gauge = t < 1 ? t : 2 - t
            resetLure()
        case .flying:
            flyT += dt / 0.75
            let t = min(1, flyT)
            lureX = flyFrom.x + (landX - flyFrom.x) * t
            lureY = flyFrom.y + (half - flyFrom.y) * t - sin(t * .pi) * 34
            if t >= 1 {
                lureY = half + 1
                phase = .sinking
                splash(at: lureX)
                SoundPlayer.shared.play(.splat, volume: 0.5)
            }
        case .sinking:
            sink(dt)
        case .bite:
            biteLeft -= dt
            if let h = hooked {
                fish[h].x = lureX - (fish[h].vx >= 0 ? 4 : -4) + sin(time * 30) * 0.8
                fish[h].y = lureY
            }
            if biteLeft <= 0 {
                if let h = hooked {
                    fish[h].vx = (fish[h].x < lureX ? -1 : 1) * 40
                    fish[h].ignoreUntil = time + 6
                    fish[h].attracted = false
                }
                hooked = nil
                phase = .sinking
                say(L("Raté ! Il s'est enfui."))
            }
        case .fighting:
            fight(dt)
        case .caught, .snapped, .escaped:
            break
        }
    }

    private func sink(_ dt: Double) {
        let r = reelInput
        if r > 0.05 {
            // On remonte le leurre vers la barque.
            let tx = surfaceEntry.x
            lureY -= reelSpeed * 0.8 * r * dt
            lureX += (tx - lureX) * min(1, 0.6 * r * dt)
            if lureY <= half + 1.5 {
                lureY = half + 1.5
                if abs(lureX - tx) < 12 { again(); return }
            }
        } else if lureY < floorY - 4 {
            lureY = min(floorY - 4, lureY + (12 + 2 * Double(levels[2])) * dt)
        }
        bubbleLeft -= dt
        if bubbleLeft <= 0 {
            bubbleLeft = 0.5
            particles.append(Particle(x: lureX, y: lureY - 2, vx: 0, vy: -10, life: 1.6, color: 0xCFEFFF, bubble: true))
        }
        // Un poisson curieux s'approche, puis mord.
        for i in fish.indices {
            let sp = FishSpecies.all[fish[i].species]
            let d = hypot(fish[i].x - lureX, fish[i].y - lureY)
            if sp.junk {
                if d < 6 { bite(i); return }
                continue
            }
            guard time >= fish[i].ignoreUntil else { continue }
            if !fish[i].attracted && d < attractRadius {
                if Double.random(in: 0...1) < 0.55 + 0.08 * Double(levels[2]) {
                    fish[i].attracted = true
                } else {
                    fish[i].ignoreUntil = time + 4
                }
            }
            if fish[i].attracted {
                if d > attractRadius * 1.8 { fish[i].attracted = false; continue }
                let dir: Double = lureX > fish[i].x ? 1 : -1
                fish[i].vx = dir * 14
                fish[i].y += max(-10 * dt, min(10 * dt, lureY - fish[i].y))
                if d < 4 { bite(i); return }
            }
        }
    }

    private func bite(_ i: Int) {
        hooked = i
        biteLeft = 0.85 + 0.1 * Double(levels[2])
        phase = .bite
        SoundPlayer.shared.play(.pok, volume: 0.8)
        Haptics.warning()
    }

    private func fight(_ dt: Double) {
        guard let h = hooked else { phase = .sinking; return }
        let sp = FishSpecies.all[fish[h].species]
        burstLeft -= dt
        if burstLeft <= 0 {
            bursting.toggle()
            burstLeft = bursting ? Double.random(in: 0.4...0.8) : Double.random(in: 0.8...2.2)
            if bursting { Haptics.tap() }
        }
        stamina = max(0.3, stamina - dt * 0.05)
        let pull = sp.strength * stamina * (bursting ? 1.7 : 0.55)
        let r = reelInput
        let fast = tooFast
        tooFastWarning = fast
        let target = (r * (0.3 + pull) + (fast ? 0.9 : 0)) / rodStrength
        tension += (target - tension) * min(1, dt * 3.5)
        if tension > 1 {
            overload += dt
            if overload > 0.5 { snap(); return }
        } else {
            overload = max(0, overload - dt)
        }
        fightDist += (-r * reelSpeed * (bursting ? 0.35 : 1) + pull * 9 * (1 - r * 0.6)) * dt
        // La position du poisson : entre l'endroit où il a mordu et la surface, près de la barque.
        let e = surfaceEntry
        let f = fightDist / fightStart
        var x = e.x + (anchor.x - e.x) * f + sin(time * 12) * (bursting ? 2.5 : 1)
        var y = e.y + (anchor.y - e.y) * f + cos(time * 9) * 0.6
        x = min(Double(cols) - 6, max(6, x))
        y = min(floorY - 4, max(half + 2, y))
        fish[h].vx = anchor.x >= e.x ? 1 : -1
        fish[h].x = x
        fish[h].y = y
        lureX = x + (fish[h].vx >= 0 ? -3 : 3)
        lureY = y
        if bursting && frame % 6 == 0 {
            particles.append(Particle(x: x, y: y - 3, vx: Double.random(in: -6...6), vy: -14, life: 1.0, color: 0xCFEFFF, bubble: true))
        }
        if fightDist <= 3 { land(h); return }
        if fightDist > fightStart + 45 {
            fish.remove(at: h)
            hooked = nil
            phase = .escaped
            tension = 0
            SoundPlayer.shared.play(.wrong, volume: 0.5)
            Haptics.error()
        }
    }

    private func snap() {
        if let h = hooked {
            fish[h].vx = (fish[h].x < surfaceEntry.x ? -1 : 1) * 50
            fish[h].ignoreUntil = time + 8
            fish[h].attracted = false
        }
        hooked = nil
        phase = .snapped
        tension = 0
        tooFastWarning = false
        SoundPlayer.shared.play(.wrong, volume: 0.7)
        Haptics.error()
    }

    private func land(_ h: Int) {
        let index = fish[h].species
        let sp = FishSpecies.all[index]
        let size = Int.random(in: sp.size)
        let span = Double(max(1, sp.size.upperBound - sp.size.lowerBound))
        let value = max(1, Int((Double(sp.value) * (0.8 + 0.4 * Double(size - sp.size.lowerBound) / span)).rounded()))
        let old = best[sp.id]
        let isNew = old == nil
        let record = !isNew && size > (old ?? 0)
        best[sp.id] = max(size, old ?? 0)
        coins += value
        save()
        fish.remove(at: h)
        hooked = nil
        tension = 0
        tooFastWarning = false
        splash(at: surfaceEntry.x)
        catchResult = Catch(species: index, size: size, value: value, isNew: isNew, record: record)
        phase = .caught
        SoundPlayer.shared.play(isNew || sp.rare ? .win : .chime, volume: 0.7)
        Haptics.success()
    }

    private func say(_ text: String) {
        message = text
        messageLeft = 1.6
    }

    // MARK: Poissons et bulles

    private func populate(_ n: Int) {
        for _ in 0..<n { spawn(anywhere: true) }
    }

    private func spawn(anywhere: Bool) {
        let d = Double.random(in: 0...1)
        let candidates = FishSpecies.all.indices.filter { FishSpecies.all[$0].depth.contains(d) }
        guard !candidates.isEmpty else { return }
        let lead = Double(levels[2])
        let weights = candidates.map { FishSpecies.all[$0].weight * (FishSpecies.all[$0].rare ? 1 + 0.35 * lead : 1) }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var pick = candidates[0]
        for (k, w) in zip(candidates, weights) {
            if roll < w { pick = k; break }
            roll -= w
        }
        let sp = FishSpecies.all[pick]
        if sp.junk {
            // Les objets reposent au fond, sans bouger.
            guard !fish.contains(where: { FishSpecies.all[$0.species].junk }) else { return }
            fish.append(Fish(species: pick, x: Double.random(in: 30...Double(cols - 14)), y: floorY - 5, vx: 0, wobble: 0))
            return
        }
        let dir: Double = Bool.random() ? 1 : -1
        let speed = Double.random(in: 7...15) / (1 + sp.strength * 0.4)
        let x = anywhere ? Double.random(in: 10...Double(cols - 10)) : (dir > 0 ? -20 : Double(cols + 20))
        fish.append(Fish(species: pick, x: x, y: depthY(d), vx: dir * speed, wobble: Double.random(in: 0...6.28)))
    }

    private func moveFish(_ dt: Double) {
        spawnLeft -= dt
        let target = 5 + levels[2] / 2
        if spawnLeft <= 0 && fish.count < target {
            spawn(anywhere: false)
            spawnLeft = Double.random(in: 1.5...3.5)
        }
        var i = 0
        while i < fish.count {
            if i == hooked { i += 1; continue }
            fish[i].age += dt
            let sp = FishSpecies.all[fish[i].species]
            if !sp.junk {
                fish[i].x += fish[i].vx * dt
                fish[i].y += sin(time * 1.8 + fish[i].wobble) * 3 * dt
                fish[i].y = min(floorY - 5, max(half + 4, fish[i].y))
            }
            let gone = fish[i].x < -30 || fish[i].x > Double(cols + 30) || (sp.junk && fish[i].age > 50)
            if gone {
                fish.remove(at: i)
                if let h = hooked, h > i { hooked = h - 1 }
                continue
            }
            i += 1
        }
    }

    private func moveParticles(_ dt: Double) {
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            if particles[i].bubble {
                particles[i].x += sin(time * 6 + Double(i)) * 4 * dt
                if particles[i].y < half + 1 { particles[i].life = 0 }
            } else {
                particles[i].vy += 120 * dt
            }
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func splash(at x: Double) {
        for _ in 0..<10 {
            particles.append(Particle(x: x + Double.random(in: -2...2), y: half - 1, vx: Double.random(in: -24...24),
                                      vy: Double.random(in: -70 ... -30), life: 0.6, color: Bool.random() ? 0xFFFFFF : 0xA8E4FF, bubble: false))
        }
    }

    // MARK: Démo (captures et vidéo)

    func demo() {
        coins = max(coins, 260)
        populate(3)
        cast(power: 0.62)
    }

    func demoBite() {
        guard phase == .sinking || phase == .flying else { return }
        if phase == .flying { lureY = depthY(0.55); phase = .sinking }
        lureY = max(lureY, depthY(0.5))
        let candidates = fish.indices.filter { !FishSpecies.all[fish[$0].species].junk }
        guard let i = candidates.min(by: { abs(fish[$0].y - lureY) < abs(fish[$1].y - lureY) }) else { return }
        fish[i].x = lureX - 4
        fish[i].y = lureY
        fish[i].vx = 1
        bite(i)
    }
}
