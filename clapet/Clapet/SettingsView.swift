import SwiftUI

struct SettingsView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { model.stats.goal }, set: { model.setGoal($0) }), in: 10...2000, step: 10) {
                        Text("Daily goal: \(model.stats.goal)")
                    }
                } header: {
                    Text("Goal")
                }
                Section {
                    Toggle(isOn: Binding(get: { model.soundOn }, set: { model.setSound($0) })) { Text("Sounds") }
                    Toggle(isOn: Binding(get: { model.hapticsOn }, set: { model.setHaptics($0) })) { Text("Vibrations") }
                } header: {
                    Text("Feel")
                }
                Section {
                    Text("iOS only tells an app about the hinge while that app is on screen. Clapet counts while it's open, on the inner or the outer screen.")
                    Text("In Shortcuts, the “Count a clap” action adds one clap. If your Duo offers an automation when it's folded, plug it in there to count all day long.")
                } header: {
                    Text("How it counts")
                }
                .font(.footnote)
                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("Reset all claps")
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
            .alert(Text("Reset all claps?"), isPresented: $confirmReset) {
                Button(role: .destructive) { model.reset() } label: { Text("Reset") }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text("Your history and records will be erased.")
            }
        }
    }
}
