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
    /// Faux en veille (StandBy) : le fond est retiré, le widget s'affiche en grand.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
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
        default:
            if showsBackground { small } else { standBy }
        }
    }

    /// En veille (StandBy) : sans fond, le chiffre du jour en très grand.
    private var standBy: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "iphone.gen3")
                Text("FOLDLY").tracking(0.8)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(today)")
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
                .widgetAccentable()
            Text("folds today")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            if let ref = reference {
                Group {
                    if stats.goalOn { Text("Limit \(ref)") } else { Text("Average \(ref)") }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                        .foregroundStyle(today > yesterday ? upColor : accent)
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
                        .fill(stats.activeLimit > 0 && days[i].closes > stats.activeLimit ? Palette.red.opacity(isToday ? 1 : 0.6) : (isToday ? accent : Palette.bar))
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

    /// Sans limite, la couleur reste celle du widget. Avec une limite : vert dessous, orange à 80 %, rouge au-delà.
    private var statusColor: Color {
        let limit = stats.activeLimit
        guard limit > 0 else { return accent }
        if today > limit { return Palette.red }
        if Double(today) >= 0.8 * Double(limit) { return Palette.orange }
        return accent
    }

    /// Plus qu'hier : rouge seulement si une limite est activée.
    private var upColor: Color { stats.goalOn ? Palette.red : Color.white.opacity(0.75) }

    /// Le repère du jour (la moyenne, ou la limite si elle est activée).
    private var reference: Int? { stats.reference(now: entry.date) }

    /// Une barre jusqu'au repère, et ce qu'il signifie.
    private var refBar: some View {
        let left = stats.goal - today
        let ref = reference ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bar)
                    Capsule().fill(statusColor)
                        .frame(width: max(5, g.size.width * CGFloat(ref > 0 ? min(1, Double(today) / Double(ref)) : 0)))
                        .widgetAccentable()
                }
            }
            .frame(height: 5)
            Group {
                if stats.goalOn {
                    if left > 0 {
                        Text("\(left) left today")
                    } else if left == 0 {
                        Text("Limit reached")
                    } else {
                        Text("\(-left) over the limit")
                    }
                } else {
                    Text("Average \(ref) a day")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(stats.goalOn && left < 0 ? Palette.red : Palette.secondary)
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
                    .foregroundStyle(today > yesterday ? upColor : accent)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
    }

    /// Temps ouvert et fermé aujourd'hui, en une ligne (grand widget).
    private var openClosedLine: some View {
        let open = stats.openTime(entry.date, now: entry.date)
        let closed = stats.closedTime(entry.date, now: entry.date)
        return HStack(spacing: 8) {
            Image(systemName: "rectangle.expand.vertical")
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("\(TimeFormat.short(open)) open")
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Image(systemName: "rectangle.compress.vertical")
                .foregroundStyle(accent)
            Text("\(TimeFormat.short(closed)) closed")
                .foregroundStyle(.white)
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
            if reference != nil {
                refBar
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
                    if reference != nil { refBar }
                }
                .frame(width: 112, alignment: .leading)
                week(height: 52, showValues: true)
            }
        }
    }

    /// Tout doit tenir dans le grand widget, même le plus petit (338 × 354 points, marges comprises) :
    /// pas de palier ici, des barres un peu moins hautes.
    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(today)")
                        .font(.system(size: 44, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .widgetAccentable()
                    todayLine
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.totalCloses)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("all time")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            if reference != nil { refBar }
            week(height: 56, showValues: true)
            byHour
            Spacer(minLength: 0)
            openClosedLine
        }
    }

    private var circular: some View {
        Gauge(value: stats.refProgress(now: entry.date)) {
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
            if reference != nil {
                Gauge(value: stats.refProgress(now: entry.date)) { EmptyView() }
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


// MARK: - Le widget « Ouvert / fermé »
//
// Le temps passé ouvert et fermé aujourd'hui. Sur l'écran verrouillé (et l'écran extérieur du téléphone plié),
// un chrono montre depuis combien de temps le téléphone est fermé (ou ouvert).
// (Le type reste « PhoneDownWidgetView » : les widgets déjà installés continuent de marcher.)

struct PhoneDownWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: ClapetEntry
    let familyOverride: WidgetFamily?

    init(entry: ClapetEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = family
    }

    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var stats: ClapetStats { entry.stats }
    private var closed: TimeInterval { stats.closedTime(entry.date, now: entry.date) }
    private var open: TimeInterval { stats.openTime(entry.date, now: entry.date) }
    private var closedSince: Date? { stats.downSince(now: entry.date) }
    private var openSince: Date? {
        guard let s = stats.openSince, entry.date.timeIntervalSince(s) < ClapetStats.maxOpenSession else { return nil }
        return s
    }
    /// La part du temps mesuré passée fermé.
    private var closedShare: Double {
        let total = open + closed
        return total > 0 ? closed / total : 0
    }

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
            default:
                if showsBackground { small } else { standBy }
            }
        }
        .containerBackground(for: .widget) {
            if isAccessory {
                Color.clear
            } else {
                Palette.background
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
            Text("Open & closed")
                .font(.system(size: 13, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Fermé (couleur du widget) puis ouvert (gris), à proportion.
    private var split: some View {
        GeometryReader { g in
            HStack(spacing: 3) {
                Capsule().fill(accent)
                    .frame(width: max(5, (g.size.width - 3) * CGFloat(closedShare)))
                    .widgetAccentable()
                Capsule().fill(Color.white.opacity(0.28))
            }
        }
        .frame(height: 5)
    }

    /// Le chrono de l'état en cours (il tourne tout seul, sans recharger le widget).
    @ViewBuilder
    private var stateTimer: some View {
        if let since = closedSince {
            timer(Text("Closed"), since: since)
        } else if let since = openSince {
            timer(Text("Open"), since: since)
        }
    }

    private func timer(_ label: Text, since: Date) -> some View {
        HStack(spacing: 4) {
            Circle().fill(accent).frame(width: 6, height: 6)
            label
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func value(_ t: TimeInterval, _ label: Text, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TimeFormat.short(t))
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
            label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }

    /// En veille (StandBy) : sans fond, le chrono de l'état en cours en très grand.
    private var standBy: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: closedSince != nil ? "moon.zzz.fill" : "iphone.gen3")
                if closedSince != nil {
                    Text("Closed for")
                } else if openSince != nil {
                    Text("Open for")
                } else {
                    Text("Today")
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let since = closedSince ?? openSince {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .widgetAccentable()
            } else {
                Text(TimeFormat.short(closed))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            Text("\(TimeFormat.short(closed)) closed · \(TimeFormat.short(open)) open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            value(closed, Text("closed today"), size: 26)
                .widgetAccentable()
            value(open, Text("open today"), size: 17)
            Spacer(minLength: 6)
            split
            Spacer(minLength: 4)
            if closedSince != nil || openSince != nil {
                stateTimer
            } else {
                Text("\(stats.day(entry.date).closes) folds today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                stateTimer
            }
            HStack(alignment: .bottom, spacing: 16) {
                value(closed, Text("closed today"), size: 32)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                value(open, Text("open today"), size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            split
            HStack {
                Text("\(stats.day(entry.date).closes) folds")
                Spacer(minLength: 4)
                Text("Longest break \(TimeFormat.short(stats.longestBreak(entry.date, now: entry.date)))")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var circular: some View {
        Gauge(value: closedShare) {
            Image(systemName: "iphone.gen3")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 9, weight: .bold))
                Text(TimeFormat.compact(closed))
                    .font(.system(.caption, weight: .bold))
                    .minimumScaleFactor(0.6)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "iphone.gen3")
                if closedSince != nil {
                    Text("Closed for").font(.system(.headline, weight: .bold))
                } else if openSince != nil {
                    Text("Open for").font(.system(.headline, weight: .bold))
                } else {
                    Text("Foldly").font(.system(.headline, weight: .bold))
                }
            }
            if let since = closedSince ?? openSince {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.system(.body, weight: .semibold))
                    .monospacedDigit()
                    .widgetAccentable()
            } else {
                Text("\(TimeFormat.short(closed)) closed")
                    .font(.system(.body, weight: .semibold))
                    .widgetAccentable()
            }
            Text("Today: \(TimeFormat.short(closed)) closed · \(TimeFormat.short(open)) open")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            Text("\(TimeFormat.short(closed)) closed · \(TimeFormat.short(open)) open")
        } icon: {
            Image(systemName: "iphone.gen3")
        }
    }
}
