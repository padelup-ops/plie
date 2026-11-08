import SwiftUI

// MARK: - Waffle Fold : la cuisine
//
// Un client arrive, son ticket s'imprime. On verse la pâte sur la plaque, on ferme le Duo :
// le gaufrier se ferme et la gaufre cuit. On rouvre au bon moment (dorée, ou bien cuite si c'est
// demandé), puis on ajoute les garnitures dans l'ordre du ticket. Plus c'est juste et rapide,
// plus le client paie. Une journée dure 100 secondes.

enum Ingredient: String, CaseIterable, Identifiable {
    case sugar, spread, cream, strawberry, banana, caramel, honey, chocmelt, jam, icecream, sprinkles, almonds

    var id: String { rawValue }
    var image: String { "ing_" + rawValue }

    var name: String {
        switch self {
        case .sugar: return T("Sucre glace", "Icing sugar")
        case .spread: return T("Choco-noisette", "Choc-hazelnut")
        case .cream: return T("Chantilly", "Whipped cream")
        case .strawberry: return T("Fraises", "Strawberries")
        case .banana: return T("Banane", "Banana")
        case .caramel: return T("Caramel", "Caramel")
        case .honey: return T("Miel", "Honey")
        case .chocmelt: return T("Chocolat", "Chocolate")
        case .jam: return T("Confiture", "Jam")
        case .icecream: return T("Glace vanille", "Vanilla ice cream")
        case .sprinkles: return T("Vermicelles", "Sprinkles")
        case .almonds: return T("Amandes", "Almonds")
        }
    }
}

struct Recipe: Identifiable {
    let id: String
    let fr: String
    let en: String
    let layers: [Ingredient]
    /// Le premier jour où on la voit.
    let day: Int
    var name: String { T(fr, en) }

    static let all: [Recipe] = [
        Recipe(id: "sucre", fr: "Gaufre au sucre", en: "Sugar waffle", layers: [.sugar], day: 1),
        Recipe(id: "choco", fr: "Gaufre choco-noisette", en: "Choc-hazelnut waffle", layers: [.spread], day: 1),
        Recipe(id: "chantilly", fr: "Gaufre chantilly", en: "Cream waffle", layers: [.cream], day: 2),
        Recipe(id: "chocoban", fr: "Choco-banane", en: "Choc & banana", layers: [.spread, .banana], day: 2),
        Recipe(id: "fraise", fr: "Fraise-chantilly", en: "Strawberries & cream", layers: [.strawberry, .cream], day: 3),
        Recipe(id: "caramel", fr: "Caramel-chantilly", en: "Caramel & cream", layers: [.caramel, .cream], day: 4),
        Recipe(id: "confiture", fr: "Gaufre confiture", en: "Jam waffle", layers: [.jam, .sugar], day: 5),
        Recipe(id: "gourmande", fr: "La gourmande", en: "The greedy one", layers: [.spread, .banana, .cream], day: 6),
        Recipe(id: "dame", fr: "Dame blanche", en: "Ice cream sundae", layers: [.icecream, .chocmelt], day: 7),
        Recipe(id: "miel", fr: "Miel-amandes", en: "Honey & almonds", layers: [.honey, .almonds], day: 8),
        Recipe(id: "fete", fr: "La fête", en: "Party waffle", layers: [.cream, .sprinkles], day: 9),
        Recipe(id: "totale", fr: "La totale", en: "The works", layers: [.spread, .strawberry, .cream, .sprinkles], day: 10),
    ]
}

enum Doneness: Int {
    case raw, light, golden, dark, burnt

    /// La cuisson (0 à 1+) -> l'image de la gaufre.
    static func of(_ d: Double) -> Doneness {
        switch d {
        case ..<0.3: return .raw
        case ..<0.5: return .light
        case ..<0.7: return .golden
        case ..<0.9: return .dark
        default: return .burnt
        }
    }

    var image: String { "waffle\(rawValue)" }

    var label: String {
        switch self {
        case .raw: return T("Pas cuite", "Raw")
        case .light: return T("Pâle", "Pale")
        case .golden: return T("Dorée", "Golden")
        case .dark: return T("Bien cuite", "Well done")
        case .burnt: return T("Brûlée", "Burnt")
        }
    }
}

struct Order {
    let number: Int
    let recipe: Recipe
    /// Garnitures, dans l'ordre.
    let layers: [Ingredient]
    let wish: Doneness
    let customer: Int
    let patience: Double
}

struct Served {
    let stars: Int
    let coins: Int
    let doneness: Doneness
    let comment: String
    var combo: Int = 0
}

/// Ce qu'on garde d'une partie à l'autre.
@Observable
final class Career {
    private(set) var stars: [Int: Int]
    private(set) var bestRush: Int

