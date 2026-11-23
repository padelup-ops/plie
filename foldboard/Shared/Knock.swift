// Knock.swift — Foldboard
//
// Taper le bord de l'iPhone (le cadre, à gauche ou à droite) met le clavier à une main de ce côté.
//
// Un coup du bout du doigt sur le côté pousse le téléphone de travers d'un coup sec : un pic d'accélération
// sur l'axe gauche-droite, souvent avec une petite rotation (le téléphone pivote autour de la main qui le
// tient : le gyroscope la voit très bien, même quand l'accélération est faible — l'idée de la détection de
// coups « aidée par le gyroscope »). On attend 80 ms après le pic pour juger le coup en entier :
//  - toucher l'écran pousse le téléphone d'avant en arrière (axe z) : refusé ;
//  - un coup est bref : si le mouvement continue après le pic, c'est la main qui bouge : refusé ;
//  - un doigt sur l'écran juste avant ou pendant : c'est une frappe : refusé.
// Le seuil s'adapte au bruit (dans le bus, en marchant) et à la sensibilité choisie dans les réglages.

import CoreMotion
import Foundation

/// Un seul gestionnaire de capteurs pour tout le clavier : Apple déconseille d'en créer plusieurs (ils se
/// gênent et donnent moins de mesures). Chacun s'abonne au rythme qu'il veut.
final class KBMotion {
    static let shared = KBMotion()
    private let manager = CMMotionManager()
    let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "foldboard.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private struct Sub { var rate: Double; var last: TimeInterval; var f: (CMDeviceMotion) -> Void }
    private var subs: [UUID: Sub] = [:]
    private var currentRate = 0.0
    private let lock = NSLock()

    var available: Bool { manager.isDeviceMotionAvailable }

    func subscribe(rate: Double, _ f: @escaping (CMDeviceMotion) -> Void) -> UUID {
        let id = UUID()
        lock.lock(); subs[id] = Sub(rate: rate, last: 0, f: f); lock.unlock()
        restart()
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock(); subs[id] = nil; lock.unlock()
        restart()
    }

    private func restart() {
        lock.lock(); let rate = subs.values.map(\.rate).max(); lock.unlock()
        guard let rate else {
            if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
            return
        }
        // Un nouveau rythme : on relance les mesures pour qu'il s'applique tout de suite.
        if manager.isDeviceMotionActive, rate != currentRate { manager.stopDeviceMotionUpdates() }
        currentRate = rate
        manager.deviceMotionUpdateInterval = 1.0 / rate
        guard !manager.isDeviceMotionActive, available else { return }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] m, _ in
            guard let self, let m else { return }
            self.lock.lock()
            var due: [(CMDeviceMotion) -> Void] = []
            for (k, s) in self.subs where m.timestamp - s.last >= 0.9 / s.rate {
                self.subs[k]?.last = m.timestamp
                due.append(s.f)
            }
            self.lock.unlock()
            due.forEach { $0(m) }
        }
    }
}

/// Ce que le capteur a vu d'un coup (pour l'essai dans l'app et pour régler la détection).
struct KBKnockProbe {
    /// La force du coup par rapport au seuil (1 = juste assez).
    var strength: Double
    var pushedRight: Bool
    var accepted: Bool
    /// Pourquoi il a été refusé : "screen", "moving", "long", "touch", "soon".
    var reason: String?
    var line: String
}

final class KBKnock {
    /// true : le coup a poussé le téléphone vers la droite de l'appareil (on a tapé son bord gauche).
    var onKnock: ((Bool) -> Void)?
    /// Chaque coup vu, accepté ou non (essai dans l'app).
    var onProbe: ((KBKnockProbe) -> Void)?
    /// La force du mouvement en ce moment, par rapport au seuil (1 = un coup serait compté), dix fois par
    /// seconde : la jauge de l'essai dans l'app.
    var onLevel: ((Double) -> Void)?
    private var levelMax = 0.0
    private var levelCount = 0
    /// L'instant du dernier toucher à l'écran (horloge des événements), mis à jour par le clavier.
    var lastTouch: TimeInterval = 0
    /// 0 : il faut taper franchement … 1 : un petit coup suffit.
    var sensitivity: Double = 0.6
    /// Les derniers coups vus, pour « Copier les données pour le développeur » (sur le fil principal).
    private(set) var log: [String] = []

