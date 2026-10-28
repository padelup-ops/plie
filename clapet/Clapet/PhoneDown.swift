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
            let plants = stats.plants(now: now)
            let since = stats.downSince(now: now)
            let reached = down >= goal && goal > 0
            VStack(alignment: .leading, spacing: 12) {
                // Sur l'écran extérieur (étroit), « objectif atteint » passe sous le temps.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        downText(down)
                        goalText(goal)
                        Spacer(minLength: 8)
                        if reached { reachedLabel }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            downText(down)
                            goalText(goal)
                        }
                        if reached { reachedLabel }
                    }
                }
                ProgressView(value: goal > 0 ? min(1, down / goal) : 0)
                    .tint(accent)
                plantsRow(plants: plants, since: since, now: now)
                if plants > 0 {
                    GardenStrip(plants: plants, color: accent)
                }
                Button(action: onGarden) {
                    HStack {
                        Label { Text("My garden") } icon: { Image(systemName: "tree.fill") }
                        Spacer()
                        Text("\(stats.totalPlants)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        let won = GardenBadges.all(stats, now: now).filter(\.unlocked).count
                        if won > 0 {
                            Label { Text(verbatim: "\(won)") } icon: { Image(systemName: "rosette") }
                                .labelStyle(.titleAndIcon)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("Badges"))
                        }
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

    private func downText(_ down: TimeInterval) -> some View {
        Text(Self.format(down))
            .font(.system(size: 32, weight: .light))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func goalText(_ goal: TimeInterval) -> some View {
        Text("of \(Self.format(goal))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var reachedLabel: some View {
        Label { Text("Goal reached") } icon: { Image(systemName: "checkmark.seal.fill") }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(accent)
            .lineLimit(1)
    }

    /// Les plantes du jour, et celle qui pousse en ce moment (un anneau qui se remplit en 25 minutes).
    private func plantsRow(plants: Int, since: Date?, now: Date) -> some View {
        let growing = since.map { Garden.growing(since: $0, now: now) }
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(accent.opacity(0.18), lineWidth: 3)
                if let growing {
                    Circle()
                        .trim(from: 0, to: max(0.03, growing.fraction))
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if plants == 0 {
                        Text("No plant yet today")
                    } else if plants == 1 {
                        Text("1 plant today")
                    } else {
                        Text("\(plants) plants today")
                    }
                }
                .font(.subheadline.weight(.semibold))
                Group {
                    if let growing {
                        Text("Next plant in \(growing.minutesLeft) min")
                    } else {
                        Text("Keep your phone closed 25 minutes in a row: a plant grows.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    static func format(_ t: TimeInterval) -> String { Garden.format(t) }

    static func plantSymbol(_ i: Int) -> String { Garden.symbol(i) }
}

/// Le jardin : toutes les plantes, et les journées téléphone posé.
struct GardenView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.stats
        let total = s.totalPlants
        let days = Array(s.lastDays(14).reversed())
        let badges = GardenBadges.all(s)
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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 34), spacing: 6)], spacing: 8) {
                                ForEach(0..<min(total, 60), id: \.self) { i in
                                    Image(systemName: Garden.symbol(i))
                                        .font(.title3)
                                        .foregroundStyle(Color.dfAccent.opacity(Garden.shade(i)))
                                }
                            }
                            if total > 60 {
                                Text("And \(total - 60) more")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 16) {
                        ForEach(badges) { b in BadgeTile(badge: b) }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Badges")
                } footer: {
                    Text("\(badges.filter(\.unlocked).count) of \(badges.count) unlocked")
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
                            Label { Text("\(s.plants(d.date))").monospacedDigit() } icon: { Image(systemName: "leaf.fill") }
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
