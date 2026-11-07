import SwiftUI

extension Theme {
    static let cascade = Color(hex: 0xFFB13D)
}

// MARK: - CASCADE
//
// Duo plié en L : sur la moitié debout, les pièces tombent et rebondissent sur les clous ;
// elles traversent la charnière et atterrissent sur le plateau posé à plat, où le poussoir
// les fait glisser. Celles qui tombent du bord avant rapportent. Avec les gains, on améliore
// la machine. Plier et déplier d'un coup secoue le plateau.

struct CascadeCoin {
    enum Kind: Int { case silver, gold, gem }
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var kind: Kind
    /// Le disque tourne en tombant (pour le dessin).
    var spin: Double = 0
}

struct CascadePop {
    var x: Double
    var y: Double
    var text: String
    var life: Double
    var gold: Bool
}

enum CascadeUpgrade: String, CaseIterable, Identifiable {
    case dropSpeed, auto, pushSpeed, pushReach, value, gold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dropSpeed: return L("Cadence")
        case .auto: return L("Auto")
        case .pushSpeed: return L("Poussoir")
        case .pushReach: return L("Portée")
        case .value: return L("Valeur")
        case .gold: return L("Or")
        }
    }

    var symbol: String {
        switch self {
        case .dropSpeed: return "hare.fill"
        case .auto: return "repeat"
        case .pushSpeed: return "arrow.down.to.line"
        case .pushReach: return "arrow.up.and.down"
        case .value: return "multiply"
        case .gold: return "sparkles"
        }
    }

    var maxLevel: Int {
        switch self {
        case .dropSpeed: return 20
        case .auto: return 30
        case .pushSpeed: return 15
        case .pushReach: return 15
        case .value: return 80
        case .gold: return 20
        }
    }

    func cost(_ level: Int) -> Double {
        let (base, growth): (Double, Double)
        switch self {
        case .dropSpeed: (base, growth) = (25, 1.55)
        case .auto: (base, growth) = (60, 1.58)
        case .pushSpeed: (base, growth) = (40, 1.62)
        case .pushReach: (base, growth) = (70, 1.66)
        case .value: (base, growth) = (35, 1.48)
        case .gold: (base, growth) = (90, 1.7)
        }
        return (base * pow(growth, Double(level))).rounded()
    }
}

@Observable
final class CascadeGame {
    static let coinR = 0.021
    /// Les pièces qui tombent sont dessinées plus grosses (elles sont plus près de nous).
    static let fallR = 0.03
    static let pegR = 0.008
    static let wall = 0.05
    static let maxBedCoins = 460
    static let maxFalling = 160

    // Économie
    private(set) var balance: Double = 0
    private(set) var levels: [CascadeUpgrade: Int] = [:]
    private(set) var perSecond: Double = 0
    private(set) var combo = 0
    private(set) var frenzy = 0.0
    private(set) var banner: String?
    private(set) var bannerTime = 0.0
    private(set) var welcomeBack: Double?
    private(set) var shakeReady = true

    // Le terrain : largeur 1, hauteur `height`. La charnière est au milieu.
    var height = 2.0 {
        didSet { if bed.isEmpty { fillBed() } }
    }
    /// Où s'arrête le plateau (au-dessus du tableau de bord).
    var edgeFraction = 0.78

    // La simulation bouge à chaque image : elle n'est pas observée pièce par pièce
    // (des milliers de notifications par image rendaient le jeu saccadé). Le dessin suit `frame`.
    @ObservationIgnored private(set) var falling: [CascadeCoin] = []
    @ObservationIgnored private(set) var bed: [CascadeCoin] = []
    @ObservationIgnored private(set) var pops: [CascadePop] = []
    @ObservationIgnored private(set) var pegs: [CGPoint] = []
    @ObservationIgnored private(set) var dropperX = 0.5
    @ObservationIgnored private(set) var pusherFront = 0.0
    @ObservationIgnored private(set) var time = 0.0
    /// La cible qui glisse en bas de la moitié debout : la traverser lâche une pluie de pièces.
    @ObservationIgnored private(set) var gateX = 0.5
    /// Change à chaque image : c'est ce que le dessin observe.
    private(set) var frame = 0
    /// Secousse en cours (pour faire trembler l'image).
    @ObservationIgnored private(set) var shakeTime = 0.0
    @ObservationIgnored private var gridHead: [Int] = []
    @ObservationIgnored private var gridNext: [Int] = []

