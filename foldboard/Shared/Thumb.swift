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

    /// Moyenne et dispersion du décalage, par main (0 gauche, 1 droite) et par zone du clavier (5 tranches).
    private struct Stat: Codable { var n = 0.0; var mean = 0.0; var m2 = 0.0 }
    private var stats: [String: [[Stat]]] = [:]
    /// Les derniers appuis (zone du clavier 0…1, décalage par rapport au centre de la touche, en largeurs de touche).
    private var recent: [(kx: Double, dx: Double, t: TimeInterval)] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([String: [[Stat]]].self, from: d) {
            stats = s
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(stats) { UserDefaults.standard.set(d, forKey: key) }
    }

    private static func bin(_ kx: Double) -> Int { max(0, min(bins - 1, Int(kx * Double(bins)))) }

    /// Un appui sur une lettre.
    func tap(kx: Double, dx: Double, time: TimeInterval) {
        guard abs(dx) < 0.9 else { return }
        recent.append((kx, dx, time))
        if recent.count > 24 { recent.removeFirst(recent.count - 24) }
    }

    /// Le clavier vient de changer de côté (ou d'être corrigé) : les appuis d'avant ne disent plus rien.
    func reset() { recent.removeAll() }

    /// Les appuis récents étaient bien de cette main (lettres tapées sans corriger le côté) : on les apprend.
    func confirm(context: String, right: Bool) {
        guard !recent.isEmpty else { return }
        var s = stats[context] ?? Array(repeating: Array(repeating: Stat(), count: Self.bins), count: 2)
        let hand = right ? 1 : 0
        for r in recent {
            var st = s[hand][Self.bin(r.kx)]
            // Moyenne glissante : les nouveaux appuis comptent plus que les très anciens (au-delà de 200).
            st.n = min(st.n + 1, 200)
            let d = r.dx - st.mean
            st.mean += d / st.n
            st.m2 = st.m2 * (1 - 1 / st.n) + d * (r.dx - st.mean)
            s[hand][Self.bin(r.kx)] = st
        }
        stats[context] = s
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
        for r in taps {
            let b = Self.bin(r.kx)
            let L = s[0][b], R = s[1][b]
            guard L.n >= 4, R.n >= 4 else { continue }
            let varL = max(0.004, L.m2 / L.n), varR = max(0.004, R.m2 / R.n)
            let v = (varL + varR) / 2
            let e = ((r.dx - L.mean) * (r.dx - L.mean) - (r.dx - R.mean) * (r.dx - R.mean)) / (2 * v)
            llr += max(-2, min(2, e))
            used += 1
        }
        guard used >= 5 else { return nil }
        return 1 / (1 + exp(-llr * 0.6))
    }

    func forget(context: String) {
        stats[context] = nil
        recent.removeAll()
        save()
    }
}
