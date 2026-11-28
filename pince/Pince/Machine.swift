import SceneKit
import UIKit
import simd

/// Les mesures de la machine. L'écran est le plan z = 0 : tout le décor est derrière, du côté des z négatifs.
enum Box {
    // Plus large que haute, comme une vraie machine : elle remplit mieux un écran couché.
    static let halfW: Float = 1.2
    static let top: Float = 1.55
    static let front: Float = -0.15
    static let back: Float = -1.85
    // La trappe, devant à gauche
    static let holeMinX: Float = -1.17, holeMaxX: Float = -0.53
    static let holeMinZ: Float = -0.78, holeMaxZ: Float = -0.18
    /// La pince attend au-dessus de la trappe.
    static let home = SIMD2<Float>(-0.85, -0.48)
    static let railY: Float = 1.48
    /// Hauteur du centre de la pince quand elle est remontée.
    static let restY: Float = 1.2
    static let minX: Float = -0.94, maxX: Float = 0.94
    static let minZ: Float = -1.58, maxZ: Float = -0.42
    /// Les emplacements où les doudous sont posés (x, z).
    static let slots: [SIMD2<Float>] = [
        SIMD2(-0.92, -1.53), SIMD2(-0.46, -1.55), SIMD2(0, -1.52), SIMD2(0.46, -1.55), SIMD2(0.92, -1.53),
        SIMD2(-0.69, -1.05), SIMD2(-0.23, -1.06), SIMD2(0.23, -1.04), SIMD2(0.69, -1.06),
        SIMD2(0, -0.56), SIMD2(0.46, -0.57), SIMD2(0.92, -0.56),
    ]
    /// Le fond du bac de sortie, sous la trappe. On le voit par une vitre dans la face avant de la machine.
    static let binFloor: Float = -0.52
    /// Le haut de cette vitre.
    static let binTop: Float = -0.1
    /// Combien de doudous la machine contient quand elle est pleine.
    static let full = 10
}

// MARK: - La pince

/// Une pince à trois griffes. La même sert à jouer et à décorer les machines voisines.
final class Claw {
    static let open: Float = 0.5
    static let shut: Float = -0.22

    let node = SCNNode()
    private var swings: [SCNNode] = []
    var angle: Float = Claw.open {
        didSet { for s in swings { s.eulerAngles.z = angle } }
    }

    init(dome: UInt32, trim: UInt32, face: Bool) {
        let shell = SCNSphere(radius: 0.14)
        shell.segmentCount = 36
        shell.firstMaterial = Paint.gloss(dome)
        let shellNode = SCNNode(geometry: shell)
        shellNode.simdScale = SIMD3<Float>(1, 0.8, 1)
        node.addChildNode(shellNode)

        let ring = SCNCylinder(radius: 0.152, height: 0.05)
        ring.firstMaterial = Paint.gloss(trim)
        let ringNode = SCNNode(geometry: ring)
        ringNode.simdPosition = SIMD3<Float>(0, -0.04, 0)
        node.addChildNode(ringNode)

        let stem = SCNCylinder(radius: 0.032, height: 0.1)
        stem.firstMaterial = Paint.gloss(trim)
        let stemNode = SCNNode(geometry: stem)
        stemNode.simdPosition = SIMD3<Float>(0, 0.14, 0)
        node.addChildNode(stemNode)

        if face {
            // Un petit visage sur le dôme
            for s in [Float(-1), 1] {
                let eye = SCNSphere(radius: 0.017)
                eye.firstMaterial = Paint.gloss(0x2B2230)
                let eyeNode = SCNNode(geometry: eye)
                eyeNode.simdPosition = SIMD3<Float>(s * 0.048, 0.03, 0.124)
                node.addChildNode(eyeNode)
                let cheek = SCNSphere(radius: 0.019)
                cheek.firstMaterial = Paint.flat(0xFFD0DA)
                let cheekNode = SCNNode(geometry: cheek)
                cheekNode.simdPosition = SIMD3<Float>(s * 0.086, 0.005, 0.108)
                cheekNode.simdScale = SIMD3<Float>(1, 0.65, 0.5)
                node.addChildNode(cheekNode)
            }
        }

        let metal = Paint.gloss(0xECEAF6)
        let rubber = Paint.gloss(trim)
        for k in 0..<3 {
            // Une griffe derrière, deux devant : le visage du doudou reste visible.
            let phi = -Float.pi / 2 + Float(k) * 2 * .pi / 3
            let pivot = SCNNode()
            pivot.simdPosition = SIMD3<Float>(0.1 * cos(phi), -0.05, 0.1 * sin(phi))
            pivot.eulerAngles.y = -phi
            let swing = SCNNode()
            pivot.addChildNode(swing)
            let elbow = SIMD3<Float>(0.075, -0.16, 0), tip = SIMD3<Float>(0, -0.34, 0)
            swing.addChildNode(Claw.rod(.zero, elbow, 0.02, metal))
            swing.addChildNode(Claw.rod(elbow, tip, 0.02, metal))
            let pad = SCNSphere(radius: 0.03)
            pad.firstMaterial = rubber
            let padNode = SCNNode(geometry: pad)
            padNode.simdPosition = tip
            swing.addChildNode(padNode)
            node.addChildNode(pivot)
            swings.append(swing)
        }
        angle = Claw.open
        for s in swings { s.eulerAngles.z = Claw.open }
    }

