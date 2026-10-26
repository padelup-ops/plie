import SwiftUI

extension Theme {
    static let navale = Color(hex: 0x3DC8FF)
    static let navaleSea = Color(hex: 0x0B3A5C)
}

// MARK: - BATAILLE NAVALE
//
// Plié en L, comme le vrai jeu : en haut (debout) les eaux ennemies où l'on tire, en bas (à plat) sa propre flotte.
// À deux, on referme le Duo pour se le passer : personne ne voit les bateaux de l'autre.

struct NavaleShip: Identifiable, Equatable {
    let id: Int
    let length: Int
    var x: Int
    var y: Int
    var horizontal: Bool

    var cells: [Int] {
        (0..<length).map { k in horizontal ? y * 10 + x + k : (y + k) * 10 + x }
    }

    var inBounds: Bool {
        guard x >= 0, y >= 0 else { return false }
        return horizontal ? (x + length <= 10 && y < 10) : (y + length <= 10 && x < 10)
    }

    var name: String {
        switch id {
        case 0: return L("Porte-avions")
        case 1: return L("Croiseur")
        case 2: return L("Contre-torpilleur")
        case 3: return L("Sous-marin")
        default: return L("Torpilleur")
        }
    }

    static let lengths = [5, 4, 3, 3, 2]
}

struct NavaleBoard {
    var ships: [NavaleShip]
    /// Cases visées sur cette grille : vrai si touché.
    var shots: [Int: Bool] = [:]

    func ship(at cell: Int) -> NavaleShip? {
        ships.first { $0.cells.contains(cell) }
    }

    func isSunk(_ ship: NavaleShip) -> Bool {
        ship.cells.allSatisfy { shots[$0] == true }
    }

    var afloat: Int { ships.filter { !isSunk($0) }.count }
    var allSunk: Bool { ships.allSatisfy { isSunk($0) } }

    func fits(_ ship: NavaleShip) -> Bool {
        guard ship.inBounds else { return false }
        let mine = Set(ship.cells)
        for other in ships where other.id != ship.id {
            if !mine.isDisjoint(with: other.cells) { return false }
        }
        return true
    }

    static func random() -> NavaleBoard {
        var board = NavaleBoard(ships: [])
        for (i, len) in NavaleShip.lengths.enumerated() {
            var placed = false
            var tries = 0
            while !placed && tries < 500 {
                tries += 1
                let h = Bool.random()
                let s = NavaleShip(id: i, length: len, x: Int.random(in: 0..<(h ? 11 - len : 10)),
                                   y: Int.random(in: 0..<(h ? 10 : 11 - len)), horizontal: h)
                if board.fits(s) {
                    board.ships.append(s)
                    placed = true
                }
            }
        }
        return board
    }
}

/// Une explosion ou une gerbe d'eau à dessiner, sur la grille du joueur `seat`.
struct NavaleBlast: Identifiable {
    let id = UUID()
    let seat: Int
    let cell: Int
    let hit: Bool
    let sunk: Bool
    let at: Double
}

@Observable
final class NavaleGame {
    enum Phase: Equatable { case menu, placing, handover, aiming, enemyTurn, over }

    var vsComputer = true
    var level = 2
    var salvo = true

    private(set) var phase: Phase = .menu
    /// Le joueur qui place ou qui tire.
    private(set) var current = 0
    private(set) var boards = [NavaleBoard.random(), NavaleBoard.random()]
    private(set) var shotsLeft = 1
    private(set) var blasts: [NavaleBlast] = []
    private(set) var banner: String?
    private(set) var bannerAt: Double = -10
    private(set) var time: Double = 0
    private(set) var winner = 0
    private(set) var shotsFired = [0, 0]
    /// La dernière flotte vient de couler : on laisse l'explosion se voir avant l'écran de fin.
    private(set) var finishing = false
    // Passage du Duo
    private(set) var handoverTo = 0
    /// 0 : il faut fermer le Duo. 1 : fermé, il faut l'ouvrir. 2 : pas de charnière, on touche un bouton.
    private(set) var handoverStage = 2
    private(set) var hasHinge = false
    @ObservationIgnored private var afterHandover: Phase = .aiming
    @ObservationIgnored private var generation = 0

    static func playerName(_ seat: Int) -> String { L("Joueur \(seat + 1)") }

    func name(_ seat: Int) -> String {
        if vsComputer { return seat == 0 ? L("Toi") : L("L'ordinateur") }
        return Self.playerName(seat)
    }

    // MARK: Partie

    func start() {
        generation += 1
        boards = [NavaleBoard.random(), NavaleBoard.random()]
        blasts = []
        banner = nil
        shotsFired = [0, 0]
        current = 0
        finishing = false
        phase = .placing
    }

    func backToMenu() {
        generation += 1
        phase = .menu
    }

    func tick(_ dt: Double) {
        guard phase != .menu else { return }
        time += dt
        if !blasts.isEmpty, let first = blasts.first, time - first.at > 2.5 {
            blasts.removeAll { time - $0.at > 2.5 }
        }
    }

