import SwiftUI

extension Theme {
    static let golf = Color(hex: 0x6BD35A)
}

// MARK: - MINIGOLF
//
// Le parcours passe d'un écran à l'autre. La moitié à plat reste plate ; quand on plie le Duo,
// la moitié du haut se relève et devient une pente : la balle y roule vers la charnière,
// comme sur un vrai terrain incliné. Chaque trou se joue aussi Duo à plat, comme un minigolf normal.
//
// Coordonnées des trous : x de 0 à 1, y de 0 à 2 (de 0 à 1 la moitié du haut, de 1 à 2 celle du bas,
// la charnière à y = 1). Le jeu les place sur l'écran réel.

struct GolfRect {
    let x: Double, y: Double, w: Double, h: Double
}

struct GolfMover {
    let rect: GolfRect
    /// Déplacement de gauche à droite (en largeur d'écran) et durée d'un aller-retour.
    let dx: Double
    let period: Double
}

struct GolfHole {
    let par: Int
    let tee: (x: Double, y: Double)
    let cup: (x: Double, y: Double)
    var walls: [GolfRect] = []
    var sand: [GolfRect] = []
    var water: [GolfRect] = []
    var movers: [GolfMover] = []

    static let all: [GolfHole] = [
        // 1. Tout droit, par-dessus la charnière
        GolfHole(par: 2, tee: (0.5, 1.8), cup: (0.5, 0.3)),
        // 2. Le zigzag
        GolfHole(par: 3, tee: (0.2, 1.85), cup: (0.8, 0.2),
                 walls: [GolfRect(x: 0, y: 1.35, w: 0.65, h: 0.06), GolfRect(x: 0.35, y: 0.6, w: 0.65, h: 0.06)]),
        // 3. Le bunker
        GolfHole(par: 3, tee: (0.5, 1.85), cup: (0.5, 0.22),
                 walls: [GolfRect(x: 0.3, y: 1.25, w: 0.4, h: 0.05)],
                 sand: [GolfRect(x: 0.18, y: 0.42, w: 0.64, h: 0.24)]),
        // 4. La mare : on passe par le haut, la pente ramène la balle
        GolfHole(par: 3, tee: (0.15, 1.8), cup: (0.85, 1.75),
                 water: [GolfRect(x: 0.33, y: 1.3, w: 0.34, h: 0.7)]),
        // 5. La poche : le trou est au fond d'un U
        GolfHole(par: 3, tee: (0.5, 1.85), cup: (0.5, 0.16),
                 walls: [GolfRect(x: 0.3, y: 0.04, w: 0.05, h: 0.38), GolfRect(x: 0.65, y: 0.04, w: 0.05, h: 0.38)],
                 water: [GolfRect(x: 0, y: 0.78, w: 0.33, h: 0.4), GolfRect(x: 0.67, y: 0.78, w: 0.33, h: 0.4)]),
        // 6. Le couloir
        GolfHole(par: 4, tee: (0.13, 0.15), cup: (0.87, 1.85),
                 walls: [GolfRect(x: 0.3, y: 0, w: 0.06, h: 1.42), GolfRect(x: 0.64, y: 0.58, w: 0.06, h: 1.42)]),
        // 7. La barrière qui bouge, sur la charnière
        GolfHole(par: 2, tee: (0.5, 1.85), cup: (0.5, 0.2),
                 movers: [GolfMover(rect: GolfRect(x: 0.3, y: 0.97, w: 0.4, h: 0.06), dx: 0.28, period: 3)]),
        // 8. Les îles
        GolfHole(par: 3, tee: (0.5, 1.85), cup: (0.5, 0.18),
                 sand: [GolfRect(x: 0.25, y: 1.28, w: 0.5, h: 0.2)],
                 water: [GolfRect(x: 0, y: 0.52, w: 0.41, h: 0.26), GolfRect(x: 0.59, y: 0.52, w: 0.41, h: 0.26)]),
        // 9. La grande finale
        GolfHole(par: 5, tee: (0.1, 1.9), cup: (0.88, 0.1),
                 walls: [GolfRect(x: 0, y: 1.5, w: 0.75, h: 0.05), GolfRect(x: 0.25, y: 0.95, w: 0.75, h: 0.05), GolfRect(x: 0, y: 0.45, w: 0.75, h: 0.05)],
                 movers: [GolfMover(rect: GolfRect(x: 0.4, y: 0.2, w: 0.06, h: 0.2), dx: 0.3, period: 2.6)]),
    ]
}

