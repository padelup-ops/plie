// Design.swift — Vicefold
//
// Le système de design de l'app : « Leonida la nuit, en néon ». Les jetons (couleurs, dégradés, polices, espacements)
// sont dans Shared/Tokens.swift, partagés avec les widgets ; ici, tout ce que les écrans posent dessus : le fond
// (une aurore très lente sur un bleu nuit), les cartes en verre sombre, les boutons, les puces, les légendes
// d'instrument de bord, les repères d'angle, les barres de néon et les constantes de mouvement.
// L'app est toujours sombre (voir project.yml : UIUserInterfaceStyle), pour que le néon reste lisible partout.

import SwiftUI
import UIKit

enum VFStyle {
    /// Les grands titres des écrans en Anton, comme une affiche ; les sélecteurs à segments aux couleurs de l'app.
    @MainActor static func apply() {
        let large = UIFont(name: "Anton-Regular", size: 38) ?? .systemFont(ofSize: 34, weight: .black)
        let small = UIFont(name: "Anton-Regular", size: 20) ?? .systemFont(ofSize: 17, weight: .bold)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: small)]
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(VF.flamingo)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(VF.ink), .font: UIFont.systemFont(ofSize: 13, weight: .bold)], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.78), .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .normal)
    }
}

/// Les mouvements de l'app : courts, souples, jamais gratuits. Avec « Réduire les animations », les écrans
/// n'utilisent plus que des fondus (voir `vfAppear`).
enum VFMotion {
    static let snap = Animation.snappy(duration: 0.28)
    static let ease = Animation.easeInOut(duration: 0.35)
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.84)
    static func stagger(_ index: Int, step: Double = 0.07) -> Animation { reveal.delay(Double(index) * step) }
}

// MARK: - Le fond

/// Le fond des écrans : bleu nuit presque noir, une aurore très lente (magenta, violet, cyan, à faible lumière)
/// et un quadrillage à peine visible en haut. L'aurore est immobile avec « Réduire les animations ».
struct VFBackdrop: View {
    var vivid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VF.abyss
            if reduceMotion || ShotMode.route != nil {
                Aurora(phase: 0.18, vivid: vivid)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                    Aurora(phase: tl.date.timeIntervalSinceReferenceDate / 46, vivid: vivid)
                }
            }
            VFGrid()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct Aurora: View {
    var phase: Double
    var vivid: Bool

    var body: some View {
        let a = Float(sin(phase * 2 * .pi))
        let b = Float(cos(phase * 2 * .pi * 0.7))
        let k: Double = vivid ? 1.7 : 1
        MeshGradient(width: 3, height: 3, points: [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + 0.10 * a, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.42 + 0.07 * b), SIMD2<Float>(0.5 + 0.14 * b, 0.40 + 0.10 * a), SIMD2<Float>(1, 0.52 - 0.07 * a),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5 - 0.10 * a, 1), SIMD2<Float>(1, 1),
        ], colors: [
            Color(red: 0.10 * k, green: 0.035 * k, blue: 0.24 * k), VF.abyss, Color(red: 0.21 * k, green: 0.03 * k, blue: 0.17 * k),
            VF.abyss, Color(red: 0.03 * k, green: 0.045 * k, blue: 0.13 * k), VF.abyss,
            Color(red: 0.02 * k, green: 0.11 * k, blue: 0.17 * k), VF.abyss, Color(red: 0.09 * k, green: 0.04 * k, blue: 0.21 * k),
        ])
    }
}

/// Un quadrillage très discret, qui s'efface vers le bas.
struct VFGrid: View {
    var step: CGFloat = 34
    var opacity: Double = 0.05

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width {
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(p, with: .color(.white.opacity(opacity)), lineWidth: 0.5)
        }
        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        .allowsHitTesting(false)
    }
}

// MARK: - Cartes et verre

/// Le fond d'une carte : du verre sombre (un voile, un reflet en diagonale, un filet lumineux), teinté si on veut.
/// Plein avec « Réduire la transparence ».
struct VFPanel<S: Shape>: View {
    var shape: S
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var solid

