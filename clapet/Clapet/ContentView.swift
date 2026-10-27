import Charts
import SwiftUI
import WidgetKit

// MARK: - Le style de Duo Folds
//
// Sombre et sobre : un fond vert-noir, des cartes cerclées d'un filet, des tuiles pleines,
// de grands chiffres fins et une seule couleur d'accent, le vert d'eau. Orange et rouge pour la limite.

extension Color {
    static let dfAccent = Color(red: 0.36, green: 0.89, blue: 0.78)
    static let dfBackground = Color(red: 0.055, green: 0.078, blue: 0.078)
    static let dfCard = Color(red: 0.135, green: 0.16, blue: 0.157)
    static let dfFill = Color.white.opacity(0.08)
    static let dfOutline = Color.white.opacity(0.17)
    static let dfBar = Color(red: 0.08, green: 0.36, blue: 0.32)
    static let dfWarning = Color(red: 1.0, green: 0.71, blue: 0.36)
    static let dfOver = Color(red: 1.0, green: 0.45, blue: 0.42)
}

/// Une carte : cerclée d'un filet, ou pleine (`filled`) pour les tuiles.
struct Card<Content: View>: View {
    let filled: Bool
    let content: Content

    init(filled: Bool = false, @ViewBuilder content: () -> Content) {
        self.filled = filled
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(filled ? Color.dfCard : Color.clear))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.dfOutline, lineWidth: 1)
                }
            }
    }
}

/// Le titre d'une carte.
struct CardTitle: View {
    let text: Text

    init(_ text: Text, symbol: String? = nil) {
        self.text = text
    }

