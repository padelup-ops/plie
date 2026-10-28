import SwiftUI

// MARK: - Le jardin, partagé entre l'app et les widgets

enum Garden {
    /// Feuille, tulipe, arbre : la plante numéro `i`.
    static func symbol(_ i: Int) -> String {
        ["leaf.fill", "camera.macro", "tree.fill"][i % 3]
    }

    /// Un peu de relief : chaque plante a sa nuance.
    static func shade(_ i: Int) -> Double {
        0.55 + 0.45 * Double((i * 7) % 5) / 4
    }

    /// « 2 h 10 », « 25 min ».
    static func format(_ t: TimeInterval) -> String {
        let minutes = Int(max(0, t) / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: allowed, width: .abbreviated))
    }

    /// Pendant une session téléphone posé : la part de la plante en train de pousser (0 à 1), et les minutes qui restent.
    static func growing(since: Date, now: Date) -> (fraction: Double, minutesLeft: Int) {
        let period = ClapetStats.plantMinutes * 60
        let done = max(0, now.timeIntervalSince(since)).truncatingRemainder(dividingBy: period)
        return (done / period, max(1, Int(((period - done) / 60).rounded(.up))))
    }
}

/// Une rangée de plantes qui tient toujours dans la largeur : au-delà, un « +N ».
struct GardenStrip: View {
    let plants: Int
    var color: Color
    var size: CGFloat = 18

    var body: some View {
        GeometryReader { g in
            let spacing: CGFloat = 5
            let capacity = max(1, Int((g.size.width + spacing) / (size + spacing)))
            let overflow = plants > capacity
            // Deux places pour le « +N », pour qu'il ne déborde jamais.
            let shown = overflow ? max(0, capacity - 2) : plants
            HStack(spacing: spacing) {
                ForEach(0..<shown, id: \.self) { i in
                    Image(systemName: Garden.symbol(i))
                        .font(.system(size: size * 0.82, weight: .semibold))
                        .frame(width: size, height: size)
                        .foregroundStyle(color.opacity(Garden.shade(i)))
                }
                if overflow {
                    Text("+\(plants - shown)")
                        .font(.system(size: max(10, size * 0.6), weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(color)
                        .frame(width: size * 2 + spacing, height: size)
                        .background(Capsule().fill(color.opacity(0.16)))
                }
            }
        }
        .frame(height: size)
        .accessibilityHidden(true)
    }
}
