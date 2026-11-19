import SwiftUI
import WidgetKit

// MARK: - Vues des widgets « Tes heures » et « Depuis le début » (partagées avec l'app pour les aperçus)

func widgetThemeColor(_ stats: ClapetStats) -> Color {
    stats.widgetColor == .mint ? Palette.mint : stats.widgetColor.color
}

// MARK: Tes heures

struct HoursWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: ClapetEntry
    /// Pour les montrer dans l'app (aperçus) : la taille voulue.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        let s = entry.stats
        let accent = widgetThemeColor(s)
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 7) {
            HStack(spacing: 5) {
                Image(systemName: "clock.badge.checkmark")
                Text("Your hours")
                Spacer(minLength: 0)
                if let peak = s.peakHour {
                    Text("Peak \(HoursText.hour(peak))")
                        .foregroundStyle(accent)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.secondary)
            if family == .systemLarge {
                if let peak = s.peakHour {
                    Text("You fold the most around \(HoursText.hour(peak))")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                TypicalDayBars(hours: s.typicalDay, accent: accent, empty: Palette.bar, height: 60)
                HoursGrid(grid: s.weekHours, accent: accent, empty: Palette.bar, spacing: 2.5)
                if let slot = s.busiestSlot {
                    Text("Busiest moment: \(HoursText.weekday(slot.weekday)), around \(HoursText.hour(slot.hour))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                HoursGrid(grid: s.weekHours, accent: accent, empty: Palette.bar, spacing: 2, showLabels: false, cornerRadius: 2)
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(HoursText.hour(h)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(WidgetLook(look: s.widgetLook))
        .containerBackground(for: .widget) { Palette.background.modifier(WidgetLook(look: s.widgetLook)) }
        .widgetURL(URL(string: "clapet://hours"))
    }
}

// MARK: Depuis le début (compteur kilométrique)

struct LifetimeWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: ClapetEntry
    /// Pour les montrer dans l'app (aperçus) : la taille voulue.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var total: Int { entry.stats.duoCloses }

    var body: some View {
        let accent = widgetThemeColor(entry.stats)
        let level = ClapetLevel.of(total)
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Since day one")
                        .font(.system(size: 11, weight: .bold))
                        .widgetAccentable()
                    Text(FoldUnit.shown(total).formatted())
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    if let next = level.next {
                        ProgressView(value: level.progress(total)) { EmptyView() } currentValueLabel: {
                            Text("Next: \(FoldUnit.shown(next).formatted())")
                        }
                        .font(.system(size: 11))
                    }
                }
            case .accessoryInline:
                Text("\(FoldUnit.shown(total).formatted()) folds since day one")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.needle")
                        Text("Since day one")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.secondary)
                    Spacer(minLength: 0)
                    Odometer(value: total, accent: accent)
                    Text("folds")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    if let next = level.next {
                        ProgressView(value: level.progress(total))
                            .tint(accent)
                        Text("Next milestone: \(FoldUnit.shown(next).formatted())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(WidgetLook(look: entry.stats.widgetLook))
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall { Palette.background.modifier(WidgetLook(look: entry.stats.widgetLook)) } else { Color.clear }
        }
    }
}

/// Le chiffre façon compteur mécanique : un rouleau par chiffre.
struct Odometer: View {
    let value: Int
    var accent: Color = Palette.mint

    var body: some View {
        let digits = Array(String(format: "%06d", min(999_999, max(0, value))))
        HStack(spacing: 2) {
            ForEach(0..<digits.count, id: \.self) { i in
                Text(String(digits[i]))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(i >= digits.count - 1 ? Color.black : Palette.ink)
                    .frame(width: 17, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i >= digits.count - 1 ? accent : Palette.bar)
                    )
                    .overlay(Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1))
            }
        }
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(FoldUnit.shown(value)) folds since day one"))
    }
}

// MARK: Ouvert et fermé depuis le début

struct LifetimeHoursWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: ClapetEntry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var open: TimeInterval { entry.stats.lifetimeOpen(now: entry.date) }
    private var closed: TimeInterval { entry.stats.lifetimeClosed(now: entry.date) }
    private var share: Double {
        let total = open + closed
        return total > 0 ? open / total : 0
    }

    var body: some View {
        let accent = widgetThemeColor(entry.stats)
        Group {
            if family == .systemMedium {
                medium(accent)
            } else {
                small(accent)
            }
        }
        .modifier(WidgetLook(look: entry.stats.widgetLook))
        .containerBackground(for: .widget) { Palette.background.modifier(WidgetLook(look: entry.stats.widgetLook)) }
    }

    private func small(_ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            amount(open, Text("Open, all time"), size: 26)
            amount(closed, Text("Closed, all time"), size: 17)
            Spacer(minLength: 6)
            bar(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .bottom, spacing: 16) {
                amount(open, Text("Open, all time"), size: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                amount(closed, Text("Closed, all time"), size: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            bar(accent)
            Text("Since day one")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
            Text("All time open & closed")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Palette.secondary)
    }

    private func amount(_ t: TimeInterval, _ label: Text, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TimeFormat.short(t))
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Palette.ink)
                .widgetAccentable()
            label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(_ accent: Color) -> some View {
        GeometryReader { g in
            HStack(spacing: share > 0 && share < 1 ? 3 : 0) {
                if share > 0 {
                    Capsule().fill(accent)
                        .frame(width: share >= 1 ? g.size.width : max(4, (g.size.width - 3) * share))
                        .widgetAccentable()
                }
                if share < 1 {
                    Capsule().fill(Palette.bar)
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