@Observable
final class GolfGame {
    enum Phase: Equatable { case menu, aim, rolling, sinking, between, finished }

    static let ballRadius = 0.022
    static let cupRadius = 0.036

    private(set) var phase: Phase = .menu
    private(set) var frame = 0
    private(set) var hole = 0
    private(set) var player = 0
    private(set) var players = 1
    /// Coups par joueur et par trou.
    private(set) var cards: [[Int]] = [[], []]
    private(set) var strokes = 0
    private(set) var banner: String?
    private(set) var tiltDegrees: Double = 0
    private(set) var best: Int

    // Dessin et physique : lus à chaque image.
    @ObservationIgnored let cols = 144
    @ObservationIgnored private(set) var height: Double = 2.2
    @ObservationIgnored private(set) var topY: Double = 0.4
    @ObservationIgnored private(set) var botY: Double = 2.0
    @ObservationIgnored private(set) var time: Double = 0
    @ObservationIgnored private(set) var ball = (x: 0.5, y: 1.0)
    @ObservationIgnored private(set) var vel = (x: 0.0, y: 0.0)
    @ObservationIgnored private(set) var aim: (dx: Double, dy: Double, power: Double)?
    @ObservationIgnored private(set) var sinkT: Double = 0
    @ObservationIgnored private(set) var splashT: Double = 0
    @ObservationIgnored private var lastShot = (x: 0.5, y: 1.0)
    @ObservationIgnored private var restTime: Double = 0
    @ObservationIgnored private var bannerLeft: Double = 0
    @ObservationIgnored private var betweenLeft: Double = 0
    @ObservationIgnored private var hasHinge = false

    init() {
        best = UserDefaults.standard.integer(forKey: "golf.best")
    }

    var current: GolfHole { GolfHole.all[hole] }
    var half: Double { height / 2 }
    var totalPar: Int { GolfHole.all.reduce(0) { $0 + $1.par } }

    func total(_ p: Int) -> Int { cards[p].reduce(0, +) }

    // MARK: Mise en page

    func configure(height: Double, topReserve: Double, bottomReserve: Double) {
        self.height = max(1.2, height)
        topY = min(half - 0.4, max(0.08, topReserve))
        botY = max(half + 0.4, min(self.height - 0.04, self.height - bottomReserve))
        if phase == .menu { placeOnTee() }
    }

    /// y d'un trou (0 à 2) -> y à l'écran (en largeurs d'écran).
    func fy(_ y: Double) -> Double {
        y <= 1 ? topY + y * (half - topY) : half + (y - 1) * (botY - half)
    }

