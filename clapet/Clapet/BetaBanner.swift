import SwiftUI

/// Seulement dans la version TestFlight : un petit bandeau qui invite à installer Foldly depuis l'App Store.
/// Il se ferme d'un geste et ne bloque jamais l'app.
struct BetaBanner: View {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6827349081")!
    @AppStorage("betaBannerClosed") private var closed = false
    @Environment(\.openURL) private var openURL

    /// Vrai dans un build TestFlight (reçu de test), faux pour la version App Store.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    var body: some View {
        if Self.isTestFlight && !closed {
            HStack(spacing: 12) {
                Image(systemName: "party.popper.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Foldly is now on the App Store")
                        .font(.subheadline.weight(.semibold))
                    Text("Install it to keep your data. The beta ends on November 9.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button("Install") { openURL(Self.appStoreURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button {
                    withAnimation { closed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .accessibilityLabel(Text("Close"))
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
