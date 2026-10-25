import SwiftUI

// MARK: - Accueil
//
// Une grande carte « Jeu du jour », des filtres simples (seul, à deux, en famille, enfants),
// puis tous les jeux en vignettes de papier plié, chacune avec le dessin de la position du Duo.

struct HubView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var filter: HubFilter = .all
    @State private var howTo: GameID?

    static let newGames: Set<GameID> = [.boite, .chut, .coupDoeil, .bombe, .dessine, .pliou]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                topBar
                hero
                filters
                grid
                postureLegend
                if !store.ownsPass { passBanner }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        // Le fond lumineux est dessiné par RootView.
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(app)
                .environment(store)
        }
        .sheet(item: $howTo) { game in HowToSheet(game: game) }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        HStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Theme.paint.opacity(0.5), radius: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Text(L("ORIGAMO"))
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .tracking(1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.laser, Theme.paint, Theme.gold, Theme.sun, Theme.laser],
                                           startPoint: UnitPoint(x: -0.5 + (t * 0.08).truncatingRemainder(dividingBy: 1), y: 0),
                                           endPoint: UnitPoint(x: 1.5 + (t * 0.08).truncatingRemainder(dividingBy: 1), y: 1))
                        )
                }
                Text(L("\(GameID.allCases.count) jeux à jouer en pliant"))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            IconButton(symbol: "gearshape.fill", label: L("Réglages")) { showSettings = true }
        }
    }

    // MARK: Jeu du jour

    private var featured: GameID {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let pool = GameID.allCases
        return pool[day % pool.count]
    }

    private var hero: some View {
        let game = featured
        return Button {
            app.route = game.route
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label(L("Jeu du jour"), systemImage: "sparkles")
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.ink.opacity(0.85)))
                            .foregroundStyle(game.color)
                        if Self.newGames.contains(game) { NewBadge() }
                    }
                    Text(game.title)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink)
                    Text(game.tagline)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                    Spacer(minLength: 6)
                    HStack(spacing: 10) {
                        Label(L("Jouer"), systemImage: "play.fill")
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .padding(.horizontal, 22)
                            .frame(height: 50)
                            .background(Capsule().fill(Theme.ink))
                            .foregroundStyle(.white)
                        PostureBadge(posture: game.posture, players: game.players, dark: true)
                    }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            // Grand symbole du jeu, en filigrane à droite
            .background(alignment: .trailing) {
                FloatingSymbol(symbol: game.symbol, animate: !reduceMotion)
                    .padding(.trailing, 18)
            }
            .background(FoldedPaper(color: game.color, cornerRadius: 32))
            .shadow(color: game.color.opacity(0.5), radius: 24, y: 10)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Jeu du jour : \(game.title). \(game.tagline). \(game.posture.label), \(game.players)."))
        .accessibilityHint(L("Ouvre le jeu"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Filtres

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HubFilter.allCases) { f in
                    let selected = f == filter
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = f }
                    } label: {
                        Label(f.label, systemImage: f.symbol)
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 46)
                            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
                            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.18), lineWidth: 1))
                            .foregroundStyle(selected ? Theme.ink : .white)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var visibleGames: [GameID] {
        GameID.allCases.filter { filter == .all || $0.filters.contains(filter) }
    }

    // MARK: Les jeux

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 270), spacing: 14)], spacing: 14) {
            ForEach(visibleGames) { game in
                GameTile(game: game, isNew: Self.newGames.contains(game), progress: progress(for: game)) {
                    app.route = game.route
                } onHelp: {
                    howTo = game
                }
            }
        }
    }

    private func progress(for game: GameID) -> String? {
        switch game {
        case .rayon: return L("\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux")
        case .bascule: return L("\(app.basculeStars.count) / \(BasculeLevel.all.count) niveaux")
        case .boite: return L("\(app.boiteStars.count) / \(BoiteLevel.count) boîtes")
        case .chut: return app.chutGems > 0 ? L("\(app.chutStars.count) / \(ChutNight.count) nuits · \(app.chutGems) gemmes") : L("\(ChutNight.count) nuits")
        case .coupDoeil: return app.oeilStreak > 0 ? L("Série : \(app.oeilStreak) jour\(app.oeilStreak > 1 ? "s" : "")") : L("Un défi par jour")
        case .bombe: return app.bombeGames > 0 ? L("\(app.bombeGames) partie\(app.bombeGames > 1 ? "s" : "")") : L("3 à 8 joueurs")
        case .dessine: return app.dessineWords > 0 ? L("\(app.dessineWords) mot\(app.dessineWords > 1 ? "s" : "") deviné\(app.dessineWords > 1 ? "s" : "")") : L("3 joueurs et plus")
        case .pliou: return app.pliouDays > 0 ? L("\(app.pliouDays) jour\(app.pliouDays > 1 ? "s" : "") avec Pliou") : L("Un œuf t'attend")
        case .filet: return app.filetWins > 0 ? L("\(app.filetWins) victoire\(app.filetWins > 1 ? "s" : "")") : nil
        case .airHockey: return L("Premier à 7 buts")
        case .billard: return app.billardWins > 0 ? L("\(app.billardWins) victoire\(app.billardWins > 1 ? "s" : "")") : nil
        case .chess: return app.chessGames > 0 ? L("\(app.chessGames) partie\(app.chessGames > 1 ? "s" : "")") : nil
        case .draughts: return app.draughtsGames > 0 ? L("\(app.draughtsGames) partie\(app.draughtsGames > 1 ? "s" : "")") : nil
        case .luciole: return app.lucioleBest > 0 ? L("Record : \(app.lucioleBest) lumières") : nil
        case .ecole: return app.ecoleLessons > 0 ? L("\(app.ecoleLessons) leçon\(app.ecoleLessons > 1 ? "s" : "")") : L("5 classes")
        case .piano: return L("\(PianoSong.all.count) morceaux")
        case .soleil: return app.soleilGames > 0 ? L("\(app.soleilGames) partie\(app.soleilGames > 1 ? "s" : "")") : nil
        case .ferme: return L("\(app.fermeSpecies.count) / \(FermePlant.all.count) plantes · un vrai arbre")
        }
    }

    // MARK: Les positions du Duo

    private var postureLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Comment tenir ton Duo"))
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach([Posture.closedOpen, .openClose, .book, .fold, .lShape, .flat, .closed, .standing], id: \.self) { p in
                    HStack(spacing: 10) {
                        PostureIcon(posture: p, color: .white, lineWidth: 3)
                            .frame(width: 44, height: 32)
                            .accessibilityHidden(true)
                        Text(p.label)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.25)))
    }

    // MARK: Pass

    private var passBanner: some View {
        Button {
            app.showPass = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 26, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Pass Origamo"))
                        .font(.system(.title3, design: .rounded, weight: .black))
                    Text(L("Tous les niveaux, pour toujours"))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .opacity(0.85)
                }
                Spacer()
                Text(store.pass?.displayPrice ?? "")
                    .font(.system(.title3, design: .rounded, weight: .black))
            }
            .foregroundStyle(Theme.ink)
            .padding(18)
            .background(FoldedPaper(color: Theme.gold, cornerRadius: 24))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Une vignette de jeu : papier plié coloré, grand symbole, nom, phrase courte, position du Duo.
