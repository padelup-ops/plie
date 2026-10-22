import SwiftUI
import Observation

// MARK: - Règles
//
// La feuille est une grille de cases. Chaque case porte un mélange de pigments :
// rouge = 1, jaune = 2, bleu = 4 (orange = 3, violet = 5, vert = 6, brun = 7).
// Plier le long d'une ligne décalque la peinture fraîche : chaque case reçoit la peinture
// de la case symétrique, si elle est sur la feuille. Même règle que tools/pliage_gen.py.

struct PliageFold: Equatable, Hashable {
    enum Axis: Equatable, Hashable {
        case vertical, horizontal
    }

    let axis: Axis
    /// Position de la ligne : entre la colonne (ou rangée) index - 1 et index.
    let index: Int

    /// Lit « v2 » ou « h1 ».
    init?(code: Substring) {
        guard let first = code.first, let value = Int(code.dropFirst()) else { return nil }
        switch first {
        case "v": axis = .vertical
        case "h": axis = .horizontal
        default: return nil
        }
        index = value
    }

    init(axis: Axis, index: Int) {
        self.axis = axis
        self.index = index
    }
}

struct PliageLevel {
    let number: Int
    let world: Int
    let width: Int
    let height: Int
    let start: [UInt8]
    let target: [UInt8]
    /// Nombre minimal de plis (vérifié par recherche exhaustive).
    let par: Int
    let solution: [PliageFold]

    init(number: Int, world: Int, width: Int, height: Int, start: String, target: String, par: Int, solution: String) {
        self.number = number
        self.world = world
        self.width = width
        self.height = height
        self.start = start.compactMap { UInt8(String($0)) }
        self.target = target.compactMap { UInt8(String($0)) }
        self.par = par
        self.solution = solution.split(separator: " ").compactMap { PliageFold(code: $0) }
    }

    static let worldCount = 3

    static func worldName(_ world: Int) -> String {
        switch world {
        case 1: return "Premiers plis"
        case 2: return "Mélanges"
        default: return "Origami"
        }
    }

    var tip: String? {
        guard let first = PliageLevel.all.first(where: { $0.world == world }), first.number == number else { return nil }
        switch world {
        case 1: return "La peinture est fraîche : plie la feuille, elle se décalque de l'autre côté du pli. Reproduis le modèle."
        case 2: return "Les couleurs se mélangent quand elles se superposent : rouge + jaune = orange, jaune + bleu = vert, rouge + bleu = violet."
        case 3: return "Trois couleurs, et l'ordre des plis compte. Observe les symétries du modèle."
        default: return nil
        }
    }

    var allFolds: [PliageFold] {
        (1..<width).map { PliageFold(axis: .vertical, index: $0) } +
        (1..<height).map { PliageFold(axis: .horizontal, index: $0) }
    }
}

enum PliageEngine {
    static func fold(_ grid: [UInt8], width: Int, height: Int, along fold: PliageFold) -> [UInt8] {
        var out = grid
        for r in 0..<height {
            for c in 0..<width {
                let mc = fold.axis == .vertical ? 2 * fold.index - 1 - c : c
                let mr = fold.axis == .horizontal ? 2 * fold.index - 1 - r : r
                if mc >= 0, mc < width, mr >= 0, mr < height {
                    out[r * width + c] = grid[r * width + c] | grid[mr * width + mc]
                }
            }
        }
        return out
    }

    /// Le côté qui se soulève : le plus petit (à égalité, gauche ou haut).
    /// Renvoie la plage de colonnes (pli vertical) ou de rangées (pli horizontal), et si c'est le premier côté.
    static func flap(for fold: PliageFold, width: Int, height: Int) -> (range: Range<Int>, isLeadingSide: Bool) {
        let count = fold.axis == .vertical ? width : height
        if fold.index <= count - fold.index {
            return (0..<fold.index, true)
        }
        return (fold.index..<count, false)
    }

    static func color(_ value: UInt8) -> Color {
        switch value {
        case 1: return Color(hex: 0xE8403C)
        case 2: return Color(hex: 0xF7C531)
        case 3: return Color(hex: 0xF58A2A)
        case 4: return Color(hex: 0x3A6FE0)
        case 5: return Color(hex: 0x9447C2)
        case 6: return Color(hex: 0x2FA65A)
        case 7: return Color(hex: 0x6E4B32)
        default: return paper
        }
    }

    static let paper = Color(hex: 0xF6F0E2)
    static let paperBack = Color(hex: 0xE6DCC6)
    static let paperLine = Color(hex: 0xD8CBB0)