    @ObservationIgnored private var dropCooldown = 0.0
    @ObservationIgnored private var autoAccumulator = 0.0
    @ObservationIgnored private var comboTime = 0.0
    @ObservationIgnored private var earnedWindow: [(t: Double, v: Double)] = []
    @ObservationIgnored private var saveTimer = 0.0
    @ObservationIgnored private var lastPusher = 0.0
    @ObservationIgnored private var shakeCooldown = 0.0
    @ObservationIgnored private var lastAngle: Double?
    @ObservationIgnored private var angleHistory: [(t: Double, a: Double)] = []
    @ObservationIgnored private var pegsHeight = 0.0
    @ObservationIgnored private var soundBudget = 0.0

    init() {
        load()
    }

    // MARK: Géométrie

    var half: Double { height / 2 }
    var bedTop: Double { half }
    var bedEdge: Double { half + half * edgeFraction }

    func level(_ u: CascadeUpgrade) -> Int { levels[u] ?? 0 }

    var dropInterval: Double { max(0.04, 0.3 * pow(0.86, Double(level(.dropSpeed)))) }
    var autoRate: Double { Double(level(.auto)) * 0.55 * (frenzy > 0 ? 3 : 1) }
    var pushPeriod: Double { max(0.75, 2.6 * pow(0.925, Double(level(.pushSpeed)))) }
    var pushReach: Double { min(0.42, 0.16 + 0.017 * Double(level(.pushReach))) * half }
    var coinValue: Double { pow(1.32, Double(level(.value))) }
    var goldChance: Double { min(0.45, 0.04 + 0.02 * Double(level(.gold))) }
    var comboMultiplier: Double { min(5, 1 + Double(combo) / 400) }

    func canBuy(_ u: CascadeUpgrade) -> Bool {
        level(u) < u.maxLevel && balance >= u.cost(level(u))
    }

    // MARK: Actions

    func buy(_ u: CascadeUpgrade) {
        guard canBuy(u) else { Haptics.error(); return }
        balance -= u.cost(level(u))
        levels[u] = level(u) + 1
        Haptics.tap()
        SoundPlayer.shared.play(.chime, volume: 0.5)
        save()
    }

    /// Le bouton LÂCHER.
    func drop() {
        guard dropCooldown <= 0 else { return }
        dropCooldown = dropInterval
        spawn()
        Haptics.tap()
    }

    func dismissWelcome() { welcomeBack = nil }

    /// La charnière bouge : un pli rapide (aller-retour) secoue le plateau.
    func hinge(_ degrees: Double?) {
        guard let degrees else { return }
        angleHistory.append((time, degrees))
        angleHistory.removeAll { time - $0.t > 0.6 }
        guard shakeCooldown <= 0, let lo = angleHistory.map(\.a).min(), let hi = angleHistory.map(\.a).max(), hi - lo > 22 else { return }
        // On secoue seulement quand le Duo revient vers sa position (aller-retour).
        if let first = angleHistory.first?.a, abs(degrees - first) < 10 {
            shake()
        }
    }

    func shake() {
        guard shakeCooldown <= 0 else { return }
        shakeCooldown = 12
        shakeReady = false
        for i in bed.indices {
            bed[i].vy += Double.random(in: 0.18...0.42)
            bed[i].vx += Double.random(in: -0.12...0.12)
        }
        show(L("SECOUSSE !"))
        shakeTime = 0.45
        Haptics.success()
        SoundPlayer.shared.play(.thud)
    }

