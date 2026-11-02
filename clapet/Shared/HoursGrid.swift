import SwiftUI

// MARK: - Tes heures
//
// Quand est-ce qu'on déplie le plus ? Une grille 7 jours × 24 heures (la « semaine type », depuis le début),
// et une journée type en 24 barres. Partagé entre l'app et les widgets.

extension ClapetStats {
    /// La journée type : les plis de chaque heure, tous jours confondus.
    var typicalDay: [Int] {
        guard weekHours.count == 168 else { return Array(repeating: 0, count: 24) }
        return (0..<24).map { h in (0..<7).reduce(0) { $0 + weekHours[$1 * 24 + h] } }
    }

    /// L'heure où l'on plie le plus, tous jours confondus (nil tant qu'il n'y a rien).
    var peakHour: Int? {
        let day = typicalDay
        guard let top = day.max(), top > 0 else { return nil }
        return day.firstIndex(of: top)
    }

    /// Le moment le plus calme de la journée éveillée (entre 7 h et 23 h), s'il y a assez de plis pour le dire.
    var quietHour: Int? {
        let day = typicalDay
        guard day.reduce(0, +) >= 30 else { return nil }
        let awake = Array(7...22)
        return awake.min { day[$0] < day[$1] }
    }

    /// La part des plis faits le soir (après 20 h), entre 0 et 1.
    var eveningShare: Double? {
        let day = typicalDay
        let total = day.reduce(0, +)
        guard total >= 20 else { return nil }
        return Double(day[20...].reduce(0, +)) / Double(total)
    }
}

enum HoursText {
    /// « 9 PM », « 21 h » : l'heure seule, dans le format de l'iPhone.
    static func hour(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }

    static func weekday(_ index: Int) -> String {
        let names = Calendar.current.standaloneWeekdaySymbols
        return names.indices.contains(index) ? names[index] : ""
    }
}

/// La grille 7 × 24 : une ligne par jour (dans l'ordre de la semaine de l'iPhone), une case par heure.
struct HoursGrid: View {
    let grid: [Int]
    var accent: Color = .accentColor
    var empty: Color = Color.primary.opacity(0.08)
    var spacing: CGFloat = 3
    var showLabels = true
    var cornerRadius: CGFloat = 3

    var body: some View {
        let cells = grid.count == 168 ? grid : Array(repeating: 0, count: 168)
        let top = max(1, cells.max() ?? 1)
        let cal = Calendar.current
        let letters = cal.veryShortStandaloneWeekdaySymbols
        VStack(spacing: spacing + 1) {
            ForEach(0..<7, id: \.self) { row in
                let wd = (cal.firstWeekday - 1 + row) % 7
                HStack(spacing: spacing) {
                    if showLabels {
                        Text(letters.indices.contains(wd) ? letters[wd] : "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .leading)
                    }
                    ForEach(0..<24, id: \.self) { h in
                        let v = cells[wd * 24 + h]
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(v == 0 ? empty : accent.opacity(0.18 + 0.82 * Double(v) / Double(top)))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            if showLabels {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 14 + spacing, height: 1)
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(HoursText.hour(h))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Folds by day and hour"))
    }
}

/// La journée type : 24 barres, l'heure de pointe en couleur pleine.
struct TypicalDayBars: View {
    let hours: [Int]
    var accent: Color = .accentColor
    var empty: Color = Color.primary.opacity(0.08)
    var height: CGFloat = 54
    var showLabels = true

    var body: some View {
        let values = hours.count == 24 ? hours : Array(repeating: 0, count: 24)
        let top = max(1, values.max() ?? 1)
        let peak = (values.max() ?? 0) > 0 ? values.firstIndex(of: top) : nil
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == peak ? accent : (values[h] > 0 ? accent.opacity(0.4) : empty))
                        .frame(height: max(4, height * CGFloat(values[h]) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            if showLabels {
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(HoursText.hour(h))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Folds by hour of the day"))
    }
}
