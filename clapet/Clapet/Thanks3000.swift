import SwiftUI

// MARK: - Merci pour les 3 000 téléchargements
//
// Carte dans l'app, comme les annonces précédentes (pas de carte distante : foldly.netlify.app
// ne sert qu'à une version minimale, et le fichier n'est pas en ligne). Visible jusqu'à la fin
// du vendredi 20 novembre 2026, heure de Paris. Foldly+ reste à 0,99 € / 0,99 $ jusqu'au
// samedi 21 novembre 9 h à Paris (minuit, heure du Pacifique, le cran le plus proche chez Apple).

enum Thanks3000 {
    private static let hiddenKey = "thanks3000Hidden"

    private static var paris: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }

    /// Samedi 21 novembre 2026, 0 h à Paris : la carte couvre encore tout le vendredi.
    static var end: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 21
        return paris.date(from: c) ?? .distantPast
    }

    static var shouldShow: Bool {
        guard Date() < end, !Demo.seeded else { return false }
        return !UserDefaults.standard.bool(forKey: hiddenKey)
    }

    static func hide() { UserDefaults.standard.set(true, forKey: hiddenKey) }
}

struct Thanks3000Card: View {
    var hasPlus: Bool
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "party.popper.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thank you for 3,000 downloads! 🎉")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Foldly just passed 3,000 downloads. Thank you for folding with us and for all your ideas in the idea box. To celebrate, Foldly+ stays at $0.99 until Friday. Keep the ideas coming!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.dfFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Not now"))
            }
            if !hasPlus {
                Button(action: onOpen) {
                    Label { Text("See Foldly+") } icon: { Image(systemName: "gift") }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.dfAccent)
                .foregroundStyle(Color.dfOnAccent)
            }
        }
    }
}
