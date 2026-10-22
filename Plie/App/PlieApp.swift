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
            case .pliageLevels:
                PliageLevelsView()
            case .pliage(let number):
                PliagePlayView(number: number)
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
        .onAppear {
            #if DEBUG
            app.applyScreenshotRoute()
            if UserDefaults.standard.bool(forKey: "selfCheck") {
                let rayon = RayonEngine.selfCheck()
                let pliage = PliageEngine.selfCheck()
                NSLog("PLIE-CHECK rayon %ld/%ld pliage %ld/%ld", rayon.ok, RayonLevel.all.count, pliage.ok, PliageLevel.all.count)
                for failure in rayon.failures + pliage.failures {
                    NSLog("PLIE-CHECK ÉCHEC %@", failure)
                }
                let report = (["rayon \(rayon.ok)/\(RayonLevel.all.count)", "pliage \(pliage.ok)/\(PliageLevel.all.count)"]
                              + rayon.failures + pliage.failures).joined(separator: "\n")
                if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? report.write(to: folder.appendingPathComponent("selfcheck.txt"), atomically: true, encoding: .utf8)
                }
            }
            #endif
        }
        .sheet(isPresented: $app.showPass) {
            PassView()
                .environment(store)
        }
    }
}
