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
    case paywall, discover, settings, privacy, memory, advent, letter
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
    /// Le parent a demandé à voir son enfant dans un coin de l'appel (caméra avant), et à garder sa réaction en photos.
    var showChild: Bool = UserDefaults.standard.bool(forKey: "allonoel.camera") {
        didSet { UserDefaults.standard.set(showChild, forKey: "allonoel.camera") }
    }
    var keepReactions: Bool = UserDefaults.standard.bool(forKey: "allonoel.reactions") {
        didSet { UserDefaults.standard.set(keepReactions, forKey: "allonoel.reactions") }
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
        call.camera(show: showChild, keep: keepReactions && premium)
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
        call.camera(show: showChild, keep: keepReactions && premium)
        ring()
    }

    func home() {
        call.hangUp()
        call.forgetReactions()
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
            call.prepare(profile: profile, scenario: .magic, premium: true, audio: false)
            let script = call.script
            let lines = script.compactMap(\.text)
            if route != "surprise" {
                // Le Père Noël dit le prénom : c'est la première phrase.
                call.pose(caption: lines.first ?? "", mood: .talking, mouth: 0.75)
            } else {
                // La phrase qui annonce l'étoile, juste avant la surprise.
                let spark = script.firstIndex { if case .spark = $0 { return true }; return false } ?? 0
                let before = script[..<spark].last { $0.text != nil }?.text
                call.pose(caption: before ?? lines.last ?? "", mood: .surprised, surprise: true, mouth: 0.4)
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
                case .advent: AdventView()
                case .letter: LetterView()
                }
            }
            .environment(model)
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(Noel.gold)
        }
        // L'écran reste allumé pendant l'appel ; la musique de Noël se tait avant la sonnerie.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            model.call.appActive(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.call.appActive(true)
        }
        .onChange(of: model.screen, initial: true) { _, s in
            UIApplication.shared.isIdleTimerDisabled = [.waiting, .incoming, .call].contains(s)
            ChristmasMusic.shared.screen(wantsMusic: ![.waiting, .incoming, .call].contains(s))
        }
    }
}
