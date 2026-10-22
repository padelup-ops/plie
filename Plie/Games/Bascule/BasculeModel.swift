import Foundation
import Observation

// MARK: - Niveaux
//
// Plateau 1 × 1, y vers le HAUT, la charnière du Duo est la ligne x = 0,5.
// Même physique que tools/bascule_gen.py (mêmes constantes, même ordre des calculs).

struct BPt {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

struct BasculeWall {
    let ax: Double
    let ay: Double
    let bx: Double
    let by: Double

    init(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) {
        self.ax = ax
        self.ay = ay
        self.bx = bx
        self.by = by
    }
}

/// Ressort horizontal : la bille rebondit dessus.
struct BasculePad {
    let x1: Double
    let x2: Double
    let y: Double

    init(_ x1: Double, _ x2: Double, _ y: Double) {
        self.x1 = x1
        self.x2 = x2
        self.y = y
    }
}

struct BasculeBasket {
    let x1: Double
    let x2: Double
    let top: Double

    init(_ x1: Double, _ x2: Double, _ top: Double) {
        self.x1 = x1
        self.x2 = x2
        self.top = top
    }
}

struct BasculeLevel {
    let number: Int
    let world: Int
    let pivotY: Double
    let drop: Double
    let wind: Double
    let basket: BasculeBasket
    let walls: [BasculeWall]
    let pads: [BasculePad]
    let stars: [BPt]
    let preview: Bool
    let solution: Double

    static let worldCount = 3

    static func worldName(_ world: Int) -> String {
        switch world {
        case 1: return L("Premier saut")
        case 2: return L("Coup de vent")
        default: return L("Rebonds")
        }
    }

    /// Point de départ de la bille (haut de la pente).
    var startPoint: BPt { BPt(0.1, pivotY + drop) }

    var tip: String? {
        guard let first = BasculeLevel.all.first(where: { $0.world == world }), first.number == number else { return nil }
        switch world {
        case 1: return L("Le pli règle le tremplin : plus tu fermes ton Duo, plus il se relève. Vise le panier, puis lâche la bille.")
        case 2: return L("Le vent pousse la bille pendant son vol. Regarde le sens des flèches avant de viser.")
        case 3: return L("Le panier n'est accessible qu'en rebondissant sur le ressort vert.")
        default: return nil
        }
    }
}

// MARK: - Physique

enum BasculeEngine {
    static let gravity = 2.0
    static let dt = 1.0 / 240.0
    static let maxSteps = 240 * 6
    static let rampLength = 0.18
    static let ballRadius = 0.018
    static let starRadius = 0.03
    static let alphaMin = -25.0
    static let alphaMax = 65.0
    static let bounce = 0.9
    static let basketDepth = 0.06

    enum Outcome: Equatable {
        case flying, win, short, wall, out
    }

    struct Flight {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var stars: Set<Int> = []
        var bounced = false
        var steps = 0
        var outcome: Outcome = .flying
    }

    /// Angle du tremplin à partir de l'ouverture (0 = Duo plié en L, 1 = à plat).
    static func alpha(fromFraction f: Double) -> Double {
        alphaMax - f * (alphaMax - alphaMin)
    }

    static func rampTip(_ level: BasculeLevel, alpha: Double) -> BPt {
        let a = alpha * .pi / 180
        return BPt(0.5 + rampLength * cos(a), level.pivotY + rampLength * sin(a))
    }

    static func basketWalls(_ b: BasculeBasket) -> [BasculeWall] {
        let bottom = b.top - basketDepth
        return [BasculeWall(b.x1, b.top, b.x1, bottom), BasculeWall(b.x1, bottom, b.x2, bottom), BasculeWall(b.x2, bottom, b.x2, b.top)]
    }

    static func pointSegmentDistance(_ px: Double, _ py: Double, _ w: BasculeWall) -> Double {
        let ex = w.bx - w.ax
        let ey = w.by - w.ay
        let l2 = ex * ex + ey * ey
        if l2 == 0 {
            return ((px - w.ax) * (px - w.ax) + (py - w.ay) * (py - w.ay)).squareRoot()
        }
        let u = max(0.0, min(1.0, ((px - w.ax) * ex + (py - w.ay) * ey) / l2))
        let qx = w.ax + u * ex
        let qy = w.ay + u * ey
        return ((px - qx) * (px - qx) + (py - qy) * (py - qy)).squareRoot()
    }

