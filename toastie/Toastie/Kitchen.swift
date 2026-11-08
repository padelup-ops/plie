import SwiftUI

// MARK: - Toastie Fold : la cuisine
//
// Un client commande un croque. On le garnit dans l'ordre du ticket (le pain du bas est déjà posé,
// on finit par le pain du dessus), puis on ferme le Duo : l'appareil se ferme et le croque cuit.
// On rouvre au bon moment : doré, ou bien grillé si le client le demande. Plus c'est juste et rapide,
// plus il paie. Une journée dure 100 secondes.

enum Ingredient: String, CaseIterable, Identifiable {
    case ham, cheese, bechamel, egg, tomato, mushroom, goat, honey, pineapple, chicken, spinach, raclette, chocolate, banana

    var id: String { rawValue }
    var image: String { "ing_" + rawValue }

    var name: String {
        switch self {
        case .ham: return T("Jambon", "Ham")
        case .cheese: return T("Fromage", "Cheese")
        case .bechamel: return T("Béchamel", "Béchamel")
        case .egg: return T("Œuf", "Egg")
        case .tomato: return T("Tomate", "Tomato")
        case .mushroom: return T("Champignons", "Mushrooms")
        case .goat: return T("Chèvre", "Goat cheese")
        case .honey: return T("Miel", "Honey")
        case .pineapple: return T("Ananas", "Pineapple")
        case .chicken: return T("Poulet", "Chicken")
        case .spinach: return T("Épinards", "Spinach")
        case .raclette: return T("Raclette", "Raclette")
        case .chocolate: return T("Chocolat", "Chocolate")
        case .banana: return T("Banane", "Banana")
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
        Recipe(id: "monsieur", fr: "Croque-monsieur", en: "Croque-monsieur", layers: [.ham, .cheese], day: 1),
        Recipe(id: "fromage", fr: "Tout fromage", en: "Cheese toastie", layers: [.cheese, .cheese], day: 1),
        Recipe(id: "bechamel", fr: "Croque béchamel", en: "Béchamel toastie", layers: [.ham, .bechamel, .cheese], day: 2),
        Recipe(id: "tomate", fr: "Tomate-fromage", en: "Tomato & cheese", layers: [.tomato, .cheese], day: 2),
        Recipe(id: "madame", fr: "Croque-madame", en: "Croque-madame", layers: [.ham, .cheese, .egg], day: 3),
        Recipe(id: "champi", fr: "Forestier", en: "Mushroom melt", layers: [.mushroom, .bechamel, .cheese], day: 4),
        Recipe(id: "chevre", fr: "Chèvre-miel", en: "Goat cheese & honey", layers: [.goat, .honey], day: 5),
        Recipe(id: "hawai", fr: "Hawaïen", en: "Hawaiian", layers: [.ham, .pineapple, .cheese], day: 6),
        Recipe(id: "poulet", fr: "Poulet-tomate", en: "Chicken & tomato", layers: [.chicken, .tomato, .cheese], day: 7),
        Recipe(id: "vege", fr: "Le végé", en: "The veggie", layers: [.spinach, .tomato, .goat], day: 8),
        Recipe(id: "savoyard", fr: "Savoyard", en: "Alpine melt", layers: [.ham, .raclette, .raclette], day: 9),
        Recipe(id: "choco", fr: "Choco-banane", en: "Choc & banana", layers: [.chocolate, .banana], day: 10),
    ]
}

enum Doneness: Int {
    case raw, light, golden, dark, burnt

    /// La cuisson (0 à 1+) -> l'image du pain.
    static func of(_ d: Double) -> Doneness {
        switch d {
        case ..<0.3: return .raw
        case ..<0.5: return .light
        case ..<0.7: return .golden
        case ..<0.9: return .dark
        default: return .burnt
        }
    }

    var image: String { "bread\(rawValue)" }

    var label: String {
        switch self {
        case .raw: return T("Pas cuit", "Raw")
        case .light: return T("Pâle", "Pale")
        case .golden: return T("Doré", "Golden")
        case .dark: return T("Bien grillé", "Well toasted")
        case .burnt: return T("Brûlé", "Burnt")
        }
    }
}

struct Order {
    let recipe: Recipe
    /// Couches dans l'ordre (sans le pain).
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
}

/// Ce qu'on garde d'une partie à l'autre.
@Observable
final class Career {
    private(set) var stars: [Int: Int]
    private(set) var bestRush: Int

