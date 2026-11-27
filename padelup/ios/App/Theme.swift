import SwiftUI

// PADELUP NEO : thème « court néon ». Nuit bleu profond, lignes cyan du terrain, balle jaune fluo,
// panneaux de verre (comme les vitres d'un court de padel).
enum Neo {
    static let night = Color(red: 0.016, green: 0.027, blue: 0.059)
    static let deep = Color(red: 0.039, green: 0.090, blue: 0.220)
    static let court = Color(red: 0.090, green: 0.278, blue: 1.0)
    static let cyan = Color(red: 0.133, green: 0.902, blue: 1.0)
    static let volt = Color(red: 0.831, green: 1.0, blue: 0.227)
    static let magenta = Color(red: 1.0, green: 0.239, blue: 0.604)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let text = Color.white
    static let dim = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.35)
    static let line = Color.white.opacity(0.12)

    static let backgroundGradient = LinearGradient(colors: [night, deep, Color(red: 0.03, green: 0.05, blue: 0.14)],
                                                   startPoint: .top, endPoint: .bottom)
    static let neonGradient = LinearGradient(colors: [cyan, court], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let voltGradient = LinearGradient(colors: [volt, Color(red: 0.55, green: 1.0, blue: 0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .heavy).width(.expanded) }
    static func label(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold).width(.expanded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func mono(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
}

// Panneau de verre : matière translucide, reflet, liseré dégradé et halo discret.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    var glow: Color = Neo.cyan
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.01)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [glow.opacity(0.55), Color.white.opacity(0.08), glow.opacity(0.18)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: glow.opacity(0.16), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func glassCard(radius: CGFloat = 22, glow: Color = Neo.cyan, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(radius: radius, glow: glow, padding: padding))
    }

    func neonGlow(_ color: Color = Neo.cyan, radius: CGFloat = 10) -> some View {
        shadow(color: color.opacity(0.75), radius: radius / 2).shadow(color: color.opacity(0.35), radius: radius)
    }
}

struct NeonButtonStyle: ButtonStyle {
    var color: Color = Neo.volt
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Neo.label(15))
            .foregroundStyle(filled ? Neo.night : color)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.10)))
            )
            .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.7), lineWidth: 1))
            .shadow(color: color.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 4 : 14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String? = nil
    var selected = false
    var color: Color = Neo.cyan

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            Text(text).font(Neo.label(12))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .foregroundStyle(selected ? Neo.night : color)
        .background(Capsule().fill(selected ? color : color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(selected ? 0 : 0.45), lineWidth: 1))
    }
}

struct SectionTitle: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased()).font(Neo.label(12)).foregroundStyle(Neo.cyan).tracking(1.6)
            Spacer()
            if let trailing { Text(trailing).font(Neo.label(11)).foregroundStyle(Neo.faint) }
        }
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var color: Color = Neo.volt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Neo.title(24)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(Neo.label(11)).foregroundStyle(Neo.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18, glow: color, padding: 14)
    }
}

// Terrain de padel en perspective, lignes néon, balayage lumineux lent : le décor de l'app.
struct CourtBackdrop: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                draw(context: &context, size: size, t: reduceMotion ? 0 : t)
            }
        }
        .background(Neo.backgroundGradient)
        .ignoresSafeArea()
    }

    private func draw(context: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let topY = h * 0.30, botY = h * 1.05
        let topHalf = w * 0.24, botHalf = w * 0.78
        func p(_ k: Double, _ side: Double) -> CGPoint {
            let y = topY + (botY - topY) * k
            let half = topHalf + (botHalf - topHalf) * k
            return CGPoint(x: w / 2 + side * half, y: y)
        }
        // halo du terrain
        let halo = Path(ellipseIn: CGRect(x: w * 0.05, y: h * 0.35, width: w * 0.9, height: h * 0.5))
        context.fill(halo, with: .radialGradient(Gradient(colors: [Neo.court.opacity(0.35 * intensity), .clear]),
                                                 center: CGPoint(x: w / 2, y: h * 0.6), startRadius: 0, endRadius: w * 0.7))
        // surface
        var surface = Path()
        surface.move(to: p(0, -1)); surface.addLine(to: p(0, 1)); surface.addLine(to: p(1, 1)); surface.addLine(to: p(1, -1))
        surface.closeSubpath()
        context.fill(surface, with: .linearGradient(Gradient(colors: [Neo.court.opacity(0.05 * intensity), Neo.court.opacity(0.22 * intensity)]),
                                                     startPoint: CGPoint(x: w / 2, y: topY), endPoint: CGPoint(x: w / 2, y: botY)))
        // lignes
        var lines = Path()
        lines.move(to: p(0, -1)); lines.addLine(to: p(0, 1)); lines.addLine(to: p(1, 1)); lines.addLine(to: p(1, -1)); lines.closeSubpath()
        for k in [0.16, 0.74] { lines.move(to: p(k, -1)); lines.addLine(to: p(k, 1)) }
        lines.move(to: p(0.16, 0)); lines.addLine(to: p(0.74, 0))
        var glowCtx = context
        glowCtx.addFilter(.blur(radius: 6))
        glowCtx.stroke(lines, with: .color(Neo.cyan.opacity(0.55 * intensity)), lineWidth: 4)
        context.stroke(lines, with: .color(Neo.cyan.opacity(0.65 * intensity)), lineWidth: 1.2)
        // filet
        var net = Path()
        net.move(to: p(0.42, -1.04)); net.addLine(to: p(0.42, 1.04))
        context.stroke(net, with: .color(Color.white.opacity(0.7 * intensity)), lineWidth: 2)
        // balayage lumineux qui parcourt le terrain
        let k = (t.truncatingRemainder(dividingBy: 6.0)) / 6.0
        var scan = Path()
        scan.move(to: p(k, -1)); scan.addLine(to: p(k, 1))
        var scanCtx = context
        scanCtx.addFilter(.blur(radius: 8))
        scanCtx.stroke(scan, with: .color(Neo.volt.opacity(0.35 * intensity * (1 - k))), lineWidth: 10)
    }
}

// Petite balle de padel lumineuse (logo).
struct BallMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Neo.voltGradient)
            Circle().trim(from: 0.08, to: 0.42).stroke(Color.white.opacity(0.9), lineWidth: size * 0.07)
                .rotationEffect(.degrees(-30)).padding(size * 0.12)
            Circle().trim(from: 0.58, to: 0.92).stroke(Color.white.opacity(0.9), lineWidth: size * 0.07)
                .rotationEffect(.degrees(-30)).padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .neonGlow(Neo.volt, radius: size * 0.4)
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34, weight: .light)).foregroundStyle(Neo.cyan).neonGlow()
            Text(title).font(Neo.label(15)).foregroundStyle(Neo.text)
            Text(message).font(Neo.body(14)).foregroundStyle(Neo.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassCard()
    }
}
