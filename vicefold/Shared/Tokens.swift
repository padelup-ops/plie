// Tokens.swift — Vicefold
//
// L'identité de l'app : Leonida la nuit, en néon. Un fond bleu nuit presque noir, un dégradé de coucher de soleil
// (magenta → orange) pour ce qui compte, un cyan électrique pour le reste, et des titres d'affiche en Anton.
// Ces jetons sont partagés par l'app et par ses widgets ; les composants de l'app sont dans App/Design.swift.
// Tout est dessiné ici : aucune couleur, image ni lettrage du jeu.

import SwiftUI
import UIKit

enum VF {
    // MARK: Fonds

    /// Le fond des écrans : un bleu nuit presque noir.
    static let abyss = Color(red: 0.016, green: 0.020, blue: 0.055)
    /// Un cran au-dessus (barres, feuilles, textes sombres posés sur un néon).
    static let ink = Color(red: 0.027, green: 0.035, blue: 0.090)
    /// Le fond plein d'une carte quand le verre n'est pas possible (« Réduire la transparence », widgets).
    static let panel = Color(red: 0.063, green: 0.075, blue: 0.160)
    static let panelHi = Color(red: 0.098, green: 0.114, blue: 0.227)
    /// Un filet lumineux très fin (bord des cartes, séparateurs).
    static let hairline = Color.white.opacity(0.12)
    /// Le fond d'une ligne de liste, et celui de la ligne choisie.
    static let row = Color.white.opacity(0.055)
    static let rowSelected = Color(red: 1.0, green: 0.26, blue: 0.60).opacity(0.20)

    // MARK: Néons

    static let flamingo = Color(red: 1.0, green: 0.26, blue: 0.60)
    static let sunset = Color(red: 1.0, green: 0.54, blue: 0.24)
    static let sun = Color(red: 1.0, green: 0.80, blue: 0.32)
    static let cyan = Color(red: 0.24, green: 0.90, blue: 0.95)
    /// Le vert menthe de ce qui est fait.
    static let palm = Color(red: 0.20, green: 0.92, blue: 0.66)
    static let sky = Color(red: 0.56, green: 0.58, blue: 1.0)
    static let violet = Color(red: 0.48, green: 0.30, blue: 0.95)

    // Les anciens noms, pour les écrans qui les utilisent encore.
    static let coral = sunset
    static let magenta = flamingo
    static let teal = palm
    static let night = ink

    // MARK: Texte

    static let text = Color(red: 0.96, green: 0.97, blue: 1.0)
    /// Texte secondaire : contraste d'au moins 7:1 sur le fond.
    static let textDim = Color(red: 0.96, green: 0.97, blue: 1.0).opacity(0.68)
    /// Légendes discrètes : contraste d'au moins 4,5:1 sur le fond.
    static let textFaint = Color(red: 0.96, green: 0.97, blue: 1.0).opacity(0.50)

    // MARK: Dégradés

    /// Le coucher de soleil : la couleur héroïne (boutons, chiffres clés, progression).
    static let gradient = LinearGradient(colors: [flamingo, sunset], startPoint: .leading, endPoint: .trailing)
    /// Le même, en diagonale et avec le soleil (icônes, anneaux).
    static let blaze = LinearGradient(colors: [sun, sunset, flamingo], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Le ciel du soir, de haut en bas (affiches, vignettes).
    static let dusk = LinearGradient(colors: [violet, flamingo, sunset], startPoint: .top, endPoint: .bottom)
    /// Le froid : du cyan au violet (accents secondaires).
    static let ice = LinearGradient(colors: [cyan, sky], startPoint: .leading, endPoint: .trailing)

    /// Les quatre parts du 100 % : missions, lieux, objets, défis.
    static let ringColors: [Color] = [flamingo, cyan, sun, sky]

    /// Le fond des écrans et celui des cartes (l'app est toujours sombre : le paramètre reste pour les anciens appels).
    static func backdrop(_ dark: Bool = true) -> Color { abyss }
    static func card(_ dark: Bool = true) -> Color { panel }

    // MARK: Typographie

    /// Les titres d'affiche (Anton, licence SIL Open Font).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Anton-Regular", size: size, relativeTo: style)
    }

    /// Les petites légendes d'instrument de bord, en chasse fixe (elles suivent la taille de texte choisie).
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .caption2).scaledValue(for: size), weight: weight, design: .monospaced)
    }

    // MARK: Espacement et rayons

    enum Space {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 22
        static let xl: CGFloat = 30
    }

    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 22
        static let hero: CGFloat = 30
    }

    /// La sortie du jeu (PS5 et Xbox Series), annoncée par l'éditeur.
    static let release: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 19; c.hour = 0
        c.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()
}

extension View {
    /// Un halo de néon autour d'une forme ou d'un chiffre.
    func vfGlow(_ color: Color, radius: CGFloat = 8, strength: Double = 0.7) -> some View {
        shadow(color: color.opacity(strength), radius: radius)
            .shadow(color: color.opacity(strength * 0.45), radius: radius * 2.6)
    }
}

/// L'anneau de progression : une part par catégorie, en tubes de néon.
struct VFRing: View {
    var parts: [Double]          // 0…1 pour chaque catégorie
    var lineWidth: CGFloat = 14
    var glow = true

    var body: some View {
        ZStack {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                let inset = CGFloat(i) * (lineWidth + 4)
                let color = VF.ringColors[i % 4]
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, p)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(glow ? 0.75 : 0), radius: lineWidth * 0.55)
                    .padding(inset)
            }
        }
        .padding(lineWidth / 2)
    }
}