    func rect(_ r: GolfRect, dx: Double = 0) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        (r.x + dx, fy(r.y), r.x + r.w + dx, fy(r.y + r.h))
    }

    func moverOffset(_ m: GolfMover) -> Double { m.dx * sin(2 * .pi * time / m.period) }

    var cup: (x: Double, y: Double) { (current.cup.x, fy(current.cup.y)) }

    // MARK: Partie

    func start(players n: Int) {
        players = n
        cards = [[], []]
        hole = 0
        player = 0
        beginTurn()
        SoundPlayer.shared.play(.go, volume: 0.5)
    }

    func backToMenu() {
        phase = .menu
        banner = nil
    }

    private func placeOnTee() {
        ball = (x: current.tee.x, y: fy(current.tee.y))
        vel = (0, 0)
        lastShot = ball
    }

    private func beginTurn() {
        strokes = 0
        sinkT = 0
        placeOnTee()
        phase = .aim
        say(players > 1 ? L("Trou \(hole + 1) · Joueur \(player + 1)") : L("Trou \(hole + 1) · Par \(current.par)"))
    }

    private func say(_ text: String) {
        banner = text
        bannerLeft = 1.6
    }

    // MARK: Viser et tirer

    /// Le doigt tire en arrière (comme un lance-pierre) : la balle part dans l'autre sens.
    func drag(dx: Double, dy: Double) {
        guard phase == .aim else { return }
        let len = hypot(dx, dy)
        guard len > 4 else { aim = nil; return }
        aim = (dx: -dx / len, dy: -dy / len, power: min(1, len / 150))
    }

    func release() {
        guard phase == .aim, let a = aim else { aim = nil; return }
        aim = nil
        guard a.power > 0.06 else { return }
        shoot(dx: a.dx, dy: a.dy, power: a.power)
    }

    func shoot(dx: Double, dy: Double, power: Double) {
        guard phase == .aim else { return }
        let speed = 0.25 + power * 2.3
        vel = (dx * speed, dy * speed)
        lastShot = ball
        strokes += 1
        restTime = 0
        phase = .rolling
        SoundPlayer.shared.play(.tock, volume: 0.4 + Float(power) * 0.5)
        Haptics.tap()
    }

    // MARK: Charnière

    func hinge(_ degrees: Double?) {
        guard let degrees else { hasHinge = false; tiltDegrees = 0; return }
        hasHinge = true
        // Duo fermé : on garde la dernière pente (le jeu ne se joue pas fermé).
        guard degrees >= HingeMapping.openThreshold else { return }
        let t = min(90, max(0, 180 - degrees))
        tiltDegrees = t < 4 ? 0 : t
    }

    // MARK: Physique

    func tick(dt: Double) {
        frame &+= 1
        time += dt
        if bannerLeft > 0 {
            bannerLeft -= dt
            if bannerLeft <= 0 { banner = nil }
        }
        if splashT > 0 { splashT -= dt }
        switch phase {
        case .rolling:
            for _ in 0..<3 { step(dt / 3) }
        case .sinking:
            sinkT += dt
            ball.x += (cup.x - ball.x) * min(1, dt * 12)
            ball.y += (cup.y - ball.y) * min(1, dt * 12)
            if sinkT > 0.9 { holeDone() }
        case .between:
            betweenLeft -= dt
            if betweenLeft <= 0 { nextTurn() }
        case .aim:
            // La pente agit aussi sur une balle arrêtée.
            if ball.y < half && tiltDegrees > 0 && !blockedDownhill() {
                phase = .rolling
                restTime = 0
            }
        default:
            break
        }
    }

    private var slope: Double { sin(tiltDegrees * .pi / 180) }

    private func blockedDownhill() -> Bool {
        var probe = ball
        probe.y += Self.ballRadius * 0.6
        return collides(probe)
    }

    private func onSand(_ p: (x: Double, y: Double)) -> Bool {
        current.sand.contains { r in
            let q = rect(r)
            return p.x >= q.x0 && p.x <= q.x1 && p.y >= q.y0 && p.y <= q.y1
        }
    }

    private func inWater(_ p: (x: Double, y: Double)) -> Bool {
        current.water.contains { r in
            let q = rect(r)
            return p.x >= q.x0 && p.x <= q.x1 && p.y >= q.y0 && p.y <= q.y1
        }
    }

    private var solids: [(x0: Double, y0: Double, x1: Double, y1: Double)] {
        current.walls.map { rect($0) } + current.movers.map { rect($0.rect, dx: moverOffset($0)) }
    }

    private func collides(_ p: (x: Double, y: Double)) -> Bool {
        let r = Self.ballRadius
        if p.x < r || p.x > 1 - r || p.y < topY + r || p.y > botY - r { return true }
        for q in solids {
            let cx = min(max(p.x, q.x0), q.x1), cy = min(max(p.y, q.y0), q.y1)
            if hypot(p.x - cx, p.y - cy) < r { return true }
        }
        return false
    }

    private func step(_ dt: Double) {
        guard phase == .rolling else { return }
        let r = Self.ballRadius
        // La pente : seulement sur la moitié du haut, vers la charnière.
        if ball.y < half { vel.y += 1.5 * slope * dt }
        // Le frottement (bien plus fort dans le sable)
        let sand = onSand(ball)
        let keep = pow(sand ? 0.08 : 0.5, dt)
        vel.x *= keep
        vel.y *= keep
        var speed = hypot(vel.x, vel.y)
        if speed > 0 {
            let drop = min(speed, 0.05 * dt)
            vel.x -= vel.x / speed * drop
            vel.y -= vel.y / speed * drop
        }
        ball.x += vel.x * dt
        ball.y += vel.y * dt

        // Les bords
        var bounced = false
        if ball.x < r { ball.x = r; vel.x = abs(vel.x) * 0.75; bounced = true }
        if ball.x > 1 - r { ball.x = 1 - r; vel.x = -abs(vel.x) * 0.75; bounced = true }
        if ball.y < topY + r { ball.y = topY + r; vel.y = abs(vel.y) * 0.75; bounced = true }
        if ball.y > botY - r { ball.y = botY - r; vel.y = -abs(vel.y) * 0.75; bounced = true }
        // Les murs
        for q in solids {
            let cx = min(max(ball.x, q.x0), q.x1), cy = min(max(ball.y, q.y0), q.y1)
            var nx = ball.x - cx, ny = ball.y - cy
            var d = hypot(nx, ny)
            guard d < r else { continue }
            if d < 1e-6 {
                // Le centre est dans le mur : on sort par le côté le plus proche.
                let left = ball.x - q.x0, right = q.x1 - ball.x, up = ball.y - q.y0, down = q.y1 - ball.y
                let m = min(left, right, up, down)
                if m == left { nx = -1; ny = 0 } else if m == right { nx = 1; ny = 0 } else if m == up { nx = 0; ny = -1 } else { nx = 0; ny = 1 }
                d = 0
            } else {
                nx /= d
                ny /= d
            }
            ball.x = cx + nx * r
            ball.y = cy + ny * r
            let vn = vel.x * nx + vel.y * ny
            if vn < 0 {
                vel.x -= 1.75 * vn * nx
                vel.y -= 1.75 * vn * ny
                bounced = true
            }
        }
        if bounced && hypot(vel.x, vel.y) > 0.25 { SoundPlayer.shared.play(.pok, volume: 0.35) }

        // L'eau : la balle revient là d'où elle est partie, un coup de pénalité.
        if inWater(ball) {
            splashT = 0.5
            ball = lastShot
            vel = (0, 0)
            strokes += 1
            say(L("Plouf ! +1 coup"))
            SoundPlayer.shared.play(.splat, volume: 0.6)
            Haptics.error()
            phase = .aim
            return
        }

        // Le trou
        let c = cup
        let dc = hypot(ball.x - c.x, ball.y - c.y)
        speed = hypot(vel.x, vel.y)
        if dc < Self.cupRadius {
            if speed < 1.25 {
                phase = .sinking
                sinkT = 0
                SoundPlayer.shared.play(.pocket, volume: 0.8)
                Haptics.success()
                return
            }
            // Trop vite : la balle saute par-dessus, un peu freinée.
            vel.x *= 0.9
            vel.y *= 0.9
        } else if dc < Self.cupRadius * 2 && speed < 0.5 {
            // Le bord du trou attire un peu.
            vel.x += (c.x - ball.x) / dc * 0.6 * dt
            vel.y += (c.y - ball.y) / dc * 0.6 * dt
        }

        // Arrêtée ?
        if speed < 0.02 {
            restTime += dt
            if restTime > 0.25 {
                vel = (0, 0)
                if ball.y >= half || slope == 0 || blockedDownhill() {
                    if strokes >= 10 {
                        say(L("10 coups : on passe au suivant"))
                        strokes = current.par + 4
                        holeDone()
                    } else {
                        phase = .aim
                    }
                }
            }
        } else {
            restTime = 0
        }
    }

    private func holeDone() {
        while cards[player].count < hole { cards[player].append(current.par + 4) }
        cards[player].append(strokes)
        let diff = strokes - current.par
        if strokes == 1 {
            say(L("TROU EN UN !"))
            SoundPlayer.shared.play(.applause, volume: 0.6)
        } else if diff < 0 {
            say(L("Sous le par !"))
            SoundPlayer.shared.play(.win, volume: 0.6)
        } else if diff == 0 {
            say(L("Par !"))
        } else {
            say(L("\(strokes) coups"))
        }
        phase = .between
        betweenLeft = 1.4
    }

    private func nextTurn() {
        if player + 1 < players {
            player += 1
            beginTurn()
            return
        }
        player = 0
        if hole + 1 < GolfHole.all.count {
            hole += 1
            beginTurn()
        } else {
            phase = .finished
            if players == 1 {
                let t = total(0)
                if best == 0 || t < best {
                    best = t
                    UserDefaults.standard.set(t, forKey: "golf.best")
                }
            }
            SoundPlayer.shared.play(.applause, volume: 0.6)
        }
    }

    // MARK: Démo

    func demoShot() {
        guard phase == .aim else { return }
        let c = cup
        let dx = c.x - ball.x, dy = c.y - ball.y
        let d = hypot(dx, dy)
        guard d > 0.001 else { return }
        shoot(dx: dx / d, dy: dy / d, power: min(1, 0.15 + d * 0.55))
    }
}