    var body: some View {
        ZStack {
            shape.fill(VF.panel.opacity(solid ? 1 : 0.66))
            shape.fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.012)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let tint {
                shape.fill(LinearGradient(colors: [tint.opacity(0.17), tint.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.stroke(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.26 : 0.55), .white.opacity(0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }
}

struct VFCardStyle: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { VFPanel(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint) }
    }
}

/// Le vrai verre d'iOS 26, pour ce qui flotte au-dessus du contenu (filtres de la carte, fiche d'un lieu, barres).
/// Avec « Réduire la transparence » : un fond plein et un filet.
struct VFGlass<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        if solid {
            content.background(VF.panel, in: shape).overlay(shape.stroke(VF.hairline, lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Quatre petits repères d'angle, comme le cadre d'un viseur.
struct CornerTicks: Shape {
    var length: CGFloat = 12
    var inset: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
            (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1),
        ]
        var p = Path()
        for (c, dx, dy) in corners {
            p.move(to: CGPoint(x: c.x + length * dx, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + length * dy))
        }
        return p
    }
}

extension View {
    /// Une carte posée sur le fond : verre sombre, coins doux, filet lumineux.
    func vfCard(radius: CGFloat = VF.Radius.card, padding: CGFloat = VF.Space.m, tint: Color? = nil) -> some View {
        modifier(VFCardStyle(radius: radius, padding: padding, tint: tint))
    }

    /// Le verre d'iOS 26 (fond plein si la transparence est réduite).
    func vfGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VFGlass(shape: shape, tint: tint, interactive: interactive))
    }

    /// Des repères d'angle par-dessus (affiches, carte, cadres).
    func vfTicks(_ color: Color = VF.cyan, length: CGFloat = 12, inset: CGFloat = 8) -> some View {
        overlay(CornerTicks(length: length, inset: inset).stroke(color.opacity(0.85), lineWidth: 1.5).allowsHitTesting(false))
    }

    /// Une liste ou un formulaire sur le fond de l'app.
    func vfScreen() -> some View {
        scrollContentBackground(.hidden).background(VFBackdrop())
    }

    /// Les lignes d'une liste : verre sombre et filets fins.
    func vfRows() -> some View {
        listRowBackground(VF.row).listRowSeparatorTint(VF.hairline)
    }

    /// Une puce (filtre, étiquette) : pleine et lumineuse quand elle est choisie.
    func vfChip(selected: Bool, color: Color = VF.flamingo) -> some View {
        font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? VF.ink : VF.text)
            .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.07)), in: .capsule)
            .overlay(Capsule().stroke(selected ? Color.clear : VF.hairline, lineWidth: 1))
            .shadow(color: selected ? color.opacity(0.55) : .clear, radius: 8)
    }

    /// L'entrée d'un élément : un fondu, avec un léger glissement si les animations ne sont pas réduites.
    func vfAppear(_ shown: Bool, index: Int = 0, offset: CGFloat = 18) -> some View {
        modifier(VFAppear(shown: shown, index: index, offset: offset))
    }
}

private struct VFAppear: ViewModifier {
    var shown: Bool
    var index: Int
    var offset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : offset)
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : VFMotion.stagger(index), value: shown)
    }
}

extension Text {
    /// Une légende d'instrument de bord : petite, en chasse fixe, en capitales espacées.
    func vfHUD(_ color: Color = VF.cyan, size: CGFloat = 10.5) -> some View {
        font(VF.mono(size)).tracking(1.4).textCase(.uppercase).foregroundStyle(color)
    }
}

// MARK: - Boutons

/// Les boutons de l'app. `primary` : le coucher de soleil, texte sombre (contraste élevé). `done` : menthe, pour ce
/// qui est fait. `secondary` : verre et filet. `quiet` : juste le texte.
struct VFButtonStyle: ButtonStyle {
    enum Kind { case primary, done, secondary, quiet }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        VFButtonBody(kind: kind, compact: compact, pressed: configuration.isPressed, label: configuration.label)
    }
}

private struct VFButtonBody<Label: View>: View {
    var kind: VFButtonStyle.Kind
    var compact: Bool
    var pressed: Bool
    var label: Label
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .font(compact ? .subheadline.weight(.bold) : .headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 8 : 14)
            .frame(minHeight: compact ? 34 : 50)
            .background(fill, in: .capsule)
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
            .shadow(color: glow.opacity(enabled ? 0.5 : 0), radius: compact ? 6 : 12)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(VFMotion.snap, value: pressed)
            .contentShape(.capsule)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .done: return VF.ink
        case .secondary: return VF.text
        case .quiet: return VF.flamingo
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(VF.gradient)
        case .done: return AnyShapeStyle(VF.palm)
        case .secondary: return AnyShapeStyle(Color.white.opacity(0.08))
        case .quiet: return AnyShapeStyle(Color.clear)
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary, .done: return .white.opacity(0.35)
        case .secondary: return .white.opacity(0.22)
        case .quiet: return .clear
        }
    }

    private var glow: Color {
        switch kind {
        case .primary: return VF.flamingo
        case .done: return VF.palm
        case .secondary, .quiet: return .clear
        }
    }
}

