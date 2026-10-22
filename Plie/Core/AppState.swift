import SwiftUI
import Observation

enum Route: Equatable {
    case hub
    case rayonLevels
    case rayon(Int)
    case pliageLevels
    case pliage(Int)
    case basculeLevels
    case bascule(Int)
    case ferme
    case panier
    case flechettes
    case airHockey
    case coffreLevels
    case coffre(Int)
    case coffreDuel
    case soleil
}

/// Navigation, réglages et progression des joueurs (sauvegardés sur l'appareil).
@Observable
final class AppState {
    var route: Route = .hub
    var showPass = false

    private(set) var soundOn = true
    private(set) var hapticsOn = true
    private(set) var musicOn = true

    /// Niveaux de RAYON réussis, et meilleur temps par niveau.
    private(set) var rayonSolved: Set<Int> = []
    private(set) var rayonBest: [Int: Double] = [:]

    /// Pliages réussis, et meilleur temps.
    private(set) var pliageSolved: Set<Int> = []
    private(set) var pliageBest: [Int: Double] = [:]

    /// BASCULE : étoiles par niveau réussi.
    private(set) var basculeStars: [Int: Int] = [:]

    /// FERME : les plantes qui ont poussé.
    private(set) var fermeGarden: [FermeRecord] = []

    /// Records des jeux d'arcade.
    private(set) var panierBest = 0
    private(set) var flechettesBest = 0

    /// Coffres ouverts : meilleur temps et étoiles.
    private(set) var coffreBest: [Int: Double] = [:]
    private(set) var coffreStars: [Int: Int] = [:]

    private(set) var soleilGames = 0

