import SwiftUI

/// Le Duo vu de profil, comme sur l'icône : deux panneaux autour de la charnière et l'arc de leur angle.
/// Suit la vraie charnière. `openness` va de 0 (fermé) à 1 (à plat, 180°).
struct HingeGauge: View {
    let openness: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let length = min(w * 0.42, h * 1.1)
            let line = max(5, length * 0.06)
            let hinge = CGPoint(x: w / 2 - length / 2, y: h - line)
            let degrees = 180 * max(0, min(1, openness))
            let rad = degrees * .pi / 180

            // La ligne de base (la moitié posée)
            var base = Path()
            base.move(to: CGPoint(x: hinge.x - length * 0.15, y: hinge.y))
            base.addLine(to: CGPoint(x: hinge.x + length * 1.15, y: hinge.y))
            context.stroke(base, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            // L'arc de l'angle
            if degrees > 3 {
                var arc = Path()
                arc.addArc(center: hinge, radius: length * 0.42, startAngle: .degrees(0), endAngle: .degrees(-degrees), clockwise: true)
                context.stroke(arc, with: .color(.accentColor), style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round))
            }
            // Les deux panneaux
            var panels = Path()
            panels.move(to: CGPoint(x: hinge.x + length * cos(rad), y: hinge.y - length * sin(rad)))
            panels.addLine(to: hinge)
            panels.addLine(to: CGPoint(x: hinge.x + length, y: hinge.y))
            context.stroke(panels, with: .foreground, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
}
