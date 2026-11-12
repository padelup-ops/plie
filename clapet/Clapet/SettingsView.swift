import SwiftUI

struct SettingsView: View {
    @AppStorage(OpeningRule.key) private var openingOn = true
    @AppStorage(DeskRule.key) private var deskOn = true
    @AppStorage(GlanceRule.key) private var glanceOn = true
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showPlus = false
    @State private var showIdeas = false
    @State private var showTour = false
    @State private var tourPending: TourTarget?
    @State private var showBoards = false
    @State private var gameCenter = GameCenter.shared
    @State private var leaderboard: String?
    @State private var alertsDenied = false
    @State private var showAuto = false
    @AppStorage(DFLook.key) private var lookRaw = ""
    @State private var liveOn = LiveCounter.isOn
    @State private var eveningOn = EveningSummary.isOn
    @State private var breakOn = BreakReminder.isOn
    @State private var breakMinutes = BreakReminder.minutes
    @State private var weekOn = WeekRecapNotice.isOn
    @State private var notificationsDenied = false
    @State private var liveDenied = false
    @AppStorage(WhyRule.key) private var whyOn = true
    @AppStorage(WhyRule.closedKey) private var whyClosedOn = false

    var body: some View {
        NavigationStack {
            Form {
                if model.stats.founder {
                    Section { FounderBadge() }
                }
                if !DuoFolds.paidApp {
                    Section {
                        PlusHeader(hasPlus: store.hasPlus) { showPlus = true }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        if !store.hasPlus {
                            Button { Task { await store.restore() } } label: {
                                Text("Restore purchases").font(.footnote)
                            }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        }
                        if let message = store.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                // 1. Mon objectif
                Section {
                    Toggle(isOn: Binding(get: { model.stats.goalOn }, set: { model.setGoalOn($0) })) {
                        Label { Text("Daily limit") } icon: { SIcon("target", .red) }
                    }
                    if model.stats.goalOn {
                        // Ta propre limite : tape le chiffre, ou ajuste de 5 en 5.
                        // Affichée dans l'unité choisie (doublée si chaque mouvement compte).
                        let unit = model.stats.eachMove ? 2 : 1
                        let goal = Binding(get: { model.stats.goal * unit }, set: { model.setGoal(min(2000, max(5, $0 / unit))) })
                        Stepper(value: goal, in: (5 * unit)...(2000 * unit), step: 5 * unit) {
                            HStack {
                                Text("Limit a day")
                                Spacer()
                                TextField("Limit a day", value: goal, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.body.monospacedDigit().weight(.semibold))
                                    .frame(width: 64)
                            }
                        }
                        Toggle(isOn: Binding(get: { model.alertsOn && store.hasPlus }, set: { on in
                            guard store.hasPlus else { showPlus = true; return }
                            Task { if !(await model.setAlerts(on)) { alertsDenied = true } }
                        })) {
                            HStack(spacing: 6) {
                                Label { Text("Limit alerts") } icon: { SIcon("bell.badge.fill", .red) }
                                if !store.hasPlus { PlusBadge() }
                            }
                        }
                    }
                    Button { showBoards = true } label: {
                        Label { Text("Leaderboards") } icon: { SIcon("trophy.fill", .orange) }
                    }
                    Picker(selection: Binding(get: { model.stats.eachMove }, set: { model.setEachMove($0) })) {
                        Text("Open + close = 1 fold").tag(false)
                        Text("Each movement counts").tag(true)
                    } label: {
                        Label { Text("How to count") } icon: { SIcon("number", .blue) }
                    }
                } header: {
                    Text("My goal")
                } footer: {
                    if alertsDenied {
                        Text("Notifications are off for Foldly. Turn them on in the Settings app.")
                    } else if model.stats.eachMove {
                        Text("Each movement counts: opening and closing count as 2. Your history follows too.")
                    } else if model.stats.goalOn {
                        Text("Tap the number to type your own limit.")
                    } else {
                        Text("Off: Foldly compares each day with your average.")
                    }
                }

                // 2. Apparence
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            // Les nouveaux d'abord : Bento et Atelier (Foldly+, ou 3 jours d'essai).
                            ForEach([DFLook.bento, .atelier] + DFLook.allCases.filter { !$0.isBento }) { look in
                                ThemeTile(look: look, selected: DFLook.resolved(lookRaw) == look,
                                          locked: !ThemeTrial.canUse(look, hasPlus: store.hasPlus),
                                          isNew: look.isBento) {
                                    if !ThemeTrial.canUse(look, hasPlus: store.hasPlus) { showPlus = true } else {
                                        if look.needsPlus && !store.hasPlus { ThemeTrial.begin() }
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { lookRaw = look.rawValue }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())
                    if DFLook.resolved(lookRaw) == .custom {
                        CustomThemeEditor()
                    }
                    HStack(spacing: 12) {
                        Label { Text("Widget color") } icon: { SIcon("square.grid.2x2.fill", .teal) }
                        Spacer(minLength: 4)
                        ForEach(ClapetTheme.allCases.filter { $0 != .gold || model.stats.founder }) { theme in
                            Button {
                                if store.hasPlus || theme == .gold { model.setTheme(theme) } else { showPlus = true }
                            } label: {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: model.stats.theme == theme.rawValue ? 2.5 : 0))
                                    .overlay {
                                        if !store.hasPlus && theme != .mint && theme != .gold {
                                            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.black.opacity(0.6))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(theme.name))
                        }
                    }
                    Picker(selection: Binding(get: { model.stats.widgetLook }, set: { model.setWidgetLook($0) })) {
                        Text("Like the iPhone").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    } label: {
                        Label { Text("Widget style") } icon: { SIcon("circle.lefthalf.filled", .gray) }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        DFLook.resolved(lookRaw).subtitle
                        if DFLook.resolved(lookRaw).isBento && !store.hasPlus, let end = ThemeTrial.end {
                            Text(String(format: NSLocalizedString("Free trial until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened)))
                        }
                    }
                }

                // « Pourquoi tu l'ouvres ? »
                Section {
                    Toggle(isOn: Binding(get: { whyOn && store.hasPlus }, set: { on in
                        guard store.hasPlus else { showPlus = true; return }
                        whyOn = on
                    })) {
                        HStack(spacing: 6) {
                            Label { Text("Ask why I open it") } icon: { SIcon("questionmark.bubble.fill", .purple) }
                            if !store.hasPlus { PlusBadge() }
                        }
                    }
                    if whyOn && store.hasPlus {
                        Toggle(isOn: Binding(get: { whyClosedOn }, set: { on in
                            Task {
                                let ok = on ? await LimitAlerts.requestPermission() : true
                                whyClosedOn = ok && on
                                notificationsDenied = on && !ok
                            }
                        })) {
                            Label { Text("Also when Foldly is closed") } icon: { SIcon("app.badge.fill", .purple) }
                        }
                    }
                } header: {
                    Text("Why you open it")
                } footer: {
                    Text("When you unfold your Duo, one tap: a notification, boredom, work or someone. Your answers stay on your iPhone. When Foldly is closed, the question comes as a notification.")
                }

                // 3. Notifications
                Section {
                    Toggle(isOn: Binding(get: { breakOn }, set: { on in
                        Task {
                            let ok = on ? await LimitAlerts.requestPermission() : true
                            BreakReminder.setOn(ok && on, stats: model.stats)
                            breakOn = ok && on
                            notificationsDenied = on && !ok
                        }
                    })) {
                        Label { Text("Break reminder") } icon: { SIcon("cup.and.saucer.fill", .brown) }
                    }
                    if breakOn {
                        Picker(selection: Binding(get: { breakMinutes }, set: { m in
                            breakMinutes = m
                            BreakReminder.setMinutes(m, stats: model.stats)
                        })) {
                            ForEach(BreakReminder.choices, id: \.self) { m in
                                Text("After \(m) min open").tag(m)
                            }
                        } label: {
                            Label { Text("Remind me") } icon: { SIcon("timer", .brown) }
                        }
                    }
                    Toggle(isOn: Binding(get: { eveningOn && store.hasPlus }, set: { on in
                        guard store.hasPlus else { showPlus = true; return }
                        Task {
                            let ok = await EveningSummary.setOn(on, stats: model.stats)
                            eveningOn = ok && on
                            notificationsDenied = on && !ok
                        }
                    })) {
                        HStack(spacing: 6) {
                            Label { Text("Evening summary (9:30 pm)") } icon: { SIcon("moon.fill", .indigo) }
                            if !store.hasPlus { PlusBadge() }
                        }
                    }
                    Toggle(isOn: Binding(get: { weekOn }, set: { on in
                        Task {
                            let ok = await WeekRecapNotice.setOn(on)
                            weekOn = ok && on
                            if weekOn { MonthRecapNotice.schedule() } else { MonthRecapNotice.cancel() }
                            notificationsDenied = on && !ok
                        }
                    })) {
                        Label { Text("Weekly and monthly recaps") } icon: { SIcon("calendar", .pink) }
                    }
                    Toggle(isOn: Binding(get: { liveOn && store.hasPlus }, set: { on in
                        guard store.hasPlus else { showPlus = true; return }
                        if on {
                            liveOn = LiveCounter.start(model.stats)
                            liveDenied = !liveOn
                        } else {
                            LiveCounter.stop()
                            liveOn = false
                        }
                    })) {
                        HStack(spacing: 6) {
                            Label { Text("Count on the Lock Screen") } icon: { SIcon("lock.fill", .gray) }
                            if !store.hasPlus { PlusBadge() }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if notificationsDenied {
                        Text("Notifications are off for Foldly. Turn them on in the Settings app.")
                    } else if liveDenied {
                        Text("Live Activities are off for Foldly. Turn them on in the Settings app.")
                    }
                }

                // Heures de repos
                Section {
                    Toggle(isOn: Binding(get: { model.stats.nightOn }, set: { model.setNight(on: $0) })) {
                        Label { Text("Rest hours") } icon: { SIcon("bed.double.fill", .indigo) }
                    }
                    if model.stats.nightOn {
                        Picker(selection: Binding(get: { model.stats.nightFrom }, set: { model.setNight(from: $0) })) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        } label: { Label { Text("Rest from") } icon: { SIcon("moon.zzz.fill", .indigo) } }
                        Picker(selection: Binding(get: { model.stats.nightTo }, set: { model.setNight(to: $0) })) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        } label: { Label { Text("Rest until") } icon: { SIcon("sunrise.fill", .orange) } }
                    }
                } header: {
                    Text("Time at rest")
                } footer: {
                    Text("Time your Duo stays open during these hours counts as rest, not as use. Open all night? The whole night counts, up to 3 hours before and after.")
                }

                // Aide
                Section {
                    Button { showAuto = true } label: {
                        Label { Text("Count even when the app is closed") } icon: { SIcon("bolt.fill", .green) }
                    }
                    Button { showTour = true } label: {
                        Label { Text("Guided tour") } icon: { SIcon("map.fill", .blue) }
                    }
                    Button { showIdeas = true } label: {
                        Label { Text("Ideas and votes") } icon: { SIcon("bubble.left.and.text.bubble.right.fill", .purple) }
                    }
                    if !store.isTestBuild {
                        Link(destination: ReviewRule.writeReviewURL) {
                            Label { Text("Rate Foldly on the App Store") } icon: { SIcon("star.fill", .yellow) }
                        }
                    }
                    NavigationLink {
                        advanced
                    } label: {
                        Label { Text("Advanced") } icon: { SIcon("gearshape.2.fill", .gray) }
                    }
                } header: {
                    Text("Help")
                }

                // Notre autre app pour le Duo
                Section {
                    Link(destination: URL(string: "https://apps.apple.com/app/id6825605393")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "Origamo")
                                Text("Mini games you play by folding your Duo").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { SIcon("gamecontroller.fill", .pink) }
                    }
                    Link(destination: FoldboardPromoRule.appURL) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "Foldboard")
                                Text("The keyboard that comes under your thumb").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { SIcon("keyboard.fill", .blue) }
                    }
                } header: {
                    Text("Also for your Duo")
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .sheet(isPresented: $showAuto) {
                AutoCountView().environment(model)
            }
            .sheet(item: Binding(get: { leaderboard.map(LeaderboardID.init) }, set: { leaderboard = $0?.id })) { item in
                LeaderboardScreen(leaderboardID: item.id).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showTour, onDismiss: {
                switch tourPending {
                case .autoCount: showAuto = true
                case .leaderboards: showBoards = true
                default: break
                }
                tourPending = nil
            }) { FeatureTour { tourPending = $0 } }
            .sheet(isPresented: $showBoards) { LeaderboardView().environment(model).environment(store) }
            .sheet(isPresented: $showIdeas) { IdeasView().environment(model) }
            .sheet(isPresented: $showPlus) {
                PlusView().environment(model).environment(store)
            }
        }
    }

    /// Les réglages rarement utiles, à part pour garder la page principale simple.
    private var advanced: some View {
        Form {
            Section {
                Toggle(isOn: $deskOn) { Text("Desk mode") }
                Toggle(isOn: $glanceOn) { Text("Just the essentials on the outer screen") }
                Toggle(isOn: $openingOn) { Text("Opening animation") }
                Toggle(isOn: Binding(get: { model.soundOn }, set: { model.setSound($0) })) { Text("Sounds") }
                Toggle(isOn: Binding(get: { model.hapticsOn }, set: { model.setHaptics($0) })) { Text("Vibrations") }
            } footer: {
                Text("Desk mode: open your iPhone Duo halfway. Held like a book, today's count is on the left page and the details on the right. Set on the table, the count stands on top.")
            }
            if store.isTestBuild && !DuoFolds.paidApp {
                Section {
                    Toggle(isOn: Binding(get: { store.simulatePlus }, set: { store.setSimulatePlus($0) })) {
                        Text("Simulate Foldly+")
                    }
                } header: {
                    Text("Test version")
                } footer: {
                    Text("Only in TestFlight. In TestFlight, the purchase is free too (Apple's test mode).")
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Text("Reset all folds")
                }
            }
        }
        .navigationTitle(Text("Advanced"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text("Reset all folds?"), isPresented: $confirmReset) {
            Button(role: .destructive) { model.reset() } label: { Text("Reset") }
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("Your history and records will be erased.")
        }
    }
}

private struct LeaderboardID: Identifiable { let id: String }

/// L'icône d'une ligne, comme dans les Réglages de l'iPhone : un symbole blanc sur un carré de couleur.
struct SIcon: View {
    let name: String
    let color: Color
    init(_ name: String, _ color: Color) { self.name = name; self.color = color }
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
    }
}

/// En haut des réglages : Foldly+ en une carte.
private struct PlusHeader: View {
    let hasPlus: Bool
    let onUnlock: () -> Void
    var body: some View {
        Button(action: { if !hasPlus { onUnlock() } }) {
            HStack(spacing: 14) {
                Image(systemName: hasPlus ? "checkmark.seal.fill" : "lock.open.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.dfOnAccent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.dfOnAccent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Foldly+").font(.title3.weight(.bold))
                    if hasPlus { Text("Foldly+ is unlocked. Thank you.").font(.subheadline).opacity(0.85) }
                    else { Text("Unlock Foldly+").font(.subheadline.weight(.medium)).opacity(0.9) }
                }
                .foregroundStyle(Color.dfOnAccent)
                Spacer(minLength: 0)
                if !hasPlus { Image(systemName: "chevron.right").font(.body.weight(.bold)).foregroundStyle(Color.dfOnAccent.opacity(0.8)) }
            }
            .padding(18)
            .background(Color.dfAccent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Un thème à toucher : un petit aperçu plutôt qu'un menu.
private struct ThemeTile: View {
    let look: DFLook
    let selected: Bool
    let locked: Bool
    var isNew = false
    let action: () -> Void

    private var colors: (bg: Color, card: Color, accent: Color) {
        switch look {
        case .classic: return (Color(white: 0.96), .white, Color(red: 0.43, green: 0.84, blue: 0.65))
        case .night: return (Color(white: 0.05), Color(white: 0.15), Color(red: 0.43, green: 0.84, blue: 0.65))
        case .minimal: return (.white, Color(white: 0.93), .black)
        case .aurora: return (Color(red: 0.05, green: 0.04, blue: 0.16), Color(red: 0.16, green: 0.1, blue: 0.32), Color(red: 0.55, green: 0.5, blue: 1.0))
        case .custom: return (Color(red: 1.0, green: 0.93, blue: 0.85), .white, Color(red: 1.0, green: 0.45, blue: 0.3))
        case .bento: return (Color(red: 0.97, green: 0.97, blue: 0.96), .white, Color(red: 0.18, green: 0.36, blue: 1.0))
        case .atelier: return (Color(red: 0.96, green: 0.953, blue: 0.937), .white, Color(red: 0.18, green: 0.545, blue: 0.416))
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colors.bg)
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 5) {
                                Circle().trim(from: 0, to: 0.7).stroke(colors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4).fill(colors.card)
                                    RoundedRectangle(cornerRadius: 4).fill(colors.card)
                                }
                                .frame(height: 16)
                            }
                            .padding(8)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    if isNew && !locked {
                        Text("New").font(.system(size: 9, weight: .heavy)).textCase(.uppercase).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(colors.accent)).padding(5)
                    }
                    if locked {
                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.55))).padding(5)
                    }
                }
                .frame(width: 74, height: 92)
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-3))
                .scaleEffect(selected ? 1.0 : 0.96)
                look.title.font(.caption.weight(selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 80)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
