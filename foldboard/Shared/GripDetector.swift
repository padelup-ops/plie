import CoreMotion
import UIKit

/// La main qui tient le téléphone.
enum KBGrip: String, Codable {
    case left, right, two
}

/// Les appuis étalonnés d'une situation : à chaque nouvel appui, les exemples les plus proches votent
/// (k plus proches voisins, après mise à l'échelle de chaque mesure). Idée : « Know Your Grip » (Electronics 2024),
/// la réponse du gyroscope à chaque appui sépare très bien main droite, main gauche et deux mains.
struct KBTapModel {
    enum Kind { case tap, swipe }
    private var points: [(grip: KBGrip, f: [Double])] = []
    private var mean: [Double] = []
    private var sd: [Double] = []
    private var rollMid: Double = 0
    let grips: [KBGrip]
    private let count: Int
    private let rollIndex: Int
    private let weights: [Double]
    private let minSD: [Double]

    /// Appuis : rotation (3), secousse (3), inclinaison, angle avec l'horizontale, position, taille.
    /// Glissements : flèche de l'arc, sens, départ, arrivée, rotation (3), inclinaison.
    init?(_ raw: [String: [[Double]]], kind: Kind = .tap) {
        switch kind {
        case .tap:
            count = GripDetector.featureCount; rollIndex = GripDetector.rollIndex
            weights = [1.2, 1.2, 1.2, 0.8, 0.8, 0.8, 1.0, 0.5, 0.7, 0.5]
            minSD = [0.002, 0.002, 0.002, 0.02, 0.02, 0.02, 2, 2, 0.05, 1]
        case .swipe:
            count = GripDetector.swipeFeatureCount; rollIndex = GripDetector.swipeRollIndex
            weights = [2.0, 1.2, 1.0, 1.0, 0.8, 0.8, 0.8, 0.8]
            minSD = [0.01, 0.02, 0.03, 0.03, 0.002, 0.002, 0.002, 2]
        }
        let need = kind == .tap ? 6 : 3
        let size = count
        var by: [KBGrip: [[Double]]] = [:]
        for (k, v) in raw {
            guard let g = KBGrip(rawValue: k) else { continue }
            let ok = v.filter { $0.count == size }
            if ok.count >= need { by[g] = ok }
        }
        guard by.count >= 2 else { return nil }
        grips = Array(by.keys)
        let all = by.values.flatMap { $0 }
        let ri = rollIndex
        let r0 = all[0][ri]
        rollMid = kbWrap(r0 + all.map { kbWrap($0[ri] - r0) }.reduce(0, +) / Double(all.count))
        let centered = all.map(center)
        let n = Double(centered.count)
        mean = (0..<count).map { i in centered.map { $0[i] }.reduce(0, +) / n }
        sd = (0..<count).map { i in
            let m = mean[i]
            let v = centered.map { ($0[i] - m) * ($0[i] - m) }.reduce(0, +) / n
            return max(v.squareRoot(), minSD[i])
        }
        for (g, list) in by { for f in list { points.append((g, scale(center(f)))) } }
    }

    private func center(_ f: [Double]) -> [Double] {
        var c = f
        c[rollIndex] = kbWrap(f[rollIndex] - rollMid)
        return c
    }

    private func scale(_ f: [Double]) -> [Double] {
        (0..<f.count).map { i in (f[i] - mean[i]) / sd[i] * weights[i] }
    }

    /// Probabilité de chaque prise pour cet appui.
    func probabilities(_ raw: [Double]) -> [KBGrip: Double] {
        guard raw.count == count else { return [:] }
        let f = scale(center(raw))
        let ranked = points.map { p -> (KBGrip, Double) in
            var d = 0.0
            for i in 0..<f.count { d += (f[i] - p.f[i]) * (f[i] - p.f[i]) }
            return (p.grip, d)
        }.sorted { $0.1 < $1.1 }
        let k = max(3, min(7, points.count / 3))
        var votes: [KBGrip: Double] = [:]
        for (i, r) in ranked.prefix(k).enumerated() { votes[r.0, default: 0] += 1.0 / Double(i + 1) }
        let total = votes.values.reduce(0, +)
        var out: [KBGrip: Double] = [:]
        for g in grips { out[g] = ((votes[g] ?? 0) + 0.15) / (total + 0.15 * Double(grips.count)) }
        return out
    }
}

