import SwiftUI

// MARK: - Aujourd'hui, heure par heure (demandé par un utilisateur)
//
// 24 barres : combien de fois on a déplié à chaque heure aujourd'hui, l'heure de pointe, et l'heure en cours.

struct TodayByHour: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent
    var empty: Color = .dfFill
    var height: CGFloat = 46

    var body: some View {
        let hours = stats.hours()
        let top = max(1, hours.max() ?? 1)
        let peak = (hours.max() ?? 0) > 0 ? hours.firstIndex(of: top) : nil
        let now = Calendar.current.component(.hour, from: Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let peak {
                    Text("Peak \(Self.label(peak)) · \(FoldUnit.shown(hours[peak])) folds")
                } else {
                    Text("Fills in as you fold, hour by hour.")
                }
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == peak ? accent : (hours[h] > 0 ? accent.opacity(0.45) : empty))
                        .frame(height: max(4, height * CGFloat(hours[h]) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            if h == now {
                                Circle().fill(Color.primary).frame(width: 4, height: 4).offset(y: 7)
                            }
                        }
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(Self.label(h)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today by hour"))
        .accessibilityValue(Text(peak.map { "Peak \(Self.label($0))" } ?? ""))
    }

    static func label(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }
}

/// Les bilans toujours à portée de main (la notification et la carte de l'accueil ne durent pas).
struct RecapLinks: View {
    var onWeek: () -> Void
    var onMonth: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onWeek) {
                Label { Text("Weekly recap") } icon: { Image(systemName: "chart.bar.doc.horizontal") }
                    .frame(maxWidth: .infinity)
            }
            Button(action: onMonth) {
                Label { Text("Monthly recap") } icon: { Image(systemName: "calendar") }
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
    }
}
