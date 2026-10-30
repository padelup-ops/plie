import SwiftUI

struct SettingsView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showPlus = false
    @State private var alertsDenied = false
    @State private var showAuto = false
    @AppStorage(DFLook.key) private var lookRaw = ""
    @State private var liveOn = LiveCounter.isOn
    @State private var eveningOn = EveningSummary.isOn
    @State private var weekOn = WeekRecapNotice.isOn
    @State private var notificationsDenied = false
    @State private var deskAuto = DeskRule.autoOn
    @State private var liveDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if !DuoFolds.paidApp {
                Section {
                    if store.hasPlus {
                        Label { Text("Foldly+ is unlocked. Thank you!") } icon: {
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
                Section {
                    Picker(selection: Binding(get: { DFLook(rawValue: lookRaw)?.rawValue ?? DFLook.classic.rawValue },
                                              set: { lookRaw = $0 })) {
                        ForEach(DFLook.allCases) { look in
                            look.title.tag(look.rawValue)
                        }
                    } label: {
                        Text("Theme")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Theme")
                } footer: {
                    (DFLook(rawValue: lookRaw) ?? .classic).subtitle
                }
                Section {
                    HStack(spacing: 12) {
                        ForEach(ClapetTheme.allCases) { theme in
                            Button {
                                if store.hasPlus { model.setTheme(theme) } else { showPlus = true }
                            } label: {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: model.stats.theme == theme.rawValue ? 3 : 0))
                                    .overlay {
                                        if !store.hasPlus && theme != .mint {
                                            Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.6))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(theme.name))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Widget color")
                }
                Section {
                    Toggle(isOn: Binding(get: { model.stats.goalOn }, set: { model.setGoalOn($0) })) {
                        Text("Daily limit")
                    }
                    if model.stats.goalOn {
                        Stepper(value: Binding(get: { model.stats.goal }, set: { model.setGoal($0) }), in: 10...2000, step: 10) {
                            Text("Limit: \(model.stats.goal) a day")
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
                } header: {
                    Text("Daily limit")
                } footer: {
                    if !model.stats.goalOn {
                        Text("Off: Foldly compares each day with your average. Turn it on to set a limit of your own.")
                    } else if alertsDenied {
                        Text("Notifications are off for Foldly. Turn them on in the Settings app.")
                    } else {
                        Text("A notification at 80 % and at 100 % of your limit.")
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { weekOn }, set: { on in
                        Task {
                            let ok = await WeekRecapNotice.setOn(on)
                            weekOn = ok && on
                            notificationsDenied = on && !ok
                        }
                    })) {
                        Text("Weekly recap")
                    }
                    Toggle(isOn: Binding(get: { eveningOn }, set: { on in
                        Task {
                            let ok = await EveningSummary.setOn(on, stats: model.stats)
                            eveningOn = ok && on
                            notificationsDenied = on && !ok
                        }
                    })) {
                        Text("Evening summary (9:30 pm)")
                    }
                } header: {
                    Text("Summaries")
                } footer: {
                    if notificationsDenied {
                        Text("Notifications are off for Foldly. Turn them on in the Settings app.")
                    } else {
                        Text("The weekly recap arrives on the last day of the week at 7 pm. The evening summary gives your folds and your time open and closed.")
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { deskAuto }, set: { on in
                        DeskRule.autoOn = on
                        deskAuto = on
                    })) {
                        Text("Open when stood in an L")
                    }
                } header: {
                    Text("Desk mode")
                } footer: {
                    Text("Stand your phone folded in an L with Foldly on screen: the top half shows the time and your numbers, big, and the screen stays on.")
                }
                Section {
                    Toggle(isOn: Binding(get: { liveOn }, set: { on in
                        if on {
                            liveOn = LiveCounter.start(model.stats)
                            liveDenied = !liveOn
                        } else {
                            LiveCounter.stop()
                            liveOn = false
                        }
                    })) {
                        Text("Live counter")
                    }
                } header: {
                    Text("Lock Screen")
                } footer: {
                    if liveDenied {
                        Text("Live Activities are off for Foldly. Turn them on in the Settings app.")
                    } else {
                        Text("Your count on the Lock Screen and the outer display, updated at every fold.")
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { model.soundOn }, set: { model.setSound($0) })) { Text("Sounds") }
                    Toggle(isOn: Binding(get: { model.hapticsOn }, set: { model.setHaptics($0) })) { Text("Vibrations") }
                } header: {
                    Text("Feel")
                }
                Section {
                    Text("On screen, Foldly reads the hinge itself. When it's not on screen, iOS doesn't tell it anything: the Shortcuts automation “When iPhone is Closed” with the action “Count a fold” takes over.")
                    Button { showAuto = true } label: {
                        Label { Text("Set up automatic counting") } icon: { Image(systemName: "bolt.badge.automatic") }
                    }
                } header: {
                    Text("How it counts")
                }
                .font(.footnote)
                if store.isTestBuild && !DuoFolds.paidApp {
                    Section {
                        Label { Text("Tester: Foldly+ is free for you.") } icon: { Image(systemName: "gift.fill") }
                        Toggle(isOn: Binding(get: { store.seeAsNewUser }, set: { store.setSeeAsNewUser($0) })) {
                            Text("See the app as a new user")
                        }
                    } header: {
                        Text("Test version")
                    } footer: {
                        Text("Only in TestFlight. Turn it on to see the locks and the Foldly+ screen, like someone who just installed the app. A test purchase is free.")
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
            .sheet(isPresented: $showPlus) {
                PlusView().environment(model).environment(store)
            }
            .alert(Text("Reset all folds?"), isPresented: $confirmReset) {
                Button(role: .destructive) { model.reset() } label: { Text("Reset") }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text("Your history and records will be erased.")
            }
        }
    }
}
