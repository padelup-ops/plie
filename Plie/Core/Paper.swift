import SwiftUI
import UIKit

// MARK: - Le papier
//
// L'accueil, les menus, les modes d'emploi et les cartes de fin de partie sont en papier :
// un fond crème marqué de plis, une encre violet-noir, des feuilles colorées au coin corné.
// Les jeux, eux, restent dans la nuit.
//
// Les couleurs dynamiques de Theme (text, muted, faint, card, cardHigh…) suivent toutes seules :
// encre sur papier en mode clair, blanc sur nuit en mode sombre. Une carte de papier posée
// sur un jeu passe donc son contenu en mode clair (`.environment(\.colorScheme, .light)`).

enum Paper {
    static let cream = Color(hex: 0xF6F0E4)
    static let creamDeep = Color(hex: 0xEEE5D4)
    /// Une feuille blanche, un peu chaude.
    static let sheet = Color(hex: 0xFFFCF6)
    /// L'encre : un violet presque noir.
    static let ink = Color(hex: 0x2A2438)
    static let inkSoft = Color(hex: 0x2A2438, opacity: 0.64)
    /// Le rouge du papier origami : badges, rappels, interrupteurs.
    static let accent = Color(hex: 0xE0533A)
    /// Le pense-bête jaune des conseils.
    static let note = Color(hex: 0xFFF0BC)
    /// L'or des étoiles et des clés, assez foncé pour se voir sur le papier.
    static let gold = Color(hex: 0xE4A11B)
    /// Ombre chaude (jamais noire) des feuilles posées sur la table.
    static let shadow = Color(hex: 0x3A2C1A)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// Une teinte sur le papier (mode clair), une autre dans la nuit (mode sombre).
    init(paper: UInt32, _ paperOpacity: Double = 1, night: UInt32, _ nightOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: night, alpha: nightOpacity)
                : UIColor(hex: paper, alpha: paperOpacity)
        })
    }

    /// La même couleur en papier d'origami : moins saturée, jamais fluo.
    /// À n'utiliser que sur des couleurs fixes (pas sur les couleurs dynamiques de Theme).
    func paperTone(saturation k: Double = 0.72, brightness maxBrightness: Double = 0.94) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s) * k, brightness: min(Double(b), maxBrightness), opacity: Double(a))
    }
}

extension GameID {
    /// La couleur du jeu, en papier.
    var paper: Color { Self.paperColors[self] ?? color }

    private static let paperColors: [GameID: Color] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.color.paperTone()) })
}

extension Font {
    /// Les titres sur papier : une serif, comme un livre de pliages.
    static func paperTitle(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Formes

/// Rectangle aux coins arrondis dont le coin en haut à droite est corné.
struct DogEarShape: Shape {
    var cornerRadius: CGFloat
    var ear: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)
        let e = min(ear, rect.width / 2, rect.height / 2)
        guard e > 0 else { return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect) }
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + e))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Le rabat du coin corné, dessiné dans un carré : le pli en diagonale, la pointe en bas à gauche.
struct DogEarFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 3), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Un morceau de ruban adhésif en papier (washi), aux bouts déchirés en zigzag.
struct TapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let teeth = 4
        let depth: CGFloat = 3
        let step = rect.height / CGFloat(teeth)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for k in 0..<teeth {
            p.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + step * (CGFloat(k) + 0.5)))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + step * CGFloat(k + 1)))
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        for k in 0..<teeth {
            p.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - step * (CGFloat(k) + 0.5)))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - step * CGFloat(k + 1)))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Feuilles

/// Une feuille de papier posée sur la table : un pli en diagonale, un coin corné si on veut,
/// et une ombre douce qui la décolle du fond.
struct PaperSheet: View {
    var color: Color = Paper.sheet
    var cornerRadius: CGFloat = 22
    /// Taille du coin corné en haut à droite (0 : pas de coin).
    var ear: CGFloat = 0
    /// Hauteur de la feuille au-dessus de la table (règle l'ombre).
    var lift: CGFloat = 1
    var crease = true

    var body: some View {
        let shape = DogEarShape(cornerRadius: cornerRadius, ear: ear)
        ZStack(alignment: .topTrailing) {
            shape.fill(color)
            if crease {
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.24), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.5),
                    .init(color: Paper.shadow.opacity(0.025), location: 0.503),
                    .init(color: Paper.shadow.opacity(0.08), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.stroke(Paper.shadow.opacity(0.09), lineWidth: 0.75)
            if ear > 0 {
                ZStack {
                    DogEarFlap().fill(color)
                    DogEarFlap().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)],
                                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                }
                .frame(width: ear, height: ear)
                .shadow(color: Paper.shadow.opacity(0.22), radius: 1.6, x: -1.2, y: 1.4)
            }
        }
        .compositingGroup()
        .shadow(color: Paper.shadow.opacity(0.10 * lift), radius: 0.8, y: 0.8)
        .shadow(color: Paper.shadow.opacity(0.13 * lift), radius: 12 * lift, y: 6 * lift)
        .accessibilityHidden(true)
    }
}

