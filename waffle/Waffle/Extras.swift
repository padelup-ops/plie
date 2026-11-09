import SwiftUI

// MARK: - Créations libres

struct Creation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var layers: [String]
    var doneness: Int
    var date = Date()

    var ingredients: [Ingredient] { layers.compactMap(Ingredient.init(rawValue:)) }
    var cooked: Doneness { Doneness(rawValue: doneness) ?? .golden }
}

// MARK: - La déco de la cuisine
//
// Le mur, le store du comptoir, le plan de travail et la couleur du gaufrier.
// Le premier choix de chaque est offert ; les autres s'achètent avec les pièces gagnées.

struct DecorChoice: Identifiable {
    let id: Int
    let fr: String
    let en: String
    let colors: [UInt32]
    let price: Int
    var name: String { T(fr, en) }
}

enum DecorKind: String, CaseIterable, Identifiable {
    case wall, awning, worktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wall: return T("Le mur", "Wall")
        case .awning: return T("Le comptoir", "Counter")
        case .worktop: return T("Le plan de travail", "Worktop")
        }
    }
    var choices: [DecorChoice] {
        switch self {
        case .wall: return [
            DecorChoice(id: 0, fr: "Crème", en: "Cream", colors: [0xF4E6CF, 0xFFFFFF], price: 0),
            DecorChoice(id: 1, fr: "Menthe", en: "Mint", colors: [0xCFF1E6, 0xE8FFF7], price: 60),
            DecorChoice(id: 2, fr: "Rose", en: "Pink", colors: [0xFAD6E2, 0xFFEFF5], price: 90),
            DecorChoice(id: 3, fr: "Ciel", en: "Sky", colors: [0xCFE6FA, 0xEEF7FF], price: 120),
            DecorChoice(id: 4, fr: "Lilas", en: "Lilac", colors: [0xE2D6FA, 0xF4EEFF], price: 160),
            DecorChoice(id: 5, fr: "Nuit", en: "Night", colors: [0x2E3350, 0x46507A], price: 220),
        ]
        case .awning: return [
            DecorChoice(id: 0, fr: "Rouge", en: "Red", colors: [0xE8453C], price: 0),
            DecorChoice(id: 1, fr: "Bleu", en: "Blue", colors: [0x3C7FE8], price: 50),
            DecorChoice(id: 2, fr: "Vert", en: "Green", colors: [0x3DB45A], price: 80),
            DecorChoice(id: 3, fr: "Orange", en: "Orange", colors: [0xF28A2E], price: 110),
            DecorChoice(id: 4, fr: "Violet", en: "Purple", colors: [0x8E5BE0], price: 150),
            DecorChoice(id: 5, fr: "Noir", en: "Black", colors: [0x2B2830], price: 200),
        ]
        case .worktop: return [
            DecorChoice(id: 0, fr: "Crème", en: "Cream", colors: [0xEDE4D6, 0xDCCDB8], price: 0),
            DecorChoice(id: 1, fr: "Bois", en: "Wood", colors: [0xE2AE72, 0xC2834A], price: 70),
            DecorChoice(id: 2, fr: "Marbre", en: "Marble", colors: [0xF2F2F5, 0xD3D4DD], price: 100),
            DecorChoice(id: 3, fr: "Rose", en: "Pink", colors: [0xF7D3DE, 0xE9B3C4], price: 130),
            DecorChoice(id: 4, fr: "Menthe", en: "Mint", colors: [0xD0EEDF, 0xA9D9C2], price: 170),
            DecorChoice(id: 5, fr: "Ardoise", en: "Slate", colors: [0x5A6070, 0x3E4350], price: 230),
        ]
        }
    }
}

@Observable
final class Decor {
    static let shared = Decor()

    private(set) var chosen: [String: Int]
    private(set) var owned: Set<String>

    private init() {
        let d = UserDefaults.standard
        chosen = (d.dictionary(forKey: "waffle.decor") as? [String: Int]) ?? [:]
        owned = Set(d.stringArray(forKey: "waffle.decor.owned") ?? [])
    }

    func choice(_ k: DecorKind) -> DecorChoice {
        let c = k.choices
        return c.first { $0.id == (chosen[k.rawValue] ?? 0) } ?? c[0]
    }