/// Un écart d'angle ramené entre -180° et 180° (179° et -179° sont voisins).
func kbWrap(_ d: Double) -> Double {
    var x = d.truncatingRemainder(dividingBy: 360)
    if x > 180 { x -= 360 } else if x < -180 { x += 360 }
    return x
}

/// Devine la main qui tient le téléphone, pour que le clavier vienne du bon côté.
///
/// 1. L'inclinaison, dès que le clavier apparaît : tenu dans une main, le téléphone penche vers cette main.
/// 2. Pendant la frappe, la méthode GripSense (Goel et al., UIST 2012) : quand le pouce va chercher les touches
///    du côté opposé à la main, le téléphone tourne davantage dans la main (gyroscope) et le pouce s'aplatit
///    (le toucher est plus large). Plus grand du côté gauche → main droite, et inversement.
/// 3. Le balayage du pouce trace un arc dont le sens donne la main (GripSense, et Adaptive App Design by Detecting Handedness).
/// 4. Deux pouces : deux touchers en même temps, loin l'un de l'autre, ou un aller-retour trop rapide pour un seul pouce.
final class GripDetector {
    var current: KBGrip?
    var onGrip: ((KBGrip) -> Void)?
    /// Réglage de l'inclinaison (voir l'étalonnage dans l'app) : l'angle « droit », et le sens de la main droite.
    var tiltMid: Double = 0
    var rightNegative = true
    /// Écart d'inclinaison entre main droite et main gauche (étalonnage), en degrés ; 0 si inconnu.
    var tiltGap: Double = 0
    /// Postures étalonnées (inclinaison, angle avec l'horizontale) : main droite, main gauche, deux mains.
    var postures: [KBGrip: (roll: Double, incline: Double)] = [:]
    /// Sans étalonnage, deviner quand même avec les capteurs (non sur le Duo ouvert : ses capteurs ne sont pas
    /// dans le sens de l'écran intérieur, la devinette serait à l'envers).
    var guessUncalibrated = true

    /// Main droite et main gauche étalonnées pour cette situation.
    var calibrated: Bool { postures[.right] != nil && postures[.left] != nil }
    /// Les appuis étalonnés (étalonnage par la frappe) : ce sont eux qui décident pendant la frappe.
    var tapModel: KBTapModel? { didSet { evidence = [:]; evidenceTaps = 0 } }
    /// Étalonnage dans l'app : chaque appui est envoyé ici au lieu de déplacer le clavier.
    var onSample: (([Double]) -> Void)?

    /// Mesures d'un appui : rotation (x, y, z), secousse (x, y, z), inclinaison, angle avec l'horizontale, position, taille.
    static let featureCount = 10
    static let rollIndex = 6
    static let swipeFeatureCount = 8
    static let swipeRollIndex = 7

    /// Les glissements étalonnés (le pouce glisse vers le haut sur les touches) : le geste le plus sûr.
    var swipeModel: KBTapModel?
    /// Étalonnage dans l'app : chaque glissement est envoyé ici.
    var onSwipeSample: (([Double]) -> Void)?
    /// Le dernier déplacement automatique : on laisse le clavier tranquille quelques secondes ensuite.
    private var lastEmit: TimeInterval = 0
    /// La dernière lecture d'inclinaison était franche (la posture étalonnée la plus proche l'est nettement).
    private var tiltStrong = false
    /// Le dernier moment où deux pouces ont tapé ensemble.
    private var lastTwo: TimeInterval = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var evidence: [KBGrip: Double] = [:]
    private var evidenceTaps = 0
    private var lastTapTime: TimeInterval = 0

