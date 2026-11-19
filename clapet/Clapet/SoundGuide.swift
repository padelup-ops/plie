import SwiftUI

// MARK: - Les sons dans Raccourcis (1.0.24)
//
// Montré une fois aux gens qui ont déjà plié (mise à jour), et toujours depuis
// l'écran du comptage automatique.

enum SoundGuide {
    static let key = "soundGuide.1.0.24"
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }

    /// Quelqu'un qui a déjà compté au moins un pli : pas le tout premier lancement.
    static func shouldOffer(stats: ClapetStats) -> Bool {
        !seen && !Demo.seeded && Demo.screen == nil && (stats.totalCloses > 0 || stats.firstDay != nil)
    }
}

struct SoundGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Play the fold sounds without opening Foldly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    row(1, Text("Open the Shortcuts app, go to the Automation tab, then tap +."))
                    row(2, Text("Choose When iPhone is Closed."))
                    row(3, Text("Add Foldly's Count a fold and Play the closing sound. In Play the closing sound, choose Which sound."))
                    row(4, Text("Do the same with When iPhone is Opened: add Count an opening and Play the opening sound."))
                } header: {
                    Text("The two automations")
                }
                Section {
                    row(5, Text("Turn each automation on. The banner Automation is disabled must not appear."))
                    row(6, Text("Set Run Immediately, and turn off Show When Run."))
                    row(7, Text("If Sounds even when Foldly is closed is on, Count a fold already plays a sound. Turn it off in Settings, Advanced, so you don't hear the sound twice."))
                } header: {
                    Text("So it really runs")
                }
                Section {
                    Text("If the sound still doesn't play: Settings, Advanced, Export sounds, then use Shortcuts' Play Sound on the saved file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("If there is no sound")
                }
                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label { Text("Open Shortcuts") } icon: { Image(systemName: "arrow.up.forward.app") }
                    }
                }
            }
            .navigationTitle(Text("Sounds in Shortcuts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .onAppear { SoundGuide.markSeen() }
        }
        .tint(.dfAccent)
    }

    private func row(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.dfOnAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.dfAccent))
            text
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