    func isOwned(_ k: DecorKind, _ c: DecorChoice) -> Bool { c.price == 0 || owned.contains("\(k.rawValue).\(c.id)") }

    func select(_ k: DecorKind, _ c: DecorChoice) {
        chosen[k.rawValue] = c.id
        UserDefaults.standard.set(chosen, forKey: "waffle.decor")
    }

    func unlock(_ k: DecorKind, _ c: DecorChoice) {
        owned.insert("\(k.rawValue).\(c.id)")
        UserDefaults.standard.set(Array(owned), forKey: "waffle.decor.owned")
        select(k, c)
    }

    func color(_ k: DecorKind, _ i: Int = 0) -> Color {
        let c = choice(k).colors
        return Color(hex: c[min(i, c.count - 1)])
    }
}

struct DecorView: View {
    @Environment(Career.self) private var progress
    let onClose: () -> Void
    @State private var tab = 0
    private var decor: Decor { Decor.shared }
    private var shop: Shop { Shop.shared }

    var body: some View {
        ZStack {
            Sunburst()
            VStack(spacing: 12) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .black)).frame(width: 40, height: 38)
                    }
                    .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line, radius: 19, depth: 3))
                    Spacer()
                    Pill {
                        Image("coin").resizable().frame(width: 22, height: 22)
                        Text("\(progress.wallet)").monospacedDigit()
                    }
                }
                .padding(.horizontal, 16)
                Outlined(text: T("Boutique", "Shop"), size: 40)
                Picker("", selection: $tab) {
                    Text(T("Gaufriers", "Irons")).tag(0)
                    Text(T("Bonus", "Boosts")).tag(1)
                    Text(T("Déco", "Decor")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                if tab == 0 {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) { ForEach(IronModel.all) { ironRow($0) } }
                            .padding(.horizontal, 18).padding(.bottom, 30)
                    }
                } else if tab == 1 {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) { ForEach(Upgrade.all) { upgradeRow($0) } }
                            .padding(.horizontal, 18).padding(.bottom, 30)
                    }
                } else {
                // Aperçu
                DecorPreview()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.line, lineWidth: 3))
                    .padding(.horizontal, 20)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(DecorKind.allCases) { kind in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(kind.title).font(.toon(18)).foregroundStyle(Ink.line)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(kind.choices) { c in swatch(kind, c) }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                }
            }
            .padding(.top, 16)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Ink.paper))
            .background(RoundedRectangle(cornerRadius: 20).fill(Ink.line).offset(y: 4))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Ink.line, lineWidth: 3))
    }

    private func ironRow(_ m: IronModel) -> some View {
        let owned = shop.owns(m)
        let equipped = shop.ironID == m.id
        return card {
            HStack(spacing: 12) {
                IronSwatch(model: m)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.name).font(.toon(17)).foregroundStyle(Ink.line)
                        Text(m.rarity.name).font(.toon(10, .black)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(m.rarity.color))
                    }
                    ForEach(m.perks, id: \.self) { Text($0).font(.toon(12, .bold)).foregroundStyle(Ink.line.opacity(0.7)) }
                }
                Spacer(minLength: 4)
                Button {
                    if owned { shop.equip(m); Sound.play(.tock, volume: 0.5) }
                    else if m.trophy { Sound.play(.wrong, volume: 0.5) }
                    else if progress.spend(m.price) { shop.give(m); Sound.play(.win, volume: 0.6); Haptics.success() }
                    else { Sound.play(.wrong, volume: 0.5); Haptics.error() }
                } label: {
                    Group {
                        if equipped { Text(T("Équipé", "Equipped")) }
                        else if owned { Text(T("Choisir", "Use")) }
                        else if m.trophy { Label(T("Jour 30", "Day 30"), systemImage: "trophy.fill") }
                        else { HStack(spacing: 3) { Image("coin").resizable().frame(width: 16, height: 16); Text("\(m.price)") } }
                    }
                    .font(.toon(13)).frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(ToonButton(color: equipped ? Ink.paper : (owned ? Ink.green : (m.trophy ? Color(hex: 0xC9C2B8) : Ink.orange)),
                                        text: equipped ? Ink.line : .white, radius: 14, depth: 3))
                .disabled(equipped)
            }
        }
    }

    private func upgradeRow(_ u: Upgrade) -> some View {
        let owned = shop.owns(u)
        return card {
            HStack(spacing: 12) {
                Image(systemName: u.icon).font(.system(size: 26, weight: .black)).foregroundStyle(Ink.orange)
                    .frame(width: 56, height: 56).background(Circle().fill(Color(hex: 0xFFF1D6)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(u.name).font(.toon(17)).foregroundStyle(Ink.line)
                    Text(u.detail).font(.toon(12, .bold)).foregroundStyle(Ink.line.opacity(0.7))
                }
                Spacer(minLength: 4)
                Button {
                    if !owned, progress.spend(u.price) { shop.buy(u); Sound.play(.win, volume: 0.6); Haptics.success() }
                    else if !owned { Sound.play(.wrong, volume: 0.5); Haptics.error() }
                } label: {
                    Group {
                        if owned { Label(T("Acheté", "Owned"), systemImage: "checkmark") }
                        else { HStack(spacing: 3) { Image("coin").resizable().frame(width: 16, height: 16); Text("\(u.price)") } }
                    }
                    .font(.toon(13)).frame(minWidth: 70, minHeight: 36)
                }
                .buttonStyle(ToonButton(color: owned ? Ink.paper : Ink.orange, text: owned ? Ink.line : .white, radius: 14, depth: 3))
                .disabled(owned)
            }
        }
    }

    private func swatch(_ kind: DecorKind, _ c: DecorChoice) -> some View {
        let owned = decor.isOwned(kind, c)
        let selected = decor.choice(kind).id == c.id
        return Button {
            if owned { decor.select(kind, c); Sound.play(.tock, volume: 0.5) }
            else if progress.spend(c.price) { decor.unlock(kind, c); Sound.play(.win, volume: 0.6); Haptics.success() }
            else { Sound.play(.wrong, volume: 0.5); Haptics.error() }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: c.colors.map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom))
                    if !owned {
                        Color.black.opacity(0.25).clipShape(RoundedRectangle(cornerRadius: 16))
                        Image(systemName: "lock.fill").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                    }
                    RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Ink.orange : Ink.line, lineWidth: selected ? 5 : 3)
                }
                .frame(width: 70, height: 58)
                Text(c.name).font(.toon(12, .bold)).foregroundStyle(Ink.line)
                if owned {
                    Text(selected ? T("Choisi", "On") : " ").font(.toon(11, .bold)).foregroundStyle(Ink.orange)
                } else {
                    HStack(spacing: 2) {
                        Image("coin").resizable().frame(width: 13, height: 13)
                        Text("\(c.price)").font(.toon(11, .bold)).foregroundStyle(progress.wallet >= c.price ? Ink.line : Ink.red)
                    }
                }
            }
        }
        .buttonStyle(Squish())
        .accessibilityLabel(c.name)
    }
}