    init() {
        let d = UserDefaults.standard
        var s: [Int: Int] = [:]
        for day in 1...Kitchen.lastDay { let v = d.integer(forKey: "waffle.stars.\(day)"); if v > 0 { s[day] = v } }
        stars = s
        bestRush = d.integer(forKey: "waffle.rush")
    }

    func record(day: Int, stars n: Int) {
        guard n > (stars[day] ?? 0) else { return }
        stars[day] = n
        UserDefaults.standard.set(n, forKey: "waffle.stars.\(day)")
    }

    func recordRush(_ score: Int) {
        guard score > bestRush else { return }
        bestRush = score
        UserDefaults.standard.set(score, forKey: "waffle.rush")
    }

    /// Le jour suivant s'ouvre dès qu'on a eu au moins une étoile.
    func isOpen(_ day: Int) -> Bool { day == 1 || (stars[day - 1] ?? 0) > 0 }
    var totalStars: Int { stars.values.reduce(0, +) }
}

@Observable
final class Kitchen {
    enum Phase: Equatable {
        case ready
        /// Il faut verser la pâte.
        case pour
        /// La pâte est sur la plaque : il faut fermer le gaufrier.
        case poured
        case cooking
        /// La gaufre est cuite : on la garnit.
        case topping
        case served, gone, dayOver
    }

    static let lastDay = 15
    static let freeDays = 3
    static let shiftLength: Double = 100

    let day: Int
    /// Le rush infini (sinon, une journée de 100 secondes).
    let rush: Bool

    private(set) var phase: Phase = .ready
    private(set) var order: Order?
    /// Les garnitures déjà posées.
    private(set) var stack: [Ingredient] = []
    /// Le curseur de cuisson (0…1) : il va et vient dans la jauge tant que le gaufrier est fermé.
    private(set) var cursor: Double = 0
    private(set) var cooked: Doneness = .raw
    private(set) var patienceLeft: Double = 1
    private(set) var shiftLeft: Double = Kitchen.shiftLength
    private(set) var coins = 0
    private(set) var servedCount = 0
    private(set) var perfectCount = 0
    private(set) var lostCount = 0
    private(set) var last: Served?
    private(set) var mistakes = 0
    /// Gaufres parfaites d'affilée : chaque parfaite de plus rapporte davantage.
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var shake = 0
    private(set) var hint: String?
    /// Le gaufrier est fermé (Duo fermé, ou bouton « Fermer » sans charnière).
    private(set) var closed = false
    private(set) var hasHinge = false

    @ObservationIgnored private var cursorDir: Double = 1
    @ObservationIgnored private var nextIn: Double = 0
    @ObservationIgnored private var hintLeft: Double = 0
    @ObservationIgnored private var lastCustomer = -1
    @ObservationIgnored private var orderNumber = 0
    /// Captures d'écran : tout est figé.
    @ObservationIgnored private var frozen = false

    init(day: Int, rush: Bool = false) {
        self.day = rush ? Kitchen.lastDay : day
        self.rush = rush
    }

    // MARK: Le menu du jour

    var recipes: [Recipe] { Recipe.all.filter { $0.day <= min(day, 10) } }

    /// Les garnitures du plateau (dans un ordre fixe).
    var tray: [Ingredient] {
        let used = Set(recipes.flatMap(\.layers))
        return Ingredient.allCases.filter { used.contains($0) }
    }

    var target: Int { 50 + day * 14 }
    var dayStars: Int {
        if coins >= target { return 3 }
        if Double(coins) >= Double(target) * 0.75 { return 2 }
        if Double(coins) >= Double(target) * 0.45 { return 1 }
        return 0
    }

    // MARK: La jauge de cuisson
    //
    // Rouge aux deux bouts, puis jaune, et vert au milieu. Le curseur fait des allers-retours ;
    // il faut rouvrir le Duo quand il est dans le vert. À gauche c'est pas assez cuit, à droite trop.

    enum Zone { case red, yellow, green }

    /// Demi-largeur de la zone verte (elle rétrécit avec les jours).
    var greenHalf: Double {
        rush ? max(0.05, 0.085 - Double(servedCount) * 0.002) : max(0.055, 0.095 - Double(day) * 0.0027)
    }
    var yellowHalf: Double { greenHalf + 0.14 }
    /// Durée d'un aller du curseur, en secondes (il accélère avec les jours).
    var sweepTime: Double {
        rush ? max(0.7, 1.5 - Double(servedCount) * 0.04) : max(0.8, 1.7 - Double(day) * 0.06)
    }

    func zone(_ x: Double) -> Zone {
        let d = abs(x - 0.5)
        return d <= greenHalf ? .green : (d <= yellowHalf ? .yellow : .red)
    }

