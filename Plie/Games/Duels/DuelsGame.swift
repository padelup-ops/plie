import SwiftUI

extension Theme {
    static let duels = Color(hex: 0xFFB020)
    static let duelsA = Color(hex: 0x3DA5FF)
    static let duelsB = Color(hex: 0xFF7A3D)
}

// MARK: - DUELS
//
// Duo ouvert à plat entre deux joueurs, chacun sa moitié. Des mini-duels express tirés au hasard :
// dégainer au signal, tir à la corde, calcul éclair… Chaque manche gagnée rapporte un point.

struct DuelWord {
    let text: String
    let ink: Int
    let target: Bool
}

struct DuelMole {
    let id: Int
    let hole: Int
    let bomb: Bool
    let at: Double
    let until: Double
}

struct DuelDot {
    let x: Double
    let y: Double
    let kind: Int
}

@Observable
final class DuelsGame {
    enum Phase: Equatable { case menu, intro, playing, result, over }

    enum Kind: Int, CaseIterable, Identifiable {
        case draw, tug, math, stroop, twins, blind, moles, arrows, simon, count

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .draw: return L("DÉGAINE")
            case .tug: return L("TIR À LA CORDE")
            case .math: return L("CALCUL ÉCLAIR")
            case .stroop: return L("COULEUR PIÈGE")
            case .twins: return L("JUMEAUX")
            case .blind: return L("CHRONO À L'AVEUGLE")
            case .moles: return L("TAUPES")
            case .arrows: return L("FLÈCHES")
            case .simon: return L("MÉMOIRE")
            case .count: return L("LE BON COMPTE")
            }
        }

        var rule: String {
            switch self {
            case .draw: return L("Attends « FEU ! », puis touche ta moitié le premier. Trop tôt : perdu !")
            case .tug: return L("Tapote ta moitié le plus vite possible pour tirer la corde de ton côté.")
            case .math: return L("Touche le bon résultat avant l'autre. Une erreur : bloqué une seconde.")
            case .stroop: return L("Touche quand le mot est écrit dans SA couleur. Pas avant !")
            case .twins: return L("Touche dès que le même dessin apparaît deux fois de suite.")
            case .blind: return L("Arrête ton chrono pile au bon moment… il disparaît vite !")
            case .moles: return L("Tape 6 taupes avant l'autre. Pas les bombes !")
            case .arrows: return L("Glisse dans le sens des flèches, dans l'ordre. Une erreur : on recommence.")
            case .simon: return L("Retiens l'ordre des couleurs, puis rejoue-le le premier.")
            case .count: return L("Il y en a plus de quel côté ? Touche la bonne réponse, vite !")
            }
        }

        var symbol: String {
            switch self {
            case .draw: return "scope"
            case .tug: return "arrow.up.and.down"
            case .math: return "plus.forwardslash.minus"
            case .stroop: return "paintpalette.fill"
            case .twins: return "square.on.square"
            case .blind: return "stopwatch.fill"
            case .moles: return "hammer.fill"
            case .arrows: return "arrow.up.circle.fill"
            case .simon: return "brain.head.profile"
            case .count: return "number"
            }
        }
    }

    static let introLength = 2.8
    static let resultLength = 1.9
    static let inks: [UInt32] = [0xFF4D5E, 0x4D8BFF, 0x3DDB7A, 0xFFD23D, 0xFF6FD8]
    static let emojis = ["🍎", "🐸", "⭐️", "🎈", "🚗", "🍩", "🐱", "⚽️", "🌵", "🎸", "🦄", "🍕"]

    var target = 5
    private(set) var phase: Phase = .menu
    private(set) var kind: Kind = .draw
    private(set) var score = [0, 0]
    private(set) var round = 0
    /// Temps depuis le début de la phase en cours.
    private(set) var t: Double = 0
    private(set) var winner: Int?
    private(set) var note = ""
    private(set) var matchWinner = 0
    private(set) var paused = false

    // Dégaine
    private(set) var fireAt: Double = 3
    private(set) var reaction: Double = 0
    // Tir à la corde : positif vers le joueur du haut
    private(set) var rope: Double = 0
    private(set) var pulls = [0, 0]
    // Calcul éclair et bon compte
    private(set) var question = ""
    private(set) var choices: [String] = []
    private(set) var answer = 0
    private(set) var lockedUntil = [0.0, 0.0]
    private(set) var wrongPick: [Int?] = [nil, nil]
    // Couleur piège et jumeaux
    private(set) var words: [DuelWord] = []
    private(set) var slot: Double = 0.8
    // Chrono à l'aveugle
    private(set) var blindTarget: Double = 5
    private(set) var stopped: [Double?] = [nil, nil]
    // Taupes
    private(set) var moles: [DuelMole] = []
    private(set) var whacked: [Set<Int>] = [[], []]
    private(set) var hits = [0, 0]
    private(set) var boomAt: [Double?] = [nil, nil]
    // Flèches
    private(set) var arrows: [SwipeDirection] = []
    private(set) var arrowStep = [0, 0]
    private(set) var arrowMiss: [Double?] = [nil, nil]
    // Mémoire
    private(set) var simon: [Int] = []
    private(set) var simonStep = [0, 0]
    private(set) var simonOut = [false, false]
    private(set) var pressed: [(pad: Int, at: Double)?] = [nil, nil]
    // Le bon compte
    private(set) var dots: [DuelDot] = []
    private(set) var countPair = ["🐟", "🐙"]

    @ObservationIgnored private var deck: [Kind] = []
    @ObservationIgnored private var lastTickSecond = -1

    static func color(_ seat: Int) -> Color { seat == 0 ? Theme.duelsA : Theme.duelsB }

    static func name(_ seat: Int) -> String { seat == 0 ? L("Bleu") : L("Orange") }

    // MARK: Partie

    func start() {
        score = [0, 0]
        round = 0
        deck = []
        paused = false
        nextRound()
    }

    func backToMenu() {
        phase = .menu
        paused = false
    }

    func togglePause() {
        guard phase != .menu && phase != .over else { return }
        paused.toggle()
    }

    private func nextRound() {
        if deck.isEmpty {
            deck = Kind.allCases.shuffled()
            // Pas deux fois de suite le même jeu, même en changeant de paquet.
            if deck.first == kind && round > 0 { deck.swapAt(0, deck.count - 1) }
        }
        kind = deck.removeFirst()
        round += 1
        winner = nil
        note = ""
        t = 0
        phase = .intro
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
    }

    private func setUp() {
        lockedUntil = [0, 0]
        wrongPick = [nil, nil]
        switch kind {
        case .draw:
            fireAt = Double.random(in: 1.6...4.4)
            reaction = 0
        case .tug:
            rope = 0
            pulls = [0, 0]
        case .math:
            makeMath()
        case .stroop:
            slot = 0.85
            words = Self.makeStroop()
        case .twins:
            slot = 0.75
            words = Self.makeTwins()
        case .blind:
            blindTarget = Double(Int.random(in: 3...6))
            stopped = [nil, nil]
        case .moles:
            moles = Self.makeMoles()
            whacked = [[], []]
            hits = [0, 0]
            boomAt = [nil, nil]
        case .arrows:
            arrows = (0..<5).map { _ in SwipeDirection.allCases.randomElement() ?? .up }
            arrowStep = [0, 0]
            arrowMiss = [nil, nil]
        case .simon:
            var s: [Int] = []
            while s.count < 5 {
                let p = Int.random(in: 0..<4)
                if p != s.last { s.append(p) }
            }
            simon = s
            simonStep = [0, 0]
            simonOut = [false, false]
            pressed = [nil, nil]
        case .count:
            makeCount()
        }
    }

    // MARK: Horloge

    func tick(_ dt: Double) {
        guard phase != .menu && phase != .over, !paused else { return }
        t += dt
        switch phase {
        case .intro:
            if t >= Self.introLength {
                setUp()
                t = 0
                lastTickSecond = -1
                phase = .playing
                if kind != .draw { SoundPlayer.shared.play(.go, volume: 0.7) }
            }
        case .playing:
            update()
        case .result:
            if t >= Self.resultLength {
                if score.max() ?? 0 >= target {
                    matchWinner = score[0] >= target ? 0 : 1
                    phase = .over
                    SoundPlayer.shared.play(.applause, volume: 0.8)
                    Haptics.success()
                } else {
                    nextRound()
                }
            }
        default:
            break
        }
    }

    private func update() {
        switch kind {
        case .draw:
            if reaction == 0 && t >= fireAt {
                reaction = -1   // « FEU ! » affiché, on attend le premier
                SoundPlayer.shared.play(.bang, volume: 0.9)
                Haptics.correct(subtle: false)
            }
            if t > fireAt + 3 { finish(nil, L("Personne n'a tiré !")) }
        case .tug:
            if t > 12 {
                if abs(rope) < 0.04 { finish(nil, L("Match nul !")) } else { finish(rope > 0 ? 1 : 0, L("Plus de force de ce côté !")) }
            }
        case .math, .count:
            if t > 11 { finish(nil, L("Trop lent, tous les deux !")) }
        case .stroop, .twins:
            let i = Int(t / slot)
            if i != lastTickSecond {
                lastTickSecond = i
                if i < words.count { SoundPlayer.shared.play(.notch, volume: 0.35) }
            }
            if i >= words.count { finish(nil, L("Personne n'a touché…")) }
        case .blind:
            if t > blindTarget + 4 { resolveBlind() }
        case .moles:
            if t > 16 {
                if hits[0] == hits[1] { finish(nil, L("Égalité !")) } else { finish(hits[0] > hits[1] ? 0 : 1, L("Plus de taupes !")) }
            }
        case .arrows:
            if t > 14 { finish(nil, L("Temps écoulé !")) }
        case .simon:
            let k = simonFlash ?? -1
            if k != lastTickSecond {
                lastTickSecond = k
                if k >= 0 { SoundPlayer.shared.play(Self.padSound(simon[k]), volume: 0.7) }
            }
            if t > simonShowEnd + 9 { finish(nil, L("Temps écoulé !")) }
        }
    }

    private func finish(_ seat: Int?, _ why: String) {
        guard phase == .playing else { return }
        winner = seat
        note = why
        if let seat {
            score[seat] += 1
            SoundPlayer.shared.play(.point, volume: 0.8)
            Haptics.success()
        } else {
            SoundPlayer.shared.play(.wrong, volume: 0.5)
        }
        t = 0
        phase = .result
    }

    // MARK: Toucher sa moitié (dégaine, corde, couleur piège, jumeaux, chrono)

    func tap(_ seat: Int) {
        guard phase == .playing, !paused else { return }
        switch kind {
        case .draw:
            if t < fireAt {
                finish(1 - seat, L("\(Self.name(seat)) a tiré trop tôt !"))
            } else {
                reaction = t - fireAt
                finish(seat, L("Dégainé en \(Self.secs(reaction)) s"))
            }
        case .tug:
            pulls[seat] += 1
            rope += seat == 1 ? 0.052 : -0.052
            if pulls[seat] % 3 == 0 { SoundPlayer.shared.play(.pok, volume: 0.35) }
            if rope >= 1 { finish(1, L("Corde tirée !")) } else if rope <= -1 { finish(0, L("Corde tirée !")) }
        case .stroop, .twins:
            let i = Int(t / slot)
            let late = t - Double(i) * slot
            let hit = (i < words.count && words[i].target) || (i > 0 && i - 1 < words.count && words[i - 1].target && late < 0.18)
            if hit {
                finish(seat, kind == .stroop ? L("Bien vu !") : L("Repéré !"))
            } else {
                finish(1 - seat, L("\(Self.name(seat)) a touché trop tôt !"))
            }
        case .blind:
            guard stopped[seat] == nil else { return }
            stopped[seat] = t
            SoundPlayer.shared.play(.clack, volume: 0.7)
            Haptics.tap()
            if stopped[0] != nil && stopped[1] != nil { resolveBlind() }
        default:
            break
        }
    }

    // MARK: Calcul éclair et bon compte

    func pick(_ seat: Int, _ index: Int) {
        guard phase == .playing, !paused, kind == .math || kind == .count else { return }
        if kind == .count && t < 0.3 { return }
        guard t >= lockedUntil[seat] else { return }
        if index == answer {
            finish(seat, kind == .math ? L("\(question) = \(choices[answer])") : L("Il y avait plus de \(choices[answer])"))
        } else {
            wrongPick[seat] = index
            lockedUntil[seat] = t + 1.2
            SoundPlayer.shared.play(.wrong, volume: 0.6)
            Haptics.error()
        }
    }

    private func makeMath() {
        let op = Int.random(in: 0..<3)
        var a = 0, b = 0, r = 0
        switch op {
        case 0:
            a = Int.random(in: 12...59); b = Int.random(in: 6...38); r = a + b
            question = "\(a) + \(b)"
        case 1:
            a = Int.random(in: 30...95); b = Int.random(in: 4...28); r = a - b
            question = "\(a) − \(b)"
        default:
            a = Int.random(in: 3...9); b = Int.random(in: 3...9); r = a * b
            question = "\(a) × \(b)"
        }
        var options: Set<Int> = [r]
        let spread = op == 2 ? [a, b, -a, -b, 1, -1] : [10, -10, 1, -1, 2, -2]
        while options.count < 3 {
            let o = r + (spread.randomElement() ?? 1)
            if o > 0 { options.insert(o) }
        }
        let list = Array(options).shuffled()
        choices = list.map { "\($0)" }
        answer = list.firstIndex(of: r) ?? 0
    }

    private func makeCount() {
        let pairs = [("🐟", "🐙"), ("🍎", "🍐"), ("🐞", "🐝"), ("⭐️", "🌙"), ("🍓", "🫐")]
        let p = pairs.randomElement() ?? ("🐟", "🐙")
        countPair = [p.0, p.1]
        let small = Int.random(in: 9...14)
        let big = small + Int.random(in: 1...3)
        let firstBig = Bool.random()
        let n0 = firstBig ? big : small
        let n1 = firstBig ? small : big
        var placed: [DuelDot] = []
        var tries = 0
        let kinds = Array(repeating: 0, count: n0) + Array(repeating: 1, count: n1)
        for k in kinds.shuffled() {
            var ok = false
            while !ok && tries < 4000 {
                tries += 1
                let x = Double.random(in: 0.06...0.94), y = Double.random(in: 0.08...0.92)
                ok = placed.allSatisfy { hypot($0.x - x, ($0.y - y) * 0.6) > 0.075 }
                if ok { placed.append(DuelDot(x: x, y: y, kind: k)) }
            }
        }
        dots = placed
        let c0 = placed.filter { $0.kind == 0 }.count
        let c1 = placed.count - c0
        choices = countPair
        answer = c0 > c1 ? 0 : 1
        if c0 == c1 {
            // Rare : le placement a raté une forme. On en ajoute une.
            dots.append(DuelDot(x: 0.5, y: 0.5, kind: 0))
            answer = 0
        }
    }

    /// Les formes ne restent visibles que quelques secondes.
    var dotsVisible: Bool { t < 3.2 }

    // MARK: Couleur piège et jumeaux

    static func makeStroop() -> [DuelWord] {
        let names = [L("ROUGE"), L("BLEU"), L("VERT"), L("JAUNE"), L("ROSE")]
        let hit = Int.random(in: 3...8)
        var list: [DuelWord] = []
        for i in 0..<16 {
            let w = Int.random(in: 0..<names.count)
            if i == hit || i == hit + Int.random(in: 4...6) {
                list.append(DuelWord(text: names[w], ink: w, target: true))
            } else {
                var ink = Int.random(in: 0..<names.count)
                while ink == w { ink = Int.random(in: 0..<names.count) }
                list.append(DuelWord(text: names[w], ink: ink, target: false))
            }
        }
        return list
    }

    static func makeTwins() -> [DuelWord] {
        let hit = Int.random(in: 3...8)
        let second = hit + Int.random(in: 4...6)
        var list: [DuelWord] = []
        for i in 0..<16 {
            if (i == hit || i == second), let prev = list.last {
                list.append(DuelWord(text: prev.text, ink: 0, target: true))
            } else {
                var e = emojis.randomElement() ?? "⭐️"
                // Jamais deux pareils par hasard, ni un faux « presque » juste avant une vraie paire.
                while e == list.last?.text { e = emojis.randomElement() ?? "⭐️" }
                list.append(DuelWord(text: e, ink: 0, target: false))
            }
        }
        return list
    }

    var currentWord: DuelWord? {
        let i = Int(t / slot)
        return i >= 0 && i < words.count ? words[i] : nil
    }

    // MARK: Chrono à l'aveugle

    /// Le chrono s'affiche une seconde et demie, puis se cache.
    var blindShown: Bool { t < 1.5 }

    private func resolveBlind() {
        guard phase == .playing else { return }
        let d0 = stopped[0].map { abs($0 - blindTarget) } ?? 99
        let d1 = stopped[1].map { abs($0 - blindTarget) } ?? 99
        let text = L("\(Self.name(0)) : \(Self.format(stopped[0])) · \(Self.name(1)) : \(Self.format(stopped[1]))")
        if abs(d0 - d1) < 0.005 {
            finish(nil, text)
        } else {
            finish(d0 < d1 ? 0 : 1, text)
        }
    }

    static func format(_ v: Double?) -> String {
        guard let v else { return "—" }
        return secs(v) + " s"
    }

    /// Deux décimales, avec la virgule en français.
    static func secs(_ v: Double) -> String {
        let s = String(format: "%.2f", v)
        return Lang.shared.isEnglish ? s : s.replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Taupes

    static func makeMoles() -> [DuelMole] {
        var list: [DuelMole] = []
        var at = 0.5
        var id = 0
        while at < 15.5 {
            let busy = Set(list.filter { $0.until > at }.map { $0.hole })
            var hole = Int.random(in: 0..<9)
            while busy.contains(hole) { hole = Int.random(in: 0..<9) }
            let bomb = id > 1 && Double.random(in: 0...1) < 0.22
            list.append(DuelMole(id: id, hole: hole, bomb: bomb, at: at, until: at + (bomb ? 1.1 : 0.9)))
            id += 1
            at += Double.random(in: 0.38...0.7)
        }
        return list
    }

    func mole(at hole: Int, for seat: Int) -> DuelMole? {
        moles.first { $0.hole == hole && $0.at <= t && t < $0.until && !whacked[seat].contains($0.id) }
    }

    func whack(_ seat: Int, hole: Int) {
        guard phase == .playing, !paused, kind == .moles, let m = mole(at: hole, for: seat) else { return }
        whacked[seat].insert(m.id)
        if m.bomb {
            hits[seat] = max(0, hits[seat] - 1)
            boomAt[seat] = t
            SoundPlayer.shared.play(.boom, volume: 0.45)
            Haptics.error()
        } else {
            hits[seat] += 1
            SoundPlayer.shared.play(.pok, volume: 0.8)
            Haptics.tap()
            if hits[seat] >= 6 { finish(seat, L("6 taupes !")) }
        }
    }

    // MARK: Flèches

    /// `d` : la direction vue par le joueur (dans sa moitié).
    func swipe(_ seat: Int, _ d: SwipeDirection) {
        guard phase == .playing, !paused, kind == .arrows else { return }
        if d == arrows[arrowStep[seat]] {
            arrowStep[seat] += 1
            SoundPlayer.shared.play(.notch, volume: 0.8)
            Haptics.tap()
            if arrowStep[seat] >= arrows.count { finish(seat, L("5 flèches sans faute !")) }
        } else {
            arrowStep[seat] = 0
            arrowMiss[seat] = t
            SoundPlayer.shared.play(.wrong, volume: 0.5)
            Haptics.error()
        }
    }

    // MARK: Mémoire

    var simonShowEnd: Double { 0.5 + Double(simon.count) * 0.62 }

    /// L'étape de la séquence montrée en ce moment (nil entre deux éclairs, ou après).
    var simonFlash: Int? {
        guard kind == .simon, phase == .playing, t >= 0.5, t < simonShowEnd else { return nil }
        let k = Int((t - 0.5) / 0.62)
        let into = t - 0.5 - Double(k) * 0.62
        return into < 0.42 && k < simon.count ? k : nil
    }

    var simonInput: Bool { t >= simonShowEnd }

    static let padSounds: [SoundPlayer.Effect] = [.simon0, .simon1, .simon2, .simon3]

    static func padSound(_ pad: Int) -> SoundPlayer.Effect {
        padSounds[pad % padSounds.count]
    }

    func press(_ seat: Int, pad: Int) {
        guard phase == .playing, !paused, kind == .simon, simonInput, !simonOut[seat] else { return }
        pressed[seat] = (pad, t)
        SoundPlayer.shared.play(Self.padSound(pad), volume: 0.7)
        if simon[simonStep[seat]] == pad {
            simonStep[seat] += 1
            if simonStep[seat] >= simon.count { finish(seat, L("Mémoire parfaite !")) }
        } else {
            simonOut[seat] = true
            Haptics.error()
            if simonOut[0] && simonOut[1] { finish(nil, L("Personne ne s'en souvenait !")) }
        }
    }
}