    /// Sortie du tremplin. Renvoie un vol déjà terminé (.short) si la bille n'a pas assez d'élan.
    static func launch(_ level: BasculeLevel, alpha: Double) -> Flight {
        let v0sq = 2 * gravity * level.drop
        let a = alpha * .pi / 180
        let v1sq = v0sq - 2 * gravity * rampLength * sin(a)
        if v1sq <= 0 {
            var f = Flight(x: 0.5, y: level.pivotY, vx: 0, vy: 0)
            f.outcome = .short
            return f
        }
        let v1 = v1sq.squareRoot()
        return Flight(x: 0.5 + rampLength * cos(a), y: level.pivotY + rampLength * sin(a), vx: v1 * cos(a), vy: v1 * sin(a))
    }

    /// Un pas de vol, dans le même ordre que le générateur.
    static func step(_ f: inout Flight, level: BasculeLevel, walls: [BasculeWall]) {
        guard f.outcome == .flying else { return }
        if f.steps >= maxSteps {
            f.outcome = .out
            return
        }
        f.steps += 1
        f.vx += level.wind * dt
        f.vy -= gravity * dt
        let nx = f.x + f.vx * dt
        var ny = f.y + f.vy * dt
        let r = ballRadius
        for pad in level.pads {
            if f.vy < 0 && f.y >= pad.y + r && ny < pad.y + r && pad.x1 <= nx && nx <= pad.x2 {
                ny = pad.y + r
                f.vy = -f.vy * bounce
                f.bounced = true
            }
        }
        let b = level.basket
        if f.vy < 0 && f.y >= b.top && ny < b.top && b.x1 + r <= nx && nx <= b.x2 - r {
            f.x = nx
            f.y = ny
            f.outcome = .win
            return
        }
        for w in walls {
            if nx < min(w.ax, w.bx) - r || nx > max(w.ax, w.bx) + r || ny < min(w.ay, w.by) - r || ny > max(w.ay, w.by) + r {
                continue
            }
            if pointSegmentDistance(nx, ny, w) < r {
                f.x = nx
                f.y = ny
                f.outcome = .wall
                return
            }
        }
        for (index, s) in level.stars.enumerated() {
            let d = ((nx - s.x) * (nx - s.x) + (ny - s.y) * (ny - s.y)).squareRoot()
            if d < r + starRadius {
                f.stars.insert(index)
            }
        }
        if nx < -0.05 || nx > 1.05 || ny < 0 || ny > 1.6 {
            f.outcome = .out
            return
        }
        f.x = nx
        f.y = ny
    }

    static func allWalls(_ level: BasculeLevel) -> [BasculeWall] {
        level.walls + basketWalls(level.basket)
    }

    static func simulate(_ level: BasculeLevel, alpha: Double) -> Flight {
        var f = launch(level, alpha: alpha)
        let walls = allWalls(level)
        while f.outcome == .flying {
            step(&f, level: level, walls: walls)
        }
        return f
    }

    /// Début de trajectoire, pour l'aide à la visée des premiers niveaux.
    static func preview(_ level: BasculeLevel, alpha: Double, steps: Int = 100) -> [BPt] {
        var f = launch(level, alpha: alpha)
        guard f.outcome == .flying else { return [] }
        var points: [BPt] = []
        let copy = BasculeLevel(number: level.number, world: level.world, pivotY: level.pivotY, drop: level.drop, wind: level.wind,
                            basket: BasculeBasket(5, 5.1, -5), walls: [], pads: level.pads, stars: [], preview: level.preview,
                            solution: level.solution)
        for i in 0..<steps {
            step(&f, level: copy, walls: [])
            if f.outcome != .flying { break }
            if i % 7 == 0 { points.append(BPt(f.x, f.y)) }
        }
        return points
    }

    #if DEBUG
    static func selfCheck() -> (ok: Int, failures: [String]) {
        var ok = 0
        var failures: [String] = []
        for level in BasculeLevel.all {
            let f = simulate(level, alpha: level.solution)
            if f.outcome == .win && f.stars.count == 3 {
                ok += 1
            } else {
                failures.append(L("BASCULE \(level.number): \(f.outcome) étoiles=\(f.stars.count)"))
            }
        }
        return (ok, failures)
    }
    #endif
}

// MARK: - Partie

@Observable
final class BasculeSession {
    enum Phase: Equatable {
        case aiming
        case rolling
        case flying
        case missed
        case won
    }

