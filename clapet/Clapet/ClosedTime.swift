import SwiftUI

/// « Temps fermé » : combien de temps le téléphone est resté fermé aujourd'hui, comparé au temps ouvert.
/// Les sessions viennent des automatisations Fermé / Ouvert.
struct ClosedTimeContent: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let closed = stats.closedTime(now, now: now)
            let open = stats.openTime(now, now: now)
            let total = closed + open
            let share = total > 0 ? closed / total : 0
            let since = stats.downSince(now: now)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(TimeFormat.short(closed))
                            .font(.system(size: 32, weight: .light))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("closed today").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TimeFormat.short(stats.closedTime(yesterday, now: now)))
                            .font(.headline)
                            .monospacedDigit()
                        Text("yesterday").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                GeometryReader { g in
                    HStack(spacing: 3) {
                        Capsule().fill(accent)
                            .frame(width: max(6, (g.size.width - 3) * share))
                        Capsule().fill(Color.dfFill)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        legend(share: share, open: open)
                        Spacer(minLength: 8)
                        state(since: since, now: now)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        legend(share: share, open: open)
                        state(since: since, now: now)
                    }
                }
                .font(.footnote)
                if stats.autoLast != nil, let a = stats.awakeSplit(now: now) {
                    awake(a, window: stats.awakeWindow(now: now))
                }
                if stats.autoLast == nil {
                    Text("Needs the two Shortcuts automations (Closed and Opened) to measure the time your phone stays closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Pendant les heures d'éveil : la vraie part ouvert / fermé, sans la nuit.
    private func awake(_ a: (open: TimeInterval, closed: TimeInterval), window: (start: Date, end: Date)) -> some View {
        let total = a.open + a.closed
        let share = total > 0 ? a.open / total : 0
        let f = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        return VStack(alignment: .leading, spacing: 6) {
            Text("While you're awake (\(window.start.formatted(f))–\(window.end.formatted(f)))")
                .font(.footnote.weight(.semibold))
            GeometryReader { g in
                HStack(spacing: 3) {
                    Capsule().fill(Color.dfAccent.opacity(0.55)).frame(width: max(6, (g.size.width - 3) * share))
                    Capsule().fill(Color.dfFill)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text("Open \(TimeFormat.short(a.open)) · closed \(TimeFormat.short(a.closed))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func legend(share: Double, open: TimeInterval) -> some View {
        let pct = share.formatted(.percent.precision(.fractionLength(0)))
        return HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text("Closed \(pct)")
            Circle().fill(Color.dfFill).frame(width: 7, height: 7)
                .padding(.leading, 6)
            Text("Open \(TimeFormat.short(open))")
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private func state(since: Date?, now: Date) -> some View {
        if let since {
            Text("Closed for \(TimeFormat.short(now.timeIntervalSince(since)))")
                .fontWeight(.medium)
                .foregroundStyle(accent)
                .lineLimit(1)
        } else if let open = stats.openSince, now.timeIntervalSince(open) < ClapetStats.maxOpenSession {
            Text("Open for \(TimeFormat.short(now.timeIntervalSince(open)))")
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