    // MARK: Boucle

    func tick(dt rawDt: Double) {
        let dt = min(rawDt, 1.0 / 30.0)
        time += dt
        dropCooldown -= dt
        if shakeCooldown > 0 {
            shakeCooldown -= dt
            if shakeCooldown <= 0 { shakeReady = true }
        }
        if frenzy > 0 { frenzy = max(0, frenzy - dt) }
        if shakeTime > 0 { shakeTime = max(0, shakeTime - dt) }
        if bannerTime > 0 {
            bannerTime -= dt
            if bannerTime <= 0 { banner = nil }
        }
        soundBudget = min(6, soundBudget + dt * 18)
        if pegs.isEmpty || abs(pegsHeight - height) > 0.001 { layoutPegs() }

        // La trémie glisse de gauche à droite ; la cible aussi, plus lentement.
        dropperX = 0.5 + 0.36 * sin(time * 1.25)
        gateX = 0.5 + 0.3 * sin(time * 0.7 + 1.3)

        // Lâcher automatique
        autoAccumulator += autoRate * dt
        while autoAccumulator >= 1 {
            autoAccumulator -= 1
            spawn()
        }

        // Le poussoir avance et recule.
        let phase = (sin(time * 2 * .pi / pushPeriod) + 1) / 2
        pusherFront = bedTop + 0.05 * half + pushReach * phase
        let pusherSpeed = (pusherFront - lastPusher) / max(dt, 0.0001)
        lastPusher = pusherFront

        stepFalling(dt)
        stepBed(dt, pusherSpeed: pusherSpeed)

        // Combo : il retombe si plus rien ne tombe pendant un moment.
        comboTime -= dt
        if comboTime <= 0 && combo > 0 { combo = 0 }

        for i in pops.indices {
            pops[i].life -= dt
            pops[i].y -= dt * 0.12
        }
        pops.removeAll { $0.life <= 0 }

        earnedWindow.removeAll { time - $0.t > 3 }
        perSecond = earnedWindow.reduce(0) { $0 + $1.v } / 3

        saveTimer += dt
        if saveTimer > 5 {
            saveTimer = 0
            save()
        }
        frame &+= 1
    }

    private func layoutPegs() {
        pegsHeight = height
        var p: [CGPoint] = []
        let top = 0.2 * half + 0.05
        let bottom = half * 0.82
        let rows = max(5, Int((bottom - top) / 0.062))
        for r in 0..<rows {
            let y = top + (bottom - top) * Double(r) / Double(max(1, rows - 1))
            let cols = r % 2 == 0 ? 10 : 9
            for c in 0..<cols {
                let x = Self.wall + 0.07 + (1 - 2 * Self.wall - 0.14) * (Double(c) + (r % 2 == 0 ? 0 : 0.5)) / 9
                p.append(CGPoint(x: x, y: y))
            }
        }
        pegs = p
    }

    private func spawn(x: Double? = nil, y: Double? = nil, burst: Bool = false) {
        guard falling.count < Self.maxFalling else { return }
        let roll = Double.random(in: 0...1)
        let kind: CascadeCoin.Kind = roll < 0.006 ? .gem : (roll < goldChance ? .gold : .silver)
        falling.append(CascadeCoin(x: (x ?? dropperX) + Double.random(in: -0.01...0.01),
                                   y: y ?? 0.12 * half,
                                   vx: burst ? Double.random(in: -0.35...0.35) : Double.random(in: -0.04...0.04),
                                   vy: burst ? Double.random(in: -0.5 ... -0.1) : 0.05,
                                   kind: kind))
    }

