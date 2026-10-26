import SwiftUI
import Observation

enum Route: Equatable {
    case hub
    case rayonLevels
    case rayon(Int)
    case basculeLevels
    case bascule(Int)
    case ferme
    case airHockey
    case filet
    case chess
    case draughts
    case piano
    case boite
    case croco
    case coupDoeil
    case bombe
    case dessine
    case pliou
    case briques
    case bonneteau
    case morpion
    case puissance
    case soleil
    case billard
    case luciole
    case ecole
    case duels
    case mots
}

/// Navigation, réglages et progression des joueurs (sauvegardés sur l'appareil).
@Observable
final class AppState {
    var route: Route = .hub
    var showPass = false

    private(set) var soundOn = true
    private(set) var hapticsOn = true
    private(set) var musicOn = true
    /// Victoires et réussites : après quelques-unes, on propose de noter l'app.
    private(set) var happyMoments = 0
    private(set) var reviewRequest = 0
    /// Jeux débloqués avec une clé, clés en poche, parties vers la prochaine clé.
    private(set) var unlockedGames: Set<String> = []
    private(set) var keys = 0
    private(set) var keyProgress = 0
    private(set) var keysEarned = 0
    /// Change à chaque nouvelle clé gagnée (pour l'annoncer).
    private(set) var newKey = 0
    private(set) var lastGame: String?

    /// Niveaux de RAYON réussis, et meilleur temps par niveau.
    private(set) var rayonSolved: Set<Int> = []
    private(set) var rayonBest: [Int: Double] = [:]

    /// BASCULE : étoiles par niveau réussi.
    private(set) var basculeStars: [Int: Int] = [:]

    /// FERME : les plantes qui ont poussé.
    private(set) var fermeGarden: [FermeRecord] = []

    /// FILET : plus haut niveau battu (0 = aucun) et nombre de victoires.
    private(set) var filetBestLevel = 0
    private(set) var filetWins = 0
    /// Jeux de plateau : parties terminées et victoires contre l'ordinateur (meilleur niveau battu).
    private(set) var chessGames = 0
    private(set) var chessBestLevel = 0
    private(set) var draughtsGames = 0
    private(set) var draughtsBestLevel = 0

    /// LA BOÎTE : étoiles par boîte ouverte.
    private(set) var boiteStars: [Int: Int] = [:]
    /// CROCO : record de dents (seul) et parties jouées.
    private(set) var crocoBest = 0
    private(set) var crocoGames = 0
    /// COUP D'ŒIL : étoiles par niveau, défi du jour et série de jours.
    private(set) var oeilStars: [Int: Int] = [:]
    private(set) var oeilDailyDay = ""
    private(set) var oeilDailyScore = 0
    private(set) var oeilStreak = 0
    /// BOMBE et DESSINE-MOI : parties jouées, mots trouvés.
    private(set) var bombeGames = 0
    private(set) var dessineGames = 0
    private(set) var dessineWords = 0
    /// PLIOU : jours où on s'en est occupé.
    private(set) var pliouDays = 0
    /// MORPION et PUISSANCE 4 : parties et victoires contre l'ordinateur.
    private(set) var morpionGames = 0
    private(set) var morpionWins = 0
    private(set) var puissanceGames = 0
    private(set) var puissanceWins = 0
    /// BONNETEAU : meilleur niveau seul, parties à deux.
    private(set) var bonneteauBest = 0
    private(set) var bonneteauGames = 0
    /// CASSE-BRIQUES : étoiles par niveau réussi.
    private(set) var briquesStars: [Int: Int] = [:]
    /// DUELS : parties jouées. MOTS INTERDITS : manches et record de mots trouvés en une manche.
    private(set) var duelsGames = 0
    private(set) var motsRounds = 0
    private(set) var motsBest = 0

    private(set) var soleilGames = 0