    private static func rod(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: Float, _ m: SCNMaterial) -> SCNNode {
        let d = b - a
        let g = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(simd_length(d) + 2 * radius))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) * 0.5
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(d))
        return n
    }

    /// L'angle des griffes refermées autour d'un doudou de ce rayon.
    static func hold(_ radius: Float) -> Float {
        asin(max(-0.2, min(0.45, (0.8 * radius - 0.1) / 0.34)))
    }
}

// MARK: - La machine

final class Machine: NSObject, SCNSceneRendererDelegate {
    enum Event {
        case busy(Bool)
        case motor(Bool)
        case clack
        case grabbed
        /// Les griffes se sont refermées sur rien, ou ont seulement effleuré un doudou.
        case missed
        case slipped
        /// La pince s'ouvre au-dessus de la trappe et lâche le doudou.
        case released
        case restocked
        case plop
        case won(Species)
    }

    /// Appelé sur le fil principal.
    var onEvent: ((Event) -> Void)?

    let scene = SCNScene()
    let cameraNode = SCNNode()

    // Ce que le fil principal écrit et que le rendu lit
    private let lock = NSLock()
    private var stick = SIMD2<Float>(0, 0)
    private var wantDrop = false
    private var eyeTarget = SIMD3<Float>(0, 0, 0)
    private var gain: Float = 1
    private var window = Window(halfW: 2, halfH: 0.87, centerY: 0.82, unitsPerMeter: 20, restDistance: 0.4)
    private var todo: [(Machine) -> Void] = []

    private struct Window {
        var halfW: Float
        var halfH: Float
        var centerY: Float
        var unitsPerMeter: Float
        /// Distance supposée des yeux quand on ne la mesure pas, en mètres.
        var restDistance: Float
    }

    // L'état du jeu, sur le fil du rendu
    private enum Phase { case idle, descending, closing, ascending, returning, opening, settling, frozen }
    private var phase = Phase.idle
    private var timer: Float = 0
    private var lastTime: TimeInterval = 0
    private var eye = SIMD3<Float>(0, 0, 0.4)
    private var spot = Box.home
    private var headY = Box.restY
    private var prongs = Claw.open
    private var prongGoal = Claw.open
    private var plushes: [Plush] = []
    private var held: Plush?
    /// Le dernier doudou gagné, posé dans le bac.
    private var prize: Plush?
    private var slipAt: Float = 2
    private var liftFrom: Float = 0
    private var tripFrom = Box.home
    private var motorOn = false
    private var freezeOnLift = false
    private var restockIn: Float = -1
    private var tried = false
    private var plain = false

    private let claw = Claw(dome: Tint.coral, trim: Tint.cream, face: true)
    private let cable = SCNNode()
    private let carriage = SCNNode()
    private let bridge = SCNNode()
    private let clawShadow = Paint.shadow()

    override init() {
        super.init()
        build()
        // Au départ : un de chaque parmi les plus courants, et un invité surprise devant.
        var first: [Species] = [.frog, .bear, .bunny, .whale, .mushroom, .axolotl, .fox, Species.random(), Species.random()]
        first.shuffle()
        first.append(Species.random())
        let slots = Box.slots.enumerated().filter { $0.offset != 0 && $0.offset != 4 }.map { $0.element }
        for (species, slot) in zip(first, slots) { add(species, slot: slot, height: nil) }
        place()
        updateCamera(0)
    }

    // MARK: Les commandes (fil principal)

    /// Le manche : x vers la droite, y vers le fond de la machine, entre −1 et 1.
    func setStick(_ v: SIMD2<Float>) {
        lock.lock(); stick = v; lock.unlock()
    }

    func drop() {
        lock.lock(); wantDrop = true; lock.unlock()
    }

    /// La position des yeux en mètres par rapport au centre de l'écran. `nil` : bien en face.
    /// Un z nul ou négatif veut dire « distance inconnue ».
    func setEye(_ e: SIMD3<Float>?) {
        lock.lock(); eyeTarget = e ?? SIMD3<Float>(0, 0, 0); lock.unlock()
    }

    func setGain(_ g: Float) {
        lock.lock(); gain = g; lock.unlock()
    }

    /// La vue change de taille : on recalcule la fenêtre par laquelle on regarde la machine.
    /// `panel` : la hauteur, en points, de la face avant de la machine en bas de la vue (le pupitre).
    func resize(_ size: CGSize, panel: CGFloat, pointsPerMeter: Float, restDistance: Float) {
        let w = Float(size.width), h = Float(size.height)
        guard w > 20, h > 20 else { return }
        let below = max(0, min(Float(panel), h * 0.6))
        // Au-dessus du pupitre, il faut voir au moins toute la largeur et toute la hauteur de la machine.
        let unitsPerPoint = max((Box.halfW + 0.1) / (w / 2), (Box.top + 0.19) / (h - below))
        let halfH = unitsPerPoint * h / 2
        lock.lock()
        window = Window(halfW: unitsPerPoint * w / 2, halfH: halfH, centerY: -0.05 - below * unitsPerPoint + halfH,
                        unitsPerMeter: unitsPerPoint * pointsPerMeter, restDistance: restDistance)
        lock.unlock()
    }

    /// Pour les essais : une caméra ordinaire à la place de la perspective « fenêtre ».
    func usePlainCamera() {
        lock.lock(); todo.append { $0.plain = true }; lock.unlock()
    }

