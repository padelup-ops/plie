import SwiftUI
import WidgetKit

// MARK: - Les widgets de Clapet
//
// Sobres, façon app Santé : fond sombre, gros chiffre, barres de la semaine,
// aujourd'hui en vert menthe, les clapets heure par heure et le niveau.

struct ClapetEntry: TimelineEntry {
    let date: Date
    let stats: ClapetStats
    /// Aperçu dans la galerie des widgets : on montre le widget tel qu'il sera.
    var preview = false
}

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
        return s
    }
}

private enum Palette {
    static let background = LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.17), Color(red: 0.08, green: 0.08, blue: 0.11)],
                                           startPoint: .top, endPoint: .bottom)
    static let mint = Color(red: 0.43, green: 0.84, blue: 0.65)
    static let red = Color(red: 0.93, green: 0.36, blue: 0.32)
    static let bar = Color.white.opacity(0.16)
    static let secondary = Color.white.opacity(0.5)
}

struct ClapetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClapetEntry

    private var stats: ClapetStats { entry.stats }
    private var today: Int { stats.day(entry.date).closes }
    private var yesterday: Int { stats.yesterday(entry.date) }

    /// Le petit widget et la ligne de l'écran verrouillé sont gratuits ; les autres demandent Duo Folds+.
    private var needsPlus: Bool {
        switch family {
        case .systemSmall, .accessoryInline: return false
        default: return true
        }
    }

    private var locked: Bool { needsPlus && !stats.plus && !entry.preview }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    /// La couleur choisie (Duo Folds+), menthe sinon.
    private var accent: Color {
        stats.plus ? (ClapetTheme(rawValue: stats.theme) ?? .mint).color : Palette.mint
    }

    var body: some View {
        Group {
            if locked {
                lockedView
            } else {
                sized
            }
        }
        .containerBackground(for: .widget) {
            if isAccessory {
                Color.clear
            } else {
                Palette.background
            }
        }
        .widgetURL(locked ? URL(string: "clapet://plus") : nil)
    }

    @ViewBuilder
    private var sized: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemLarge, .systemExtraLarge: large
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder
    private var lockedView: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "lock.fill").font(.system(size: 14, weight: .bold))
                    Text("Plus").font(.system(size: 10, weight: .heavy, design: .rounded))
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(.title3, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Duo Folds+").font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Tap to unlock").font(.system(.caption, design: .rounded, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            ZStack {
                sized
                    .blur(radius: 7)
                    .opacity(0.4)
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Palette.mint)
                    Text("Duo Folds+")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tap to unlock this widget")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    // MARK: Morceaux

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 13, weight: .semibold))
            Text("DUO FOLDS")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(0.8)
                .lineLimit(1)
            if needsPlus && !stats.plus && entry.preview {
                Text("PLUS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.mint))
            }
            Spacer(minLength: 4)
            if family != .systemSmall, let last = stats.lastClose {
                Text("Last fold \(Self.ago(last, from: entry.date))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Palette.secondary)
    }

    static func ago(_ date: Date, from now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: min(date, now), relativeTo: now)
    }

    private var versusYesterday: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(today)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if today != yesterday {
                    Text("\(today > yesterday ? "↑" : "↓") \(abs(today - yesterday))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(today > yesterday ? Palette.red : accent)
                }
            }
            Text("today vs yesterday")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var allTime: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(stats.totalCloses)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text("all time")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
        }
    }

    /// Les 7 derniers jours : le chiffre au-dessus, la barre, la lettre du jour.
    private func week(height: CGFloat, showValues: Bool) -> some View {
        let days = stats.lastWeek(now: entry.date)
        let top = max(1, days.map(\.closes).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<days.count, id: \.self) { i in
                let isToday = i == days.count - 1
                VStack(spacing: 4) {
                    if showValues {
                        Text("\(days[i].closes)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(isToday ? .white : Palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(stats.goal > 0 && days[i].closes > stats.goal ? Palette.red.opacity(isToday ? 1 : 0.6) : (isToday ? accent : Palette.bar))
                        .frame(height: max(5, height * CGFloat(days[i].closes) / CGFloat(top)))
                    Text(days[i].date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isToday ? .white : Palette.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var byHour: some View {
        let hours = stats.hours(entry.date)
        let top = max(1, hours.max() ?? 1)
        let peak = hours.firstIndex(of: top)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today by hour")
                Spacer()
                if let peak, (hours.max() ?? 0) > 0 {
                    Text("Peak \(Self.hour(peak))")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.secondary)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(hours[h] > 0 && h == peak ? accent : (hours[h] > 0 ? Color.white.opacity(0.28) : Palette.bar))
                        .frame(height: max(3, 28 * CGFloat(hours[h]) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28, alignment: .bottom)
        }
    }

    static func hour(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private var levelBar: some View {
        let level = stats.level
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Level \(level.number)")
                    .foregroundStyle(.white)
                Text(level.name)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                if let next = level.next {
                    Text("\(next - stats.totalCloses) to level \(level.number + 1)")
                        .foregroundStyle(Palette.secondary)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bar)
                    Capsule().fill(accent).frame(width: max(6, g.size.width * CGFloat(level.progress(stats.totalCloses))))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Tailles

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            Text("\(today)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                Text("today")
                    .foregroundStyle(Palette.secondary)
                if today != yesterday {
                    Text("\(today > yesterday ? "↑" : "↓") \(abs(today - yesterday))")
                        .foregroundStyle(today > yesterday ? Palette.red : accent)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            if let last = stats.lastClose {
                Text("Last fold \(Self.ago(last, from: entry.date))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    allTime
                    versusYesterday
                        .scaleEffect(0.9, anchor: .leading)
                }
                .frame(width: 118, alignment: .leading)
                week(height: 52, showValues: true)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .bottom) {
                allTime
                Spacer()
                versusYesterday
            }
            week(height: 110, showValues: true)
            byHour
            Spacer(minLength: 0)
            levelBar
        }
    }

    private var circular: some View {
        Gauge(value: stats.goal > 0 ? min(1, Double(today) / Double(stats.goal)) : 0) {
            Image(systemName: "iphone.gen3")
        } currentValueLabel: {
            Text("\(today)")
                .font(.system(.body, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "iphone.gen3")
                Text("Duo Folds")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            Text("\(today) folds today")
                .font(.system(.body, design: .rounded, weight: .semibold))
            Text("\(stats.totalCloses) all time")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            Text("\(today) folds today")
        } icon: {
            Image(systemName: "iphone.gen3")
        }
    }
}

struct ClapetWidget: Widget {
    let kind = "ClapetToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            ClapetWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Duo Folds"))
        .description(Text("How many times you closed your Duo, like your steps in Health."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ClapetWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClapetWidget()
    }
}
