import SwiftUI
import UIKit

/// « Ta semaine de frappe » : mots, vitesse, corrections, glisser et ta main préférée, à partager en image.
/// Tout est compté sur le téléphone (rien n'est envoyé).
struct RecapRow: View {
    @State private var stats = KBVault.loadStats()
    @Environment(\.scenePhase) private var phase

    private var week: KBStats.Day { stats.total(lastDays: 7) }

    var body: some View {
        Section {
            if week.words < 5 {
                Label {
                    Text("Type a few messages with Foldboard: your week will show up here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Color.accentColor)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(Color.accentColor)
                        Text("Your week of typing").font(.headline)
                        Spacer()
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        RecapStat(value: "\(week.words)", label: "words")
                        RecapStat(value: week.wpm.map { "\($0)" } ?? "–", label: "words per minute")
                        RecapStat(value: "\(week.corrections)", label: "typos fixed")
                        RecapStat(value: "\(week.glides)", label: "words slid")
                    }
                    if let h = week.favoriteHand {
                        Label { Text(RecapRow.handText(h)) } icon: { Image(systemName: h == 2 ? "hands.clap" : "hand.raised") }
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let img = shareImage() {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(Text("My week with Foldboard"), image: Image(uiImage: img))) {
                            Label("Share my week", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } footer: {
            Text("Counted on your iPhone only, never sent anywhere.")
        }
        .onChange(of: phase) { if phase == .active { stats = KBVault.loadStats() } }
        .onAppear { stats = KBVault.loadStats() }
    }

    static func handText(_ h: Int) -> LocalizedStringKey {
        switch h {
        case 1: return "Mostly typed with your right thumb"
        case 0: return "Mostly typed with your left thumb"
        default: return "Mostly typed with both hands"
        }
    }

    @MainActor private func shareImage() -> UIImage? {
        let r = ImageRenderer(content: RecapShareCard(week: week).frame(width: 360, height: 450))
        r.scale = 3
        return r.uiImage
    }
}

private struct RecapStat: View {
    let value: String
    let label: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// L'image partagée : grande, lisible, aux couleurs de l'icône.
struct RecapShareCard: View {
    let week: KBStats.Day
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.40), Color(red: 0.02, green: 0.03, blue: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard").font(.headline)
                    Text("Foldboard").font(.headline)
                    Spacer()
                    Text("My week").font(.subheadline).opacity(0.7)
                }
                Spacer(minLength: 0)
                Text("\(week.words)").font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("words typed on my iPhone Duo").font(.title3.weight(.semibold)).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 22) {
                    mini(week.wpm.map { "\($0)" } ?? "–", "wpm")
                    mini("\(week.corrections)", "typos fixed")
                    mini("\(week.glides)", "words slid")
                }
                Spacer(minLength: 0)
                Text("The keyboard that follows your hand").font(.footnote).opacity(0.6)
            }
            .padding(28)
            .foregroundStyle(.white)
        }
    }
    private func mini(_ v: String, _ l: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.bold()).monospacedDigit()
            Text(l).font(.caption).opacity(0.7)
        }
    }
}
