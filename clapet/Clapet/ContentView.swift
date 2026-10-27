import Charts
import SwiftUI

extension Color {
    static let clapetInk = Color(red: 0.06, green: 0.07, blue: 0.16)
    static let clapetCard = Color(red: 0.12, green: 0.13, blue: 0.27)
    static let clapetOrange = Color(red: 1.0, green: 0.54, blue: 0.24)
    static let clapetYellow = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let clapetPink = Color(red: 1.0, green: 0.31, blue: 0.48)
    static let clapetCyan = Color(red: 0.49, green: 0.98, blue: 1.0)
    static let clapetMint = Color(red: 0.43, green: 0.84, blue: 0.65)
}

struct ContentView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var plusReason: PlusReason?
    @State private var showDemoWidgets = false
    @State private var burst = false
    @State private var blink = false
    @State private var tapOpen = 1.0

    private var openness: Double {
        if let d = model.degrees { return min(1, max(0, d / 140)) }
        return tapOpen
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.clapetInk, Color(red: 0.10, green: 0.08, blue: 0.22)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    hero
                    numbers
                    extras
                    week
                    hoursAndLevel
                    tips
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .modifier(HingeReader { closed, degrees in model.hinge(closed: closed, degrees: degrees) })
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(model).environment(store)
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
            burst = false
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { burst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.25)) { burst = false }
            }
        }
        .task {
            // La mascotte cligne des yeux de temps en temps.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.5...5.5) * 1_000_000_000))
                blink = true
                try? await Task.sleep(nanoseconds: 140_000_000)
                blink = false
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

    // MARK: En-tête

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Duo Folds")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.clapetYellow, .clapetOrange, .clapetPink], startPoint: .leading, endPoint: .trailing))
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if !store.hasPlus {
                Button {
                    plusReason = .menu
                } label: {
                    Text("Plus")
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.43, green: 0.84, blue: 0.65), .clapetCyan], startPoint: .leading, endPoint: .trailing)))
                }
                .accessibilityLabel(Text("Duo Folds+"))
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.clapetCard))
            }
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.top, 8)
    }

    // MARK: La mascotte et l'anneau

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                MascotView(openness: openness, blink: blink)
                    .frame(height: 190)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !model.hasHinge else { return }
                        // Sans charnière : on touche Clapet pour compter.
                        withAnimation(.spring(response: 0.12, dampingFraction: 0.9)) { tapOpen = 0 }
                        model.clap()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { tapOpen = 1 }
                        }
                    }
                Text("CLAP!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.clapetYellow)
                    .shadow(color: .clapetPink, radius: 0, x: 3, y: 3)
                    .rotationEffect(.degrees(-10))
                    .scaleEffect(burst ? 1 : 0.3)
                    .opacity(burst ? 1 : 0)
                    .padding(.top, 10)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(ringColor.opacity(0.18), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: model.stats.progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.stats.progress)
                    VStack(spacing: 0) {
                        Text("\(model.stats.today)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: model.stats.today)
                        Text("folds")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Label {
                        Text("Limit \(model.stats.goal)")
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(ringColor)
                    }
                    Label {
                        Text("Yesterday \(model.stats.yesterday())")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.clapetCyan)
                    }
                    status
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .foregroundStyle(ringColor)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.clapetCard))
        .accessibilityElement(children: .combine)
    }

    /// Menthe sous la limite, jaune à l'approche, rose au-delà.
    private var ringColor: Color {
        let s = model.stats
        guard s.goal > 0 else { return .clapetMint }
        if s.today > s.goal { return .clapetPink }
        if Double(s.today) >= 0.8 * Double(s.goal) { return .clapetYellow }
        return .clapetMint
    }

    private var status: Text {
        let left = model.stats.left()
        if left > 0 { return Text("\(left) left today") }
        if left == 0 { return Text("Limit reached") }
        return Text("\(-left) over the limit")
    }

    // MARK: Les chiffres

    private var numbers: some View {
        let d = model.stats.day()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(Text("Closed today"), value: d.closes, symbol: "rectangle.portrait.on.rectangle.portrait.fill", color: .clapetOrange)
            tile(Text("Opened today"), value: d.opens, symbol: "book.fill", color: .clapetCyan)
            tile(Text("Last 7 days"), value: model.stats.weekTotal, symbol: "calendar", color: .clapetYellow)
            tile(Text("All time"), value: model.stats.totalCloses, symbol: "infinity", color: .clapetPink)
        }
    }

    private func tile(_ title: Text, value: Int, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            title
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.clapetCard))
        .accessibilityElement(children: .combine)
    }

    // MARK: Alertes et historique

    private var extras: some View {
        HStack(spacing: 12) {
            Button {
                if store.hasPlus { showSettings = true } else { plusReason = .alerts }
            } label: {
                extraCard("bell.badge.fill", .clapetYellow, Text("Limit alerts"), Text("A notification at 80 % and 100 % of your limit"),
                          badge: alertsBadge)
            }
            Button {
                if store.hasPlus { showHistory = true } else { plusReason = .history }
            } label: {
                extraCard("calendar", .clapetCyan, Text("History"), Text("30 days, 12 months, records"),
                          badge: store.hasPlus ? nil : AnyView(PlusBadge()))
            }
        }
        .buttonStyle(.plain)
    }

    private var alertsBadge: AnyView? {
        if !store.hasPlus { return AnyView(PlusBadge()) }
        guard model.alertsOn else { return nil }
        return AnyView(Text("On")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.clapetMint))
    }

    private func extraCard(_ symbol: String, _ color: Color, _ title: Text, _ detail: Text, badge: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                if let badge { badge }
            }
            title
                .font(.system(.headline, design: .rounded, weight: .black))
            detail
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.clapetCard))
        .contentShape(Rectangle())
    }

    // MARK: La semaine

    private var week: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .font(.system(.headline, design: .rounded, weight: .black))
            ClapetWeekChart(days: model.stats.lastWeek(), goal: model.stats.goal)
                .frame(height: 150)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.clapetCard))
    }

    // MARK: Heure par heure et niveau

    private var hoursAndLevel: some View {
        let hours = model.stats.hours()
        let top = max(1, hours.max() ?? 1)
        let peak = (hours.max() ?? 0) > 0 ? hours.firstIndex(of: top) : nil
        let level = model.stats.level
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today by hour")
                    .font(.system(.headline, design: .rounded, weight: .black))
                Spacer()
                if let peak {
                    Text("Peak \(Self.hourLabel(peak))")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(h == peak ? Color.clapetOrange : Color.white.opacity(hours[h] > 0 ? 0.35 : 0.12))
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
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))

            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.clapetYellow)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Level \(level.number)")
                        .font(.system(.headline, design: .rounded, weight: .black))
                    Text(level.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                if let next = level.next {
                    Text("\(next - model.stats.totalCloses) to level \(level.number + 1)")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.clapetYellow, .clapetOrange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * CGFloat(level.progress(model.stats.totalCloses))))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.clapetCard))
    }

    static func hourLabel(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }

    // MARK: Conseils

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasHinge {
                tip("hand.raised.fill", Text("Duo Folds counts while it's on screen. Keep it open, then close and open your Duo: clap!"))
            } else {
                tip("hand.tap.fill", Text("No hinge here: tap the mascot to count."))
            }
            tip("square.grid.2x2.fill", Text("Add the widget: touch and hold your Home Screen or Lock Screen, tap Edit, then add Duo Folds."))
            tip("bolt.fill", Text("In the Shortcuts app, the “Count a fold” action adds one fold, even when Duo Folds is closed."))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.clapetCard.opacity(0.6)))
    }

    private func tip(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.clapetOrange)
                .frame(width: 22)
            text
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Les 7 derniers jours en barres, aujourd'hui en couleur.
struct ClapetWeekChart: View {
    let days: [(date: Date, closes: Int)]
    let goal: Int

    var body: some View {
        Chart {
            ForEach(0..<days.count, id: \.self) { i in
                BarMark(x: .value("Day", days[i].date, unit: .day),
                        y: .value("Folds", days[i].closes))
                    .foregroundStyle((goal > 0 && days[i].closes > goal ? Color.clapetPink : Color.clapetMint).opacity(i == days.count - 1 ? 1 : 0.5))
                    .cornerRadius(6)
            }
            if goal > 0 {
                RuleMark(y: .value("Limit", goal))
                    .foregroundStyle(Color.clapetYellow.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.1))
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
        case .tracking: return Text("Three days of tracking! Keep an eye on your folds right from your Home Screen.")
        case .alerts: return Text("Limit alerts are part of Duo Folds+.")
        case .history: return Text("Your full history and records are part of Duo Folds+.")
        }
    }
}
