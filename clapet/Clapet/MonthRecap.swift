import Charts
import SwiftUI
import UserNotifications

// MARK: - Le bilan du mois (demandé dans le sondage)
//
// Comme le bilan de la semaine, sur un mois entier : le total, la comparaison avec le mois d'avant,
// le temps ouvert et fermé, le jour record, le plus calme, et l'heure où l'on plie le plus.
// Disponible dès le 1er du mois suivant ; une carte l'annonce sur l'accueil pendant 5 jours, une notification le 1er à 10 h.

extension ClapetStats {
    /// Le mois qui contient `date`, résumé jour par jour, comparé au mois d'avant.
    func monthRecap(containing date: Date, now: Date = Date()) -> WeekRecap {
        let cal = Calendar.current
        guard let month = cal.dateInterval(of: .month, for: date) else { return weekRecap(endingOn: date, now: now) }
        func days(in interval: DateInterval) -> [Date] {
            var out: [Date] = []
            var d = interval.start.addingTimeInterval(12 * 3600)
            while d < interval.end {
                out.append(d)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
            return out
        }
        let current = days(in: month).filter { $0 <= now || cal.isDate($0, inSameDayAs: now) }.map { d in
            WeekRecap.Day(date: d, closes: day(d).closes, open: openTime(d, now: now), closed: downTime(d, now: now))
        }
        let previousMonth = cal.date(byAdding: .month, value: -1, to: month.start).flatMap { cal.dateInterval(of: .month, for: $0) }
        let previous = previousMonth.map(days(in:)) ?? []
        return WeekRecap(
            id: "month-" + Self.key(month.start),
            days: current,
            total: current.reduce(0) { $0 + $1.closes },
            previousTotal: previous.reduce(0) { $0 + day($1).closes },
            open: current.reduce(0) { $0 + $1.open },
            previousOpen: previous.reduce(0) { $0 + openTime($1, now: now) },
            closed: current.reduce(0) { $0 + $1.closed },
            peeks: current.reduce(0) { $0 + day($1.date).peeks },
            longestBreak: current.map { longestBreak($0.date, now: now) }.max() ?? 0,
            tracked: current.filter { $0.closes > 0 }.count)
    }

    /// Le mois à résumer maintenant : le mois dernier.
    static func monthRecapDate(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: now)?.start ?? now
        return cal.date(byAdding: .day, value: -1, to: start) ?? now
    }
}

enum MonthRecapRule {
    private static let seenKey = "monthRecap.seen"

    static func current(_ stats: ClapetStats, now: Date = Date()) -> WeekRecap {
        stats.monthRecap(containing: ClapetStats.monthRecapDate(now: now), now: now)
    }

    /// La carte « Ton mois est prêt » : les 5 premiers jours du mois, tant qu'on ne l'a pas ouverte.
    static func shouldShowCard(_ stats: ClapetStats, now: Date = Date()) -> Bool {
        let recap = current(stats, now: now)
        guard recap.tracked >= 3, UserDefaults.standard.string(forKey: seenKey) != recap.id else { return false }
        return Calendar.current.component(.day, from: now) <= 5
    }

    static func markSeen(_ recap: WeekRecap) {
        UserDefaults.standard.set(recap.id, forKey: seenKey)
    }

    static func changeText(_ change: Double?) -> Text {
        guard let change else { return Text("Your first month with Foldly") }
        if abs(change) < 0.005 { return Text("Same as the month before") }
        let pct = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return change > 0 ? Text("\(pct) more than the month before") : Text("\(pct) less than the month before")
    }

    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

/// La notification du bilan du mois : le 1er de chaque mois à 10 h (avec le réglage du bilan de la semaine).
enum MonthRecapNotice {
    private static let id = "foldly.month"

    static func schedule() {
        guard WeekRecapNotice.isOn, !Demo.seeded else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Your month with Foldly")
                content.body = String(localized: "Your monthly recap is ready: your folds, your busiest day and the hour you unfold the most.")
                content.userInfo = ["url": "clapet://month"]
                var at = DateComponents()
                at.day = 1
                at.hour = 10
                let request = UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: at, repeats: true))
                try? await center.add(request)
            default:
                break
            }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

