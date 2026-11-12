import Foundation

/// Le deuxième indice de la main : où le pouce tombe sur les touches.
///
/// Un pouce droit et un pouce gauche n'arrivent pas sur les touches de la même façon : le pouce droit touche
/// un peu à gauche du centre des touches éloignées (côté gauche du clavier), le gauche l'inverse. Ce décalage
/// ne dépend pas de l'inclinaison du téléphone, il aide donc quand on tient le Duo presque pareil des deux mains.
///
/// Le clavier l'apprend en tapant : quand une série de lettres est tapée sans corriger le côté, les appuis de
/// cette série sont rangés sous cette main. Pour décider, on compare les derniers appuis aux deux mains.
final class KBThumb {
    static let shared = KBThumb()
    private let key = "foldboard.thumb.v1"
    private static let bins = 5

    /// Moyenne et dispersion d'une mesure, par main (0 gauche, 1 droite) et par zone du clavier (5 tranches).
    private struct Stat: Codable {
        var n = 0.0; var mean = 0.0; var m2 = 0.0
        mutating func add(_ v: Double) {
            n = min(n + 1, 200)
            let d = v - mean
            mean += d / n
            m2 = m2 * (1 - 1 / n) + d * (v - mean)
        }
    }
    /// Les mesures apprises : 0 décalage du pouce sur la touche, 1 à 3 réaction du téléphone (rotation x, y, z).
    private static let features = 4
    private var stats: [String: [[Stat]]] = [:]
    private var kicks: [String: [[[Stat]]]] = [:]
    /// La taille du toucher (rayon, en points), par main et par zone : un pouce qui arrive de biais s'écrase autrement.
    private var sizes: [String: [[Stat]]] = [:]
    /// Les étalonnages de l'app déjà repris (situation → date de l'étalonnage).
    private var seeded: [String: Double] = [:]
    /// Les derniers appuis (zone du clavier 0…1, décalage par rapport au centre de la touche, en largeurs de touche,
    /// et la réaction du téléphone quand elle est connue).
    private struct Tap { var kx: Double; var dx: Double; var r: Double; var t: TimeInterval; var kick: [Double]? }
    private var recent: [Tap] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([String: [[Stat]]].self, from: d) {
            stats = s
        }
        if let d = UserDefaults.standard.data(forKey: key + ".kick"), let s = try? JSONDecoder().decode([String: [[[Stat]]]].self, from: d) {
            kicks = s
        }
        if let d = UserDefaults.standard.data(forKey: key + ".size"), let s = try? JSONDecoder().decode([String: [[Stat]]].self, from: d) {
            sizes = s
        }
        seeded = (UserDefaults.standard.dictionary(forKey: key + ".seeded") as? [String: Double]) ?? [:]
    }

    private func save() {
        if let d = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(d, forKey: key) }
        if let d = try? JSONEncoder().encode(kicks) { UserDefaults.standard.set(d, forKey: key + ".kick") }
        if let d = try? JSONEncoder().encode(sizes) { UserDefaults.standard.set(d, forKey: key + ".size") }
        UserDefaults.standard.set(seeded, forKey: key + ".seeded")
    }

    private static func bin(_ kx: Double) -> Int { max(0, min(bins - 1, Int(kx * Double(bins)))) }

    /// Un appui sur une lettre.
    func tap(kx: Double, dx: Double, radius: Double = 0, time: TimeInterval) {
        guard abs(dx) < 0.9 else { return }
        recent.append(Tap(kx: kx, dx: dx, r: radius, t: time, kick: nil))
        if recent.count > 24 { recent.removeFirst(recent.count - 24) }
    }

    /// La réaction du téléphone à l'appui de ce moment (connue un quart de seconde après).
    func kick(time: TimeInterval, _ k: (x: Double, y: Double, z: Double)) {
        guard let i = recent.lastIndex(where: { abs($0.t - time) < 0.001 }) else { return }
        recent[i].kick = [k.x, k.y, k.z]
    }

    /// Le clavier vient de changer de côté (ou d'être corrigé) : les appuis d'avant ne disent plus rien.
    func reset() { recent.removeAll() }

    /// Les appuis récents étaient bien de cette main (lettres tapées sans corriger le côté) : on les apprend.
    func confirm(context: String, right: Bool) {
        guard !recent.isEmpty else { return }
        var s = stats[context] ?? Array(repeating: Array(repeating: Stat(), count: Self.bins), count: 2)
        let hand = right ? 1 : 0
        var k = kicks[context] ?? Array(repeating: Array(repeating: Array(repeating: Stat(), count: 3), count: Self.bins), count: 2)
        var z = sizes[context] ?? Array(repeating: Array(repeating: Stat(), count: Self.bins), count: 2)
        for r in recent {
            // Moyenne glissante : les nouveaux appuis comptent plus que les très anciens (au-delà de 200).
            s[hand][Self.bin(r.kx)].add(r.dx)
            if let kick = r.kick { for j in 0..<3 { k[hand][Self.bin(r.kx)][j].add(kick[j]) } }
            if r.r > 0 { z[hand][Self.bin(r.kx)].add(r.r) }
        }
        stats[context] = s
        kicks[context] = k
        sizes[context] = z
        recent.removeAll()
        save()
    }

    /// Assez appris des deux mains pour donner un avis.
    func ready(context: String) -> Bool {
        guard let s = stats[context] else { return false }
        // Étalonné dans l'app : une phrase par main suffit pour commencer.
        let need = seeded[context] != nil ? 12.0 : 25.0
        return s[0].map(\.n).reduce(0, +) >= need && s[1].map(\.n).reduce(0, +) >= need
    }

    /// La probabilité que les derniers appuis viennent de la main droite. nil : pas assez d'appuis récents,
    /// ou pas encore assez appris.
    func vote(context: String, now: TimeInterval) -> Double? {
        guard ready(context: context), let s = stats[context] else { return nil }
        let taps = recent.filter { now - $0.t < 25 }
        guard taps.count >= 6 else { return nil }
        var llr = 0.0
        var used = 0
        /// L'écart d'une mesure aux deux mains : positif si elle ressemble plus à la droite.
        func evidence(_ v: Double, _ L: Stat, _ R: Stat, floor: Double) -> Double? {
            guard L.n >= 4, R.n >= 4 else { return nil }
            let vr = (max(floor, L.m2 / L.n) + max(floor, R.m2 / R.n)) / 2
            // Une mesure qui ne sépare pas les deux mains (moyennes trop proches) ne compte presque pas.
            return max(-2, min(2, ((v - L.mean) * (v - L.mean) - (v - R.mean) * (v - R.mean)) / (2 * vr)))
        }
        let k = kicks[context]
        let z = sizes[context]
        for r in taps {
            let b = Self.bin(r.kx)
            guard let e = evidence(r.dx, s[0][b], s[1][b], floor: 0.004) else { continue }
            var tapLLR = e
            if let kick = r.kick, let k {
                for j in 0..<3 { if let e2 = evidence(kick[j], k[0][b][j], k[1][b][j], floor: 0.0004) { tapLLR += e2 * 0.5 } }
            }
            // La taille du toucher (iOS l'arrondit par paliers : plancher large).
            if r.r > 0, let z, let e3 = evidence(r.r, z[0][b], z[1][b], floor: 1.5) { tapLLR += e3 * 0.4 }
            llr += max(-3, min(3, tapLLR))
            used += 1
        }
        guard used >= 5 else { return nil }
        return 1 / (1 + exp(-llr * 0.6))
    }

    /// L'étalonnage fait dans l'app (« Apprends tes pouces ») : chaque appui = [zone, décalage, rayon, réaction x, y, z].
    /// Repris une fois par étalonnage ; un nouvel étalonnage remplace ce qui avait été appris pour cette situation.
    func importSeed(_ seed: [String: [String: [[Double]]]], stamps: [String: Double]) {
        var changed = false
        for (context, hands) in seed {
            let stamp = stamps[context] ?? 0
            guard stamp > (seeded[context] ?? 0) else { continue }
            stats[context] = nil; kicks[context] = nil; sizes[context] = nil
            var s = Array(repeating: Array(repeating: Stat(), count: Self.bins), count: 2)
            var k = Array(repeating: Array(repeating: Array(repeating: Stat(), count: 3), count: Self.bins), count: 2)
            var z = Array(repeating: Array(repeating: Stat(), count: Self.bins), count: 2)
            for (name, rows) in hands {
                let hand = name == "right" ? 1 : (name == "left" ? 0 : -1)
                guard hand >= 0 else { continue }
                for f in rows where f.count >= 3 && abs(f[1]) < 0.9 {
                    let b = Self.bin(f[0])
                    s[hand][b].add(f[1])
                    if f[2] > 0 { z[hand][b].add(f[2]) }
                    if f.count >= 6 { for j in 0..<3 { k[hand][b][j].add(f[3 + j]) } }
                }
            }
            stats[context] = s; kicks[context] = k; sizes[context] = z
            seeded[context] = stamp
            changed = true
        }
        if changed { save() }
    }

    func forget(context: String) {
        stats[context] = nil
        kicks[context] = nil
        sizes[context] = nil
        recent.removeAll()
        save()
    }
}
