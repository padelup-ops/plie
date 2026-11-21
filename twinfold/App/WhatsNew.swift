// WhatsNew.swift — Twinfold
//
// After an update, what changed (once), and every version's changes in Settings.

import SwiftUI

struct Release: Identifiable {
    let version: String
    let items: [(String, LocalizedStringKey)]
    var id: String { version }
}

enum WhatsNew {
    /// Newest first. Each item: an SF Symbol and a short line.
    static let releases: [Release] = [
        Release(version: "1.0", items: [
            ("rectangle.split.2x1", "Two pages at once: at the fold of iPhone Duo, top and bottom or side by side on any iPhone and iPad"),
            ("hand.draw", "Gestures you choose: two-finger swipes and taps for back, private tab, swap, scroll together, full screen and more"),
            ("arrow.up.and.down.text.horizontal", "Scroll the two pages together"),
            ("speaker.wave.2", "A sound button on each pane: two videos at once, you choose the one you hear"),
            ("sparkles", "Ask AI in the other pane: ChatGPT, Claude, Gemini, Le Chat, Perplexity, Copilot"),
            ("square.on.square", "Pairs: two pages in one tap, even from the Home Screen"),
            ("doc.plaintext", "Reader view and read aloud, PDF, followed sites"),
            ("hand.raised", "Ads and trackers blocked, no account, no server"),
        ]),
    ]

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// True once after an update (never on a first install, never in screenshots).
    static func shouldShow() -> Bool {
        guard ShotMode.current == nil else { return false }
        let d = UserDefaults.standard
        let last = d.string(forKey: "lastSeenVersion")
        d.set(current, forKey: "lastSeenVersion")
        guard let last, last != current else { return false }
        return releases.contains { current.hasPrefix($0.version) }
    }
}

struct ReleaseView: View {
    let release: Release

    var body: some View {
        ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
            Label { Text(item.1) } icon: { Image(systemName: item.0).foregroundStyle(Brand.accent) }
        }
    }
}

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let r = WhatsNew.releases.first(where: { WhatsNew.current.hasPrefix($0.version) }) ?? WhatsNew.releases.first {
                    Section { ReleaseView(release: r) } header: { Text("Version \(r.version)") }
                }
            }
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Continue") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct WhatsNewList: View {
    var body: some View {
        List {
            ForEach(WhatsNew.releases) { r in
                Section { ReleaseView(release: r) } header: { Text("Version \(r.version)") }
            }
        }
        .navigationTitle("What's New")
    }
}