/// Le fond des écrans en papier : une grande feuille crème, avec son grain et les plis
/// d'une base d'origami (diagonales et médianes), à peine marqués.
struct PaperBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(hex: 0xF8F3EA), Color(hex: 0xF0E8D9)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.35, y: size.height)))

            // Les plis : un creux sombre et son arête claire, un point plus bas.
            let w = size.width
            let tile = max(w, 300)
            var dark = Path()
            var y = -tile * 0.3
            while y < size.height {
                dark.move(to: CGPoint(x: 0, y: y))
                dark.addLine(to: CGPoint(x: w, y: y + tile))
                dark.move(to: CGPoint(x: w, y: y))
                dark.addLine(to: CGPoint(x: 0, y: y + tile))
                dark.move(to: CGPoint(x: 0, y: y + tile / 2))
                dark.addLine(to: CGPoint(x: w, y: y + tile / 2))
                y += tile
            }
            var middle = Path()
            middle.move(to: CGPoint(x: w / 2, y: 0))
            middle.addLine(to: CGPoint(x: w / 2, y: size.height))
            context.stroke(dark.offsetBy(dx: 0, dy: 1), with: .color(.white.opacity(0.7)), lineWidth: 1)
            context.stroke(dark, with: .color(Paper.shadow.opacity(0.05)), lineWidth: 1)
            context.stroke(middle.offsetBy(dx: 1, dy: 0), with: .color(.white.opacity(0.6)), lineWidth: 1)
            context.stroke(middle, with: .color(Paper.shadow.opacity(0.035)), lineWidth: 1)

            Draw.paperGrain(&context, in: rect, seed: 11, density: Int(size.width * size.height / 700))

            // Les bords un peu plus sombres, comme une feuille sous une lampe.
            context.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [.clear, Paper.shadow.opacity(0.06)]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.3),
                startRadius: min(size.width, size.height) * 0.4,
                endRadius: max(size.width, size.height) * 0.9))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Un bout de ruban washi, pour « coller » une carte sur l'écran.
struct WashiTape: View {
    let color: Color
    var width: CGFloat = 86

    var body: some View {
        ZStack {
            TapeShape().fill(color.opacity(0.78))
            TapeShape().fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .white.opacity(0.15)],
                                            startPoint: .top, endPoint: .bottom))
        }
        .frame(width: width, height: 26)
        .rotationEffect(.degrees(-4))
        .shadow(color: Paper.shadow.opacity(0.14), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// Le petit emblème de l'accueil : le Duo en papier, plié en V.
struct OrigamoMark: View {
    var body: some View {
        Canvas { context, size in
            let base = context
            let s = min(size.width, size.height)
            let panel = CGSize(width: s * 0.36, height: s * 0.66)
            func draw(_ color: Color, angle: Double, dx: CGFloat, symbol: (inout GraphicsContext, CGRect) -> Void) {
                var c = base
                c.translateBy(x: size.width / 2 + dx, y: size.height * 0.86)
                c.rotate(by: .degrees(angle))
                let rect = CGRect(x: -panel.width / 2, y: -panel.height, width: panel.width, height: panel.height)
                let shape = Path(roundedRect: rect, cornerRadius: s * 0.08, style: .continuous)
                c.fill(shape.offsetBy(dx: 0, dy: s * 0.03), with: .color(Paper.shadow.opacity(0.18)))
                c.fill(shape, with: .color(color))
                c.fill(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.3), Paper.shadow.opacity(0.1)]),
                                                     startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                     endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                symbol(&c, rect)
            }
            let ink = GraphicsContext.Shading.color(Paper.ink)
            draw(Color(hex: 0x3DE0FF).paperTone(), angle: -16, dx: -s * 0.12) { c, r in
                var plus = Path()
                let m = CGPoint(x: r.midX, y: r.midY)
                let k = r.width * 0.18
                plus.move(to: CGPoint(x: m.x - k, y: m.y))
                plus.addLine(to: CGPoint(x: m.x + k, y: m.y))
                plus.move(to: CGPoint(x: m.x, y: m.y - k))
                plus.addLine(to: CGPoint(x: m.x, y: m.y + k))
                c.stroke(plus, with: ink, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            }
            draw(Color(hex: 0xFF4F9A).paperTone(), angle: 16, dx: s * 0.12) { c, r in
                let m = CGPoint(x: r.midX, y: r.midY)
                let k = r.width * 0.15
                let d = s * 0.05
                for (x, y) in [(0.0, -1.0), (-1.0, 0.0), (1.0, 0.0), (0.0, 1.0)] {
                    let p = CGPoint(x: m.x + CGFloat(x) * k, y: m.y + CGFloat(y) * k)
                    c.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: ink)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Un écran présenté par-dessus (feuille) en papier : fond crème, encre, mode clair, même posé sur un jeu.
    func paperScreen() -> some View {
        self
            .foregroundStyle(Paper.ink)
            .background(PaperBackdrop())
            .tint(Paper.accent)
            .environment(\.colorScheme, .light)
            .presentationBackground(Paper.cream)
            .presentationDragIndicator(.visible)
    }
}

extension Color {
    /// La même teinte, assez foncée pour être lue sur le papier (textes de couleur).
    func readableOnPaper() -> Color { paperTone(saturation: 0.95, brightness: 0.52) }
}
