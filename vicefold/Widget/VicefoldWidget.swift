// VicefoldWidget.swift — Vicefold
//
// Les widgets : ton 100 % et la prochaine mission (écran d'accueil et écran verrouillé), et le compte des jours
// depuis la sortie du jeu. Leur dessin est dans Shared/WidgetFaces.swift (le même que l'aperçu dans l'app).

import SwiftUI
import WidgetKit

struct VFEntry: TimelineEntry {
    var date: Date
    var snap: VFSnapshot
}

struct VFProvider: TimelineProvider {
    func placeholder(in context: Context) -> VFEntry {
        var s = VFSnapshot()
        s.percent = 0.42; s.missions = 0.5; s.places = 0.35; s.collectibles = 0.2; s.challenges = 0.6
        s.nextMission = "—"; s.hours = 36
        s.counts = [38, 91, 3, 7, 880, 1590, 12, 42]; s.eggs = [4, 15]
        return VFEntry(date: Date(), snap: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (VFEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : VFEntry(date: Date(), snap: VFSnapshot.load()))
    }

    /// Une entrée maintenant et une à minuit : « jour N à Leonida » change de lui-même, même si l'app n'est pas
    /// rouverte. L'app recharge aussi les widgets dès que la progression change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<VFEntry>) -> Void) {
        let snap = VFSnapshot.load()
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let entries = [VFEntry(date: now, snap: snap), VFEntry(date: midnight, snap: snap)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(86_400))))
    }
}

struct ProgressWidgetView: View {
    var entry: VFEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VFWidgetFace(snap: entry.snap, size: size, day: VFWidgetFace.dayInLeonida(entry.date))
    }

    private var size: VFWidgetSize {
        switch family {
        case .accessoryCircular: return .circular
        case .accessoryRectangular: return .rectangular
        case .accessoryInline: return .inline
        case .systemMedium: return .medium
        case .systemLarge: return .large
        default: return .small
        }
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "vicefold.progress", provider: VFProvider()) { e in
            ProgressWidgetView(entry: e)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { VFWidgetBackground() }
                .widgetURL(URL(string: "vicefold://tracker"))
        }
        .configurationDisplayName("Your 100%")
        .description("Your progress ring and next mission.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DaysWidgetView: View {
    var entry: VFEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let days = VFDaysFace.days(entry.date)
        if family == .accessoryInline {
            Text(days < 0 ? String(localized: "\(-days) days to Leonida") : String(localized: "Day \(days + 1) in Leonida"))
        } else {
            VFDaysFace(days: days)
        }
    }
}

struct DaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "vicefold.days", provider: VFProvider()) { e in
            DaysWidgetView(entry: e)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { VFWidgetBackground() }
                .widgetURL(URL(string: "vicefold://home"))
        }
        .configurationDisplayName("Days in Leonida")
        .description("Counts the days since the game came out.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

@main
struct VicefoldWidgets: WidgetBundle {
    var body: some Widget {
        ProgressWidget()
        DaysWidget()
    }
}