    private func stepFalling(_ dt: Double) {
        let g = 2.4
        let r = Self.fallR
        let gateY = half * 0.92
        var landed: [CascadeCoin] = []
        var bursts: [Double] = []
        var pegPaid = 0.0
        for i in falling.indices.reversed() {
            var c = falling[i]
            let oldY = c.y
            c.vy += g * dt
            c.x += c.vx * dt
            c.y += c.vy * dt
            c.spin += dt * 6
            // Murs
            if c.x < Self.wall + r { c.x = Self.wall + r; c.vx = abs(c.vx) * 0.5 }
            if c.x > 1 - Self.wall - r { c.x = 1 - Self.wall - r; c.vx = -abs(c.vx) * 0.5 }
            // Clous
            for p in pegs {
                let dx = c.x - p.x, dy = c.y - p.y
                let d2 = dx * dx + dy * dy
                let lim = r + Self.pegR
                if d2 < lim * lim && d2 > 0.0000001 {
                    let d = sqrt(d2)
                    let nx = dx / d, ny = dy / d
                    c.x = p.x + nx * lim
                    c.y = p.y + ny * lim
                    let dot = c.vx * nx + c.vy * ny
                    if dot < 0 {
                        c.vx -= 1.5 * dot * nx
                        c.vy -= 1.5 * dot * ny
                        c.vx += Double.random(in: -0.05...0.05)
                        c.vx *= 0.8
                        c.vy *= 0.6
                        // Chaque clou touché rapporte un peu (et nourrit le combo).
                        let hit = 0.2 * coinValue * (c.kind == .gold ? 10 : 1) * comboMultiplier * (frenzy > 0 ? 2 : 1)
                        pegPaid += hit
                        combo += 1
                        comboTime = 1.6
                        if pops.count < 6 && Double.random(in: 0...1) < 0.05 {
                            pops.append(CascadePop(x: p.x, y: p.y - 0.02, text: "+" + Self.format(hit), life: 0.6, gold: c.kind != .silver))
                        }
                        if soundBudget > 1 && Double.random(in: 0...1) < 0.25 {
                            soundBudget -= 1
                            SoundPlayer.shared.play(.tock, volume: 0.18)
                        }
                    }
                }
            }
            // La cible mobile
            if oldY < gateY && c.y >= gateY && abs(c.x - gateX) < 0.07 {
                bursts.append(c.x)
            }
            if c.y >= half {
                landed.append(c)
                falling.remove(at: i)
            } else {
                falling[i] = c
            }
        }
        if pegPaid > 0 {
            balance += pegPaid
            earnedWindow.append((time, pegPaid))
        }
        for x in bursts {
            for _ in 0..<4 { spawn(x: x, y: gateY - 0.02, burst: true) }
            // Un seul « ×4 » à la fois : sinon, en CASCADE, ils s'empilent en une tache jaune.
            if !pops.contains(where: { $0.text == "×4" }) {
                pops.append(CascadePop(x: x, y: gateY, text: "×4", life: 0.9, gold: true))
            }
            Haptics.tap()
            if soundBudget > 1 { soundBudget -= 1; SoundPlayer.shared.play(.pop, volume: 0.5) }
        }
        // Les pièces tombent sur le plateau, juste devant le poussoir.
        for var c in landed where bed.count < Self.maxBedCoins {
            c.y = pusherFront + Self.coinR + Double.random(in: 0...0.03)
            c.vy = 0.05
            c.vx *= 0.3
            bed.append(c)
        }
    }

