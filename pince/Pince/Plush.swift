import SceneKit
import UIKit
import simd

// MARK: - Les doudous

enum Rarity: Int {
    case common, uncommon, rare, legendary

    var label: String {
        switch self {
        case .common: return T("Courant", "Common")
        case .uncommon: return T("Peu courant", "Uncommon")
        case .rare: return T("Rare", "Rare")
        case .legendary: return T("Légendaire", "Legendary")
        }
    }

    var tint: UInt32 {
        switch self {
        case .common: return 0x7CCB8F
        case .uncommon: return 0x5FA8F2
        case .rare: return 0xB57BEA
        case .legendary: return 0xFFB02E
        }
    }

    /// Pièces gagnées quand le doudou tombe dans la trappe.
    var reward: Int {
        switch self {
        case .common: return 15
        case .uncommon: return 25
        case .rare: return 50
        case .legendary: return 100
        }
    }

    /// Plus le nombre est grand, plus le doudou sort souvent.
    var weight: Int {
        switch self {
        case .common: return 12
        case .uncommon: return 7
        case .rare: return 3
        case .legendary: return 1
        }
    }
}

enum Species: String, CaseIterable, Identifiable {
    case frog, bear, bunny, fox, whale, mushroom, axolotl, strawberry, unicorn

    var id: String { rawValue }

    var name: String {
        switch self {
        case .frog: return T("Nénu la grenouille", "Lily the frog")
        case .bear: return T("Praline l'ourson", "Praline the bear")
        case .bunny: return T("Mochi le lapin", "Mochi the bunny")
        case .fox: return T("Roux le renard", "Rusty the fox")
        case .whale: return T("Bulle la baleine", "Bubble the whale")
        case .mushroom: return T("Chapi le champignon", "Cap the mushroom")
        case .axolotl: return T("Axo l'axolotl", "Axo the axolotl")
        case .strawberry: return T("Fraisie la fraise", "Berry the strawberry")
        case .unicorn: return T("Nova la licorne", "Nova the unicorn")
        }
    }

    var rarity: Rarity {
        switch self {
        case .frog, .bear, .bunny, .fox: return .common
        case .whale, .mushroom, .axolotl: return .uncommon
        case .strawberry: return .rare
        case .unicorn: return .legendary
        }
    }

    /// Rayon du corps dans la machine.
    var radius: Float {
        switch self {
        case .frog, .bunny: return 0.21
        case .bear, .fox, .mushroom: return 0.22
        case .whale, .axolotl: return 0.225
        case .strawberry: return 0.2
        case .unicorn: return 0.215
        }
    }

    static func random() -> Species {
        let total = allCases.reduce(0) { $0 + $1.rarity.weight }
        var pick = Int.random(in: 0..<total)
        for s in allCases {
            pick -= s.rarity.weight
            if pick < 0 { return s }
        }
        return .frog
    }
}

// MARK: - Les matières

enum Paint {
    private static var cache: [String: SCNMaterial] = [:]
    private static let lock = NSLock()

    private static func cached(_ key: String, _ make: () -> SCNMaterial) -> SCNMaterial {
        lock.lock()
        defer { lock.unlock() }
        if let m = cache[key] { return m }
        let m = make()
        cache[key] = m
        return m
    }

    /// Tissu : mat, doux.
    static func matte(_ hex: UInt32) -> SCNMaterial {
        cached("m\(hex)") {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = UIColor(hex: hex)
            return m
        }
    }

    /// Plastique : un reflet.
    static func gloss(_ hex: UInt32) -> SCNMaterial {
        cached("g\(hex)") {
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = UIColor(hex: hex)
            m.specular.contents = UIColor(white: 0.55, alpha: 1)
            m.shininess = 0.45
            return m
        }
    }

    /// Couleur pleine, sans éclairage.
    static func flat(_ hex: UInt32) -> SCNMaterial {
        cached("f\(hex)") {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor(hex: hex)
            return m
        }
    }