    /// LUCIOLE : meilleur total de lumières et voyages terminés.
    private(set) var lucioleBest = 0
    private(set) var lucioleVoyages = 0
    /// ÉCOLE : meilleur nombre d'étoiles (sur 10) par classe, et leçons terminées.
    private(set) var ecoleStars: [Int: Int] = [:]
    private(set) var ecoleLessons = 0
    /// BILLARD : parties gagnées.
    private(set) var billardWins = 0

    /// FERME : le vrai arbre. `treePending` : le jardin est complet, l'envoi au compteur reste à faire.
    private(set) var treePending = false
    private(set) var treeNumber = 0

    /// Nombre de niveaux jouables sans le Pass.
    static let freeRayonLevels = 20
    static let freeBasculeLevels = 10
    static let freeBoiteLevels = 12
    static let freeBriquesLevels = 15

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        load()
        SoundPlayer.shared.enabled = soundOn
        Haptics.enabled = hapticsOn
        MusicPlayer.shared.setEnabled(musicOn)
        // Un jardin complet n'a pas encore pu être compté (pas de réseau) : on réessaie.
        if fermeComplete && treeNumber == 0 { treePending = true }
        sendTree()
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
        case "basculeLevels": route = .basculeLevels
        case "bascule": route = .bascule(number)
        case "ferme": route = .ferme
        case "airHockey": route = .airHockey
        case "filet": route = .filet
        case "chess": route = .chess
        case "draughts": route = .draughts
        case "piano": route = .piano
        case "boite": route = .boite
        case "croco": route = .croco
        case "coupDoeil": route = .coupDoeil
        case "bombe": route = .bombe
        case "dessine": route = .dessine
        case "pliou": route = .pliou
        case "briques": route = .briques
        case "bonneteau": route = .bonneteau
        case "morpion": route = .morpion
        case "puissance": route = .puissance
        case "soleil": route = .soleil
        case "billard": route = .billard
        case "luciole": route = .luciole
        case "ecole": route = .ecole
        case "duels": route = .duels
        case "mots": route = .mots
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

    /// Une victoire ou une réussite. À la 4e, la 15e et la 40e, on propose de noter l'app
    /// (iOS limite de toute façon l'affichage à trois fois par an).
    func celebrate() {
        happyMoments += 1
        defaults.set(happyMoments, forKey: "happyMoments")
        if [4, 15, 40].contains(happyMoments) { reviewRequest += 1 }
    }

    // MARK: Jeux à débloquer
    //
    // Six jeux sont ouverts dès le départ. Les autres se débloquent avec des clés : on gagne une clé
    // à la fin de sa première partie, puis toutes les 3 parties, et on choisit le jeu à ouvrir.
    // Le Pass Origamo ouvre tout, tout de suite.

    static let starterGames: [GameID] = [.duels, .boite, .croco, .mots, .coupDoeil, .rayon]

    /// Parties à jouer pour gagner la prochaine clé.
    var gamesPerKey: Int { keysEarned == 0 ? 1 : 3 }

    func isUnlocked(_ game: GameID, hasPass: Bool) -> Bool {
        hasPass || Self.starterGames.contains(game) || unlockedGames.contains(game.rawValue)
    }

    var lockedCount: Int {
        GameID.allCases.filter { !Self.starterGames.contains($0) && !unlockedGames.contains($0.rawValue) }.count
    }

    /// Une partie terminée : on avance vers la prochaine clé.
    func gamePlayed() {
        guard lockedCount > keys else { return }
        keyProgress += 1
        if keyProgress >= gamesPerKey {
            keyProgress = 0
            keys += 1
            keysEarned += 1
            newKey += 1
        }
        defaults.set(keyProgress, forKey: Keys.keyProgress)
        defaults.set(keys, forKey: Keys.keys)
        defaults.set(keysEarned, forKey: Keys.keysEarned)
    }

    @discardableResult
    func unlock(_ game: GameID) -> Bool {
        guard keys > 0, !unlockedGames.contains(game.rawValue), !Self.starterGames.contains(game) else { return false }
        keys -= 1
        unlockedGames.insert(game.rawValue)
        defaults.set(Array(unlockedGames), forKey: Keys.unlockedGames)
        defaults.set(keys, forKey: Keys.keys)
        celebrate()
        return true
    }

