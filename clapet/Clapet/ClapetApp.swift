import SwiftUI

@main
struct ClapetApp: App {
    @State private var model = ClapetModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, p in
                    if p == .active { model.reload() } else { model.flush() }
                }
        }
    }
}