    /// La même couleur, plus sombre (`k` < 1) ou plus claire (`k` > 1).
    static func shade(_ hex: UInt32, _ k: Float) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(max(0, min(255, (Float(v) * k).rounded()))) }
        return (ch((hex >> 16) & 0xFF) << 16) | (ch((hex >> 8) & 0xFF) << 8) | ch(hex & 0xFF)
    }
}

// MARK: - Le modelage

/// Petite boîte à outils pour modeler un doudou. Tout est mesuré en rayons de corps : le corps fait 1 de rayon.
private struct Kit {
    let root: SCNNode
    static let one = SIMD3<Float>(1, 1, 1)
    static let ink = Paint.gloss(0x2B2230)
    static let white = Paint.flat(0xFFFFFF)
    static let pink = Paint.matte(0xFF9DB5)

    /// Un point à la surface du corps : `az` tourne autour de la verticale (0 = de face), `el` monte.
    func at(_ az: Float, _ el: Float, _ k: Float = 1) -> SIMD3<Float> {
        SIMD3<Float>(sin(az) * cos(el), sin(el) * 0.92, cos(az) * cos(el)) * k
    }

    /// La rotation qui tourne l'axe z vers `v`.
    func turn(_ v: SIMD3<Float>) -> simd_quatf {
        simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(v))
    }

    @discardableResult
    func ball(_ radius: Float, _ pos: SIMD3<Float>, _ m: SCNMaterial, scale: SIMD3<Float> = Kit.one,
              turn q: simd_quatf? = nil, seg: Int = 20) -> SCNNode {
        let g = SCNSphere(radius: CGFloat(radius))
        g.segmentCount = seg
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = pos
        n.simdScale = scale
        if let q { n.simdOrientation = q }
        root.addChildNode(n)
        return n
    }

    @discardableResult
    func cone(_ radius: Float, _ height: Float, _ pos: SIMD3<Float>, _ m: SCNMaterial, turn q: simd_quatf? = nil) -> SCNNode {
        let g = SCNCone(topRadius: 0.02, bottomRadius: CGFloat(radius), height: CGFloat(height))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = pos
        if let q { n.simdOrientation = q }
        root.addChildNode(n)
        return n
    }

    /// Une gélule entre deux points.
    @discardableResult
    func rod(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: Float, _ m: SCNMaterial) -> SCNNode {
        let d = b - a
        let g = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(simd_length(d) + 2 * radius))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) * 0.5
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(d))
        root.addChildNode(n)
        return n
    }

    func body(_ m: SCNMaterial) {
        ball(1, .zero, m, scale: SIMD3<Float>(1, 0.92, 1), seg: 48)
    }

    /// Un œil noir brillant posé en `pos`, tourné vers `normal`.
    func eye(at pos: SIMD3<Float>, normal: SIMD3<Float>, size: Float = 0.088) {
        let q = turn(normal)
        ball(size, pos, Kit.ink, scale: SIMD3<Float>(1, 1.15, 0.5), turn: q)
        ball(size * 0.32, pos + q.act(SIMD3<Float>(-size * 0.3, size * 0.42, size * 0.46)), Kit.white,
             scale: SIMD3<Float>(1, 1, 0.5), turn: q, seg: 12)
    }

    func eyes(_ az: Float = 0.38, _ el: Float = 0.12, size: Float = 0.088) {
        for s in [Float(-1), 1] {
            let p = at(s * az, el, 0.985)
            eye(at: p, normal: p, size: size)
        }
    }

    /// Une tache plate qui épouse le corps (joue, ventre, museau). `lift` la fait ressortir.
    @discardableResult
    func patch(_ az: Float, _ el: Float, radius: Float, _ m: SCNMaterial, flat: Float = 0.3, lift: Float = 0.02,
               stretch: Float = 1) -> SCNNode {
        let p = at(az, el)
        let k = 1 - radius * flat + lift
        return ball(radius, p * k, m, scale: SIMD3<Float>(1, stretch, flat), turn: turn(p), seg: 24)
    }

    func blush(_ az: Float = 0.68, _ el: Float = -0.1) {
        for s in [Float(-1), 1] { patch(s * az, el, radius: 0.13, Kit.pink, flat: 0.28, lift: 0.022, stretch: 0.62) }
    }

    /// Une petite bouche ronde.
    func mouth(_ el: Float = -0.1, out: Float = 1) {
        let p = at(0, el, out)
        ball(0.045, p, Paint.matte(0xC9506B), scale: SIMD3<Float>(1.15, 0.8, 0.45), turn: turn(p), seg: 12)
    }

    /// Une bouche en trait, large.
    func smile(_ el: Float = -0.12, width: Float = 0.2) {
        let a = at(-width, el + 0.02, 1.0), b = at(0, el - 0.02, 1.01), c = at(width, el + 0.02, 1.0)
        let m = Paint.matte(0x5A3A46)
        rod(a, b, 0.016, m)
        rod(b, c, 0.016, m)
    }

    func feet(_ m: SCNMaterial) {
        for s in [Float(-1), 1] { ball(0.22, SIMD3<Float>(s * 0.4, -0.8, 0.45), m, scale: SIMD3<Float>(1, 0.62, 1.25)) }
    }

    func arms(_ m: SCNMaterial) {
        for s in [Float(-1), 1] { ball(0.17, SIMD3<Float>(s * 0.9, -0.2, 0.3), m, scale: SIMD3<Float>(0.8, 1.15, 0.85)) }
    }
}

