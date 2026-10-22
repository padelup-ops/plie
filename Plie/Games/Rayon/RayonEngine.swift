import Foundation

// Géométrie de RAYON. Plateau de 1 × 1, y vers le bas, angles en degrés.
// Traduction exacte de tools/rayon_gen.py, qui a servi à vérifier chaque niveau.

struct Pt: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// Un segment défini par son centre, sa longueur et son angle.
struct Seg {
    let cx: Double
    let cy: Double
    let length: Double
    let angle: Double

    init(_ cx: Double, _ cy: Double, _ length: Double, _ angle: Double) {
        self.cx = cx
        self.cy = cy
        self.length = length
        self.angle = angle
    }
}

/// Un miroir qui tourne avec la charnière : angle = base + t × span × factor.
struct ControlMirror {
    let cx: Double
    let cy: Double
    let length: Double
    let base: Double
    let factor: Double

    init(_ cx: Double, _ cy: Double, _ length: Double, _ base: Double, _ factor: Double) {
        self.cx = cx
        self.cy = cy
        self.length = length
        self.base = base
        self.factor = factor
    }
}

struct RayonLevel {
    let number: Int
    let world: Int
    let emitter: Pt
    let emitterAngle: Double
    let target: Pt
    let targetRadius: Double
    let mirrors: [Seg]
    let walls: [Seg]
    let controls: [ControlMirror]
    let span: Double
    let startT: Double

    func controlAngle(_ control: ControlMirror, t: Double) -> Double {
        control.base + t * span * control.factor
    }

    static func worldName(_ world: Int) -> String {
        switch world {
        case 1: return "Premier reflet"
        case 2: return "Le labyrinthe"
        default: return "Les jumeaux"
        }
    }
}

enum RayonEngine {
    static let epsilon = 1e-7
    static let maxSegments = 30

    struct Line {
        let p: Pt
        let q: Pt
        let isMirror: Bool
    }

    struct Result: Equatable {
        let points: [Pt]
        let hit: Bool
    }

    static func endpoints(cx: Double, cy: Double, length: Double, angle: Double) -> (Pt, Pt) {
        let a = angle * .pi / 180
        let dx = cos(a) * length / 2
        let dy = sin(a) * length / 2
        return (Pt(cx - dx, cy - dy), Pt(cx + dx, cy + dy))
    }

    static func lines(for level: RayonLevel, t: Double) -> [Line] {
        var result: [Line] = []
        for m in level.mirrors {
            let (p, q) = endpoints(cx: m.cx, cy: m.cy, length: m.length, angle: m.angle)
            result.append(Line(p: p, q: q, isMirror: true))
        }
        for c in level.controls {
            let (p, q) = endpoints(cx: c.cx, cy: c.cy, length: c.length, angle: level.controlAngle(c, t: t))
            result.append(Line(p: p, q: q, isMirror: true))
        }
        for w in level.walls {
            let (p, q) = endpoints(cx: w.cx, cy: w.cy, length: w.length, angle: w.angle)
            result.append(Line(p: p, q: q, isMirror: false))
        }
        let border = [(Pt(0, 0), Pt(1, 0)), (Pt(1, 0), Pt(1, 1)), (Pt(1, 1), Pt(0, 1)), (Pt(0, 1), Pt(0, 0))]
        for (p, q) in border {
            result.append(Line(p: p, q: q, isMirror: false))
        }
        return result
    }

    private static func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        ax * by - ay * bx
    }

    private static func raySegment(ox: Double, oy: Double, dx: Double, dy: Double, p: Pt, q: Pt) -> Double? {
        let ex = q.x - p.x
        let ey = q.y - p.y
        let den = cross(dx, dy, ex, ey)
        if abs(den) < 1e-12 { return nil }
        let wx = p.x - ox
        let wy = p.y - oy
        let t = cross(wx, wy, ex, ey) / den
        let s = cross(wx, wy, dx, dy) / den
        if t > epsilon && s >= -1e-9 && s <= 1 + 1e-9 {
            return t
        }
        return nil
    }

    private static func rayCircle(ox: Double, oy: Double, dx: Double, dy: Double, c: Pt, r: Double) -> Double? {
        let fx = ox - c.x
        let fy = oy - c.y
        let b = fx * dx + fy * dy
        let cc = fx * fx + fy * fy - r * r
        let disc = b * b - cc
        if disc < 0 { return nil }
        let sq = disc.squareRoot()
        var t = -b - sq
        if t <= epsilon { t = -b + sq }
        return t > epsilon ? t : nil
    }

    /// Suit le rayon depuis l'émetteur jusqu'à la cible, un mur ou le bord du plateau.
    static func trace(_ level: RayonLevel, t: Double) -> Result {
        let segments = lines(for: level, t: t)
        var ox = level.emitter.x
        var oy = level.emitter.y
        let a = level.emitterAngle * .pi / 180
        var dx = cos(a)
        var dy = sin(a)
        var points = [Pt(ox, oy)]
        var last = -1

        for _ in 0..<maxSegments {
            var bestT: Double?
            var bestIndex = -1
            for (index, line) in segments.enumerated() where index != last {
                if let h = raySegment(ox: ox, oy: oy, dx: dx, dy: dy, p: line.p, q: line.q),
                   bestT == nil || h < bestT! {
                    bestT = h
                    bestIndex = index
                }
            }
            if let ht = rayCircle(ox: ox, oy: oy, dx: dx, dy: dy, c: level.target, r: level.targetRadius),
               bestT == nil || ht < bestT! {
                points.append(Pt(ox + dx * ht, oy + dy * ht))
                return Result(points: points, hit: true)
            }
            guard let hitT = bestT else {
                return Result(points: points, hit: false)
            }
            let hx = ox + dx * hitT
            let hy = oy + dy * hitT
            points.append(Pt(hx, hy))
            let line = segments[bestIndex]
            if !line.isMirror {
                return Result(points: points, hit: false)
            }
            let ex = line.q.x - line.p.x
            let ey = line.q.y - line.p.y
            let length = (ex * ex + ey * ey).squareRoot()
            let nx = -ey / length
            let ny = ex / length
            let dot = dx * nx + dy * ny
            dx -= 2 * dot * nx
            dy -= 2 * dot * ny
            ox = hx
            oy = hy
            last = bestIndex
        }
        return Result(points: points, hit: false)
    }
}
