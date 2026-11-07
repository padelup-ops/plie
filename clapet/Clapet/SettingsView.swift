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
                if !DuoFolds.paidApp {
                Section {
                    if store.hasPlus {
                        Label { Text("Foldly+ is unlocked. Thank you.") } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(red: 0.43, green: 0.84, blue: 0.65))
                        }
                    } else {
                        Button { showPlus = true } label: {
                            Label { Text("Unlock Foldly+") } icon: { Image(systemName: "sparkles") }
                        }
                    }
                    Button {
                        Task { await store.restore() }
                    } label: {
                        Text("Restore purchases")
                    }
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Foldly+")
                }
                }
                // 1. Mon objectif
                Section {
                    Toggle(isOn: Binding(get: { model.stats.goalOn }, set: { model.setGoalOn($0) })) {
                        Text("Daily limit")
                    }
                    if model.stats.goalOn {
                        // Ta propre limite : tape le chiffre, ou ajuste de 5 en 5.
                        let goal = Binding(get: { model.stats.goal }, set: { model.setGoal(min(2000, max(5, $0))) })
                        Stepper(value: goal, in: 5...2000, step: 5) {
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
                                Text("Limit alerts")
                                if !store.hasPlus { PlusBadge() }
                            }
                        }
                    }
                    Button { showBoards = true } label: {
                        Label { Text("Leaderboards") } icon: { Image(systemName: "trophy.fill").foregroundStyle(.orange) }
                    }
                } header: {
                    Text("My goal")
                } footer: {
                    if alertsDenied {
                        Text("Notifications are off for Foldly. Turn them on in the Settings app.")
                    } else if model.stats.goalOn {
                        Text("Tap the number to type your own limit.")
                    } else {
                        Text("Off: Foldly compares each day with your average.")
                    }
                }

                // 2. Apparence
                Section {
                    Picker(selection: Binding(get: { DFLook.resolved(lookRaw).rawValue },
                                              set: { raw in
                                                  if (DFLook(rawValue: raw)?.needsPlus ?? false) && !store.hasPlus { showPlus = true } else { lookRaw = raw }
                                              })) {
                        ForEach(DFLook.allCases) { look in
                            if look == .custom && !store.hasPlus {
                                Text("My theme (Foldly+)").tag(look.rawValue)
                            } else if look == .aurora && !store.hasPlus {
                                Text("Aurora (Foldly+)").tag(look.rawValue)
                            } else {
                                look.title.tag(look.rawValue)
                            }
                        }
                    } label: {
                        Text("Theme")
                    }
                    if DFLook.resolved(lookRaw) == .custom {
                        CustomThemeEditor()
                    }
                    HStack(spacing: 12) {
                        Text("Widget color")
                        Spacer(minLength: 4)
                        ForEach(ClapetTheme.allCases) { theme in
                            Button {
                                if store.hasPlus { model.setTheme(theme) } else { showPlus = true }
                            } label: {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: model.stats.theme == theme.rawValue ? 2.5 : 0))
                                    .overlay {
                                        if !store.hasPlus && theme != .mint {
                                            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.black.opacity(0.6))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(theme.name))
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    DFLook.resolved(lookRaw).subtitle
                }

                // « Pourquoi tu l'ouvres ? »
                Section {
                    Toggle(isOn: Binding(get: { whyOn && store.hasPlus }, set: { on in
                        guard store.hasPlus else { showPlus = true; return }
                        whyOn = on
                    })) {
                        HStack(spacing: 6) {
                            Text("Ask why I open it")
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
                            Text("Also when Foldly is closed")
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
                        Text("Break reminder")
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
                            Text("Remind me")
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
                            Text("Evening summary (9:30 pm)")
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
                        Text("Weekly and monthly recaps")
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
                            Text("Count on the Lock Screen")
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

                // Aide
                Section {
                    Button { showAuto = true } label: {
                        Label { Text("Count even when the app is closed") } icon: { Image(systemName: "bolt.badge.automatic") }
                    }
                    Button { showTour = true } label: {
                        Label { Text("Guided tour") } icon: { Image(systemName: "map") }
                    }
                    if !store.isTestBuild {
                        Link(destination: ReviewRule.writeReviewURL) {
                            Label { Text("Rate Foldly on the App Store") } icon: { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        }
                    }
                    NavigationLink {
                        advanced
                    } label: {
                        Label { Text("Advanced") } icon: { Image(systemName: "slider.horizontal.3") }
                    }
                } header: {
                    Text("Help")
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
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