enum PlushModel {
    /// Le doudou, de rayon 1, tourné vers +z. À mettre à l'échelle par celui qui l'utilise.
    static func make(_ species: Species) -> SCNNode {
        let root = SCNNode()
        let k = Kit(root: root)
        let up = SIMD3<Float>(0, 1, 0)

        switch species {
        case .frog:
            let skin = Paint.matte(0x9BD96A), belly = Paint.matte(0xEDF8CC)
            k.body(skin)
            k.patch(0, -0.38, radius: 0.6, belly, flat: 0.4, lift: 0.03)
            for s in [Float(-1), 1] {
                let bump = SIMD3<Float>(s * 0.42, 0.74, 0.3)
                k.ball(0.29, bump, skin)
                k.eye(at: bump + SIMD3<Float>(s * 0.02, 0.03, 0.26), normal: SIMD3<Float>(s * 0.1, 0.1, 1), size: 0.12)
            }
            k.blush(0.72, 0.02)
            k.smile(0.12, width: 0.3)
            k.feet(Paint.matte(0x7FC552))
            k.arms(skin)

        case .bear:
            let fur = Paint.matte(0xDCA76C), cream = Paint.matte(0xFFEBCF)
            k.body(fur)
            for s in [Float(-1), 1] {
                k.ball(0.3, SIMD3<Float>(s * 0.64, 0.7, 0), fur, scale: SIMD3<Float>(1, 1, 0.7))
                k.ball(0.17, SIMD3<Float>(s * 0.64, 0.7, 0.15), cream, scale: SIMD3<Float>(1, 1, 0.5))
            }
            k.patch(0, -0.14, radius: 0.34, cream, flat: 0.55, lift: 0.1, stretch: 0.82)
            let nose = k.at(0, -0.06, 1.1)
            k.ball(0.075, nose, Paint.gloss(0x5A3423), scale: SIMD3<Float>(1.25, 0.85, 0.7))
            k.mouth(-0.22, out: 1.07)
            k.eyes(0.42, 0.14)
            k.blush(0.78, -0.12)
            k.feet(Paint.matte(0xC98F55))
            k.arms(fur)

        case .bunny:
            let fur = Paint.matte(0xFFF7F2), inner = Paint.matte(0xFFB7CB)
            k.body(fur)
            for s in [Float(-1), 1] {
                let base = SIMD3<Float>(s * 0.32, 0.7, -0.05)
                let tip = SIMD3<Float>(s * 0.5, 1.65, -0.1)
                k.rod(base, tip, 0.17, fur)
                k.rod(base + SIMD3<Float>(s * 0.04, 0.3, 0.1), tip + SIMD3<Float>(-s * 0.02, -0.1, 0.1), 0.09, inner)
            }
            let nose = k.at(0, -0.02, 1.0)
            k.ball(0.055, nose, Paint.matte(0xFF7FA0), scale: SIMD3<Float>(1.2, 0.8, 0.6))
            k.mouth(-0.16)
            k.eyes(0.38, 0.14)
            k.blush(0.7, -0.08)
            k.ball(0.22, SIMD3<Float>(0, -0.45, -0.92), fur)
            k.feet(Paint.matte(0xFFE3E8))
            k.arms(fur)

        case .fox:
            let fur = Paint.matte(0xFF9A4D), cream = Paint.matte(0xFFF3E2), dark = Paint.matte(0x7A4A2B)
            k.body(fur)
            for s in [Float(-1), 1] {
                let lean = simd_quatf(angle: -s * 0.32, axis: SIMD3<Float>(0, 0, 1))
                k.cone(0.32, 0.6, SIMD3<Float>(s * 0.52, 0.98, 0), fur, turn: lean)
                k.cone(0.18, 0.36, SIMD3<Float>(s * 0.52, 0.94, 0.14), dark, turn: lean)
            }
            for s in [Float(-1), 1] { k.patch(s * 0.5, -0.32, radius: 0.36, cream, flat: 0.35, lift: 0.03) }
            k.patch(0, -0.3, radius: 0.3, cream, flat: 0.5, lift: 0.07, stretch: 0.8)
            let nose = k.at(0, -0.18, 1.08)
            k.ball(0.065, nose, Kit.ink, scale: SIMD3<Float>(1.2, 0.85, 0.7))
            k.eyes(0.4, 0.12)
            k.blush(0.82, -0.02)
            k.ball(0.4, SIMD3<Float>(0.78, -0.42, -0.5), fur, scale: SIMD3<Float>(0.8, 0.85, 1.15))
            k.ball(0.24, SIMD3<Float>(0.92, -0.32, -0.86), cream)
            k.feet(dark)
            k.arms(fur)

        case .whale:
            let skin = Paint.matte(0x6DB7F2), belly = Paint.matte(0xEAF6FF), spray = Paint.gloss(0xBFE6FF)
            k.body(skin)
            k.patch(0, -0.5, radius: 0.72, belly, flat: 0.4, lift: 0.03)
            k.ball(0.3, SIMD3<Float>(0, 0.25, -0.95), skin, scale: SIMD3<Float>(0.7, 0.7, 1.3))
            for s in [Float(-1), 1] {
                k.ball(0.3, SIMD3<Float>(s * 0.26, 0.55, -1.25), skin, scale: SIMD3<Float>(1, 0.4, 0.7),
                       turn: simd_quatf(angle: s * 0.5, axis: SIMD3<Float>(0, 0, 1)))
                k.ball(0.28, SIMD3<Float>(s * 0.95, -0.3, 0.15), skin, scale: SIMD3<Float>(0.9, 0.35, 0.75),
                       turn: simd_quatf(angle: -s * 0.5, axis: SIMD3<Float>(0, 0, 1)))
            }
            k.rod(SIMD3<Float>(0, 0.9, 0), SIMD3<Float>(0, 1.12, 0), 0.035, spray)
            k.ball(0.1, SIMD3<Float>(0, 1.22, 0), spray)
            k.ball(0.085, SIMD3<Float>(-0.2, 1.3, 0), spray)
            k.ball(0.085, SIMD3<Float>(0.2, 1.3, 0), spray)
            k.eyes(0.55, 0.06)
            k.blush(0.88, -0.14)
            k.smile(-0.1, width: 0.22)

        case .mushroom:
            let stem = Paint.matte(0xFFF1DC), cap = Paint.matte(0xFF6B6B)
            k.body(stem)
            let center = SIMD3<Float>(0, 0.58, 0)
            k.ball(1.18, center, cap, scale: SIMD3<Float>(1, 0.6, 1), seg: 40)
            let dots: [(Float, Float, Float)] = [(0, 0.95, 0.2), (-0.7, 0.42, 0.17), (0.75, 0.5, 0.16), (0.1, 0.38, 0.13),
                                                 (-1.6, 0.6, 0.17), (1.7, 0.55, 0.17), (2.7, 0.5, 0.18), (-2.6, 0.45, 0.16)]
            for (az, el, r) in dots {
                let dir = SIMD3<Float>(sin(az) * cos(el), sin(el), cos(az) * cos(el))
                let p = center + SIMD3<Float>(dir.x * 1.18, dir.y * 0.708, dir.z * 1.18)
                let normal = SIMD3<Float>(dir.x / 1.18, dir.y / 0.708, dir.z / 1.18)
                k.ball(r, p - simd_normalize(normal) * 0.02, Kit.white, scale: SIMD3<Float>(1, 1, 0.22), turn: k.turn(normal))
            }
            k.eyes(0.36, -0.14)
            k.blush(0.66, -0.34)
            k.mouth(-0.34)
            k.feet(Paint.matte(0xF3DDC0))

        case .axolotl:
            let skin = Paint.matte(0xFFB7CB), gill = Paint.matte(0xF2709C)
            k.body(skin)
            k.patch(0, -0.45, radius: 0.6, Paint.matte(0xFFDCE6), flat: 0.4, lift: 0.03)
            for s in [Float(-1), 1] {
                for (i, a) in [Float(0.95), 0.3, -0.35].enumerated() {
                    let dir = SIMD3<Float>(s * cos(a), sin(a), 0)
                    let base = SIMD3<Float>(s * 0.72, 0.38 - Float(i) * 0.08, -0.05)
                    k.rod(base, base + dir * 0.55, 0.085, gill)
                }
            }
            k.eyes(0.52, 0.1, size: 0.075)
            k.blush(0.8, -0.1)
            k.smile(-0.06, width: 0.24)
            k.ball(0.3, SIMD3<Float>(0, -0.3, -1.0), skin, scale: SIMD3<Float>(0.3, 0.75, 1.1))
            k.feet(Paint.matte(0xFF9DB5))
            k.arms(skin)

        case .strawberry:
            let flesh = Paint.matte(0xFF6F86), seed = Paint.matte(0xFFEDB0), leaf = Paint.matte(0x6CC36B)
            k.body(flesh)
            let seeds: [(Float, Float)] = [(-0.8, 0.5), (0, 0.62), (0.8, 0.5), (-1.1, 0.08), (1.1, 0.08), (-0.9, -0.45),
                                           (0.9, -0.45), (-0.32, -0.62), (0.32, -0.62), (-1.6, 0.4), (1.6, 0.4), (0, -0.9),
                                           (-1.7, -0.3), (1.7, -0.3), (2.4, 0.2), (-2.4, 0.2), (3.1, -0.2), (3.1, 0.5)]
            for (az, el) in seeds {
                let p = k.at(az, el)
                k.ball(0.05, p * 0.99, seed, scale: SIMD3<Float>(0.8, 1.2, 0.4), turn: k.turn(p), seg: 10)
            }
            for i in 0..<5 {
                let a = Float(i) * 2 * .pi / 5 + 0.3
                let q = simd_quatf(angle: -a, axis: up) * simd_quatf(angle: -0.4, axis: SIMD3<Float>(0, 0, 1))
                k.ball(0.36, SIMD3<Float>(cos(a) * 0.3, 0.88, sin(a) * 0.3), leaf, scale: SIMD3<Float>(1, 0.2, 0.5), turn: q)
            }
            k.rod(SIMD3<Float>(0, 0.9, 0), SIMD3<Float>(0.04, 1.14, 0), 0.05, Paint.matte(0x4E9E57))
            k.eyes(0.36, 0.1)
            k.blush(0.66, -0.12)
            k.mouth(-0.12)
            k.feet(Paint.matte(0xF2586F))

        case .unicorn:
            let fur = Paint.matte(0xFFFDF9), gold = Paint.gloss(0xFFD166)
            k.body(fur)
            k.cone(0.14, 0.56, SIMD3<Float>(0, 1.08, 0.36), gold, turn: simd_quatf(angle: 0.38, axis: SIMD3<Float>(1, 0, 0)))
            for s in [Float(-1), 1] {
                let lean = simd_quatf(angle: -s * 0.4, axis: SIMD3<Float>(0, 0, 1))
                k.cone(0.17, 0.36, SIMD3<Float>(s * 0.5, 0.92, 0.08), fur, turn: lean)
                k.cone(0.09, 0.2, SIMD3<Float>(s * 0.5, 0.9, 0.16), Kit.pink, turn: lean)
            }
            k.ball(0.24, SIMD3<Float>(0.14, 0.9, 0.1), Paint.matte(0xFFB3D1))
            k.ball(0.27, SIMD3<Float>(0.05, 0.92, -0.25), Paint.matte(0xC9B6F2))
            k.ball(0.28, SIMD3<Float>(0, 0.7, -0.6), Paint.matte(0x9AD4F5))
            k.ball(0.27, SIMD3<Float>(0, 0.35, -0.85), Paint.matte(0xA8E6CF))
            k.ball(0.24, SIMD3<Float>(0, -0.02, -0.96), Paint.matte(0xFFE08A))
            k.ball(0.26, SIMD3<Float>(0.5, -0.5, -0.8), Paint.matte(0xFFB3D1), scale: SIMD3<Float>(0.8, 1, 1))
            k.eyes(0.4, 0.1)
            k.blush(0.7, -0.14)
            k.mouth(-0.14)
            k.feet(Paint.matte(0xC9B6F2))
            k.arms(fur)
        }
        return root
    }
}

