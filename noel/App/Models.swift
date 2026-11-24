// Models.swift — Allô Père Noël
//
// Ce que le parent prépare (prénoms, âge, qualités, anecdote, cadeau), les scénarios, le compte à rebours.
// Tout reste sur l'iPhone (UserDefaults) : aucun compte, aucun serveur.

import Foundation
import SwiftUI

enum Quality: String, CaseIterable, Codable, Identifiable {
    case kind, curious, brave, funny, sporty, dreamer, creative, caring, adventurous
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .kind: return "Kind"
        case .curious: return "Curious"
        case .brave: return "Brave"
        case .funny: return "Funny"
        case .sporty: return "Sporty"
        case .dreamer: return "Dreamer"
        case .creative: return "Creative"
        case .caring: return "Caring"
        case .adventurous: return "Adventurous"
        }
    }

    var symbol: String {
        switch self {
        case .kind: return "heart.fill"
        case .curious: return "magnifyingglass"
        case .brave: return "shield.fill"
        case .funny: return "face.smiling.inverse"
        case .sporty: return "figure.run"
        case .dreamer: return "moon.stars.fill"
        case .creative: return "paintpalette.fill"
        case .caring: return "hands.and.sparkles.fill"
        case .adventurous: return "map.fill"
        }
    }
}

struct ChildProfile: Codable, Equatable {
    var names: [String] = [""]
    var age: Int = 6
    var qualities: [Quality] = []
    var anecdote = ""
    var gift = ""

    var cleanNames: [String] { names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    var isPlural: Bool { cleanNames.count > 1 }
    var isReady: Bool { !cleanNames.isEmpty }

    private static let key = "allonoel.profile"
    static func load() -> ChildProfile {
        if let demo = ShotMode.demoProfile { return demo }
        guard let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode(ChildProfile.self, from: d) else { return ChildProfile() }
        return p
    }
    static func forget() { UserDefaults.standard.removeObject(forKey: key) }
    func save() {
        guard ShotMode.route == nil, let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(d, forKey: Self.key)
    }
}

enum Scenario: String, CaseIterable, Identifiable {
    case magic, secret, congrats, funny, eve
    var id: String { rawValue }
    var isFree: Bool { self == .magic }

    var title: LocalizedStringKey {
        switch self {
        case .magic: return "The magic call"
        case .secret: return "Santa's secret"
        case .congrats: return "Santa is proud of you"
        case .funny: return "Silly Santa"
        case .eve: return "The Christmas Eve call"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .magic: return "Santa wants to wish you a wonderful Christmas."
        case .secret: return "Santa has something special to tell you."
        case .congrats: return "He heard about all your efforts this year."
        case .funny: return "Santa had a little mishap at the workshop."
        case .eve: return "Santa is getting ready for his big night, with a very important message."
        }
    }

    var symbol: String {
        switch self {
        case .magic: return "phone.and.waveform.fill"
        case .secret: return "envelope.fill"
        case .congrats: return "medal.fill"
        case .funny: return "gift.fill"
        case .eve: return "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .magic: return Noel.red
        case .secret: return Noel.forest
        case .congrats: return Noel.gold
        case .funny: return Color(red: 0.86, green: 0.36, blue: 0.22)
        case .eve: return Color(red: 0.20, green: 0.27, blue: 0.52)
        }
    }

    /// Durée annoncée au parent.
    var minutes: LocalizedStringKey { self == .eve || self == .magic ? "About 1½ min" : "About 1 min" }
}

/// Quand le téléphone doit sonner : tout de suite, ou après un petit délai pour le donner à l'enfant.
enum RingDelay: Int, CaseIterable, Identifiable {
    case now = 0, ten = 10, thirty = 30, minute = 60
    var id: Int { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .now: return "Now"
        case .ten: return "In 10 s"
        case .thirty: return "In 30 s"
        case .minute: return "In 1 min"
        }
    }
}

/// Le compte à rebours jusqu'au 25 décembre (le suivant, s'il est passé).
enum Countdown {
    static func daysUntilChristmas(from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let y = cal.component(.year, from: today)
        var xmas = cal.date(from: DateComponents(year: y, month: 12, day: 25))!
        if xmas < today { xmas = cal.date(from: DateComponents(year: y + 1, month: 12, day: 25))! }
        return cal.dateComponents([.day], from: today, to: xmas).day ?? 0
    }

    static var text: LocalizedStringKey {
        let d = daysUntilChristmas()
        if d == 0 { return "It's Christmas! 🎄" }
        if d == 1 { return "Christmas is tomorrow! 🎄" }
        if d > 330 { return "Happy holidays! 🎄" }
        return "Only \(d) days until Christmas 🎄"
    }
}

/// Captures pour l'App Store : l'app est lancée avec « -shot nom » et ouvre l'écran voulu, avec un exemple.
enum ShotMode {
    static let route: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()

    static var demoProfile: ChildProfile? {
        guard route != nil else { return nil }
        let lang = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        let name: String
        switch lang {
        case "fr": name = "Léa"
        case "es": name = "Lucía"
        case "de": name = "Emma"
        case "it": name = "Giulia"
        case "pt": name = "Alice"
        default: name = "Emma"
        }
        return ChildProfile(names: [name], age: 6, qualities: [.kind, .funny], anecdote: "", gift: "")
    }
}
