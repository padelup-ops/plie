import SwiftUI
import StoreKit

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
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        @Bindable var app = app

        ZStack {
            AmbientBackdrop(colors: backdropColors, intensity: 0.2)

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
            case .basculeLevels:
                BasculeLevelsView()
            case .bascule(let number):
                BasculePlayView(number: number)
                    .id(number)
            case .ferme:
                FermeView()
            case .panier:
                PanierView()
            case .flechettes:
                FlechettesView()
            case .airHockey:
                AirHockeyView()
            case .filet:
                FiletView()
            case .chess:
                ChessView()
            case .draughts:
                DraughtsView()
            case .piano:
                PianoView()
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
        .onChange(of: app.route) { _, _ in
            SoundPlayer.shared.play(.pop, volume: 0.35)
        }
        .onChange(of: app.reviewRequest) { _, _ in
            // Un peu après la victoire, pour ne pas couper l'écran de réussite.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { requestReview() }
        }
        .onAppear {
            #if DEBUG
            app.applyScreenshotRoute()
            if UserDefaults.standard.bool(forKey: "selfCheck") {
                let rayon = RayonEngine.selfCheck()
                let pliage = PliageEngine.selfCheck()
                let bascule = BasculeEngine.selfCheck()
                NSLog("PLIE-CHECK rayon %ld/%ld pliage %ld/%ld", rayon.ok, RayonLevel.all.count, pliage.ok, PliageLevel.all.count)
                for failure in rayon.failures + pliage.failures {
                    NSLog("PLIE-CHECK ÉCHEC %@", failure)
                }
                let report = ([L("rayon \(rayon.ok)/\(RayonLevel.all.count)"), L("pliage \(pliage.ok)/\(PliageLevel.all.count)"),
                               L("bascule \(bascule.ok)/\(BasculeLevel.all.count)")]
                              + rayon.failures + pliage.failures + bascule.failures).joined(separator: "\n")
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

    /// Les couleurs du fond lumineux changent avec le jeu.
    private var backdropColors: [Color] {
        switch app.route {
        case .hub:
            return [Theme.laser, Theme.paint, Theme.gold]
        case .rayonLevels, .rayon:
            return [Color(hex: 0x6A3DE8), Theme.laser, Color(hex: 0x1F4FC9)]
        case .pliageLevels, .pliage:
            return [Theme.paint, Color(hex: 0xFF9A3D), Color(hex: 0x8B5CF6)]
        case .basculeLevels, .bascule:
            return [Color(hex: 0x3DB8FF), Color(hex: 0x8BDB4F), Theme.gold]
        case .ferme:
            return [Color(hex: 0x4FD18B), Color(hex: 0xC7E86B), Color(hex: 0xFF9AC4)]
        case .panier:
            return [Theme.sun, Color(hex: 0xFF3D6E), Theme.gold]
        case .flechettes:
            return [Theme.stop, Theme.gold, Color(hex: 0x2FD6A0)]
        case .airHockey:
            return [Theme.laser, Theme.paint, Color(hex: 0x7B5CFF)]
        case .filet:
            return [Theme.filet, Color(hex: 0x3CCB7F), Color(hex: 0xFF5C4D)]
        case .chess:
            return [Theme.chess, Color(hex: 0x8A5A3C), Color(hex: 0x6A5CFF)]
        case .draughts:
            return [Theme.draughts, Color(hex: 0xC8A35A), Color(hex: 0x5C3DE8)]
        case .piano:
            return [Theme.piano, Color(hex: 0xF3D79A), Color(hex: 0x8E1B22)]
        case .coffreLevels, .coffre, .coffreDuel:
            return [Theme.gold, Color(hex: 0xFF8A3D), Color(hex: 0x6A5CFF)]
        case .soleil:
            return [Theme.sun, Theme.go, Theme.gold]
        }
    }
}