    func doneness(at x: Double) -> Doneness {
        switch zone(x) {
        case .green: return .golden
        case .yellow: return x < 0.5 ? .light : .dark
        case .red: return x < 0.5 ? .raw : .burnt
        }
    }

    var cursorZone: Zone { zone(cursor) }

    // MARK: Le service

    func start() {
        guard phase == .ready else { return }
        coins = 0
        shiftLeft = Self.shiftLength
        newOrder()
    }

    private func newOrder() {
        // Les recettes du jour reviennent plus souvent.
        let pool = recipes
        let weights = pool.map { $0.day == min(day, 10) ? 2.5 : 1.0 }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var recipe = pool[0]
        for (r, w) in zip(pool, weights) {
            if roll < w { recipe = r; break }
            roll -= w
        }
        var layers = recipe.layers
        // Dès le jour 11 (et en rush), un client sur trois veut un supplément.
        if day >= 11 && Int.random(in: 0..<3) == 0 {
            let extra: Ingredient = [.sugar, .cream, .sprinkles, .chocmelt].filter { !layers.contains($0) }.randomElement() ?? .sugar
            layers.append(extra)
        }
        let wish: Doneness = .golden
        var customer = Int.random(in: 0..<5)
        if customer == lastCustomer { customer = (customer + 1) % 5 }
        lastCustomer = customer
        orderNumber += 1
        let speedUp = rush ? min(9, Double(servedCount) * 0.35) : 0
        let patience = max(16, 30 - Double(day) * 0.7 - speedUp) + 2.5 * Double(layers.count)
        order = Order(number: orderNumber, recipe: recipe, layers: layers, wish: wish, customer: customer, patience: patience)
        stack = []
        cursor = 0
        cooked = .raw
        mistakes = 0
        patienceLeft = 1
        phase = .pour
        Sound.play(.bell, volume: 0.5)
    }

    var nextNeeded: Ingredient? {
        guard let order, stack.count < order.layers.count else { return nil }
        return order.layers[stack.count]
    }

    /// On verse la pâte.
    func pour() {
        guard phase == .pour else { return }
        phase = .poured
        Sound.play(.chomp, volume: 0.5)
        Haptics.tap()
        say(hasHinge ? T("Ferme le Duo pour cuire !", "Close the Duo to cook!") : T("Ferme le gaufrier !", "Close the waffle iron!"))
    }

    func add(_ ing: Ingredient) {
        guard phase == .topping, let order else { return }
        if stack.count < order.layers.count && order.layers[stack.count] == ing {
            stack.append(ing)
            Sound.play(.pop, volume: 0.6)
            Haptics.tap()
            if stack.count == order.layers.count { serve() }
        } else {
            mistake(T("Pas ça ! Regarde le ticket.", "Not that! Check the ticket."))
        }
    }

    private func mistake(_ text: String) {
        mistakes += 1
        shake += 1
        patienceLeft = max(0, patienceLeft - 1.5 / max(1, order?.patience ?? 20))
        say(text)
        Sound.play(.wrong, volume: 0.6)
        Haptics.error()
    }

    private func say(_ text: String) {
        hint = text
        hintLeft = 2
    }

    // MARK: Le gaufrier (la charnière)

    func hinge(_ degrees: Double?) {
        #if DEBUG
        // Captures : le simulateur donne un angle de charnière qui fermerait le gaufrier.
        if UserDefaults.standard.string(forKey: "shot") != nil { return }
        #endif
        guard let degrees else { hasHinge = false; return }
        hasHinge = true
        // Fermé sous 12° ; on le considère rouvert dès 16°, pour que le curseur s'arrête au tout début du geste.
        if closed { if degrees > 16 { setClosed(false) } } else if degrees < 12 { setClosed(true) }
    }

    /// Sans charnière : le bouton Fermer / Ouvrir.
    func toggleLid() { setClosed(!closed) }

    private func setClosed(_ c: Bool) {
        guard c != closed else { return }
        closed = c
        if c {
            Sound.play(.clunk, volume: 0.8)
            if phase == .poured {
                cursor = 0
                cursorDir = 1
                phase = .cooking
                Sound.loop(.sizzle, volume: 0.55)
            }
        } else {
            Sound.stopLoop()
            Sound.play(.clack, volume: 0.6)
            if phase == .cooking {
                cooked = doneness(at: cursor)
                if cooked == .burnt {
                    serve()
                } else {
                    phase = .topping
                    switch cooked {
                    case .golden:
                        Sound.play(.pop, volume: 0.6)
                        Haptics.success()
                        say(T("Pile dans le vert ! Garnis-la !", "Right in the green! Top it!"))
                    case .raw: say(T("Trop tôt ! Pas assez cuite…", "Too early! Undercooked…"))
                    case .light: say(T("Un peu tôt… Garnis-la !", "A bit early… Top it!"))
                    default: say(T("Un peu tard… Garnis-la !", "A bit late… Top it!"))
                    }
                }
            }
        }
    }