    /// Seuil d'inclinaison : un tiers de l'écart étalonné (plus réactif), sinon une valeur prudente.
    private var switchThreshold: Double { tiltGap >= 4 ? max(3, tiltGap * 0.3) : 9 }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private let lock = NSLock()
    private var samples: [(t: TimeInterval, x: Double, y: Double, z: Double)] = []
    private var angle: Double?
    private var incline: Double?
    private var planar: Double = 0
    private var tiltTimer: Timer?
    private var tiltStreak: (grip: KBGrip, n: Int)?
    /// Le côté donné par l'inclinaison à la dernière lecture : on ne réagit qu'à un vrai changement de main.
    private var tiltSide: KBGrip?

    private var rotLeft: [Double] = []
    private var rotRight: [Double] = []
    private var sizeLeft: [Double] = []
    private var sizeRight: [Double] = []
    private var lastTap: (x: CGFloat, t: TimeInterval)?
    private var twoEvidence: [Bool] = []
    private var lastVote: KBGrip?

    // MARK: Capteurs

    func start(initial: @escaping (KBGrip?) -> Void) {
        reset()
        guard motion.isDeviceMotionAvailable else { initial(nil); return }
        if !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 100
            motion.startDeviceMotionUpdates(to: queue) { [weak self] m, _ in
                guard let self, let m else { return }
                let g = m.gravity
                let p = (g.x * g.x + g.y * g.y).squareRoot()
                let a = atan2(g.x, -g.y) * 180 / .pi
                let inc = asin(max(-1, min(1, -g.z))) * 180 / .pi
                self.lock.lock()
                self.incline = self.incline.map { $0 * 0.85 + inc * 0.15 } ?? inc
                self.samples.append((m.timestamp, m.rotationRate.x, m.rotationRate.y, m.rotationRate.z))
                if self.samples.count > 200 { self.samples.removeFirst(self.samples.count - 200) }
                self.planar = p
                self.angle = self.angle.map { kbWrap($0 + kbWrap(a - $0) * 0.15) } ?? a
                self.lock.unlock()
            }
        }
        // Comme le clavier qui « suit la main » : un quart de seconde pour lire l'inclinaison, puis on place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let g = self.tiltGrip(threshold: min(5, self.switchThreshold))
            self.tiltSide = g
            initial(g)
        }
        tiltTimer?.invalidate()
        tiltTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.checkTilt() }
    }

    func stop() {
        tiltTimer?.invalidate()
        tiltTimer = nil
        motion.stopDeviceMotionUpdates()
        lock.lock()
        samples.removeAll()
        angle = nil
        lock.unlock()
    }

    func reset() {
        rotLeft = []; rotRight = []; sizeLeft = []; sizeRight = []
        lastTap = nil; twoEvidence = []; lastVote = nil; tiltStreak = nil; tiltSide = nil
        evidence = [:]; evidenceTaps = 0
    }

    /// Les mesures d'un appui, une fois le mouvement du téléphone enregistré (un quart de seconde).
    private func features(time: TimeInterval, screenX: CGFloat, radius: CGFloat) -> [Double]? {
        lock.lock()
        let w = samples.filter { $0.t >= time - 0.02 && $0.t <= time + 0.25 }
        let roll = angle, inc = incline
        lock.unlock()
        guard w.count >= 8, let roll, let inc else { return nil }
        var ix = 0.0, iy = 0.0, iz = 0.0, px = 0.0, py = 0.0, pz = 0.0
        let base = w.prefix(3)
        let bx = base.map { $0.x }.reduce(0, +) / Double(base.count)
        let by = base.map { $0.y }.reduce(0, +) / Double(base.count)
        let bz = base.map { $0.z }.reduce(0, +) / Double(base.count)
        for s in w {
            let x = s.x - bx, y = s.y - by, z = s.z - bz
            ix += x * 0.01; iy += y * 0.01; iz += z * 0.01
            px = max(px, abs(x)); py = max(py, abs(y)); pz = max(pz, abs(z))
        }
        return [ix, iy, iz, px, py, pz, roll, inc, Double(screenX), Double(radius)]
    }

    /// Un appui de plus dans la balance : on garde la mémoire des derniers appuis (les plus récents comptent plus).
    private func weigh(_ f: [Double]) {
        guard let m = tapModel else { return }
        let p = m.probabilities(f)
        guard !p.isEmpty else { return }
        for g in m.grips { evidence[g] = (evidence[g] ?? 0) * 0.7 + log(p[g] ?? 0.05) }
        evidenceTaps += 1
        let ranked = evidence.sorted { $0.value > $1.value }
        // Prudent : au moins 6 appuis, un net avantage, et pas de nouveau déplacement avant 6 secondes.
        guard evidenceTaps >= 4, ranked.count >= 2, ranked[0].value - ranked[1].value > 2.0 else { return }
        let g = ranked[0].key
        guard g != current, now - lastEmit > 2.5 else { return }
        if current == .two && g != .two && now - lastTwo < 2 { return }
        evidence = [:]; evidenceTaps = 0
        emit(g)
    }

    /// L'angle actuel du téléphone dans le plan de l'écran (pour l'étalonnage), en degrés.
    var currentAngle: Double? {
        lock.lock(); defer { lock.unlock() }
        return planar > 0.35 ? angle : nil
    }

    /// L'inclinaison et l'angle avec l'horizontale en ce moment (pour l'étalonnage).
    var currentPosture: (roll: Double, incline: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard planar > 0.2, let a = angle, let i = incline else { return nil }
        return (a, i)
    }

    /// Avec les postures étalonnées (droite, gauche, et deux mains si faite) : la plus proche, avec une petite marge
    /// pour ne pas hésiter à la frontière.
    private func postureGrip() -> KBGrip? {
        guard calibrated, let now = currentPosture, let r = postures[.right], let l = postures[.left] else { return nil }
        let ranked = postures.map { (g, p) -> (KBGrip, Double) in
            let dr = kbWrap(now.roll - p.roll), di = (now.incline - p.incline) * 0.3
            return (g, (dr * dr + di * di).squareRoot())
        }.sorted { $0.1 < $1.1 }
        guard ranked.count >= 2 else { return ranked.first?.0 }
        let margin = max(1.5, abs(kbWrap(r.roll - l.roll)) * 0.1)
        let gap = ranked[1].1 - ranked[0].1
        guard gap >= margin else { tiltStrong = false; return nil }
        tiltStrong = gap >= margin * 3
        return ranked[0].0
    }

    /// La main d'après l'inclinaison, si le téléphone n'est pas posé à plat et penche assez.
    private func tiltGrip(threshold: Double) -> KBGrip? {
        if calibrated { return postureGrip() }
        if tiltGap < 4 && !guessUncalibrated { return nil }
        guard let a = currentAngle else { return nil }
        let d = kbWrap(a - tiltMid)
        guard abs(d) >= threshold else { return nil }
        let negative = d < 0
        return negative == rightNegative ? .right : .left
    }

    /// En continu : si le téléphone change franchement de main, le clavier suit.
    private func checkTilt() {
        // L'inclinaison place le clavier quand il apparaît ; ensuite, elle ne le bouge que si le téléphone change
        // franchement de main pendant une pause (pas de frappe depuis 2 s, rien bougé depuis 5 s).
        if now - lastTapTime < 0.6 || now - lastEmit < 1.2 { tiltStreak = nil; return }
        let threshold: Double = current == .two ? switchThreshold + 5 : switchThreshold
        guard let g = tiltGrip(threshold: threshold) else { tiltStreak = nil; return }
        // Étalonné : l'inclinaison a le dernier mot (le clavier revient toujours du bon côté).
        // Sinon, on ne réagit qu'à un vrai changement d'inclinaison.
        if g == tiltSide || g == current { tiltSide = g; tiltStreak = nil; return }
        let n = (tiltStreak?.grip == g ? tiltStreak!.n : 0) + 1
        tiltStreak = (g, n)
        // Franc : 2 lectures (0,3 s). Sinon 4 (0,6 s) : on ignore les gestes, on suit un vrai changement de main.
        guard n >= (tiltStrong ? 2 : 4) else { return }
        tiltSide = g
        tiltStreak = nil
        // Pas de retour à une main tant que deux pouces tapent encore (dans les 2 dernières secondes).
        if current == .two && now - lastTwo < 2 { return }
        emit(g)
    }

    private func variance(from a: TimeInterval, to b: TimeInterval) -> Double? {
        lock.lock()
        let ys = samples.filter { $0.t >= a && $0.t <= b }.map { $0.y }
        lock.unlock()
        guard ys.count >= 5 else { return nil }
        let m = ys.reduce(0, +) / Double(ys.count)
        return ys.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(ys.count)
    }

    // MARK: Touchers (GripSense)

    /// Un appui. `blockX` : 0…1 sur la largeur des touches ; `screenX` : 0…1 sur l'écran ;
    /// `others` : `screenX` des autres doigts posés ; `radius` : taille du toucher.
    func tap(blockX: CGFloat, screenX: CGFloat, radius: CGFloat, time: TimeInterval, others: [CGFloat]) {
        let together = others.contains { abs($0 - screenX) > 0.3 }
        var two = together
        if let last = lastTap, abs(last.x - screenX) > 0.45, time - last.t > 0, time - last.t < 0.13 { two = true }
        if two && onSample == nil {
            lastTwo = now
            // Deux doigts posés en même temps, loin l'un de l'autre : aucun doute, tout de suite au milieu.
            if together && current != .two { emit(.two) }
        }
        lastTap = (screenX, time)
        lastTapTime = time
        if let onSample {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self, let f = self.features(time: time, screenX: screenX, radius: radius) else { return }
                onSample(f)
            }
            return
        }
        twoEvidence.append(two)
        if twoEvidence.count > 12 { twoEvidence.removeFirst() }

        let region = blockX < 1.0 / 3 ? 0 : (blockX > 2.0 / 3 ? 2 : 1)
        if region != 1, radius > 0 {
            if region == 0 { push(&sizeLeft, Double(radius)) } else { push(&sizeRight, Double(radius)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self else { return }
            if self.tapModel != nil {
                if self.twoEvidence.filter({ $0 }).count >= 2 { self.emit(.two); return }
                if let f = self.features(time: time, screenX: screenX, radius: radius) { self.weigh(f) }
                return
            }
            if region != 1, let v = self.variance(from: time, to: time + 0.25) {
                if region == 0 { self.push(&self.rotLeft, v) } else { self.push(&self.rotRight, v) }
            }
            self.decide()
        }
    }

    /// Les mesures d'un glissement du pouce : forme de l'arc (normalisée), départ et arrivée sur la largeur,
    /// rotation du téléphone pendant le geste, inclinaison.
    private func swipeFeatures(_ pts: [CGPoint], width: CGFloat, t0: TimeInterval, t1: TimeInterval) -> [Double]? {
        guard pts.count >= 5, let first = pts.first, let last = pts.last, width > 0 else { return nil }
        let dx = last.x - first.x, dy = last.y - first.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        guard abs(dy) >= 40 else { return nil }
        var best: CGFloat = 0
        for p in pts {
            let d = ((p.x - first.x) * dy - (p.y - first.y) * dx) / len
            if abs(d) > abs(best) { best = d }
        }
        // Toujours dans le même sens de lecture (vers le haut) : on retourne l'arc d'un geste vers le bas.
        let sag = Double(dy > 0 ? -best : best) / Double(len)
        lock.lock()
        let w = samples.filter { $0.t >= t0 && $0.t <= max(t1, t0 + 0.1) }
        let roll = angle
        lock.unlock()
        guard let roll else { return nil }
        let rx = w.reduce(0) { $0 + $1.x * 0.01 }, ry = w.reduce(0) { $0 + $1.y * 0.01 }, rz = w.reduce(0) { $0 + $1.z * 0.01 }
        return [sag, Double(dx / len) * (dy > 0 ? -1 : 1), Double(first.x / width), Double(last.x / width), rx, ry, rz, roll]
    }

    /// Un glissement du pouce (au moins 40 points de haut). Étalonné : les glissements enregistrés votent
    /// (k plus proches voisins, comme Löchtefeld et al. 2015 avec le geste de déverrouillage : 98,5 %).
    /// Sinon, le sens de l'arc : le pouce droit pivote en bas à droite, l'arc se creuse vers la gauche de la corde.
    func swipe(_ pts: [CGPoint], width: CGFloat, t0: TimeInterval, t1: TimeInterval) {
        let f = swipeFeatures(pts, width: width, t0: t0, t1: t1)
        if let onSwipeSample {
            if let f { onSwipeSample(f) }
            return
        }
        if let m = swipeModel, let f {
            let p = m.probabilities(f)
            if let top = p.max(by: { $0.value < $1.value }), top.value >= 0.6, top.key != .two {
                emit(top.key)
                return
            }
        }
        guard let first = pts.first, let last = pts.last, pts.count >= 5, abs(last.y - first.y) >= 40 else { return }
        let dx = last.x - first.x, dy = last.y - first.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        var best: CGFloat = 0
        for p in pts {
            let d = ((p.x - first.x) * dy - (p.y - first.y) * dx) / len
            if abs(d) > abs(best) { best = d }
        }
        guard abs(best) >= 3 else { return }
        let bulgeLeft = (dy > 0) ? best < 0 : best > 0
        emit(bulgeLeft ? .right : .left)
    }

    private func push(_ a: inout [Double], _ v: Double) {
        a.append(v)
        if a.count > 2 { a.removeFirst() }
    }

    private func vote(_ l: [Double], _ r: [Double], bias: Double, high: Double) -> (grip: KBGrip, high: Bool)? {
        guard !l.isEmpty, !r.isEmpty else { return nil }
        let ml = l.reduce(0, +) / Double(l.count)
        let mr = r.reduce(0, +) / Double(r.count)
        guard ml > 0, mr > 0 else { return nil }
        if ml / mr > bias { return (.right, ml / mr > high) }
        if mr / ml > bias { return (.left, mr / ml > high) }
        return nil
    }

    private func decide() {
        if twoEvidence.filter({ $0 }).count >= 2 {
            emit(.two)
            return
        }
        // Étalonné : seule l'inclinaison place le clavier d'un côté (les touchers ne servent qu'aux deux pouces).
        if calibrated { return }
        // Gyroscope seulement quand ses axes suivent l'écran (pas sur le Duo ouvert).
        let rot = guessUncalibrated ? vote(rotLeft, rotRight, bias: 2, high: 6) : nil
        let size = vote(sizeLeft, sizeRight, bias: 1.25, high: 1.4)
        var result: KBGrip?
        if let r = rot, let s = size {
            if r.grip == s.grip { result = r.grip }
            else if r.high && !s.high { result = r.grip }
            else if s.high && !r.high { result = s.grip }
        } else if let r = rot, r.high {
            result = r.grip
        } else if let s = size, s.high {
            result = s.grip
        }
        guard let result else { return }
        if current == .two && now - lastTwo < 2 { return }
        // Deux décisions de suite avant de déplacer le clavier, et pas plus d'un déplacement toutes les 4 secondes.
        if lastVote == result && now - lastEmit > 4 { emit(result) }
        lastVote = result
    }

    private func emit(_ g: KBGrip) {
        guard g != current else { return }
        current = g
        lastEmit = now
        onGrip?(g)
    }
}
