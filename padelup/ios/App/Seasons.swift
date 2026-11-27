import SwiftUI

// L'idée de Yacine : l'app vit au rythme des saisons. Feuilles qui tombent en automne, neige à Noël,
// confettis au Nouvel An, pétales au printemps, éclats de soleil l'été.
enum Season: String, CaseIterable, Identifiable {
    case autumn, halloween, christmas, newYear, winter, spring, summer

    var id: String { rawValue }

    var name: String {
        switch self {
        case .autumn: return "Automne"
        case .halloween: return "Halloween"
        case .christmas: return "Noël"
        case .newYear: return "Nouvel An"
        case .winter: return "Hiver"
        case .spring: return "Printemps"
        case .summer: return "Été"
        }
    }

    var greeting: String {
        switch self {
        case .autumn: return "Les feuilles tombent, les balles aussi."
        case .halloween: return "Smash à faire peur."
        case .christmas: return "Joyeux Noël sur les courts ❄︎"
        case .newYear: return "Bonne année, nouveau niveau !"
        case .winter: return "Courts couverts et mains au chaud."
        case .spring: return "Le printemps relance la partie."
        case .summer: return "Soleil, vitres et bandejas."
        }
    }

    var symbol: String {
        switch self {
        case .autumn, .halloween: return "leaf.fill"
        case .christmas, .winter: return "snowflake"
        case .newYear: return "sparkles"
        case .spring: return "camera.macro"
        case .summer: return "sun.max.fill"
        }
    }

    var tint: Color {
        switch self {
        case .autumn: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .halloween: return Color(red: 1.0, green: 0.45, blue: 0.10)
        case .christmas: return Color(red: 0.80, green: 0.20, blue: 0.22)
        case .newYear: return Color(red: 0.85, green: 0.70, blue: 0.20)
        case .winter: return Color(red: 0.35, green: 0.55, blue: 0.78)
        case .spring: return Color(red: 0.85, green: 0.40, blue: 0.55)
        case .summer: return Color(red: 0.90, green: 0.62, blue: 0.10)
        }
    }

    /// Saison du calendrier (hémisphère nord, comme la France et la Tunisie).
    static func current(for date: Date = Date(), calendar: Calendar = .current) -> Season {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        switch (m, d) {
        case (12, 31), (1, 1), (1, 2): return .newYear
        case (12, _): return .christmas
        case (10, 25...31): return .halloween
        case (9, 22...30), (10, _), (11, _): return .autumn
        case (1, _), (2, _), (3, 1...19): return .winter
        case (3, _), (4, _), (5, _), (6, 1...20): return .spring
        default: return .summer
        }
    }
}

/// Réglage : « auto » (selon la date), « off », ou une saison imposée (aperçu).
enum SeasonSetting {
    static let key = "seasonMode"

    static func resolve(_ raw: String, date: Date = Date()) -> Season? {
        if raw == "off" { return nil }
        if let forced = Season(rawValue: raw) { return forced }
        return Season.current(for: date)
    }
}

