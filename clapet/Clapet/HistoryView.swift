import Charts
import SwiftUI

/// L'historique complet et les records (Duo Folds+).
struct HistoryView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var range = 0
    @State private var csvFile: URL?

    private let mint = Color(red: 0.43, green: 0.84, blue: 0.65)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.clapetInk, Color(red: 0.10, green: 0.08, blue: 0.22)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        chartCard
                        calendarCard.id("calendar")
                        records.id("records")
                        if let csvFile {
                            ShareLink(item: csvFile) {
                                Label { Text("Export as a spreadsheet (CSV)") } icon: { Image(systemName: "square.and.arrow.up") }
                                    .font(.system(.headline, design: .rounded, weight: .heavy))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.clapetCard))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .task {
                    // Mode démo : défile jusqu'à une section à un instant donné.
                    guard let target = Demo.scroll else { return }
                    try? await Task.sleep(nanoseconds: UInt64((Demo.delay + target.at) * 1_000_000_000))
                    withAnimation(.easeInOut(duration: 0.9)) { proxy.scrollTo(target.id, anchor: .top) }
                }
                }
            }
            .foregroundStyle(.white)
            .navigationTitle(Text("History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .onAppear { csvFile = writeCSV() }
        }
    }

    // MARK: Le graphique

    private var chartCard: some View {
        let data = range == 0 ? model.stats.lastDays(30) : model.stats.lastMonths()
        let total = data.reduce(0) { $0 + $1.closes }
        return VStack(alignment: .leading, spacing: 12) {
            Picker(selection: $range) {
                Text("30 days").tag(0)
                Text("12 months").tag(1)
            } label: {
                Text("Period")
            }
            .pickerStyle(.segmented)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(total)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                (range == 0 ? Text("folds in 30 days") : Text("folds in 12 months"))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Chart {
                ForEach(0..<data.count, id: \.self) { i in
                    BarMark(x: .value("Day", data[i].date, unit: range == 0 ? .day : .month),
                            y: .value("Folds", data[i].closes))
                        .foregroundStyle(i == data.count - 1 ? mint : mint.opacity(0.45))
                        .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: range == 0 ? .day : .month, count: range == 0 ? 7 : 2)) { _ in
                    AxisValueLabel(format: range == 0 ? Date.FormatStyle.dateTime.day().month(.abbreviated) : Date.FormatStyle.dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.clapetCard))
    }

    // MARK: Le calendrier du mois

    private var calendarCard: some View {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let count = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        // Décalage du premier jour selon le premier jour de la semaine du pays.
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let values = (0..<count).map { i -> Int in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return 0 }
            return model.stats.day(d).closes
        }
        let top = max(1, values.max() ?? 1)
        let today = cal.component(.day, from: now) - 1
        let symbols = Self.weekdaySymbols()
        return VStack(alignment: .leading, spacing: 12) {
            Text(now, format: .dateTime.month(.wide).year())
                .font(.system(.headline, design: .rounded, weight: .black))
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(symbols[i])
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<(lead + count), id: \.self) { cell in
                    if cell < lead {
                        Color.clear.frame(height: 34)
                    } else {
                        let i = cell - lead
                        let v = values[i]
                        let over = model.stats.goal > 0 && v > model.stats.goal
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(v == 0 ? Color.white.opacity(0.06) : (over ? Color.clapetPink : mint).opacity(0.25 + 0.75 * Double(v) / Double(top)))
                            Text("\(i + 1)")
                                .font(.system(.caption, design: .rounded, weight: i == today ? .black : .semibold))
                                .foregroundStyle(v > top / 2 ? Color.black : Color.white.opacity(i > today ? 0.3 : 0.85))
                        }
                        .frame(height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(i == today ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5))
                    }
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(mint).frame(width: 12, height: 12)
                    Text("Under the limit")
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.clapetPink).frame(width: 12, height: 12)
                    Text("Over the limit")
                }
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.clapetCard))
    }

    static func weekdaySymbols() -> [String] {
        let cal = Calendar.current
        let s = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { s[(cal.firstWeekday - 1 + $0) % 7] }
    }

    // MARK: Les records

    private var records: some View {
        let s = model.stats
        let busiest = s.bestDay
        let calmest = s.calmestDay()
        let change = s.weekChange()
        let dateStyle = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            record("flame.fill", mint, "\(s.currentStreak())", Text("Days under the limit in a row"), nil)
            record("crown.fill", .clapetYellow, "\(s.longestStreak())", Text("Longest streak"), nil)
            record(change.map { $0 <= 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis" } ?? "chart.line.flattrend.xyaxis",
                   change.map { $0 <= 0 ? mint : Color.clapetPink } ?? .white,
                   change.map { $0.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) } ?? "–",
                   Text("This week vs last week"), nil)
            record("chart.line.flattrend.xyaxis", .clapetCyan, s.dailyAverage().formatted(.number.precision(.fractionLength(0...1))), Text("Average per day"), nil)
            record("leaf.fill", mint, "\(calmest?.closes ?? 0)", Text("Calmest day"), calmest.map { Text($0.date, format: dateStyle) })
            record("chart.bar.fill", .clapetPink, "\(busiest?.closes ?? 0)", Text("Busiest day"), busiest.map { Text($0.date, format: dateStyle) })
            record("clock.fill", .clapetOrange, "\(s.recordHour)", Text("Busiest hour"), nil)
            record("calendar.badge.checkmark", .white, "\(s.daysCounted)", Text("Days tracked"), nil)
        }
    }

    private func record(_ symbol: String, _ color: Color, _ value: String, _ title: Text, _ detail: Text?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            title
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            if let detail {
                detail
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.clapetCard))
        .accessibilityElement(children: .combine)
    }

    private func writeCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Duo Folds.csv")
        do {
            try model.stats.csv().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
