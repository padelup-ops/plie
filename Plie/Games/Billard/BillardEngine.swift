import Foundation

// MARK: - Physique du billard
//
// Repère de la table : x va de 0 à 1 dans la longueur (de gauche à droite à l'écran),
// y de 0 à `width` dans la largeur. La charnière du Duo passe en x = 0,5, sur les poches du milieu.
// Tout est en Foundation pur : l'ordinateur s'en sert aussi pour essayer ses coups à l'avance.

struct BVec: Equatable {
    var x: Double
    var y: Double

    static let zero = BVec(x: 0, y: 0)
    static func + (a: BVec, b: BVec) -> BVec { BVec(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: BVec, b: BVec) -> BVec { BVec(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: BVec, k: Double) -> BVec { BVec(x: a.x * k, y: a.y * k) }
    var length: Double { (x * x + y * y).squareRoot() }
    func dot(_ o: BVec) -> Double { x * o.x + y * o.y }
    var normalized: BVec {
        let l = length
        return l > 1e-9 ? BVec(x: x / l, y: y / l) : BVec(x: 1, y: 0)
    }
}

struct BBall: Equatable {
    /// 0 = la blanche, 1 à 7 = pleines, 8 = la noire, 9 à 15 = rayées.
    let number: Int
    var p: BVec
    var v: BVec = .zero
    var pocketed = false
    /// Angle de roulement (pour faire tourner le numéro à l'écran).
    var spin: Double = 0
}

enum BEvent {
    case ballHit(a: Int, b: Int, speed: Double)
    case cushion(ball: Int, speed: Double)
    case pocket(ball: Int)
}

struct BillardWorld {
    static let radius = 0.021
    static let friction = 0.22
    static let maxSpeed = 3.2
    static let restitution = 0.95
    static let cushionBounce = 0.78

    var width: Double
    var balls: [BBall]

    /// Centres des 6 poches : les 4 coins et le milieu des grands côtés.
    var pockets: [BVec] {
        [BVec(x: 0, y: 0), BVec(x: 0.5, y: -0.012), BVec(x: 1, y: 0),
         BVec(x: 0, y: width), BVec(x: 0.5, y: width + 0.012), BVec(x: 1, y: width)]
    }

    static func pocketRadius(_ index: Int) -> Double { index == 1 || index == 4 ? 0.044 : 0.052 }

    var moving: Bool { balls.contains { !$0.pocketed && ($0.v.x != 0 || $0.v.y != 0) } }

    /// Les 15 billes en triangle (la noire au centre), la blanche à gauche.
    static func rack(width: Double) -> [BBall] {
        let r = radius
        var balls = [BBall(number: 0, p: BVec(x: 0.25, y: width / 2))]
        // Ordre classique : une pleine en tête, la noire au milieu, une pleine et une rayée aux coins du fond.
        let order = [1, 9, 2, 10, 8, 3, 11, 4, 12, 13, 5, 14, 6, 15, 7]
        var k = 0
        let apex = BVec(x: 0.72, y: width / 2)
        for row in 0..<5 {
            for i in 0...row {
                let x = apex.x + Double(row) * r * 2 * 0.8661 + 0.0005 * Double(row)
                let y = apex.y + (Double(i) - Double(row) / 2) * (r * 2 + 0.0008)
                balls.append(BBall(number: order[k], p: BVec(x: x, y: y)))
                k += 1
            }
        }
        return balls
    }

    /// Une bille peut-elle être posée là (dans la table, sans toucher les autres) ?
    func canPlace(_ p: BVec, ignoring index: Int) -> Bool {
        let r = Self.radius
        guard p.x > r, p.x < 1 - r, p.y > r, p.y < width - r else { return false }
        for (i, b) in balls.enumerated() where i != index && !b.pocketed {
            if (b.p - p).length < r * 2.05 { return false }
        }
        return true
    }

    /// Avance la simulation de `dt` secondes (en petits pas) et renvoie ce qui s'est passé.
    mutating func step(_ dt: Double) -> [BEvent] {
        var events: [BEvent] = []
        let steps = max(1, Int((dt / (1.0 / 240.0)).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            substep(h, &events)
        }
        return events
    }

    private mutating func substep(_ h: Double, _ events: inout [BEvent]) {
        let r = Self.radius
        // Déplacement et frottement du tapis
        for i in balls.indices where !balls[i].pocketed {
            var b = balls[i]
            let speed = b.v.length
            if speed > 0 {
                b.p = b.p + b.v * h
                b.spin += speed * h / r
                let slower = max(0, speed - Self.friction * h)
                b.v = slower < 0.004 ? .zero : b.v * (slower / speed)
            }
            balls[i] = b
        }

        // Poches
        let ps = pockets
        for i in balls.indices where !balls[i].pocketed {
            let b = balls[i]
            var inPocket = false
            for (k, pc) in ps.enumerated() where (b.p - pc).length < Self.pocketRadius(k) {
                inPocket = true
            }
            // Sortie de la table par une entrée de poche : la bille est tombée.
            if b.p.x < -0.03 || b.p.x > 1.03 || b.p.y < -0.03 || b.p.y > width + 0.03 { inPocket = true }
            if inPocket {
                balls[i].pocketed = true
                balls[i].v = .zero
                events.append(.pocket(ball: balls[i].number))
            }
        }

        // Bandes (sauf devant les poches, pour que les billes puissent y entrer)
        for i in balls.indices where !balls[i].pocketed {
            var b = balls[i]
            let nearCornerX = b.p.x < 0.065 || b.p.x > 1 - 0.065
            let nearCornerY = b.p.y < 0.065 || b.p.y > width - 0.065
            let nearMiddle = abs(b.p.x - 0.5) < 0.042
            if b.p.x < r && !nearCornerY {
                b.p.x = r
                events.append(.cushion(ball: b.number, speed: abs(b.v.x)))
                b.v.x = abs(b.v.x) * Self.cushionBounce
                b.v.y *= 0.96
            } else if b.p.x > 1 - r && !nearCornerY {
                b.p.x = 1 - r
                events.append(.cushion(ball: b.number, speed: abs(b.v.x)))
                b.v.x = -abs(b.v.x) * Self.cushionBounce
                b.v.y *= 0.96
            }
            if b.p.y < r && !nearCornerX && !nearMiddle {
                b.p.y = r
                events.append(.cushion(ball: b.number, speed: abs(b.v.y)))
                b.v.y = abs(b.v.y) * Self.cushionBounce
                b.v.x *= 0.96
            } else if b.p.y > width - r && !nearCornerX && !nearMiddle {
                b.p.y = width - r
                events.append(.cushion(ball: b.number, speed: abs(b.v.y)))
                b.v.y = -abs(b.v.y) * Self.cushionBounce
                b.v.x *= 0.96
            }
            balls[i] = b
        }

        // Chocs entre billes (même masse)
        let n = balls.count
        for i in 0..<n where !balls[i].pocketed {
            for j in (i + 1)..<n where !balls[j].pocketed {
                let d = balls[j].p - balls[i].p
                let dist = d.length
                guard dist < r * 2, dist > 1e-9 else { continue }
                let nrm = d * (1 / dist)
                let overlap = r * 2 - dist
                balls[i].p = balls[i].p - nrm * (overlap / 2)
                balls[j].p = balls[j].p + nrm * (overlap / 2)
                let vn = (balls[i].v - balls[j].v).dot(nrm)
                if vn > 0 {
                    let k = vn * (1 + Self.restitution) / 2
                    balls[i].v = balls[i].v - nrm * k
                    balls[j].v = balls[j].v + nrm * k
                    events.append(.ballHit(a: balls[i].number, b: balls[j].number, speed: vn))
                }
            }
        }
    }
}

// MARK: - Règles (billard à 8 billes, simplifiées)

enum BGroup: Equatable {
    case open, solids, stripes

    func owns(_ number: Int) -> Bool {
        switch self {
        case .open: return number != 0 && number != 8
        case .solids: return (1...7).contains(number)
        case .stripes: return (9...15).contains(number)
        }
    }

    var other: BGroup {
        switch self {
        case .open: return .open
        case .solids: return .stripes
        case .stripes: return .solids
        }
    }
}

/// Ce que le coup a donné, pour appliquer les règles une fois les billes arrêtées.
struct BShotLog {
    var firstHit: Int?
    var pocketed: [Int] = []
    var scratch: Bool { pocketed.contains(0) }

    mutating func record(_ events: [BEvent]) {
        for e in events {
            switch e {
            case .ballHit(let a, let b, _):
                if firstHit == nil {
                    if a == 0 { firstHit = b } else if b == 0 { firstHit = a }
                }
            case .pocket(let ball):
                pocketed.append(ball)
            case .cushion:
                break
            }
        }
    }
}

struct BVerdict {
    var foul = false
    var keepsTurn = false
    /// nil : la partie continue ; sinon le joueur gagnant.
    var winner: Int?
    var message: String = ""
    var assigned = false
}

enum BillardRules {
    /// Le joueur a-t-il rentré toutes ses billes (avant ce coup) ?
    static func cleared(_ group: BGroup, balls: [BBall]) -> Bool {
        guard group != .open else { return false }
        return !balls.contains { group.owns($0.number) && !$0.pocketed }
    }

    /// Applique les règles au coup qui vient d'être joué.
    /// `ballsBefore` : l'état des billes avant le coup.
    static func judge(log: BShotLog, shooter: Int, groups: inout [BGroup], ballsBefore: [BBall], isBreak: Bool) -> BVerdict {
        var verdict = BVerdict()
        let group = groups[shooter]
        let wasCleared = cleared(group, balls: ballsBefore)
        // Fautes : blanche rentrée, aucune bille touchée, ou mauvaise bille touchée en premier.
        if log.scratch {
            verdict.foul = true
            verdict.message = L("Faute : la blanche est tombée")
        } else if log.firstHit == nil {
            verdict.foul = true
            verdict.message = L("Faute : aucune bille touchée")
        } else if let first = log.firstHit, !isBreak {
            if group == .open && first == 8 {
                verdict.foul = true
                verdict.message = L("Faute : la noire en premier")
            } else if group != .open && !wasCleared && !group.owns(first) {
                verdict.foul = true
                verdict.message = L("Faute : il fallait toucher une de tes billes")
            } else if wasCleared && first != 8 {
                verdict.foul = true
                verdict.message = L("Faute : il fallait toucher la noire")
            }
        }

        // La noire décide de la partie.
        if log.pocketed.contains(8) {
            if wasCleared && !verdict.foul {
                verdict.winner = shooter
                verdict.message = L("La noire est rentrée !")
            } else {
                verdict.winner = 1 - shooter
                verdict.message = isBreak ? L("La noire au premier coup… perdu !") : L("La noire trop tôt… perdu !")
            }
            return verdict
        }

        // Attribution des groupes : la première bille rentrée sans faute.
        if group == .open && !verdict.foul, let first = log.pocketed.first(where: { $0 != 0 && $0 != 8 }) {
            let mine: BGroup = (1...7).contains(first) ? .solids : .stripes
            groups[shooter] = mine
            groups[1 - shooter] = mine.other
            verdict.assigned = true
        }
        let mine = groups[shooter]
        let pocketedOwn = log.pocketed.contains { mine.owns($0) }
        verdict.keepsTurn = !verdict.foul && pocketedOwn
        if verdict.message.isEmpty {
            if verdict.assigned {
                verdict.message = mine == .solids ? L("Pleines pour ce joueur, rayées pour l'autre") : L("Rayées pour ce joueur, pleines pour l'autre")
            } else if pocketedOwn {
                verdict.message = L("Bien joué, rejoue !")
            }
        }
        return verdict
    }
}

// MARK: - L'ordinateur

enum BillardAI {
    struct Shot {
        let direction: BVec
        let power: Double
    }

    /// Essaie de nombreux coups dans une copie de la table et garde le meilleur.
    /// `skill` de 0 (débutant) à 1 (fort).
    static func choose(world: BillardWorld, group: BGroup, skill: Double) -> Shot {
        let cue = world.balls[0].p
        let r = BillardWorld.radius
        let wasCleared = BillardRules.cleared(group, balls: world.balls)
        let targets = world.balls.filter { b in
            guard !b.pocketed, b.number != 0 else { return false }
            if wasCleared { return b.number == 8 }
            return group.owns(b.number)
        }
        var candidates: [Shot] = []
        for t in targets {
            for (k, pocket) in world.pockets.enumerated() {
                let toPocket = (pocket - t.p).normalized
                let ghost = t.p - toPocket * (r * 2)
                let aim = ghost - cue
                guard aim.length > r else { continue }
                let cut = aim.normalized.dot(toPocket)
                guard cut > 0.25 else { continue }
                let far = (pocket - t.p).length + aim.length
                for base in [0.38, 0.55, 0.75] {
                    let power = min(1, base + far * 0.25 + (k == 1 || k == 4 ? 0.05 : 0))
                    candidates.append(Shot(direction: aim.normalized, power: power))
                }
            }
            // Coup direct sur la bille (pour au moins la toucher).
            candidates.append(Shot(direction: (t.p - cue).normalized, power: 0.5))
        }
        if candidates.isEmpty {
            for a in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 12) {
                candidates.append(Shot(direction: BVec(x: cos(a), y: sin(a)), power: 0.6))
            }
        }

        var best = candidates[0]
        var bestScore = -Double.infinity
        for shot in candidates.prefix(90) {
            let s = evaluate(shot, world: world, group: group)
            if s > bestScore {
                bestScore = s
                best = shot
            }
        }
        // Le débutant vise moins bien.
        let noise = (1 - skill) * 0.05 + 0.004
        let angle = atan2(best.direction.y, best.direction.x) + Double.random(in: -noise...noise)
        let power = min(1, max(0.2, best.power * Double.random(in: (0.92 - 0.1 * (1 - skill))...(1.06 + 0.1 * (1 - skill)))))
        return Shot(direction: BVec(x: cos(angle), y: sin(angle)), power: power)
    }

    private static func evaluate(_ shot: Shot, world: BillardWorld, group: BGroup) -> Double {
        var w = world
        w.balls[0].v = shot.direction * (shot.power * BillardWorld.maxSpeed)
        var log = BShotLog()
        var t = 0.0
        while w.moving && t < 9 {
            log.record(w.step(1.0 / 60.0))
            t += 1.0 / 60.0
        }
        var groups: [BGroup] = [group.other, group]
        let verdict = BillardRules.judge(log: log, shooter: 1, groups: &groups, ballsBefore: world.balls, isBreak: false)
        if let winner = verdict.winner { return winner == 1 ? 10_000 : -10_000 }
        var score = 0.0
        if verdict.foul { score -= 80 }
        let mine = groups[1]
        for n in log.pocketed where n != 0 {
            score += mine.owns(n) ? 40 : -15
        }
        if verdict.keepsTurn {
            score += 25
            // Bonus si la blanche finit près du centre (plus de coups possibles ensuite).
            let c = w.balls[0].p
            score -= (c - BVec(x: 0.5, y: w.width / 2)).length * 6
        }
        return score + Double.random(in: 0...1)
    }
}
