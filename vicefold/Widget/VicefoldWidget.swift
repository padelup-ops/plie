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
        let s = entry.snap
        switch family {
        case .accessoryCircular:
            Gauge(value: s.percent) {
                Text("VF")
            } currentValueLabel: {
                Text("\(Int(s.percent * 100))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(s.percent * 100))% of Leonida").font(.headline)
                Text(s.nextMission ?? String(localized: "All missions done")).font(.caption).lineLimit(2)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                ring(s).frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next mission").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(s.nextMission ?? String(localized: "All missions done")).font(.headline).lineLimit(2)
                    if let c = s.nextChapter { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if s.hours > 0 { Label("\(Int(s.hours)) h", systemImage: "clock").font(.caption) }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(spacing: 6) {
                ring(s).frame(width: 96, height: 96)
                Text("Leonida").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func ring(_ s: VFSnapshot) -> some View {
        ZStack {
            VFRing(parts: [s.missions, s.places, s.collectibles, s.challenges], lineWidth: 8)
            Text("\(Int(s.percent * 100))%").font(.headline.monospacedDigit())
        }
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "vicefold.progress", provider: VFProvider()) { e in
            ProgressWidgetView(entry: e)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [VF.night, Color(red: 0.22, green: 0.07, blue: 0.22)], startPoint: .top, endPoint: .bottom)
                }
                .environment(\.colorScheme, .dark)
                .widgetURL(URL(string: "vicefold://tracker"))
        }
        .configurationDisplayName("Your 100%")
        .description("Your progress ring and next mission.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
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
                VStack(spacing: 2) {
                    Text(days < 0 ? "\(-days)" : "\(days + 1)").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(VF.gradient)
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
                .containerBackground(for: .widget) { VF.night }
                .environment(\.colorScheme, .dark)
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
