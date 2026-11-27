// InfoViews.swift — Allô Père Noël
//
// « Découvrir la magie » (comment ça marche, écouter la voix), les réglages, et la confidentialité.

import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            NightScene(moon: true, trees: false)
            Snowfall(count: 40, opacity: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Spacer(); SantaMedallion(size: 120); Spacer() }
                        .padding(.top, 34)
                    Text("How the magic works")
                        .font(.tale(32))
                        .foregroundStyle(Noel.cream)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)

                    VStack(alignment: .leading, spacing: 22) {
                        step(1, "Tell Santa about your child", "First name, age, two qualities. Less than a minute.")
                        step(2, "Choose the story", "From the magic call to the Christmas Eve call.")
                        step(3, "Hand over the iPhone", "It rings like a real call. Your child answers, and Santa talks to them by name.")
                    }
                    .padding(.top, 28)

                    Text("Santa pauses so your child can answer him. Nothing is recorded: the app never uses the microphone.")
                        .font(.ui(15))
                        .foregroundStyle(Noel.cream.opacity(0.75))
                        .padding(.top, 24)

                    Button { model.call.preview() } label: {
                        Label(model.call.previewing ? "Santa is talking…" : "Hear Santa's voice", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(model.call.previewing)
                    .padding(.top, 22)

                    Button {
                        model.sheet = nil
                        model.go(.setup)
                    } label: { Text("✨ Prepare a magic call") }
                        .buttonStyle(MagicButtonStyle())
                        .padding(.top, 26)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 34)
            }
        }
    }

    private func step(_ n: Int, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.tale(20))
                .foregroundStyle(Noel.night)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Noel.goldGradient))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.tale(20)).foregroundStyle(Noel.cream)
                Text(text).font(.ui(15)).foregroundStyle(Noel.cream.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false
    @State private var messageGate = false
    @State private var music = ChristmasMusic.shared

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Button { model.call.preview() } label: {
                        Label(model.call.previewing ? "Santa is talking…" : "Hear Santa's voice", systemImage: "speaker.wave.2.fill")
                    }
                    .disabled(model.call.previewing)
                } header: { Text("Santa's voice") }

                Section {
                    Toggle(isOn: $model.subtitles) { Label("Subtitles during the call", systemImage: "captions.bubble") }
                    Toggle(isOn: $music.enabled) { Label("Christmas music", systemImage: "music.note") }
                }

                Section {
                    if store.owned {
                        Label("Pass unlocked. Thank you! ✨", systemImage: "checkmark.seal.fill").foregroundStyle(Noel.goldLight)
                    } else {
                        Button { model.sheet = .paywall } label: { Label("Unlock the Christmas Pass", systemImage: "sparkles") }
                    }
                    Button { messageGate = true } label: {
                        Label {
                            if store.messagesLoaded { Text("3 extra messages for \(store.messagesPrice)") } else { Text("3 extra messages") }
                        } icon: { Image(systemName: "bubble.left.and.bubble.right.fill") }
                    }
                    Text("Messages left: \(store.credits)")
                    Button { Task { await store.restore() } } label: { Label("Restore purchases", systemImage: "arrow.clockwise") }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Christmas Pass") }

                Section {
                    NavigationLink { DiscoverView() } label: { Label("How the magic works", systemImage: "wand.and.stars") }
                    NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "lock.shield") }
                    Button(role: .destructive) { confirmForget = true } label: {
                        Label("Forget the children's details", systemImage: "trash")
                    }
                } footer: {
                    Text("Allô Père Noël \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea())
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $messageGate) {
                ParentalGate {
                    messageGate = false
                    Task { await store.buyMessages() }
                }
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
            }
            .confirmationDialog(Text("Forget the first names, age, qualities, moment and wish saved on this iPhone?"),
                                isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) {
                    model.profile = ChildProfile()
                    ChildProfile.forget()
                }
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your family's privacy")
                    .font(.tale(30))
                    .foregroundStyle(Noel.cream)
                block("iphone", "Everything stays on this iPhone", "The first names, age, qualities, special moment and wish you enter are only used to build Santa's call. They are saved on this iPhone and never sent anywhere.")
                block("mic.slash.fill", "No microphone, no recording", "Santa pauses so your child can answer, but the app never listens: it doesn't use the microphone.")
                block("camera.fill", "The camera, only if you turn it on", "You can show your child in a corner of the call, like a video call. The picture only appears on the screen: nothing is recorded or sent. With the Christmas Pass, you can ask for a few photos of their reaction: they stay on this iPhone unless you save or share them.")
                block("person.crop.circle.badge.xmark", "No account, no tracking, no ads", "There is no sign-up, no advertising and no analytics. Santa's voice is inside the app: it works without the internet.")
                block("lock.fill", "Purchases", "The full magic is bought through the App Store, protected by a question for grown-ups. We never see your payment details.")
                block("trash.fill", "You're in control", "You can erase the children's details at any time in Settings, or by deleting the app.")
                GatedLink(title: "Full privacy policy", url: NoelLinks.privacy)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Noel.goldLight)
            }
            .padding(24)
        }
        .background(Color(red: 0.05, green: 0.08, blue: 0.15).ignoresSafeArea())
        .navigationTitle(Text("Privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Noel.goldGradient)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.ui(17, .bold)).foregroundStyle(Noel.cream)
                Text(text).font(.ui(15)).foregroundStyle(Noel.cream.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
