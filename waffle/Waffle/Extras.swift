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
    case wall, awning, worktop, iron
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wall: return T("Le mur", "Wall")
        case .awning: return T("Le comptoir", "Counter")
        case .worktop: return T("Le plan de travail", "Worktop")
        case .iron: return T("Le gaufrier", "Waffle iron")
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
        case .iron: return [
            DecorChoice(id: 0, fr: "Turquoise", en: "Teal", colors: [0x7FE0D6, 0x2FA79E], price: 0),
            DecorChoice(id: 1, fr: "Cerise", en: "Cherry", colors: [0xFF8A80, 0xD9433A], price: 80),
            DecorChoice(id: 2, fr: "Citron", en: "Lemon", colors: [0xFFE07A, 0xE0A92A], price: 120),
            DecorChoice(id: 3, fr: "Bonbon", en: "Candy", colors: [0xFFB3D9, 0xE0679F], price: 160),
            DecorChoice(id: 4, fr: "Myrtille", en: "Blueberry", colors: [0xA9A4FF, 0x5E55D6], price: 210),
            DecorChoice(id: 5, fr: "Réglisse", en: "Licorice", colors: [0x5A5560, 0x2B2830], price: 280),
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
    private var decor: Decor { Decor.shared }

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
                Outlined(text: T("Déco", "Decor"), size: 40)
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
            .padding(.top, 16)
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
                Image(open ? "waffle2" : "waffle0").resizable().scaledToFit()
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
