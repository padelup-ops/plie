import SwiftUI

// MARK: - Les Fondateurs (les 2 000 premiers)
//
// Merci aux premiers : ceux qui ont ouvert Foldly avant le 1er décembre 2026 reçoivent un badge et une couleur
// de widget à eux, l'Or 2K, sans Foldly+. Un écran le leur annonce une fois.

enum FounderWelcomeRule {
    static let key = "founderWelcomeSeen"
    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Le badge, dans les réglages.
struct FounderBadge: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundStyle(ClapetTheme.gold.color.gradient)
                .frame(width: 44, height: 44)
                .background(Circle().fill(ClapetTheme.gold.color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Founder").font(.headline)
                Text("One of the first 2,000. Thank you!").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// L'annonce, une fois : merci, le badge, et l'Or 2K à essayer tout de suite.
struct FounderWelcome: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ZStack {
                Circle().fill(ClapetTheme.gold.color.opacity(0.14)).frame(width: 150, height: 150)
                    .scaleEffect(shown ? 1 : 0.6)
                Text(verbatim: "2K")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(ClapetTheme.gold.color.gradient)
                    .scaleEffect(shown ? 1 : 0.4)
                    .rotationEffect(.degrees(shown ? 0 : -12))
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: shown)
            VStack(spacing: 10) {
                Text("Thank you, Founder!")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Foldly just passed 2,000 downloads. You are one of the very first: you get the Founder badge, and a widget color of your own, Gold 2K.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 10)
            VStack(spacing: 12) {
                Button {
                    model.setTheme(.gold)
                    dismiss()
                } label: {
                    Text("Use Gold 2K on my widgets")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ClapetTheme.gold.color))
                        .foregroundStyle(.black)
                }
                Button { dismiss() } label: {
                    Text("Later").font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 520)
        .onAppear {
            FounderWelcomeRule.seen = true
            shown = true
        }
    }
}
