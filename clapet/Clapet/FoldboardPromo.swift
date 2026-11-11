import SwiftUI

/// La carte « Nouveau : Foldboard », notre clavier pour le Duo. Fermée d'une croix, elle ne revient pas.
/// Pack Duo : jusqu'au 30 novembre 2026, ceux qui ont Foldly+ ont Foldboard Pro à 1,99 € (code DUOPACK).
/// La carte revient pour eux (même s'ils avaient fermé l'annonce de Foldboard), avec le lien du code.
enum FoldboardPromoRule {
    static let key = "foldboardPromoHidden"
    static let packKey = "duoPackHidden"
    static let appURL = URL(string: "https://apps.apple.com/app/id6832556606")!
    static let packURL = URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=6832556606&code=DUOPACK")!
    static var packOpen: Bool {
        Date() < (DateComponents(calendar: .current, year: 2026, month: 12, day: 1).date ?? .distantPast)
    }
    /// Foldly+ acheté (ou l'app payante) et la période du pack en cours.
    static var pack: Bool {
        packOpen && ((ClapetModel.current?.stats.plus ?? false) || DuoFolds.paidApp)
    }
    static var url: URL { pack ? packURL : appURL }
    static var shouldShow: Bool {
        pack ? !UserDefaults.standard.bool(forKey: packKey) : !UserDefaults.standard.bool(forKey: key)
    }
    static func hide() { UserDefaults.standard.set(true, forKey: pack ? packKey : key) }
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
                    if FoldboardPromoRule.pack {
                        Text("Duo Pack: Foldboard Pro for €1.99")
                            .font(.headline)
                        Text("Thanks for Foldly+! Our keyboard for the Duo comes under the thumb of the hand holding your phone. Until November 30, Foldboard Pro is yours for €1.99.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("New: Foldboard")
                            .font(.headline)
                        Text("Our keyboard for the Duo: it comes under the thumb of the hand holding your phone, and learns how you hold it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !FoldboardPromoRule.pack && FoldboardPromoRule.launchPrice {
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
                Group {
                    if FoldboardPromoRule.pack {
                        Label { Text("Get it for €1.99") } icon: { Image(systemName: "gift.fill") }
                    } else {
                        Label { Text("See Foldboard") } icon: { Image(systemName: "arrow.up.right") }
                    }
                }
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
