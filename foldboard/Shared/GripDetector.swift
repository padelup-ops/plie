import CoreMotion
import UIKit

/// La main qui tient le téléphone.
enum KBGrip: String, Codable {
    case left, right, two
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

    /// Main droite et main gauche étalonnées pour cette situation : l'inclinaison décide seule.
    var calibrated: Bool { postures[.right] != nil && postures[.left] != nil }

    /// Seuil d'inclinaison : un tiers de l'écart étalonné (plus réactif), sinon une valeur prudente.
    private var switchThreshold: Double { tiltGap >= 4 ? max(3, tiltGap * 0.3) : 9 }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private let lock = NSLock()
    private var samples: [(t: TimeInterval, y: Double)] = []
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
                self.samples.append((m.timestamp, m.rotationRate.y))
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
        guard ranked[1].1 - ranked[0].1 >= margin else { return nil }
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
        let threshold: Double = current == .two ? switchThreshold + 5 : switchThreshold
        guard let g = tiltGrip(threshold: threshold) else { tiltStreak = nil; return }
        // Étalonné : l'inclinaison a le dernier mot (le clavier revient toujours du bon côté).
        // Sinon, on ne réagit qu'à un vrai changement d'inclinaison.
        if calibrated ? g == current : g == tiltSide { tiltStreak = nil; return }
        let n = (tiltStreak?.grip == g ? tiltStreak!.n : 0) + 1
        tiltStreak = (g, n)
        // 3 lectures de suite (≈ 0,45 s) : assez pour ignorer un geste, assez vite pour suivre un changement de main.
        guard n >= 3 else { return }
        tiltSide = g
        tiltStreak = nil
        // Pas de retour à une main tant que deux pouces tapent encore.
        if current == .two && twoEvidence.suffix(8).contains(true) { return }
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
        var two = others.contains { abs($0 - screenX) > 0.3 }
        if let last = lastTap, abs(last.x - screenX) > 0.45, time - last.t > 0, time - last.t < 0.13 { two = true }
        lastTap = (screenX, time)
        twoEvidence.append(two)
        if twoEvidence.count > 12 { twoEvidence.removeFirst() }

        let region = blockX < 1.0 / 3 ? 0 : (blockX > 2.0 / 3 ? 2 : 1)
        if region != 1, radius > 0 {
            if region == 0 { push(&sizeLeft, Double(radius)) } else { push(&sizeRight, Double(radius)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { [weak self] in
            guard let self else { return }
            if region != 1, let v = self.variance(from: time, to: time + 0.25) {
                if region == 0 { self.push(&self.rotLeft, v) } else { self.push(&self.rotRight, v) }
            }
            self.decide()
        }
    }

    /// Un balayage du pouce (au moins 40 points de haut) : le sens de l'arc donne la main.
    func swipe(_ pts: [CGPoint]) {
        guard !calibrated, pts.count >= 5, let first = pts.first, let last = pts.last, abs(last.y - first.y) >= 40 else { return }
        // Écart signé entre le point le plus éloigné et la corde (premier → dernier point).
        let dx = last.x - first.x, dy = last.y - first.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        var best: CGFloat = 0
        for p in pts {
            let d = ((p.x - first.x) * dy - (p.y - first.y) * dx) / len
            if abs(d) > abs(best) { best = d }
        }
        guard abs(best) >= 3 else { return }
        // Le pouce droit pivote en bas à droite : l'arc se creuse vers la gauche de la corde, quel que soit le sens.
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
        if current == .two && twoEvidence.suffix(8).contains(true) { return }
        // Deux décisions de suite avant de déplacer le clavier.
        if lastVote == result { emit(result) }
        lastVote = result
    }

    private func emit(_ g: KBGrip) {
        guard g != current else { return }
        current = g
        onGrip?(g)
    }
}