    private func stepBed(_ dt: Double, pusherSpeed: Double) {
        let r = Self.coinR
        let edge = bedEdge
        // Le poussoir : il pousse tout ce qui est derrière son bord avant.
        for i in bed.indices {
            var c = bed[i]
            if c.y < pusherFront + r {
                c.y = pusherFront + r
                if pusherSpeed > 0 { c.vy = max(c.vy, pusherSpeed) }
            }
            c.x += c.vx * dt
            c.y += c.vy * dt
            c.vx *= pow(0.02, dt)
            c.vy *= pow(0.02, dt)
            if c.x < Self.wall + r { c.x = Self.wall + r; c.vx = 0 }
            if c.x > 1 - Self.wall - r { c.x = 1 - Self.wall - r; c.vx = 0 }
            bed[i] = c
        }
        // Les pièces se poussent entre elles. Grille fixe (listes chaînées dans des tableaux) :
        // aucune allocation par image, pour rester fluide avec des centaines de pièces.
        let cell = 2 * r
        let cols = Int(1 / cell) + 2
        let rows = Int(height / cell) + 2
        let n = bed.count
        let lim = 2 * r * 0.86
        let blockY = pusherFront + r + 0.0005
        for _ in 0..<2 {
            if gridHead.count != cols * rows { gridHead = Array(repeating: -1, count: cols * rows) }
            else { for k in gridHead.indices { gridHead[k] = -1 } }
            if gridNext.count < n { gridNext = Array(repeating: -1, count: n + 64) }
            for i in 0..<n {
                let cx = min(cols - 1, max(0, Int(bed[i].x / cell))), cy = min(rows - 1, max(0, Int(bed[i].y / cell)))
                let k = cy * cols + cx
                gridNext[i] = gridHead[k]
                gridHead[k] = i
            }
            for i in 0..<n {
                let gx = min(cols - 1, max(0, Int(bed[i].x / cell))), gy = min(rows - 1, max(0, Int(bed[i].y / cell)))
                for oy in -1...1 {
                    let yy = gy + oy
                    if yy < 0 || yy >= rows { continue }
                    for ox in -1...1 {
                        let xx = gx + ox
                        if xx < 0 || xx >= cols { continue }
                        var j = gridHead[yy * cols + xx]
                        while j >= 0 {
                            if j > i {
                                let dx = bed[j].x - bed[i].x, dy = bed[j].y - bed[i].y
                                let d2 = dx * dx + dy * dy
                                if d2 < lim * lim {
                                    let d = max(0.0001, sqrt(d2))
                                    let push = (lim - d) / 2
                                    let nx = d2 < 0.0000001 ? 1 : dx / d, ny = d2 < 0.0000001 ? 0 : dy / d
                                    // La pièce contre le poussoir ne recule pas : l'autre prend tout.
                                    let iBlocked = bed[i].y <= blockY, jBlocked = bed[j].y <= blockY
                                    let wi = iBlocked && !jBlocked ? 0.0 : (jBlocked && !iBlocked ? 2.0 : 1.0)
                                    let wj = 2 - wi
                                    bed[i].x -= nx * push * wi
                                    bed[i].y -= ny * push * wi
                                    bed[j].x += nx * push * wj
                                    bed[j].y += ny * push * wj
                                    let rel = (bed[i].vy - bed[j].vy) * 0.5
                                    if rel > 0 { bed[j].vy += rel; bed[i].vy -= rel }
                                }
                            }
                            j = gridNext[j]
                        }
                    }
                }
            }
            // Personne ne passe à travers les murs après les poussées.
            for i in 0..<n {
                if bed[i].x < Self.wall + r { bed[i].x = Self.wall + r }
                if bed[i].x > 1 - Self.wall - r { bed[i].x = 1 - Self.wall - r }
                if bed[i].y < pusherFront + r { bed[i].y = pusherFront + r }
            }
        }
        // Le bord avant : ça rapporte. Les côtés, près du bord : perdues.
        var paid = 0.0
        var count = 0
        var gem = false
        bed.removeAll { c in
            guard c.y > edge else { return false }
            if c.x < Self.wall + 0.09 || c.x > 1 - Self.wall - 0.09 {
                return true
            }
            let base = c.kind == .gold ? 10.0 : (c.kind == .gem ? 250.0 : 1.0)
            let v = base * coinValue * comboMultiplier * (frenzy > 0 ? 2 : 1)
            paid += v
            count += 1
            if c.kind == .gem { gem = true }
            if pops.count < 8 {
                pops.append(CascadePop(x: c.x, y: edge, text: "+" + Self.format(v), life: 0.8, gold: c.kind != .silver))
            }
            return true
        }
        if count > 0 {
            balance += paid
            earnedWindow.append((time, paid))
            combo += count * 5
            comboTime = 1.6
            if soundBudget > 1 {
                soundBudget -= 1
                SoundPlayer.shared.play(.clack, volume: 0.45)
            }
            if combo >= 1000 && combo % 1000 < count + 8 && bannerTime <= 0 { show(L("COMBO \(combo) !")) }
        }
        if gem {
            frenzy = 12
            show(L("CASCADE !"))
            Haptics.success()
            SoundPlayer.shared.play(.win, volume: 0.7)
        }
    }

