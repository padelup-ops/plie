import SwiftUI
import WidgetKit

// MARK: - Le dessin des widgets de Foldly
//
// Partagé avec l'app : le mode démo (vidéo de présentation) montre les vrais widgets.

struct ClapetEntry: TimelineEntry {
    let date: Date
    let stats: ClapetStats
    /// Aperçu dans la galerie des widgets : on montre le widget tel qu'il sera.
    var preview = false
}

enum Palette {
    static let background = LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.17), Color(red: 0.08, green: 0.08, blue: 0.11)],
                                           startPoint: .top, endPoint: .bottom)
    static let mint = Color(red: 0.43, green: 0.84, blue: 0.65)
    static let red = Color(red: 0.93, green: 0.36, blue: 0.32)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.32)
    static let bar = Color.white.opacity(0.16)
    static let secondary = Color.white.opacity(0.5)
}

struct ClapetWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: ClapetEntry
    /// Dans l'app (mode démo), la taille du widget à dessiner.
    let familyOverride: WidgetFamily?

    init(entry: ClapetEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = family
    }

    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var stats: ClapetStats { entry.stats }
    private var today: Int { stats.day(entry.date).closes }
    private var yesterday: Int { stats.yesterday(entry.date) }

    /// Le petit widget et la ligne de l'écran verrouillé sont gratuits ; les autres demandent Foldly+.
    private var needsPlus: Bool {
        switch family {
        case .systemSmall, .accessoryInline: return false
        default: return true
        }
    }

    private var locked: Bool { !DuoFolds.paidApp && needsPlus && !stats.plus && !entry.preview }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    /// La couleur choisie (Foldly+), menthe sinon.
    private var accent: Color {
        stats.plus || DuoFolds.paidApp ? (ClapetTheme(rawValue: stats.theme) ?? .mint).color : Palette.mint
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
                    Text("Plus").font(.system(size: 10, weight: .semibold))
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(.title3, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Foldly+").font(.system(.headline, weight: .bold))
                    Text("Tap to unlock").font(.system(.caption, weight: .medium))
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
                    Text("Foldly+")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Tap to unlock this widget")
                        .font(.system(size: 12, weight: .semibold))
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
            Text("FOLDLY")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .lineLimit(1)
            if !DuoFolds.paidApp && needsPlus && !stats.plus && entry.preview {
                Text("PLUS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.mint))
            }
            Spacer(minLength: 4)
            if family != .systemSmall, let last = stats.lastClose {
                Text("Last fold \(Self.ago(last, from: entry.date))")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Palette.secondary)
    }

    static func ago(_ date: Date, from now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: min(date, now), relativeTo: now)
    }

    private var versusYesterday: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(today)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                if today != yesterday {
                    Text("\(today > yesterday ? "↑" : "↓") \(abs(today - yesterday))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(today > yesterday ? Palette.red : accent)
                }
            }
            Text("today vs yesterday")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var allTime: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(stats.totalCloses)")
                .font(.system(size: 52, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text("all time")
                .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isToday ? .white : Palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(stats.goal > 0 && days[i].closes > stats.goal ? Palette.red.opacity(isToday ? 1 : 0.6) : (isToday ? accent : Palette.bar))
                        .frame(height: max(5, height * CGFloat(days[i].closes) / CGFloat(top)))
                    Text(days[i].date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 11, weight: isToday ? .bold : .medium))
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
            .font(.system(size: 12, weight: .medium))
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
                if let next = level.next {
                    Text("Next milestone: \(next)")
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text("\(next - stats.totalCloses) to go")
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text("\(stats.totalCloses) folds")
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 12, weight: .semibold))
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

    /// Vert sous la limite, orange à 80 %, rouge au-delà.
    private var statusColor: Color {
        guard stats.goal > 0 else { return accent }
        if today > stats.goal { return Palette.red }
        if Double(today) >= 0.8 * Double(stats.goal) { return Palette.orange }
        return accent
    }

    /// La limite du jour : une barre et ce qui reste.
    private var limitBar: some View {
        let left = stats.goal - today
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bar)
                    Capsule().fill(statusColor)
                        .frame(width: max(5, g.size.width * CGFloat(min(1, Double(today) / Double(max(1, stats.goal))))))
                        .widgetAccentable()
                }
            }
            .frame(height: 5)
            Group {
                if left > 0 {
                    Text("\(left) left today")
                } else if left == 0 {
                    Text("Limit reached")
                } else {
                    Text("\(-left) over the limit")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(left >= 0 ? Palette.secondary : Palette.red)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var todayLine: some View {
        HStack(spacing: 4) {
            Text("today")
                .foregroundStyle(Palette.secondary)
            if today != yesterday {
                Text("\(today > yesterday ? "↑" : "↓") \(abs(today - yesterday))")
                    .foregroundStyle(today > yesterday ? Palette.red : accent)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
    }

    /// Téléphone posé aujourd'hui, en une ligne (grand widget).
    private var phoneDownLine: some View {
        let down = stats.downTime(now: entry.date)
        let plants = stats.plants(now: entry.date)
        return HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("\(Garden.format(down)) phone down")
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Text("\(plants)")
                .foregroundStyle(.white)
                .monospacedDigit()
            Image(systemName: "camera.macro")
                .foregroundStyle(accent)
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Tailles

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            Text("\(today)")
                .font(.system(size: 46, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .widgetAccentable()
            todayLine
            Spacer(minLength: 6)
            if stats.goal > 0 {
                limitBar
            } else if let last = stats.lastClose {
                Text("Last fold \(Self.ago(last, from: entry.date))")
                    .font(.system(size: 11, weight: .medium))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(today)")
                        .font(.system(size: 40, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .widgetAccentable()
                    todayLine
                    Spacer(minLength: 6)
                    if stats.goal > 0 { limitBar }
                }
                .frame(width: 112, alignment: .leading)
                week(height: 52, showValues: true)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(today)")
                        .font(.system(size: 52, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .widgetAccentable()
                    todayLine
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.totalCloses)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("all time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            if stats.goal > 0 { limitBar }
            week(height: 86, showValues: true)
            byHour
            Spacer(minLength: 0)
            phoneDownLine
            levelBar
        }
    }

    private var circular: some View {
        Gauge(value: stats.goal > 0 ? min(1, Double(today) / Double(stats.goal)) : 0) {
            Image(systemName: "iphone.gen3")
        } currentValueLabel: {
            Text("\(today)")
                .font(.system(.body, weight: .bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "iphone.gen3")
                Text("Foldly")
                    .font(.system(.headline, weight: .bold))
            }
            Text("\(today) folds today")
                .font(.system(.body, weight: .semibold))
                .widgetAccentable()
            if stats.goal > 0 {
                Gauge(value: min(1, Double(today) / Double(stats.goal))) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            } else {
                Text("\(stats.totalCloses) all time")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }
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


// MARK: - Le widget « Téléphone posé »
//
// Le temps passé téléphone fermé aujourd'hui, l'objectif, et le jardin. Sur l'écran verrouillé
// (et l'écran extérieur du téléphone plié), un chrono tourne pendant que le téléphone est posé.

struct PhoneDownWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: ClapetEntry
    let familyOverride: WidgetFamily?

    init(entry: ClapetEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = family
    }

    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var stats: ClapetStats { entry.stats }
    private var down: TimeInterval { stats.downTime(now: entry.date) }
    private var goal: TimeInterval { Double(stats.downGoalMinutes) * 60 }
    private var plants: Int { stats.plants(now: entry.date) }
    private var since: Date? { stats.downSince(now: entry.date) }
    private var progress: Double { goal > 0 ? min(1, down / goal) : 0 }

    private var accent: Color {
        stats.plus || DuoFolds.paidApp ? (ClapetTheme(rawValue: stats.theme) ?? .mint).color : Palette.mint
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium, .systemLarge, .systemExtraLarge: medium
            default: small
            }
        }
        .containerBackground(for: .widget) {
            if isAccessory {
                Color.clear
            } else {
                Palette.background
            }
        }
        .widgetURL(URL(string: "clapet://garden"))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("Phone down")
                .font(.system(size: 13, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
    }

    private var bar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bar)
                Capsule().fill(accent)
                    .frame(width: max(5, g.size.width * CGFloat(progress)))
                    .widgetAccentable()
            }
        }
        .frame(height: 5)
    }

    /// Le chrono de la session en cours (il tourne tout seul, sans recharger le widget).
    private func sessionTimer(_ since: Date) -> some View {
        HStack(spacing: 4) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accent)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            Spacer(minLength: 0)
            Text(Garden.format(down))
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .widgetAccentable()
            Text("of \(Garden.format(goal))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 6)
            bar
            Spacer(minLength: 6)
            if plants > 0 {
                GardenStrip(plants: plants, color: accent, size: 15)
            } else if let since {
                sessionTimer(since)
            } else {
                Text("No plant yet today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                if let since { sessionTimer(since) }
            }
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Garden.format(down))
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(.white)
                        .widgetAccentable()
                    Text("of \(Garden.format(goal))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    Spacer(minLength: 6)
                    bar
                }
                .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if plants == 0 {
                            Text("No plant yet today")
                        } else if plants == 1 {
                            Text("1 plant today")
                        } else {
                            Text("\(plants) plants today")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    GardenStrip(plants: max(plants, 0), color: accent, size: 17)
                        .opacity(plants > 0 ? 1 : 0)
                    Spacer(minLength: 0)
                    Text("\(stats.totalPlants) in your garden")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var circular: some View {
        Gauge(value: progress) {
            Image(systemName: "leaf.fill")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(plants)")
                    .font(.system(.body, weight: .bold))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                Text("Phone down")
                    .font(.system(.headline, weight: .bold))
            }
            if let since {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.system(.body, weight: .semibold))
                    .monospacedDigit()
                    .widgetAccentable()
            } else {
                Text("\(Garden.format(down)) today")
                    .font(.system(.body, weight: .semibold))
                    .widgetAccentable()
            }
            Group {
                if plants == 1 {
                    Text("1 plant today")
                } else {
                    Text("\(plants) plants today")
                }
            }
            .font(.system(.caption, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            Text("\(Garden.format(down)) phone down")
        } icon: {
            Image(systemName: "leaf.fill")
        }
    }
}
