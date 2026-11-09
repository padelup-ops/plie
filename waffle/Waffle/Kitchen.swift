import SwiftUI

// MARK: - Waffle Fold : la cuisine
//
// Un client arrive, son ticket s'imprime. On verse la pâte sur la plaque, on ferme le Duo :
// le gaufrier se ferme et la gaufre cuit. On rouvre au bon moment (dorée, ou bien cuite si c'est
// demandé), puis on ajoute les garnitures dans l'ordre du ticket. Plus c'est juste et rapide,
// plus le client paie. Une journée dure 100 secondes.

enum Ingredient: String, CaseIterable, Identifiable {
    case sugar, spread, cream, strawberry, banana, caramel, honey, chocmelt, jam, icecream, sprinkles, almonds
    case chocobar, wafer, cookie, speculoos, coconut, blueberry, marshmallow, pistachio
    case ham, cheese, egg, avocado, salmon, tomato, bacon, rocket, sourcream, chives, cheesesauce

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
        case .chocobar: return T("Barre choco-caramel", "Choc-caramel bar")
        case .wafer: return T("Gaufrette noisette", "Hazelnut wafer")
        case .cookie: return T("Cookie", "Cookie")
        case .speculoos: return T("Spéculoos", "Speculoos")
        case .coconut: return T("Coco râpée", "Coconut")
        case .blueberry: return T("Myrtilles", "Blueberries")
        case .marshmallow: return T("Guimauves", "Marshmallows")
        case .pistachio: return T("Crème pistache", "Pistachio cream")
        case .ham: return T("Jambon", "Ham")
        case .cheese: return T("Fromage râpé", "Grated cheese")
        case .egg: return T("Œuf", "Egg")
        case .avocado: return T("Avocat", "Avocado")
        case .salmon: return T("Saumon", "Salmon")
        case .tomato: return T("Tomates", "Tomatoes")
        case .bacon: return T("Bacon", "Bacon")
        case .rocket: return T("Roquette", "Rocket")
        case .sourcream: return T("Crème fraîche", "Sour cream")
        case .chives: return T("Ciboulette", "Chives")
        case .cheesesauce: return T("Sauce cheddar", "Cheddar sauce")
        }
    }

    /// Salé (jambon, fromage…) ou sucré.
    var savory: Bool {
        switch self {
        case .ham, .cheese, .egg, .avocado, .salmon, .tomato, .bacon, .rocket, .sourcream, .chives, .cheesesauce: return true
        default: return false
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
    /// Une crêpe (dès le jour 20, avec la crêpière) plutôt qu'une gaufre.
    var crepe = false
    var name: String { T(fr, en) }
    var savory: Bool { layers.contains { $0.savory } }

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
        Recipe(id: "croquante", fr: "La croquante", en: "The crunchy one", layers: [.spread, .chocobar], day: 11),
        Recipe(id: "noisette", fr: "Noisette-croustille", en: "Hazelnut crunch", layers: [.spread, .wafer, .cream], day: 12),
        Recipe(id: "cookie", fr: "Cookie-glace", en: "Cookie & ice cream", layers: [.icecream, .cookie], day: 13),
        Recipe(id: "speculoos", fr: "Spéculoos-caramel", en: "Speculoos & caramel", layers: [.caramel, .speculoos], day: 14),
        Recipe(id: "jambonfromage", fr: "Gaufre jambon-fromage", en: "Ham & cheese waffle", layers: [.ham, .cheese], day: 15),
        Recipe(id: "coco", fr: "Coco-myrtille", en: "Coconut & blueberry", layers: [.cream, .blueberry, .coconut], day: 16),
        Recipe(id: "guimauve", fr: "Guimauve party", en: "Marshmallow party", layers: [.chocmelt, .marshmallow, .sprinkles], day: 17),
        Recipe(id: "brunch", fr: "Gaufre brunch", en: "Brunch waffle", layers: [.bacon, .egg], day: 18),
        Recipe(id: "pistache", fr: "Pistache-fraise", en: "Pistachio & strawberry", layers: [.pistachio, .strawberry], day: 19),
        Recipe(id: "crepesucre", fr: "Crêpe au sucre", en: "Sugar crêpe", layers: [.sugar], day: 20, crepe: true),
        Recipe(id: "crepechoco", fr: "Crêpe choco-banane", en: "Choc & banana crêpe", layers: [.spread, .banana], day: 20, crepe: true),
        Recipe(id: "complete", fr: "Crêpe complète", en: "Ham, cheese & egg crêpe", layers: [.ham, .cheese, .egg], day: 21, crepe: true),
        Recipe(id: "avosaumon", fr: "Gaufre avocat-saumon", en: "Avocado & salmon waffle", layers: [.avocado, .salmon], day: 22),
        Recipe(id: "nordique", fr: "Crêpe nordique", en: "Nordic crêpe", layers: [.sourcream, .salmon, .chives], day: 23, crepe: true),
        Recipe(id: "italienne", fr: "Gaufre à l'italienne", en: "Italian waffle", layers: [.tomato, .cheese, .rocket], day: 24),
        Recipe(id: "crepecaramel", fr: "Crêpe caramel-amandes", en: "Caramel & almond crêpe", layers: [.caramel, .almonds], day: 25, crepe: true),
        Recipe(id: "cheddar", fr: "Crêpe bacon-cheddar", en: "Bacon & cheddar crêpe", layers: [.bacon, .cheesesauce], day: 26, crepe: true),
        Recipe(id: "crepetotale", fr: "La crêpe totale", en: "The works crêpe", layers: [.spread, .strawberry, .banana, .cream], day: 27, crepe: true),
        Recipe(id: "crepenoisette", fr: "Crêpe noisette-croustille", en: "Hazelnut crunch crêpe", layers: [.spread, .wafer], day: 28, crepe: true),
        Recipe(id: "crepebarre", fr: "Crêpe choco-caramel", en: "Choc-caramel crêpe", layers: [.chocmelt, .chocobar], day: 28, crepe: true),
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
    func image(crepe: Bool) -> String { crepe ? "crepe\(rawValue)" : image }

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

/// La note d'une gaufre : chaque critère sur 5, et la note finale (0 à 5 étoiles).
struct Grade {
    var recipe = 0
    var cooking = 0
    var speed = 0
    var total: Int {
        guard cooking > 0 else { return 0 }   // brûlée : zéro
        return Int((Double(recipe + cooking + speed) / 3).rounded())
    }
}

struct Served {
    let stars: Int
    let coins: Int
    let doneness: Doneness
    let comment: String
    var combo: Int = 0
    var grade = Grade()
    var recipeID = ""
}

/// Ce qu'on garde d'une partie à l'autre.
@Observable
final class Career {
    private(set) var stars: [Int: Int]
    private(set) var bestRush: Int
    /// Les pièces gagnées en tout (pour la déco).
    private(set) var wallet: Int
    /// Meilleure note (sur 5) de chaque recette ; 5 = carte dorée.
    private(set) var recipeBest: [String: Int]
    private(set) var creations: [Creation]

    init() {
        let d = UserDefaults.standard
        var s: [Int: Int] = [:]
        for day in 1...Kitchen.lastDay { let v = d.integer(forKey: "waffle.stars.\(day)"); if v > 0 { s[day] = v } }
        stars = s
        bestRush = d.integer(forKey: "waffle.rush")
        wallet = d.integer(forKey: "waffle.wallet")
        recipeBest = (d.dictionary(forKey: "waffle.recipes") as? [String: Int]) ?? [:]
        creations = (d.data(forKey: "waffle.creations")).flatMap { try? JSONDecoder().decode([Creation].self, from: $0) } ?? []
    }

    func earn(_ n: Int) {
        guard n > 0 else { return }
        wallet += n
        UserDefaults.standard.set(wallet, forKey: "waffle.wallet")
    }

    func spend(_ n: Int) -> Bool {
        guard wallet >= n else { return false }
        wallet -= n
        UserDefaults.standard.set(wallet, forKey: "waffle.wallet")
        return true
    }

    func recordRecipe(_ id: String, stars n: Int) {
        guard !id.isEmpty, n > (recipeBest[id] ?? 0) else { return }
        recipeBest[id] = n
        UserDefaults.standard.set(recipeBest, forKey: "waffle.recipes")
    }

    var goldenCards: Int { recipeBest.values.filter { $0 >= 5 }.count }

    func save(_ c: Creation) {
        creations.insert(c, at: 0)
        if creations.count > 60 { creations.removeLast(creations.count - 60) }
        UserDefaults.standard.set(try? JSONEncoder().encode(creations), forKey: "waffle.creations")
    }

    func delete(_ c: Creation) {
        creations.removeAll { $0.id == c.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(creations), forKey: "waffle.creations")
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

    /// Les trophées de la Gaufre d'Or (jours 10, 20, 30).
    private(set) var trophies: Set<Int> = Set(UserDefaults.standard.array(forKey: "waffle.trophies") as? [Int] ?? [])
    func winTrophy(_ day: Int) {
        trophies.insert(day)
        UserDefaults.standard.set(Array(trophies), forKey: "waffle.trophies")
    }
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
        /// Atelier libre : la création est finie, on la nomme.
        case created
    }

    static let lastDay = 30
    /// Les concours de la Gaufre d'Or : bronze, argent, or.
    static let contestDays = [10, 20, 30]
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
    /// Écart au centre du vert quand on a rouvert (0 = pile au milieu).
    @ObservationIgnored private var cookOffset: Double = 0.5
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

    /// Atelier libre : pas de client, pas de chrono, toutes les garnitures.
    let free: Bool
    /// Le tutoriel : la première gaufre du jour 1 (curseur plus lent, client patient, chrono arrêté).
    private(set) var tutorial: Bool
    static let tutorialKey = "waffle.tutorialDone"
    static let freeLayers = 6

    init(day: Int, rush: Bool = false, free: Bool = false) {
        self.day = rush || free ? Kitchen.lastDay : day
        self.rush = rush
        self.free = free
        self.tutorial = !rush && !free && day == 1 && !UserDefaults.standard.bool(forKey: Self.tutorialKey)
        self.hasHinge = UserDefaults.standard.bool(forKey: Self.hingeKey)
    }

    /// Le conseil du tutoriel, étape par étape.
    var coach: String? {
        guard tutorial else { return nil }
        switch phase {
        case .pour: return T("1 · Touche le pichet pour verser la pâte sur le gaufrier.", "1 · Tap the jug to pour the batter.")
        case .poured: return hasHinge ? T("2 · Ferme ton Duo : ça ferme le gaufrier et la gaufre cuit.", "2 · Close your Duo: it closes the waffle iron and the waffle cooks.")
                                      : T("2 · Ferme le gaufrier pour cuire la gaufre.", "2 · Close the waffle iron to cook.")
        case .cooking: return T("3 · Le curseur va et vient dans la jauge. Rouvre ton Duo quand il est dans le vert : la gaufre sera dorée !", "3 · The cursor moves along the gauge. Open your Duo when it's in the green: the waffle will be golden!")
        case .topping: return T("4 · Ajoute les garnitures dans l'ordre du ticket.", "4 · Add the toppings in the order on the ticket.")
        default: return nil
        }
    }

    // MARK: Le menu du jour

    var recipes: [Recipe] { Recipe.all.filter { $0.day <= day } }
    var isContest: Bool { !rush && !free && Self.contestDays.contains(day) }
    var isCrepe: Bool { order?.recipe.crepe ?? false }

    /// Les garnitures du plateau (dans un ordre fixe).
    var tray: [Ingredient] {
        if free { return Ingredient.allCases }
        let used = Set(recipes.flatMap(\.layers))
        return Ingredient.allCases.filter { used.contains($0) }
    }

    var target: Int { Int(Double(50 + day * 14) * (isContest ? 1.25 : 1)) }
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
        let base = rush ? max(0.05, 0.085 - Double(servedCount) * 0.002) : max(0.05, 0.095 - Double(min(day, 20)) * 0.0022)
        return base * (1 + Shop.shared.iron.green) * (tutorial ? 1.6 : 1)
    }
    var yellowHalf: Double { greenHalf + 0.14 }
    /// Durée d'un aller du curseur, en secondes (il accélère avec les jours).
    var sweepTime: Double {
        (rush ? max(0.7, 1.5 - Double(servedCount) * 0.04) : max(0.75, 1.7 - Double(min(day, 20)) * 0.05)) * (tutorial ? 1.6 : 1)
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
        if free { newCreation() } else { newOrder() }
    }

    /// Atelier libre : une nouvelle gaufre à inventer.
    func newCreation() {
        orderNumber += 1
        let blank = Recipe(id: "", fr: "Création libre", en: "Free creation", layers: [], day: 1)
        order = Order(number: orderNumber, recipe: blank, layers: [], wish: .golden, customer: -1, patience: .infinity)
        stack = []
        cursor = 0
        cooked = .raw
        mistakes = 0
        patienceLeft = 1
        phase = .pour
    }

    /// Atelier libre : on a fini de garnir.
    func finishCreation() {
        guard free, phase == .topping else { return }
        phase = .created
        Sound.play(.win, volume: 0.6)
        Haptics.success()
    }

    /// Le mot du chef sur une création libre.
    var chefComment: String {
        let s = Set(stack)
        if cooked == .burnt { return T("Euh… c'est du charbon !", "Uh… that's charcoal!") }
        if cooked == .raw { return T("Un peu molle, mais l'idée est là !", "A bit soft, but nice idea!") }
        if stack.isEmpty { return T("Nature : la classique !", "Plain: a classic!") }
        if stack.count >= 5 { return T("Une montagne de gourmandise !", "A mountain of treats!") }
        if s.contains(.spread) && s.contains(.banana) { return T("Le duo gagnant !", "The winning duo!") }
        if s.contains(.strawberry) && s.contains(.cream) { return T("Un grand classique, parfait !", "A true classic, perfect!") }
        if s.contains(.icecream) { return T("Chaud-froid : bien vu !", "Hot and cold: nice!") }
        let all = [T("Le chef approuve !", "The chef approves!"), T("Audacieux !", "Bold!"), T("Ça donne faim !", "Looks delicious!")]
        return all[stack.count % all.count]
    }

    private func newOrder() {
        // Les recettes du jour reviennent plus souvent.
        let pool = recipes
        let weights = pool.map { $0.day == day || $0.day == day - 1 ? 2.5 : 1.0 }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var recipe = pool[0]
        for (r, w) in zip(pool, weights) {
            if roll < w { recipe = r; break }
            roll -= w
        }
        var layers = recipe.layers
        // Dès le jour 11 (et en rush), un client sur trois veut un supplément.
        if day >= 11 && Int.random(in: 0..<3) == 0 {
            let extras: [Ingredient] = recipe.savory ? [.cheese, .chives, .egg] : [.sugar, .cream, .sprinkles, .chocmelt]
            let extra: Ingredient = extras.filter { !layers.contains($0) }.randomElement() ?? extras[0]
            layers.append(extra)
        }
        let wish: Doneness = .golden
        var customer = Int.random(in: 0..<5)
        if customer == lastCustomer { customer = (customer + 1) % 5 }
        lastCustomer = customer
        orderNumber += 1
        let speedUp = rush ? min(9, Double(servedCount) * 0.35) : 0
        let patience = (max(16, 30 - Double(min(day, 20)) * 0.7 - speedUp) + 2.5 * Double(layers.count)) * Shop.shared.patienceFactor
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
        if free {
            guard stack.count < Self.freeLayers else { say(T("Elle est déjà bien garnie !", "It's already loaded!")); return }
            stack.append(ing)
            Sound.play(.pop, volume: 0.6)
            Haptics.tap()
            return
        }
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

    static let hingeKey = "waffle.hasHinge"

    func hinge(closed status: Bool?, degrees: Double?) {
        #if DEBUG
        // Captures : le simulateur donne un angle de charnière qui fermerait le gaufrier.
        if UserDefaults.standard.string(forKey: "shot") != nil { return }
        #endif
        // Un instant sans charnière (pendant le passage d'un écran à l'autre) : on ne change rien.
        guard status != nil || degrees != nil else { return }
        if !hasHinge {
            hasHinge = true
            UserDefaults.standard.set(true, forKey: Self.hingeKey)
        }
        if let degrees {
            // Fermé sous 12° ; on le considère rouvert dès 16°, pour que le curseur s'arrête au tout début du geste.
            if closed { if degrees > 16 { setClosed(false) } } else if degrees < 12 || status == true { setClosed(true) }
        } else if let status {
            setClosed(status)
        }
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
                cookOffset = abs(cursor - 0.5)
                if cooked == .burnt && !free {
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

    /// La note détaillée : recette, cuisson, rapidité.
    private func grade() -> Grade {
        var g = Grade()
        g.recipe = max(1, 5 - mistakes)
        switch cooked {
        case .golden: g.cooking = cookOffset <= greenHalf * 0.45 ? 5 : 4
        case .light, .dark: g.cooking = 3
        case .raw: g.cooking = 1
        case .burnt: g.cooking = 0
        }
        g.speed = patienceLeft > 0.66 ? 5 : patienceLeft > 0.5 ? 4 : patienceLeft > 0.33 ? 3 : patienceLeft > 0.15 ? 2 : 1
        return g
    }

    private func serve() {
        guard let order else { return }
        let d = cooked
        let g = grade()
        let stars = g.total
        let comment: String
        switch stars {
        case 5: comment = T("Parfaite !", "Perfect!")
        case 4: comment = T("Excellente !", "Excellent!")
        case 3: comment = d == .light ? T("Un peu pâle…", "A bit pale…") : d == .dark ? T("Un peu trop cuite…", "A bit overdone…") : T("Pas mal !", "Not bad!")
        case 1, 2: comment = d == .raw ? T("Pas assez cuite !", "Undercooked!") : T("Bof…", "Meh…")
        default: comment = T("Brûlée !", "Burnt!")
        }
        let base = 6 + 3 * order.layers.count
        let mult = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0][stars]
        let tip = stars >= 4 ? Int((patienceLeft * 8 * Shop.shared.tipFactor).rounded()) : 0
        if stars == 5 { combo += 1; bestCombo = max(bestCombo, combo) } else { combo = 0 }
        // Combo : +25 % par parfaite d'affilée (jusqu'à ×2).
        let comboBonus = 1 + 0.25 * Double(min(4, max(0, combo - 1)))
        let earned = Int(((Double(base) * mult + Double(tip)) * comboBonus * Shop.shared.coinFactor).rounded())
        coins += earned
        servedCount += 1
        if stars == 5 { perfectCount += 1 }
        if stars == 0 && rush { lostCount += 1 }
        last = Served(stars: stars, coins: earned, doneness: d, comment: comment, combo: stars == 5 ? combo : 0, grade: g, recipeID: order.recipe.id)
        if tutorial {
            tutorial = false
            UserDefaults.standard.set(true, forKey: Self.tutorialKey)
            say(T("Bravo ! Maintenant, sers un max de clients avant la fin du chrono !", "Well done! Now serve as many customers as you can before time runs out!"))
        }
        phase = .served
        nextIn = 2.2
        Sound.play(stars >= 3 ? .win : .wrong, volume: 0.6)
        if stars >= 3 { Haptics.success() } else { Haptics.error() }
    }

    // MARK: Le temps

    func tick(_ dt: Double) {
        if frozen { return }
        if hintLeft > 0 {
            hintLeft -= dt
            if hintLeft <= 0 { hint = nil }
        }
        guard phase != .ready && phase != .dayOver else { return }
        if free {
            if phase == .cooking {
                cursor += cursorDir * dt / sweepTime
                if cursor >= 1 { cursor = 1; cursorDir = -1 }
                if cursor <= 0 { cursor = 0; cursorDir = 1 }
            }
            return
        }
        if !rush && !tutorial && phase != .served && phase != .gone {
            shiftLeft = max(0, shiftLeft - dt)
        }
        switch phase {
        case .pour, .poured, .cooking, .topping:
            if let order, !tutorial { patienceLeft = max(0, patienceLeft - dt / order.patience) }
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
        case .served: return (last?.stars ?? 0) >= 3 ? "happy" : "angry"
        case .gone: return "angry"
        default: return patienceLeft < 0.3 ? "angry" : "wait"
        }
    }

    // MARK: Démo (captures)

    func demo(_ step: String) {
        start()
        frozen = step != "summary"
        if free && step == "created" {
            phase = .topping; cooked = .golden; stack = [.spread, .banana, .cream, .sprinkles]; phase = .created; return
        }
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
            cookOffset = 0
            stack = order.layers
            serve()
        case "free":
            phase = .topping
            cooked = .golden
            stack = [.strawberry, .cream, .sprinkles]
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