    // MARK: Placement

    func shuffleFleet() {
        guard phase == .placing else { return }
        boards[current] = NavaleBoard.random()
        SoundPlayer.shared.play(.whoosh, volume: 0.5)
        Haptics.tap()
    }

    func move(_ id: Int, x: Int, y: Int) {
        guard phase == .placing, let i = boards[current].ships.firstIndex(where: { $0.id == id }) else { return }
        var s = boards[current].ships[i]
        s.x = x
        s.y = y
        if boards[current].fits(s) {
            boards[current].ships[i] = s
            SoundPlayer.shared.play(.clack, volume: 0.6)
            Haptics.tap()
        } else {
            Haptics.error()
        }
    }

    func rotate(_ id: Int) {
        guard phase == .placing, let i = boards[current].ships.firstIndex(where: { $0.id == id }) else { return }
        var s = boards[current].ships[i]
        s.horizontal.toggle()
        // S'il ne tient pas, on le décale un peu pour qu'il rentre.
        for shift in 0..<s.length {
            var t = s
            if t.horizontal { t.x -= shift } else { t.y -= shift }
            if boards[current].fits(t) {
                boards[current].ships[i] = t
                SoundPlayer.shared.play(.clack, volume: 0.6)
                Haptics.tap()
                return
            }
        }
        Haptics.error()
    }

    func fleetReady() {
        guard phase == .placing else { return }
        SoundPlayer.shared.play(.go, volume: 0.7)
        if vsComputer {
            boards[1] = NavaleBoard.random()
            beginAiming(0)
        } else if current == 0 {
            beginHandover(to: 1, then: .placing)
        } else {
            beginHandover(to: 0, then: .aiming)
        }
    }

    // MARK: Passer le Duo

    private func beginHandover(to seat: Int, then next: Phase) {
        handoverTo = seat
        afterHandover = next
        handoverStage = hasHinge ? 0 : 2
        phase = .handover
    }

    func hinge(_ degrees: Double) {
        if !hasHinge {
            hasHinge = true
            if phase == .handover && handoverStage == 2 { handoverStage = 0 }
        }
        guard phase == .handover else { return }
        if handoverStage == 0 && degrees < 20 {
            handoverStage = 1
            SoundPlayer.shared.play(.thud, volume: 0.6)
        } else if handoverStage == 1 && degrees > 50 {
            finishHandover()
        }
    }

    /// Bouton « C'est moi » (sans charnière, ou si on préfère ne pas fermer).
    func finishHandover() {
        guard phase == .handover else { return }
        current = handoverTo
        if afterHandover == .aiming {
            beginAiming(current)
        } else {
            phase = .placing
        }
    }

    // MARK: Tirer

    private func beginAiming(_ seat: Int) {
        current = seat
        shotsLeft = salvo ? boards[seat].afloat : 1
        banner = nil
        phase = .aiming
        SoundPlayer.shared.play(.sonar, volume: 0.6)
    }

    /// Le joueur `current` tire sur la grille de l'autre.
    func fire(_ cell: Int) {
        guard phase == .aiming, shotsLeft > 0 else { return }
        let target = 1 - current
        guard boards[target].shots[cell] == nil else {
            Haptics.error()
            return
        }
        shotsLeft -= 1
        shotsFired[current] += 1
        shoot(target, cell)
        if boards[target].allSunk {
            win(current)
        } else if shotsLeft == 0 {
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                guard let self, self.generation == gen, self.phase == .aiming else { return }
                self.endTurn()
            }
        }
    }

    private func shoot(_ target: Int, _ cell: Int) {
        let ship = boards[target].ship(at: cell)
        boards[target].shots[cell] = ship != nil
        var sunk = false
        if let ship, boards[target].isSunk(ship) {
            sunk = true
            banner = L("Coulé ! \(ship.name)")
            bannerAt = time
        }
        blasts.append(NavaleBlast(seat: target, cell: cell, hit: ship != nil, sunk: sunk, at: time))
        if sunk {
            SoundPlayer.shared.play(.boom, volume: 1)
            Haptics.chomp()
        } else if ship != nil {
            SoundPlayer.shared.play(.boom, volume: 0.55)
            Haptics.correct(subtle: false)
        } else {
            SoundPlayer.shared.play(.splash, volume: 0.8)
            Haptics.tap()
        }
    }

    private func endTurn() {
        if vsComputer {
            computerTurn()
        } else {
            beginHandover(to: 1 - current, then: .aiming)
        }
    }

    private func win(_ seat: Int) {
        winner = seat
        finishing = true
        // Les tirs encore programmés (salve de l'ordinateur) sont annulés.
        generation += 1
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.phase = .over
            SoundPlayer.shared.play(seat == 0 || !self.vsComputer ? .win : .wrong, volume: 0.9)
        }
        phase = .enemyTurn
    }

    // MARK: L'ordinateur

    private func computerTurn() {
        phase = .enemyTurn
        current = 1
        banner = nil
        let shots = salvo ? boards[1].afloat : 1
        let gen = generation
        for k in 0..<shots {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 + Double(k) * 0.75) { [weak self] in
                guard let self, self.generation == gen, self.phase == .enemyTurn, self.current == 1 else { return }
                let cell = NavaleAI.choose(self.boards[0], level: self.level)
                self.shotsFired[1] += 1
                self.shoot(0, cell)
                if self.boards[0].allSunk {
                    self.win(1)
                } else if k == shots - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self, self.generation == gen, self.phase == .enemyTurn else { return }
                        self.beginAiming(0)
                    }
                }
            }
        }
    }

    var accuracy: [Int] {
        (0..<2).map { seat in
            let target = boards[1 - seat]
            let hits = target.shots.values.filter { $0 }.count
            return shotsFired[seat] > 0 ? Int((Double(hits) / Double(shotsFired[seat]) * 100).rounded()) : 0
        }
    }
}