/// Un petit bout de cuisine avec la déco choisie.
struct DecorPreview: View {
    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack(alignment: .topLeading) {
                WallBackground().frame(width: W, height: H * 0.5)
                Counter().frame(width: W, height: H * 0.18).offset(y: H * 0.42)
                Worktop().frame(width: W, height: H * 0.42).offset(y: H * 0.58)
                IronPlate(hingeEdge: .top)
                    .frame(width: W * 0.42, height: H * 0.36)
                    .position(x: W / 2, y: H * 0.78)
                Image("waffle2").resizable().scaledToFit().frame(width: H * 0.38).position(x: W / 2, y: H * 0.77)
            }
        }
    }
}

// MARK: - La boutique : les gaufriers et les améliorations
//
// Les gaufriers ont une rareté et des atouts : une zone verte plus large (cuisson plus facile),
// des clients plus patients (il chauffe plus vite), plus de pièces. Le gaufrier en or ne s'achète pas :
// il se gagne au dernier concours de la Gaufre d'Or (jour 30).

enum Rarity: Int {
    case common, rare, epic, legendary
    var name: String {
        switch self {
        case .common: return T("Commun", "Common")
        case .rare: return T("Rare", "Rare")
        case .epic: return T("Épique", "Epic")
        case .legendary: return T("Légendaire", "Legendary")
        }
    }
    var color: Color {
        switch self {
        case .common: return Color(hex: 0x8A8F99)
        case .rare: return Color(hex: 0x3C7FE8)
        case .epic: return Color(hex: 0x8E5BE0)
        case .legendary: return Color(hex: 0xE0A21E)
        }
    }
}

