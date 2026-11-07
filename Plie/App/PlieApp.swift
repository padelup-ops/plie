import SwiftUI
import StoreKit
import Combine

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
                .task { await store.load() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.requestReview) private var requestReview
    /// Mode d'emploi montré automatiquement à la première visite de chaque jeu.
    @State private var howTo: GameID?
    @State private var keyToast = false
    private let trialTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var app = app

        ZStack {
            // L'accueil et les menus sont en papier. Les jeux en plein écran se dessinent eux-mêmes :
            // pas de fond animé derrière (économie de batterie).
            if onPaper {
                PaperBackdrop()
            } else if fullScreen {
                Theme.ink.ignoresSafeArea()
            } else {
                AmbientBackdrop(colors: backdropColors, intensity: 0.2)
            }

            Group {
            switch app.route {
            case .hub:
                HubView()
            case .rayonLevels:
                RayonLevelsView()
            case .rayon(let number):
                RayonPlayView(number: number)
                    .id(number)
            case .basculeLevels:
                BasculeLevelsView()
            case .bascule(let number):
                BasculePlayView(number: number)
                    .id(number)
            case .ferme:
                FermeView()
            case .cascade:
                CascadeView()
            case .bataille:
                BatailleView()
            case .carres:
                CarresView()
            case .mines:
                MinesView()
            case .peche:
                PecheView()
            case .golf:
                GolfView()
            case .comete:
                CometeView()
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
            case .boite:
                BoiteView()
            case .croco:
                CrocoView()
            case .coupDoeil:
                CoupDoeilView()
            case .bombe:
                BombeView()
            case .dessine:
                DessineView()
            case .pliou:
                PliouView()
            case .briques:
                BriquesView()
            case .bonneteau:
                BonneteauView()
            case .morpion:
                MorpionView()
            case .puissance:
                PuissanceView()
            case .soleil:
                SoleilView()
            case .billard:
                BillardView()
            case .luciole:
                LucioleView()
            case .ecole:
                EcoleView()
            case .duels:
                DuelsView()
            case .chifoumi:
                ChifoumiView()
            case .doigts:
                DoigtsView()
            case .sourire:
                SourireView()
            case .tape:
                TapeView()
            case .mots:
                MotsView()
            }
            }
            .environment(\.colorScheme, onPaper ? .light : .dark)
            .tint(onPaper ? Paper.accent : Theme.laser)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
        }
        .preferredColorScheme(onPaper ? .light : .dark)
        .animation(.easeInOut(duration: 0.24), value: app.route)
        .onChange(of: app.route) { _, route in
            SoundPlayer.shared.play(.pop, volume: 0.35)
            if let game = GameID.of(route) { app.opened(game) }
            if let game = GameID.of(route) {
                let key = "howto.seen.\(game.rawValue)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    #if DEBUG
                    // Pendant le tournage de la démo, pas de mode d'emploi par-dessus le jeu.
                    if Demo.scene != nil { return }
                    if UserDefaults.standard.string(forKey: "screenshotRoute") != nil { return }
                    #endif
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { howTo = game }
                }
            }
        }
        .sheet(item: $howTo) { game in HowToSheet(game: game) }
        .sheet(item: Binding(get: { app.trialOver }, set: { if $0 == nil { app.closeTrialOver() } })) { game in
            TrialOverSheet(game: game)
                .environment(app)
                .environment(store)
        }
        .onReceive(trialTicker) { _ in app.checkTrial(hasPass: store.hasEverything) }
        .overlay(alignment: .top) {
            if keyToast {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill").foregroundStyle(Paper.gold)
                    Text(L("Nouvelle clé ! Débloque un jeu depuis l'accueil."))
                        .font(.plie(15, weight: .bold))
                }
                .foregroundStyle(Paper.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Paper.sheet).shadow(color: Paper.shadow.opacity(0.25), radius: 10, y: 4))
                .overlay(Capsule().strokeBorder(Paper.gold, lineWidth: 1.5))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onChange(of: app.newKey) { _, _ in
            guard !store.hasEverything else { return }
            SoundPlayer.shared.play(.chime, volume: 0.8)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { keyToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeOut(duration: 0.3)) { keyToast = false }
            }
        }
        .onChange(of: app.reviewRequest) { _, _ in
            #if DEBUG
            if Demo.scene != nil { return }
            #endif
            // Un peu après la victoire, pour ne pas couper l'écran de réussite.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { requestReview() }
        }
        .onAppear {
            #if DEBUG
            app.applyScreenshotRoute()
            if UserDefaults.standard.bool(forKey: "selfCheck") {
                let rayon = RayonEngine.selfCheck()
                let bascule = BasculeEngine.selfCheck()
                NSLog("PLIE-CHECK rayon %ld/%ld", rayon.ok, RayonLevel.all.count)
                for failure in rayon.failures {
                    NSLog("PLIE-CHECK ÉCHEC %@", failure)
                }
                let report = ([L("rayon \(rayon.ok)/\(RayonLevel.all.count)"),
                               L("bascule \(bascule.ok)/\(BasculeLevel.all.count)")]
                              + rayon.failures + bascule.failures).joined(separator: "\n")
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
        case .basculeLevels, .bascule:
            return [Color(hex: 0x3DB8FF), Color(hex: 0x8BDB4F), Theme.gold]
        case .bataille:
            return [Theme.bataille, Color(hex: 0x0E4A6B), Color(hex: 0xFF6A3D)]
        case .carres:
            return [Color(hex: 0x3D8BFF), Color(hex: 0xFF4F7B), Theme.carres]
        case .mines:
            return [Color(hex: 0x3F8F6A), Theme.mines, Theme.coral]
        case .peche:
            return [Theme.peche, Color(hex: 0x0D335E), Color(hex: 0xFFC93C)]
        case .golf:
            return [Theme.golf, Color(hex: 0x16301E), Color(hex: 0xFF4F4F)]
        case .comete:
            return [Theme.comete, Color(hex: 0x07061A), Color(hex: 0xFF5AD8)]
        case .cascade:
            return [Theme.cascade, Color(hex: 0x7A3DFF), Color(hex: 0x0F4A52)]
        case .ferme:
            return [Color(hex: 0x4FD18B), Color(hex: 0xC7E86B), Color(hex: 0xFF9AC4)]
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
        case .boite:
            return [Theme.boite, Color(hex: 0x8A5A3C), Theme.gold]
        case .croco:
            return [Theme.croco, Color(hex: 0x0A5A44), Theme.gold]
        case .coupDoeil:
            return [Theme.oeil, Color(hex: 0x3D5CFF), Theme.gold]
        case .bombe:
            return [Theme.bombe, Theme.sun, Color(hex: 0x6A3DE8)]
        case .dessine:
            return [Theme.dessine, Theme.paint, Color(hex: 0x3D8BFF)]
        case .pliou:
            return [Theme.pliou, Color(hex: 0xFFD166), Color(hex: 0x7FC8FF)]
        case .briques:
            return [Theme.briques, Color(hex: 0xFF5C8A), Color(hex: 0x10123A)]
        case .bonneteau:
            return [Theme.bonneteau, Color(hex: 0x1F7A4D), Theme.gold]
        case .morpion:
            return [Theme.neonX, Theme.neonO, Color(hex: 0x1E0840)]
        case .puissance:
            return [Theme.p4Red, Theme.p4Yellow, Theme.p4Plate]
        case .soleil:
            return [Theme.sun, Theme.go, Theme.gold]
        case .billard:
            return [Theme.billard, Color(hex: 0x0E8558), Theme.gold]
        case .luciole:
            return [Theme.luciole, Color(hex: 0x5B2C6F), Color(hex: 0x0B0F3A)]
        case .ecole:
            return [Theme.ecole, Color(hex: 0x2F5D46), Color(hex: 0xFF8FC7)]
        case .duels:
            return [Theme.duelsA, Theme.duelsB, Theme.duels]
        case .mots:
            return [Theme.motsTeamA, Theme.motsTeamB, Theme.gold]
        case .chifoumi:
            return [Theme.chifoumi, Theme.sun, Theme.gold]
        case .doigts:
            return [Theme.doigts, Theme.gold, Theme.coral]
        case .sourire:
            return [Theme.sourire, Theme.paint, Theme.gold]
        case .tape:
            return [Theme.tape, Theme.duelsA, Theme.duelsB]
        }
    }

    /// L'accueil et les listes de niveaux : en papier, en mode clair.
    private var onPaper: Bool {
        switch app.route {
        case .hub, .rayonLevels, .basculeLevels: return true
        default: return false
        }
    }

    /// Écrans qui couvrent tout : le fond animé ne servirait à rien.
    private var fullScreen: Bool {
        switch app.route {
        case .airHockey, .billard, .filet, .piano, .luciole, .ecole, .soleil, .chess, .draughts, .boite, .croco, .pliou, .bombe, .coupDoeil, .dessine, .briques, .bonneteau, .morpion, .puissance, .duels, .mots, .chifoumi, .doigts, .sourire, .tape, .cascade, .bataille, .carres, .mines, .peche, .golf, .comete: return true
        default: return false
        }
    }
}


