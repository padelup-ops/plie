// VicefoldWidget.swift — Vicefold
//
// Les widgets : ton anneau 100 % et la prochaine mission (écran d'accueil et écran verrouillé), et le compte des jours
// depuis la sortie du jeu.

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

    func getTimeline(in context: Context, completion: @escaping (Timeline<VFEntry>) -> Void) {
        let e = VFEntry(date: Date(), snap: VFSnapshot.load())
        let next = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [e], policy: .after(next)))
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
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: VF.release), to: Calendar.current.startOfDay(for: entry.date)).day ?? 0
        Group {
            if family == .accessoryInline {
                Text(days < 0 ? String(localized: "\(-days) days to Leonida") : String(localized: "Day \(days + 1) in Leonida"))
            } else {
                VStack(spacing: 0) {
                    Text(days < 0 ? "\(-days)" : "\(days + 1)").font(VF.display(56)).monospacedDigit().foregroundStyle(VF.gradient)
                    Text(days < 0 ? String(localized: "days to go") : String(localized: "days in Leonida")).font(.caption.weight(.semibold))
                }
            }
        }
    }
}

struct DaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "vicefold.days", provider: VFProvider()) { e in
            DaysWidgetView(entry: e)
                .containerBackground(for: .widget) { VFWidgetBackground() }
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