struct IronModel: Identifiable {
    let id: String
    let fr: String
    let en: String
    let rarity: Rarity
    /// Corps clair, corps foncé, garnitures.
    let colors: [UInt32]
    let price: Int
    /// Zone verte en plus (0.15 = +15 %).
    var green = 0.0
    /// Clients plus patients (le gaufrier chauffe plus vite).
    var calm = 0.0
    /// Pièces en plus.
    var bonus = 0.0
    var shine = false
    /// Se gagne au concours du jour 30 (ne s'achète pas).
    var trophy = false
    var name: String { T(fr, en) }

    static let all: [IronModel] = [
        IronModel(id: "classic", fr: "Le Classique", en: "The Classic", rarity: .common, colors: [0x7FE0D6, 0x2FA79E, 0xF4F6FA], price: 0),
        IronModel(id: "cherry", fr: "Cerise", en: "Cherry", rarity: .common, colors: [0xFF8A80, 0xD9433A, 0xF4F6FA], price: 120, bonus: 0.05),
        IronModel(id: "lemon", fr: "Citron", en: "Lemon", rarity: .common, colors: [0xFFE07A, 0xE0A92A, 0xF4F6FA], price: 160, bonus: 0.05),
        IronModel(id: "candy", fr: "Bonbon", en: "Candy", rarity: .common, colors: [0xFFB3D9, 0xE0679F, 0xF4F6FA], price: 200, bonus: 0.05),
        IronModel(id: "retro", fr: "Le Rétro", en: "The Retro", rarity: .rare, colors: [0xF2E6D0, 0xC9A97A, 0xD9DEE6], price: 450, green: 0.15),
        IronModel(id: "turbo", fr: "Le Turbo", en: "The Turbo", rarity: .rare, colors: [0x4A505C, 0x1E2128, 0x3DF2C8], price: 650, calm: 0.2),
        IronModel(id: "pro", fr: "Le Pro Double", en: "The Pro Double", rarity: .epic, colors: [0xA9BEE0, 0x5A6F96, 0xF4F6FA], price: 1200, green: 0.25, bonus: 0.1),
        IronModel(id: "diamond", fr: "Le Diamant", en: "The Diamond", rarity: .epic, colors: [0xD6F4FF, 0x6FBCE0, 0xFFFFFF], price: 2000, green: 0.2, calm: 0.15, bonus: 0.15, shine: true),
        IronModel(id: "gold", fr: "La Gaufre d'Or", en: "The Golden Waffle", rarity: .legendary, colors: [0xFFE27A, 0xD39A12, 0xFFF6CC], price: 0, green: 0.4, calm: 0.2, bonus: 0.25, shine: true, trophy: true),
    ]

    var perks: [String] {
        var p: [String] = []
        if green > 0 { p.append(T("Zone verte +\(Int(green * 100)) %", "Green zone +\(Int(green * 100))%")) }
        if calm > 0 { p.append(T("Clients patients +\(Int(calm * 100)) %", "Patient customers +\(Int(calm * 100))%")) }
        if bonus > 0 { p.append(T("Pièces +\(Int(bonus * 100)) %", "Coins +\(Int(bonus * 100))%")) }
        if p.isEmpty { p.append(T("Le gaufrier de départ", "The starter iron")) }
        return p
    }
}

struct Upgrade: Identifiable {
    let id: String
    let fr: String
    let en: String
    let detailFR: String
    let detailEN: String
    let icon: String
    let price: Int
    var name: String { T(fr, en) }
    var detail: String { T(detailFR, detailEN) }

