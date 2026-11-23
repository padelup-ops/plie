// Models.swift — Vicefold
//
// Le contenu du guide : chapitres, missions, guides, lieux, objets à collectionner, défis, personnages, radios, codes.
// Tout est dans un fichier JSON par langue, livré avec l'app (hors ligne) et mis à jour depuis notre serveur.

import Foundation
import Observation

struct VFChapter: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var summary: String?
}

struct VFMission: Codable, Identifiable, Hashable {
    var id: String
    var chapter: Int
    var title: String
    var giver: String?
    var location: String?
    var objectives: [String] = []
    var walkthrough: String?
    var tips: [String]?
    var unlocks: String?
    var optional: Bool?
    var place: String?
}

enum VFGuideCategory: String, Codable, CaseIterable, Identifiable {
    case start, collectibles, events, skills, properties, shops, hobbies, challenges, secrets, trophies, cheats, landmarks, money, vehicles, weapons
    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return String(localized: "Start here")
        case .collectibles: return String(localized: "Collectibles")
        case .events: return String(localized: "Random events")
        case .skills: return String(localized: "Skills")
        case .properties: return String(localized: "Properties")
        case .shops: return String(localized: "Shops")
        case .hobbies: return String(localized: "Hobbies")
        case .challenges: return String(localized: "Challenges")
        case .secrets: return String(localized: "Secrets")
        case .trophies: return String(localized: "Trophy roadmap")
        case .cheats: return String(localized: "Cheat codes")
        case .landmarks: return String(localized: "Landmarks")
        case .money: return String(localized: "Money")
        case .vehicles: return String(localized: "Vehicles")
        case .weapons: return String(localized: "Weapons")
        }
    }

    var icon: String {
        switch self {
        case .start: return "flag.checkered"
        case .collectibles: return "sparkles"
        case .events: return "exclamationmark.bubble"
        case .skills: return "figure.run"
        case .properties: return "house"
        case .shops: return "bag"
        case .hobbies: return "fish"
        case .challenges: return "stopwatch"
        case .secrets: return "eye"
        case .trophies: return "trophy"
        case .cheats: return "gamecontroller"
        case .landmarks: return "building.columns"
        case .money: return "dollarsign.circle"
        case .vehicles: return "car.side"
        case .weapons: return "scope"
        }
    }
}

struct VFGuide: Codable, Identifiable, Hashable {
    var id: String
    var category: VFGuideCategory
    var title: String
    var summary: String?
    var body: String
    /// Le chapitre à partir duquel ce guide ne dévoile plus rien (0 = sans spoiler).
    var spoiler: Int?
    var minutes: Int?
}

enum VFPlaceKind: String, Codable, CaseIterable, Identifiable {
    case region, landmark, shop, property, activity, collectible, event, mission, service
    var id: String { rawValue }
    var title: String {
        switch self {
        case .region: return String(localized: "Regions")
        case .landmark: return String(localized: "Landmarks")
        case .shop: return String(localized: "Shops")
        case .property: return String(localized: "Properties")
        case .activity: return String(localized: "Activities")
        case .collectible: return String(localized: "Collectibles")
        case .event: return String(localized: "Random events")
        case .mission: return String(localized: "Missions")
        case .service: return String(localized: "Services")
        }
    }
    var icon: String {
        switch self {
        case .region: return "map"
        case .landmark: return "building.columns.fill"
        case .shop: return "bag.fill"
        case .property: return "house.fill"
        case .activity: return "figure.surfing"
        case .collectible: return "sparkles"
        case .event: return "exclamationmark.bubble.fill"
        case .mission: return "flag.fill"
        case .service: return "wrench.and.screwdriver.fill"
        }
    }
    /// Couches réservées à Pro sur la carte (comme les objets à collectionner et les activités).
    var pro: Bool { self == .collectible || self == .activity || self == .event }
}

struct VFPlace: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: VFPlaceKind
    /// Position sur notre carte, de 0 à 1 (gauche → droite, haut → bas).
    var x: Double
    var y: Double
    var region: String?
    var note: String?
    var spoiler: Int?
}

struct VFCollectibleSet: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var count: Int
    var reward: String?
    var summary: String?
}

struct VFChallenge: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var group: String
    var detail: String?
}

struct VFCharacter: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var role: String
    var bio: String
    var spoiler: Int?
    var firstSeen: String?
    var tags: [String]?
}

struct VFSong: Codable, Hashable, Identifiable {
    var title: String
    var artist: String
    var id: String { artist + " — " + title }
}

struct VFStation: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var genre: String
    var host: String?
    var summary: String?
    var songs: [VFSong] = []
}

struct VFCheat: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var effect: String
    var playstation: String?
    var xbox: String?
    var phone: String?
    var note: String?
}

struct VFNews: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var title: String
    var body: String
}

struct VFContent: Codable {
    var version: Int
    var updated: String?
    var sources: [String]?
    var chapters: [VFChapter] = []
    var missions: [VFMission] = []
    var guides: [VFGuide] = []
    var places: [VFPlace] = []
    var collectibles: [VFCollectibleSet] = []
    var challenges: [VFChallenge] = []
    var characters: [VFCharacter] = []
    var stations: [VFStation] = []
    var cheats: [VFCheat] = []
    var news: [VFNews]?

    static let empty = VFContent(version: 0)
}

/// Le contenu en cours : celui livré avec l'app, ou une version plus récente téléchargée depuis notre serveur.
@MainActor @Observable
final class ContentStore {
    static let shared = ContentStore()

    private(set) var content: VFContent = .empty
    private(set) var lastCheck: Date?
    var updating = false

    /// Notre serveur de contenu : le dossier public du projet (pas celui d'une autre app).
    static let remoteBase = URL(string: "https://raw.githubusercontent.com/padelup-ops/plie/main/vicefold/Content/")!

    static var lang: String {
        let l = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        return l == "fr" ? "fr" : "en"
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("content-\(Self.lang).json")
    }

    init() {
        load()
    }

    func load() {
        let bundled = Bundle.main.url(forResource: "content-\(Self.lang)", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(VFContent.self, from: $0) }
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(VFContent.self, from: $0) }
        if let cached, cached.version >= (bundled?.version ?? 0) { content = cached } else if let bundled { content = bundled }
    }

    /// Nouveau contenu sur le serveur : on le garde pour la prochaine ouverture hors ligne.
    func refresh() async -> Bool {
        guard !updating else { return false }
        updating = true
        defer { updating = false; lastCheck = Date() }
        let url = Self.remoteBase.appendingPathComponent("content-\(Self.lang).json")
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let c = try? JSONDecoder().decode(VFContent.self, from: data),
              c.version > content.version else { return false }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
        content = c
        return true
    }

    // MARK: Raccourcis

    var chapters: [VFChapter] { content.chapters }
    var missions: [VFMission] { content.missions }
    func missions(in chapter: Int) -> [VFMission] { content.missions.filter { $0.chapter == chapter } }
    func chapter(_ id: Int) -> VFChapter? { content.chapters.first { $0.id == id } }
    func guides(_ c: VFGuideCategory) -> [VFGuide] { content.guides.filter { $0.category == c } }
    func place(_ id: String) -> VFPlace? { content.places.first { $0.id == id } }
    var totalCollectibles: Int { content.collectibles.reduce(0) { $0 + $1.count } }
}