/// Fin de l'essai gratuit : on propose de garder le jeu (clé ou Pass), sans insister.
struct TrialOverSheet: View {
    let game: GameID
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: L("Fermer")) { dismiss() }
                }
                ZStack {
                    PaperSheet(color: game.paper, cornerRadius: 30, ear: 32, lift: 1.2)
                    VStack(spacing: 10) {
                        Image(systemName: game.symbol).font(.system(size: 46, weight: .bold))
                        Text(L("Fin de l'essai")).font(.system(.headline, design: .rounded, weight: .heavy)).opacity(0.7)
                        Text(game.title).font(.paperTitle(32)).minimumScaleFactor(0.5).lineLimit(1)
                        Text(L("Ça t'a plu ? Garde-le pour toujours avec une clé, ou ouvre tous les jeux avec le Pass."))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .opacity(0.8)
                    }
                    .foregroundStyle(Paper.ink)
                    .padding(22)
                }
                .frame(minHeight: 230)

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.showPass = true }
                } label: {
                    Label(store.pass.map { L("Tout débloquer · \($0.displayPrice)") } ?? L("Tout débloquer avec le Pass"), systemImage: "crown.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold.paperTone(), textColor: Paper.ink, height: 60))

                if app.keys > 0 {
                    Button {
                        if app.unlock(game) {
                            SoundPlayer.shared.play(.vault, volume: 0.8)
                            Haptics.success()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.route = game.route }
                        }
                    } label: {
                        Label(L("Garder ce jeu avec une clé"), systemImage: "key.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: game.paper, textColor: Paper.ink, height: 56))
                } else {
                    let left = app.gamesPerKey - app.keyProgress
                    Text(left > 1 ? L("Joue encore \(left) parties pour gagner une clé") : L("Joue encore 1 partie pour gagner une clé"))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }

                Button(L("Plus tard")) { dismiss() }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .paperScreen()
        .onAppear {
            // Déjà débloqué entre-temps (Pass acheté pendant l'essai) : rien à proposer.
            if store.hasEverything || app.isUnlocked(game, hasPass: false) { dismiss() }
        }
        .task {
            if store.pass == nil { await store.load() }
        }
    }
}
