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
    /// Les derniers appuis (zone du clavier 0…1, décalage par rapport au centre de la touche, en largeurs de touche,
    /// et la réaction du téléphone quand elle est connue).
    private struct Tap { var kx: Double; var dx: Double; var t: TimeInterval; var kick: [Double]? }
    private var recent: [Tap] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([String: [[Stat]]].self, from: d) {
            stats = s
        }
        if let d = UserDefaults.standard.data(forKey: key + ".kick"), let s = try? JSONDecoder().decode([String: [[[Stat]]]].self, from: d) {
            kicks = s
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(d, forKey: key) }
        if let d = try? JSONEncoder().encode(kicks) { UserDefaults.standard.set(d, forKey: key + ".kick") }
    }

    private static func bin(_ kx: Double) -> Int { max(0, min(bins - 1, Int(kx * Double(bins)))) }

    /// Un appui sur une lettre.
    func tap(kx: Double, dx: Double, time: TimeInterval) {
        guard abs(dx) < 0.9 else { return }
        recent.append(Tap(kx: kx, dx: dx, t: time, kick: nil))
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
        for r in recent {
            // Moyenne glissante : les nouveaux appuis comptent plus que les très anciens (au-delà de 200).
            s[hand][Self.bin(r.kx)].add(r.dx)
            if let kick = r.kick { for j in 0..<3 { k[hand][Self.bin(r.kx)][j].add(kick[j]) } }
        }
        stats[context] = s
        kicks[context] = k
        recent.removeAll()
        save()
    }

    /// Assez appris des deux mains pour donner un avis.
    func ready(context: String) -> Bool {
        guard let s = stats[context] else { return false }
        return s[0].map(\.n).reduce(0, +) >= 25 && s[1].map(\.n).reduce(0, +) >= 25
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
        for r in taps {
            let b = Self.bin(r.kx)
            guard let e = evidence(r.dx, s[0][b], s[1][b], floor: 0.004) else { continue }
            var tapLLR = e
            if let kick = r.kick, let k {
                for j in 0..<3 { if let e2 = evidence(kick[j], k[0][b][j], k[1][b][j], floor: 0.0004) { tapLLR += e2 * 0.5 } }
            }
            llr += max(-3, min(3, tapLLR))
            used += 1
        }
        guard used >= 5 else { return nil }
        return 1 / (1 + exp(-llr * 0.6))
    }

    func forget(context: String) {
        stats[context] = nil
        kicks[context] = nil
        recent.removeAll()
        save()
    }
}