    private func show(_ text: String) {
        banner = text
        bannerTime = 1.6
    }

    /// Le plateau commence déjà bien rempli.
    private func fillBed() {
        guard height > 0.5 else { return }
        let r = Self.coinR
        var y = bedTop + 0.05 * half + r
        var row = 0
        while y < bedEdge - 0.02 && bed.count < 260 {
            var x = Self.wall + r + (row % 2 == 0 ? 0 : r)
            while x < 1 - Self.wall - r {
                let kind: CascadeCoin.Kind = Double.random(in: 0...1) < 0.08 ? .gold : .silver
                bed.append(CascadeCoin(x: x + Double.random(in: -0.004...0.004), y: y, vx: 0, vy: 0, kind: kind))
                x += 2 * r * 1.05
            }
            y += 2 * r * 0.95
            row += 1
        }
        lastPusher = bedTop
    }

    // MARK: Nombres

    static func format(_ v: Double) -> String {
        let units = ["", "K", "M", "B", "T", "Qa", "Qi"]
        var n = v
        var i = 0
        while n >= 1000 && i < units.count - 1 {
            n /= 1000
            i += 1
        }
        if i == 0 { return String(Int(n.rounded())) }
        let s = n >= 100 ? String(format: "%.0f", n) : (n >= 10 ? String(format: "%.1f", n) : String(format: "%.2f", n))
        return s + units[i]
    }

    // MARK: Sauvegarde

    private enum Keys {
        static let balance = "cascade.balance"
        static let levels = "cascade.levels"
        static let seen = "cascade.lastSeen"
    }

    func save() {
        let d = UserDefaults.standard
        d.set(balance, forKey: Keys.balance)
        d.set(Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) }), forKey: Keys.levels)
        d.set(Date().timeIntervalSince1970, forKey: Keys.seen)
    }

    private func load() {
        let d = UserDefaults.standard
        balance = d.double(forKey: Keys.balance)
        if d.object(forKey: Keys.levels) == nil { levels[.auto] = 1 }
        if let raw = d.dictionary(forKey: Keys.levels) as? [String: Int] {
            for (k, v) in raw { if let u = CascadeUpgrade(rawValue: k) { levels[u] = v } }
        }
        // Pendant l'absence, le lâcher automatique a continué (au ralenti, 2 heures au plus).
        let seen = d.double(forKey: Keys.seen)
        if seen > 0, level(.auto) > 0 {
            let away = min(7200, Date().timeIntervalSince1970 - seen)
            if away > 60 {
                let avg = (1 - goldChance) + goldChance * 10
                let gain = (Double(level(.auto)) * 0.55 * away * 0.35 * avg * coinValue).rounded()
                if gain >= 1 {
                    balance += gain
                    welcomeBack = gain
                }
            }
        }
    }

    #if DEBUG
    /// Captures : une machine déjà bien avancée.
    func demoRich() {
        balance = 8_400_000
        for u in CascadeUpgrade.allCases { levels[u] = min(u.maxLevel, u == .value ? 33 : 14) }
        for _ in 0..<40 { spawn(x: Double.random(in: 0.15...0.85), y: Double.random(in: 0.1...0.8) * half) }
        frenzy = 6
        combo = 240
        show(L("CASCADE !"))
    }
    #endif
}
