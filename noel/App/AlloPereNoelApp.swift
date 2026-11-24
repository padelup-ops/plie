// AlloPereNoelApp.swift — Allô Père Noël
//
// Le parent prépare un appel du Père Noël en moins d'une minute (prénom, qualités, scénario), puis tend l'iPhone :
// un « appel entrant » sonne, l'enfant décroche et le Père Noël lui parle. Tout se passe sur l'iPhone, sans internet.
//
// Parcours : lancement → accueil → lettre au Père Noël → choix du scénario → (attente) → appel entrant → appel → fin.

import SwiftUI

@main
struct AlloPereNoelApp: App {
    @State private var model = AppModel()
    @State private var store = MagicStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Noel.gold)
                .task { await store.start() }
        }
    }
}

enum Screen: Equatable { case splash, home, setup, scenario, waiting, incoming, call, ended, declined }

enum Sheet: String, Identifiable {
    case paywall, discover, settings, privacy, memory
    var id: String { rawValue }
}

@MainActor @Observable
final class AppModel {
    var screen: Screen = .splash
    var sheet: Sheet?
    var profile = ChildProfile.load()
    var scenario: Scenario = .magic
    var delay: RingDelay = .now
    var ringAt: Date?
    var subtitles: Bool = UserDefaults.standard.object(forKey: "allonoel.subtitles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(subtitles, forKey: "allonoel.subtitles") }
    }
    let call = CallController()

    init() {
        if let route = ShotMode.route { applyShot(route) }
    }

    func go(_ s: Screen) {
        withAnimation(.easeInOut(duration: 0.55)) { screen = s }
    }

    /// Lance l'appel choisi : on prépare la voix tout de suite, la sonnerie part maintenant ou après le délai.
    func startCall(premium: Bool) {
        profile.save()
        call.prepare(profile: profile, scenario: scenario, premium: premium)
        if delay == .now {
            ring()
        } else {
            ringAt = Date().addingTimeInterval(TimeInterval(delay.rawValue))
            go(.waiting)
        }
    }

    func ring() {
        ringAt = nil
        go(.incoming)
        call.ring()
    }

    func answer() {
        withAnimation(.easeOut(duration: 0.35)) { screen = .call }
        call.answer { [weak self] in self?.go(.ended) }
    }

    func decline() {
        call.decline()
        go(.declined)
    }

    func hangUp() {
        call.hangUp()
        go(.ended)
    }

    func replay(premium: Bool) {
        call.prepare(profile: profile, scenario: scenario, premium: premium)
        ring()
    }

    func home() {
        call.hangUp()
        ringAt = nil
        go(.home)
    }

    // MARK: Captures App Store

    private func applyShot(_ route: String) {
        switch route {
        case "home": screen = .home
        case "setup": screen = .setup
        case "scenario": screen = .scenario
        case "incoming": screen = .incoming
        case "call", "surprise":
            call.prepare(profile: profile, scenario: .magic, premium: false, audio: false)
            let lines = call.script.compactMap(\.text)
            if route == "call" {
                let line = lines.first(where: { $0.contains(profile.cleanNames.first ?? "§") && $0.count > 60 }) ?? lines.dropFirst(3).first ?? ""
                call.pose(caption: line, mood: .talking)
            } else {
                let i = lines.count >= 3 ? lines.count - 2 : 0
                call.pose(caption: lines.isEmpty ? "" : lines[i], mood: .surprised, surprise: true)
            }
            screen = .call
        case "end": screen = .ended
        case "card": screen = .ended; sheet = .memory
        case "paywall": screen = .scenario; sheet = .paywall
        case "discover": screen = .home; sheet = .discover
        default: screen = .home
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(MagicStore.self) private var store

    var body: some View {
        @Bindable var model = model
        ZStack {
            Noel.night.ignoresSafeArea()
            switch model.screen {
            case .splash: SplashView().transition(.opacity)
            case .home: HomeView().transition(.opacity)
            case .setup: SetupView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .scenario: ScenarioView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .waiting: WaitingView().transition(.opacity)
            case .incoming: IncomingCallView().transition(.opacity)
            case .call: CallView().transition(.opacity)
            case .ended: EndView().transition(.opacity)
            case .declined: DeclinedView().transition(.opacity)
            }
        }
        .sheet(item: $model.sheet) { sheet in
            Group {
                switch sheet {
                case .paywall: PaywallView()
                case .discover: DiscoverView()
                case .settings: SettingsView()
                case .privacy: NavigationStack { PrivacyView() }
                case .memory: MemoryCardView()
                }
            }
            .environment(model)
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(Noel.gold)
        }
        // L'écran reste allumé pendant l'appel ; la musique de Noël se tait avant la sonnerie.
        .onChange(of: model.screen, initial: true) { _, s in
            UIApplication.shared.isIdleTimerDisabled = [.waiting, .incoming, .call].contains(s)
            ChristmasMusic.shared.screen(wantsMusic: ![.waiting, .incoming, .call].contains(s))
        }
    }
}