    static let all: [Upgrade] = [
        Upgrade(id: "tips", fr: "Pot à pourboires", en: "Tip jar", detailFR: "Pourboires +50 %", detailEN: "Tips +50%", icon: "dollarsign.circle.fill", price: 250),
        Upgrade(id: "radio", fr: "Petite radio", en: "Little radio", detailFR: "Clients patients +15 %", detailEN: "Patient customers +15%", icon: "radio.fill", price: 350),
        Upgrade(id: "sign", fr: "Enseigne lumineuse", en: "Neon sign", detailFR: "Pièces +10 %", detailEN: "Coins +10%", icon: "lightbulb.max.fill", price: 500),
    ]
}

@Observable
final class Shop {
    static let shared = Shop()

    private(set) var ironID: String
    private(set) var ownedIrons: Set<String>
    private(set) var upgrades: Set<String>

    private init() {
        let d = UserDefaults.standard
        ironID = d.string(forKey: "waffle.iron") ?? "classic"
        ownedIrons = Set(d.stringArray(forKey: "waffle.irons") ?? ["classic"])
        upgrades = Set(d.stringArray(forKey: "waffle.upgrades") ?? [])
        // L'ancienne couleur choisie dans la déco devient un gaufrier.
        if let old = (d.dictionary(forKey: "waffle.decor") as? [String: Int])?["iron"], old > 0 {
            let map = [1: "cherry", 2: "lemon", 3: "candy"]
            if let id = map[old] { ownedIrons.insert(id); ironID = id }
        }
    }

    var iron: IronModel { IronModel.all.first { $0.id == ironID } ?? IronModel.all[0] }
    func ironColor(_ i: Int) -> Color { Color(hex: iron.colors[min(i, iron.colors.count - 1)]) }

    func owns(_ m: IronModel) -> Bool { m.price == 0 && !m.trophy || ownedIrons.contains(m.id) }
    func owns(_ u: Upgrade) -> Bool { upgrades.contains(u.id) }

    func equip(_ m: IronModel) {
        ironID = m.id
        UserDefaults.standard.set(m.id, forKey: "waffle.iron")
    }

    func give(_ m: IronModel) {
        ownedIrons.insert(m.id)
        UserDefaults.standard.set(Array(ownedIrons), forKey: "waffle.irons")
        equip(m)
    }

    func buy(_ u: Upgrade) {
        upgrades.insert(u.id)
        UserDefaults.standard.set(Array(upgrades), forKey: "waffle.upgrades")
    }

    var patienceFactor: Double { (1 + iron.calm) * (owns(Upgrade.all[1]) ? 1.15 : 1) }
    var coinFactor: Double { (1 + iron.bonus) * (owns(Upgrade.all[2]) ? 1.1 : 1) }
    var tipFactor: Double { owns(Upgrade.all[0]) ? 1.5 : 1 }
}

/// Un petit gaufrier aux couleurs du modèle (pour la boutique).
struct IronSwatch: View {
    let model: IronModel

    var body: some View {
        let c = model.colors.map { Color(hex: $0) }
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Ink.line).offset(y: 3)
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [c[0], c[1]], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16).strokeBorder(Ink.line, lineWidth: 3)
            RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x2B2830))
                .overlay(
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x57525E)) } }
                        }
                    }
                    .padding(5)
                )
                .padding(10)
            Capsule().fill(c[2]).overlay(Capsule().strokeBorder(Ink.line, lineWidth: 2)).frame(width: 26, height: 7).offset(y: -27)
            if model.shine {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: c[1], radius: 3).offset(x: 24, y: -18)
            }
        }
        .frame(width: 84, height: 62)
    }
}

// MARK: - Le livre de recettes et les créations

struct RecipeBookView: View {
    @Environment(Career.self) private var progress
    let onClose: () -> Void
    @State private var tab = 0

