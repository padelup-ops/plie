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
                .modifier(ScreenLearner())
                .environment(model)
                .environment(store)
                .tint(Color("AccentColor"))
                .fullScreenDuo()
                .onChange(of: phase) { _, p in
                    if p == .active {
                        model.reload()
                        Task { await store.refresh() }
                        // La dictée se met prête toute seule si tout est déjà permis (le clavier n'aura pas à rouvrir l'app).
                        if UserDefaults.standard.string(forKey: "shot") == nil { DictationService.shared.warmStart() }
                    }
                }
                .task {
                    // Essai sur simulateur (CI) : `-parakeetTest chemin.wav` transcrit le fichier et écrit le résultat.
                    if let path = UserDefaults.standard.string(forKey: "parakeetTest") { await ParakeetSelfTest.run(path) }
                }
        }
    }
}

struct HomeView: View {
    @Environment(SettingsModel.self) private var model
    @Environment(Store.self) private var store
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("onboarded") private var onboarded = false
    /// Les nouveaux boutons (version 1.0.4) : montrés une fois à ceux qui avaient déjà l'app.
    @AppStorage("seenButtonsGuide") private var seenButtonsGuide = false
    @State private var showButtonsGuide = false
    /// « Quoi de neuf » : une fois par grande mise à jour, à ceux qui avaient déjà l'app.
    @AppStorage("seenWhatsNew") private var seenWhatsNew = ""
    @State private var showWhatsNew = false
    @State private var showPro = false
    /// Le clavier a demandé la dictée (foldboard://dictate).
    @State private var showDictation = false

    var body: some View {
        NavigationStack {
            // Un seul accueil pour tout le monde : la recherche, les réglages en cartes, l'aide et la FAQ.
            AtelierHome(showPro: $showPro)
            .sheet(isPresented: $showPro) { ProView().environment(store).fullScreenDuo() }
            .sheet(isPresented: $showDictation) { DictationView() }
            .onOpenURL { url in
                guard url.scheme == "foldboard", url.host == "dictate" else { return }
                DictationService.shared.startSession()
                showDictation = true
            }
            .sheet(isPresented: $showButtonsGuide) {
                NavigationStack { ButtonsGuide { showButtonsGuide = false } }
            }
            .sheet(isPresented: $showWhatsNew) {
                NavigationStack { WhatsNewView { showWhatsNew = false } }
            }
            .onAppear {
                // Déjà installé avant cette version : « Quoi de neuf » une fois (il remplace l'ancien guide des boutons).
                if onboarded && seenWhatsNew != WhatsNewView.edition {
                    seenWhatsNew = WhatsNewView.edition
                    seenButtonsGuide = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showWhatsNew = true }
                } else if onboarded && !seenButtonsGuide {
                    seenButtonsGuide = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showButtonsGuide = true }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                OnboardingView { onboarded = true; seenWhatsNew = WhatsNewView.edition }
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
