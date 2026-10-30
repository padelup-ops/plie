import SwiftUI
import WidgetKit

// MARK: - Les widgets de Clapet
//
// Sobres, façon app Santé : fond sombre, gros chiffre, barres de la semaine,
// aujourd'hui en vert menthe, les clapets heure par heure et le niveau.


struct ClapetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClapetEntry {
        ClapetEntry(date: Date(), stats: Self.sample(), preview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClapetEntry) -> Void) {
        let stats = ClapetVault.load()
        var shown = context.isPreview && stats.totalCloses == 0 ? Self.sample() : stats
        shown.plus = stats.plus
        shown.theme = stats.theme
        completion(ClapetEntry(date: Date(), stats: shown, preview: context.isPreview))
    }

    /// Une entrée tous les quarts d'heure (pour « il y a 27 min »), et minuit pour repartir à zéro.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClapetEntry>) -> Void) {
        let stats = ClapetVault.load()
        let now = Date()
        var entries = (0..<16).map { ClapetEntry(date: now.addingTimeInterval(Double($0) * 900), stats: stats) }
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime),
           midnight < entries.last?.date ?? now {
            entries.removeAll { $0.date >= midnight }
            entries.append(ClapetEntry(date: midnight, stats: stats))
        }
        completion(Timeline(entries: entries, policy: .after(entries.last?.date ?? now.addingTimeInterval(3600))))
    }

    /// Des chiffres d'exemple pour la galerie des widgets.
    static func sample() -> ClapetStats {
        var s = ClapetStats()
        let cal = Calendar.current
        for (back, n) in [(6, 12), (5, 30), (4, 8), (3, 21), (2, 103), (1, 46), (0, 5)] {
            if let d = cal.date(byAdding: .day, value: -back, to: Date()) { s.days[ClapetStats.key(d)] = DayCount(closes: n, opens: n) }
        }
        s.totalCloses = 225
        s.hourlyDay = ClapetStats.key()
        s.hourly = Array(repeating: 0, count: 24)
        s.hourly[9] = 3
        s.hourly[15] = 2
        s.lastClose = Date().addingTimeInterval(-27 * 60)
        // Aujourd'hui : 2 h 10 fermé, 1 h 25 ouvert.
        var today = s.days[ClapetStats.key()] ?? DayCount()
        today.downSeconds = 130 * 60
        today.openSeconds = 85 * 60
        s.days[ClapetStats.key()] = today
        return s
    }
}


struct ClapetWidget: Widget {
    let kind = "ClapetToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            ClapetWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Folds today"))
        .description(Text("Your folds today, compared with your average, and your week, like your steps in Health."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Le widget « Ouvert / fermé » : le temps passé ouvert et fermé aujourd'hui (type inchangé pour les widgets déjà installés).
struct PhoneDownWidget: Widget {
    let kind = "FoldlyPhoneDown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            PhoneDownWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Open & closed"))
        .description(Text("How long your phone stayed open and closed today, with a timer on the Lock Screen."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ClapetWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClapetWidget()
        PhoneDownWidget()
        FoldLiveActivity()
    }
}
