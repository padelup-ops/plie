import SwiftUI

// MARK: - Tes heures (demandé dans le sondage)
//
// À quel moment de la journée on déplie le plus : la journée type (24 barres), la semaine type (7 × 24),
// et deux ou trois phrases simples. Tout est calculé sur les plis depuis le début.

struct HoursContent: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent
    var showsGrid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let peak = stats.peakHour {
                Text("You fold the most around \(HoursText.hour(peak))")
                    .font(.headline)
            } else {
                Text("Fills in as you fold, hour by hour.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TypicalDayBars(hours: stats.typicalDay, accent: accent, empty: Color.dfFill)
            if showsGrid {
                HoursGrid(grid: stats.weekHours, accent: accent, empty: Color.dfFill)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let slot = stats.busiestSlot {
                    insight("flame.fill", Text("Busiest moment: \(HoursText.weekday(slot.weekday)), around \(HoursText.hour(slot.hour))"))
                }
                if let quiet = stats.quietHour {
                    insight("leaf.fill", Text("Calmest while you're awake: around \(HoursText.hour(quiet))"))
                }
                if let evening = stats.eveningShare {
                    let pct = evening.formatted(.percent.precision(.fractionLength(0)))
                    insight("moon.stars.fill", Text("\(pct) of your folds come after \(HoursText.hour(20))"))
                }
            }
        }
    }

    private func insight(_ symbol: String, _ text: Text) -> some View {
        Label { text } icon: { Image(systemName: symbol).foregroundStyle(accent) }
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// La feuille « Tes heures » (look Épuré, menu, widget).
struct HoursSheet: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                HoursContent(stats: model.stats)
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.dfCard))
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                Text("Counted since your first day with Foldly, on every day of the week.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Your hours"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .tint(.dfAccent)
    }
}
