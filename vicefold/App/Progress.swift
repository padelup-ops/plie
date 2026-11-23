// Progress.swift — Vicefold
//
// Ta partie : missions faites, lieux visités, objets trouvés, défis, épingles, notes, où tu en es dans l'histoire.
// Tout reste sur l'iPhone (aucun compte), et passe d'un appareil à l'autre par iCloud avec Pro.

import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Une trouvaille à toi : un secret que tu as vu dans le jeu (avec une photo si tu veux).
struct VFMyEgg: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var note: String = ""
    var place: String = ""
    var photo: String?
    var date = Date()
}

struct VFPin: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var note: String = ""
    var icon: String = "mappin"
    var color: Int = 0
    var x: Double
    var y: Double
    var created = Date()

    static let icons = ["mappin", "star.fill", "flag.fill", "car.fill", "dollarsign", "cross.case.fill", "house.fill",
                        "bag.fill", "fish.fill", "camera.fill", "exclamationmark.triangle.fill", "heart.fill"]
    static let colors: [Color] = [VF.coral, VF.teal, VF.sun, VF.magenta, .blue, .green, .purple, .gray]
}

/// Le calage de ta propre carte (une capture de la carte du jeu) sur la nôtre.
struct VFMapFit: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var opacity: Double = 1
}

struct VFProgressData: Codable, Equatable {
    var missions: Set<String> = []
    var objectives: [String: [Int]] = [:]
    var visited: Set<String> = []
    var collected: [String: Int] = [:]
    var challenges: Set<String> = []
    var readGuides: Set<String> = []
    var pins: [VFPin] = []
    var favorites: Set<String> = []
    var notes: [String: String] = [:]
    /// Le chapitre où tu en es : au-delà, tout est masqué (sans spoiler par défaut).
    var chapter: Int = 1
    var spoilersShown = false
    var name: String = ""
    var manualHours: Double = 0
    var psnHours: Double?
    var psnUpdated: Date?
    var platform: String = "ps5"
    var customMap = false
    var mapFit = VFMapFit()
    /// Les easter eggs trouvés, et tes propres trouvailles.
    var eggs: Set<String> = []
    var myEggs: [VFMyEgg] = []
    /// Tes captures de chaque mission (noms de fichiers, sur cet appareil), pour t'en souvenir.
    var missionShots: [String: [String]] = [:]
    var updated = Date()

    init() {}

    /// Chaque champ est facultatif : une version plus ancienne (ou plus récente) de l'app ne fait jamais perdre la partie.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let z = VFProgressData()
        missions = (try? c.decodeIfPresent(Set<String>.self, forKey: .missions)) ?? z.missions
        objectives = (try? c.decodeIfPresent([String: [Int]].self, forKey: .objectives)) ?? z.objectives
        visited = (try? c.decodeIfPresent(Set<String>.self, forKey: .visited)) ?? z.visited
        collected = (try? c.decodeIfPresent([String: Int].self, forKey: .collected)) ?? z.collected
        challenges = (try? c.decodeIfPresent(Set<String>.self, forKey: .challenges)) ?? z.challenges
        readGuides = (try? c.decodeIfPresent(Set<String>.self, forKey: .readGuides)) ?? z.readGuides
        pins = (try? c.decodeIfPresent([VFPin].self, forKey: .pins)) ?? z.pins
        favorites = (try? c.decodeIfPresent(Set<String>.self, forKey: .favorites)) ?? z.favorites
        notes = (try? c.decodeIfPresent([String: String].self, forKey: .notes)) ?? z.notes
        chapter = (try? c.decodeIfPresent(Int.self, forKey: .chapter)) ?? z.chapter
        spoilersShown = (try? c.decodeIfPresent(Bool.self, forKey: .spoilersShown)) ?? z.spoilersShown
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? z.name
        manualHours = (try? c.decodeIfPresent(Double.self, forKey: .manualHours)) ?? z.manualHours
        psnHours = try? c.decodeIfPresent(Double.self, forKey: .psnHours)
        psnUpdated = try? c.decodeIfPresent(Date.self, forKey: .psnUpdated)
        platform = (try? c.decodeIfPresent(String.self, forKey: .platform)) ?? z.platform
        customMap = (try? c.decodeIfPresent(Bool.self, forKey: .customMap)) ?? z.customMap
        mapFit = (try? c.decodeIfPresent(VFMapFit.self, forKey: .mapFit)) ?? z.mapFit
        eggs = (try? c.decodeIfPresent(Set<String>.self, forKey: .eggs)) ?? z.eggs
        myEggs = (try? c.decodeIfPresent([VFMyEgg].self, forKey: .myEggs)) ?? z.myEggs
        missionShots = (try? c.decodeIfPresent([String: [String]].self, forKey: .missionShots)) ?? z.missionShots
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? z.updated
    }
}