    /// Le dernier jeu ouvert, pour « Reprendre » sur l'accueil.
    func opened(_ game: GameID) {
        guard lastGame != game.rawValue else { return }
        lastGame = game.rawValue
        defaults.set(game.rawValue, forKey: Keys.lastGame)
    }

    var lastPlayed: GameID? { lastGame.flatMap { GameID(rawValue: $0) } }

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
        gamePlayed()
        celebrate()
        rayonSolved.insert(number)
        if let best = rayonBest[number] {
            rayonBest[number] = min(best, time)
        } else {
            rayonBest[number] = time
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
        gamePlayed()
        if stars > 0 { celebrate() }
        basculeStars[number] = max(basculeStars[number] ?? 0, stars)
        save()
    }

    // MARK: FERME

    func recordFerme(_ record: FermeRecord) {
        gamePlayed()
        celebrate()
        fermeGarden.append(record)
        if fermeComplete && treeNumber == 0 && !treePending {
            treePending = true
        }
        save()
        sendTree()
    }

    /// Les espèces qui ont déjà fleuri au moins une fois.
    var fermeSpecies: Set<String> { Set(fermeGarden.map(\.plant)) }

    /// Les 8 plantes ont fleuri : on plante un vrai arbre.
    var fermeComplete: Bool { FermePlant.all.allSatisfy { fermeSpecies.contains($0.id) } }

    /// Envoie « +1 jardin complet » au compteur (anonyme). Réessaie au prochain lancement si besoin.
    func sendTree() {
        guard treePending else { return }
        TreeCounter.send { [weak self] number in
            guard let self, let number else { return }
            self.treePending = false
            self.treeNumber = max(1, number)
            self.defaults.set(false, forKey: Keys.treePending)
            self.defaults.set(self.treeNumber, forKey: Keys.treeNumber)
        }
    }

    // MARK: Nouveaux jeux

    func recordLuciole(lights: Int, stars: Int) {
        gamePlayed()
        celebrate()
        lucioleVoyages += 1
        lucioleBest = max(lucioleBest, lights)
        save()
    }

    func recordEcole(classRaw: Int, stars: Int) {
        gamePlayed()
        if stars >= 5 { celebrate() }
        ecoleLessons += 1
        ecoleStars[classRaw] = max(ecoleStars[classRaw] ?? 0, stars)
        save()
    }

    func recordBillard(won: Bool) {
        gamePlayed()
        guard won else { return }
        celebrate()
        billardWins += 1
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

    /// Le niveau Champion de FILET fait partie du Pass.
    static let freeFiletLevel = 2

    func filetNeedsPass(_ level: Int, hasPass: Bool) -> Bool {
        level > Self.freeFiletLevel && !hasPass
    }

    /// Le niveau « Difficile » de l'ordinateur, aux échecs et aux dames, fait partie du Pass.
    func boardLevelNeedsPass(_ level: Int, hasPass: Bool) -> Bool {
        level >= 3 && !hasPass
    }

    func recordBoardGame(chess: Bool, wonAgainstComputer: Bool, level: Int) {
        gamePlayed()
        celebrate()
        if chess {
            chessGames += 1
            if wonAgainstComputer { chessBestLevel = max(chessBestLevel, level) }
        } else {
            draughtsGames += 1
            if wonAgainstComputer { draughtsBestLevel = max(draughtsBestLevel, level) }
        }
        save()
    }

    func recordFilet(level: Int, won: Bool) {
        gamePlayed()
        guard won else { return }
        celebrate()
        filetWins += 1
        filetBestLevel = max(filetBestLevel, level)
        save()
    }

    // MARK: LA BOÎTE

    func boiteIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freeBoiteLevels && !hasPass { return false }
        return number == 1 || boiteStars[number - 1] != nil || boiteStars[number] != nil
    }

