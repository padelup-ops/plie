import SwiftUI
import UserNotifications

@main
struct ClapetApp: App {
    @State private var model = ClapetModel()
    @State private var store = ClapetStore()
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = AlertPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(store)
                .preferredColorScheme(.dark)
                .task {
                    store.onChange = { [model] has in model.setPlus(has) }
                    await store.load()
                }
                .onChange(of: phase) { _, p in
                    if p == .active {
                        model.reload()
                        Task { await store.refresh() }
                    } else {
                        model.leavingScreen()
                        model.flush()
                    }
                }
        }
    }
}
