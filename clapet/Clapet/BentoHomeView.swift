import SwiftUI

// MARK: - Le look « Bento » (à l'essai)
//
// Une grille de cartes vivantes, façon « design system » : fond clair et plat, cartes blanches à ombre douce,
// deux cartes sombres, UNE couleur d'accent (bleu). Tout bouge un peu : entrée en ressort décalée, chiffres
// qui roulent, jauge de charnière qui suit le téléphone, point qui pulse quand le Duo est ouvert.

enum Bento {
    static let bg = Color(red: 0.969, green: 0.969, blue: 0.961)       // #F7F7F5
    static let tray = Color(red: 0.933, green: 0.933, blue: 0.918)     // #EEEEEA
    static let card = Color.white
    static let dark = Color(red: 0.059, green: 0.059, blue: 0.071)     // #0F0F12
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.086)      // #141416
    static let muted = Color(red: 0.545, green: 0.545, blue: 0.529)    // #8B8B87
    static let accent = Color(red: 0.184, green: 0.357, blue: 1.0)     // #2F5BFF
    static let tint = Color(red: 0.933, green: 0.949, blue: 1.0)       // #EEF2FF
    static let line = Color.black.opacity(0.07)
}

struct BentoHomeView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showBoards = false
    @State private var showHistory = false
    @State private var showWeek = false
    @State private var showAuto = false
    @State private var showAdjust = false
    @State private var showShare = false
    @State private var showWidgets = false
    @State private var showMonth = false
    @State private var showHours = false
    @State private var plusReason: PlusReason?
    @State private var foldboardPromoHidden = false
    @State private var appeared = false
    @State private var bump = false

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width >= 520
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    grid(wide: wide)
                }
                .padding(.horizontal, 18)
                .padding(.top, 36)
                .padding(.bottom, 120)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .environment(\.colorScheme, .light)
        }
        .background(Bento.bg.ignoresSafeArea())
        .tint(Bento.accent)
        .modifier(HingeReader { closed, degrees in model.hinge(closed: closed, degrees: degrees) })
        .sheet(isPresented: $showSettings) { SettingsView().environment(model).environment(store) }
        .sheet(isPresented: $showBoards) { LeaderboardView().environment(model).environment(store) }
        .sheet(isPresented: $showAuto) { AutoCountView().environment(model) }
        .sheet(isPresented: $showWeek) { WeekRecapView().environment(model) }
        .sheet(isPresented: $showShare) { ShareDaySheet().environment(model) }
        .sheet(isPresented: $showMonth) {
            if store.hasPlus { MonthRecapView().environment(model) } else { PlusView(reason: Text("The monthly recap is part of Foldly+.")).environment(model).environment(store) }
        }
        .sheet(isPresented: $showHours) { if store.hasPlus { HoursSheet().environment(model) } else { PlusView(reason: Text("Your hours are part of Foldly+.")).environment(model).environment(store) } }
        .sheet(isPresented: $showAdjust) { AdjustCountView().environment(model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showWidgets) { WidgetsHelpView().environment(model).environment(store) }
        .sheet(isPresented: $showHistory) { HistoryView().environment(model) }
        .sheet(item: $plusReason) { reason in PlusView(reason: reason.text(model.stats)).environment(model).environment(store) }
        .onOpenURL { url in
            if url.host == "plus" && !store.hasPlus { plusReason = .widget }
            if url.host == "week" { showWeek = true }
            if url.host == "month" { showMonth = true }
            if url.host == "hours" { showHours = true }
            if url.host == "boards" { showBoards = true }
            if url.host == "share" { showShare = true }
            if url.host == "settings" { showSettings = true }
            if url.host == "repos" { model.setRest(true) }
            if url.host == "utilise" { model.setRest(false) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let d = UserDefaults.standard
            if !Demo.seeded && !store.hasPlus && model.stats.daysCounted >= 3 && !d.bool(forKey: "plusPromptShown") {
                d.set(true, forKey: "plusPromptShown")
                plusReason = .tracking
            } else if PlusNudgeRule.claimLimit(model.stats, hasPlus: store.hasPlus) {
                plusReason = .limit
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && plusReason == nil && PlusNudgeRule.claimLimit(model.stats, hasPlus: store.hasPlus) {
                plusReason = .limit
            }
        }
        .onAppear {
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: model.claps) { _, _ in
            bump = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeOut(duration: 0.3)) { bump = false } }
        }
    }

    // MARK: En haut

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Foldly").font(.system(size: 28, weight: .bold)).foregroundStyle(Bento.ink)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.footnote).foregroundStyle(Bento.muted)
            }
            Spacer()
            LeaderboardButton(show: $showBoards).font(.body).frame(width: 40, height: 44)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.body.weight(.medium)).foregroundStyle(Bento.ink)
                    .frame(width: 40, height: 40).background(Circle().fill(Bento.card))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .accessibilityLabel(Text("Settings"))
        }
    }

    // MARK: La grille (colonnes de hauteurs différentes)

    /// Une rangée : deux cartes côte à côte, de même hauteur.
    private func row<A: View, B: View>(_ a: A, _ b: B, _ i: Int, lead: CGFloat = 1) -> some View {
        HStack(alignment: .top, spacing: 12) {
            a.frame(maxWidth: .infinity, maxHeight: .infinity).layoutPriority(lead)
            b.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(Pop(on: appeared, i: i))
    }

    private func one<A: View>(_ a: A, _ i: Int) -> some View {
        a.modifier(Pop(on: appeared, i: i))
    }

    /// L'entrée en ressort, rangée après rangée.
    private struct Pop: ViewModifier {
        let on: Bool
        let i: Int
        func body(content: Content) -> some View {
            content
                .scaleEffect(on ? 1 : 0.92)
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 14)
                .animation(.spring(response: 0.55, dampingFraction: 0.72).delay(Double(i) * 0.07), value: on)
        }
    }

    @ViewBuilder private func grid(wide: Bool) -> some View {
        let showAuto = model.stats.autoLast == nil && !Demo.seeded
        let showPromo = !foldboardPromoHidden && FoldboardPromoRule.shouldShow
        if wide {
            VStack(spacing: 12) {
                row(today, hinge, 0)
                if showAuto { one(autoCard, 1) }
                row(week, VStack(spacing: 12) { split; lifetime }, 2)
                row(closed, VStack(spacing: 12) { hours; garden }, 3)
                one(actions, 4)
                if showPromo { one(promo, 5) }
            }
        } else {
            VStack(spacing: 12) {
                one(today, 0)
                if showAuto { one(autoCard, 1) }
                one(split, 2)
                one(week, 3)
                one(hours, 4)
                row(lifetime, garden, 5)
                one(closed, 6)
                one(actions, 7)
                if showPromo { one(promo, 8) }
            }
        }
    }

    private var promo: some View {
        white {
            FoldboardPromo { openURL(FoldboardPromoRule.url) } onHide: {
                FoldboardPromoRule.hide()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { foldboardPromoHidden = true }
            }
        }
    }

    // MARK: Les cartes

    private func white<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Bento.card))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private func trayCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Bento.tray))
    }

    private func darkCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Bento.dark))
            .environment(\.colorScheme, .dark)
    }

    private func label(_ t: Text) -> some View {
        t.font(.system(size: 13, weight: .medium)).foregroundStyle(Bento.muted)
    }

    /// Aujourd'hui : le grand chiffre, et l'anneau jusqu'au repère (moyenne ou limite).
    private var today: some View {
        let s = model.stats
        return darkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Today").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("+1").font(.footnote.weight(.semibold)).foregroundStyle(Bento.accent)
                        .opacity(bump ? 1 : 0).offset(y: bump ? 0 : 8)
                }
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: max(0.02, min(1, s.progress)))
                            .stroke(AngularGradient(colors: [Bento.accent.opacity(0.6), Bento.accent], center: .center),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: s.progress)
                        Image(systemName: "rectangle.compress.vertical").font(.title3).foregroundStyle(.white)
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(FoldUnit.shown(s.today))")
                            .font(.system(size: 56, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: s.today)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text("folds today").font(.subheadline).foregroundStyle(.white.opacity(0.55))
                    }
                }
                statusText.font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            }
            .contentShape(Rectangle())
            .onTapGesture { if !model.hasHinge { model.clap() } }
            .onLongPressGesture { showAdjust = true }
        }
    }

    private var statusText: Text {
        let s = model.stats
        if s.goalOn {
            let left = s.left()
            if left > 0 { return Text("\(FoldUnit.shown(left)) left today") }
            if left == 0 { return Text("Limit reached") }
            return Text("\(FoldUnit.shown(-left)) over the limit")
        }
        return AverageText.status(today: s.today, average: s.averageRef())
    }

    /// La charnière, en direct : un arc qui suit l'angle du téléphone, et un point qui pulse quand il est ouvert.
    private var hinge: some View {
        let deg = model.degrees ?? 0
        let open = deg > 20
        return white {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label(Text(verbatim: "Hinge"))
                    Spacer()
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let p = (sin(ctx.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                        Circle().fill(open ? Bento.accent : Bento.muted.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Bento.accent.opacity(open ? 0.35 * (1 - p) : 0), lineWidth: 6).scaleEffect(1 + p))
                    }
                    (open ? Text("Open") : Text("Closed")).font(.caption.weight(.semibold)).foregroundStyle(open ? Bento.accent : Bento.muted)
                }
                ZStack(alignment: .bottom) {
                    Circle().trim(from: 0.5, to: 1).stroke(Bento.tray, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    Circle().trim(from: 0.5, to: 0.5 + 0.5 * min(1, deg / 180))
                        .stroke(Bento.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: deg)
                    Text(model.degrees == nil ? "—" : "\(Int(deg))°")
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: Int(deg))
                }
                .frame(height: 92)
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// La semaine : sept barres qui montent en ressort, aujourd'hui en bleu.
    private var week: some View {
        let s = model.stats
        let days = s.lastWeek()
        let top = Double(max(1, days.map(\.closes).max() ?? 1, s.reference() ?? 0))
        return trayCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(.system(size: 15, weight: .semibold)).foregroundStyle(Bento.ink)
                    Spacer()
                    Text("\(s.weekTotal)").font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.muted)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<days.count, id: \.self) { i in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(i == days.count - 1 ? Bento.accent : Bento.card)
                                .frame(height: appeared ? max(6, 92 * CGFloat(Double(days[i].closes) / top)) : 6)
                                .animation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.25 + Double(i) * 0.05), value: appeared)
                            Text(days[i].date, format: .dateTime.weekday(.narrow))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(i == days.count - 1 ? Bento.ink : Bento.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 118, alignment: .bottom)
                Button { showWeek = true } label: {
                    Text("Weekly recap").font(.footnote.weight(.semibold))
                }
            }
        }
    }

    /// Ouvert ou fermé aujourd'hui, en une barre.
    private var split: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let s = model.stats
            let now = ctx.date
            let open = s.openTime(now, now: now), closed = s.closedTime(now, now: now)
            let share = open + closed > 0 ? open / (open + closed) : 0
            white {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            label(Text("Open"))
                            Text(TimeFormat.narrow(open)).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.ink)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            label(Text("Closed"))
                            Text(s.autoLast == nil && closed == 0 ? "—" : TimeFormat.narrow(closed))
                                .font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.ink)
                        }
                    }
                    GeometryReader { g in
                        HStack(spacing: 4) {
                            Capsule().fill(Bento.accent).frame(width: max(8, (g.size.width - 4) * share))
                            Capsule().fill(Bento.tray)
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: share)
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    private var hours: some View {
        white {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label(Text("Today by hour"))
                    Spacer()
                    Button { showHours = true } label: { Image(systemName: "arrow.up.right").font(.caption.weight(.bold)) }
                }
                TodayByHour(stats: model.stats, accent: Bento.accent, empty: Bento.tray, height: 54)
            }
        }
    }

    /// Le total depuis le début, en chiffres qui roulent.
    private var lifetime: some View {
        trayCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    label(Text("Since day one"))
                    Text(model.stats.totalCloses, format: .number)
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.stats.totalCloses)
                }
                Spacer()
                Image(systemName: "infinity").font(.title2.weight(.semibold)).foregroundStyle(Bento.accent)
                    .frame(width: 46, height: 46).background(Circle().fill(Bento.tint))
            }
        }
    }

    private var garden: some View {
        let today = model.stats.plants()
        return white {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    label(Text("My garden"))
                    Text(model.stats.totalPlants, format: .number)
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(Bento.ink)
                        .contentTransition(.numericText())
                    if today > 0 {
                        Text(verbatim: "+\(today)").font(.caption.weight(.semibold)).foregroundStyle(Bento.accent)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "leaf.fill").font(.title2.weight(.semibold)).foregroundStyle(Bento.accent)
                    .frame(width: 46, height: 46).background(Circle().fill(Bento.tint))
            }
        }
    }

    /// Les raccourcis, sur une carte sombre.
    private var actions: some View {
        darkCard {
            HStack(spacing: 10) {
                pill("square.and.arrow.up", Text("Share")) { showShare = true }
                pill("calendar", Text("Monthly recap")) { showMonth = true }
                pill("clock.arrow.circlepath", Text("History")) {
                    if store.hasPlus { showHistory = true } else { plusReason = .history }
                }
            }
        }
    }

    private func pill(_ icon: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.body.weight(.semibold))
                title.font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var autoCard: some View {
        Button { showAuto = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.badge.automatic").font(.title3).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: 12).fill(Bento.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count even when the app is closed").font(.subheadline.weight(.semibold)).foregroundStyle(Bento.ink)
                    Text("Set up the Shortcuts automation in a minute.").font(.caption).foregroundStyle(Bento.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Bento.tint))
        }
        .buttonStyle(.plain)
    }
}