    var body: some View {
        ZStack {
            Sunburst()
            VStack(spacing: 12) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .black)).frame(width: 40, height: 38)
                    }
                    .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line, radius: 19, depth: 3))
                    Spacer()
                    Pill {
                        Image(systemName: "star.fill").foregroundStyle(Ink.gold)
                        Text("\(progress.goldenCards) / \(Recipe.all.count)").monospacedDigit()
                    }
                }
                .padding(.horizontal, 16)
                Outlined(text: T("Recettes", "Recipes"), size: 40)
                Picker("", selection: $tab) {
                    Text(T("Le menu", "Menu")).tag(0)
                    Text(T("Mes créations", "My creations")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 30)
                ScrollView(showsIndicators: false) {
                    if tab == 0 {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(Recipe.all) { r in RecipeCard(recipe: r, best: progress.recipeBest[r.id] ?? 0, open: progress.isOpen(r.day)) }
                        }
                        .padding(16)
                    } else if progress.creations.isEmpty {
                        Text(T("Invente ta première gaufre dans l'atelier libre !", "Invent your first waffle in the free kitchen!"))
                            .font(.toon(16, .bold)).foregroundStyle(Ink.line.opacity(0.7)).multilineTextAlignment(.center)
                            .padding(30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(progress.creations) { c in
                                CreationCard(creation: c)
                                    .contextMenu {
                                        Button(role: .destructive) { progress.delete(c) } label: { Label(T("Supprimer", "Delete"), systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.top, 16)
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    let best: Int
    let open: Bool

    var body: some View {
        let gold = best >= 5
        VStack(spacing: 6) {
            ZStack {
                Image(open ? (recipe.crepe ? "crepe2" : "waffle2") : (recipe.crepe ? "crepe0" : "waffle0")).resizable().scaledToFit()
                if open { ForEach(Array(recipe.layers.enumerated()), id: \.offset) { _, i in Image(i.image).resizable().scaledToFit() } }
            }
            .frame(width: 96, height: 96)
            .saturation(open ? 1 : 0)
            .opacity(open ? 1 : 0.4)
            Text(open ? recipe.name : "???").font(.toon(15)).foregroundStyle(Ink.line).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(i < best ? "star_on" : "star_off").resizable().frame(width: 18, height: 18)
                }
            }
            Text(open ? (gold ? T("Carte dorée", "Golden card") : T("Jour \(recipe.day)", "Day \(recipe.day)")) : T("Jour \(recipe.day)", "Day \(recipe.day)"))
                .font(.toon(11, .bold)).foregroundStyle(gold ? Color(hex: 0xA8601F) : Ink.line.opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(gold ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xF5C24A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                           : AnyShapeStyle(Ink.paper))
        )
        .background(RoundedRectangle(cornerRadius: 18).fill(Ink.line).offset(y: 4))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(gold ? Color(hex: 0xC98A1E) : Ink.line, lineWidth: 3))
    }
}

struct CreationCard: View {
    let creation: Creation

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(creation.cooked.image).resizable().scaledToFit()
                ForEach(Array(creation.ingredients.enumerated()), id: \.offset) { _, i in Image(i.image).resizable().scaledToFit() }
            }
            .frame(width: 96, height: 96)
            Text(creation.name).font(.toon(15)).foregroundStyle(Ink.line).lineLimit(1).minimumScaleFactor(0.6)
            ShareLink(item: CreationImage.render(creation), preview: SharePreview(creation.name, image: CreationImage.render(creation))) {
                Label(T("Partager", "Share"), systemImage: "square.and.arrow.up").font(.toon(12, .bold))
            }
            .tint(Ink.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Ink.paper))
        .background(RoundedRectangle(cornerRadius: 18).fill(Ink.line).offset(y: 4))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.line, lineWidth: 3))
    }
}

/// L'image à partager d'une création.
enum CreationImage {
    @MainActor
    static func render(_ c: Creation) -> Image {
        let card = VStack(spacing: 10) {
            ZStack {
                Image(c.cooked.image).resizable().scaledToFit()
                ForEach(Array(c.ingredients.enumerated()), id: \.offset) { _, i in Image(i.image).resizable().scaledToFit() }
            }
            .frame(width: 300, height: 300)
            Text(c.name).font(.toon(34, .black)).foregroundStyle(Ink.line)
            Text("Waffle Fold").font(.toon(18, .bold)).foregroundStyle(Ink.orange)
        }
        .padding(30)
        .frame(width: 420)
        .background(Color(hex: 0xFFF1D6))
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "photo")
    }
}

// MARK: - Atelier libre, à l'écran