    init() {
        let d = UserDefaults.standard
        var s: [Int: Int] = [:]
        for day in 1...Kitchen.lastDay { let v = d.integer(forKey: "toastie.stars.\(day)"); if v > 0 { s[day] = v } }
        stars = s
        bestRush = d.integer(forKey: "toastie.rush")
    }

    func record(day: Int, stars n: Int) {
        guard n > (stars[day] ?? 0) else { return }
        stars[day] = n
        UserDefaults.standard.set(n, forKey: "toastie.stars.\(day)")
    }

    func recordRush(_ score: Int) {
        guard score > bestRush else { return }
        bestRush = score
        UserDefaults.standard.set(score, forKey: "toastie.rush")
    }

    /// Le jour suivant s'ouvre dès qu'on a eu au moins une étoile.
    func isOpen(_ day: Int) -> Bool { day == 1 || (stars[day - 1] ?? 0) > 0 }
    var totalStars: Int { stars.values.reduce(0, +) }
}

@Observable
final class Kitchen {
    enum Phase: Equatable { case ready, assembling, cooking, served, gone, dayOver }

    static let lastDay = 15
    static let freeDays = 3
    static let shiftLength: Double = 100

    let day: Int
    /// 0 = une journée ; sinon le rush infini.
    let rush: Bool

    private(set) var phase: Phase = .ready
    private(set) var order: Order?
    /// Ce qui est posé sur le pain du bas.
    private(set) var stack: [Ingredient] = []
    private(set) var topBread = false
    private(set) var cook: Double = 0
    private(set) var patienceLeft: Double = 1
    private(set) var shiftLeft: Double = Kitchen.shiftLength
    private(set) var coins = 0
    private(set) var servedCount = 0
    private(set) var perfectCount = 0
    private(set) var lostCount = 0
    private(set) var last: Served?
    private(set) var mistakes = 0
    private(set) var shake = 0
    private(set) var hint: String?
    /// L'appareil est fermé (Duo fermé, ou bouton « Fermer » sans charnière).
    private(set) var closed = false
    private(set) var hasHinge = false

    @ObservationIgnored private var nextIn: Double = 0
    @ObservationIgnored private var hintLeft: Double = 0
    @ObservationIgnored private var lastCustomer = -1

    init(day: Int, rush: Bool = false) {
        self.day = rush ? Kitchen.lastDay : day
        self.rush = rush
    }

    // MARK: Le menu du jour

    var recipes: [Recipe] {
        Recipe.all.filter { $0.day <= min(day, 10) }
    }

    /// Les garnitures du plateau (dans un ordre fixe).
    var tray: [Ingredient] {
        let used = Set(recipes.flatMap(\.layers))
        return Ingredient.allCases.filter { used.contains($0) }
    }

    var target: Int { 60 + day * 15 }
    var dayStars: Int {
        if coins >= target { return 3 }
        if Double(coins) >= Double(target) * 0.75 { return 2 }
        if Double(coins) >= Double(target) * 0.45 { return 1 }
        return 0
    }

    // MARK: Le service

    func start() {
        guard phase == .ready else { return }
        coins = 0
        shiftLeft = Self.shiftLength
        newOrder()
    }

    private func newOrder() {
        // Les recettes nouvelles du jour reviennent plus souvent.
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
            let extra: Ingredient = [.cheese, .tomato, .ham, .bechamel].randomElement() ?? .cheese
            layers.insert(extra, at: Int.random(in: 0...layers.count))
        }
        let wish: Doneness = day >= 3 && Int.random(in: 0..<10) < 3 ? .dark : .golden
        var customer = Int.random(in: 0..<5)
        if customer == lastCustomer { customer = (customer + 1) % 5 }
        lastCustomer = customer
        let speedUp = rush ? min(10, Double(servedCount) * 0.4) : 0
        let patience = max(11, 27 - Double(day) * 0.8 - speedUp) + 2.2 * Double(layers.count)
        order = Order(recipe: recipe, layers: layers, wish: wish, customer: customer, patience: patience)
        stack = []
        topBread = false
        cook = 0
        mistakes = 0
        patienceLeft = 1
        phase = .assembling
        Sound.play(.bell, volume: 0.5)
    }

    var nextNeeded: Ingredient? {
        guard let order, stack.count < order.layers.count else { return nil }
        return order.layers[stack.count]
    }

    var sandwichReady: Bool { topBread }

