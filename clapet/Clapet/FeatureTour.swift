import SwiftUI

/// La visite guidée : 4 pages courtes, chacune avec un bouton « Essayer » qui ouvre le bon écran.
/// Une fois après le choix du thème (nouveaux utilisateurs) ou après la mise à jour, et à revoir depuis les Réglages.
enum TourRule {
    static let key = "tourSeen.1.0.3"
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

/// Où mène le bouton « Essayer ».
enum TourTarget: String, Identifiable {
    case autoCount, settings, leaderboards
    var id: String { rawValue }
}

struct FeatureTour: View {
    /// Appelé quand on touche « Essayer » (la visite se ferme d'abord).
    var onTry: (TourTarget) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Stop {
        let icon: String
        let color: Color
        let title: Text
        let body: Text
        let target: TourTarget
    }

    private let stops: [Stop] = [
        Stop(icon: "bolt.fill", color: .mint,
             title: Text("Count all day"),
             body: Text("Foldly counts on its own while it's on screen. One short setup, and it counts even when the app is closed."),
             target: .autoCount),
        Stop(icon: "target", color: .red,
             title: Text("Set your daily limit"),
             body: Text("Pick how many folds a day is enough for you. Foldly tells you when you get close."),
             target: .settings),
        Stop(icon: "trophy.fill", color: .orange,
             title: Text("Climb the leaderboards"),
             body: Text("Stay under your limit day after day, and compare with other Foldly users. Tap the trophy at the top."),
             target: .leaderboards),
        Stop(icon: "paintpalette.fill", color: .purple,
             title: Text("Make it yours"),
             body: Text("Try the new Aurora theme, and add Foldly widgets to your Home Screen and your Apple Watch."),
             target: .settings),
        Stop(icon: "moon.zzz.fill", color: .indigo,
             title: Text("Open, but at rest"),
             body: Text("Set your rest hours in Settings: open time then counts as rest. You can also add the two Shortcuts for the Sleep focus."),
             target: .settings),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { close() }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            TabView(selection: $page) {
                ForEach(stops.indices, id: \.self) { i in
                    let stop = stops[i]
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        Image(systemName: stop.icon)
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(stop.color)
                            .frame(width: 120, height: 120)
                            .background(stop.color.opacity(0.15), in: Circle())
                        stop.title
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                        stop.body
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            TourRule.markSeen()
                            dismiss()
                            onTry(stop.target)
                        } label: {
                            Text("Try it")
                                .font(.headline)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .tint(stop.color)
                        .buttonBorderShape(.capsule)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: 520)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < stops.count - 1 { withAnimation { page += 1 } } else { close() }
            } label: {
                (page < stops.count - 1 ? Text("Next") : Text("Let's go"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 520)
        }
        .onDisappear { TourRule.markSeen() }
    }

    private func close() {
        TourRule.markSeen()
        dismiss()
    }
}
