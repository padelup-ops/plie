import CoreLocation
import SwiftUI

@main
struct PadelUpNeoApp: App {
    @StateObject private var directory = ClubDirectory.shared
    @StateObject private var bot = BotEngine.shared
    @StateObject private var server = ServerAPI.shared
    @StateObject private var location = LocationManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(directory)
                .environmentObject(bot)
                .environmentObject(server)
                .environmentObject(location)
                .tint(UI.accent)
                .task {
                    if let shot = ShotMode.current {
                        ShotMode.install(shot, directory: directory, bot: bot, location: location)
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