    var body: some View {
        text
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

struct ContentView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var plusReason: PlusReason?
    @State private var showDemoWidgets = false
    @State private var showAuto = false
    @State private var showAdjust = false
    @State private var showWidgets = false
    @State private var bump = false
    /// Sans charnière : l'angle du dessin, qu'on « ferme » d'un toucher.
    @State private var tapAngle = 112.0

    /// Sous cet angle, le Duo est fermé (voir ClapetModel.hinge).
    private let closedBelow = 12

    private enum Page: Hashable { case today, week }
    @State private var page: Page = .today
    @Namespace private var tabSpace

    var body: some View {
        // Deux onglets en haut : Aujourd'hui et Semaine (on peut aussi glisser de l'un à l'autre).
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            TabView(selection: $page) {
                ScrollView { pane { todayPane } }
                    .tag(Page.today)
                ScrollView { pane { weekPane } }
                    .tag(Page.week)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color.dfBackground.ignoresSafeArea())
        .tint(.dfAccent)
        .modifier(HingeReader { closed, degrees in model.hinge(closed: closed, degrees: degrees) })
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model).environment(store)
        }
        .sheet(isPresented: $showAuto) {
            AutoCountView().environment(model)
        }
        .sheet(isPresented: $showAdjust) {
            AdjustCountView().environment(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showWidgets) {
            WidgetsHelpView().environment(model)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView().environment(model)
        }
        .sheet(item: $plusReason) { reason in
            PlusView(reason: reason.text).environment(model).environment(store)
        }
        .fullScreenCover(isPresented: $showDemoWidgets) {
            DemoWidgetsView().environment(model)
        }
        .task { await runDemo() }
        .onOpenURL { url in
            if url.host == "plus" && !store.hasPlus { plusReason = .widget }
        }
        .task {
            // Une seule fois, après 3 jours suivis : on présente Duo Folds+ (sans insister).
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let d = UserDefaults.standard
            if !Demo.seeded && !store.hasPlus && model.stats.daysCounted >= 3 && !d.bool(forKey: "plusPromptShown") {
                d.set(true, forKey: "plusPromptShown")
                plusReason = .tracking
            }
        }
        .onChange(of: model.claps) { _, _ in
            bump = false
            withAnimation(.easeOut(duration: 0.2)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) { bump = false }
            }
        }
    }

    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: Mode démo (vidéo)

    private func runDemo() async {
        switch Demo.screen {
        case "history": showHistory = true
        case "widgets": showDemoWidgets = true
        case "plus": plusReason = .menu
        default: break
        }
        let keys = Demo.hinge
        guard !keys.isEmpty else {
            if Demo.screen != nil || Demo.seeded {
                try? await Task.sleep(nanoseconds: UInt64(Demo.delay * 1_000_000_000))
                _ = Demo.markOrigin()
            }
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(Demo.delay * 1_000_000_000))
        let origin = Demo.markOrigin()
        let end = (keys.last?.t ?? 0) + 0.5
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(origin)
            model.hinge(closed: nil, degrees: Demo.angle(at: t, in: keys))
            if t > end { break }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    // MARK: En-têtes

    private var topBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                tab(Text("Today"), .today)
                tab(Text("Week"), .week)
            }
            .padding(4)
            .background(Capsule().fill(Color.dfCard))
            Spacer()
            Button { showWidgets = true } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Widgets"))
            Menu {
                Button { showAdjust = true } label: { Label { Text("Adjust the count") } icon: { Image(systemName: "pencil") } }
                Button { showAuto = true } label: { Label { Text("Automatic counting") } icon: { Image(systemName: "bolt.badge.automatic") } }
                Button {
                    if store.hasPlus { showHistory = true } else { plusReason = .history }
                } label: { Label { Text("History") } icon: { Image(systemName: "calendar") } }
                if !store.hasPlus {
                    Button { plusReason = .menu } label: { Label { Text("Duo Folds+") } icon: { Image(systemName: "plus.circle") } }
                }
                Button { showSettings = true } label: { Label { Text("Settings") } icon: { Image(systemName: "gearshape") } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .rotationEffect(.degrees(90))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("More"))
        }
        .foregroundStyle(.primary)
    }

    private func tab(_ title: Text, _ target: Page) -> some View {
        let selected = page == target
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { page = target }
        } label: {
            title
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? Color.dfBackground : Color.primary.opacity(0.8))
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.dfAccent)
                            .matchedGeometryEffect(id: "tab", in: tabSpace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Aujourd'hui (volet de gauche)

    private var todayPane: some View {
        let s = model.stats
        return Group {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .padding(.top, 8)
            HStack(alignment: .center, spacing: 8) {
                bigNumber
                    .layoutPriority(1)
                Spacer(minLength: 0)
                miniGauge
            }
            trend
            if s.autoLast == nil && !Demo.seeded { autoBanner }
            tiles
            timeOpen
            more
            footnote
        }
    }

    private var bigNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(model.stats.today)")
                .font(.system(size: 112, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: model.stats.today)
                .overlay(alignment: .topTrailing) {
                    Text("+1")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.dfAccent)
                        .offset(x: 26, y: bump ? 0 : 14)
                        .opacity(bump ? 1 : 0)
                        .allowsHitTesting(false)
                }
            Text("folds")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentShape(Rectangle())
        .onLongPressGesture { showAdjust = true }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Touch and hold to adjust the count"))
    }

    /// Aujourd'hui comparé à la moyenne des 30 derniers jours.
    private var trend: some View {
        let s = model.stats
        let today = s.today
        let symbol: String
        let color: Color
        let text: Text
        if let avg = s.recentAverage().map({ Int($0.rounded()) }) {
            let diff = today - avg
            if diff < 0 {
                symbol = "chart.line.downtrend.xyaxis"; color = .dfAccent
                text = Text("\(-diff) below your \(avg)/day average")
            } else if diff > 0 {
                symbol = "chart.line.uptrend.xyaxis"; color = .dfWarning
                text = Text("\(diff) above your \(avg)/day average")
            } else {
                symbol = "chart.line.flattrend.xyaxis"; color = .dfAccent
                text = Text("Right on your \(avg)/day average")
            }
        } else {
            symbol = "chart.line.flattrend.xyaxis"; color = .dfAccent
            text = Text("Your daily average shows up tomorrow")
        }
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
            text
                .font(.title3)
                .foregroundStyle(Color.primary.opacity(0.85))
        }
    }

    // MARK: La charnière

    private var angle: Double { model.degrees ?? tapAngle }

    private var miniGauge: some View {
        VStack(spacing: 4) {
            HingeArc(degrees: angle, closedBelow: Double(closedBelow), line: 10)
                .frame(width: 128, height: 70)
                .overlay(alignment: .bottom) {
                    Text("\(Int(angle.rounded()))°")
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                }
            hingeStatus
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 136)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !model.hasHinge else { return }
            // Sans charnière : on touche pour compter, la jauge se ferme puis se rouvre.
            withAnimation(.easeIn(duration: 0.12)) { tapAngle = 0 }
            model.clap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeOut(duration: 0.35)) { tapAngle = 112 }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var hingeStatus: Text {
        if !model.hasHinge { return Text("Tap to count") }
        if model.isClosed { return Text("Folded") }
        return Text("Counts below \(closedBelow)°")
    }

    // MARK: Les tuiles

    private var tiles: some View {
        let s = model.stats
        let left = s.left()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(Text("All time"), "\(s.totalCloses)")
            tile(Text("Last 7 days"), "\(s.weekTotal)")
            tile(Text("Opened today"), "\(s.day().opens)")
            tile(Text("Daily limit"), "\(s.goal)",
                 detail: left > 0 ? Text("\(left) left today") : (left == 0 ? Text("Limit reached") : Text("\(-left) over the limit")),
                 color: statusColor)
        }
    }

    /// Vert d'eau sous la limite, orange à l'approche (80 %), rouge au-delà.
    private var statusColor: Color {
        let s = model.stats
        guard s.goal > 0 else { return .dfAccent }
        if s.today > s.goal { return .dfOver }
        if Double(s.today) >= 0.8 * Double(s.goal) { return .dfWarning }
        return .dfAccent
    }

    private func tile(_ title: Text, _ value: String, detail: Text? = nil, color: Color = .secondary) -> some View {
        Card(filled: true) {
            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.headline.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                Text(value)
                    .font(.system(size: 34, weight: .regular))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    detail
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: La semaine (volet de droite)

    private var weekPane: some View {
        let s = model.stats
        let days = s.lastWeek()
        let total = days.reduce(0) { $0 + $1.closes }
        let perDay = Int((Double(total) / 7).rounded())
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
        let range = (start..<max(Date(), start.addingTimeInterval(60))).formatted(.interval.day().month(.abbreviated).year())
        let perDayText = Text("\(perDay) per day")
        return Group {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(total)")
                    .font(.system(size: 76, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                Text("folds · \(range)")
                    .font(.title3)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 6)
            Text("\(perDayText) · \(changeText(s.weekChange()))")
                .font(.title3)
                .foregroundStyle(Color.primary.opacity(0.85))
            weekBars(days, perDay: Double(total) / 7)
            heatmap
            lifetime
        }
    }

    private func changeText(_ change: Double?) -> Text {
        guard let change else { return Text("First week") }
        let pct = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if abs(change) < 0.005 { return Text("Same as the previous period") }
        return change > 0 ? Text("\(pct) more than the previous period") : Text("\(pct) less than the previous period")
    }

    private func weekBars(_ days: [(date: Date, closes: Int)], perDay: Double) -> some View {
        let goal = model.stats.goal
        let top = max(1, days.map(\.closes).max() ?? 1, Int(perDay.rounded()))
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Chart {
                    ForEach(0..<days.count, id: \.self) { i in
                        let n = days[i].closes
                        let isToday = i == days.count - 1
                        BarMark(x: .value("Day", days[i].date, unit: .day),
                                y: .value("Folds", max(Double(n), Double(top) * 0.018)),
                                width: .ratio(0.8))
                            .foregroundStyle(isToday ? Color.dfAccent : (goal > 0 && n > goal ? Color.dfOver.opacity(0.75) : Color.dfBar))
                            .cornerRadius(10)
                            .annotation(position: .top, spacing: 6) {
                                Text("\(n)")
                                    .font(.callout.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.primary.opacity(0.9))
                            }
                    }
                    if perDay > 0 {
                        RuleMark(y: .value("Average", perDay))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    }
                }
                .chartYScale(domain: 0...(Double(top) * 1.22))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                            .font(.headline)
                            .foregroundStyle(Color.primary.opacity(0.85))
                    }
                }
                .frame(height: 230)
                Text("Average \(Int(perDay.rounded())) per day")
                    .font(.headline.weight(.regular))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
        }
    }

    // MARK: Quand on plie (semaine type, heure par heure)

    private var heatmap: some View {
        let s = model.stats
        let grid = s.weekHours.count == 168 ? s.weekHours : Array(repeating: 0, count: 168)
        let top = max(1, grid.max() ?? 1)
        let cal = Calendar.current
        let letters = cal.veryShortStandaloneWeekdaySymbols
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(Text("When you fold"))
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        let wd = (cal.firstWeekday - 1 + row) % 7
                        HStack(spacing: 3) {
                            Text(letters.indices.contains(wd) ? letters[wd] : "")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .frame(width: 18, alignment: .leading)
                            ForEach(0..<24, id: \.self) { h in
                                let v = grid[wd * 24 + h]
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(v == 0 ? Color.dfFill : Color.dfAccent.opacity(0.16 + 0.84 * Double(v) / Double(top)))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 21, height: 1)
                        ForEach([0, 6, 12, 18], id: \.self) { h in
                            Text(Self.hourLabel(h))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                if let slot = s.busiestSlot {
                    let names = cal.standaloneWeekdaySymbols
                    let day = names.indices.contains(slot.weekday) ? names[slot.weekday] : ""
                    Text("Most folds: \(day), around \(Self.hourLabel(slot.hour))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Fills in as you fold, hour by hour.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func hourLabel(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }

    // MARK: Temps ouvert

    static func duration(_ t: TimeInterval) -> String {
        let minutes = Int(t / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: allowed, width: .abbreviated))
    }

    private var timeOpen: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let s = model.stats
            let week = s.lastWeek(now: now).map { (date: $0.date, hours: s.openTime($0.date, now: now) / 3600) }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        CardTitle(Text("Time open"))
                        Spacer()
                        if s.openSince != nil {
                            Label { Text("Open now") } icon: { Circle().fill(Color.dfAccent).frame(width: 7, height: 7) }
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.duration(s.openTime(now, now: now)))
                                .font(.system(size: 34, weight: .light))
                                .monospacedDigit()
                            Text("today").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Self.duration(s.openTime(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now, now: now)))
                                .font(.headline)
                                .monospacedDigit()
                            Text("yesterday").font(.footnote).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Self.duration(s.averageOpen(days: 7, now: now)))
                                .font(.headline)
                                .monospacedDigit()
                            Text("per day, 7 days").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.leading, 14)
                    }
                    Chart {
                        ForEach(0..<week.count, id: \.self) { i in
                            BarMark(x: .value("Day", week[i].date, unit: .day), y: .value("Hours", week[i].hours), width: .ratio(0.8))
                                .foregroundStyle(i == week.count - 1 ? Color.dfAccent : Color.dfBar)
                                .cornerRadius(6)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color.dfFill)
                            AxisValueLabel {
                                if let h = value.as(Double.self) { Text("\(Int(h)) h") }
                            }
                        }
                    }
                    .frame(height: 110)
                    if s.autoLast == nil {
                        Text("Measured only while Duo Folds is on screen. Set up the two Shortcuts automations to measure all day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Depuis le début (paliers)

    private var lifetime: some View {
        let level = model.stats.level
        let total = model.stats.totalCloses
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(Text("Lifetime"))
                HStack(alignment: .firstTextBaseline) {
                    Text("\(total)")
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
                    Text("folds")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let next = level.next {
                        Text("Next milestone: \(next)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: level.progress(total))
                    .tint(.dfAccent)
                if let next = level.next {
                    Text("\(next - total) folds to the next milestone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Comptage automatique

    private var autoBanner: some View {
        Button { showAuto = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.badge.automatic.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count even when the app is closed")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Set up the Shortcuts automation in one minute.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.dfAccent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.dfAccent.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Réglages rapides

    private var more: some View {
        VStack(spacing: 0) {
            row("bolt.badge.automatic", Text("Automatic counting"),
                model.stats.autoLast == nil ? Text("Off: counts only while the app is on screen") : Text("On, with Shortcuts"),
                locked: false) {
                showAuto = true
            }
            Divider().overlay(Color.dfOutline).padding(.leading, 56)
            row("pencil", Text("Adjust the count"), Text("Type today's folds or your lifetime total"), locked: false) {
                showAdjust = true
            }
            Divider().overlay(Color.dfOutline).padding(.leading, 56)
            row("calendar", Text("History"), Text("30 days, 12 months, records"), locked: !store.hasPlus) {
                if store.hasPlus { showHistory = true } else { plusReason = .history }
            }
            Divider().overlay(Color.dfOutline).padding(.leading, 56)
            row("bell.badge", Text("Limit alerts"), model.alertsOn && store.hasPlus ? Text("On") : Text("At 80 % and 100 % of your limit"),
                locked: !store.hasPlus) {
                if store.hasPlus { showSettings = true } else { plusReason = .alerts }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.dfOutline, lineWidth: 1))
    }

    private func row(_ symbol: String, _ title: Text, _ detail: Text, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    title.font(.body).foregroundStyle(.primary)
                    detail.font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if locked { PlusBadge() }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.hasHinge {
                Text("Without the automation, Duo Folds counts only while it's on screen, on the inner or the outer display.")
            } else {
                Text("No hinge here: tap the Duo drawing to count.")
            }
            Text("Add the widgets from your Home Screen or Lock Screen: touch and hold, Edit, then Duo Folds.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// La charnière en demi-cercle : à gauche fermé (0°), à droite à plat (180°).
/// Le petit trait marque l'angle sous lequel un pli est compté.
struct HingeArc: View {
    let degrees: Double
    let closedBelow: Double
    var line: CGFloat = 16

    var body: some View {
        GeometryReader { g in
            let line = self.line
            let radius = max(1, min(g.size.width / 2, g.size.height) - line / 2)
            let center = CGPoint(x: g.size.width / 2, y: g.size.height - line / 2)
            let value = min(180, max(0, degrees))
            ZStack {
                arc(0, 180, center, radius)
                    .stroke(Color.dfFill, style: StrokeStyle(lineWidth: line, lineCap: .round))
                arc(0, max(0.5, value), center, radius)
                    .stroke(Color.dfAccent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                Path { p in
                    p.move(to: point(closedBelow, center, radius - line * 0.95))
                    p.addLine(to: point(closedBelow, center, radius + line * 0.95))
                }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func point(_ hinge: Double, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let t = Double.pi - hinge * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(cos(t)), y: c.y - r * CGFloat(sin(t)))
    }

    private func arc(_ from: Double, _ to: Double, _ c: CGPoint, _ r: CGFloat) -> Path {
        Path { p in
            let steps = max(2, Int((to - from) / 2))
            for i in 0...steps {
                let pt = point(from + (to - from) * Double(i) / Double(steps), c, r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}

/// Les widgets : à quoi ils ressemblent et comment les ajouter.
struct WidgetsHelpView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entry = ClapetEntry(date: Date(), stats: model.stats)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        preview(entry, .systemSmall, width: 170, height: 170)
                        Spacer(minLength: 0)
                    }
                    preview(entry, .systemMedium, width: 364, height: 170)
                    VStack(alignment: .leading, spacing: 10) {
                        Label { Text("Touch and hold an empty spot on your Home Screen.") } icon: { Image(systemName: "hand.tap") }
                        Label { Text("Tap Edit, then Add Widget.") } icon: { Image(systemName: "plus.square") }
                        Label { Text("Search for Duo Folds and pick a size.") } icon: { Image(systemName: "magnifyingglass") }
                        Label { Text("On the Lock Screen too: touch and hold, Customize, then add Duo Folds.") } icon: { Image(systemName: "lock") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.9))
                }
                .padding(20)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Widgets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .tint(.dfAccent)
    }

    private func preview(_ entry: ClapetEntry, _ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        ClapetWidgetView(entry: entry, family: family)
            .padding(16)
            .frame(width: width, height: height)
            .background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

/// Pourquoi l'écran Duo Folds+ s'ouvre.
enum PlusReason: String, Identifiable {
    case menu, widget, tracking, history, alerts

    var id: String { rawValue }

    var text: Text? {
        switch self {
        case .menu: return nil
        case .widget: return Text("This widget is part of Duo Folds+.")
        case .tracking: return Text("Three days of tracking. Keep an eye on your folds right from your Home Screen.")
        case .alerts: return Text("Limit alerts are part of Duo Folds+.")
        case .history: return Text("Your full history and records are part of Duo Folds+.")
        }
    }
}