@MainActor @Observable
final class Progress {
    static let shared = Progress()

    private(set) var data = VFProgressData()
    private let kvs = NSUbiquitousKeyValueStore.default
    private static let kvsKey = "vicefold.progress"

    /// Limites de la version gratuite (Pro : illimité).
    static let freePins = 10
    static let freeVisited = Int.max

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("progress.json")
    }

    var photoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile.jpg")
    }

    var mapURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("my-map.jpg")
    }

    init() {
        if let d = try? Data(contentsOf: fileURL), let p = try? JSONDecoder().decode(VFProgressData.self, from: d) { data = p }
        if ShotMode.route != nil { data = Self.demo() }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: kvs, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullCloud() }
        }
        kvs.synchronize()
        lastCloudSync = UserDefaults.standard.object(forKey: Self.syncKey) as? Date
    }

    func edit(_ change: (inout VFProgressData) -> Void) {
        change(&data)
        data.updated = Date()
        save()
    }

    private func save() {
        if ShotMode.route != nil { writeSnapshot(); return }
        if let d = try? JSONEncoder().encode(data) {
            try? d.write(to: fileURL, options: .atomic)
            if Store.shared.isPro { kvs.set(d, forKey: Self.kvsKey); markSynced() }
        }
        writeSnapshot()
    }

    /// Une partie en cours, pour les captures d'écran (simulateur seulement).
    static func demo() -> VFProgressData {
        let c = ContentStore.shared.content
        var d = VFProgressData()
        d.name = "Alex"
        d.chapter = 3
        d.manualHours = 38
        d.missions = Set(c.missions.prefix(44).map(\.id))
        if let m = c.missions.dropFirst(44).first { d.objectives[m.id] = [0] }
        d.visited = Set(c.places.filter { $0.kind != .region && !$0.community }.prefix(5).map(\.id))
        for (i, s) in c.collectibles.enumerated() { d.collected[s.id] = Int(Double(s.target) * [0.62, 0.35, 0.8, 0.5, 0.2, 0.9][i % 6]) }
        d.challenges = ["f-narco", "f-cars"]
        d.favorites = ["lucia", "jason"]
        d.readGuides = ["start-how"]
        d.pins = [VFPin(name: "Stash", note: "Behind the bait shop", icon: "dollarsign", color: 2, x: 0.735, y: 0.535),
                  VFPin(name: "Car to scan", icon: "car.fill", color: 1, x: 0.79, y: 0.455),
                  VFPin(name: "Sunset spot", icon: "camera.fill", color: 3, x: 0.86, y: 0.51)]
        return d
    }

    // MARK: iCloud (Pro)

    /// La dernière fois que cet appareil et iCloud avaient la même partie.
    private(set) var lastCloudSync: Date?
    private static let syncKey = "vicefold.lastCloudSync"

    private func markSynced() {
        lastCloudSync = Date()
        UserDefaults.standard.set(data.updated, forKey: Self.syncKey + ".updated")
        UserDefaults.standard.set(lastCloudSync, forKey: Self.syncKey)
    }

    /// Rien n'a changé ici depuis la dernière synchro : l'autre appareil a le dernier mot (même pour ce qu'on a décoché).
    private var untouchedSinceSync: Bool {
        guard let u = UserDefaults.standard.object(forKey: Self.syncKey + ".updated") as? Date else { return false }
        return data.updated <= u
    }

    func pushCloud() {
        guard Store.shared.isPro, let d = try? JSONEncoder().encode(data) else { return }
        kvs.set(d, forKey: Self.kvsKey)
        kvs.synchronize()
        markSynced()
    }

    func pullCloud() {
        guard Store.shared.isPro, ShotMode.route == nil else { return }
        kvs.synchronize()
        guard let d = kvs.data(forKey: Self.kvsKey),
              let other = try? JSONDecoder().decode(VFProgressData.self, from: d) else { pushCloud(); return }
        if other == data { markSynced(); return }
        if untouchedSinceSync && other.updated >= data.updated {
            data = other
        } else {
            data = Self.merge(data, other)
        }
        if let d = try? JSONEncoder().encode(data) {
            try? d.write(to: fileURL, options: .atomic)
            // la partie fusionnée repart vers les autres appareils
            if data != other { kvs.set(d, forKey: Self.kvsKey) }
        }
        markSynced()
        writeSnapshot()
    }

    /// Deux appareils : on garde tout ce qui a été coché des deux côtés, et le reste du plus récent.
    static func merge(_ a: VFProgressData, _ b: VFProgressData) -> VFProgressData {
        var m = a.updated >= b.updated ? a : b
        m.missions = a.missions.union(b.missions)
        m.visited = a.visited.union(b.visited)
        m.challenges = a.challenges.union(b.challenges)
        m.readGuides = a.readGuides.union(b.readGuides)
        m.favorites = a.favorites.union(b.favorites)
        m.collected = a.collected.merging(b.collected) { max($0, $1) }
        m.objectives = a.objectives.merging(b.objectives) { Array(Set($0).union($1)).sorted() }
        var pins = Dictionary(uniqueKeysWithValues: a.pins.map { ($0.id, $0) })
        for p in b.pins where pins[p.id] == nil { pins[p.id] = p }
        m.pins = pins.values.sorted { $0.created < $1.created }
        m.chapter = max(a.chapter, b.chapter)
        m.eggs = a.eggs.union(b.eggs)
        m.missionShots = a.missionShots.merging(b.missionShots) { x, y in x + y.filter { !x.contains($0) } }
        var mine = Dictionary(uniqueKeysWithValues: a.myEggs.map { ($0.id, $0) })
        for e in b.myEggs where mine[e.id] == nil { mine[e.id] = e }
        m.myEggs = mine.values.sorted { $0.date > $1.date }
        return m
    }

    // MARK: Missions

    func isDone(_ m: VFMission) -> Bool { data.missions.contains(m.id) }

    func toggle(_ m: VFMission) {
        edit { d in
            if d.missions.contains(m.id) { d.missions.remove(m.id) } else {
                d.missions.insert(m.id)
                // Finir une mission fait avancer « où j'en suis » : la suite reste masquée.
                if m.chapter > d.chapter { d.chapter = m.chapter }
            }
        }
    }

    func objectiveDone(_ m: VFMission, _ i: Int) -> Bool { data.objectives[m.id]?.contains(i) ?? false }

    func toggleObjective(_ m: VFMission, _ i: Int) {
        edit { d in
            var s = Set(d.objectives[m.id] ?? [])
            if s.contains(i) { s.remove(i) } else { s.insert(i) }
            d.objectives[m.id] = s.sorted()
            if s.count == m.objectives.count, !m.objectives.isEmpty { d.missions.insert(m.id) }
        }
    }

    // MARK: Spoilers

    /// Masqué : au-delà du chapitre où tu en es (sauf si tu as choisi de tout voir).
    func hidden(_ spoiler: Int?) -> Bool {
        guard let s = spoiler, s > 0 else { return false }
        return !data.spoilersShown && s > data.chapter
    }

    // MARK: Lieux, objets, défis

    func visited(_ p: VFPlace) -> Bool { data.visited.contains(p.id) }

    // MARK: Easter eggs

    func found(_ e: VFEgg) -> Bool { data.eggs.contains(e.id) }
    func toggle(_ e: VFEgg) { edit { d in if d.eggs.contains(e.id) { d.eggs.remove(e.id) } else { d.eggs.insert(e.id) } } }
    func save(_ e: VFMyEgg) {
        edit { d in
            if let i = d.myEggs.firstIndex(where: { $0.id == e.id }) { d.myEggs[i] = e } else { d.myEggs.insert(e, at: 0) }
        }
    }
    func remove(_ e: VFMyEgg) {
        if let f = e.photo { try? FileManager.default.removeItem(at: Self.eggPhotoURL(f)) }
        edit { d in d.myEggs.removeAll { $0.id == e.id } }
    }
    // MARK: Captures des missions

    static let maxShots = 6
    func shots(_ m: VFMission) -> [String] { (data.missionShots[m.id] ?? []).filter { FileManager.default.fileExists(atPath: Self.eggPhotoURL($0).path) } }
    func addShot(_ m: VFMission, jpeg: Data) {
        guard shots(m).count < Self.maxShots else { return }
        let name = "mission-\(m.id)-\(UUID().uuidString.prefix(8)).jpg"
        guard (try? jpeg.write(to: Self.eggPhotoURL(name), options: .atomic)) != nil else { return }
        edit { d in d.missionShots[m.id, default: []].append(name) }
    }
    func removeShot(_ m: VFMission, _ name: String) {
        try? FileManager.default.removeItem(at: Self.eggPhotoURL(name))
        edit { d in d.missionShots[m.id]?.removeAll { $0 == name } }
    }

    static func eggPhotoURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    /// false : la limite gratuite est atteinte.
    @discardableResult
    func toggleVisited(_ p: VFPlace) -> Bool {
        if !data.visited.contains(p.id), !Store.shared.isPro, data.visited.count >= Self.freeVisited { return false }
        edit { d in if d.visited.contains(p.id) { d.visited.remove(p.id) } else { d.visited.insert(p.id) } }
        return true
    }

    func found(_ s: VFCollectibleSet) -> Int { data.collected[s.id] ?? 0 }

    func setFound(_ s: VFCollectibleSet, _ n: Int) {
        edit { $0.collected[s.id] = max(0, min(s.count, n)) }
    }

    func challengeDone(_ c: VFChallenge) -> Bool { data.challenges.contains(c.id) }

    func toggle(_ c: VFChallenge) {
        edit { d in if d.challenges.contains(c.id) { d.challenges.remove(c.id) } else { d.challenges.insert(c.id) } }
    }

    // MARK: Épingles

    var canAddPin: Bool { Store.shared.isPro || data.pins.count < Self.freePins }

    func add(_ pin: VFPin) { edit { $0.pins.append(pin) } }
    func update(_ pin: VFPin) { edit { d in if let i = d.pins.firstIndex(where: { $0.id == pin.id }) { d.pins[i] = pin } } }
    func remove(_ pin: VFPin) { edit { $0.pins.removeAll { $0.id == pin.id } } }

    // MARK: Personnages

    func isFavorite(_ c: VFCharacter) -> Bool { data.favorites.contains(c.id) }
    func toggleFavorite(_ c: VFCharacter) {
        edit { d in if d.favorites.contains(c.id) { d.favorites.remove(c.id) } else { d.favorites.insert(c.id) } }
    }

    // MARK: Le 100 %

    struct Parts {
        var missions: Double, places: Double, collectibles: Double, challenges: Double
        var all: [Double] { [missions, places, collectibles, challenges] }
        var total: Double {
            let xs = all
            return xs.reduce(0, +) / Double(max(1, xs.count))
        }
    }

    func parts(_ c: VFContent) -> Parts {
        let missions = c.missions.filter { $0.optional != true }
        let m = missions.isEmpty ? 0 : Double(missions.filter { data.missions.contains($0.id) }.count) / Double(missions.count)
        let places = c.places.filter { $0.kind != .region && !$0.community }
        let p = places.isEmpty ? 0 : Double(places.filter { data.visited.contains($0.id) }.count) / Double(places.count)
        let total = c.collectibles.reduce(0) { $0 + $1.target }
        let found = c.collectibles.reduce(0) { $0 + min($1.target, data.collected[$1.id] ?? 0) }
        let col = total == 0 ? 0 : Double(found) / Double(total)
        let ch = c.challenges.isEmpty ? 0 : Double(c.challenges.filter { data.challenges.contains($0.id) }.count) / Double(c.challenges.count)
        return Parts(missions: m, places: p, collectibles: col, challenges: ch)
    }

    func nextMission(_ c: VFContent) -> VFMission? {
        c.missions.filter { $0.optional != true }.sorted { ($0.chapter, c.missions.firstIndex(of: $0) ?? 0) < ($1.chapter, c.missions.firstIndex(of: $1) ?? 0) }
            .first { !data.missions.contains($0.id) }
    }

    var hours: Double { data.psnHours ?? data.manualHours }

    /// Ce que montrent les widgets (et leur aperçu dans l'app).
    func snapshot() -> VFSnapshot {
        let c = ContentStore.shared.content
        let p = parts(c)
        let next = nextMission(c)
        var s = VFSnapshot()
        s.percent = p.total
        s.missions = p.missions; s.places = p.places; s.collectibles = p.collectibles; s.challenges = p.challenges
        s.nextMission = next.map { hidden($0.chapter) ? String(localized: "Next mission") : $0.title }
        s.nextChapter = next.flatMap { ContentStore.shared.chapter($0.chapter)?.title }
        s.hours = hours
        s.pro = Store.shared.isPro
        let story = c.missions.filter { $0.optional != true }
        let places = c.places.filter { $0.kind != .region && !$0.community }
        let total = c.collectibles.reduce(0) { $0 + $1.target }
        let found = c.collectibles.reduce(0) { $0 + min($1.target, data.collected[$1.id] ?? 0) }
        s.counts = [story.filter { data.missions.contains($0.id) }.count, story.count,
                    places.filter { data.visited.contains($0.id) }.count, places.count,
                    found, total,
                    c.challenges.filter { data.challenges.contains($0.id) }.count, c.challenges.count]
        s.eggs = [c.eggs.filter { data.eggs.contains($0.id) }.count, c.eggs.count]
        s.chapter = data.chapter
        s.updated = Date(timeIntervalSince1970: 0)
        return s
    }

    func writeSnapshot() {
        let s = snapshot()
        GameCenterHub.shared.report(s.percent)
        if s != VFSnapshot.load() {
            s.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