    private struct S { var t, ax, ay, az, gz, gy: Double }
    private var buf: [S] = []
    private var pending: (t: TimeInterval, th: Double)?
    private var lastKnock: TimeInterval = 0
    private var noise = 0.02
    private var sub: UUID?

    var running: Bool { sub != nil }

    func start() {
        guard sub == nil, KBMotion.shared.available else { return }
        buf = []
        pending = nil
        sub = KBMotion.shared.subscribe(rate: 100) { [weak self] m in self?.process(m) }
    }

    func stop() {
        if let s = sub { KBMotion.shared.unsubscribe(s) }
        sub = nil
    }

    /// Seuils : accélération (g) et rotation (rad/s), du plus franc (sensibilité 0) au plus léger (1).
    private var accT: Double { 0.30 - 0.21 * max(0, min(1, sensitivity)) }
    private var gyroT: Double { 1.4 - 1.0 * max(0, min(1, sensitivity)) }

    private func process(_ m: CMDeviceMotion) {
        let u = m.userAcceleration, r = m.rotationRate
        let s = S(t: m.timestamp, ax: u.x, ay: u.y, az: u.z, gz: r.z, gy: r.y)
        buf.append(s)
        if buf.count > 70 { buf.removeFirst(buf.count - 70) }
        if let p = pending {
            if s.t - p.t >= 0.08 { decide(p.t, th: p.th); pending = nil }
            return
        }
        guard buf.count >= 40 else { noise = noise * 0.95 + abs(s.ax) * 0.05; return }
        // Le seuil monte avec le bruit ambiant (marche, transports), jamais en dessous du réglage.
        let th = max(accT, noise * 5)
        let sx = abs(s.ax) / th
        let sg = max(abs(s.gz), abs(s.gy)) / gyroT
        if let onLevel {
            levelMax = max(levelMax, sx, min(sx * 2, sg))
            levelCount += 1
            if levelCount >= 10 {
                let v = levelMax
                levelMax = 0; levelCount = 0
                DispatchQueue.main.async { onLevel(v) }
            }
        }
        if sx >= 1 || (sx >= 0.5 && sg >= 1) {
            pending = (s.t, th)
        } else {
            noise = noise * 0.97 + abs(s.ax) * 0.03
        }
    }

    private func decide(_ t0: TimeInterval, th: Double) {
        guard let i0 = buf.firstIndex(where: { $0.t >= t0 }) else { return }
        let n = buf.count
        let before = buf[max(0, i0 - 30)..<max(0, i0 - 2)]
        let win = buf[max(0, i0 - 1)...min(n - 1, i0 + 3)]
        let after: ArraySlice<S> = i0 + 5 < n ? buf[(i0 + 5)...] : []
        let px = win.map { abs($0.ax) }.max() ?? 0
        let pz = win.map { abs($0.az) }.max() ?? 0
        let pg = win.map { max(abs($0.gz), abs($0.gy)) }.max() ?? 0
        let calm = before.isEmpty ? 0 : before.map { abs($0.ax) + abs($0.az) }.reduce(0, +) / Double(before.count)
        let tail = after.isEmpty ? 0 : after.map { abs($0.ax) }.reduce(0, +) / Double(after.count)
        // Le sens : la première poussée nette (le rebond qui suit va dans l'autre sens).
        let first = win.first(where: { abs($0.ax) >= px * 0.5 }) ?? buf[i0]
        let pushedRight = first.ax > 0
        var reason: String?
        if pz > px * 1.3 { reason = "screen" }
        else if lastTouch > t0 - 0.2 { reason = "touch" }
        else if calm > max(0.08, px * 0.45) { reason = "moving" }
        else if tail > px * 0.6 { reason = "long" }
        else if t0 - lastKnock < 0.6 { reason = "soon" }
        let strength = max(px / th, min(px / th * 2, pg / gyroT))
        let line = String(format: "%@ %@ x%.2f z%.2f g%.2f calme%.2f suite%.2f seuil%.2f bruit%.3f sens%.1f",
                          reason ?? "ok", pushedRight ? "→" : "←", px, pz, pg, calm, tail, th, noise, sensitivity)
        let probe = KBKnockProbe(strength: strength, pushedRight: pushedRight, accepted: reason == nil, reason: reason, line: line)
        if reason == nil { lastKnock = t0 }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.log.append(line)
            if self.log.count > 40 { self.log.removeFirst(self.log.count - 40) }
            self.onProbe?(probe)
            if probe.accepted { self.onKnock?(pushedRight) }
        }
    }
}
