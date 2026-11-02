import SwiftUI
import WidgetKit

// MARK: - Les complications de Foldly (Apple Watch)
//
// Le chiffre du jour sur le cadran : anneau, ligne, coin, ou rectangle avec la semaine.
// Les chiffres viennent du dernier envoi de l'iPhone, rangé par l'app de la montre.

struct WatchEntry: TimelineEntry {
    let date: Date
    let data: FoldlyWatchData?
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let data = WatchVault.load() ?? (context.isPreview ? .sample : nil)
        completion(WatchEntry(date: Date(), data: data))
    }

    /// Une entrée par quart d'heure (les durées avancent), et minuit pour repartir à zéro.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let data = WatchVault.load()
        let now = Date()
        var entries = (0..<12).map { WatchEntry(date: now.addingTimeInterval(Double($0) * 900), data: data) }
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime),
           midnight < entries.last?.date ?? now {
            entries.removeAll { $0.date >= midnight }
            entries.append(WatchEntry(date: midnight, data: data))
        }
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? now.addingTimeInterval(3600))))
    }
}

struct FoldlyComplicationView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: WatchEntry
    /// Pour les captures de la vidéo : force une famille hors d'un vrai cadran.
    var forced: WidgetFamily? = nil
    private var family: WidgetFamily { forced ?? widgetFamily }

    private var data: FoldlyWatchData? { entry.data?.current(at: entry.date) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryCorner: corner
            default: inline
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var today: Int { data?.today ?? 0 }

    @ViewBuilder
    private var circular: some View {
        if let data, let ref = data.reference, ref > 0 {
            Gauge(value: Double(min(today, ref)), in: 0...Double(ref)) {
                Image(systemName: "iphone.gen3")
            } currentValueLabel: {
                Text("\(today)")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(data.over ? WatchPalette.orange : WatchPalette.mint)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text("\(today)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text("folds")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        let week = (data?.week.count == 7 ? data?.week : nil) ?? Array(repeating: 0, count: 7)
        let top = max(1, week.max() ?? 1)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "FOLDLY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WatchPalette.mint)
                    .widgetAccentable()
                Text("\(today) folds")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                (data?.statusText ?? Text("Open Foldly on your iPhone"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(i == 6 ? WatchPalette.mint : Color.white.opacity(0.3))
                        .frame(width: 4, height: max(3, 30 * CGFloat(week[i]) / CGFloat(top)))
                }
            }
            .frame(height: 30, alignment: .bottom)
            .widgetAccentable()
        }
    }

    private var corner: some View {
        Text("\(today)")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetLabel {
                if let data, let ref = data.reference, ref > 0 {
                    Gauge(value: Double(min(today, ref)), in: 0...Double(ref)) {
                        Text("folds")
                    }
                    .tint(WatchPalette.mint)
                } else {
                    Text("folds today")
                }
            }
    }

    private var inline: some View {
        Label {
            Text("\(today) folds today")
        } icon: {
            Image(systemName: "iphone.gen3")
        }
    }
}

struct FoldlyComplication: Widget {
    let kind = "FoldlyWatchToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            FoldlyComplicationView(entry: entry)
        }
        .configurationDisplayName(Text("Folds today"))
        .description(Text("Today's folds from your iPhone, compared with your average."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct FoldlyWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        FoldlyComplication()
    }
}