    /// Nombre de niveaux jouables sans le Pass.
    static let freeRayonLevels = 20
    static let freePliageLevels = 15
    static let freeBasculeLevels = 10
    static let freeCoffreLevels = 10

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        load()
        SoundPlayer.shared.enabled = soundOn
        Haptics.enabled = hapticsOn
        MusicPlayer.shared.setEnabled(musicOn)
    }

    #if DEBUG
    /// Captures automatiques : `-screenshotRoute rayon:3` ouvre directement le niveau 3 de RAYON.
    func applyScreenshotRoute() {
        guard let value = UserDefaults.standard.string(forKey: "screenshotRoute") else { return }
        let parts = value.split(separator: ":").map(String.init)
        let number = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        switch parts.first ?? "" {
        case "rayonLevels": route = .rayonLevels
        case "rayon": route = .rayon(number)
        case "pliageLevels": route = .pliageLevels
        case "pliage": route = .pliage(number)
        case "basculeLevels": route = .basculeLevels
        case "bascule": route = .bascule(number)
        case "ferme": route = .ferme
        case "panier": route = .panier
        case "flechettes": route = .flechettes
        case "airHockey": route = .airHockey
        case "coffreLevels": route = .coffreLevels
        case "coffre": route = .coffre(number)
        case "coffreDuel": route = .coffreDuel
        case "soleil": route = .soleil
        case "pass": showPass = true
        default: route = .hub
        }
    }
    #endif

    // MARK: Réglages

    func setSound(_ on: Bool) {
        soundOn = on
        SoundPlayer.shared.enabled = on
        defaults.set(on, forKey: Keys.sound)
    }

    func setMusic(_ on: Bool) {
        musicOn = on
        MusicPlayer.shared.setEnabled(on)
        defaults.set(on, forKey: Keys.music)
    }

    func setHaptics(_ on: Bool) {
        hapticsOn = on
        Haptics.enabled = on
        defaults.set(on, forKey: Keys.haptics)
    }

    // MARK: RAYON

    func rayonIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freeRayonLevels && !hasPass { return false }
        return number == 1 || rayonSolved.contains(number - 1) || rayonSolved.contains(number)
    }

    func rayonNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freeRayonLevels && !hasPass
    }

    func recordRayon(_ number: Int, time: Double) {
        rayonSolved.insert(number)
        if let best = rayonBest[number] {
            rayonBest[number] = min(best, time)
        } else {
            rayonBest[number] = time
        }
        save()
    }

    // MARK: PLIAGE

    func pliageIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freePliageLevels && !hasPass { return false }
        return number == 1 || pliageSolved.contains(number - 1) || pliageSolved.contains(number)
    }

    func pliageNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freePliageLevels && !hasPass
    }

    func recordPliage(_ number: Int, time: Double) {
        pliageSolved.insert(number)
        if let best = pliageBest[number] {
            pliageBest[number] = min(best, time)
        } else {
            pliageBest[number] = time
        }
        save()
    }

    // MARK: BASCULE

    func basculeIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freeBasculeLevels && !hasPass { return false }
        return number == 1 || basculeStars[number - 1] != nil || basculeStars[number] != nil
    }

    func basculeNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freeBasculeLevels && !hasPass
    }

    func recordBascule(_ number: Int, stars: Int) {
        basculeStars[number] = max(basculeStars[number] ?? 0, stars)
        save()
    }

    // MARK: FERME

    func recordFerme(_ record: FermeRecord) {
        fermeGarden.append(record)
        save()
    }

    /// Nombre de jours d'affilée (jusqu'à aujourd'hui ou hier) avec au moins une plante.
    var fermeStreak: Int {
        let calendar = Calendar.current
        let days = Set(fermeGarden.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    // MARK: Arcade

    func recordPanier(_ score: Int) {
        if score > panierBest { panierBest = score; save() }
    }

    func recordFlechettes(_ score: Int) {
        if score > flechettesBest { flechettesBest = score; save() }
    }

    // MARK: COFFRE

    func coffreIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freeCoffreLevels && !hasPass { return false }
        return number == 1 || coffreBest[number - 1] != nil || coffreBest[number] != nil
    }

    func coffreNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freeCoffreLevels && !hasPass
    }

    func recordCoffre(_ number: Int, time: Double, stars: Int) {
        if let best = coffreBest[number] {
            coffreBest[number] = min(best, time)
        } else {
            coffreBest[number] = time
        }
        coffreStars[number] = max(coffreStars[number] ?? 0, stars)
        save()
    }

    // MARK: SOLEIL

    func recordSoleilGame() {
        soleilGames += 1
        save()
    }

    // MARK: Sauvegarde

    private enum Keys {
        static let sound = "sound"
        static let haptics = "haptics"
        static let music = "music"
        static let rayonSolved = "rayon.solved"
        static let rayonBest = "rayon.best"
        static let pliageSolved = "pliage.solved"
        static let basculeStars = "bascule.stars"
        static let fermeGarden = "ferme.garden"
        static let panierBest = "panier.best"
        static let flechettesBest = "flechettes.best"
        static let pliageBest = "pliage.best"
        static let coffreBest = "coffre.best"
        static let coffreStars = "coffre.stars"
        static let soleilGames = "soleil.games"
    }

    private func load() {
        // Version 2 des niveaux RAYON : les mondes 2 et suivants ont été refaits avec les pivots.
        if defaults.integer(forKey: "rayon.levelsVersion") < 2 {
            if let solved = defaults.array(forKey: Keys.rayonSolved) as? [Int] {
                defaults.set(solved.filter { $0 <= 15 }, forKey: Keys.rayonSolved)
            }
            defaults.set(2, forKey: "rayon.levelsVersion")
        }
        if defaults.object(forKey: Keys.sound) != nil { soundOn = defaults.bool(forKey: Keys.sound) }
        if defaults.object(forKey: Keys.haptics) != nil { hapticsOn = defaults.bool(forKey: Keys.haptics) }
        if defaults.object(forKey: Keys.music) != nil { musicOn = defaults.bool(forKey: Keys.music) }
        if let solved = defaults.array(forKey: Keys.rayonSolved) as? [Int] { rayonSolved = Set(solved) }
        rayonBest = decode(Keys.rayonBest)
        if let solved = defaults.array(forKey: Keys.pliageSolved) as? [Int] { pliageSolved = Set(solved) }
        pliageBest = decode(Keys.pliageBest)
        basculeStars = decode(Keys.basculeStars).mapValues { Int($0) }
        if let data = defaults.data(forKey: Keys.fermeGarden),
           let garden = try? JSONDecoder().decode([FermeRecord].self, from: data) {
            fermeGarden = garden
        }
        panierBest = defaults.integer(forKey: Keys.panierBest)
        flechettesBest = defaults.integer(forKey: Keys.flechettesBest)
        coffreBest = decode(Keys.coffreBest)
        let stars: [Int: Double] = decode(Keys.coffreStars)
        coffreStars = stars.mapValues { Int($0) }
        soleilGames = defaults.integer(forKey: Keys.soleilGames)
    }

    private func save() {
        defaults.set(Array(rayonSolved), forKey: Keys.rayonSolved)
        encode(rayonBest, Keys.rayonBest)
        defaults.set(Array(pliageSolved), forKey: Keys.pliageSolved)
        encode(pliageBest, Keys.pliageBest)
        encode(basculeStars.mapValues { Double($0) }, Keys.basculeStars)
        if let data = try? JSONEncoder().encode(fermeGarden) {
            defaults.set(data, forKey: Keys.fermeGarden)
        }
        defaults.set(panierBest, forKey: Keys.panierBest)
        defaults.set(flechettesBest, forKey: Keys.flechettesBest)
        encode(coffreBest, Keys.coffreBest)
        encode(coffreStars.mapValues { Double($0) }, Keys.coffreStars)
        defaults.set(soleilGames, forKey: Keys.soleilGames)
    }

    /// Les dictionnaires sont rangés avec des clés texte (« 12 » → 8,4 secondes).
    private func encode(_ dict: [Int: Double], _ key: String) {
        var stored: [String: Double] = [:]
        for (level, value) in dict { stored[String(level)] = value }
        defaults.set(stored, forKey: key)
    }

    private func decode(_ key: String) -> [Int: Double] {
        guard let stored = defaults.dictionary(forKey: key) else { return [:] }
        var result: [Int: Double] = [:]
        for (level, value) in stored {
            if let number = Int(level), let seconds = value as? Double {
                result[number] = seconds
            }
        }
        return result
    }
}
