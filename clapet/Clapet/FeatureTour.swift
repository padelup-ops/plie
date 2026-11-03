import SwiftUI

/// La visite guidée : où trouver chaque chose dans Foldly.
/// Une fois après le choix du thème (nouveaux utilisateurs) ou après la mise à jour, et à revoir depuis les Réglages.
enum TourRule {
    static let key = "tourSeen.1.0.2"
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

struct FeatureTour: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Stop: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: Text
        let body: Text
        let place: Text
    }

    private var stops: [Stop] {
        [
            Stop(icon: "hand.wave.fill", color: .orange,
                 title: Text("Welcome to Foldly"),
                 body: Text("Foldly counts every time you fold your iPhone Duo, so you can see your habit and keep it under control. Here's where everything is."),
                 place: Text("Swipe to continue")),
            Stop(icon: "number", color: .mint,
                 title: Text("Your count, all day"),
                 body: Text("On screen, Foldly reads the hinge itself. To count even when the app is closed, set up the Shortcuts automation once: Foldly shows you how."),
                 place: Text("Settings › How it counts")),
            Stop(icon: "target", color: .red,
                 title: Text("Your own daily limit"),
                 body: Text("Turn on a limit and tap the number to type yours. Foldly warns you at 80 % and 100 %."),
                 place: Text("Settings › Daily limit")),
            Stop(icon: "trophy.fill", color: .yellow,
                 title: Text("Leaderboards"),
                 body: Text("Compare your longest streak under your limit, and your last 30 days, with other Foldly users and friends, through Game Center. Off until you turn it on."),
                 place: Text("Settings › Leaderboard")),
            Stop(icon: "laptopcomputer", color: .blue,
                 title: Text("Desk mode"),
                 body: Text("Open your Duo halfway. Held like a book, you get two pages. Set on the table, the count stands on top."),
                 place: Text("Just open your Duo halfway")),
            Stop(icon: "paintpalette.fill", color: .purple,
                 title: Text("Themes, widgets and Apple Watch"),
                 body: Text("Try the new Aurora theme. Add Foldly widgets to your Home and Lock Screen, and the complications to your watch face."),
                 place: Text("Settings › Theme · Home Screen › Edit › Add widget · Watch app")),
            Stop(icon: "cup.and.saucer.fill", color: .brown,
                 title: Text("Break reminder"),
                 body: Text("When your Duo stays open for a while, Foldly can suggest a short break, on your iPhone or your Apple Watch."),
                 place: Text("Settings › Break reminder")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .foregroundStyle(.secondary)
                    .opacity(page < stops.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            TabView(selection: $page) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    VStack(spacing: 20) {
                        Spacer(minLength: 0)
                        Image(systemName: stop.icon)
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(stop.color)
                            .frame(width: 112, height: 112)
                            .background(stop.color.opacity(0.15), in: Circle())
                        stop.title
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                        stop.body
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Label { stop.place } icon: { Image(systemName: "location.fill") }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .opacity(i == 0 ? 0 : 1)
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
                if page < stops.count - 1 { withAnimation { page += 1 } } else { finish() }
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

    private func finish() {
        TourRule.markSeen()
        dismiss()
    }
}
