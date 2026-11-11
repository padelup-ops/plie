import Foundation

/// Une prise en main constatée : comment le téléphone penchait, et de quel côté le clavier était voulu.
struct KBHabit: Codable {
    var roll: Double
    var incline: Double
    var right: Bool
    var weight: Double
    /// Au milieu, à deux mains (le clavier entier). Absent dans les anciens exemples.
    var two: Bool? = nil
    /// Quand l'exemple a été appris (les récents comptent plus). Absent dans les anciens exemples.
    var at: Double? = nil

    /// Le poids qui compte aujourd'hui : il diminue de moitié en deux semaines.
    var current: Double {
        guard let at else { return weight }
        let days = (Date().timeIntervalSince1970 - at) / 86_400
        return weight * pow(0.5, max(0, days) / 14)
    }

    var label: Int { two == true ? 2 : (right ? 1 : 0) }
}

/// Les habitudes : le clavier retient, au fil de l'usage, comment le téléphone penche quand on le veut à droite
/// ou à gauche (au lit, debout, dans le métro…). Deux sources :
/// - une correction à la main (toucher la place libre, flèche ⇆) : exemple fort, qui efface les exemples
///   voisins qui disaient le contraire ;
/// - plusieurs lettres tapées sans rien corriger : exemple léger, le côté était le bon.
/// La décision est un vote des exemples les plus proches de la posture du moment. Une posture jamais vue
/// (loin de tous les exemples) ne déplace pas le clavier : dans le doute, il reste où il est.
final class KBHabits {
    static let shared = KBHabits()
    private let key = "foldboard.habits.v1"
    private var data: [String: [KBHabit]] = [:]
    private var signatures: [String: String] = [:]
    /// Tout ce que le clavier a appris depuis le début, par situation (ne baisse jamais : c'est ce qu'on montre).
    private(set) var total: [String: Int] = [:]
    private static let cap = 90

    private struct Stored: Codable {
        var data: [String: [KBHabit]]
        var signatures: [String: String]
        var total: [String: Int]?
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            data = s.data
            signatures = s.signatures
            total = s.total ?? s.data.mapValues(\.count)
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(Stored(data: data, signatures: signatures, total: total)) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    /// Le réglage des mains a été refait (ou effacé) pour cette situation : on repart de ses mesures.
    func sync(context: String, signature: String) {
        guard signatures[context] != signature else { return }
        signatures[context] = signature
        data[context] = []
        save()
    }

    func count(context: String) -> Int { data[context]?.count ?? 0 }

    private static func distance(_ r1: Double, _ i1: Double, _ r2: Double, _ i2: Double) -> Double {
        let dr = kbWrap(r1 - r2), di = (i1 - i2) * 0.3
        return (dr * dr + di * di).squareRoot()
    }

    func add(context: String, roll: Double, incline: Double, right: Bool, two: Bool = false, weight: Double, correction: Bool) {
        var a = data[context] ?? []
        let h = KBHabit(roll: roll, incline: incline, right: right, weight: weight, two: two ? true : nil,
                        at: Date().timeIntervalSince1970)
        if correction {
            // Les exemples tout proches qui disaient autre chose perdent du poids, sans disparaître : si on tient
            // le Duo pareil des deux mains, les deux restent, et c'est la position du pouce qui départage.
            for i in a.indices where a[i].label != h.label && Self.distance(a[i].roll, a[i].incline, roll, incline) < 6 {
                a[i].weight *= 0.5
            }
            a.removeAll { $0.weight < 0.3 }
        }
        a.append(h)
        if a.count > Self.cap {
            // On oublie d'abord les plus vieux exemples légers.
            if let i = a.firstIndex(where: { $0.weight <= 1 }) { a.remove(at: i) } else { a.removeFirst() }
        }
        data[context] = a
        total[context, default: 0] += 1
        save()
        var l = KBVault.loadLearn()
        l.total = total
        KBVault.save(l)
    }

    /// Tout ce qui a été appris, toutes situations confondues.
    var learnedTotal: Int { total.values.reduce(0, +) }

    /// Assez d'exemples des deux côtés pour décider (les mesures du réglage comptent comme des exemples forts).
    func ready(context: String, seeds: [KBHabit]) -> Bool {
        let all = seeds + (data[context] ?? [])
        let r = all.filter { $0.label == 1 }.map(\.current).reduce(0, +)
        let l = all.filter { $0.label == 0 }.map(\.current).reduce(0, +)
        return r >= 3 && l >= 3
    }

    /// La probabilité que ce soit la main droite, pour cette posture. `nil` : posture inconnue (loin de tout
    /// ce qu'on a vu), on ne décide pas.
    func vote(context: String, roll: Double, incline: Double, seeds: [KBHabit]) -> (right: Double, two: Double)? {
        let all = seeds + (data[context] ?? [])
        guard !all.isEmpty else { return nil }
        let ranked = all.map { ($0, Self.distance($0.roll, $0.incline, roll, incline)) }.sorted { $0.1 < $1.1 }
        guard let nearest = ranked.first, nearest.1 < 28 else { return nil }
        var r = 0.0, l = 0.0, t = 0.0
        for (h, d) in ranked.prefix(9) {
            let s = h.current / (1 + (d / 4) * (d / 4))
            switch h.label { case 2: t += s; case 1: r += s; default: l += s }
        }
        guard r + l + t > 0 else { return nil }
        // « right » : parmi les votes pour un côté ; « two » : la part du milieu.
        return (r + l > 0 ? r / (r + l) : 0.5, t / (r + l + t))
    }
}