    let level: BasculeLevel
    /// Angle visé (suit la charnière ou le doigt), et angle affiché (suit en douceur).
    var targetAlpha: Double
    private(set) var alpha: Double
    private(set) var phase: Phase = .aiming
    private(set) var ballX: Double
    private(set) var ballY: Double
    private(set) var collected: Set<Int> = []
    private(set) var attempts = 0
    private(set) var bestStars = 0
    private(set) var message: String?
    private(set) var clock: Double = 0
    private(set) var previewPoints: [BPt] = []

    @ObservationIgnored private var flight: BasculeEngine.Flight?
    @ObservationIgnored private var rollTime: Double = 0
    @ObservationIgnored private var lockedAlpha: Double = 0
    @ObservationIgnored private var walls: [BasculeWall]
    @ObservationIgnored private var previewAlpha: Double = 1000

    static let slopeDuration = 0.45
    static let rampDuration = 0.22

    init(level: BasculeLevel) {
        self.level = level
        let start = 20.0
        self.targetAlpha = start
        self.alpha = start
        self.ballX = level.startPoint.x
        self.ballY = level.startPoint.y
        self.walls = BasculeEngine.allWalls(level)
    }

    var canLaunch: Bool { phase == .aiming || phase == .missed }

    func setTarget(_ value: Double) {
        guard canLaunch else { return }
        targetAlpha = min(BasculeEngine.alphaMax, max(BasculeEngine.alphaMin, value))
    }

    func launch() {
        guard canLaunch else { return }
        lockedAlpha = alpha
        collected = []
        message = nil
        rollTime = 0
        flight = nil
        ballX = level.startPoint.x
        ballY = level.startPoint.y
        attempts += 1
        phase = .rolling
        Haptics.tap()
        SoundPlayer.shared.play(.whoosh, volume: 0.5)
    }

    func tick(dt: Double) {
        clock += dt
        switch phase {
        case .aiming, .missed:
            alpha += (targetAlpha - alpha) * min(1, dt * 14)
            if level.preview && abs(alpha - previewAlpha) > 0.05 {
                previewAlpha = alpha
                previewPoints = BasculeEngine.preview(level, alpha: alpha)
            }
        case .rolling:
            rollTime += dt
            let start = level.startPoint
            if rollTime < Self.slopeDuration {
                let p = rollTime / Self.slopeDuration
                let e = p * p
                ballX = start.x + (0.5 - start.x) * e
                ballY = start.y + (level.pivotY - start.y) * e
            } else {
                let p = min(1, (rollTime - Self.slopeDuration) / Self.rampDuration)
                let tip = BasculeEngine.rampTip(level, alpha: lockedAlpha)
                ballX = 0.5 + (tip.x - 0.5) * p
                ballY = level.pivotY + (tip.y - level.pivotY) * p
                if p >= 1 {
                    let f = BasculeEngine.launch(level, alpha: lockedAlpha)
                    if f.outcome == .short {
                        miss(L("Pas assez d'élan : baisse le tremplin."))
                    } else {
                        flight = f
                        phase = .flying
                    }
                }
            }
        case .flying:
            guard var f = flight else { return }
            let steps = max(1, Int((dt / BasculeEngine.dt).rounded()))
            for _ in 0..<steps {
                BasculeEngine.step(&f, level: level, walls: walls)
                if f.outcome != .flying { break }
            }
            if f.stars.count > collected.count {
                Haptics.tap()
                SoundPlayer.shared.play(.pop, volume: 0.8)
            }
            collected = f.stars
            ballX = f.x
            ballY = f.y
            flight = f
            switch f.outcome {
            case .win:
                phase = .won
                bestStars = max(bestStars, f.stars.count)
                Haptics.success()
                SoundPlayer.shared.play(.win)
            case .wall:
                miss(L("Bing ! Un mur. Essaie un autre angle."))
            case .out:
                miss(L("Raté ! Ajuste le tremplin."))
            case .short:
                miss(L("Pas assez d'élan : baisse le tremplin."))
            case .flying:
                break
            }
        case .won:
            break
        }
    }

    private func miss(_ text: String) {
        phase = .missed
        message = text
        Haptics.error()
        SoundPlayer.shared.play(.wrong, volume: 0.6)
    }

    func resetBall() {
        ballX = level.startPoint.x
        ballY = level.startPoint.y
    }
}
