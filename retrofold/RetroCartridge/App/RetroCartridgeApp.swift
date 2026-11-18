// RetroCartridgeApp.swift
// RetroCartridge
//
// Main entry point for the RetroFold app.
//
// The app uses a UIKit scene with a SwiftUI root instead of a SwiftUI `App`,
// so the root view controller can pick the supported orientations per
// display (see `ConsoleHostingController`).

import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ConsoleHostingController(rootView: RootView())
        // The console is designed dark; system bars and titles follow suit.
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Hosts the SwiftUI root.
///
/// The outer display honors supported orientations like any iPhone, so it is
/// locked to the landscape orientation that puts the hinge on top. The inner
/// display ignores supported orientations (Apple: "Prepare your app for
/// iPhone Duo"), so there the layout adapts to whatever orientation the
/// system picks and always splits at the fold. See DESIGN.md §4.
final class ConsoleHostingController: UIHostingController<RootView> {
    private var lastDisplay: DuoDisplay?
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard let screen = view.window?.windowScene?.screen else { return .all }
        if DuoDisplay(size: screen.bounds.size) == .outer { return .landscapeLeft }
        return ShotMode.forcedOrientation ?? .all
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Screenshot mode only: ask for a given orientation of the inner display.
        if let mask = ShotMode.forcedOrientation, let scene = view.window?.windowScene {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("shotOrient:", error.localizedDescription)
            }
        }
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-evaluate the orientation mask when the app moves between displays.
        guard let screen = view.window?.windowScene?.screen else { return }
        let display = DuoDisplay(size: screen.bounds.size)
        if display != lastDisplay {
            lastDisplay = display
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

/// Owns the application-scoped managers and injects them into the environment.
struct RootView: View {

    // MARK: - Core Managers (Application-Scoped)

    /// Global application state — active game, selected skin, purchase status.
    @State private var appState = AppState()

    /// Posture manager — tracks which iPhone Duo display the app is on.
    @State private var postureManager = PostureManager()

    /// Hinge engine — provides hinge angle data for visual effects ONLY.
    /// NOT used for layout decisions (per Apple HIG).
    @State private var hingeEngine = HingeEngine()

    /// Haptic feedback manager — CoreHaptics for button presses and events.
    @State private var hapticManager = HapticManager()

    /// Audio manager — 8-bit sound effects and retro chimes.
    @State private var audioManager = AudioManager()

    /// Store manager — StoreKit 2 IAP integration.
    @State private var storeManager = StoreManager()

    // MARK: - Body

    var body: some View {
        // The navigation stack only provides the system toolbar: on iPhone Duo
        // its items move into the display's reserved side column.
        NavigationStack {
            AdaptiveConsoleLayout()
        }
            .environment(appState)
            .environment(postureManager)
            .environment(hingeEngine)
            .environment(hapticManager)
            .environment(audioManager)
            .environment(storeManager)
            .onAppear {
                setupOnLaunch()
            }
            // Play the chosen sound pack once it's unlocked
            .onChange(of: storeManager.effectiveSoundPack(appState.soundPack), initial: true) { _, pack in
                audioManager.soundPack = pack
            }
            .onChange(of: appState.isSoundOn) { _, isOn in
                audioManager.areSoundEffectsOn = isOn
            }
    }

    // MARK: - Setup

    /// One-time initialization on app launch.
    private func setupOnLaunch() {
        // Before any sound, so a muted launch skips the startup chime
        audioManager.areSoundEffectsOn = appState.isSoundOn

        // Start haptic engine
        hapticManager.prepareEngine()

        // Chime and click when the hinge swings past 90° while unfolding
        hingeEngine.onUnfoldPast90Degrees = { [audioManager, hapticManager] in
            audioManager.playHingeSnap()
            hapticManager.playHaptic(.hingeClick)
        }

        // Start the hinge angle pipeline (onHingeChange, with a display-posture fallback)
        hingeEngine.startListening(following: postureManager)

        // Load StoreKit products
        Task {
            await storeManager.loadProducts()
        }

        // Play startup chime
        audioManager.playStartupChime()

        // Captures pour l'App Store (« -shot »)
        if let shot = ShotMode.shot { ShotMode.apply(shot, appState: appState) }
    }
}
