// Progress.swift — Vicefold
//
// Ta partie : missions faites, lieux visités, objets trouvés, défis, épingles, notes, où tu en es dans l'histoire.
// Tout reste sur l'iPhone (aucun compte), et passe d'un appareil à l'autre par iCloud avec Pro.

import Foundation
import Observation
import SwiftUI
import WidgetKit

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
    var updated = Date()
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
            if Store.shared.isPro { kvs.set(d, forKey: Self.kvsKey) }
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
        d.visited = Set(c.places.filter { $0.kind != .region }.prefix(7).map(\.id))
        for (i, s) in c.collectibles.enumerated() { d.collected[s.id] = Int(Double(s.target) * [0.62, 0.35, 0.8, 0.5, 0.2, 0.9][i % 6]) }
        d.challenges = ["f-narco", "f-cars"]
        d.favorites = ["lucia", "jason"]
        d.readGuides = ["start-how"]
        d.pins = [VFPin(name: "Stash", note: "Behind the bait shop", icon: "dollarsign", color: 2, x: 0.6, y: 0.86),
                  VFPin(name: "Car to scan", icon: "car.fill", color: 1, x: 0.84, y: 0.66),
                  VFPin(name: "Sunset spot", icon: "camera.fill", color: 3, x: 0.9, y: 0.7)]
        return d
    }

    // MARK: iCloud (Pro)

    func pushCloud() {
        guard Store.shared.isPro, let d = try? JSONEncoder().encode(data) else { return }
        kvs.set(d, forKey: Self.kvsKey)
        kvs.synchronize()
    }

    func pullCloud() {
        guard Store.shared.isPro, let d = kvs.data(forKey: Self.kvsKey),
              let other = try? JSONDecoder().decode(VFProgressData.self, from: d), other != data else { return }
        data = Self.merge(data, other)
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: fileURL, options: .atomic) }
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
        let places = c.places.filter { $0.kind != .region }
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

    func writeSnapshot() {
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
        if s != VFSnapshot.load() {
            s.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
