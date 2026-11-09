import SwiftUI

@main
struct FoldboardApp: App {
    @State private var model = SettingsModel()
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    init() {
        // Captures : « écran~variante » choisit une variante d'affichage plein écran.
        let shot = UserDefaults.standard.string(forKey: "shot") ?? ""
        let parts = shot.split(separator: "~")
        if parts.first == "home" { UserDefaults.standard.set(true, forKey: "onboarded") }
        if parts.count > 1 { UserDefaults.standard.set(String(parts[1]), forKey: "duoVariant") }
        else { UserDefaults.standard.removeObject(forKey: "duoVariant") }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let shot = UserDefaults.standard.string(forKey: "shot") {
                    ShotView(name: shot)
                } else {
                    HomeView()
                }
            }
                .environment(model)
                .environment(store)
                .tint(Color("AccentColor"))
                .fullScreenDuo()
                .onChange(of: phase) { _, p in
                    if p == .active {
                        model.reload()
                        Task { await store.refresh() }
                    }
                }
        }
    }
}

struct HomeView: View {
    @Environment(SettingsModel.self) private var model
    @Environment(Store.self) private var store
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("onboarded") private var onboarded = false
    @State private var showPro = false
    @State private var tryText = ""
    @FocusState private var tryFocus: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Image("Logo")
                                .resizable()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Foldboard").font(.title2.bold())
                                Text("The keyboard made for iPhone Duo").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Text("Outer screen: the keyboard comes out on the side of the hand holding the phone. Inner screen: it splits in two, like Apple's.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                ProStatusRow(showPro: $showPro)

                Section {
                    NavigationLink {
                        SetupView(done: $setupDone).fullScreenDuo()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Foldboard to your keyboards")
                                Text(setupDone ? "Done" : "1 minute, 3 steps").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: setupDone ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                                .foregroundStyle(setupDone ? .green : Color.accentColor)
                        }
                    }
                } header: {
                    Text("Get started")
                }

                Section {
                    TextField("Type here to try Foldboard", text: $tryText, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($tryFocus)
                    if !tryText.isEmpty {
                        Button("Clear", role: .destructive) { tryText = "" }
                    }
                } header: {
                    Text("Try it")
                } footer: {
                    Text("Tap the field, then hold the globe key and pick Foldboard.")
                }

                Section {
                    NavigationLink { PlaceTutorial().fullScreenDuo() } label: {
                        Label("How it works", systemImage: "hand.tap")
                    }
                    NavigationLink { HandTest().fullScreenDuo() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Test: right hand, left hand")
                                Text("3 seconds per hand, nothing to type").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "hand.raised.fingers.spread") }
                    }
                    NavigationLink { GripSetup().fullScreenDuo() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Learn my thumbs")
                                Text("Optional: the keyboard follows your thumb by itself").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "touchid") }
                    }
                    NavigationLink { PositionView().fullScreenDuo() } label: { Label("Position and size", systemImage: "hand.raised.fingers.spread") }
                    NavigationLink { LookView().fullScreenDuo() } label: { Label("Colors and font", systemImage: "paintpalette") }
                    NavigationLink { FeelView().fullScreenDuo() } label: { Label("Sound, vibrations and swipe", systemImage: "waveform") }
                    NavigationLink { PhrasesView().fullScreenDuo() } label: { Label("Phrases and emoji", systemImage: "text.bubble") }
                    NavigationLink { TypingView().fullScreenDuo() } label: { Label("Typing", systemImage: "character.cursor.ibeam") }
                } header: {
                    Text("Make it yours")
                }

                Section {
                    Label("Foldboard never sends what you type anywhere. It has no internet access, no account and no ads.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .fullScreenDuo()
            .navigationTitle("Foldboard")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPro) { ProView().environment(store).fullScreenDuo() }
            .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                OnboardingView { onboarded = true }
                    .environment(store)
                    .environment(model)
                    .fullScreenDuo()
            }
        }
    }
}

/// La ligne qui dit où en est l'essai ou l'achat.
struct ProStatusRow: View {
    @Environment(Store.self) private var store
    @Binding var showPro: Bool

    var body: some View {
        Section {
            Button { showPro = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.access.purchased ? "checkmark.seal.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).foregroundStyle(.primary)
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !store.access.purchased {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var title: LocalizedStringKey {
        if store.access.purchased { return "Foldboard Pro is unlocked" }
        if store.isPro { return "Free trial in progress" }
        if store.access.trialOver() { return "Your free trial is over" }
        return "Try everything free for 3 days"
    }

    private var detail: String {
        if store.access.purchased { return NSLocalizedString("Thank you!", comment: "") }
        if store.isPro, let end = store.access.trialEnd {
            return String(format: NSLocalizedString("Until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened))
        }
        if store.access.trialOver() { return NSLocalizedString("Unlock Foldboard Pro to keep two hands, follow-your-hand, colors and phrases.", comment: "") }
        return NSLocalizedString("Two hands, follow-your-hand, colors, fonts, sounds and your phrases.", comment: "")
    }
}
