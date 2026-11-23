// ProfileView.swift — Vicefold
//
// Profil (photo, nom), temps de jeu (à la main, ou lu sur ton compte PlayStation avec Pro), réglages, Pro, bienvenue.

import PhotosUI
import StoreKit
import SwiftUI

struct ProfileView: View {
    @Environment(Progress.self) private var progress
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var name = ""
    @State private var psn = PlayStation.shared
    @State private var signIn = false
    @State private var showPro = false
    @State private var photoStamp = 0

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Avatar(size: 72).id(photoStamp)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill").font(.title3).foregroundStyle(.white, VF.coral)
                            }
                    }
                    .accessibilityLabel("Change photo")
                    TextField("Your name", text: $name)
                        .font(.title3.weight(.semibold))
                        .onSubmit { save() }
                }
                .padding(.vertical, 6)
            }

            Section {
                HStack {
                    Text("Play time")
                    Spacer()
                    Text(progress.hours, format: .number.precision(.fractionLength(0...1))).monospacedDigit()
                    Text("h").foregroundStyle(.secondary)
                }
                if progress.data.psnHours == nil {
                    Stepper("Add 1 hour", value: Binding(get: { progress.data.manualHours }, set: { v in progress.edit { $0.manualHours = max(0, v) } }), step: 1)
                }
            } header: {
                Text("Play time")
            } footer: {
                if let d = progress.data.psnUpdated {
                    Text("From PlayStation, updated \(d.formatted(.relative(presentation: .named))).")
                }
            }

            Section {
                if psn.connected {
                    if let t = psn.gtaTitle {
                        LabeledContent(t.name) { Text("\(Int(t.hours)) h") }
                    }
                    if !psn.titles.isEmpty {
                        Picker("Game to follow", selection: Binding(get: { psn.gtaTitle?.titleId ?? "" }, set: { id in
                            if let t = psn.titles.first(where: { $0.titleId == id }) { psn.choose(t) }
                        })) {
                            Text("Choose").tag("")
                            ForEach(psn.titles.sorted { $0.hours > $1.hours }) { t in Text(t.name).tag(t.titleId) }
                        }
                    }
                    Button { Task { await psn.refreshTitles() } } label: { Label("Update now", systemImage: "arrow.clockwise") }
                        .disabled(psn.busy)
                    Button("Disconnect", role: .destructive) { psn.disconnect() }
                } else {
                    Button {
                        if store.isPro { signIn = true } else { showPro = true }
                    } label: {
                        Label(store.isPro ? "Connect PlayStation" : "Connect PlayStation (Pro)", systemImage: "playstation.logo")
                    }
                }
                if psn.busy { ProgressView() }
                if let e = psn.error { Text(e).foregroundStyle(.red).font(.footnote) }
            } header: {
                Text("PlayStation")
            } footer: {
                Text("You sign in on Sony's own page: Vicefold never sees your password. It only reads your games and hours. This uses the access the PlayStation app uses; Sony may change it at any time.")
            }
        }
        .navigationTitle("Profile")
        .scrollContentBackground(.hidden)
        .background(VFBackdrop())
        .onAppear { name = progress.data.name; if psn.connected && psn.titles.isEmpty { Task { await psn.refreshTitles() } } }
        .onDisappear { save() }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    let side = min(img.size.width, img.size.height)
                    let r = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
                    let out = r.jpegData(withCompressionQuality: 0.85) { _ in
                        let scale = 400 / side
                        img.draw(in: CGRect(x: (400 - img.size.width * scale) / 2, y: (400 - img.size.height * scale) / 2,
                                            width: img.size.width * scale, height: img.size.height * scale))
                    }
                    try? out.write(to: progress.photoURL, options: .atomic)
                    photoStamp += 1
                    progress.edit { _ in }
                }
            }
        }
        .sheet(isPresented: $signIn) {
            NavigationStack {
                PSNSignIn { npsso in
                    signIn = false
                    if let npsso { Task { await psn.connect(npsso: npsso) } }
                }
                .navigationTitle("PlayStation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { signIn = false } } }
            }
        }
        .sheet(isPresented: $showPro) { ProView() }
        .toolbar {
            if ShotMode.route == nil {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n != progress.data.name { progress.edit { $0.name = n } }
    }
}

struct SettingsView: View {
    @Environment(Progress.self) private var progress
    @Environment(ContentStore.self) private var content
    @Environment(Store.self) private var store
    @State private var alerts = Alerts.shared
    @State private var icon = UIApplication.shared.alternateIconName
    @State private var confirmReset = false
    @State private var showPro = false

    static let icons: [(String?, LocalizedStringKey)] = [(nil, "Neon pin"), ("IconSunrise", "Sunrise"), ("IconSunset", "Sunset"), ("IconNeon", "Neon"), ("IconPalm", "Palm"),
                                                          ("IconFlamingo", "Flamingo"), ("IconMidnight", "Midnight"), ("IconSwamp", "Swamp"), ("IconChrome", "Chrome")]

    var body: some View {
        @Bindable var alerts = alerts
        Form {
            Section {
                Picker("I'm at", selection: Binding(get: { progress.data.chapter }, set: { v in progress.edit { $0.chapter = v } })) {
                    ForEach(content.chapters) { c in
                        Text(c.id <= progress.data.chapter || progress.data.spoilersShown ? "\(c.id). \(c.title)" : String(localized: "Chapter \(c.id)")).tag(c.id)
                    }
                }
                Toggle("Show all spoilers", isOn: Binding(get: { progress.data.spoilersShown }, set: { v in progress.edit { $0.spoilersShown = v } }))
            } header: {
                Text("Spoilers")
            } footer: {
                Text("Guides, missions, places and characters after your chapter stay hidden. Finishing a mission moves you forward on its own.")
            }

            Section {
                Toggle("New guide alerts", isOn: $alerts.enabled)
                if alerts.denied { Text("Notifications are off for Vicefold in Settings.").font(.footnote).foregroundStyle(.secondary) }
                Button {
                    Task { _ = await content.refresh() }
                } label: {
                    HStack { Text("Check for new guides"); Spacer(); if content.updating { ProgressView() } }
                }
                LabeledContent("Guide version", value: "\(content.content.version)")
            } header: {
                Text("Content")
            } footer: {
                Text("Guides update by themselves, for free, without updating the app. Alerts only read a public file: nothing about you is sent.")
            }

            Section("App icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(Self.icons.enumerated()), id: \.offset) { _, entry in
                            let (name, label) = entry
                            Button {
                                UIApplication.shared.setAlternateIconName(name) { _ in icon = UIApplication.shared.alternateIconName }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(uiImage: UIImage(named: (name ?? "AppIcon") + "Preview") ?? UIImage())
                                        .resizable().frame(width: 58, height: 58).clipShape(.rect(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(icon == name ? VF.coral : .clear, lineWidth: 3).padding(-3))
                                    Text(label).font(.caption2).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                if store.isPro {
                    Label("Pro is on. Thank you!", systemImage: "star.circle.fill").foregroundStyle(VF.coral)
                    Toggle("iCloud sync", isOn: .constant(true)).disabled(true)
                } else {
                    Button { showPro = true } label: { Label("Vicefold Pro", systemImage: "star.circle") }
                }
                Button("Restore purchases") { Task { await store.restore() } }
            } header: {
                Text("Pro")
            }

            Section {
                Button("Reset my progress", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Erase missions, places, pins and notes on this device?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Erase", role: .destructive) {
                            progress.edit { d in
                                let name = d.name, hours = d.manualHours
                                d = VFProgressData()
                                d.name = name; d.manualHours = hours
                            }
                        }
                    }
            }

            Section {
                Text("Vicefold is an unofficial fan guide. It is not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. Grand Theft Auto and related names are trademarks of Take-Two Interactive. The map is the GTADB.org community map (CC BY 4.0); no game art is included.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let s = content.content.sources, !s.isEmpty {
                    ForEach(s, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                Text("No account, no ads, no tracking. Your progress stays on your devices.").font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(VFBackdrop())
        .sheet(isPresented: $showPro) { ProView() }
    }
}

struct ProView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let perks: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("mappin.and.ellipse", "Unlimited pins", "Free: 10 pins, and every place you visit."),
        ("square.3.layers.3d", "Every map layer", "Collectibles, activities and random events."),
        ("photo.on.rectangle", "Your own map", "Import the game's map and keep all your pins on it."),
        ("icloud", "iCloud sync", "Your progress on iPhone, iPad and Duo."),
        ("playstation.logo", "PlayStation play time", "Your hours, read from your account."),
        ("square.grid.2x2", "Progress widgets", "Your ring and next mission on the Home and Lock Screen."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "star.circle.fill").font(.system(size: 64)).foregroundStyle(VF.gradient).padding(.top, 10)
                    Text("Vicefold Pro").font(.largeTitle.bold())
                    Text("Every guide stays free. Pro is for the map and your progress.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.0) { p in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: p.0).font(.title3).foregroundStyle(VF.coral).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) { Text(p.1).font(.headline); Text(p.2).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 22))
                    if store.isPro {
                        Label("Pro is on", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(VF.teal)
                    } else if store.products.isEmpty {
                        ProgressView().task { await store.load() }
                    } else {
                        ForEach(store.products) { p in
                            Button { Task { await store.buy(p) } } label: {
                                VStack(spacing: 2) {
                                    Text(p.displayName).font(.headline)
                                    Text(label(p)).font(.subheadline)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(p.id == Store.lifetime ? VF.coral : VF.magenta)
                            .disabled(store.busy)
                        }
                    }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    HStack(spacing: 18) {
                        Button("Restore") { Task { await store.restore() } }
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.footnote)
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func label(_ p: Product) -> String {
        if let s = p.subscription {
            return s.subscriptionPeriod.unit == .year ? String(localized: "\(p.displayPrice) a year") : String(localized: "\(p.displayPrice) a month")
        }
        return String(localized: "\(p.displayPrice) once")
    }
}

struct OnboardingView: View {
    var done: () -> Void
    @Environment(Progress.self) private var progress
    @Environment(ContentStore.self) private var content
    @State private var name = ""
    @State private var chapter = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sun.horizon.fill").font(.system(size: 56)).foregroundStyle(VF.gradient)
                    Text("Welcome to Vicefold").font(.largeTitle.bold())
                    Text("Your companion for Leonida: guides, a map with your own pins, and every mission on your way to 100%.").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        point("eye.slash", "Spoiler-free", "Nothing past your chapter shows up unless you ask.")
                        point("rectangle.split.2x1", "Made for the Duo", "Open it: the list on one side, the map on the other.")
                        point("lock.shield", "Yours only", "No account, no ads, no tracking.")
                    }
                    TextField("Your name (optional)", text: $name).textFieldStyle(.roundedBorder)
                    if !content.chapters.isEmpty {
                        Picker("Where are you in the story?", selection: $chapter) {
                            Text("Just starting").tag(1)
                            ForEach(content.chapters.dropFirst()) { c in Text(String(localized: "Chapter \(c.id)")).tag(c.id) }
                        }
                    }
                    Button {
                        progress.edit { $0.name = name.trimmingCharacters(in: .whitespaces); $0.chapter = chapter }
                        done()
                    } label: { Text("Let's go").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func point(_ icon: String, _ t: LocalizedStringKey, _ d: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(VF.coral).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline); Text(d).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