    private func serve() {
        guard let order else { return }
        let d = cooked
        var stars: Int
        var comment: String
        if d == .burnt {
            stars = 0
            comment = T("Brûlée !", "Burnt!")
        } else if d == order.wish {
            stars = 3
            comment = mistakes == 0 ? T("Parfaite !", "Perfect!") : T("Très bonne !", "Very good!")
        } else if abs(d.rawValue - order.wish.rawValue) == 1 {
            stars = 2
            comment = d.rawValue < order.wish.rawValue ? T("Un peu pâle…", "A bit pale…") : T("Un peu trop cuite…", "A bit overdone…")
        } else {
            stars = 1
            comment = T("Pas assez cuite !", "Undercooked!")
        }
        if mistakes > 0 { stars = min(stars, 2) }
        let base = 6 + 3 * order.layers.count
        let mult = [0.0, 0.4, 0.75, 1.0][stars]
        let tip = stars >= 2 ? Int((patienceLeft * 8).rounded()) : 0
        if stars == 3 { combo += 1; bestCombo = max(bestCombo, combo) } else { combo = 0 }
        // Combo : +25 % par parfaite d'affilée (jusqu'à ×2).
        let comboBonus = 1 + 0.25 * Double(min(4, max(0, combo - 1)))
        let earned = Int(((Double(base) * mult + Double(tip)) * comboBonus).rounded())
        coins += earned
        servedCount += 1
        if stars == 3 { perfectCount += 1 }
        if stars == 0 && rush { lostCount += 1 }
        last = Served(stars: stars, coins: earned, doneness: d, comment: comment, combo: stars == 3 ? combo : 0)
        phase = .served
        nextIn = 1.8
        Sound.play(stars >= 2 ? .win : .wrong, volume: 0.6)
        if stars >= 2 { Haptics.success() } else { Haptics.error() }
    }

    // MARK: Le temps

    func tick(_ dt: Double) {
        if frozen { return }
        if hintLeft > 0 {
            hintLeft -= dt
            if hintLeft <= 0 { hint = nil }
        }
        guard phase != .ready && phase != .dayOver else { return }
        if !rush && phase != .served && phase != .gone {
            shiftLeft = max(0, shiftLeft - dt)
        }
        switch phase {
        case .pour, .poured, .cooking, .topping:
            if let order { patienceLeft = max(0, patienceLeft - dt / order.patience) }
            if phase == .cooking {
                // Le curseur fait des allers-retours entre les deux bords.
                cursor += cursorDir * dt / sweepTime
                if cursor >= 1 { cursor = 1; cursorDir = -1 }
                if cursor <= 0 { cursor = 0; cursorDir = 1 }
            }
            if patienceLeft <= 0 {
                // Le client s'en va.
                Sound.stopLoop()
                lostCount += 1
                combo = 0
                last = Served(stars: 0, coins: 0, doneness: cooked, comment: T("Trop long ! Il est parti.", "Too slow! They left."))
                phase = .gone
                nextIn = 1.8
                Sound.play(.buzzer, volume: 0.5)
                Haptics.error()
            }
        case .served, .gone:
            nextIn -= dt
            if nextIn <= 0 {
                if rush && lostCount >= 3 { endDay() }
                else if !rush && shiftLeft <= 0 { endDay() }
                else { newOrder() }
            }
        default:
            break
        }
        // Fin de journée : on finit la commande commencée, sinon on ferme.
        if !rush && shiftLeft <= 0 && phase == .pour { endDay() }
    }

    private func endDay() {
        Sound.stopLoop()
        phase = .dayOver
        order = nil
        Sound.play(.applause, volume: 0.6)
    }

    var customerMood: String {
        switch phase {
        case .served: return (last?.stars ?? 0) >= 2 ? "happy" : "angry"
        case .gone: return "angry"
        default: return patienceLeft < 0.3 ? "angry" : "wait"
        }
    }

    // MARK: Démo (captures)

    func demo(_ step: String) {
        start()
        frozen = step != "summary"
        guard let order else { return }
        switch step {
        case "pour":
            break
        case "poured":
            pour()
        case "assemble", "topping":
            phase = .topping
            cooked = .golden
            for ing in order.layers.prefix(max(1, order.layers.count - 1)) { stack.append(ing) }
            if stack.count == order.layers.count { stack.removeLast() }
        case "cook", "closed":
            phase = .cooking
            cursor = 0.47
            closed = true
        case "result":
            cooked = order.wish
            stack = order.layers
            serve()
        case "summary":
            coins = target + 12
            servedCount = 9
            perfectCount = 6
            endDay()
        default:
            break
        }
    }
}