    func add(_ ing: Ingredient) {
        guard phase == .assembling, !topBread, let order else { return }
        if stack.count < order.layers.count && order.layers[stack.count] == ing {
            stack.append(ing)
            Sound.play(.pop, volume: 0.6)
            Haptics.tap()
        } else {
            mistake(T("Pas ça ! Regarde le ticket.", "Not that! Check the ticket."))
        }
    }

    func addTopBread() {
        guard phase == .assembling, !topBread, let order else { return }
        guard stack.count == order.layers.count else {
            mistake(T("Il manque des garnitures.", "Some fillings are missing."))
            return
        }
        topBread = true
        Sound.play(.tock, volume: 0.7)
        Haptics.tap()
        say(hasHinge ? T("Ferme le Duo pour cuire !", "Close the Duo to toast it!") : T("Ferme l'appareil !", "Close the press!"))
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
        hintLeft = 1.8
    }

    // MARK: L'appareil (la charnière)

    func hinge(_ degrees: Double?) {
        guard let degrees else { hasHinge = false; return }
        hasHinge = true
        setClosed(degrees < 35)
    }

    /// Sans charnière : le bouton Fermer / Ouvrir.
    func toggleLid() { setClosed(!closed) }

    private func setClosed(_ c: Bool) {
        guard c != closed else { return }
        closed = c
        if c {
            Sound.play(.clunk, volume: 0.8)
            if phase == .assembling && topBread {
                phase = .cooking
                Sound.loop(.sizzle, volume: 0.45)
            }
        } else {
            Sound.stopLoop()
            Sound.play(.clack, volume: 0.6)
            if phase == .cooking { serve() }
        }
    }

    private func serve() {
        guard let order else { return }
        let d = Doneness.of(cook)
        var stars: Int
        var comment: String
        if d == .burnt {
            stars = 0
            comment = T("Brûlé !", "Burnt!")
        } else if d == order.wish {
            stars = 3
            comment = mistakes == 0 ? T("Parfait !", "Perfect!") : T("Très bon !", "Very good!")
        } else if abs(d.rawValue - order.wish.rawValue) == 1 {
            stars = 2
            comment = d.rawValue < order.wish.rawValue ? T("Un peu pâle…", "A bit pale…") : T("Un peu trop cuit…", "A bit overdone…")
        } else {
            stars = 1
            comment = T("Pas assez cuit !", "Undercooked!")
        }
        if mistakes > 0 { stars = min(stars, 2) }
        let base = 6 + 2 * order.layers.count
        let mult = [0.0, 0.4, 0.75, 1.0][stars]
        let tip = stars >= 2 ? Int((patienceLeft * 8).rounded()) : 0
        let earned = Int((Double(base) * mult).rounded()) + tip
        coins += earned
        servedCount += 1
        if stars == 3 { perfectCount += 1 }
        if stars == 0 { lostCount += rush ? 1 : 0 }
        last = Served(stars: stars, coins: earned, doneness: d, comment: comment)
        phase = .served
        nextIn = 1.8
        Sound.play(stars >= 2 ? .win : .wrong, volume: 0.6)
        if stars >= 2 { Haptics.success() } else { Haptics.error() }
    }

    // MARK: Le temps

    func tick(_ dt: Double) {
        if hintLeft > 0 {
            hintLeft -= dt
            if hintLeft <= 0 { hint = nil }
        }
        guard phase != .ready && phase != .dayOver else { return }
        if !rush && phase != .served && phase != .gone {
            shiftLeft = max(0, shiftLeft - dt)
        }
        switch phase {
        case .assembling, .cooking:
            if let order { patienceLeft = max(0, patienceLeft - dt / order.patience) }
            if phase == .cooking { cook += dt / 7.5 }
            if patienceLeft <= 0 {
                // Le client s'en va.
                if closed { Sound.stopLoop() }
                lostCount += 1
                last = Served(stars: 0, coins: 0, doneness: Doneness.of(cook), comment: T("Trop long ! Il est parti.", "Too slow! They left."))
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
        // Fin de journée : on finit la commande en cours, puis on ferme.
        if !rush && shiftLeft <= 0 && phase == .assembling && stack.isEmpty { endDay() }
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
        guard let order else { return }
        switch step {
        case "assemble":
            for ing in order.layers.prefix(max(1, order.layers.count - 1)) { stack.append(ing) }
        case "cook", "closed":
            stack = order.layers
            topBread = true
            phase = .cooking
            cook = 0.58
            closed = true
        case "result":
            stack = order.layers
            topBread = true
            cook = 0.6
            phase = .cooking
            closed = true
            setClosed(false)
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
