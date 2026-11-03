import SwiftUI

/// Le petit écran extérieur (Duo fermé) : l'essentiel d'un coup d'œil.
/// Le chiffre du jour, ta limite et ta série. Pour tout voir : déplier le Duo, ou « Voir le détail ».
/// La vue d'accueil complète reste dessous (elle lit la charnière et ouvre les feuilles).
struct OuterGlance: View {
    let look: DFLook
    var onDetails: () -> Void
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @State private var showSettings = false
    @State private var showBoards = false

    private var stats: ClapetStats { model.stats }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                LeaderboardButton(show: $showBoards)
                    .font(.title3)
                    .frame(width: 40, height: 44)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel(Text("Settings"))
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)

            // Le chiffre du jour
            VStack(spacing: 2) {
                Text("\(stats.today)")
                    .font(.system(size: 120, weight: look == .classic ? .bold : .light,
                                  design: look == .aurora || look == .classic ? .rounded : .default))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(look == .aurora ? AnyShapeStyle(Aurora.glow) : AnyShapeStyle(Color.primary))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: stats.today)
                Text(stats.today == 1 ? "fold today" : "folds today")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            // Ta limite
            if stats.goalOn {
                let left = stats.left()
                VStack(spacing: 8) {
                    ProgressView(value: min(1, Double(stats.today) / Double(max(1, stats.goal))))
                        .tint(left < 0 ? Color.dfOver : (Double(stats.today) >= 0.8 * Double(stats.goal) ? Color.dfWarning : Color.dfAccent))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    Group {
                        if left > 0 {
                            Text("\(left) left today")
                        } else if left == 0 {
                            Text("Limit reached")
                        } else {
                            Text("\(-left) over the limit")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(left < 0 ? Color.dfOver : Color.primary)
                }
                .padding(.horizontal, 44)
                .padding(.top, 18)
            }

            // Ta série
            let streak = stats.currentStreak()
            if stats.goalOn && streak > 1 {
                Label { Text("\(streak) days in a row under your limit") } icon: { Image(systemName: "flame.fill").foregroundStyle(.orange) }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.dfCard, in: Capsule())
                    .padding(.top, 16)
            }

            Spacer(minLength: 8)

            // Pour lire plus
            VStack(spacing: 10) {
                Label { Text("Unfold your Duo to see everything") } icon: { Image(systemName: "rectangle.portrait.on.rectangle.portrait") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: onDetails) {
                    Text("See details")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.dfAccent)
            }
            .padding(.bottom, 18)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DFBackdrop(degrees: model.degrees).ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView().environment(model).environment(store) }
        .sheet(isPresented: $showBoards) { LeaderboardView().environment(model).environment(store) }
    }
}
