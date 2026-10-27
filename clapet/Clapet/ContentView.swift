import Charts
import SwiftUI

// MARK: - Le style de Duo Folds
//
// Sobre, comme une app Santé : fonds et textes du système (clair ou sombre selon l'iPhone),
// une seule couleur d'accent (AccentColor, vert d'eau), l'orange et le rouge du système pour la limite.

extension Color {
    static let dfAccent = Color.accentColor
    static let dfBackground = Color(uiColor: .systemGroupedBackground)
    static let dfCard = Color(uiColor: .secondarySystemGroupedBackground)
    static let dfFill = Color(uiColor: .tertiarySystemFill)
    static let dfWarning = Color.orange
    static let dfOver = Color.red
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }
}

/// Le titre d'une carte, en petites capitales comme dans Santé.
struct CardTitle: View {
    let text: Text
    var symbol: String?

    init(_ text: Text, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            text
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.dfAccent)
        .textCase(.uppercase)
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
    @State private var bump = false
    @State private var tapOpen = 0.62

    private var openness: Double {
        if let d = model.degrees { return min(1, max(0, d / 180)) }
        return tapOpen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.stats.autoLast == nil && !Demo.seeded { autoBanner }
                    today
                    numbers
                    timeOpen
                    week
                    byHour
                    lifetime
                    more
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground)
            .navigationTitle(Text("Duo Folds"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.hasPlus {
                        Button { plusReason = .menu } label: {
                            Text("Plus").font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Duo Folds+"))
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
        }
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

    // MARK: Aujourd'hui

    /// Vert d'eau sous la limite, orange à l'approche (80 %), rouge au-delà.
    private var statusColor: Color {
        let s = model.stats
        guard s.goal > 0 else { return .dfAccent }
        if s.today > s.goal { return .dfOver }
        if Double(s.today) >= 0.8 * Double(s.goal) { return .dfWarning }
        return .dfAccent
    }

    private var status: Text {
        let left = model.stats.left()
        if left > 0 { return Text("\(left) left today") }
        if left == 0 { return Text("Limit reached") }
        return Text("\(-left) over the limit")
    }

    private var today: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardTitle(Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)), symbol: "calendar")
                    Spacer()
                    if model.hasHinge, let d = model.degrees {
                        Text("Hinge \(Int(d.rounded()))°")
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button { showAdjust = true } label: {
                        Image(systemName: "pencil")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.dfFill))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dfAccent)
                    .accessibilityLabel(Text("Adjust the count"))
                }
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Circle().stroke(statusColor.opacity(0.15), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: model.stats.progress)
                            .stroke(statusColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.4), value: model.stats.progress)
                        VStack(spacing: 0) {
                            Text("\(model.stats.today)")
                                .font(.system(size: 40, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.25), value: model.stats.today)
                            Text("folds")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 132, height: 132)
                    .contentShape(Circle())
                    .onLongPressGesture { showAdjust = true }
                    .overlay(alignment: .topTrailing) {
                        Text("+1")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .offset(x: 10, y: bump ? -12 : 0)
                            .opacity(bump ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        status
                            .font(.headline)
                            .foregroundStyle(statusColor)
                        stat(Text("Daily limit"), "\(model.stats.goal)")
                        stat(Text("Yesterday"), "\(model.stats.yesterday())")
                    }
                    Spacer(minLength: 0)
                }
                HingeGauge(openness: openness)
                    .frame(height: 64)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !model.hasHinge else { return }
                        // Sans charnière : on touche le Duo pour compter.
                        withAnimation(.easeIn(duration: 0.12)) { tapOpen = 0 }
                        model.clap()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.easeOut(duration: 0.3)) { tapOpen = 0.62 }
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: Les chiffres

    private var numbers: some View {
        let d = model.stats.day()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(Text("Closed today"), value: d.closes, symbol: "rectangle.compress.vertical")
            tile(Text("Opened today"), value: d.opens, symbol: "rectangle.expand.vertical")
            tile(Text("Last 7 days"), value: model.stats.weekTotal, symbol: "calendar")
            tile(Text("All time"), value: model.stats.totalCloses, symbol: "sum")
        }
    }

    private func tile(_ title: Text, value: Int, symbol: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label { title } icon: { Image(systemName: symbol).foregroundStyle(Color.dfAccent) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardTitle(Text("Time open"), symbol: "hourglass")
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
                                .font(.system(size: 28, weight: .bold))
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
                            BarMark(x: .value("Day", week[i].date, unit: .day), y: .value("Hours", week[i].hours))
                                .foregroundStyle(Color.dfAccent.opacity(i == week.count - 1 ? 1 : 0.55))
                                .cornerRadius(4)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
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

    // MARK: La semaine

    private var week: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(Text("This week"), symbol: "chart.bar.fill")
                ClapetWeekChart(days: model.stats.lastWeek(), goal: model.stats.goal)
                    .frame(height: 150)
            }
        }
    }

    // MARK: Heure par heure

    private var byHour: some View {
        let hours = model.stats.hours()
        let top = max(1, hours.max() ?? 1)
        let peak = (hours.max() ?? 0) > 0 ? hours.firstIndex(of: top) : nil
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardTitle(Text("Today by hour"), symbol: "clock.fill")
                    Spacer()
                    if let peak {
                        Text("Peak \(Self.hourLabel(peak))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(h == peak ? Color.dfAccent : (hours[h] > 0 ? Color.dfAccent.opacity(0.45) : Color.dfFill))
                            .frame(height: max(4, 46 * CGFloat(hours[h]) / CGFloat(top)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 46, alignment: .bottom)
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(Self.hourLabel(h))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    static func hourLabel(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }

    // MARK: Depuis le début (paliers)

    private var lifetime: some View {
        let level = model.stats.level
        let total = model.stats.totalCloses
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(Text("Lifetime"), symbol: "infinity")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(total)")
                        .font(.system(size: 30, weight: .bold))
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
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfAccent.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Historique et alertes

    private var more: some View {
        VStack(spacing: 0) {
            row("bolt.badge.automatic", Text("Automatic counting"),
                model.stats.autoLast == nil ? Text("Off: counts only while the app is on screen") : Text("On, with Shortcuts"),
                locked: false) {
                showAuto = true
            }
            Divider().padding(.leading, 52)
            row("pencil", Text("Adjust the count"), Text("Type today's folds or your lifetime total"), locked: false) {
                showAdjust = true
            }
            Divider().padding(.leading, 52)
            row("calendar", Text("History"), Text("30 days, 12 months, records"), locked: !store.hasPlus) {
                if store.hasPlus { showHistory = true } else { plusReason = .history }
            }
            Divider().padding(.leading, 52)
            row("bell.badge", Text("Limit alerts"), model.alertsOn && store.hasPlus ? Text("On") : Text("At 80 % and 100 % of your limit"),
                locked: !store.hasPlus) {
                if store.hasPlus { showSettings = true } else { plusReason = .alerts }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }

    private func row(_ symbol: String, _ title: Text, _ detail: Text, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 24)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

/// Les 7 derniers jours en barres : vert d'eau sous la limite, rouge au-dessus, la limite en pointillés.
struct ClapetWeekChart: View {
    let days: [(date: Date, closes: Int)]
    let goal: Int

    var body: some View {
        Chart {
            ForEach(0..<days.count, id: \.self) { i in
                BarMark(x: .value("Day", days[i].date, unit: .day),
                        y: .value("Folds", days[i].closes))
                    .foregroundStyle((goal > 0 && days[i].closes > goal ? Color.dfOver : Color.dfAccent).opacity(i == days.count - 1 ? 1 : 0.55))
                    .cornerRadius(4)
            }
            if goal > 0 {
                RuleMark(y: .value("Limit", goal))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
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