    /// Pour les captures : la pince va toute seule chercher le doudou de devant.
    func demo(freezeOnLift freeze: Bool) {
        lock.lock()
        todo.append { m in
            m.freezeOnLift = freeze
            if let target = m.plushes.last {
                let p = target.node.simdPosition
                m.spot = SIMD2<Float>(p.x, p.z)
            }
        }
        wantDrop = true
        lock.unlock()
    }

    // MARK: Chaque image (fil du rendu)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 0 : Float(min(max(time - lastTime, 0), 0.05))
        lastTime = time
        updateCamera(dt)
        step(dt)
    }

    /// La perspective « fenêtre » : l'œil est où se trouve vraiment le joueur, et la pyramide de vue passe
    /// exactement par les bords de l'écran. Elle devient oblique dès qu'on n'est plus en face.
    private func updateCamera(_ dt: Float) {
        lock.lock()
        let w = window
        var target = eyeTarget
        let k = gain
        lock.unlock()
        if target.z <= 0 { target.z = w.restDistance }
        eye += (target - eye) * (dt > 0 ? 1 - exp(-dt * 32) : 1)

        let ez = max(0.16, min(1.2, eye.z)) * w.unitsPerMeter
        let reach = ez * 0.75
        let ex = max(-reach, min(reach, eye.x * k * w.unitsPerMeter))
        // Bien en face, on regarde quand même un peu d'en haut, comme devant une vraie machine : on voit le sol.
        let ey = max(-reach, min(reach, eye.y * k * w.unitsPerMeter + ez * 0.22))
        cameraNode.simdPosition = SIMD3<Float>(ex, w.centerY + ey, ez)

        if plain {
            // Vue ordinaire, sans perspective oblique : sert seulement à vérifier le décor.
            cameraNode.camera?.fieldOfView = CGFloat(2 * atan(w.halfH / ez) * 180 / .pi)
            return
        }
        // Le plan proche est tout près de l'œil, comme le fait ARKit : le moteur de rendu coupe sinon
        // tout ce qui est plus près que deux fois cette distance.
        let n: Float = 0.2, f: Float = 120
        let l = (-w.halfW - ex) * n / ez, r = (w.halfW - ex) * n / ez
        let b = (-w.halfH - ey) * n / ez, t = (w.halfH - ey) * n / ez
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4<Float>(2 * n / (r - l), 0, 0, 0)
        m.columns.1 = SIMD4<Float>(0, 2 * n / (t - b), 0, 0)
        m.columns.2 = SIMD4<Float>((r + l) / (r - l), (t + b) / (t - b), -(f + n) / (f - n), -1)
        m.columns.3 = SIMD4<Float>(0, 0, -2 * f * n / (f - n), 0)
        cameraNode.camera?.projectionTransform = SCNMatrix4(m)
    }

    private func emit(_ e: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(e) }
    }

    private func step(_ dt: Float) {
        guard dt > 0 else { return }
        lock.lock()
        let s = stick
        let drop = wantDrop
        let jobs = todo
        todo.removeAll()
        wantDrop = false
        lock.unlock()
        for job in jobs { job(self) }

        var moving = false
        switch phase {
        case .idle:
            if simd_length(s) > 0.08 {
                let before = spot
                spot.x = max(Box.minX, min(Box.maxX, spot.x + s.x * 0.75 * dt))
                spot.y = max(Box.minZ, min(Box.maxZ, spot.y - s.y * 0.75 * dt))
                moving = simd_distance(before, spot) > 0.0005
            }
            if drop {
                phase = .descending
                emit(.busy(true))
            } else if restockIn >= 0 {
                restockIn -= dt
                if restockIn < 0 { restock() }
            }

        case .descending:
            moving = true
            headY -= 0.95 * dt
            shove(dt)
            let stop = stopHeight()
            if headY <= stop {
                headY = stop
                phase = .closing
                timer = 0
                tried = false
                prongGoal = Claw.shut
                emit(.clack)
            }

        case .closing:
            timer += dt
            if timer > 0.2, !tried {
                tried = true
                grab()
            }
            if timer > 0.55 {
                phase = .ascending
                liftFrom = headY
            }

        case .ascending:
            moving = true
            headY = min(Box.restY, headY + 0.9 * dt)
            let done = (headY - liftFrom) / max(0.01, Box.restY - liftFrom)
            if held != nil, done >= slipAt { slip() }
            if freezeOnLift, done > 0.55 {
                phase = .frozen
            } else if headY >= Box.restY {
                phase = .returning
                tripFrom = spot
            }

        case .returning:
            let gap = Box.home - spot
            let far = simd_length(gap)
            let total = max(0.01, simd_distance(tripFrom, Box.home))
            if held != nil, slipAt >= 1, 1 - far / total >= (slipAt - 1) * 4 { slip() }
            if far < 0.01 {
                spot = Box.home
                phase = .opening
                timer = 0
                prongGoal = Claw.open
            } else {
                moving = true
                spot += gap / far * min(far, 0.8 * dt)
            }

        case .opening:
            timer += dt
            if timer > 0.18, let p = held {
                release(p)
                emit(.released)
            }
            if timer > 0.5 {
                phase = .settling
                timer = 0
            }

        case .settling:
            timer += dt
            if timer > 0.7 {
                phase = .idle
                emit(.busy(false))
                if plushes.count <= 3 { restockIn = 0.4 }
            }

        case .frozen:
            break
        }

        if moving != motorOn {
            motorOn = moving
            emit(.motor(moving))
        }

        prongs += (prongGoal - prongs) * (1 - exp(-dt * 16))
        claw.angle = prongs
        place()

        if let p = held {
            let goal = SIMD3<Float>(spot.x, headY - 0.115 - p.radius, spot.y)
            p.node.simdPosition += (goal - p.node.simdPosition) * (1 - exp(-dt * 20))
        }
        for p in plushes { p.sway(dt) }

        // Un doudou tombé dans la trappe est gagné, qu'il ait été porté ou simplement poussé.
        // Il reste dans le bac, derrière sa vitre, jusqu'à ce qu'un autre s'approche de la trappe.
        if let old = prize, plushes.contains(where: { overHole($0.position) && $0.position.y < 0.45 }) {
            old.node.removeFromParentNode()
            old.shadow.removeFromParentNode()
            prize = nil
        }
        for p in plushes where p !== held && p.position.y < -0.12 {
            plushes.removeAll { $0 === p }
            prize?.node.removeFromParentNode()
            prize?.shadow.removeFromParentNode()
            prize = p
            // Des paillettes : une gerbe dans le bac, une autre qui jaillit de la trappe.
            let holeX = (Box.holeMinX + Box.holeMaxX) / 2, holeZ = (Box.holeMinZ + Box.holeMaxZ) / 2
            glitter(at: SIMD3<Float>(holeX, Box.binFloor + 0.22, holeZ), fountain: false)
            glitter(at: SIMD3<Float>(holeX, 0.04, holeZ), fountain: true)
            emit(.plop)
            emit(.won(p.species))
        }
        prize?.sway(dt)
    }

    private lazy var glitterImage = Backdrop.glitter()

    /// Une gerbe de paillettes dorées et rosées. `fountain` : elles jaillissent vers le haut ; sinon elles éclatent
    /// dans tous les sens.
    private func glitter(at position: SIMD3<Float>, fountain: Bool) {
        let sparks = SCNParticleSystem()
        sparks.particleImage = glitterImage
        sparks.birthRate = fountain ? 150 : 240
        sparks.emissionDuration = 0.4
        sparks.loops = false
        sparks.particleLifeSpan = 1.1
        sparks.particleLifeSpanVariation = 0.5
        sparks.particleVelocity = fountain ? 1.7 : 0.8
        sparks.particleVelocityVariation = 0.7
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.spreadingAngle = fountain ? 30 : 180
        sparks.particleSize = 0.06
        sparks.particleSizeVariation = 0.04
        sparks.particleColor = UIColor(hex: 0xFFD84D)
        sparks.particleColorVariation = SCNVector4(0.14, 0.35, 0.1, 0)
        sparks.particleAngleVariation = 180
        sparks.particleAngularVelocityVariation = 240
        sparks.acceleration = SCNVector3(0, -1.8, 0)
        sparks.blendMode = .alpha
        sparks.isLightingEnabled = false
        let fade = CAKeyframeAnimation()
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        sparks.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]

        let node = SCNNode()
        node.simdPosition = position
        node.castsShadow = false
        node.renderingOrder = 30
        node.addParticleSystem(sparks)
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([.wait(duration: 2.4), .removeFromParentNode()]))
    }

    private func overHole(_ p: SIMD3<Float>) -> Bool {
        p.x > Box.holeMinX && p.x < Box.holeMaxX && p.z > Box.holeMinZ && p.z < Box.holeMaxZ
    }

    /// Range la pince, le câble et le chariot à leur place.
    private func place() {
        claw.node.simdPosition = SIMD3<Float>(spot.x, headY, spot.y)
        carriage.simdPosition = SIMD3<Float>(spot.x, Box.railY - 0.03, spot.y)
        bridge.simdPosition = SIMD3<Float>(0, Box.railY, spot.y)
        let top = Box.railY - 0.06, bottom = headY + 0.16
        let length = max(0.01, top - bottom)
        cable.simdPosition = SIMD3<Float>(spot.x, (top + bottom) / 2, spot.y)
        cable.simdScale = SIMD3<Float>(1, length, 1)

        let overHole = spot.x > Box.holeMinX && spot.x < Box.holeMaxX && spot.y > Box.holeMinZ && spot.y < Box.holeMaxZ
        clawShadow.isHidden = overHole
        clawShadow.simdPosition = SIMD3<Float>(spot.x, 0.005, spot.y)
        let spread: Float = 0.42 + headY * 0.12
        clawShadow.simdScale = SIMD3<Float>(spread, spread, 1)
        clawShadow.opacity = CGFloat(max(0.25, 1 - headY * 0.42))
    }

    /// Jusqu'où la pince peut descendre : le sol, ou le dessus du doudou qui est sous elle.
    private func stopHeight() -> Float {
        var stop: Float = 0.37
        for p in plushes {
            let c = p.position
            let d = simd_length(SIMD2<Float>(c.x - spot.x, c.z - spot.y))
            if d < p.radius * 0.98 {
                stop = max(stop, c.y + (p.radius * p.radius - d * d).squareRoot() * 0.95 + 0.115)
            }
        }
        return stop
    }

    /// En descendant, les griffes écartent doucement les doudous voisins.
    private func shove(_ dt: Float) {
        let tips = headY - 0.35
        for p in plushes {
            let c = p.position
            let away = SIMD2<Float>(c.x - spot.x, c.z - spot.y)
            let d = simd_length(away)
            guard d > p.radius * 0.98, d < 0.26 + p.radius * 0.85, tips < c.y + p.radius * 0.6 else { continue }
            // Assez fort pour vaincre le frottement du sol, pas plus.
            let push = away / d * 11
            p.node.physicsBody?.applyForce(SCNVector3(push.x, 0, push.y), asImpulse: false)
        }
    }

    /// Les griffes se referment. Tout se joue sur la précision : bien centré, le doudou est tenu jusqu'au bout ;
    /// un peu de travers, il glisse en route ; trop loin, la pince ne fait que le chatouiller.
    private func grab() {
        var best: Plush?
        var bestOffset: Float = 10
        for p in plushes {
            let c = p.position
            let d = simd_length(SIMD2<Float>(c.x - spot.x, c.z - spot.y))
            guard d < p.radius * 0.98 else { continue }
            let contact = c.y + (p.radius * p.radius - d * d).squareRoot() * 0.95 + 0.115
            if abs(contact - headY) < 0.07, d / p.radius < bestOffset {
                best = p
                bestOffset = d / p.radius
            }
        }
        for p in plushes where p !== best {
            let c = p.position
            let away = SIMD2<Float>(c.x - spot.x, c.z - spot.y)
            let d = simd_length(away)
            if d > 0.01, d < 0.3 + p.radius * 0.7, c.y < headY {
                let push = away / d * 0.9
                p.node.physicsBody?.applyForce(SCNVector3(push.x, 0.25, push.y), asImpulse: true)
            }
        }
        guard let p = best else {
            emit(.missed)
            return
        }
        let quality = 1 - bestOffset
        if quality < 0.2 {
            p.node.physicsBody?.applyForce(SCNVector3(0, 1.1, 0), asImpulse: true)
            emit(.missed)
            return
        }
        held = p
        p.node.physicsBody = nil
        prongGoal = Claw.hold(p.radius)
        // 2 : ne glisse jamais. Entre 0 et 1 : glisse pendant la montée. Entre 1 et 1,25 : pendant le retour.
        slipAt = quality >= 0.5 ? 2 : 0.2 + (quality - 0.2) / 0.3
        emit(.grabbed)
    }

    private func slip() {
        guard let p = held else { return }
        prongGoal = Claw.shut
        release(p)
        emit(.slipped)
    }

    private func release(_ p: Plush) {
        held = nil
        p.node.physicsBody = p.makeBody()
    }

    private func restock() {
        var free: [SIMD2<Float>] = []
        for slot in Box.slots {
            let taken = plushes.contains { p in
                let c = p.position
                return simd_distance(SIMD2<Float>(c.x, c.z), slot) < 0.44
            }
            if !taken { free.append(slot) }
        }
        free.shuffle()
        var height: Float = 1.15
        for slot in free.prefix(max(0, Box.full - plushes.count)) {
            add(Species.random(), slot: slot, height: height)
            height += 0.12
        }
        emit(.restocked)
    }

    private func add(_ species: Species, slot: SIMD2<Float>, height: Float?) {
        let jitter = SIMD2<Float>(Float.random(in: -0.02...0.02), Float.random(in: -0.02...0.02))
        let p = Plush(species, at: SIMD3<Float>(slot.x + jitter.x, height ?? species.radius, slot.y + jitter.y))
        plushes.append(p)
        scene.rootNode.addChildNode(p.node)
        scene.rootNode.addChildNode(p.shadow)
    }

    // MARK: Le décor

    @discardableResult
    private func box(_ w: Float, _ h: Float, _ l: Float, _ pos: SIMD3<Float>, _ m: SCNMaterial, chamfer: Float = 0,
                     solid: Bool = false, shadow: Bool = false) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(chamfer))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = pos
        n.castsShadow = shadow
        if solid {
            n.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
            n.physicsBody?.friction = 0.9
        }
        scene.rootNode.addChildNode(n)
        return n
    }

    /// Un mur qu'on ne voit pas : il retient les doudous.
    private func wall(_ w: Float, _ h: Float, _ l: Float, _ pos: SIMD3<Float>) {
        let n = SCNNode()
        n.simdPosition = pos
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: 0)
        n.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: g, options: nil))
        n.physicsBody?.friction = 0.3
        scene.rootNode.addChildNode(n)
    }

    /// Un panneau plat, tourné de `yaw` autour de la verticale.
    @discardableResult
    private func panel(_ w: Float, _ h: Float, _ pos: SIMD3<Float>, yaw: Float, _ m: SCNMaterial, order: Int = 0) -> SCNNode {
        let g = SCNPlane(width: CGFloat(w), height: CGFloat(h))
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.simdPosition = pos
        n.eulerAngles.y = yaw
        n.castsShadow = false
        n.renderingOrder = order
        scene.rootNode.addChildNode(n)
        return n
    }

    private func textured(_ image: UIImage, repeatX: Float = 1, repeatY: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = image
        if repeatX != 1 || repeatY != 1 {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        }
        return m
    }

    private func glass() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Backdrop.glare()
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        return m
    }

    private func build() {
        scene.background.contents = UIColor(hex: 0xF7D9E6)
        scene.physicsWorld.gravity = SCNVector3(0, -7, 0)

        let camera = SCNCamera()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // Les lumières : une ambiance chaude, un projecteur, un appoint de face. Les ombres sont des taches
        // floues posées au sol (voir Paint.shadow) : c'est plus doux, et ça ne dépend pas de la perspective oblique.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(hex: 0xFFF4F0)
        ambient.light?.intensity = 560
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = UIColor(hex: 0xFFFBF2)
        keyLight.intensity = 620
        key.light = keyLight
        key.simdPosition = SIMD3<Float>(1.3, 5.6, 0.9)
        key.look(at: SCNVector3(0, 0.6, -1))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(hex: 0xFFE9F2)
        fill.light?.intensity = 260
        fill.simdPosition = SIMD3<Float>(-1.5, 1.5, 4)
        fill.look(at: SCNVector3(0, 0.8, -1))
        scene.rootNode.addChildNode(fill)

        let cream = Paint.gloss(Tint.cream)
        let coral = Paint.gloss(Tint.coral)
        let depth = Box.front - Box.back
        let midZ = (Box.front + Box.back) / 2

        // La salle, derrière les machines
        let room = textured(Backdrop.stripes(0xFFD9C9, 0xFFE6D8), repeatX: 14, repeatY: 1)
        panel(40, 14, SIMD3<Float>(0, 3, Box.back - 0.5), yaw: 0, room)
        // Le socle de la salle, de chaque côté de la machine (pas dessous : la trappe doit rester creuse)
        for side in [Float(-1), 1] {
            _ = box(20, 4, depth + 0.4, SIMD3<Float>(side * (Box.halfW + 10), -2.03, midZ - 0.22), Paint.matte(0xD79AB3))
        }

        // Le sol de la machine, avec la trappe
        let floor = SCNMaterial()
        floor.lightingModel = .lambert
        floor.diffuse.contents = UIColor(hex: Tint.floor)
        // Les blocs descendent bas : leur face avant est le pupitre, qu'on voit sous la vitre.
        func slab(_ x0: Float, _ x1: Float, _ z0: Float, _ z1: Float, from y0: Float = -4, to y1: Float = 0) {
            let n = box(x1 - x0, y1 - y0, z1 - z0, SIMD3<Float>((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), cream, solid: true)
            n.geometry?.materials = [cream, cream, cream, cream, floor, cream]
        }
        slab(Box.holeMaxX, Box.halfW, Box.back, Box.front)
        slab(-Box.halfW, Box.holeMaxX, Box.back, Box.holeMinZ)
        slab(-Box.halfW, Box.holeMinX, Box.holeMinZ, Box.holeMaxZ)
        // Devant la trappe, la face avant est percée d'une vitre : on voit le bac où tombent les doudous.
        slab(-Box.halfW, Box.holeMaxX, Box.holeMaxZ, Box.front, from: Box.binTop, to: 0)
        slab(-Box.halfW, Box.holeMaxX, Box.holeMaxZ, Box.front, from: -4, to: Box.binFloor)
        slab(-Box.halfW, Box.holeMinX, Box.holeMaxZ, Box.front, from: Box.binFloor, to: Box.binTop)

        let holeW = Box.holeMaxX - Box.holeMinX, holeL = Box.holeMaxZ - Box.holeMinZ
        let holeX = (Box.holeMinX + Box.holeMaxX) / 2, holeZ = (Box.holeMinZ + Box.holeMaxZ) / 2
        // L'intérieur du bac, rose : un fond, deux côtés, un plancher.
        let binH = -Box.binFloor
        let binY = Box.binFloor / 2
        panel(holeW, binH, SIMD3<Float>(holeX, binY, Box.holeMinZ + 0.004), yaw: 0, Paint.flat(0xE98AAA))
        panel(holeL, binH, SIMD3<Float>(Box.holeMinX + 0.004, binY, holeZ), yaw: .pi / 2, Paint.flat(0xD9739A))
        panel(holeL, binH, SIMD3<Float>(Box.holeMaxX - 0.004, binY, holeZ), yaw: -.pi / 2, Paint.flat(0xDD7A9F))
        _ = box(holeW, 0.1, holeL + 0.03, SIMD3<Float>(holeX, Box.binFloor - 0.047, holeZ + 0.015), Paint.flat(0xF9BFD0), solid: true)
        // La vitre du bac et son cadre, sur la face avant
        let openH = Box.binTop - Box.binFloor
        let openY = (Box.binTop + Box.binFloor) / 2
        panel(holeW, openH, SIMD3<Float>(holeX, openY, Box.front + 0.002), yaw: 0, glass(), order: 20)
        let trim = Paint.gloss(Tint.rose)
        for y in [Box.binTop + 0.018, Box.binFloor - 0.018] {
            _ = box(holeW + 0.07, 0.036, 0.016, SIMD3<Float>(holeX, y, Box.front + 0.006), trim, chamfer: 0.006)
        }
        for x in [Box.holeMinX - 0.018, Box.holeMaxX + 0.018] {
            _ = box(0.036, openH, 0.016, SIMD3<Float>(x, openY, Box.front + 0.006), trim, chamfer: 0.006)
        }
        // Un liseré tout le long du pupitre, sous la vitre de la machine
        _ = box(2 * Box.halfW + 0.02, 0.028, 0.014, SIMD3<Float>(0, -0.03, Box.front + 0.006), trim)
        // Le décor peint du pupitre, posé sur la face avant en deux morceaux : à droite du bac, et sous le bac.
        let artTop: Float = -0.05, artBottom: Float = -2.05
        let art = Backdrop.panelArt(width: CGFloat(2 * Box.halfW), height: CGFloat(artTop - artBottom))
        func paint(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float) {
            let k = Float(Backdrop.panelScale)
            let cut = CGRect(x: CGFloat((x0 + Box.halfW) * k), y: CGFloat((artTop - y1) * k), width: CGFloat((x1 - x0) * k), height: CGFloat((y1 - y0) * k))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Backdrop.piece(of: art, cut)
            panel(x1 - x0, y1 - y0, SIMD3<Float>((x0 + x1) / 2, (y0 + y1) / 2, Box.front + 0.0015), yaw: 0, m)
        }
        paint(Box.holeMaxX + 0.036, Box.halfW, artBottom, artTop)
        paint(-Box.halfW, Box.holeMaxX + 0.036, artBottom, Box.binFloor - 0.036)
        // Le rebord
        let rim = Paint.gloss(Tint.rose)
        _ = box(holeW + 0.06, 0.016, 0.03, SIMD3<Float>(holeX, 0.008, Box.holeMinZ - 0.015), rim)
        _ = box(0.03, 0.016, holeL, SIMD3<Float>(Box.holeMaxX + 0.015, 0.008, holeZ), rim)

        // Les parois qui retiennent les doudous
        wall(0.4, 4, depth + 0.8, SIMD3<Float>(-Box.halfW - 0.2, 1.5, midZ))
        wall(0.4, 4, depth + 0.8, SIMD3<Float>(Box.halfW + 0.2, 1.5, midZ))
        wall(2 * Box.halfW + 0.8, 4, 0.4, SIMD3<Float>(0, 1.5, Box.back - 0.2))
        wall(2 * Box.halfW + 0.8, 6, 0.4, SIMD3<Float>(0, 1, Box.front + 0.2))

        // Le fond, les montants, les vitres, le plafond et l'enseigne
        panel(2 * Box.halfW, Box.top, SIMD3<Float>(0, Box.top / 2, Box.back + 0.002), yaw: 0, textured(Backdrop.poster()))
        for x in [-Box.halfW, Box.halfW] {
            for z in [Box.front - 0.045, Box.back + 0.045] {
                _ = box(0.09, Box.top + 0.2, 0.09, SIMD3<Float>(x, Box.top / 2 + 0.05, z), cream, chamfer: 0.025)
            }
            panel(depth, Box.top, SIMD3<Float>(x, Box.top / 2, midZ), yaw: .pi / 2, glass(), order: 20)
        }
        _ = box(2 * Box.halfW + 0.1, 0.16, depth + 0.1, SIMD3<Float>(0, Box.top + 0.08, midZ), coral)
        let sign = box(2.1, 0.64, 0.34, SIMD3<Float>(0, Box.top + 0.5, Box.front - 0.2), coral, chamfer: 0.08)
        let title = SCNMaterial()
        title.lightingModel = .constant
        title.diffuse.contents = Backdrop.marquee("PEEKACLAW")
        sign.geometry?.materials = [title, coral, coral, coral, coral, coral]

        // Le portique : deux rails, un pont qui avance et recule, un chariot qui va de gauche à droite
        let steel = Paint.gloss(0xD9D4EC)
        for x in [-Box.halfW + 0.06, Box.halfW - 0.06] {
            _ = box(0.05, 0.05, depth - 0.1, SIMD3<Float>(x, Box.railY, midZ), steel)
        }
        let bar = SCNBox(width: CGFloat(2 * Box.halfW - 0.1), height: 0.05, length: 0.07, chamferRadius: 0.01)
        bar.firstMaterial = steel
        bridge.geometry = bar
        bridge.castsShadow = false
        scene.rootNode.addChildNode(bridge)
        let cart = SCNBox(width: 0.24, height: 0.12, length: 0.18, chamferRadius: 0.04)
        cart.firstMaterial = Paint.gloss(Tint.rose)
        carriage.geometry = cart
        carriage.castsShadow = false
        scene.rootNode.addChildNode(carriage)
        let wire = SCNCylinder(radius: 0.012, height: 1)
        wire.firstMaterial = Paint.gloss(0xB9B3D6)
        cable.geometry = wire
        cable.castsShadow = false
        scene.rootNode.addChildNode(cable)
        scene.rootNode.addChildNode(claw.node)
        scene.rootNode.addChildNode(clawShadow)

        // Une guirlande au fond et une devant, tout en haut : deux plans de plus pour le relief
        let bulbs: [UInt32] = [Tint.butter, Tint.mint, Tint.coral, Tint.sky, Tint.lilac]
        for (z, sag, count) in [(Box.back + 0.06, Float(0.13), 13), (Box.front - 0.07, Float(0.06), 11)] {
            for i in 0..<count {
                let u = Float(i) / Float(count - 1)
                let g = SCNSphere(radius: 0.035)
                g.segmentCount = 12
                g.firstMaterial = Paint.flat(bulbs[i % bulbs.count])
                let n = SCNNode(geometry: g)
                let droop: Float = sag * 4 * u * (1 - u)
                n.simdPosition = SIMD3<Float>((Box.halfW - 0.1) * (2 * u - 1), Box.top - 0.06 - droop, z)
                n.castsShadow = false
                scene.rootNode.addChildNode(n)
            }
        }

        let roof = Box.top + 0.82
        let sitters: [(Species, Float, Float, Float)] = [(.bear, -0.72, 0.27, 0.25), (.unicorn, 0, 0.3, 0), (.axolotl, 0.72, 0.27, -0.25)]
        for (species, x, size, yaw) in sitters {
            let model = PlushModel.make(species)
            model.simdScale = SIMD3<Float>(size, size, size)
            model.simdPosition = SIMD3<Float>(x, roof + size * 0.9, Box.front - 0.22)
            model.eulerAngles.y = yaw
            scene.rootNode.addChildNode(model)
        }
        for i in 0..<17 {
            let u = Float(i) / 16
            let g = SCNSphere(radius: 0.06)
            g.segmentCount = 12
            g.firstMaterial = Paint.flat(bulbs[i % bulbs.count])
            let n = SCNNode(geometry: g)
            let droop: Float = 0.5 * 4 * u * (1 - u)
            n.simdPosition = SIMD3<Float>(3.2 * (2 * u - 1), roof + 1.75 - droop, Box.back - 0.44)
            scene.rootNode.addChildNode(n)
        }

        neighbour(x: -Box.halfW - 1.42, wall: (0xFFF0C2, 0xFFDF8E), floor: 0xF6C98A, trim: Tint.butter, claw: Tint.mint,
                  guests: [(.bear, SIMD3<Float>(-0.35, 0, -1.25), 0.34, 0.5), (.fox, SIMD3<Float>(0.4, 0, -0.9), 0.3, 0.2),
                           (.strawberry, SIMD3<Float>(-0.1, 0, -0.5), 0.22, 0.6)])
        neighbour(x: Box.halfW + 1.42, wall: (0xD6F3E6, 0xAEE5CC), floor: 0x8FD3C0, trim: Tint.mint, claw: Tint.lilac,
                  guests: [(.bunny, SIMD3<Float>(0.3, 0, -1.3), 0.33, -0.5), (.whale, SIMD3<Float>(-0.4, 0, -0.95), 0.3, -0.3),
                           (.mushroom, SIMD3<Float>(0.25, 0, -0.5), 0.23, -0.6)])
    }

    /// Une machine voisine, pour le décor : on la devine à travers les vitres.
    private func neighbour(x: Float, wall: (UInt32, UInt32), floor: UInt32, trim: UInt32, claw clawTint: UInt32,
                           guests: [(Species, SIMD3<Float>, Float, Float)]) {
        let depth = Box.front - Box.back
        let midZ = (Box.front + Box.back) / 2
        let frame = Paint.gloss(Tint.cream)
        let top = SCNMaterial()
        top.lightingModel = .lambert
        top.diffuse.contents = UIColor(hex: floor)
        let base = box(2, 4, depth, SIMD3<Float>(x, -2, midZ), frame)
        base.geometry?.materials = [frame, frame, frame, frame, top, frame]
        panel(2, Box.top, SIMD3<Float>(x, Box.top / 2, Box.back + 0.002), yaw: 0, textured(Backdrop.dots(wall.0, wall.1), repeatX: 2, repeatY: 2))
        for sx in [Float(-1), 1] {
            for z in [Box.front - 0.045, Box.back + 0.045] {
                _ = box(0.09, Box.top + 0.2, 0.09, SIMD3<Float>(x + sx, Box.top / 2 + 0.05, z), frame, chamfer: 0.025)
            }
            panel(depth, Box.top, SIMD3<Float>(x + sx, Box.top / 2, midZ), yaw: .pi / 2, glass(), order: 20)
        }
        _ = box(2.1, 0.16, depth + 0.1, SIMD3<Float>(x, Box.top + 0.08, midZ), Paint.gloss(trim))
        _ = box(2.3, 0.64, 0.34, SIMD3<Float>(x, Box.top + 0.5, Box.front - 0.2), Paint.gloss(trim), chamfer: 0.08)

        for (species, at, size, yaw) in guests {
            let model = PlushModel.make(species)
            model.simdScale = SIMD3<Float>(size, size, size)
            model.simdPosition = SIMD3<Float>(x + at.x, size * 0.92, at.z)
            model.eulerAngles.y = yaw
            model.castsShadow = false
            scene.rootNode.addChildNode(model)
            let blob = Paint.shadow()
            blob.simdPosition = SIMD3<Float>(x + at.x, 0.004, at.z)
            blob.simdScale = SIMD3<Float>(size * 2.9, size * 2.9, 1)
            scene.rootNode.addChildNode(blob)
        }

        let hanging = Claw(dome: clawTint, trim: Tint.cream, face: false)
        hanging.node.simdPosition = SIMD3<Float>(x - 0.3 * (x < 0 ? -1 : 1), Box.top - 0.45, -0.8)
        hanging.node.castsShadow = false
        scene.rootNode.addChildNode(hanging.node)
        let wire = SCNCylinder(radius: 0.012, height: 0.28)
        wire.firstMaterial = Paint.gloss(0xB9B3D6)
        let wireNode = SCNNode(geometry: wire)
        wireNode.simdPosition = hanging.node.simdPosition + SIMD3<Float>(0, 0.32, 0)
        wireNode.castsShadow = false
        scene.rootNode.addChildNode(wireNode)
    }
}
