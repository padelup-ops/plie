// Snapshot.swift — Vicefold
//
// Ce que l'app partage avec ses widgets (écran d'accueil et écran verrouillé) : la progression, la prochaine mission
// et le temps de jeu. Écrit par l'app dans le groupe d'apps, lu par le widget.

import Foundation
import SwiftUI

struct VFSnapshot: Codable, Equatable {
    var percent: Double = 0
    var missions: Double = 0
    var places: Double = 0
    var collectibles: Double = 0
    var challenges: Double = 0
    var nextMission: String?
    var nextChapter: String?
    var hours: Double = 0
    var pro = false
    var updated = Date()

    static let group = "group.com.padelup.vicefold"
    private static let key = "vicefold.snapshot"

    static func load() -> VFSnapshot {
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key),
              let s = try? JSONDecoder().decode(VFSnapshot.self, from: d) else { return VFSnapshot() }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(d, forKey: Self.key)
    }
}

/// Les couleurs de Vicefold : des cartes postales de Leonida — l'eau du golfe la nuit, le flamant, le coucher de
/// soleil, les palmiers, l'eau des piscines. Pas celles du jeu.
enum VF {
    /// Le bleu nuit du golfe : le texte en clair, le fond en sombre.
    static let ink = Color(red: 14 / 255, green: 27 / 255, blue: 43 / 255)
    /// L'eau de piscine : le fond en clair.
    static let pool = Color(red: 234 / 255, green: 246 / 255, blue: 245 / 255)
    static let flamingo = Color(red: 1.0, green: 79 / 255, blue: 139 / 255)
    static let sunset = Color(red: 1.0, green: 138 / 255, blue: 61 / 255)
    static let palm = Color(red: 20 / 255, green: 176 / 255, blue: 138 / 255)
    static let sun = Color(red: 1.0, green: 201 / 255, blue: 74 / 255)
    static let sky = Color(red: 75 / 255, green: 163 / 255, blue: 1.0)

    // Les anciens noms, pour les écrans qui les utilisent encore.
    static let coral = sunset
    static let magenta = flamingo
    static let teal = palm
    static let night = ink

    static let gradient = LinearGradient(colors: [sun, sunset, flamingo], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Le ciel du soir, de haut en bas (affiches, cartes postales).
    static let dusk = LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.86), flamingo, sunset], startPoint: .top, endPoint: .bottom)

    /// Les quatre parts du 100 % : missions, lieux, objets, défis.
    static let ringColors: [Color] = [flamingo, palm, sun, sky]

    /// Le fond des écrans : l'eau de piscine le jour, le golfe la nuit.
    static func backdrop(_ dark: Bool) -> Color { dark ? Color(red: 9 / 255, green: 20 / 255, blue: 34 / 255) : pool }
    /// Le fond des cartes posées dessus.
    static func card(_ dark: Bool) -> Color { dark ? Color(red: 17 / 255, green: 36 / 255, blue: 58 / 255) : .white }

    /// Les titres d'affiche (Anton, licence SIL Open Font).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Anton-Regular", size: size, relativeTo: style)
    }

    /// La sortie du jeu (PS5 et Xbox Series), annoncée par l'éditeur.
    static let release: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 19; c.hour = 0
        c.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()
}

/// L'anneau de progression : une part par catégorie, comme un anneau d'activité.
struct VFRing: View {
    var parts: [Double]          // 0…1 pour chaque catégorie
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                let inset = CGFloat(i) * (lineWidth + 3)
                Circle()
                    .stroke(VF.ringColors[i % 4].opacity(0.18), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, p)))
                    .stroke(VF.ringColors[i % 4], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .padding(lineWidth / 2)
    }
}