extension ButtonStyle where Self == VFButtonStyle {
    static var vfPrimary: VFButtonStyle { VFButtonStyle(kind: .primary) }
    static var vfDone: VFButtonStyle { VFButtonStyle(kind: .done) }
    static var vfSecondary: VFButtonStyle { VFButtonStyle(kind: .secondary) }
    static var vfQuiet: VFButtonStyle { VFButtonStyle(kind: .quiet) }
    static func vf(_ kind: VFButtonStyle.Kind, compact: Bool = false) -> VFButtonStyle { VFButtonStyle(kind: kind, compact: compact) }
}

// MARK: - Petits composants

/// Une icône dans une pastille lumineuse.
struct VFIconBadge: View {
    var icon: String
    var color: Color = VF.flamingo
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1))
            .shadow(color: color.opacity(0.35), radius: 6)
            .accessibilityHidden(true)
    }
}

/// Une barre de progression en tube de néon.
struct VFBar: View {
    var value: Double
    var color: Color = VF.flamingo
    var gradient = true
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                if value > 0 {
                    Capsule()
                        .fill(gradient ? AnyShapeStyle(VF.gradient) : AnyShapeStyle(color))
                        .frame(width: max(height, g.size.width * min(1, value)))
                        .shadow(color: color.opacity(0.7), radius: 4)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Le titre d'une partie d'écran : en Anton, précédé d'un trait de néon, avec une action à droite si besoin.
struct SectionTitle: View {
    var title: LocalizedStringKey
    var action: LocalizedStringKey?
    var tap: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule().fill(VF.gradient).frame(width: 4, height: 20).shadow(color: VF.flamingo.opacity(0.7), radius: 5)
                .accessibilityHidden(true)
            Text(title).font(VF.display(24, relativeTo: .title2)).foregroundStyle(VF.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let action, let tap {
                Button(action, action: tap).buttonStyle(.vf(.secondary, compact: true))
            }
        }
    }
}

/// Un écran (ou une partie d'écran) vide : une icône dans un anneau, un titre, une phrase qui dit quoi faire.
struct VFEmptyState: View {
    var icon: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(VF.cyan)
                .frame(width: 68, height: 68)
                .background(VF.cyan.opacity(0.10), in: .circle)
                .overlay(Circle().stroke(VF.cyan.opacity(0.55), lineWidth: 1))
                .overlay(Circle().stroke(VF.cyan.opacity(0.18), lineWidth: 1).padding(-8))
                .shadow(color: VF.cyan.opacity(0.4), radius: 10)
                .accessibilityHidden(true)
            Text(title).font(VF.display(22, relativeTo: .title3)).foregroundStyle(VF.text).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(VF.textDim).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Un billet : deux encoches sur les côtés, au niveau de la ligne pointillée.
struct TicketShape: Shape {
    var notch: CGFloat = 9
    /// La position de l'encoche, de 0 (haut) à 1 (bas).
    var at: CGFloat = 0.62
    func path(in r: CGRect) -> Path {
        let y = r.minY + r.height * at
        var p = Path(roundedRect: r, cornerRadius: 16, style: .continuous)
        p = p.subtracting(Path(ellipseIn: CGRect(x: r.minX - notch, y: y - notch, width: notch * 2, height: notch * 2)))
        p = p.subtracting(Path(ellipseIn: CGRect(x: r.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2)))
        return p
    }
}

/// Un raccourci en forme de billet : l'icône lumineuse, le nom, et un talon avec un mot.
struct TicketTile: View {
    var title: LocalizedStringKey
    var stub: LocalizedStringKey
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(color)
                    .shadow(color: color.opacity(0.8), radius: 8)
                Text(title).font(VF.display(21, relativeTo: .title3)).foregroundStyle(VF.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14).padding(.top, 14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            Line().stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])).foregroundStyle(color.opacity(0.6)).frame(height: 1).padding(.horizontal, 12)
            Text(stub).font(VF.mono(10.5)).foregroundStyle(VF.textDim).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 150)
        .background { VFPanel(shape: TicketShape(at: 0.66), tint: color) }
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}