struct GameTile: View {
    let game: GameID
    let isNew: Bool
    let progress: String?
    let onPlay: () -> Void
    let onHelp: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        ZStack {
                            Circle().fill(Theme.ink.opacity(0.88))
                            PostureIcon(posture: game.posture, color: game.color, lineWidth: 2.6)
                                .padding(9)
                        }
                        .frame(width: 46, height: 46)
                        Spacer()
                        if isNew { NewBadge() }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: game.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                    Text(game.title)
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(game.tagline)
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress {
                        Text(progress)
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .foregroundStyle(Theme.ink.opacity(0.65))
                            .padding(.top, 2)
                    }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                Image(systemName: game.symbol)
                    .font(.system(size: 62, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.16))
                    .rotationEffect(.degrees(-12))
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .background(FoldedPaper(color: game.color, cornerRadius: 26))
            .shadow(color: game.color.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .topTrailing) {
            if !isNew {
                Button(action: onHelp) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.55)))
                }
                .padding(12)
                .accessibilityLabel(L("Comment jouer à \(game.title)"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("\(game.title). \(game.tagline). \(game.posture.label), \(game.players)."))
        .accessibilityHint(L("Ouvre le jeu"))
    }
}

struct NewBadge: View {
    var body: some View {
        Text(L("NOUVEAU"))
            .font(.system(.caption, design: .rounded, weight: .black))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.ink))
            .foregroundStyle(.white)
            .accessibilityLabel(L("Nouveau jeu"))
    }
}

struct PostureBadge: View {
    let posture: Posture
    let players: String
    var dark = false

    var body: some View {
        HStack(spacing: 8) {
            PostureIcon(posture: posture, color: dark ? Theme.ink : .white, lineWidth: 2.4)
                .frame(width: 34, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(posture.label)
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                Text(players)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .opacity(0.75)
            }
        }
        .foregroundStyle(dark ? Theme.ink : .white)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Capsule().fill((dark ? Color.white : Color.black).opacity(0.35)))
    }
}

