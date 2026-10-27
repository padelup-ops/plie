import SwiftUI

/// La mascotte : un iPhone Duo vu de côté, ouvert comme une bouche, avec deux gros yeux.
/// `openness` va de 0 (fermé) à 1 (grand ouvert).
struct MascotView: View {
    let openness: Double
    var blink = false

    static let body0 = Color(red: 0.17, green: 0.19, blue: 0.40)
    static let body1 = Color(red: 0.08, green: 0.10, blue: 0.21)
    static let screen0 = Color(red: 0.49, green: 0.98, blue: 1.0)
    static let screen1 = Color(red: 0.24, green: 0.72, blue: 1.0)

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let length = w * 0.66
            let thick = w * 0.12
            let hinge = CGPoint(x: w * 0.18, y: h * 0.72)
            let openDeg = 4 + 40 * max(0, min(1, openness))

            // Lueur de l'écran intérieur, dans la bouche
            if openness > 0.05 {
                let glow = CGRect(x: hinge.x + length * 0.15, y: hinge.y - length * 0.42 * openness - thick,
                                  width: length * 0.8, height: length * 0.5 * openness + thick)
                context.fill(Path(ellipseIn: glow), with: .radialGradient(
                    Gradient(colors: [Self.screen0.opacity(0.55 * openness), Self.screen0.opacity(0)]),
                    center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 0, endRadius: glow.width * 0.55))
            }
            // Moitié basse
            slab(context, at: hinge, angle: .degrees(-4), length: length, thick: thick, top: false)
            // La langue
            var tongue = context
            tongue.translateBy(x: hinge.x, y: hinge.y)
            tongue.rotate(by: .degrees(-4 - 6 * openness))
            var t = Path()
            t.move(to: CGPoint(x: thick * 0.6, y: -2))
            t.addQuadCurve(to: CGPoint(x: length * 0.48, y: -2), control: CGPoint(x: length * 0.25, y: -thick * 0.9 * openness - 2))
            t.closeSubpath()
            tongue.fill(t, with: .color(Color(red: 1, green: 0.36, blue: 0.54)))
            // Moitié haute
            slab(context, at: hinge, angle: .degrees(-4 - openDeg), length: length, thick: thick, top: true)
            // La charnière
            let r = thick * 0.75
            context.fill(Path(ellipseIn: CGRect(x: hinge.x - r, y: hinge.y - r, width: 2 * r, height: 2 * r)),
                         with: .linearGradient(Gradient(colors: [Self.body0, Self.body1]), startPoint: CGPoint(x: hinge.x, y: hinge.y - r), endPoint: CGPoint(x: hinge.x, y: hinge.y + r)))
            context.fill(Path(ellipseIn: CGRect(x: hinge.x - r * 0.35, y: hinge.y - r * 0.35, width: r * 0.7, height: r * 0.7)),
                         with: .color(Color(red: 1, green: 0.82, blue: 0.25)))
        }
        .accessibilityHidden(true)
    }

    private func slab(_ context: GraphicsContext, at hinge: CGPoint, angle: Angle, length: CGFloat, thick: CGFloat, top: Bool) {
        var c = context
        c.translateBy(x: hinge.x, y: hinge.y)
        c.rotate(by: angle)
        let rect = CGRect(x: -thick * 0.5, y: top ? -thick : 0, width: length + thick * 0.5, height: thick)
        c.fill(Path(roundedRect: rect, cornerRadius: thick / 2),
               with: .linearGradient(Gradient(colors: [Self.body0, Self.body1]), startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        // L'écran, sur la face intérieure
        let screen = CGRect(x: thick * 0.45, y: top ? -thick * 0.34 : thick * 0.04, width: length - thick * 0.9, height: thick * 0.3)
        c.fill(Path(roundedRect: screen, cornerRadius: thick * 0.15),
               with: .linearGradient(Gradient(colors: [Self.screen0, Self.screen1]), startPoint: CGPoint(x: screen.minX, y: 0), endPoint: CGPoint(x: screen.maxX, y: 0)))
        guard top else { return }
        // Les yeux, posés sur le dessus
        let eye = thick * 0.85
        for x in [length * 0.55, length * 0.82] {
            let center = CGPoint(x: x, y: -thick - eye * 0.7)
            c.fill(Path(ellipseIn: CGRect(x: center.x - eye, y: center.y - eye * (blink ? 0.15 : 1), width: 2 * eye, height: 2 * eye * (blink ? 0.15 : 1))), with: .color(.white))
            guard !blink else { continue }
            let pupil = eye * 0.46
            let px = center.x + eye * 0.25, py = center.y + eye * 0.1
            c.fill(Path(ellipseIn: CGRect(x: px - pupil, y: py - pupil, width: 2 * pupil, height: 2 * pupil)), with: .color(Self.body1))
            let shine = pupil * 0.32
            c.fill(Path(ellipseIn: CGRect(x: px + pupil * 0.2 - shine, y: py - pupil * 0.45 - shine, width: 2 * shine, height: 2 * shine)), with: .color(.white))
        }
    }
}
