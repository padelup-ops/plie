import Foundation

/// Ton bilan de frappe : compté sur le téléphone seulement (jamais envoyé), jour par jour.
/// Le clavier compte en mémoire et enregistre quand il se ferme ; l'app lit pour la carte « Ton bilan ».
struct KBStats: Codable, Equatable {
    struct Day: Codable, Equatable {
        var words = 0
        var letters = 0
        var corrections = 0
        var glides = 0
        /// Secondes de frappe active (les pauses de plus de 6 s ne comptent pas).
        var seconds = 0.0
        /// Lettres tapées à une main droite, gauche, ou à deux mains.
        var right = 0
        var left = 0
        var two = 0
    }
    var days: [String: Day] = [:]
    var stamp: Date = .distantPast

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Les `n` derniers jours additionnés (aujourd'hui compris).
    func total(lastDays n: Int, now: Date = Date()) -> Day {
        var t = Day()
        for i in 0..<n {
            guard let d = Calendar.current.date(byAdding: .day, value: -i, to: now), let x = days[Self.key(d)] else { continue }
            t.words += x.words; t.letters += x.letters; t.corrections += x.corrections; t.glides += x.glides
            t.seconds += x.seconds; t.right += x.right; t.left += x.left; t.two += x.two
        }
        return t
    }

    /// Ajoute ce qui a été compté dans le clavier depuis le dernier enregistrement.
    mutating func merge(_ add: [String: Day]) {
        for (k, x) in add {
            var t = days[k] ?? Day()
            t.words += x.words; t.letters += x.letters; t.corrections += x.corrections; t.glides += x.glides
            t.seconds += x.seconds; t.right += x.right; t.left += x.left; t.two += x.two
            days[k] = t
        }
        // On garde 60 jours.
        if days.count > 60 { for k in days.keys.sorted().dropLast(60) { days[k] = nil } }
    }
}

extension KBStats.Day {
    /// Mots par minute de frappe active (nil si trop peu de données).
    var wpm: Int? { seconds >= 60 && words >= 20 ? Int((Double(words) / (seconds / 60)).rounded()) : nil }
    /// La main la plus utilisée : 1 droite, 0 gauche, 2 deux mains (nil si trop peu de lettres).
    var favoriteHand: Int? {
        guard right + left + two >= 50 else { return nil }
        if two >= right && two >= left { return 2 }
        return right >= left ? 1 : 0
    }
}

/// Le compteur du clavier : très léger (quelques additions par lettre), enregistré à la fermeture du clavier.
final class KBStatsRecorder {
    static let shared = KBStatsRecorder()
    private var pending: [String: KBStats.Day] = [:]
    private var lastLetter: Date?

    private func update(_ f: (inout KBStats.Day) -> Void) {
        let k = KBStats.key(Date())
        var d = pending[k] ?? KBStats.Day()
        f(&d)
        pending[k] = d
    }

    /// `hand` : 1 droite, 0 gauche, 2 deux mains.
    func letter(hand: Int) {
        let now = Date()
        let gap = lastLetter.map { now.timeIntervalSince($0) } ?? 99
        lastLetter = now
        update { d in
            d.letters += 1
            if gap < 6 { d.seconds += gap }
            switch hand { case 1: d.right += 1; case 0: d.left += 1; default: d.two += 1 }
        }
    }
    func word() { update { $0.words += 1 } }
    /// Un mot écrit en glissant (compté comme mot ici : l'espace qui suit ne le recompte pas).
    func glide() { update { d in d.glides += 1; d.words += 1 } }
    func correction() { update { $0.corrections += 1 } }

    /// À la fermeture du clavier : ajouté au bilan enregistré.
    func flush() {
        guard !pending.isEmpty else { return }
        let add = pending
        pending = [:]
        lastLetter = nil
        var s = KBVault.loadStats()
        s.merge(add)
        KBVault.save(s)
    }
}