/// La progression comme l'égaliseur d'un autoradio : une barre de néon par catégorie, le total en grand.
struct ProgressEqualizer: View {
    var parts: Progress.Parts
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Les barres montent à l'apparition (tout de suite avec « Réduire les animations »).
    @State private var risen = false

    var body: some View {
        let items: [(LocalizedStringKey, Double, Color)] = [("Missions", parts.missions, VF.ringColors[0]), ("Places", parts.places, VF.ringColors[1]),
                                                           ("Items", parts.collectibles, VF.ringColors[2]), ("Challenges", parts.challenges, VF.ringColors[3])]
        HStack(alignment: .bottom, spacing: compact ? 3 : 5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(parts.total, format: .percent.precision(.fractionLength(0)))
                    .font(VF.display(compact ? 44 : 60))
                    .monospacedDigit()
                    .foregroundStyle(VF.gradient)
                    .shadow(color: VF.flamingo.opacity(0.55), radius: 14)
                    // Dans un demi-écran étroit (Duo ouvert), le total rétrécit au lieu de passer sur deux lignes.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text("of Leonida done").vfHUD(VF.textDim).lineLimit(1).minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                VStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(it.2.opacity(0.14))
                            Capsule().fill(LinearGradient(colors: [it.2, it.2.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(6, g.size.height * min(1, risen ? it.1 : 0)))
                                .shadow(color: it.2.opacity(0.8), radius: 6)
                                .animation(reduceMotion ? nil : VFMotion.stagger(i, step: 0.09), value: risen)
                                .animation(reduceMotion ? nil : VFMotion.snap, value: it.1)
                        }
                    }
                    .frame(width: compact ? 12 : 16, height: compact ? 60 : 82)
                    Text(it.1, format: .percent.precision(.fractionLength(0))).font(VF.mono(10.5, weight: .bold)).foregroundStyle(VF.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    // Une colonne de largeur fixe : un mot long (« Herausforderungen ») rétrécit au lieu de déborder.
                    Text(it.0).font(.system(size: 9, weight: .semibold)).foregroundStyle(VF.textDim).lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(width: compact ? 38 : 46)
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear { risen = true }
    }
}

/// Un balayage de radar : un faisceau qui tourne lentement sur une carte (immobile avec « Réduire les animations »).
struct RadarSweep: View {
    var color: Color = VF.cyan
    var period: Double = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        GeometryReader { g in
            let side = max(g.size.width, g.size.height) * 1.5
            Circle()
                .fill(AngularGradient(colors: [color.opacity(0), color.opacity(0), color.opacity(0.30)], center: .center))
                .frame(width: side, height: side)
                .rotationEffect(.degrees(turning ? 300 : -60))
                .position(x: g.size.width / 2, y: g.size.height / 2)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, ShotMode.route == nil else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

// MARK: - Navigation et choix du jour

/// Aller à un lieu sur la carte depuis n'importe quel écran, et rouvrir la présentation de l'app.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var mapPlace: VFPlace?
    /// La présentation (première ouverture), rouverte depuis les réglages.
    var showIntro = false
}

/// Le choix du jour : le même toute la journée, un autre demain (une raison d'ouvrir l'app chaque jour).
enum Daily {
    static func index(_ count: Int, salt: Int = 0) -> Int {
        guard count > 0 else { return 0 }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return abs((day &* 2_654_435_761 &+ salt &* 40_503) % count)
    }
}

/// « Reprendre » : les derniers guides, missions, secrets et personnages ouverts, gardés sur cet appareil.
@MainActor @Observable
final class Recents {
    static let shared = Recents()

    enum Kind: String, Codable { case guide, mission, egg, character }
    struct Item: Codable, Hashable, Identifiable {
        var kind: Kind
        var ref: String
        var date: Date
        var id: String { kind.rawValue + ":" + ref }
    }

    private(set) var items: [Item] = []
    private static let key = "vicefold.recents"

    private init() {
        if ShotMode.route != nil {
            items = [Item(kind: .guide, ref: "route-100", date: Date()), Item(kind: .egg, ref: "egg-dog", date: Date()),
                     Item(kind: .character, ref: "lucia", date: Date())]
        } else if let d = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Item].self, from: d) {
            items = saved
        }
    }

    func opened(_ kind: Kind, _ ref: String) {
        guard ShotMode.route == nil else { return }
        if items.first?.kind == kind, items.first?.ref == ref { return }
        var list = items.filter { !($0.kind == kind && $0.ref == ref) }
        list.insert(Item(kind: kind, ref: ref, date: Date()), at: 0)
        items = Array(list.prefix(8))
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
