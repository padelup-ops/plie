import SwiftUI

/// La carte « Nouveau : Foldboard », notre clavier pour le Duo. Fermée d'une croix, elle ne revient pas.
enum FoldboardPromoRule {
    static let key = "foldboardPromoHidden"
    static let url = URL(string: "https://apps.apple.com/app/id6832556606")!
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func hide() { UserDefaults.standard.set(true, forKey: key) }
    /// Le prix de lancement, affiché jusqu'au 18 novembre 2026 inclus.
    static var launchPrice: Bool {
        Date() < (DateComponents(calendar: .current, year: 2026, month: 11, day: 19).date ?? .distantPast)
    }
}

struct FoldboardPromo: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "keyboard.onehanded.right")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("New: Foldboard")
                        .font(.headline)
                    Text("Our keyboard for the Duo: it comes under the thumb of the hand holding your phone, and learns how you hold it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if FoldboardPromoRule.launchPrice {
                        Text("Launch price until November 18")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.dfAccent)
                    }
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
            Button(action: onOpen) {
                Label { Text("See Foldboard") } icon: { Image(systemName: "arrow.up.right") }
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
