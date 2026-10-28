import SwiftUI

/// « Téléphone posé » : le temps où le téléphone reste fermé, l'objectif du jour et les plantes qui poussent
/// (une toutes les 25 minutes d'affilée). Les sessions viennent des automatisations Fermé / Ouvert.
struct PhoneDownContent: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent
    var onGarden: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let down = stats.downTime(now: now)
            let goal = Double(stats.downGoalMinutes) * 60
            let plants = stats.day(now).plants
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.format(down))
                        .font(.system(size: 32, weight: .light))
                        .monospacedDigit()
                    Text("of \(Self.format(goal))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if down >= goal && goal > 0 {
                        Label { Text("Goal reached") } icon: { Image(systemName: "checkmark.seal.fill") }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                ProgressView(value: goal > 0 ? min(1, down / goal) : 0)
                    .tint(accent)
                HStack(spacing: 4) {
                    if plants == 0 {
                        Text("Keep your phone closed 25 minutes in a row: a plant grows.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(0..<min(plants, 12), id: \.self) { i in
                            Image(systemName: Self.plantSymbol(i))
                                .foregroundStyle(accent.opacity(0.55 + 0.45 * Double(i % 3) / 2))
                        }
                        if plants > 12 {
                            Text("+\(plants - 12)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("\(plants) today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title3)
                Button(action: onGarden) {
                    HStack {
                        Label { Text("My garden") } icon: { Image(systemName: "tree.fill") }
                        Spacer()
                        Text("\(stats.totalPlants)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                if stats.autoLast == nil {
                    Text("Needs the two Shortcuts automations (Closed and Opened) to measure the time your phone stays down.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let minutes = Int(t / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: allowed, width: .abbreviated))
    }

    static func plantSymbol(_ i: Int) -> String {
        ["leaf.fill", "camera.macro", "tree.fill"][i % 3]
    }
}

/// Le jardin : toutes les plantes, et les journées téléphone posé.
struct GardenView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.stats
        let total = s.totalPlants
        let days = Array(s.lastDays(14).reversed())
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(total)")
                                .font(.system(size: 44, weight: .light))
                                .monospacedDigit()
                            Text("plants grown")
                                .foregroundStyle(.secondary)
                        }
                        if total == 0 {
                            Text("Your garden is empty for now. Keep your phone closed 25 minutes in a row: a plant grows.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 8) {
                                ForEach(0..<min(total, 300), id: \.self) { i in
                                    Image(systemName: PhoneDownContent.plantSymbol(i))
                                        .font(.title3)
                                        .foregroundStyle(Color.dfAccent.opacity(0.5 + 0.5 * Double((i * 7) % 5) / 4))
                                }
                            }
                            if total > 300 {
                                Text("And \(total - 300) more")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    ForEach(0..<days.count, id: \.self) { i in
                        let d = days[i]
                        HStack {
                            Text(d.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                            Spacer()
                            Text(PhoneDownContent.format(s.downTime(d.date)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Label { Text("\(s.day(d.date).plants)").monospacedDigit() } icon: { Image(systemName: "leaf.fill") }
                                .foregroundStyle(Color.dfAccent)
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Phone down, day by day")
                }
            }
            .navigationTitle(Text("My garden"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .tint(.dfAccent)
    }
}
