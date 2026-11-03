import SwiftUI

/// Les couleurs de la carte, selon le thème choisi (couleurs fixes, pour qu'elle rende pareil partout).
struct ShareCardPalette {
    var top: Color
    var bottom: Color
    var accent: Color
    var bar: Color
    var ink: Color
    var over = Color(red: 1.0, green: 0.45, blue: 0.42)
    var aurora = false

    static func of(_ look: DFLook) -> ShareCardPalette {
        switch look {
        case .night:
            return .init(top: Color(red: 0.055, green: 0.078, blue: 0.078), bottom: Color(red: 0.05, green: 0.21, blue: 0.19),
                         accent: Color(red: 0.36, green: 0.89, blue: 0.78), bar: Color(red: 0.12, green: 0.42, blue: 0.37), ink: .white)
        case .classic:
            return .init(top: Color(red: 0.97, green: 0.98, blue: 0.98), bottom: Color(red: 0.86, green: 0.94, blue: 0.92),
                         accent: Color(red: 0.2, green: 0.62, blue: 0.55), bar: Color(red: 0.2, green: 0.62, blue: 0.55).opacity(0.35),
                         ink: Color(red: 0.08, green: 0.1, blue: 0.1), over: Color(red: 0.86, green: 0.25, blue: 0.22))
        case .minimal:
            return .init(top: .white, bottom: Color(white: 0.95), accent: .black, bar: Color.black.opacity(0.18), ink: .black,
                         over: Color(red: 0.86, green: 0.25, blue: 0.22))
        case .aurora:
            return .init(top: Aurora.deep, bottom: Aurora.night, accent: Aurora.mint, bar: Color.white.opacity(0.22), ink: .white, aurora: true)
        case .custom:
            let dark = CustomTheme.isDark
            return .init(top: CustomTheme.top, bottom: CustomTheme.bottom, accent: CustomTheme.accent,
                         bar: CustomTheme.accent.opacity(0.4), ink: dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.1))
        }
    }
}

/// L'image à partager : la journée en un coup d'œil, aux couleurs du thème.
struct ShareCard: View {
    let stats: ClapetStats
    let date: Date
    var palette: ShareCardPalette = .of(DFLook.current)

    private var top: Color { palette.top }
    private var bottom: Color { palette.bottom }
    private var mint: Color { palette.accent }
    private var bar: Color { palette.bar }
    private var over: Color { palette.over }

    var body: some View {
        let today = stats.day(date).closes
        let week = stats.lastWeek(now: date)
        let highest = max(1, week.map(\.closes).max() ?? 1)
        let left = stats.goal - today
        VStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 14, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(mint)
            Spacer(minLength: 12)
            Text("Today I folded my phone")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.ink.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(today)")
                    .font(.system(size: 96, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(palette.aurora ? AnyShapeStyle(Aurora.glow) : AnyShapeStyle(palette.ink))
                Text("times")
                    .font(.system(size: 26))
                    .foregroundStyle(palette.ink.opacity(0.7))
            }
            Group {
                if stats.goalOn && left >= 0 {
                    Text("Under my daily limit of \(stats.goal) 🎯")
                } else if stats.goalOn {
                    Text("\(-left) over my daily limit")
                } else if let avg = stats.averageRef(now: date) {
                    Text("My average: \(avg) a day")
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(stats.goalOn && left < 0 ? over : mint)
            Spacer(minLength: 18)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<week.count, id: \.self) { i in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(i == week.count - 1 ? mint : bar)
                            .frame(height: max(6, 88 * CGFloat(week[i].closes) / CGFloat(highest)))
                        Text(week[i].date, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.ink.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                Image("TutorialIcon")
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Foldly")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text("The fold counter · App Store")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink.opacity(0.6))
                }
            }
        }
        .padding(26)
        .frame(width: 360, height: 450)
        .background {
            if palette.aurora {
                AuroraBackdrop(animated: false)
            } else {
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            }
        }
        .environment(\.colorScheme, palette.ink == .white ? .dark : .light)
    }
}

/// « Partager ma journée » : l'aperçu de la carte, et le bouton de partage.
struct ShareDaySheet: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?

    static let appStoreURL = "https://apps.apple.com/app/id6827349081"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ShareCard(stats: model.stats, date: Date())
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    if let image {
                        ShareLink(item: image,
                                  message: Text("My folds today with Foldly: \(Self.appStoreURL)"),
                                  preview: SharePreview(Text(verbatim: "Foldly"), image: image)) {
                            Label { Text("Share") } icon: { Image(systemName: "square.and.arrow.up") }
                                .font(.headline)
                                .frame(maxWidth: 320)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.dfAccent))
                                .foregroundStyle(Color.dfOnAccent)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Share my day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .task { await render() }
        }
        .tint(.dfAccent)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: ShareCard(stats: model.stats, date: Date()))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}

/// La santé de la charnière : le total, et à ce rythme, quand on atteint 32 000 plis
/// (un test public d'endurance a plié ce téléphone 32 000 fois).
struct HingeHealthContent: View {
    let stats: ClapetStats
    var accent: Color = .dfAccent

    static let benchmark = 32_000

    var body: some View {
        let total = stats.totalCloses
        let pace = stats.recentAverage() ?? stats.dailyAverage()
        let bench = Self.benchmark.formatted()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(total)")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text("folds since you started counting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, Double(total) / Double(Self.benchmark)))
                .tint(accent)
            Text("A public durability test folded this phone \(bench) times, and the crease gets deeper with folds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if total >= Self.benchmark {
                Text("You're past \(bench) folds. Every fold you skip spares your crease.")
                    .font(.subheadline.weight(.medium))
            } else if pace >= 1 {
                let days = Double(Self.benchmark - total) / pace
                let target = Date().addingTimeInterval(days * 86_400)
                let span = (Date()..<target).formatted(.components(style: .wide, fields: [.year, .month, .day]))
                Text("At your pace (\(Int(pace.rounded())) a day), you'll reach \(bench) folds in \(span).")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("10 fewer folds a day is 3,650 fewer a year: less wear on the hinge and the crease.")
                .font(.footnote)
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
