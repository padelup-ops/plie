// TwinfoldApp.swift — Twinfold
//
// Two web pages at once: one above the fold of an iPhone Duo and one below (or side by side), or stacked on
// any iPhone. Everything stays on the device: no account, no server, no analytics.

import AVFoundation
import SwiftUI
import UIKit

@main
struct TwinfoldApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browser = Browser.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environment(browser)
                .onOpenURL { url in browser.handleIncoming(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { browser.saveSession() }
                    if phase == .active { QuickActions.refresh() }
                }
        }
    }
}

/// Home-screen quick actions (a saved pair opens both of its pages at once).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Videos play with sound even with the silent switch on, and keep going in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        if let item = options.shortcutItem {
            DispatchQueue.main.async { QuickActions.perform(item) }
        }
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.perform(shortcutItem))
    }
}

@MainActor
enum QuickActions {
    static func refresh() {
        let pairs = Library.shared.pairs.prefix(4)
        UIApplication.shared.shortcutItems = pairs.map { pair in
            UIApplicationShortcutItem(type: "pair", localizedTitle: pair.name,
                                      localizedSubtitle: String(localized: "Open both pages"),
                                      icon: UIApplicationShortcutIcon(systemImageName: "rectangle.split.1x2"),
                                      userInfo: ["id": pair.id.uuidString as NSString])
        }
    }

    @discardableResult
    static func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == "pair", let id = item.userInfo?["id"] as? String,
              let pair = Library.shared.pairs.first(where: { $0.id.uuidString == id }) else { return false }
        Browser.shared.open(pair)
        return true
    }
}
