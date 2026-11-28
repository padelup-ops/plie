import CoreLocation
import SwiftUI
import UserNotifications

// Notification touchée (créneau libre, ouverture des réservations) : on ouvre la page de réservation dans l'app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Anciennes versions : jetons Playtomic issus d'une connexion par mot de passe, désormais inutiles.
        Keychain.set(nil, for: "playtomic.session")
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let link = (info["url"] as? String).flatMap(URL.init(string:))
        let target = (info["time"] as? String).map { BookingTarget(time: $0, duration: info["duration"] as? Int) }
        await MainActor.run {
            if let link { BotEngine.shared.openBooking = BookingRequest(url: link, target: target) }
            BotEngine.shared.armImminentRelease()
        }
    }
}

@main
struct PadelUpNeoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var directory = ClubDirectory.shared
    @StateObject private var bot = BotEngine.shared
    @StateObject private var server = ServerAPI.shared
    @StateObject private var location = LocationManager()
    @StateObject private var favorites = Favorites.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(directory)
                .environmentObject(bot)
                .environmentObject(server)
                .environmentObject(location)
                .environmentObject(favorites)
                .tint(UI.court)
                .task {
                    if let shot = ShotMode.current {
                        ShotMode.install(shot, directory: directory, bot: bot, location: location, server: server, favorites: favorites)
                        return
                    }
                    await directory.load()
                    await server.refreshMe()
                    await directory.loadPartnerClubs()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard ShotMode.current == nil else { return }
            switch phase {
            case .active: bot.startForeground()
            case .background: bot.stopForeground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BotEngine.backgroundTaskID)) {
            await BotEngine.shared.runAll()
            await BotEngine.shared.scheduleBackground()
        }
    }
}

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation? = nil
    @Published var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    func setDemo(_ loc: CLLocation) { location = loc }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways { self.manager.requestLocation() }
        }
    }
}
