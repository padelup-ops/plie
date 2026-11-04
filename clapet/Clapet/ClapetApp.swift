import SwiftUI
import UIKit
import UserNotifications
import AppsFlyerLib

@main
struct ClapetApp: App {
    @UIApplicationDelegateAdaptor(FoldlyAppDelegate.self) private var appDelegate
    @State private var model = ClapetModel()
    @State private var store = ClapetStore()
    @Environment(\.scenePhase) private var phase
    /// Version TestFlight : l'écran de fête « Foldly est sur l'App Store », une fois.
    @AppStorage("launchPartySeen") private var partySeen = false
    @State private var party = false

    init() {
        UNUserNotificationCenter.current().delegate = AlertPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .safeAreaInset(edge: .bottom) { BetaBanner() }
                .fullScreenCover(isPresented: $party, onDismiss: { partySeen = true }) { LaunchCelebration() }
                .onAppear { if BetaBanner.isTestFlight && !partySeen { party = true } }
                .environment(model)
                .environment(store)
                .task {
                    store.onChange = { [model] has in
                        model.setPlus(has)
                        UserDefaults.standard.set(has, forKey: "plusActive")
                        GameCenter.shared.plus = has
                        // Sans Foldly+ : le compteur de l'écran verrouillé et le bilan du soir s'arrêtent.
                        if !has {
                            if LiveCounter.isOn { LiveCounter.stop() }
                            if EveningSummary.isOn { Task { _ = await EveningSummary.setOn(false, stats: model.stats) } }
                        }
                    }
                    GameCenter.shared.start()
                    await store.load()
                }
                .onChange(of: phase) { _, p in
                    if p == .active {
                        AppsFlyerLib.shared().start()   // une installation la première fois, puis chaque ouverture
                        model.reload()
                        LiveCounter.resume(model.stats)
                        GameCenter.shared.submit(model.stats)
                        Task { await store.refresh() }
                    } else {
                        model.leavingScreen()
                        model.flush()
                    }
                }
        }
    }
}

/// Orientation : l'écran extérieur reste en portrait ; l'écran intérieur (grand) tourne,
/// pour lire Foldly comme un livre quand le Duo est tenu en largeur.
final class FoldlyAppDelegate: NSObject, UIApplicationDelegate {
    /// AppsFlyer : mesure des installations et des ouvertures (attribution), configuré au lancement.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = "bTMCaKzq75sAF5TSGTyAHP"
        af.appleAppID = "6827349081"
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.isLargeScreen(window) ? .allButUpsideDown : .portrait
    }

    static func isLargeScreen(_ window: UIWindow?) -> Bool {
        guard let size = window?.windowScene?.screen.bounds.size ?? window?.bounds.size else { return false }
        return max(size.width, size.height) >= 800
    }

    /// À appeler quand l'écran change (Duo ouvert ou fermé).
    @MainActor static func refreshOrientations() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