/// Le grand symbole de la carte du jour, qui flotte doucement.
struct FloatingSymbol: View {
    let symbol: String
    let animate: Bool
    @State private var up = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 130, weight: .bold))
            .foregroundStyle(Theme.ink.opacity(0.2))
            .rotationEffect(.degrees(up ? -6 : 4))
            .offset(y: up ? -8 : 8)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { up = true }
            }
            .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Ressenti")) {
                    Toggle(L("Musique"), isOn: Binding(get: { app.musicOn }, set: { app.setMusic($0) }))
                    Toggle(L("Sons"), isOn: Binding(get: { app.soundOn }, set: { app.setSound($0) }))
                    Toggle(L("Vibrations"), isOn: Binding(get: { app.hapticsOn }, set: { app.setHaptics($0) }))
                }
                Section(L("Pass Origamo")) {
                    if store.ownsPass {
                        Label(L("Tout est débloqué"), systemImage: "checkmark.seal.fill")
                    } else {
                        Button(L("Voir le Pass")) {
                            dismiss()
                            app.showPass = true
                        }
                    }
                    Button(L("Restaurer mes achats")) {
                        Task { await store.restore() }
                    }
                    if let message = store.message {
                        Text(message).foregroundStyle(Theme.muted)
                    }
                }
                Section(L("iPhone Duo")) {
                    Text(DuoSupport.apisAvailable
                         ? L("Sur iPhone Duo, LA BOÎTE et CHUT ! commencent fermés : il faut ouvrir le Duo pour jouer. COUP D'ŒIL, BOMBE, PLIOU et LUCIOLE passent d'un écran à l'autre, et DESSINE-MOI montre ton dessin sur l'écran extérieur. RAYON et BASCULE se jouent avec la charnière ; FILET, ÉCOLE et le PIANO plié en L ; AIR HOCKEY, BILLARD, ÉCHECS et DAMES à plat ; FERME se joue fermé. Chaque jeu a son mode d'emploi : touche « ? ».")
                         : L("Cet iPhone n'a pas de charnière : tous les jeux se jouent au doigt. Chaque jeu a son mode d'emploi : touche « ? »."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                Section("Langue · Language") {
                    Picker("Langue · Language", selection: Binding(get: { Lang.shared.choice }, set: { Lang.shared.choice = $0 })) {
                        Text(verbatim: "Automatique · Automatic").tag(Lang.Choice.auto)
                        Text(verbatim: "Français").tag(Lang.Choice.fr)
                        Text(verbatim: "English").tag(Lang.Choice.en)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(L("Vie privée")) {
                    Text(L("Dans 1, 2, 3… Soleil ! et DESSINE-MOI, la caméra sert, directement sur le téléphone, à repérer les mouvements ou à prendre en photo ceux qui devinent. Les photos restent dans l'app le temps de la partie, et ne sont partagées que si tu le choisis. Quand ton jardin de FERME est complet, l'app envoie un seul message anonyme pour compter l'arbre à planter : rien ne permet de savoir qui tu es."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(L("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
    }
}

struct PassView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: L("Fermer")) { dismiss() }
                }
                Image(systemName: "crown.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text(L("Pass Origamo"))
                    .font(.plie(40))
                Text(L("Un seul achat, sans abonnement ni publicité."))
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    benefit("light.beacon.max.fill", Theme.laser, L("RAYON : \(RayonLevel.all.count - AppState.freeRayonLevels) niveaux de plus"), L("Miroirs pivotants, labyrinthes et miroirs jumeaux."))
                    benefit("shippingbox.fill", Theme.boite, L("LA BOÎTE : \(BoiteLevel.count - AppState.freeBoiteLevels) boîtes de plus"), L("Décodeurs géants, motifs en miroir et codes à l'envers."))
                    benefit("lizard.fill", Theme.chut, L("CHUT ! : \(ChutNight.count - AppState.freeChutNights) nuits de plus"), L("Un dragon au sommeil de plus en plus léger."))
                    benefit("arrow.up.right.circle.fill", Theme.bascule, L("BASCULE : \(BasculeLevel.all.count - AppState.freeBasculeLevels) niveaux de plus"), L("Le vent, puis les ressorts."))
                    benefit("figure.table.tennis", Theme.filet, L("FILET : le niveau Champion"), L("Un adversaire qui smashe et vise loin de ta raquette."))
                    benefit("crown.fill", Theme.chess, L("ÉCHECS et DAMES : l'ordinateur Difficile"), L("Un adversaire qui calcule plusieurs coups à l'avance."))
                    benefit("leaf.fill", Theme.ferme, L("FERME : toutes les plantes"), L("Tulipe, lavande, bonsaï, cerisier, rose, et les séances de 45 à 90 minutes."))
                    benefit("sparkles", Theme.sun, L("Les prochains jeux et niveaux"), L("Tout ce qui sortira plus tard est inclus."))
                }
                .padding(18)
                .background(GlassPanel(cornerRadius: 22))

                if store.ownsPass {
                    Label(L("Déjà débloqué, merci !"), systemImage: "checkmark.seal.fill")
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.go)
                } else {
                    Button {
                        Task { await store.buyPass() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(Theme.ink)
                        } else if let pass = store.pass {
                            Text(L("Tout débloquer pour \(pass.displayPrice)"))
                        } else {
                            Text(store.isLoading ? L("Chargement…") : L("Indisponible pour le moment"))
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink, height: 62))
                    .disabled(store.pass == nil || store.isPurchasing)
                }

                Button(L("Restaurer mes achats")) {
                    Task { await store.restore() }
                }
                .buttonStyle(GhostButtonStyle())

                if let message = store.message {
                    Text(message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink.ignoresSafeArea())
        .foregroundStyle(.white)
        .task {
            if store.pass == nil { await store.load() }
        }
    }

    private func benefit(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.plie(16, weight: .bold))
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Bouton qui s'enfonce légèrement quand on appuie.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