// MARK: - L'amiral de l'ordinateur

enum NavaleAI {
    /// Facile : au hasard. Moyen : chasse puis vise autour des touches. Difficile : carte des probabilités.
    static func choose(_ board: NavaleBoard, level: Int) -> Int {
        let free = (0..<100).filter { board.shots[$0] == nil }
        guard !free.isEmpty else { return 0 }
        if level <= 1 {
            // Même facile, il finit un bateau touché une fois sur deux.
            if Bool.random(), let c = target(board) { return c }
            return free.randomElement() ?? free[0]
        }
        if level == 2 {
            if let c = target(board) { return c }
            let smallest = remaining(board).min() ?? 2
            let parity = free.filter { ($0 / 10 + $0 % 10) % smallest == 0 }
            return (parity.isEmpty ? free : parity).randomElement() ?? free[0]
        }
        return density(board) ?? free.randomElement() ?? free[0]
    }

    /// Les touches qui n'appartiennent pas encore à un bateau coulé.
    private static func openHits(_ board: NavaleBoard) -> [Int] {
        let sunkCells = Set(board.ships.filter { board.isSunk($0) }.flatMap { $0.cells })
        return board.shots.filter { $0.value && !sunkCells.contains($0.key) }.map { $0.key }.sorted()
    }

    private static func remaining(_ board: NavaleBoard) -> [Int] {
        board.ships.filter { !board.isSunk($0) }.map { $0.length }
    }

    private static func neighbors(_ c: Int) -> [Int] {
        var n: [Int] = []
        let x = c % 10, y = c / 10
        if x > 0 { n.append(c - 1) }
        if x < 9 { n.append(c + 1) }
        if y > 0 { n.append(c - 10) }
        if y < 9 { n.append(c + 10) }
        return n
    }

    private static func target(_ board: NavaleBoard) -> Int? {
        let hits = openHits(board)
        guard !hits.isEmpty else { return nil }
        let hitSet = Set(hits)
        // Deux touches alignées : on continue dans la même ligne.
        for h in hits {
            for d in [1, 10] {
                guard hitSet.contains(h + d), (d == 10 || h / 10 == (h + d) / 10) else { continue }
                var a = h
                while hitSet.contains(a - d) && (d == 10 || (a - d) / 10 == a / 10) && a - d >= 0 { a -= d }
                var b = h
                while hitSet.contains(b + d) && (d == 10 || (b + d) / 10 == b / 10) && b + d < 100 { b += d }
                var ends: [Int] = []
                if a - d >= 0 && (d == 10 || (a - d) / 10 == a / 10) { ends.append(a - d) }
                if b + d < 100 && (d == 10 || (b + d) / 10 == b / 10) { ends.append(b + d) }
                if let c = ends.filter({ board.shots[$0] == nil }).randomElement() { return c }
            }
        }
        let around = hits.flatMap { neighbors($0) }.filter { board.shots[$0] == nil }
        return around.randomElement()
    }

    private static func density(_ board: NavaleBoard) -> Int? {
        var score = [Int](repeating: 0, count: 100)
        let misses = Set(board.shots.filter { !$0.value }.map { $0.key })
        let sunkCells = Set(board.ships.filter { board.isSunk($0) }.flatMap { $0.cells })
        let hits = Set(openHits(board))
        for len in remaining(board) {
            for h in [true, false] {
                for y in 0..<10 {
                    for x in 0..<10 {
                        let s = NavaleShip(id: 99, length: len, x: x, y: y, horizontal: h)
                        guard s.inBounds else { continue }
                        let cells = s.cells
                        if cells.contains(where: { misses.contains($0) || sunkCells.contains($0) }) { continue }
                        let covered = cells.filter { hits.contains($0) }.count
                        let weight = 1 + covered * 30
                        for c in cells where board.shots[c] == nil { score[c] += weight }
                    }
                }
            }
        }
        let best = score.max() ?? 0
        guard best > 0 else { return nil }
        return (0..<100).filter { score[$0] == best && board.shots[$0] == nil }.randomElement()
    }
}
