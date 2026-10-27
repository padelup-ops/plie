import SwiftUI

/// Comptage automatique : la mise en place de l'automatisation Raccourcis, pas à pas.
struct AutoCountView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.dfAccent)
                        Text("Count every fold, even when Duo Folds isn't on screen.")
                            .font(.title3.weight(.semibold))
                        Text("Your Duo can run a Shortcuts automation each time it's closed. Plug Duo Folds into it: it takes a minute, and it counts all day long.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    ShortcutTutorialView()
                        .padding(.vertical, 8)
                } header: {
                    Text("Video guide")
                }

                Section {
                    step(1, Text("Open the **Shortcuts** app, **Automation** tab, then tap **+**."))
                    step(2, Text("Choose the trigger **When iPhone is Opened or Closed**, tap the blue words and keep **Closed** only."))
                    step(3, Text("Select **Run Immediately** and turn **Notify When Run** off."))
                    step(4, Text("Tap **Next**, then add the action **Count a fold** (Duo Folds)."))
                    step(5, Text("Tap the action, open it with the little arrow and turn **Show When Run** off: nothing will show up, it counts silently."))
                    step(6, Text("Back in the list, check that the automation is **turned on**. iOS sometimes adds it switched off."))
                    step(7, Text("Do it again with **Opened** and the action **Count an opening**: Duo Folds then also measures how long your Duo stays open."))
                } header: {
                    Text("Set up")
                }

                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        Label { Text("Open Shortcuts") } icon: { Image(systemName: "arrow.up.forward.app") }
                    }
                }

                Section {
                    if let last = model.stats.autoLast {
                        Label {
                            Text("Working. Last automatic count \(last, format: .relative(presentation: .named)).")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dfAccent)
                        }
                    } else {
                        Label {
                            Text("Nothing yet. Once it's set up, close your Duo once: this line turns green.")
                        } icon: {
                            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Check")
                }

                Section {
                    faq(Text("Something shows up each time I open my Duo."),
                        Text("In Shortcuts, open the automation, tap the action and turn **Show When Run** off. Also check that **Notify When Run** is off and **Run Immediately** is selected. Do it for both automations."))
                    faq(Text("Why keep only “Closed”?"),
                        Text("With “Opened or Closed”, every opening would also count as a fold. Use two automations: **Closed** with Count a fold, **Opened** with Count an opening."))
                    faq(Text("Is a fold counted twice when the app is open?"),
                        Text("No. When Duo Folds is on screen and the automation runs too, the fold is counted only once."))
                    faq(Text("The widget isn't up to date."),
                        Text("iOS decides when widgets refresh, usually within a few minutes. Opening Duo Folds updates them right away."))
                    faq(Text("Does it open the app or drain the battery?"),
                        Text("No. The action runs in the background in a fraction of a second, without opening Duo Folds, even after a restart."))
                    faq(Text("It doesn't count anymore."),
                        Text("Check in Shortcuts that both automations are still turned on. If “Working” above isn't recent, close your Duo once and come back here."))
                } header: {
                    Text("Questions")
                }
            }
            .navigationTitle(Text("Automatic counting"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
        .tint(.dfAccent)
    }

    private func faq(_ question: Text, _ answer: Text) -> some View {
        DisclosureGroup {
            answer
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            question.font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
    }

    private func step(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.dfAccent))
            text
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
