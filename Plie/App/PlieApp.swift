import SwiftUI

@main
struct PlieApp: App {
    @State private var app = AppState()
    @State private var store = StoreManager()

    init() {
        SoundPlayer.configureSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.laser)
                .task { await store.load() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store

    var body: some View {
        @Bindable var app = app

        ZStack {
            Theme.ink.ignoresSafeArea()

            switch app.route {
            case .hub:
                HubView()
            case .rayonLevels:
                RayonLevelsView()
            case .rayon(let number):
                RayonPlayView(number: number)
                    .id(number)
            case .coffreLevels:
                CoffreLevelsView()
            case .coffre(let number):
                CoffrePlayView(number: number)
                    .id(number)
            case .coffreDuel:
                CoffreDuelView()
            case .soleil:
                SoleilView()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.route)
        .sheet(isPresented: $app.showPass) {
            PassView()
                .environment(store)
        }
    }
}
