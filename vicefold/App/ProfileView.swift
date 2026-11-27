// ProfileView.swift — Vicefold
//
// Profil (photo, nom), temps de jeu (à la main, ou lu sur ton compte PlayStation avec Pro), réglages, et l'écran Pro.
// La présentation de la première ouverture est dans Onboarding.swift.

import PhotosUI
import StoreKit
import SwiftUI

struct ProfileView: View {
    @Environment(Progress.self) private var progress
    @Environment(ContentStore.self) private var content
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Ouvert en feuille (depuis l'accueil) : un bouton « OK » pour fermer.
    var closable = false
    @State private var item: PhotosPickerItem?
    @State private var name = ""
    @State private var psn = PlayStation.shared
    @State private var signIn = false
    @State private var showPro = false
    @State private var showShare = false
    @State private var photoStamp = 0

    var body: some View {
        Form {
            Group {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $item, matching: .images) {
                            Avatar(size: 72).id(photoStamp)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.circle.fill").font(.title3).foregroundStyle(VF.ink, VF.cyan)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change photo")
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Your name", text: $name)
                                .font(VF.display(26, relativeTo: .title2))
                                .foregroundStyle(VF.text)
                                .submitLabel(.done)
                                .onSubmit { save() }
                            HStack(spacing: 6) {
                                Text(progress.parts(content.content).total, format: .percent.precision(.fractionLength(0)))
                                    .font(VF.mono(12, weight: .bold)).foregroundStyle(VF.flamingo)
                                Text("of Leonida done").font(VF.mono(11)).foregroundStyle(VF.textDim).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Button { showShare = true } label: { Label("Share my progress", systemImage: "square.and.arrow.up") }
                }

                Section {
                    HStack {
                        Text("Play time")
                        Spacer()
                        Text(progress.hours, format: .number.precision(.fractionLength(0...1))).font(VF.display(24, relativeTo: .title3)).monospacedDigit().foregroundStyle(VF.gradient)
                        Text(verbatim: "h").foregroundStyle(VF.textDim)
                    }
                    .accessibilityElement(children: .combine)
                    if progress.data.psnHours == nil {
                        Stepper("Add 1 hour", value: Binding(get: { progress.data.manualHours }, set: { v in progress.edit { $0.manualHours = max(0, v) } }), in: 0...99_999, step: 1)
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
                    if psn.busy { ProgressView().tint(VF.flamingo) }
                    if let e = psn.error { Text(e).foregroundStyle(VF.sun).font(.footnote) }
                } header: {
                    Text("PlayStation")
                } footer: {
                    Text("You sign in on Sony's own page: Vicefold never sees your password. It only reads your games and hours. This uses the access the PlayStation app uses; Sony may change it at any time.")
                }
            }
            .vfRows()
        }
        .navigationTitle("Profile")
        .vfScreen()
        .onAppear { name = progress.data.name; if psn.connected && psn.titles.isEmpty { Task { await psn.refreshTitles() } } }
        .onDisappear { save() }
        .onChange(of: item) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    let side = min(img.size.width, img.size.height)
                    let r = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
                    let out = r.jpegData(withCompressionQuality: 0.85) { _ in
                        let scale = 400 / max(1, side)
                        img.draw(in: CGRect(x: (400 - img.size.width * scale) / 2, y: (400 - img.size.height * scale) / 2,
                                            width: img.size.width * scale, height: img.size.height * scale))
                    }
                    try? out.write(to: progress.photoURL, options: .atomic)
                    photoStamp += 1
                    progress.edit { _ in }
                }
                item = nil
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
        .sheet(isPresented: $showShare) { ShareProgressView() }
        .toolbar {
            // « OK » seulement quand le profil est ouvert en feuille (depuis l'accueil), pas dans « Plus » où la
            // flèche de retour suffit.
            if closable {
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
    @State private var checked: Bool?

    static let icons: [(String?, LocalizedStringKey)] = [(nil, "Neon pin"), ("IconSunrise", "Sunrise"), ("IconSunset", "Sunset"), ("IconNeon", "Neon"), ("IconPalm", "Palm"),
                                                          ("IconFlamingo", "Flamingo"), ("IconMidnight", "Midnight"), ("IconSwamp", "Swamp"), ("IconChrome", "Chrome")]

    var body: some View {
        @Bindable var alerts = alerts
        Form {
            Group {
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
                    if alerts.denied && alerts.enabled { Text("Notifications are off for Vicefold in Settings.").font(.footnote).foregroundStyle(VF.sun) }
                    Button {
                        Task { checked = await content.refresh() }
                    } label: {
                        HStack {
                            Text("Check for new guides")
                            Spacer()
                            if content.updating {
                                ProgressView().tint(VF.flamingo)
                            } else if let checked {
                                // Le bouton répond : à jour, ou nouveau contenu reçu.
                                Label(checked ? "Updated" : "Up to date", systemImage: checked ? "sparkles" : "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(VF.palm)
                            }
                        }
                    }
                    .disabled(content.updating)
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
                                    UIApplication.shared.setAlternateIconName(name) { _ in Task { @MainActor in icon = UIApplication.shared.alternateIconName } }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(uiImage: UIImage(named: (name ?? "AppIcon") + "Preview") ?? UIImage())
                                            .resizable().frame(width: 58, height: 58).clipShape(.rect(cornerRadius: 13, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(icon == name ? VF.flamingo : Color.clear, lineWidth: 3).padding(-3))
                                            .shadow(color: icon == name ? VF.flamingo.opacity(0.7) : .clear, radius: 8)
                                        Text(label).font(.caption2).foregroundStyle(icon == name ? VF.text : VF.textDim)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(icon == name ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }

                Section {
                    if store.isPro {
                        Label("Pro is on. Thank you!", systemImage: "star.circle.fill").foregroundStyle(VF.sunset)
                        LabeledContent {
                            if let d = progress.lastCloudSync {
                                Text(d, style: .relative)
                            }
                        } label: {
                            Label("iCloud sync", systemImage: "icloud")
                        }
                        Text("Your progress on iPhone, iPad and Duo.").font(.footnote).foregroundStyle(VF.textDim)
                        NavigationLink { WidgetGallery() } label: { Label("Progress widgets", systemImage: "square.grid.2x2") }
                    } else {
                        Button { showPro = true } label: { Label("Vicefold Pro", systemImage: "star.circle") }
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                        .disabled(store.busy)
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(VF.textDim) }
                } header: {
                    Text("Pro")
                }

                Section {
                    Button { AppRouter.shared.showIntro = true } label: { Label("Replay the introduction", systemImage: "play.circle") }
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
                        .font(.footnote).foregroundStyle(VF.textDim)
                    if let s = content.content.sources, !s.isEmpty {
                        ForEach(s, id: \.self) { Text($0).font(.caption).foregroundStyle(VF.textDim) }
                    }
                    Text("No account, no ads, no tracking. Your progress stays on your devices.").font(.footnote).foregroundStyle(VF.textDim)
                } header: {
                    Text("About")
                }
            }
            .vfRows()
        }
        .navigationTitle("Settings")
        .vfScreen()
        .sheet(isPresented: $showPro) { ProView() }
        .onDisappear { store.message = nil }
    }
}

/// L'emblème de Pro : une étoile de coucher de soleil dans des anneaux qui respirent.
struct ProEmblem: View {
    var size: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(VF.flamingo.opacity(0.38 - Double(i) * 0.11), lineWidth: 1)
                    .frame(width: size * (0.70 + CGFloat(i) * 0.15), height: size * (0.70 + CGFloat(i) * 0.15))
                    .scaleEffect(breathe ? 1.04 : 0.97)
            }
            Image(systemName: "star.circle.fill")
                .font(.system(size: size * 0.52))
                .foregroundStyle(VF.blaze)
                .shadow(color: VF.sunset.opacity(0.8), radius: size * 0.09)
                .shadow(color: VF.flamingo.opacity(0.5), radius: size * 0.22)
                .scaleEffect(breathe ? 1.03 : 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, ShotMode.route == nil else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

struct ProView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let perks: [(String, LocalizedStringKey, LocalizedStringKey, Color)] = [
        ("mappin.and.ellipse", "Unlimited pins", "Free: 10 pins, and every place you visit.", VF.flamingo),
        ("square.3.layers.3d", "Every map layer", "Collectibles, activities and random events.", VF.cyan),
        ("photo.on.rectangle", "Your own map", "Import the game's map and keep all your pins on it.", VF.sun),
        ("icloud", "iCloud sync", "Your progress on iPhone, iPad and Duo.", VF.sky),
        ("playstation.logo", "PlayStation play time", "Your hours, read from your account.", VF.palm),
        ("square.grid.2x2", "Progress widgets", "Your ring and next mission on the Home and Lock Screen.", VF.sunset),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProEmblem(size: 150)
                    VStack(spacing: 8) {
                        Text("Vicefold Pro").font(VF.display(44)).foregroundStyle(VF.gradient)
                            .shadow(color: VF.flamingo.opacity(0.55), radius: 14)
                            .accessibilityAddTraits(.isHeader)
                        Text("Every guide stays free. Pro is for the map and your progress.")
                            .font(.subheadline).foregroundStyle(VF.textDim).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.0) { p in
                            HStack(alignment: .top, spacing: 14) {
                                VFIconBadge(icon: p.0, color: p.3, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.1).font(.headline).foregroundStyle(VF.text)
                                    Text(p.2).font(.subheadline).foregroundStyle(VF.textDim).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .vfCard(radius: 24, padding: 18)
                    offers
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(VF.sun).multilineTextAlignment(.center) }
                    HStack(spacing: 18) {
                        Button("Restore") { Task { await store.restore() } }.disabled(store.busy)
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy", destination: URL(string: ContentStore.lang == "fr" ? "https://foldly.netlify.app/vicefold/fr/privacy.html" : "https://foldly.netlify.app/vicefold/en/privacy.html")!)
                    }
                    .font(.footnote.weight(.semibold))
                    .tint(VF.cyan)
                }
                .padding()
                .padding(.bottom, 12)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(VFBackdrop(vivid: true))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onDisappear { store.message = nil }
        }
    }

    @ViewBuilder private var offers: some View {
        if ShotMode.route == "pro" {
            // Capture pour la vérification des achats : les trois offres, aux prix de base.
            VStack(spacing: 10) {
                ForEach([("Vicefold Pro", 5.99, "once"), ("Vicefold Pro", 2.99, "year"), ("Vicefold Pro", 0.99, "month")], id: \.1) { o in
                    let price = o.1.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                    Button {} label: {
                        offerLabel(o.0, o.2 == "once" ? String(localized: "\(price) once") : o.2 == "year" ? String(localized: "\(price) a year") : String(localized: "\(price) a month"))
                    }
                    .buttonStyle(.vf(o.2 == "once" ? .primary : .secondary))
                }
            }
        } else if store.isPro {
            Label("Pro is on", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(VF.palm)
                .shadow(color: VF.palm.opacity(0.6), radius: 8)
        } else if store.products.isEmpty {
            ProgressView().tint(VF.flamingo).task { await store.load() }
        } else {
            VStack(spacing: 10) {
                ForEach(store.products) { p in
                    Button { Task { await store.buy(p) } } label: { offerLabel(p.displayName, label(p)) }
                        .buttonStyle(.vf(p.id == Store.lifetime ? .primary : .secondary))
                        .disabled(store.busy)
                }
            }
        }
    }

    private func offerLabel(_ name: String, _ price: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: name).font(.headline).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(verbatim: price).font(.subheadline.weight(.bold)).multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(_ p: Product) -> String {
        if let s = p.subscription {
            return s.subscriptionPeriod.unit == .year ? String(localized: "\(p.displayPrice) a year") : String(localized: "\(p.displayPrice) a month")
        }
        return String(localized: "\(p.displayPrice) once")
    }
}