/// Calque d'effets saisonniers, dessiné au-dessus de l'app sans intercepter les gestes.
struct SeasonalOverlay: View {
    var season: Season
    var density: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var count: Int {
        let base: Int
        switch season {
        case .christmas: base = 34
        case .winter: base = 18
        case .newYear: base = 30
        case .autumn, .halloween: base = 14
        case .spring: base = 16
        case .summer: base = 10
        }
        return reduceMotion ? base / 3 : Int(Double(base) * density)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 12.0 : timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    drawParticle(index: i, t: t, context: &context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // Nombre pseudo-aléatoire stable pour la particule i (pas d'état à garder entre les images).
    private func rnd(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i * 127 + salt * 311) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    private func drawParticle(index i: Int, t: Double, context: inout GraphicsContext, size: CGSize) {
        let speed: Double
        let sway: Double
        switch season {
        case .christmas, .winter: speed = 0.045 + rnd(i, 1) * 0.06; sway = 18
        case .autumn, .halloween: speed = 0.035 + rnd(i, 1) * 0.04; sway = 42
        case .spring: speed = 0.03 + rnd(i, 1) * 0.035; sway = 34
        case .newYear: speed = 0.06 + rnd(i, 1) * 0.07; sway = 22
        case .summer: speed = -(0.012 + rnd(i, 1) * 0.02); sway = 14
        }
        let phase = rnd(i, 2) * 2 * .pi
        var progress = (rnd(i, 3) + t * speed).truncatingRemainder(dividingBy: 1.0)
        if progress < 0 { progress += 1 }
        let y = -40 + progress * (size.height + 80)
        let x = rnd(i, 4) * size.width + sin(t * (0.6 + rnd(i, 5)) + phase) * sway
        let depth = 0.55 + rnd(i, 6) * 0.65
        let angle = Angle.radians(t * (rnd(i, 7) - 0.5) * 2.4 + phase)

        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: angle)
        ctx.opacity = season == .summer ? 0.25 + 0.35 * sin(t * 1.5 + phase).magnitude : 0.7

        switch season {
        case .autumn, .halloween:
            let palette: [Color] = season == .halloween
                ? [Color(red: 1.0, green: 0.45, blue: 0.1), Color(red: 0.55, green: 0.25, blue: 0.75), Color(red: 0.95, green: 0.65, blue: 0.2)]
                : [Color(red: 0.89, green: 0.39, blue: 0.11), Color(red: 0.95, green: 0.65, blue: 0.25), Color(red: 0.78, green: 0.22, blue: 0.11),
                   Color(red: 0.97, green: 0.77, blue: 0.27), Color(red: 0.55, green: 0.29, blue: 0.12)]
            let color = palette[i % palette.count]
            let s = 11 * depth
            ctx.scaleBy(x: s, y: s * (0.75 + 0.25 * cos(t * 2 + phase)))  // la feuille tourne sur elle-même
            ctx.fill(Self.leaf, with: .color(color))
            ctx.stroke(Self.vein, with: .color(Color.black.opacity(0.25)), lineWidth: 0.08)
        case .christmas, .winter:
            // Neige blanche la nuit, gris-bleu doux sur fond clair (sinon invisible).
            let snow = scheme == .dark ? Color.white : Color(red: 0.62, green: 0.71, blue: 0.80)
            let r = (season == .christmas ? 3.0 : 2.4) * depth
            if i % 4 == 0 {
                ctx.stroke(Self.flake(radius: r * 2.2), with: .color(snow.opacity(0.9)), lineWidth: 1)
            } else {
                var blurred = ctx
                if depth < 0.8 { blurred.addFilter(.blur(radius: 1.2)) }
                blurred.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(snow.opacity(0.9)))
            }
        case .spring:
            let colors = [Color(red: 1.0, green: 0.78, blue: 0.86), Color(red: 1.0, green: 0.9, blue: 0.94), Color(red: 0.98, green: 0.62, blue: 0.75)]
            let s = 6 * depth
            ctx.fill(Path(ellipseIn: CGRect(x: -s, y: -s * 0.55, width: 2 * s, height: 1.1 * s)), with: .color(colors[i % colors.count]))
        case .newYear:
            let colors = [UI.accent, UI.ball, Color(red: 0.85, green: 0.70, blue: 0.20), Color(red: 0.80, green: 0.30, blue: 0.45), Color(red: 0.25, green: 0.65, blue: 0.55)]
            let w = 5 * depth, h = 9 * depth * abs(cos(t * 3 + phase)) + 1
            ctx.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(colors[i % colors.count]))
        case .summer:
            let r = 3 * depth
            var glow = ctx
            glow.addFilter(.blur(radius: 4))
            glow.fill(Path(ellipseIn: CGRect(x: -r * 2, y: -r * 2, width: r * 4, height: r * 4)), with: .color(Color(red: 1.0, green: 0.85, blue: 0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: -r / 2, y: -r / 2, width: r, height: r)), with: .color(.white))
        }
    }

    // Feuille unitaire (environ 2 x 1), centrée.
    private static let leaf: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -1, y: 0))
        p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 0, y: -0.95))
        p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: 0, y: 0.95))
        p.closeSubpath()
        return p
    }()

    private static let vein: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -1.1, y: 0)); p.addLine(to: CGPoint(x: 0.9, y: 0))
        for k in [-0.4, 0.1, 0.5] {
            p.move(to: CGPoint(x: k, y: 0)); p.addLine(to: CGPoint(x: k + 0.3, y: -0.35))
            p.move(to: CGPoint(x: k, y: 0)); p.addLine(to: CGPoint(x: k + 0.3, y: 0.35))
        }
        return p
    }()

    private static func flake(radius r: Double) -> Path {
        var p = Path()
        for k in 0..<6 {
            let a = Double(k) * .pi / 3
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r))
            let bx = cos(a) * r * 0.6, by = sin(a) * r * 0.6
            p.move(to: CGPoint(x: bx, y: by))
            p.addLine(to: CGPoint(x: bx + cos(a + 0.6) * r * 0.3, y: by + sin(a + 0.6) * r * 0.3))
            p.move(to: CGPoint(x: bx, y: by))
            p.addLine(to: CGPoint(x: bx + cos(a - 0.6) * r * 0.3, y: by + sin(a - 0.6) * r * 0.3))
        }
        return p
    }
}

/// Bandeau de saison (accueil) : symbole + petite phrase.
struct SeasonBadge: View {
    var season: Season

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: season.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(season.tint)
            Text(season.greeting).font(UI.caption()).foregroundStyle(UI.muted)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Capsule().fill(UI.tray))
    }
}
