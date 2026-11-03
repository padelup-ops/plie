import SwiftUI

/// Le look « Aurore » : un ciel de nuit bleu profond, des aurores boréales qui ondulent lentement
/// (et bougent un peu avec la charnière), quelques étoiles, et des chiffres lumineux.
enum Aurora {
    static let night = Color(red: 0.035, green: 0.043, blue: 0.11)
    static let deep = Color(red: 0.07, green: 0.06, blue: 0.2)
    static let mint = Color(red: 0.42, green: 0.98, blue: 0.78)
    static let teal = Color(red: 0.18, green: 0.78, blue: 0.86)
    static let violet = Color(red: 0.6, green: 0.45, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.48, blue: 0.78)
    /// L'accent des boutons et des jauges.
    static let accent = Color(red: 0.55, green: 0.92, blue: 0.86)
    /// Le dégradé des grands chiffres.
    static let glow = LinearGradient(colors: [mint, teal, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Le fond de l'écran : l'aurore pour le look Aurore, la couleur unie pour les autres.
struct DFBackdrop: View {
    var degrees: Double? = nil

    var body: some View {
        if DFLook.current == .aurora {
            AuroraBackdrop(degrees: degrees)
        } else if DFLook.current == .custom {
            CustomBackdrop()
        } else {
            Color.dfBackground
        }
    }
}

/// Le ciel et ses aurores. `animated: false` pour les petits aperçus.
struct AuroraBackdrop: View {
    var degrees: Double? = nil
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stars: [(x: Double, y: Double, r: Double, phase: Double)] = (0..<46).map { i in
        // Positions fixes (pas d'aléatoire : le ciel reste le même d'une ouverture à l'autre).
        let a = Double(i) * 12.9898, b = Double(i) * 78.233
        let x = (sin(a) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let y = (sin(b) * 12543.123).truncatingRemainder(dividingBy: 1)
        return (abs(x), abs(y) * 0.75, 0.6 + abs(x - y) * 1.1, abs(x * 7).truncatingRemainder(dividingBy: 1))
    }

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                sky(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            sky(t: 12)
        }
    }

    private func sky(t: Double) -> some View {
        // La charnière décale doucement les voiles (0 à 180°).
        let hinge = ((degrees ?? 90) - 90) / 90
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Aurora.deep, Aurora.night, Aurora.night]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Étoiles qui scintillent
            for s in Self.stars {
                let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.3 + s.phase * 6.28))
                let rect = CGRect(x: s.x * w, y: s.y * h, width: s.r, height: s.r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 * twinkle)))
            }
            // Trois voiles d'aurore, flous, qui ondulent
            var glow = ctx
            glow.addFilter(.blur(radius: min(w, h) * 0.09))
            glow.blendMode = .screen
            let veils: [(Color, Double, Double, Double)] = [
                (Aurora.mint, 0.22, 0.9, 0.0),
                (Aurora.violet, 0.34, 0.7, 2.1),
                (Aurora.pink, 0.46, 0.55, 4.2),
            ]
            for (color, base, opacity, phase) in veils {
                var path = Path()
                let top = h * base
                let steps = 24
                path.move(to: CGPoint(x: -40, y: h * 0.95))
                for i in 0...steps {
                    let x = Double(i) / Double(steps)
                    let wave = sin(x * 5.2 + t * 0.35 + phase) * 0.06 + sin(x * 2.3 - t * 0.22 + phase) * 0.05
                    let y = top + h * (wave + hinge * 0.05 * sin(x * 3 + phase))
                    path.addLine(to: CGPoint(x: -40 + x * (w + 80), y: y))
                }
                path.addLine(to: CGPoint(x: w + 40, y: h * 0.95))
                path.closeSubpath()
                glow.fill(path, with: .linearGradient(
                    Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear]),
                    startPoint: CGPoint(x: 0, y: top - h * 0.08), endPoint: CGPoint(x: 0, y: top + h * 0.32)))
            }
        }
    }
}