/// À la place du client et du ticket : ce qu'on a mis sur la gaufre, et le bouton « Terminer ».
struct FreePanel: View {
    let kitchen: Kitchen
    var height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Atelier libre", "Free kitchen")).font(.toon(20, .black)).foregroundStyle(Ink.line)
            Text(phaseText).font(.toon(13, .bold)).foregroundStyle(Ink.line.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(0..<Kitchen.freeLayers, id: \.self) { i in
                    ZStack {
                        Circle().fill(Color(hex: 0xF3DFC0)).overlay(Circle().strokeBorder(Ink.line.opacity(0.4), lineWidth: 2))
                        if i < kitchen.stack.count { Image(kitchen.stack[i].image).resizable().scaledToFit().padding(3) }
                    }
                    .frame(width: 30, height: 30)
                }
            }
            Spacer(minLength: 0)
            if kitchen.phase == .topping {
                Button {
                    kitchen.finishCreation()
                } label: {
                    Label(T("Terminer", "Done"), systemImage: "checkmark").font(.toon(18)).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(ToonButton(color: Ink.green))
            }
        }
        .padding(12)
        .frame(maxHeight: height)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.paper))
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.line).offset(x: 3, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 3))
    }

    private var phaseText: String {
        switch kitchen.phase {
        case .pour: return T("Verse la pâte pour commencer.", "Pour the batter to start.")
        case .poured: return T("Ferme le Duo pour cuire.", "Close the Duo to cook.")
        case .cooking: return T("Ça cuit…", "Cooking…")
        default: return T("Garnis-la comme tu veux (6 max).", "Top it any way you like (6 max).")
        }
    }
}

/// La création est finie : le mot du chef, un nom, et on la garde.
struct CreatedCard: View {
    @Environment(Career.self) private var progress
    let kitchen: Kitchen
    let onExit: () -> Void
    @State private var name = ""
    @State private var saved: Creation?
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { typing = false }
            VStack(spacing: 12) {
                Text(T("Le mot du chef", "Chef says")).font(.toon(14, .bold)).foregroundStyle(Ink.orange)
                Text(kitchen.chefComment).font(.toon(24, .black)).foregroundStyle(Ink.line).multilineTextAlignment(.center)
                ZStack {
                    Image(kitchen.cooked.image).resizable().scaledToFit()
                    ForEach(Array(kitchen.stack.enumerated()), id: \.offset) { _, i in Image(i.image).resizable().scaledToFit() }
                }
                .frame(width: 140, height: 140)
                if let saved {
                    Text(T("« \(saved.name) » est dans ton livre !", "“\(saved.name)” is in your book!"))
                        .font(.toon(15, .bold)).foregroundStyle(Color(hex: 0x1F7A2E)).multilineTextAlignment(.center)
                    ShareLink(item: CreationImage.render(saved), preview: SharePreview(saved.name, image: CreationImage.render(saved))) {
                        Label(T("Partager", "Share"), systemImage: "square.and.arrow.up").font(.toon(18)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(ToonButton(color: Ink.orange))
                } else {
                    TextField(T("Nom de ta gaufre", "Name your waffle"), text: $name)
                        .font(.toon(18, .bold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 3))
                        .focused($typing)
                        .submitLabel(.done)
                    Button {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let c = Creation(name: n.isEmpty ? T("Ma gaufre", "My waffle") : String(n.prefix(30)),
                                         layers: kitchen.stack.map(\.rawValue), doneness: kitchen.cooked.rawValue)
                        progress.save(c)
                        saved = c
                        typing = false
                        Sound.play(.chime, volume: 0.6)
                    } label: {
                        Label(T("Garder dans mon livre", "Save to my book"), systemImage: "book.closed.fill").font(.toon(18)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(ToonButton(color: Ink.green))
                }
                HStack(spacing: 10) {
                    Button {
                        saved = nil; name = ""
                        kitchen.newCreation()
                    } label: {
                        Text(T("Une autre !", "Another!")).font(.toon(17)).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(ToonButton(color: Ink.orange))
                    Button(action: onExit) {
                        Text(T("Menu", "Menu")).font(.toon(17)).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(ToonButton(color: Ink.paper, text: Ink.line))
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.paper))
            .background(RoundedRectangle(cornerRadius: 30).fill(Ink.line).offset(y: 6))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Ink.line, lineWidth: 3.5))
            .padding(22)
        }
    }
}
