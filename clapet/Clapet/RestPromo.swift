import SwiftUI

/// La carte « Nouveau : le temps au repos », montrée une fois après la mise à jour 1.0.13.
enum RestPromoRule {
    static let key = "restPromoHidden.1.0.13"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func hide() { UserDefaults.standard.set(true, forKey: key) }
}

struct RestPromo: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("New: time at rest")
                        .font(.headline)
                    Text("Foldly now tells open time at rest from the rest. Set your rest hours, or add the Shortcuts for the Sleep focus.")
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
            Button(action: onOpen) {
                Label { Text("Set rest hours") } icon: { Image(systemName: "arrow.up.right") }
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