/// La carte de l'accueil : « Ton mois est prêt ».
struct MonthRecapPromo: View {
    let recap: WeekRecap
    let open: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color.dfAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your \(MonthRecapRule.monthName(recap.start)) is ready")
                    .font(.headline)
                Text("\(recap.total) folds. \(MonthRecapRule.changeText(recap.change))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: open) {
                    Text("See my month")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel(Text("Hide"))
        }
    }
}

struct MonthRecapView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var month = ClapetStats.monthRecapDate()

    var body: some View {
        let s = model.stats
        let recap = s.monthRecap(containing: month)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    picker(recap)
                    if recap.isEmpty {
                        Text("No folds counted this month.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(recap.total)")
                                    .font(.system(size: 64, weight: .light))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text("folds")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            MonthRecapRule.changeText(recap.change)
                                .font(.headline)
                                .foregroundStyle(Color.dfAccent)
                        }
                        chart(recap)
                        tiles(recap)
                        highlights(recap)
                        if s.peakHour != nil {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your hours")
                                    .font(.headline)
                                HoursContent(stats: s, showsGrid: false)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Your month"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .onAppear { MonthRecapRule.markSeen(MonthRecapRule.current(s)) }
        }
        .tint(.dfAccent)
    }

    private func picker(_ recap: WeekRecap) -> some View {
        let cal = Calendar.current
        let first = model.stats.firstDay.flatMap(ClapetStats.date)
        let monthStart = cal.dateInterval(of: .month, for: month)?.start ?? month
        let canGoBack = first.map { monthStart > $0 } ?? false
        let canGoForward = !cal.isDate(month, equalTo: Date(), toGranularity: .month)
        return HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .disabled(!canGoBack)
                .accessibilityLabel(Text("Previous month"))
            Spacer()
            Text(MonthRecapRule.monthName(month))
                .font(.headline)
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .disabled(!canGoForward)
                .accessibilityLabel(Text("Next month"))
        }
        .font(.body.weight(.semibold))
    }

    private func move(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = min(next, Date()) }
    }

    private func chart(_ recap: WeekRecap) -> some View {
        let busiest = recap.busiest.map { ClapetStats.key($0.date) }
        let avg = Double(recap.perDay)
        return Chart {
            ForEach(0..<recap.days.count, id: \.self) { i in
                let d = recap.days[i]
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Folds", FoldUnit.shown(d.closes)))
                    .foregroundStyle(ClapetStats.key(d.date) == busiest ? Color.dfAccent : Color.dfBar)
                    .cornerRadius(3)
            }
            if avg > 0 {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .frame(height: 170)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }

    private func tiles(_ recap: WeekRecap) -> some View {
        let measured = model.stats.autoLast != nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(Text("Per day"), "\(recap.perDay)", detail: Text("on the days counted"))
            tile(Text("Time open"), TimeFormat.short(recap.open), detail: nil)
            tile(Text("Time closed"), measured || recap.closed > 0 ? TimeFormat.short(recap.closed) : "—", detail: nil)
            tile(Text("Quick checks"), "\(recap.peeks)", detail: Text("Opened less than 10 s"))
            tile(Text("Longest break"), TimeFormat.short(recap.longestBreak), detail: nil)
            tile(Text("Days counted"), "\(recap.tracked)", detail: nil)
        }
    }

    private func tile(_ title: Text, _ value: String, detail: Text?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.dfCard))
        .accessibilityElement(children: .combine)
    }

    private func highlights(_ recap: WeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = recap.busiest {
                row("arrow.up.circle.fill", Text("Busiest day"),
                    Text("\(Text(b.date, format: .dateTime.weekday(.wide).day().month(.wide))) · \(FoldUnit.shown(b.closes)) folds"))
            }
            if let c = recap.calmest {
                row("arrow.down.circle.fill", Text("Calmest day"),
                    Text("\(Text(c.date, format: .dateTime.weekday(.wide).day().month(.wide))) · \(FoldUnit.shown(c.closes)) folds"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }

    private func row(_ symbol: String, _ title: Text, _ value: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.dfAccent)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.footnote).foregroundStyle(.secondary)
                value.font(.headline)
            }
        }
    }
}
