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

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        chapter = try c.decode(Int.self, forKey: .chapter)
        title = try c.decode(String.self, forKey: .title)
        giver = try c.decodeIfPresent(String.self, forKey: .giver)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        objectives = try c.decodeIfPresent([String].self, forKey: .objectives) ?? []
        walkthrough = try c.decodeIfPresent(String.self, forKey: .walkthrough)
        tips = try c.decodeIfPresent([String].self, forKey: .tips)
        unlocks = try c.decodeIfPresent(String.self, forKey: .unlocks)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional)
        place = try c.decodeIfPresent(String.self, forKey: .place)
    }
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
    case region, landmark, shop, property, activity, collectible, event, mission, service, vehicle
    case hotel, food, gas, transport, nature, civic = "public", other
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
        case .vehicle: return String(localized: "Rare vehicles")
        case .hotel: return String(localized: "Hotels")
        case .food: return String(localized: "Food & drink")
        case .gas: return String(localized: "Gas stations")
        case .transport: return String(localized: "Transport")
        case .nature: return String(localized: "Nature")
        case .civic: return String(localized: "Public buildings")
        case .other: return String(localized: "Other places")
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
        case .vehicle: return "car.fill"
        case .hotel: return "bed.double.fill"
        case .food: return "fork.knife"
        case .gas: return "fuelpump.fill"
        case .transport: return "tram.fill"
        case .nature: return "leaf.fill"
        case .civic: return "building.2.fill"
        case .other: return "mappin"
        }
    }
    /// L'ordre d'importance sur la carte (quand les repères se gênent, le plus important reste).
    var rank: Int {
        switch self {
        case .mission: return 0
        case .landmark, .property: return 1
        case .collectible, .event, .activity: return 2
        // Les véhicules rares après les monuments : ils ne couvrent pas la carte tant qu'on ne les filtre pas.
        case .hotel, .nature, .vehicle: return 3
        case .shop, .food, .gas: return 4
        case .service, .transport: return 5
        case .civic: return 6
        case .region, .other: return 7
        }
    }
    /// Couches affichées au départ (les « autres lieux », très nombreux, attendent qu'on les demande).
    static var defaultLayers: Set<VFPlaceKind> { Set(allCases).subtracting([.other]) }
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
    /// Le lieu réel qui l'a inspiré (Floride), d'après GTADB.
    var real: String?
    var enterable: Bool?
    var uncertain: Bool?
    var closed: Bool?

    /// Un lieu repris d'une base communautaire (pas un des nôtres) : GTADB, Open GTA 6 Map pour les véhicules rares, ou
    /// un véhicule ajouté par un joueur (Cars.swift).
    var community: Bool { gtadb || openMap || playerSpot }
    /// Un lieu de GTADB.org (il a une page de photos là-bas).
    var gtadb: Bool { id.hasPrefix("g-") }
    /// Un véhicule rare relevé par Open GTA 6 Map (CC BY 4.0).
    var openMap: Bool { id.hasPrefix("o-") }
    /// L'ordre sur la carte : nos lieux d'abord, puis par catégorie, ceux où l'on peut entrer en premier.
    var rank: Int { (community ? 100 : 0) + kind.rank * 10 + (enterable == true ? 0 : 1) }
}

struct VFCollectibleSet: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var count: Int
    /// Combien il en faut pour le 100 % (s'il ne faut pas tout).
    var needed: Int?
    var group: String?
    var reward: String?
    var summary: String?
    var target: Int { needed ?? count }
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

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        genre = try c.decodeIfPresent(String.self, forKey: .genre) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        songs = try c.decodeIfPresent([VFSong].self, forKey: .songs) ?? []
    }
}

struct VFCheat: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var effect: String
    var playstation: String?
    var xbox: String?
    var phone: String?
    var note: String?
    var group: String?
}

/// Un easter egg : ce que c'est, où, et (si on le demande) comment le trouver. Rédigé par nous à partir de ce que
/// les joueurs et la presse ont rapporté ; « confirmed » quand plusieurs sources le décrivent.
struct VFEgg: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var how: String?
    var area: String
    /// Position approximative sur la carte (0 à 1), si on la connaît.
    var x: Double?
    var y: Double?
    var refs: [String]?
    var confirmed: Bool?
    var spoiler: Int?
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
    var eggs: [VFEgg] = []
    var news: [VFNews]?

    init(version: Int) { self.version = version }

    /// Tolérant : une partie absente ou une entrée mal formée ne fait pas perdre tout le reste du guide.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        updated = try? c.decodeIfPresent(String.self, forKey: .updated)
        sources = try? c.decodeIfPresent([String].self, forKey: .sources)
        func list<T: Decodable>(_ k: CodingKeys) -> [T] {
            (try? c.decodeIfPresent([Lossy<T>].self, forKey: k))?.compactMap(\.value) ?? []
        }
        chapters = list(.chapters); missions = list(.missions); guides = list(.guides); places = list(.places)
        collectibles = list(.collectibles); challenges = list(.challenges); characters = list(.characters)
        stations = list(.stations); cheats = list(.cheats); eggs = list(.eggs)
        news = list(.news)
    }

    static let empty = VFContent(version: 0)
}

/// Une entrée qu'on garde si elle se lit, qu'on saute sinon.
struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
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
        // la langue de l'interface choisie par iOS, pour que le contenu suive toujours les menus
        let l = String((Bundle.main.preferredLocalizations.first ?? "en").prefix(2))
        return ["fr", "es", "de", "it", "pt"].contains(l) ? l : "en"
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
    var totalCollectibles: Int { content.collectibles.reduce(0) { $0 + $1.target } }
    /// Les missions de l'histoire (celles qui comptent pour le 100 %).
    var storyMissions: [VFMission] { content.missions.filter { $0.optional != true } }
    /// Les lieux qui comptent pour le 100 % (pas les régions ni les lieux de la communauté).
    var countedPlaces: [VFPlace] { content.places.filter { $0.kind != .region && !$0.community } }
    /// Le nombre de lieux de la carte, sans les véhicules rares (comptés à part).
    var mapPlaceCount: Int { content.places.filter { $0.kind != .vehicle }.count }
}
