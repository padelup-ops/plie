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
        // Avec le Pass
        case rps, nerve, order, odd, circle, balloon, target, grid

        /// Les 8 duels du Pass.
        var needsPass: Bool { rawValue >= Kind.rps.rawValue }

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
            case .rps: return L("PIERRE-FEUILLE-CISEAUX")
            case .nerve: return L("NERFS D'ACIER")
            case .order: return L("1 À 9")
            case .odd: return L("L'INTRUS")
            case .circle: return L("CERCLE PARFAIT")
            case .balloon: return L("BALLON")
            case .target: return L("PILE AU CENTRE")
            case .grid: return L("MÉMO-GRILLE")
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
            case .rps: return L("Choisis en secret. La feuille couvre la pierre, la pierre casse les ciseaux, les ciseaux coupent la feuille.")
            case .nerve: return L("Gardez chacun un doigt posé. La bombe va sauter… Le dernier à lâcher gagne, mais pas après le BOUM !")
            case .order: return L("Touche les nombres de 1 à 9, dans l'ordre, plus vite que l'autre.")
            case .odd: return L("Un seul dessin n'est pas comme les autres. Trouve-le le premier !")
            case .circle: return L("Dessine un cercle d'un seul trait. Le plus parfait gagne.")
            case .balloon: return L("Gonfle ton ballon puis touche « Stop ». Le plus gros gagne… s'il n'a pas éclaté !")
            case .target: return L("L'aiguille va et vient. Arrête-la le plus près possible du centre.")
            case .grid: return L("Retiens les cases allumées, puis touche-les toutes. Une erreur : éliminé.")
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
            case .rps: return "hand.raised.fill"
            case .nerve: return "flame.fill"
            case .order: return "list.number"
            case .odd: return "eye.fill"
            case .circle: return "circle.dashed"
            case .balloon: return "balloon.fill"
            case .target: return "target"
            case .grid: return "square.grid.3x3.fill"
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
    // Pierre-feuille-ciseaux : 0 pierre, 1 feuille, 2 ciseaux
    private(set) var rpsPick: [Int?] = [nil, nil]
    private(set) var rpsRevealAt: Double?
    private(set) var rpsTieAt: Double?
    private(set) var rpsTies = 0
    private(set) var rpsDeadline: Double = 8
    // Nerfs d'acier
    private(set) var holding = [false, false]
    private(set) var fuseStart: Double?
    private(set) var releasedAfter: [Double?] = [nil, nil]
    @ObservationIgnored private var explodeAfter: Double = 5
    // 1 à 9
    private(set) var orderLayout: [Int] = []
    private(set) var orderNext = [1, 1]
    private(set) var orderMiss: [Double?] = [nil, nil]
    // L'intrus
    private(set) var oddPair = ["🙂", "🙃"]
    private(set) var oddIndex = 0
    // Cercle parfait (points dans le repère de tout l'écran)
    private(set) var strokes: [[CGPoint]] = [[], []]
    private(set) var circleScore: [Double?] = [nil, nil]
    @ObservationIgnored private var drawing = [false, false]
    // Ballon
    private(set) var balloon = [0, 0]
    private(set) var balloonDone = [false, false]
    private(set) var balloonBurst = [false, false]
    @ObservationIgnored private var balloonLimit = 18
    // Pile au centre : position de l'aiguille (−1…1) au moment où on l'arrête
    private(set) var targetStop: [Double?] = [nil, nil]
    // Mémo-grille
    private(set) var gridCells: Set<Int> = []
    private(set) var gridPicked: [Set<Int>] = [[], []]
    private(set) var gridOut = [false, false]

    /// Avec le Pass, les 8 duels de plus entrent dans le paquet.
    var hasPass = false

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
            deck = Kind.allCases.filter { hasPass || !$0.needsPass }.shuffled()
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
        default:
            setUpMore()
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
        default:
            updateMore()
        }
    }

    func finish(_ seat: Int?, _ why: String) {
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
        case .target:
            stopNeedle(seat)
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

// MARK: - Les 8 duels du Pass

extension DuelsGame {
    static let rpsEmoji = ["✊", "✋", "✌️"]

    static func rpsName(_ k: Int) -> String {
        switch k {
        case 0: return L("Pierre")
        case 1: return L("Feuille")
        default: return L("Ciseaux")
        }
    }

    static let oddPairs: [(String, String)] = [("🙂", "🙃"), ("😀", "😃"), ("🐶", "🐺"), ("🍏", "🍎"), ("🌲", "🎄"),
                                               ("🔒", "🔓"), ("📕", "📗"), ("⭐️", "🌟"), ("🌙", "🌛"), ("🚗", "🚙"),
                                               ("☕️", "🍵"), ("🐢", "🐊"), ("⏰", "⏱️"), ("🍋", "🍌"), ("👀", "👁️")]

    func setUpMore() {
        switch kind {
        case .rps:
            rpsPick = [nil, nil]
            rpsRevealAt = nil
            rpsTieAt = nil
            rpsTies = 0
            rpsDeadline = 8
        case .nerve:
            holding = [false, false]
            fuseStart = nil
            releasedAfter = [nil, nil]
            explodeAfter = Double.random(in: 3...9)
        case .order:
            orderLayout = Array(1...9).shuffled()
            orderNext = [1, 1]
            orderMiss = [nil, nil]
        case .odd:
            let p = Self.oddPairs.randomElement() ?? ("🙂", "🙃")
            oddPair = Bool.random() ? [p.0, p.1] : [p.1, p.0]
            oddIndex = Int.random(in: 0..<16)
        case .circle:
            strokes = [[], []]
            circleScore = [nil, nil]
            drawing = [false, false]
        case .balloon:
            balloon = [0, 0]
            balloonDone = [false, false]
            balloonBurst = [false, false]
            balloonLimit = Int.random(in: 12...22)
        case .target:
            targetStop = [nil, nil]
        case .grid:
            var cells = Set<Int>()
            while cells.count < 5 { cells.insert(Int.random(in: 0..<16)) }
            gridCells = cells
            gridPicked = [[], []]
            gridOut = [false, false]
        default:
            break
        }
    }

    func updateMore() {
        switch kind {
        case .rps:
            if let r = rpsRevealAt, t > r + 1.2 { resolveRPS() }
            if rpsRevealAt == nil && t > rpsDeadline {
                if let s = (0..<2).first(where: { rpsPick[$0] != nil }) {
                    finish(s, L("\(Self.name(1 - s)) n'a pas choisi à temps !"))
                } else {
                    finish(nil, L("Personne n'a choisi…"))
                }
            }
        case .nerve:
            if fuseStart == nil && t > 10 { finish(nil, L("Il faut tenir à deux !")) }
            if let f = fuseStart, t - f >= explodeAfter { explode() }
        case .order:
            if t > 16 {
                if orderNext[0] == orderNext[1] { finish(nil, L("Égalité !")) } else { finish(orderNext[0] > orderNext[1] ? 0 : 1, L("Plus loin dans la suite !")) }
            }
        case .odd:
            if t > 12 { finish(nil, L("Personne ne l'a trouvé…")) }
        case .circle:
            if t > 15 { resolveCircle() }
        case .balloon:
            if t > 12 {
                balloonDone = [true, true]
                resolveBalloon()
            }
        case .target:
            if t > 10 { resolveTarget() }
        case .grid:
            if t > 15 { finish(nil, L("Temps écoulé !")) }
        default:
            break
        }
    }

    // MARK: Pierre-feuille-ciseaux

    func rps(_ seat: Int, _ choice: Int) {
        guard phase == .playing, !paused, kind == .rps, rpsRevealAt == nil, rpsPick[seat] == nil else { return }
        rpsPick[seat] = choice
        SoundPlayer.shared.play(.clack, volume: 0.6)
        Haptics.tap()
        if rpsPick[0] != nil && rpsPick[1] != nil {
            rpsRevealAt = t
            SoundPlayer.shared.play(.whoosh, volume: 0.6)
        }
    }

    private func resolveRPS() {
        guard let a = rpsPick[0], let b = rpsPick[1] else { return }
        if a == b {
            rpsTies += 1
            if rpsTies >= 3 {
                finish(nil, L("Trois égalités de suite !"))
            } else {
                rpsPick = [nil, nil]
                rpsRevealAt = nil
                rpsTieAt = t
                rpsDeadline = t + 8
                SoundPlayer.shared.play(.wrong, volume: 0.4)
            }
            return
        }
        let w = (a - b + 3) % 3 == 1 ? 0 : 1
        let x = w == 0 ? a : b, y = w == 0 ? b : a
        finish(w, L("\(Self.rpsName(x)) bat \(Self.rpsName(y)) !"))
    }

    // MARK: Nerfs d'acier

    func hold(_ seat: Int, _ down: Bool) {
        guard phase == .playing, !paused, kind == .nerve else { return }
        if fuseStart == nil {
            holding[seat] = down
            if holding[0] && holding[1] {
                fuseStart = t
                SoundPlayer.shared.play(.whoosh, volume: 0.5)
                Haptics.tap()
            }
            return
        }
        guard let f = fuseStart, !down, holding[seat], releasedAfter[seat] == nil else { return }
        holding[seat] = false
        releasedAfter[seat] = t - f
        SoundPlayer.shared.play(.clack, volume: 0.7)
        if let r0 = releasedAfter[0], let r1 = releasedAfter[1] {
            let w = r0 >= r1 ? 0 : 1
            finish(w, L("\(Self.name(w)) a tenu \(Self.secs(max(r0, r1))) s"))
        }
    }

    private func explode() {
        guard phase == .playing else { return }
        SoundPlayer.shared.play(.boom, volume: 1)
        Haptics.chomp()
        let caught = (0..<2).filter { holding[$0] && releasedAfter[$0] == nil }
        if caught.count == 2 {
            finish(nil, L("BOUM ! Vous avez tenu trop longtemps"))
        } else if let c = caught.first {
            finish(1 - c, L("BOUM ! \(Self.name(c)) a tenu trop longtemps"))
        } else {
            finish(nil, L("BOUM !"))
        }
    }

    // MARK: 1 à 9

    func orderTap(_ seat: Int, cell: Int) {
        guard phase == .playing, !paused, kind == .order, t >= lockedUntil[seat], cell < orderLayout.count else { return }
        let n = orderLayout[cell]
        if n < orderNext[seat] { return }
        if n == orderNext[seat] {
            orderNext[seat] += 1
            SoundPlayer.shared.play(.notch, volume: 0.8)
            Haptics.tap()
            if orderNext[seat] > 9 { finish(seat, L("1 à 9 dans l'ordre !")) }
        } else {
            orderMiss[seat] = t
            lockedUntil[seat] = t + 0.6
            SoundPlayer.shared.play(.wrong, volume: 0.5)
            Haptics.error()
        }
    }

    // MARK: L'intrus

    func oddTap(_ seat: Int, cell: Int) {
        guard phase == .playing, !paused, kind == .odd, t >= lockedUntil[seat] else { return }
        if cell == oddIndex {
            finish(seat, L("L'intrus était \(oddPair[1]) !"))
        } else {
            wrongPick[seat] = cell
            lockedUntil[seat] = t + 1.2
            SoundPlayer.shared.play(.wrong, volume: 0.6)
            Haptics.error()
        }
    }

    // MARK: Cercle parfait

    func circleAdd(_ seat: Int, _ p: CGPoint) {
        guard phase == .playing, !paused, kind == .circle, circleScore[seat] == nil else { return }
        if !drawing[seat] {
            drawing[seat] = true
            strokes[seat] = [p]
            return
        }
        guard let last = strokes[seat].last, hypot(p.x - last.x, p.y - last.y) > 2, strokes[seat].count < 900 else { return }
        strokes[seat].append(p)
    }

    func circleEnd(_ seat: Int) {
        guard phase == .playing, kind == .circle, drawing[seat] else { return }
        drawing[seat] = false
        guard let score = Self.roundness(strokes[seat]) else {
            strokes[seat] = []
            Haptics.error()
            return
        }
        circleScore[seat] = score
        SoundPlayer.shared.play(.chime, volume: 0.7)
        Haptics.tap()
        if circleScore[0] != nil && circleScore[1] != nil { resolveCircle() }
    }

    /// Note sur 100 : rayon régulier, tour complet, trait refermé. nil si c'est trop petit pour juger.
    static func roundness(_ pts: [CGPoint]) -> Double? {
        guard pts.count >= 20 else { return nil }
        let n = CGFloat(pts.count)
        let cx = pts.reduce(0) { $0 + $1.x } / n
        let cy = pts.reduce(0) { $0 + $1.y } / n
        let radii = pts.map { hypot($0.x - cx, $0.y - cy) }
        let mean = radii.reduce(0, +) / n
        guard mean > 28 else { return nil }
        let variance = radii.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let deviation = Double(sqrt(variance) / mean)
        var turned = 0.0
        var previous = atan2(Double(pts[0].y - cy), Double(pts[0].x - cx))
        for p in pts.dropFirst() {
            let a = atan2(Double(p.y - cy), Double(p.x - cx))
            var d = a - previous
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            turned += d
            previous = a
        }
        let coverage = min(1, abs(turned) / (2 * .pi * 0.97))
        guard let first = pts.first, let last = pts.last else { return nil }
        let gap = Double(hypot(first.x - last.x, first.y - last.y) / mean)
        let closed = max(0.5, 1 - max(0, gap - 0.25) * 0.5)
        let score = max(0, 1 - deviation * 3.2) * coverage * coverage * closed * 100
        return min(99.9, score)
    }

    private func resolveCircle() {
        guard phase == .playing else { return }
        let a = circleScore[0] ?? -1, b = circleScore[1] ?? -1
        let text = L("\(Self.name(0)) : \(Self.percent(circleScore[0])) · \(Self.name(1)) : \(Self.percent(circleScore[1]))")
        if a < 0 && b < 0 {
            finish(nil, L("Pas de cercle…"))
        } else if abs(a - b) < 0.05 {
            finish(nil, text)
        } else {
            finish(a > b ? 0 : 1, text)
        }
    }

    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded())) %"
    }

    // MARK: Ballon

    func pump(_ seat: Int) {
        guard phase == .playing, !paused, kind == .balloon, !balloonDone[seat] else { return }
        balloon[seat] += 1
        if balloon[seat] > balloonLimit {
            balloonBurst[seat] = true
            balloonDone[seat] = true
            SoundPlayer.shared.play(.boom, volume: 0.6)
            Haptics.error()
            if balloonDone[0] && balloonDone[1] { resolveBalloon() }
        } else {
            SoundPlayer.shared.play(.pop, volume: 0.3)
            Haptics.tap()
        }
    }

    func stopBalloon(_ seat: Int) {
        guard phase == .playing, !paused, kind == .balloon, !balloonDone[seat], balloon[seat] > 0 else { return }
        balloonDone[seat] = true
        SoundPlayer.shared.play(.clack, volume: 0.7)
        if balloonDone[0] && balloonDone[1] { resolveBalloon() }
    }

    private func resolveBalloon() {
        guard phase == .playing else { return }
        let sizes = (0..<2).map { balloonBurst[$0] ? -1 : balloon[$0] }
        let text = L("\(Self.name(0)) : \(balloonBurst[0] ? "💥" : "\(balloon[0])") · \(Self.name(1)) : \(balloonBurst[1] ? "💥" : "\(balloon[1])")")
        if sizes[0] < 0 && sizes[1] < 0 {
            finish(nil, L("Les deux ballons ont éclaté !"))
        } else if sizes[0] == sizes[1] {
            finish(nil, text)
        } else {
            finish(sizes[0] > sizes[1] ? 0 : 1, text)
        }
    }

    // MARK: Pile au centre

    /// Position de l'aiguille : un aller-retour d'un bord à l'autre, de plus en plus vite.
    var needle: Double { sin(t * (3.1 + t * 0.12)) }

    func stopNeedle(_ seat: Int) {
        guard targetStop[seat] == nil else { return }
        targetStop[seat] = needle
        SoundPlayer.shared.play(.clack, volume: 0.7)
        Haptics.tap()
        if targetStop[0] != nil && targetStop[1] != nil { resolveTarget() }
    }

    private func resolveTarget() {
        guard phase == .playing else { return }
        let d = (0..<2).map { targetStop[$0].map { abs($0) } ?? 9 }
        let text = L("\(Self.name(0)) : \(Self.precision(targetStop[0])) · \(Self.name(1)) : \(Self.precision(targetStop[1]))")
        if d[0] > 8 && d[1] > 8 {
            finish(nil, L("Personne n'a arrêté l'aiguille…"))
        } else if abs(d[0] - d[1]) < 0.002 {
            finish(nil, text)
        } else {
            finish(d[0] < d[1] ? 0 : 1, text)
        }
    }

    static func precision(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(((1 - abs(v)) * 100).rounded())) %"
    }

    // MARK: Mémo-grille

    var gridShown: Bool { t < 2.2 }

    func gridTap(_ seat: Int, cell: Int) {
        guard phase == .playing, !paused, kind == .grid, !gridShown, !gridOut[seat], !gridPicked[seat].contains(cell) else { return }
        if gridCells.contains(cell) {
            gridPicked[seat].insert(cell)
            SoundPlayer.shared.play(.notch, volume: 0.8)
            Haptics.tap()
            if gridPicked[seat].count >= gridCells.count { finish(seat, L("Grille parfaite !")) }
        } else {
            gridOut[seat] = true
            SoundPlayer.shared.play(.wrong, volume: 0.6)
            Haptics.error()
            if gridOut[0] && gridOut[1] { finish(nil, L("Raté des deux côtés !")) }
        }
    }
}
