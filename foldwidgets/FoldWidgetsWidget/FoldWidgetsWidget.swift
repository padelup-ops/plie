import SwiftUI
import WidgetKit

// Le widget ne peut pas savoir si le Duo est plié. PanelRole le déduit de la
// famille : petit et complications = couverture, moyen = deux volets,
// grand = diptyque intérieur. Les réglages (mot, citation, date, humeur)
// viennent du groupe d'app ; l'angle de la charnière n'y est pas écrit.

extension PanelRole {
    /// WidgetKit has no fold angle. The family is the stand-in:
    /// small and Lock Screen = cover, medium = two panes, large = inner diptych.
    init(family: WidgetFamily) {
        switch family {
        case .systemLarge, .systemExtraLarge:
            self = .diptych
        case .systemMedium:
            self = .pair
        default:
            self = .cover
        }
    }
}

struct FoldEntry: TimelineEntry {
    var date: Date
    var settings: FoldSettings
}

struct FoldProvider: TimelineProvider {
    var theme: FoldTheme

    func placeholder(in context: Context) -> FoldEntry {
        var settings = FoldSettings()
        settings.theme = theme
        return FoldEntry(date: Date(), settings: settings)
    }

    func getSnapshot(in context: Context, completion: @escaping (FoldEntry) -> Void) {
        completion(FoldEntry(date: Date(), settings: themed(FoldStore.load())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoldEntry>) -> Void) {
        let settings = themed(FoldStore.load())
        let now = Date()
        switch theme {
        case .hour:
            let entries = (0..<60).map { index in
                FoldEntry(date: now.addingTimeInterval(Double(index) * 60), settings: settings)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        case .countdown:
            let entries = (0..<48).map { index in
                FoldEntry(date: now.addingTimeInterval(Double(index) * 3600), settings: settings)
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        default:
            let next = now.addingTimeInterval(6 * 60 * 60)
            completion(Timeline(entries: [FoldEntry(date: now, settings: settings)], policy: .after(next)))
        }
    }

    private func themed(_ settings: FoldSettings) -> FoldSettings {
        var copy = settings
        copy.theme = theme
        return copy
    }
}

struct FoldWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FoldEntry

    var body: some View {
        content
            .containerBackground(Ink.resolve(entry.settings).ground, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.settings.inline(at: entry.date))
                .lineLimit(1)
        case .accessoryCircular:
            Text(entry.settings.badge(at: entry.date))
                .font(.headline.weight(.medium))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(entry.settings.theme.nameKey, comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.settings.inline(at: entry.date))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            GeometryReader { geo in
                FoldArtwork(
                    settings: entry.settings,
                    mode: .widget(PanelRole(family: family)),
                    date: entry.date,
                    openAmount: 1,
                    size: geo.size
                )
            }
        }
    }
}

/// `Widget` exige `init()`. Le thème est donc figé dans chaque type, et le dessin est partagé.
private func foldWidget(_ theme: FoldTheme) -> some WidgetConfiguration {
    StaticConfiguration(kind: "fold." + theme.rawValue, provider: FoldProvider(theme: theme)) { entry in
        FoldWidgetView(entry: entry)
    }
    .configurationDisplayName(Text(NSLocalizedString(theme.nameKey, comment: "")))
    .description(Text(NSLocalizedString(theme.detailKey, comment: "")))
    .supportedFamilies([
        .systemSmall,
        .systemMedium,
        .systemLarge,
        .accessoryCircular,
        .accessoryRectangular,
        .accessoryInline
    ])
}

struct RevelationWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.revelation) }
}

struct HourWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.hour) }
}

struct QuoteWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.quote) }
}

struct DiptychWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.diptych) }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.countdown) }
}

struct MoodWidget: Widget {
    var body: some WidgetConfiguration { foldWidget(.mood) }
}

@main
struct FoldWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RevelationWidget()
        HourWidget()
        QuoteWidget()
        DiptychWidget()
        CountdownWidget()
        MoodWidget()
    }
}
