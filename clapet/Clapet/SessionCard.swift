import SwiftUI

// MARK: - « Tes sessions » (Foldly+)
//
// Combien de temps le Duo reste ouvert à chaque fois : deux longues sessions, ou plein de petites ?
// Idée de BraXzy, testeur.

struct SessionCard: View {
    let stats: ClapetStats

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let r = stats.sessionSummary(days: 7, now: context.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text("YOUR SESSIONS").tracking(0.8)
                    Spacer()
                    Text("Last 7 days").textCase(nil)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

                if r.count == 0 {
                    Text("Each time you unfold your Duo, Foldly times how long it stays open. Your sessions show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open on average, each time").font(.subheadline).foregroundStyle(.secondary)
                        Text(verbatim: SessionCard.duration(r.average))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dfAccent)
                        if r.estimated {
                            Text("Estimated from your daily totals. Exact sessions are recorded from now on.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(r.count) sessions · half last less than \(SessionCard.duration(r.median))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !r.estimated {
                        buckets(r)
                        HStack(spacing: 10) {
                            if let w = r.weekdayAverage {
                                tile(Text("Weekdays"), SessionCard.duration(w))
                            }
                            if let w = r.weekendAverage {
                                tile(Text("Weekends"), SessionCard.duration(w))
                            }
                            if let l = r.longest {
                                tile(Text("Longest"), SessionCard.duration(l.s))
                            }
                        }
                        if let share = r.awakeShare {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Open while you're awake")
                                    Spacer()
                                    Text(verbatim: "\(Int((share * 100).rounded())) %").monospacedDigit()
                                }
                                .font(.subheadline.weight(.semibold))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.08))
                                        Capsule().fill(Color.dfAccent).frame(width: max(6, g.size.width * share))
                                    }
                                }
                                .frame(height: 10)
                                Text("Share of 7 am – 11 pm spent with your Duo open.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.dfCard))
        }
    }

    private func buckets(_ r: SessionSummary) -> some View {
        let total = Double(max(1, r.short + r.medium + r.long))
        let rows: [(Text, Int, Color)] = [
            (Text("Under 1 min"), r.short, Color(red: 0.35, green: 0.72, blue: 1.0)),
            (Text("1 to 10 min"), r.medium, Color(red: 0.62, green: 0.56, blue: 1.0)),
            (Text("Over 10 min"), r.long, Color(red: 1.0, green: 0.62, blue: 0.25)),
        ]
        return VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let (label, n, color) = rows[i]
                HStack(spacing: 10) {
                    label.font(.subheadline.weight(.medium)).frame(width: 110, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: max(6, g.size.width * Double(n) / total))
                        }
                    }
                    .frame(height: 10)
                    Text(verbatim: "\(n)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func tile(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(verbatim: value).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// 45 s, 12 min, 1 h 20 min.
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, t.rounded())
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = s < 60 ? [.seconds] : (s < 3600 ? [.minutes, .seconds] : [.hours, .minutes])
        let rounded = s < 60 ? s : (s < 600 ? (s / 10).rounded() * 10 : (s / 60).rounded() * 60)
        return Duration.seconds(rounded).formatted(.units(allowed: allowed, width: .abbreviated, maximumUnitCount: 2))
    }
}
