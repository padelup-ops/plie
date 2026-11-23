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

/// Les couleurs de Vicefold : un coucher de soleil sur la côte (corail, magenta, turquoise), pas celles du jeu.
enum VF {
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.36)
    static let magenta = Color(red: 0.93, green: 0.23, blue: 0.56)
    static let teal = Color(red: 0.11, green: 0.74, blue: 0.72)
    static let sun = Color(red: 1.0, green: 0.74, blue: 0.27)
    static let night = Color(red: 0.07, green: 0.08, blue: 0.16)
    static let gradient = LinearGradient(colors: [sun, coral, magenta], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Les quatre parts de l'anneau 100 %.
    static let ringColors: [Color] = [coral, teal, sun, magenta]

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
