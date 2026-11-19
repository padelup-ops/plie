import Charts
import SwiftUI

// MARK: - Aujourd'hui, heure par heure (demandé par un utilisateur)
//
// 24 barres : combien de fois on a déplié à chaque heure aujourd'hui, l'heure de pointe, et l'heure en cours.
// Un toucher ou un glissement sur une barre affiche le nombre de plis et le temps exact de cette heure.

struct TodayByHour: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent
    var empty: Color = .dfFill
    var height: CGFloat = 46
    @State private var selectedHour: Int? = nil

    var body: some View {
        let hours = stats.hours()
        let top = max(1, hours.max() ?? 1)
        let peak = (hours.max() ?? 0) > 0 ? hours.firstIndex(of: top) : nil
        let picked = selectedHour.flatMap { (0..<24).contains($0) ? $0 : nil }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let picked {
                    BarValueCallout(title: Text(Self.label(picked)),
                                    folds: hours[picked],
                                    open: stats.hourOpen(picked),
                                    closed: stats.hourClosed(picked),
                                    measuredClosed: stats.autoLast != nil)
                } else if let peak {
                    Text("Peak \(Self.label(peak)) · \(FoldUnit.shown(hours[peak])) folds")
                } else {
                    Text("Fills in as you fold, hour by hour.")
                }
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    let n = hours[h]
                    BarMark(x: .value("Hour", h),
                            y: .value("Folds", n == 0 ? Double(top) * 0.08 : Double(n)))
                        .foregroundStyle(h == picked || (picked == nil && h == peak) ? accent : (n > 0 ? accent.opacity(0.45) : empty))
                        .cornerRadius(2)
                }
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...Double(top))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .modifier(ChartBarSelect(selection: $selectedHour))
            .frame(height: height)
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(Self.label(h)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            if picked == nil {
                Text("Touch a bar to see the exact time and the fold count.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today by hour"))
        .accessibilityValue(picked.map { h in
            let closedText = stats.autoLast != nil ? TimeFormat.short(stats.hourClosed(h)) : "—"
            return Text("\(FoldUnit.shown(hours[h])) folds · \(TimeFormat.short(stats.hourOpen(h))) open · \(closedText) closed")
        } ?? Text(peak.map { "Peak \(Self.label($0))" } ?? ""))
        .accessibilityHint(Text("Touch a bar to see the exact time and the fold count."))
    }

    static func label(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }
}

// MARK: - Le détail d'une barre (bilan de la semaine, aujourd'hui heure par heure)

/// Le jour du graphique le plus proche d'une sélection, s'il est vraiment sous le doigt.
func nearestChartDay<T>(_ selected: Date?, _ days: [T], date: (T) -> Date) -> T? {
    guard let selected, let best = days.min(by: { abs(date($0).timeIntervalSince(selected)) < abs(date($1).timeIntervalSince(selected)) }) else { return nil }
    return abs(date(best).timeIntervalSince(selected)) < 20 * 3600 ? best : nil
}

/// Sélection d'une barre au toucher ou au glissement. `chartXSelection` (iOS 17) et un geste
/// simultané, pour que la page puisse encore défiler.
struct ChartBarSelect<Value: Plottable>: ViewModifier {
    @Binding var selection: Value?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $selection)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear.contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let frame = geo[proxy.plotAreaFrame]
                                    let x = drag.location.x - frame.origin.x
                                    guard x >= 0, x <= frame.width else { return }
                                    if let value: Value = proxy.value(atX: x) {
                                        selection = value
                                    }
                                }
                        )
                }
            }
    }
}

/// Plis et durée exacte d'une barre. `measuredClosed` : les automatisations mesurent le temps fermé.
struct BarValueCallout: View {
    let title: Text
    let folds: Int
    let open: TimeInterval
    let closed: TimeInterval
    var measuredClosed = true

    var body: some View {
        let closedText = measuredClosed ? TimeFormat.short(closed) : "—"
        VStack(alignment: .leading, spacing: 1) {
            title.font(.caption.weight(.semibold)).foregroundStyle(.primary)
            Text("\(FoldUnit.shown(folds)) folds · \(TimeFormat.short(open)) open · \(closedText) closed")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
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
