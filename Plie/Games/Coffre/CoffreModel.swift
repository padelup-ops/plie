import Foundation
import Observation

// MARK: - Niveaux

struct CoffreLevel {
    let number: Int
    let digits: Int
    let positions: Int
    let decoysPerDigit: Int
    let subtle: Bool
    let hideNumbers: Bool

    static let count = 30

    static func make(_ number: Int) -> CoffreLevel {
        let n = max(1, min(count, number))
        let digits = n <= 8 ? 3 : (n <= 25 ? 4 : 5)
        let positions: Int
        switch n {
        case 1...4: positions = 16
        case 5...12: positions = 20
        case 13...22: positions = 24
        default: positions = 30
        }
        let decoys = n < 7 ? 0 : (n < 15 ? 1 : (n < 24 ? 2 : 3))
        return CoffreLevel(number: n,
                           digits: digits,
                           positions: positions,
                           decoysPerDigit: decoys,
                           subtle: n >= 19,
                           hideNumbers: n >= 22 && n % 2 == 0)
    }

    /// Temps de référence pour les 3 étoiles.
    var par: Double {
        Double(digits) * (5 + Double(positions) / 4) + Double(decoysPerDigit * digits) * 1.5
    }

    var features: [String] {
        var list = ["\(digits) chiffres", "\(positions) crans"]
        if decoysPerDigit > 0 { list.append(decoysPerDigit == 1 ? "1 faux cran" : "\(decoysPerDigit) faux crans") }
        if subtle { list.append("cran discret") }
        if hideNumbers { list.append("sans chiffres") }
        return list
    }

    func stars(time: Double, mistakes: Int) -> Int {
        if mistakes == 0 && time <= par { return 3 }
        if mistakes <= 2 && time <= par * 1.7 { return 2 }
        return 1
    }
}

// MARK: - Partie

enum CoffreEvent: Equatable {
    case none
    case wrong
    case locked
}

@Observable
final class CoffreSession {
    let level: CoffreLevel
    let combination: [Int]
    let decoys: [[Int]]

    /// Position continue du cadran, de 0 à positions - 1.
    var value: Double = 0
    private(set) var notch: Int = 0
    private(set) var index = 0
    private(set) var found: [Int] = []
    private(set) var holdProgress: Double = 0
    private(set) var mistakes = 0
    private(set) var elapsed: Double = 0
    private(set) var opened = false
    private(set) var event: CoffreEvent = .none
    private(set) var eventCount = 0

    /// Vrai tant qu'on n'a pas bougé d'un cran : la position de départ n'est jamais testée.
    @ObservationIgnored private var evaluated = true
    @ObservationIgnored private var started = false
    static let holdDuration = 0.9

    init(level: CoffreLevel, combination: [Int]? = nil) {
        self.level = level
        var generator = SystemRandomNumberGenerator()
        let combo: [Int]
        if let combination {
            combo = combination
        } else {
            combo = Self.randomCombination(level: level, using: &generator)
        }
        var decoyList: [[Int]] = []
        for digit in combo {
            decoyList.append(Self.randomDecoys(around: digit, level: level, using: &generator))
        }
        self.combination = combo
        self.decoys = decoyList
    }

    var maxValue: Double { Double(level.positions - 1) }

    // MARK: Entrées

    /// Position venant de la charnière (0 = presque fermé, 1 = à plat).
    func setFraction(_ fraction: Double) {
        setValue(fraction * maxValue)
    }

    func nudge(by notches: Double) {
        setValue(value + notches)
    }

    func setValue(_ newValue: Double) {
        guard !opened else { return }
        value = min(maxValue, max(0, newValue))
        // Première lecture (position de départ de la charnière) : on se cale sans rien déclencher.
        if !started {
            started = true
            notch = Int(value.rounded())
            return
        }
        // Hystérésis : on ne change de cran que franchement, pour éviter les faux clics.
        if abs(value - Double(notch)) > 0.68 {
            let next = Int(value.rounded())
            if next != notch {
                notch = next
                enterNotch(next)
            }
        }
    }

    // MARK: Temps

    func tick(dt: Double) {
        guard !opened, started else { return }
        elapsed += dt
        guard !evaluated else { return }
        holdProgress += dt / Self.holdDuration
        if holdProgress >= 1 {
            holdProgress = 1
            evaluate()
        }
    }

    // MARK: Règles

    private func enterNotch(_ position: Int) {
        evaluated = false
        holdProgress = 0
        guard index < combination.count else { return }

        if position == combination[index] {
            Haptics.correct(subtle: level.subtle)
            SoundPlayer.shared.play(.clunk, volume: level.subtle ? 0.45 : 0.9)
        } else if decoys[index].contains(position) {
            Haptics.decoy(strength: level.subtle ? 0.9 : 0.75)
            SoundPlayer.shared.play(.decoy, volume: level.subtle ? 0.5 : 0.75)
        } else {
            Haptics.notch()
            SoundPlayer.shared.play(.notch, volume: 0.35)
        }
    }

    private func evaluate() {
        evaluated = true
        guard index < combination.count else { return }

        if notch == combination[index] {
            found.append(notch)
            index += 1
            event = .locked
            eventCount += 1
            if index == combination.count {
                opened = true
                Haptics.success()
                SoundPlayer.shared.play(.vault)
            } else {
                Haptics.correct(subtle: false)
                SoundPlayer.shared.play(.lock)
            }
        } else {
            mistakes += 1
            event = .wrong
            eventCount += 1
            Haptics.error()
            SoundPlayer.shared.play(.wrong, volume: 0.8)
        }
    }

    // MARK: Tirage

    private static func randomCombination<G: RandomNumberGenerator>(level: CoffreLevel, using generator: inout G) -> [Int] {
        var result: [Int] = []
        let minGap = max(3, level.positions / 4)
        while result.count < level.digits {
            let candidate = Int.random(in: 1...(level.positions - 2), using: &generator)
            if let last = result.last, abs(candidate - last) < minGap { continue }
            result.append(candidate)
        }
        return result
    }

    private static func randomDecoys<G: RandomNumberGenerator>(around correct: Int, level: CoffreLevel, using generator: inout G) -> [Int] {
        var result: [Int] = []
        var attempts = 0
        while result.count < level.decoysPerDigit && attempts < 200 {
            attempts += 1
            let candidate = Int.random(in: 0...(level.positions - 1), using: &generator)
            if abs(candidate - correct) < 2 { continue }
            if result.contains(where: { abs($0 - candidate) < 2 }) { continue }
            result.append(candidate)
        }
        return result
    }
}
