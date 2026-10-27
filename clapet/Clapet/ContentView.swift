import Charts
import SwiftUI

extension Color {
    static let clapetInk = Color(red: 0.06, green: 0.07, blue: 0.16)
    static let clapetCard = Color(red: 0.12, green: 0.13, blue: 0.27)
    static let clapetOrange = Color(red: 1.0, green: 0.54, blue: 0.24)
    static let clapetYellow = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let clapetPink = Color(red: 1.0, green: 0.31, blue: 0.48)
    static let clapetCyan = Color(red: 0.49, green: 0.98, blue: 1.0)
}

struct ContentView: View {
    @Environment(ClapetModel.self) private var model
    @State private var showSettings = false
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
            SettingsView().environment(model)
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

    // MARK: En-tête

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Clapet")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.clapetYellow, .clapetOrange, .clapetPink], startPoint: .leading, endPoint: .trailing))
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
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
                    Circle().stroke(Color.clapetOrange.opacity(0.18), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: model.stats.progress)
                        .stroke(AngularGradient(colors: [.clapetYellow, .clapetOrange, .clapetPink, .clapetYellow], center: .center),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.stats.progress)
                    VStack(spacing: 0) {
                        Text("\(model.stats.today)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: model.stats.today)
                        Text("claps")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Label {
                        Text("Goal \(model.stats.goal)")
                    } icon: {
                        Image(systemName: "target").foregroundStyle(Color.clapetOrange)
                    }
                    Label {
                        Text("Best day \(model.stats.best)")
                    } icon: {
                        Image(systemName: "trophy.fill").foregroundStyle(Color.clapetYellow)
                    }
                    if model.stats.today >= model.stats.goal && model.stats.goal > 0 {
                        Text("Goal reached!")
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .foregroundStyle(Color.clapetPink)
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.clapetCard))
        .accessibilityElement(children: .combine)
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
                tip("hand.raised.fill", Text("Clapet counts while it's on screen. Keep it open, then close and open your Duo: clap!"))
            } else {
                tip("hand.tap.fill", Text("No hinge here: tap Clapet to count."))
            }
            tip("square.grid.2x2.fill", Text("Add the widget: touch and hold your Home Screen or Lock Screen, tap Edit, then add Clapet."))
            tip("bolt.fill", Text("In the Shortcuts app, the “Count a clap” action adds one clap, even when Clapet is closed."))
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
                        y: .value("Claps", days[i].closes))
                    .foregroundStyle(i == days.count - 1 ? Color.clapetOrange : Color.clapetOrange.opacity(0.4))
                    .cornerRadius(6)
            }
            if goal > 0 {
                RuleMark(y: .value("Goal", goal))
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
