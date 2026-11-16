import Foundation

/// Où tu tapes vraiment sur chaque touche. Chaque mot gardé tel quel (sans correction) apprend au clavier l'endroit
/// où ton pouce se pose par rapport au centre de la touche ; une fois assez d'appuis, les zones d'appui se décalent
/// vers là (un tiers de touche au plus). La barre d'espace a son propre réglage : touchée plus haut que son centre,
/// sa zone monte un peu.
///
/// Rien de ce que tu écris n'est gardé : pour chaque touche, seulement quelques positions d'appui tirées au hasard,
/// sans ordre (impossible de relire un mot), et des moyennes.
struct KBTapMap: Codable, Equatable {
    struct Offset: Codable, Equatable {
        var dx: Double = 0
        var dy: Double = 0
        var n = 0
    }

    /// Par touche (« a », « b »…, « » pour la barre d'espace) : jusqu'à `perKey` appuis, en fraction de la touche
    /// depuis son centre (x vers la droite, y vers le bas).
    var keys: [String: [[Float]]] = [:]
    /// Moyennes lissées : clavier d'un côté (une main), clavier entier ou coupé en deux (deux mains).
    var one = Offset()
    var two = Offset()
    var space = Offset()
    var total = 0

    static let perKey = 24
    static let minSamples = 30
    static let maxShift = 0.33

    mutating func add(key: String, dx: Double, dy: Double, twoHands: Bool) {
        // Un appui très loin du centre : sans doute pas cette touche-là.
        guard abs(dx) < 0.9, abs(dy) < 0.9 else { return }
        total += 1
        var list = keys[key] ?? []
        let s: [Float] = [Float(dx), Float(dy)]
        if list.count < Self.perKey { list.append(s) } else { list[Int.random(in: 0..<list.count)] = s }
        keys[key] = list
        if key == " " {
            Self.update(&space, dx, dy)
        } else if twoHands {
            Self.update(&two, dx, dy)
        } else {
            Self.update(&one, dx, dy)
        }
    }

    private static func update(_ o: inout Offset, _ dx: Double, _ dy: Double) {
        o.n += 1
        // Moyenne qui suit tes habitudes récentes (les 300 derniers appuis comptent le plus).
        let a = 1.0 / Double(min(o.n, 300))
        o.dx += (dx - o.dx) * a
        o.dy += (dy - o.dy) * a
    }

    /// Le décalage des zones d'appui (en fraction de touche), une fois assez d'appuis.
    func shift(twoHands: Bool) -> (dx: Double, dy: Double)? {
        let o = twoHands ? two : one
        guard o.n >= Self.minSamples else { return nil }
        return (max(-Self.maxShift, min(Self.maxShift, o.dx)), max(-Self.maxShift, min(Self.maxShift, o.dy)))
    }

    /// La barre d'espace touchée nettement plus haut que son centre : sa zone d'appui monte d'autant.
    var spaceRaise: Double {
        guard space.n >= 20, space.dy < -0.12 else { return 0 }
        return min(Self.maxShift, -space.dy)
    }
}
