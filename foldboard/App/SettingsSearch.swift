import SwiftUI

/// Les pages de réglages de l'app, pour la recherche et les sous-titres de l'accueil.
enum SettingsPage: CaseIterable {
    case position, typing, look, feel, phrases, teach, buttons, tour

    var title: LocalizedStringKey {
        switch self {
        case .position: return "Position and size"
        case .typing: return "Typing"
        case .look: return "Colors and font"
        case .feel: return "Sound, vibrations and swipe"
        case .phrases: return "Phrases and emoji"
        case .teach: return "Teach your thumbs"
        case .buttons: return "The keyboard buttons"
        case .tour: return "Guided tour"
        }
    }

    /// Les six cartes de réglages de l'accueil.
    static let grid: [SettingsPage] = [.position, .typing, .look, .feel, .phrases, .teach]

    var icon: String {
        switch self {
        case .position: return "hand.raised.fingers.spread"
        case .typing: return "character.cursor.ibeam"
        case .look: return "paintpalette"
        case .feel: return "waveform"
        case .phrases: return "text.bubble"
        case .teach: return "touchid"
        case .buttons: return "rectangle.topthird.inset.filled"
        case .tour: return "play.rectangle"
        }
    }

    /// Ce qu'on trouve dans la page, en une ligne (sous le titre, à l'accueil).
    var subtitle: LocalizedStringKey {
        switch self {
        case .position: return "Follows your hand, full width, split, each screen, key height, width"
        case .typing: return "Autocorrect, suggestions, slide to type, emoji, clipboard"
        case .look: return "Theme, colors, font"
        case .feel: return "Key sound, vibrations, space-bar trackpad speed"
        case .phrases: return "Your phrases and favorite emoji"
        case .teach: return "30 seconds: a sentence with each thumb"
        case .buttons: return "What each button of the keyboard does"
        case .tour: return "A short tour of the keyboard"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .position: PositionView().fullScreenDuo()
        case .typing: TypingView().fullScreenDuo()
        case .look: LookView().fullScreenDuo()
        case .feel: FeelView().fullScreenDuo()
        case .phrases: PhrasesView().fullScreenDuo()
        case .teach: GripSetup().fullScreenDuo()
        case .buttons: ButtonsGuide().fullScreenDuo()
        case .tour: KeyboardTourScreen()
        }
    }
}

/// Un réglage qu'on peut chercher : son nom (traduit), des mots-clés en français et en anglais, et sa page.
struct SettingsEntry: Identifiable {
    let id = UUID()
    let title: String
    let keywords: String
    let page: SettingsPage

    static let all: [SettingsEntry] = [
        e("Layout", "azerty qwerty qwertz disposition langue language clavier français anglais", .position),
        e("Follows your hand", "main hand suivre suit follow gauche droite left right position", .position),
        e("Full width", "entier intégral toute la largeur full width position", .position),
        e("Split keyboard", "scindé dissocier coupé deux moitiés split two hands deux mains", .position),
        e("For each screen", "écran screen fermé ouvert paysage portrait closed open landscape duo", .position),
        e("Key height", "hauteur taille grandes petites touches size height keys bigger smaller", .position),
        e("One-hand width", "largeur width une main one hand", .position),
        e("Two-hand width (each side)", "largeur moitié scindé split width each side", .position),
        e("Distance from the edge", "bord marge edge margin distance", .position),
        e("Number row", "chiffres rangée numbers row", .position),
        e("Space bar row height", "barre d'espace espace rangée du bas hauteur space bar bottom row height", .position),
        e("Reset size to default", "réinitialiser rétablir taille origine reset default size", .position),
        e("Position and settings buttons", "barre du haut boutons top bar buttons cacher hide", .position),
        e("Hide keyboard button", "masquer fermer clavier hide dismiss keyboard button", .position),
        e("Learning messages", "messages apprentissage noté learning tips", .position),
        e("Auto-correction", "correction autocorrect fautes typos corriger", .typing),
        e("Slide to type", "glisser glide swipe écrire en glissant", .typing),
        e("Word suggestions", "suggestions prédiction mots predictions words barre", .typing),
        e("Contact names in suggestions", "contacts noms prénoms names", .typing),
        e("Capital letter at the start of a sentence", "majuscule capital phrase sentence", .typing),
        e("Double space adds a period", "point espace double period space", .typing),
        e("Foldboard emoji key", "emoji smiley touche emoji key", .typing),
        e("Show the globe as a smiley", "globe smiley emoji", .typing),
        e("Emoji suggestions", "emoji suggestions suggérés barre", .typing),
        e("Save everything I copy", "presse-papier clipboard copier coller copy paste autoriser allow", .typing),
        e("Colors and font", "thème couleurs police sombre clair theme colors font dark light verre glass", .look),
        e("Sound, vibrations and swipe", "son sons vibrations haptique sound haptics trackpad curseur cursor sensibilité", .feel),
        e("Phrases and emoji", "phrases favoris emojis favorites", .phrases),
        e("Teach your thumbs", "étalonnage pouces main calibration thumbs apprendre", .teach),
        e("The keyboard buttons", "aide boutons help buttons explication", .buttons),
        e("Guided tour", "tutoriel visite tour guide aide help", .tour),
    ]

    private static func e(_ key: String, _ kw: String, _ p: SettingsPage) -> SettingsEntry {
        SettingsEntry(title: NSLocalizedString(key, comment: ""), keywords: kw, page: p)
    }

    /// Sans accents ni majuscules, pour comparer.
    static func norm(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

    static func search(_ q: String) -> [SettingsEntry] {
        let terms = norm(q).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return all.filter { e in
            let hay = norm(e.title + " " + e.keywords)
            return terms.allSatisfy { hay.contains($0) }
        }
    }
}

/// Les résultats de la recherche, à la place de l'accueil pendant qu'on tape.
struct SettingsSearchResults: View {
    let query: String

    var body: some View {
        let found = SettingsEntry.search(query)
        List {
            if found.isEmpty {
                Text("No setting found").foregroundStyle(.secondary)
            }
            ForEach(found) { r in
                NavigationLink { r.page.destination } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title)
                        Text(r.page.title).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