    func boiteNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freeBoiteLevels && !hasPass
    }

    func recordBoite(_ number: Int, stars: Int) {
        gamePlayed()
        celebrate()
        boiteStars[number] = max(boiteStars[number] ?? 0, stars)
        save()
    }

    // MARK: CROCO

    /// `streak` : dents appuyées seul, ou -1 pour une partie à plusieurs.
    func recordCroco(streak: Int) {
        gamePlayed()
        crocoGames += 1
        if streak > crocoBest {
            crocoBest = streak
            celebrate()
        }
        save()
    }

    // MARK: COUP D'ŒIL, BOMBE, DESSINE-MOI, PLIOU

    func recordOeil(level: Int, stars: Int) {
        gamePlayed()
        guard stars > 0 else { return }
        celebrate()
        oeilStars[level] = max(oeilStars[level] ?? 0, stars)
        save()
    }

    /// Défi du jour : la série continue si le dernier défi date d'hier.
    func recordOeilDaily(day: String, correct: Int) {
        guard oeilDailyDay != day else {
            oeilDailyScore = max(oeilDailyScore, correct)
            save()
            return
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var continues = false
        if let today = formatter.date(from: day), let last = formatter.date(from: oeilDailyDay),
           let gap = Calendar.current.dateComponents([.day], from: last, to: today).day {
            continues = gap == 1
        }
        oeilStreak = continues ? oeilStreak + 1 : 1
        oeilDailyDay = day
        oeilDailyScore = correct
        if correct >= 3 { celebrate() }
        save()
    }

    func recordBombe() {
        gamePlayed()
        bombeGames += 1
        celebrate()
        save()
    }

    func recordDessine(found: Int) {
        gamePlayed()
        dessineGames += 1
        dessineWords += found
        if found > 0 { celebrate() }
        save()
    }

    func recordPliou(days: Int) {
        guard days != pliouDays else { return }
        pliouDays = days
        save()
    }

    // MARK: MORPION, PUISSANCE 4, BONNETEAU, CASSE-BRIQUES

    func recordMorpion(won: Bool) {
        gamePlayed()
        morpionGames += 1
        if won {
            morpionWins += 1
            celebrate()
        }
        save()
    }

    func recordPuissance(won: Bool) {
        gamePlayed()
        puissanceGames += 1
        if won {
            puissanceWins += 1
            celebrate()
        }
        save()
    }

    func recordDuels() {
        gamePlayed()
        duelsGames += 1
        save()
    }

    func recordMots(found: Int) {
        gamePlayed()
        motsRounds += 1
        if found > motsBest {
            motsBest = found
        }
        save()
    }

    /// `level` : niveau atteint seul (0 pour une partie à deux).
    func recordBonneteau(level: Int) {
        gamePlayed()
        bonneteauGames += 1
        if level > bonneteauBest {
            bonneteauBest = level
            celebrate()
        }
        save()
    }

    func briquesIsUnlocked(_ number: Int, hasPass: Bool) -> Bool {
        if number > Self.freeBriquesLevels && !hasPass { return false }
        return number == 1 || briquesStars[number - 1] != nil || briquesStars[number] != nil
    }

    func briquesNeedsPass(_ number: Int, hasPass: Bool) -> Bool {
        number > Self.freeBriquesLevels && !hasPass
    }

    func recordBriques(_ number: Int, stars: Int) {
        gamePlayed()
        celebrate()
        briquesStars[number] = max(briquesStars[number] ?? 0, stars)
        save()
    }

    // MARK: SOLEIL

    func recordSoleilGame() {
        gamePlayed()
        celebrate()
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
        static let basculeStars = "bascule.stars"
        static let fermeGarden = "ferme.garden"
        static let filetBest = "filet.bestLevel"
        static let filetWins = "filet.wins"
        static let chessGames = "chess.games"
        static let chessBest = "chess.bestLevel"
        static let draughtsGames = "draughts.games"
        static let draughtsBest = "draughts.bestLevel"
        static let boiteStars = "boite.stars"
        static let crocoBest = "croco.best"
        static let crocoGames = "croco.games"
        static let oeilStars = "oeil.stars"
        static let oeilDailyDay = "oeil.dailyDay"
        static let oeilDailyScore = "oeil.dailyScore"
        static let oeilStreak = "oeil.streak"
        static let bombeGames = "bombe.games"
        static let dessineGames = "dessine.games"
        static let dessineWords = "dessine.words"
        static let pliouDays = "pliou.days"
        static let morpionGames = "morpion.games"
        static let morpionWins = "morpion.wins"
        static let puissanceGames = "puissance.games"
        static let puissanceWins = "puissance.wins"
        static let bonneteauBest = "bonneteau.best"
        static let bonneteauGames = "bonneteau.games"
        static let briquesStars = "briques.stars"
        static let duelsGames = "duels.games"
        static let motsRounds = "mots.rounds"
        static let motsBest = "mots.best"
        static let soleilGames = "soleil.games"
        static let lucioleBest = "luciole.best"
        static let lucioleVoyages = "luciole.voyages"
        static let ecoleStars = "ecole.stars"
        static let ecoleLessons = "ecole.lessons"
        static let billardWins = "billard.wins"
        static let treePending = "ferme.treePending"
        static let treeNumber = "ferme.treeNumber"
        static let unlockedGames = "unlock.games"
        static let keys = "unlock.keys"
        static let keyProgress = "unlock.progress"
        static let keysEarned = "unlock.earned"
        static let lastGame = "hub.lastGame"
    }

    private func load() {
        unlockedGames = Set(defaults.stringArray(forKey: Keys.unlockedGames) ?? [])
        keys = defaults.integer(forKey: Keys.keys)
        keyProgress = defaults.integer(forKey: Keys.keyProgress)
        keysEarned = defaults.integer(forKey: Keys.keysEarned)
        lastGame = defaults.string(forKey: Keys.lastGame)
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
        happyMoments = defaults.integer(forKey: "happyMoments")
        if let solved = defaults.array(forKey: Keys.rayonSolved) as? [Int] { rayonSolved = Set(solved) }
        rayonBest = decode(Keys.rayonBest)
        basculeStars = decode(Keys.basculeStars).mapValues { Int($0) }
        if let data = defaults.data(forKey: Keys.fermeGarden),
           let garden = try? JSONDecoder().decode([FermeRecord].self, from: data) {
            fermeGarden = garden
        }
        filetBestLevel = defaults.integer(forKey: Keys.filetBest)
        filetWins = defaults.integer(forKey: Keys.filetWins)
        chessGames = defaults.integer(forKey: Keys.chessGames)
        chessBestLevel = defaults.integer(forKey: Keys.chessBest)
        draughtsGames = defaults.integer(forKey: Keys.draughtsGames)
        draughtsBestLevel = defaults.integer(forKey: Keys.draughtsBest)
        boiteStars = decode(Keys.boiteStars).mapValues { Int($0) }
        crocoBest = defaults.integer(forKey: Keys.crocoBest)
        crocoGames = defaults.integer(forKey: Keys.crocoGames)
        oeilStars = decode(Keys.oeilStars).mapValues { Int($0) }
        oeilDailyDay = defaults.string(forKey: Keys.oeilDailyDay) ?? ""
        oeilDailyScore = defaults.integer(forKey: Keys.oeilDailyScore)
        oeilStreak = defaults.integer(forKey: Keys.oeilStreak)
        bombeGames = defaults.integer(forKey: Keys.bombeGames)
        dessineGames = defaults.integer(forKey: Keys.dessineGames)
        dessineWords = defaults.integer(forKey: Keys.dessineWords)
        pliouDays = defaults.integer(forKey: Keys.pliouDays)
        morpionGames = defaults.integer(forKey: Keys.morpionGames)
        morpionWins = defaults.integer(forKey: Keys.morpionWins)
        puissanceGames = defaults.integer(forKey: Keys.puissanceGames)
        puissanceWins = defaults.integer(forKey: Keys.puissanceWins)
        bonneteauBest = defaults.integer(forKey: Keys.bonneteauBest)
        bonneteauGames = defaults.integer(forKey: Keys.bonneteauGames)
        briquesStars = decode(Keys.briquesStars).mapValues { Int($0) }
        duelsGames = defaults.integer(forKey: Keys.duelsGames)
        motsRounds = defaults.integer(forKey: Keys.motsRounds)
        motsBest = defaults.integer(forKey: Keys.motsBest)
        soleilGames = defaults.integer(forKey: Keys.soleilGames)
        lucioleBest = defaults.integer(forKey: Keys.lucioleBest)
        lucioleVoyages = defaults.integer(forKey: Keys.lucioleVoyages)
        ecoleStars = decode(Keys.ecoleStars).mapValues { Int($0) }
        ecoleLessons = defaults.integer(forKey: Keys.ecoleLessons)
        billardWins = defaults.integer(forKey: Keys.billardWins)
        treePending = defaults.bool(forKey: Keys.treePending)
        treeNumber = defaults.integer(forKey: Keys.treeNumber)
    }

    private func save() {
        defaults.set(Array(rayonSolved), forKey: Keys.rayonSolved)
        encode(rayonBest, Keys.rayonBest)
        encode(basculeStars.mapValues { Double($0) }, Keys.basculeStars)
        if let data = try? JSONEncoder().encode(fermeGarden) {
            defaults.set(data, forKey: Keys.fermeGarden)
        }
        defaults.set(filetBestLevel, forKey: Keys.filetBest)
        defaults.set(filetWins, forKey: Keys.filetWins)
        defaults.set(chessGames, forKey: Keys.chessGames)
        defaults.set(chessBestLevel, forKey: Keys.chessBest)
        defaults.set(draughtsGames, forKey: Keys.draughtsGames)
        defaults.set(draughtsBestLevel, forKey: Keys.draughtsBest)
        encode(boiteStars.mapValues { Double($0) }, Keys.boiteStars)
        defaults.set(crocoBest, forKey: Keys.crocoBest)
        defaults.set(crocoGames, forKey: Keys.crocoGames)
        encode(oeilStars.mapValues { Double($0) }, Keys.oeilStars)
        defaults.set(oeilDailyDay, forKey: Keys.oeilDailyDay)
        defaults.set(oeilDailyScore, forKey: Keys.oeilDailyScore)
        defaults.set(oeilStreak, forKey: Keys.oeilStreak)
        defaults.set(bombeGames, forKey: Keys.bombeGames)
        defaults.set(dessineGames, forKey: Keys.dessineGames)
        defaults.set(dessineWords, forKey: Keys.dessineWords)
        defaults.set(pliouDays, forKey: Keys.pliouDays)
        defaults.set(morpionGames, forKey: Keys.morpionGames)
        defaults.set(morpionWins, forKey: Keys.morpionWins)
        defaults.set(puissanceGames, forKey: Keys.puissanceGames)
        defaults.set(puissanceWins, forKey: Keys.puissanceWins)
        defaults.set(bonneteauBest, forKey: Keys.bonneteauBest)
        defaults.set(bonneteauGames, forKey: Keys.bonneteauGames)
        encode(briquesStars.mapValues { Double($0) }, Keys.briquesStars)
        defaults.set(duelsGames, forKey: Keys.duelsGames)
        defaults.set(motsRounds, forKey: Keys.motsRounds)
        defaults.set(motsBest, forKey: Keys.motsBest)
        defaults.set(soleilGames, forKey: Keys.soleilGames)
        defaults.set(lucioleBest, forKey: Keys.lucioleBest)
        defaults.set(lucioleVoyages, forKey: Keys.lucioleVoyages)
        encode(ecoleStars.mapValues { Double($0) }, Keys.ecoleStars)
        defaults.set(ecoleLessons, forKey: Keys.ecoleLessons)
        defaults.set(billardWins, forKey: Keys.billardWins)
        defaults.set(treePending, forKey: Keys.treePending)
        defaults.set(treeNumber, forKey: Keys.treeNumber)
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
