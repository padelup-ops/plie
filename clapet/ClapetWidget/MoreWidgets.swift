import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Les nouveaux widgets (demandés dans le sondage)
//
// « Tes heures » : quand tu déplies le plus (semaine type, heure par heure).
// « Depuis le début » : le compteur kilométrique de la charnière.
// « Compter un pli » : un bouton dans le Centre de contrôle et sur l'écran verrouillé (iOS 18).

private func themeColor(_ stats: ClapetStats) -> Color {
    stats.plus || DuoFolds.paidApp ? (ClapetTheme(rawValue: stats.theme) ?? .mint).color : Palette.mint
}

// MARK: Tes heures

struct HoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClapetEntry

    var body: some View {
        let s = entry.stats
        let accent = themeColor(s)
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

struct HoursWidget: Widget {
    let kind = "FoldlyHours"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            HoursWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Your hours"))
        .description(Text("When you unfold the most: your typical week, hour by hour."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: Depuis le début (compteur kilométrique)

struct LifetimeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClapetEntry

    private var total: Int { entry.stats.totalCloses }

    var body: some View {
        let accent = themeColor(entry.stats)
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

struct LifetimeWidget: Widget {
    let kind = "FoldlyLifetime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            LifetimeWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Since day one"))
        .description(Text("Every fold since you started, like an odometer for your hinge."))
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Le bouton « Compter un pli » (Centre de contrôle, iOS 18)

/// Ajoute un pli, sans ouvrir l'app.
struct CountFoldControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Count a fold"
    static var description = IntentDescription("Adds one fold to today's count.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var stats = ClapetVault.load()
        stats.addClose()
        stats.endOpen(event: true)
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 18.0, *)
struct CountFoldControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FoldlyCountControl") {
            ControlWidgetButton(action: CountFoldControlIntent()) {
                Label { Text("Count a fold") } icon: { Image(systemName: "plus.circle") }
            }
        }
        .displayName("Count a fold")
        .description("Adds one fold to today's count.")
    }
}
