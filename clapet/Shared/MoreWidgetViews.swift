import SwiftUI
import WidgetKit

// MARK: - Vues des widgets « Tes heures » et « Depuis le début » (partagées avec l'app pour les aperçus)

func widgetThemeColor(_ stats: ClapetStats) -> Color {
    stats.plus || DuoFolds.paidApp ? (ClapetTheme(rawValue: stats.theme) ?? .mint).color : Palette.mint
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
                Text("YOUR HOURS").tracking(0.8)
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
                        .foregroundStyle(.white)
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
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Palette.background }
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

    private var total: Int { entry.stats.totalCloses }

    var body: some View {
        let accent = widgetThemeColor(entry.stats)
        let level = ClapetLevel.of(total)
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("SINCE DAY ONE")
                        .font(.system(size: 11, weight: .bold))
                        .widgetAccentable()
                    Text(total.formatted())
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    if let next = level.next {
                        ProgressView(value: level.progress(total)) { EmptyView() } currentValueLabel: {
                            Text("Next: \(next.formatted())")
                        }
                        .font(.system(size: 11))
                    }
                }
            case .accessoryInline:
                Text("\(total.formatted()) folds since day one")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "gauge.with.needle")
                        Text("SINCE DAY ONE").tracking(0.8)
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
                        Text("Next milestone: \(next.formatted())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.colorScheme, .dark)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall { Palette.background } else { Color.clear }
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
                    .foregroundStyle(i >= digits.count - 1 ? Color.black : .white)
                    .frame(width: 17, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i >= digits.count - 1 ? accent : Color.white.opacity(0.12))
                    )
                    .overlay(Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1))
            }
        }
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value) folds since day one"))
    }
}