    #if DEBUG
    /// Autocontrôle : la solution enregistrée donne bien le modèle, en exactement « par » plis.
    static func selfCheck() -> (ok: Int, failures: [String]) {
        var ok = 0
        var failures: [String] = []
        for level in PliageLevel.all {
            var grid = level.start
            for f in level.solution {
                grid = fold(grid, width: level.width, height: level.height, along: f)
            }
            let sizes = level.start.count == level.width * level.height && level.target.count == level.width * level.height
            if sizes && grid == level.target && level.solution.count == level.par && level.start != level.target {
                ok += 1
            } else {
                failures.append("PLIAGE \(level.number): tailles=\(sizes) modèle=\(grid == level.target) plis=\(level.solution.count)/\(level.par)")
            }
        }
        return (ok, failures)
    }
    #endif
}

// MARK: - Partie

@Observable
final class PliageSession {
    enum Phase: Equatable {
        case idle
        case auto
        case hinge
    }

    let level: PliageLevel
    private(set) var grid: [UInt8]
    private(set) var history: [[UInt8]] = []
    private(set) var selected: PliageFold?
    /// Fold en cours d'animation (reste défini pendant le dépli).
    private(set) var active: PliageFold?
    /// 0 = feuille à plat, 1 = rabat posé sur l'autre moitié.
    private(set) var progress: Double = 0
    private(set) var phase: Phase = .idle
    private(set) var stamped = false
    private(set) var solved = false
    private(set) var elapsed: Double = 0
    private(set) var outOfFolds = false
    private(set) var hingeReady = false

    @ObservationIgnored private var hingeBaseline: Double?
    static let autoDuration = 0.34
    static let hingeTravel = 45.0

    init(level: PliageLevel) {
        self.level = level
        self.grid = level.start
    }

    var foldsUsed: Int { history.count }
    var foldsLeft: Int { max(0, level.par - foldsUsed) }
    var isAnimating: Bool { phase != .idle }
    var canFold: Bool { selected != nil && foldsLeft > 0 && !solved && !isAnimating }

    // MARK: Actions

    func tapLine(_ fold: PliageFold) {
        guard !solved, !isAnimating else { return }
        if selected == fold {
            performFold()
            return
        }
        selected = fold
        outOfFolds = foldsLeft == 0
        Haptics.tap()
        SoundPlayer.shared.play(.notch, volume: 0.5)
    }

    func performFold() {
        guard selected != nil, !solved, !isAnimating else { return }
        guard foldsLeft > 0 else {
            outOfFolds = true
            Haptics.warning()
            return
        }
        active = selected
        stamped = false
        phase = .auto
    }

    func undo() {
        guard !isAnimating, let previous = history.popLast() else { return }
        grid = previous
        solved = false
        outOfFolds = false
        Haptics.tap()
    }

    func reset() {
        guard !isAnimating else { return }
        grid = level.start
        history = []
        selected = nil
        solved = false
        outOfFolds = false
        Haptics.tap()
    }

    // MARK: Animation

    func tick(dt: Double) {
        if !solved { elapsed += dt }
        guard phase == .auto else { return }
        if !stamped {
            progress = min(1, progress + dt / Self.autoDuration)
            if progress >= 1 { stamp() }
        } else {
            progress = max(0, progress - dt / Self.autoDuration)
            if progress <= 0 { finishFold() }
        }
    }

    /// iPhone Duo : avec une ligne choisie, plier le téléphone plie la feuille.
    func hingeChanged(_ degrees: Double?) {
        guard let degrees, HingeMapping.isOpen(degrees) else {
            hingeBaseline = nil
            hingeReady = false
            return
        }
        hingeReady = true
        if phase == .auto || solved || selected == nil {
            hingeBaseline = degrees
            return
        }
        if hingeBaseline == nil { hingeBaseline = degrees }
        if phase == .idle, let base = hingeBaseline, degrees > base { hingeBaseline = degrees }
        let base = hingeBaseline ?? degrees
        let p = min(1, max(0, (base - degrees) / Self.hingeTravel))

        switch phase {
        case .idle:
            if p > 0.08 {
                guard foldsLeft > 0 else {
                    if !outOfFolds { Haptics.warning() }
                    outOfFolds = true
                    return
                }
                active = selected
                stamped = false
                phase = .hinge
                progress = p
            }
        case .hinge:
            progress = p
            if !stamped {
                if p >= 0.98 { stamp() }
                else if p <= 0.02 { cancelHingeFold() }
            } else if p <= 0.04 {
                progress = 0
                finishFold()
            }
        case .auto:
            break
        }
    }

    private func cancelHingeFold() {
        progress = 0
        phase = .idle
        active = nil
    }

    private func stamp() {
        guard let fold = active else { return }
        history.append(grid)
        grid = PliageEngine.fold(grid, width: level.width, height: level.height, along: fold)
        stamped = true
        progress = 1
        Haptics.correct(subtle: false)
        SoundPlayer.shared.play(.splat)
    }

    private func finishFold() {
        phase = .idle
        active = nil
        stamped = false
        progress = 0
        selected = nil
        if grid == level.target {
            solved = true
            Haptics.success()
            SoundPlayer.shared.play(.win)
        } else if foldsLeft == 0 {
            outOfFolds = true
        }
    }
}
