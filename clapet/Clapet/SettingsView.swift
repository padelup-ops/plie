import SwiftUI

struct SettingsView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(ClapetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showPlus = false
    @State private var alertsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.hasPlus {
                        Label { Text("Duo Folds+ is unlocked. Thank you!") } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(red: 0.43, green: 0.84, blue: 0.65))
                        }
                    } else {
                        Button { showPlus = true } label: {
                            Label { Text("Unlock Duo Folds+") } icon: { Image(systemName: "sparkles") }
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
                    Text("Duo Folds+")
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
                                    .overlay(Circle().stroke(Color.white, lineWidth: model.stats.theme == theme.rawValue ? 3 : 0))
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
                    Stepper(value: Binding(get: { model.stats.goal }, set: { model.setGoal($0) }), in: 10...2000, step: 10) {
                        Text("Daily limit: \(model.stats.goal)")
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
                } header: {
                    Text("Daily limit")
                } footer: {
                    if alertsDenied {
                        Text("Notifications are off for Duo Folds. Turn them on in the Settings app.")
                    } else {
                        Text("A notification at 80 % and at 100 % of your limit.")
                    }
                }
                Section {
                    Toggle(isOn: Binding(get: { model.soundOn }, set: { model.setSound($0) })) { Text("Sounds") }
                    Toggle(isOn: Binding(get: { model.hapticsOn }, set: { model.setHaptics($0) })) { Text("Vibrations") }
                } header: {
                    Text("Feel")
                }
                Section {
                    Text("iOS only tells an app about the hinge while that app is on screen. Duo Folds counts while it's open, on the inner or the outer screen.")
                    Text("In Shortcuts, the “Count a fold” action adds one fold. If your Duo offers an automation when it's folded, plug it in there to count all day long.")
                } header: {
                    Text("How it counts")
                }
                .font(.footnote)
                if store.isTestBuild {
                    Section {
                        Toggle(isOn: Binding(get: { store.simulatePlus }, set: { store.setSimulatePlus($0) })) {
                            Text("Simulate Duo Folds+")
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
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
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