/// Un doudou dans la machine : une sphère qui glisse sans rouler (il reste debout, face au joueur),
/// et un habillage qui tangue et s'écrase quand on le bouscule.
final class Plush {
    let species: Species
    let radius: Float
    let node = SCNNode()
    private let look = SCNNode()
    private var lean = SIMD2<Float>(0, 0)
    private var leanSpeed = SIMD2<Float>(0, 0)
    private var squash: Float = 0
    private var squashSpeed: Float = 0
    private var lastVelocity = SIMD3<Float>(0, 0, 0)
    private var lastPosition: SIMD3<Float>
    private let yaw: Float

    init(_ species: Species, at position: SIMD3<Float>) {
        self.species = species
        radius = species.radius
        yaw = Float.random(in: -0.35...0.35)
        lastPosition = position
        let model = PlushModel.make(species)
        model.simdScale = SIMD3<Float>(radius, radius, radius)
        look.addChildNode(model)
        look.eulerAngles.y = yaw
        node.addChildNode(look)
        node.simdPosition = position
        node.physicsBody = makeBody()
    }

    func makeBody() -> SCNPhysicsBody {
        let shape = SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(radius)), options: nil)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = 1
        body.friction = 0.9
        body.restitution = 0.2
        body.damping = 0.3
        body.angularVelocityFactor = SCNVector3(0, 0, 0)
        return body
    }

    var position: SIMD3<Float> { node.presentation.simdPosition }

    /// Le balancement : un ressort amorti, poussé par chaque changement de vitesse.
    func sway(_ dt: Float) {
        guard dt > 0 else { return }
        let p = position
        let velocity: SIMD3<Float>
        if let body = node.physicsBody {
            velocity = SIMD3<Float>(body.velocity)
        } else {
            velocity = (p - lastPosition) / dt
        }
        lastPosition = p
        var kick = velocity - lastVelocity
        lastVelocity = velocity
        if simd_length(kick) > 6 { kick = simd_normalize(kick) * 6 }

        leanSpeed += SIMD2<Float>(kick.x, kick.z) * 1.1
        leanSpeed += (lean * -70 - leanSpeed * 5) * dt
        lean += leanSpeed * dt
        lean = simd_clamp(lean, SIMD2<Float>(-0.45, -0.45), SIMD2<Float>(0.45, 0.45))

        squashSpeed += max(0, kick.y) * 0.35
        squashSpeed += (squash * -160 - squashSpeed * 11) * dt
        squash = max(-0.25, min(0.3, squash + squashSpeed * dt))

        look.simdEulerAngles = SIMD3<Float>(lean.y, yaw, -lean.x)
        look.simdScale = SIMD3<Float>(1 + squash * 0.5, 1 - squash, 1 + squash * 0.5)
        look.simdPosition = SIMD3<Float>(0, -squash * radius, 0)
    }
}
