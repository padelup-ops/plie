import SwiftUI

// MARK: - Accueil
//
// Une table couverte de papier. En haut, les jeux à la une, en feuilles qu'on fait glisser.
// Puis « Reprendre », et tous les jeux en cartes pliées, qu'on trie d'un geste : à deux, en soirée,
// la magie du Duo, seul, pour les enfants. Les jeux encore fermés montrent un cadenas.

struct HubView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var howTo: GameID?
    @State private var unlocking: GameID?
    @State private var choosing = false
    @State private var featuredID: GameID?
    /// Dernière page choisie par le défilement automatique (pour reconnaître un glissement du doigt).
    @State private var autoFeatured: GameID?
    @State private var lastSwipe = Date.distantPast
    @State private var showPostures = false
    @AppStorage("hub.shelf") private var shelfID = "all"

    static let newGames: Set<GameID> = [.duels, .mots, .briques, .bonneteau]

    /// Les jeux à la une : ceux qui donnent le plus envie, et qui montrent ce que le Duo sait faire.
    static let featured: [GameID] = [.duels, .boite, .croco, .mots, .coupDoeil]

    /// L'ordre de « Tous » : les plus parlants d'abord.
    static let allOrder: [GameID] = {
        let curated: [GameID] = [.duels, .boite, .mots, .croco, .coupDoeil, .rayon, .airHockey, .dessine, .bombe,
                                 .puissance, .briques, .bonneteau, .pliou, .luciole, .morpion, .billard, .filet,
                                 .bascule, .chess, .draughts, .soleil, .ferme, .ecole, .piano]
        return curated + GameID.allCases.filter { !curated.contains($0) }
    }()

    struct Shelf: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let games: [GameID]
    }

    private var shelves: [Shelf] {
        [
            Shelf(id: "all", title: L("Tous"), symbol: "square.grid.2x2.fill", games: Self.allOrder),
            Shelf(id: "duo", title: L("À deux"), symbol: "person.2.fill",
                  games: [.duels, .airHockey, .puissance, .morpion, .billard, .chess, .draughts, .bonneteau]),
            Shelf(id: "party", title: L("En soirée"), symbol: "party.popper.fill",
                  games: [.mots, .croco, .dessine, .bombe, .soleil]),
            Shelf(id: "magic", title: L("La magie du Duo"), symbol: "sparkles",
                  games: [.boite, .coupDoeil, .luciole, .pliou, .ferme]),
            Shelf(id: "fold", title: L("Seul"), symbol: "person.fill",
                  games: [.rayon, .bascule, .briques, .filet, .boite, .coupDoeil, .pliou, .ferme]),
            Shelf(id: "kids", title: L("Enfants"), symbol: "graduationcap.fill",
                  games: [.ecole, .piano, .croco, .pliou, .morpion, .puissance])
        ]
    }

    private var shelf: Shelf { shelves.first { $0.id == shelfID } ?? shelves[0] }

    private var hasPass: Bool { store.hasEverything }

    private func unlocked(_ game: GameID) -> Bool { app.isUnlocked(game, hasPass: hasPass) }

    private func open(_ game: GameID) {
        if unlocked(game) {
            app.route = game.route
        } else {
            unlocking = game
        }
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar
                    .padding(.horizontal, 20)
                featured
                if !hasPass && app.lockedCount > 0 {
                    keysCard
                        .padding(.horizontal, 20)
                }
                if let last = app.lastPlayed, unlocked(last) {
                    resume(last)
                        .padding(.horizontal, 20)
                }
                library
                    .id("library")
                if !hasPass { passCard.padding(.horizontal, 20) }
                postureLegend
                    .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        .task {
            // Captures d'écran : les feuilles de l'accueil, et la grille des jeux.
            let shot = UserDefaults.standard.string(forKey: "screenshotRoute") ?? ""
            try? await Task.sleep(nanoseconds: 700_000_000)
            switch shot {
            case "settings": showSettings = true
            case "howto": howTo = .boite
            case "unlock": unlocking = .ferme
            case "games": reader.scrollTo("library", anchor: .top)
            case "party":
                shelfID = "party"
                reader.scrollTo("library", anchor: .top)
            default: break
            }
        }
        #endif
        }
        // Le fond de papier est dessiné par RootView.
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(app)
                .environment(store)
        }
        .sheet(item: $howTo) { game in HowToSheet(game: game) }
        .sheet(item: $unlocking) { game in
            UnlockSheet(game: game) {
                unlocking = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.route = game.route }
            }
            .environment(app)
            .environment(store)
        }
        .sheet(isPresented: $choosing) {
            ChooseGameSheet { game in
                choosing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { unlocking = game }
            }
            .environment(app)
            .environment(store)
        }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        HStack(spacing: 12) {
            OrigamoMark()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Origamo")
                    .font(.paperTitle(32, weight: .bold))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(L("\(GameID.allCases.count) jeux à jouer en pliant"))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Paper.inkSoft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !hasPass {
                Button {
                    app.showPass = true
                } label: {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Paper.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.gold.paperTone()).shadow(color: Paper.shadow.opacity(0.22), radius: 6, y: 3))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(L("Pass Origamo"))
            }
            IconButton(symbol: "gearshape.fill", label: L("Réglages")) { showSettings = true }
        }
    }

    // MARK: À la une

    private var featured: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Self.featured) { game in
                        HeroCard(game: game, locked: !unlocked(game), isNew: Self.newGames.contains(game),
                                 daily: game == .coupDoeil, animate: !reduceMotion) {
                            open(game)
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(game)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.leading, 20, for: .scrollContent)
            .contentMargins(.trailing, 44, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $featuredID)
            .scrollClipDisabled()
            .frame(height: 222)
            .onChange(of: featuredID) { _, new in
                if new != autoFeatured { lastSwipe = Date() }
            }
            .task {
                // Les feuilles défilent toutes seules, doucement, sauf si on vient d'en faire glisser une.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard !reduceMotion, Date().timeIntervalSince(lastSwipe) > 12 else { continue }
                    let current = Self.featured.firstIndex(of: featuredID ?? Self.featured[0]) ?? 0
                    let next = Self.featured[(current + 1) % Self.featured.count]
                    autoFeatured = next
                    withAnimation(.easeInOut(duration: 0.6)) { featuredID = next }
                }
            }

            HStack(spacing: 6) {
                ForEach(Self.featured) { game in
                    let on = game == (featuredID ?? Self.featured[0])
                    Capsule()
                        .fill(on ? Paper.ink : Paper.ink.opacity(0.18))
                        .frame(width: on ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: featuredID)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }

    // MARK: Clés

    private var keysCard: some View {
        let need = app.gamesPerKey
        let progress = Double(app.keyProgress) / Double(max(1, need))
        return Button {
            if app.keys > 0 { choosing = true } else { app.showPass = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Paper.ink.opacity(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: app.keys > 0 ? 1 : CGFloat(progress))
                        .stroke(Paper.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "key.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Paper.gold)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    if app.keys > 0 {
                        Text(app.keys > 1 ? L("\(app.keys) clés à utiliser !") : L("Une clé à utiliser !"))
                            .font(.paperTitle(20))
                        Text(L("Choisis le prochain jeu à débloquer"))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Paper.inkSoft)
                    } else {
                        Text(L("\(app.lockedCount) jeux à débloquer"))
                            .font(.paperTitle(20))
                        Text(need - app.keyProgress > 1 ? L("Encore \(need - app.keyProgress) parties pour gagner une clé") : L("Encore 1 partie pour gagner une clé"))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Paper.inkSoft)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: app.keys > 0 ? "chevron.right" : "crown.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(app.keys > 0 ? Paper.ink : Paper.gold)
            }
            .foregroundStyle(Paper.ink)
            .padding(16)
            .background(PaperSheet(color: app.keys > 0 ? Paper.note : Paper.sheet, cornerRadius: 22, ear: app.keys > 0 ? 18 : 0, lift: 0.8))
        }
        .buttonStyle(PressableStyle())
    }

    private func resume(_ game: GameID) -> some View {
        Button {
            app.route = game.route
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    PaperSheet(color: game.paper, cornerRadius: 12, lift: 0.4)
                    Image(systemName: game.symbol)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Paper.ink)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Reprendre"))
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(Paper.inkSoft)
                    Text(game.title)
                        .font(.paperTitle(19))
                        .foregroundStyle(Paper.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Paper.sheet)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Paper.ink))
            }
            .padding(10)
            .padding(.trailing, 4)
            .background(PaperSheet(color: Paper.sheet, cornerRadius: 22, lift: 0.7))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Reprendre") + ", " + game.title)
    }

    // MARK: Les jeux

    private var library: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shelves) { item in
                        let on = item.id == shelf.id
                        Button {
                            Haptics.tap()
                            withAnimation(.snappy(duration: 0.3)) { shelfID = item.id }
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .foregroundStyle(on ? Paper.sheet : Paper.ink)
                                .background(
                                    Capsule()
                                        .fill(on ? Paper.ink : Paper.sheet)
                                        .shadow(color: Paper.shadow.opacity(on ? 0.25 : 0.10), radius: on ? 6 : 3, y: 2)
                                )
                                .overlay(Capsule().stroke(Paper.shadow.opacity(on ? 0 : 0.08), lineWidth: 0.75))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 14)], spacing: 14) {
                ForEach(shelf.games) { game in
                    GameCard(game: game, locked: !unlocked(game), isNew: Self.newGames.contains(game), progress: progress(for: game)) {
                        open(game)
                    } onHelp: {
                        howTo = game
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private func progress(for game: GameID) -> String? {
        switch game {
        case .rayon: return L("\(app.rayonSolved.count) / \(RayonLevel.all.count) niveaux")
        case .bascule: return L("\(app.basculeStars.count) / \(BasculeLevel.all.count) niveaux")
        case .duels: return app.duelsGames > 0 ? L("\(app.duelsGames) partie\(app.duelsGames > 1 ? "s" : "")") : L("\(DuelsGame.Kind.allCases.count) mini-duels")
        case .mots: return app.motsBest > 0 ? L("Record : \(app.motsBest) mots") : L("En équipes")
        case .boite: return L("\(app.boiteStars.count) / \(BoiteLevel.count) boîtes")
        case .croco: return app.crocoBest > 0 ? L("Record : \(app.crocoBest) dents") : L("1 à 6 joueurs")
        case .coupDoeil: return app.oeilStreak > 0 ? L("Série : \(app.oeilStreak) jour\(app.oeilStreak > 1 ? "s" : "")") : L("Un défi par jour")
        case .bombe: return app.bombeGames > 0 ? L("\(app.bombeGames) partie\(app.bombeGames > 1 ? "s" : "")") : L("3 à 8 joueurs")
        case .dessine: return app.dessineWords > 0 ? L("\(app.dessineWords) mot\(app.dessineWords > 1 ? "s" : "") deviné\(app.dessineWords > 1 ? "s" : "")") : L("3 joueurs et plus")
        case .briques: return L("\(app.briquesStars.count) / \(BriquesLevel.count) niveaux")
        case .bonneteau: return app.bonneteauBest > 0 ? L("Record seul : niveau \(app.bonneteauBest)") : L("À deux ou seul")
        case .morpion: return app.morpionWins > 0 ? L("\(app.morpionWins) victoire\(app.morpionWins > 1 ? "s" : "")") : L("Classique et super morpion")
        case .puissance: return app.puissanceWins > 0 ? L("\(app.puissanceWins) victoire\(app.puissanceWins > 1 ? "s" : "")") : L("Contre l'ordi ou à deux")
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
        case .ferme: return BuildFlags.realTrees ? L("\(app.fermeSpecies.count) / \(FermePlant.all.count) plantes · un vrai arbre")
                                                 : L("\(app.fermeSpecies.count) / \(FermePlant.all.count) plantes")
        }
    }

    // MARK: Pass

    private var passCard: some View {
        Button {
            app.showPass = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 24, weight: .bold))
                    Text(L("Pass Origamo"))
                        .font(.paperTitle(26))
                    Spacer()
                    Text(store.pass?.displayPrice ?? "")
                        .font(.system(.title3, design: .rounded, weight: .black))
                }
                Text(L("Tous les jeux tout de suite, 8 mini-duels de plus et tous les niveaux. Un seul achat, sans abonnement ni publicité."))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Paper.ink.opacity(0.75))
                Text(L("Tout débloquer"))
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Capsule().fill(Paper.ink))
                    .foregroundStyle(Paper.sheet)
            }
            .foregroundStyle(Paper.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PaperSheet(color: Theme.gold.paperTone(), cornerRadius: 26, ear: 26, lift: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Les positions du Duo

    private var postureLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showPostures.toggle() }
            } label: {
                HStack {
                    Label(L("Comment tenir ton Duo"), systemImage: "iphone.gen3")
                        .font(.paperTitle(18))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .rotationEffect(.degrees(showPostures ? 180 : 0))
                }
                .foregroundStyle(Paper.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showPostures {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach([Posture.closedOpen, .openClose, .book, .fold, .lShape, .flat, .closed, .standing], id: \.self) { p in
                        HStack(spacing: 10) {
                            PostureIcon(posture: p, color: Paper.ink, lineWidth: 2.6)
                                .frame(width: 44, height: 32)
                                .accessibilityHidden(true)
                            Text(p.label)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(Paper.ink.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.cream))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(16)
        .background(PaperSheet(color: Paper.sheet, cornerRadius: 22, lift: 0.7))
    }
}

/// Une grande feuille « à la une » : couleur du jeu, coin corné, symbole qui flotte, nom, phrase, position du Duo.
struct HeroCard: View {
    let game: GameID
    let locked: Bool
    let isNew: Bool
    let daily: Bool
    let animate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(daily ? L("Défi du jour") : L("À la une"), systemImage: daily ? "calendar" : "sparkles")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Paper.ink))
                        .foregroundStyle(Paper.sheet)
                    if isNew { NewBadge() }
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Paper.ink)
                    }
                }
                Spacer(minLength: 4)
                Text(game.title)
                    .font(.paperTitle(34))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Paper.ink)
                Text(game.tagline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Paper.ink.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)
                HStack(spacing: 10) {
                    Label(locked ? L("Débloquer") : L("Jouer"), systemImage: locked ? "lock.open.fill" : "play.fill")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Capsule().fill(Paper.ink))
                        .foregroundStyle(Paper.sheet)
                    PostureBadge(posture: game.posture, players: game.players, dark: true)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topTrailing) {
                FloatingSymbol(symbol: game.symbol, animate: animate)
                    .padding(.top, 30)
                    .padding(.trailing, 16)
            }
            .background(PaperSheet(color: game.paper, cornerRadius: 28, ear: 30, lift: 1.1))
            .padding(.vertical, 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(game.title). \(game.tagline). \(game.posture.label), \(game.players)."))
        .accessibilityHint(locked ? L("Jeu à débloquer") : L("Ouvre le jeu"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Une carte de jeu : une feuille pliée de la couleur du jeu, coin corné, grand symbole, nom, et un cadenas si le jeu est fermé.
struct GameCard: View {
    let game: GameID
    let locked: Bool
    let isNew: Bool
    let progress: String?
    let onPlay: () -> Void
    let onHelp: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(.white.opacity(0.45))
                        Circle().stroke(Paper.ink.opacity(0.18), lineWidth: 0.75)
                        PostureIcon(posture: game.posture, color: Paper.ink, lineWidth: 2.2)
                            .padding(8)
                    }
                    .frame(width: 38, height: 38)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Paper.sheet)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Paper.ink))
                    } else if isNew {
                        NewBadge()
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 8)
                Image(systemName: game.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Paper.ink)
                    .accessibilityHidden(true)
                Text(game.title)
                    .font(.paperTitle(17))
                    .foregroundStyle(Paper.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(locked ? L("Une clé pour l'ouvrir") : (progress ?? game.players))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.66))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                Image(systemName: game.symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Paper.ink.opacity(0.08))
                    .rotationEffect(.degrees(-12))
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .background(PaperSheet(color: game.paper, cornerRadius: 22, ear: 22, lift: 0.8))
            .saturation(locked ? 0.3 : 1)
            .opacity(locked ? 0.85 : 1)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button {
                onHelp()
            } label: {
                Label(L("Comment jouer"), systemImage: "questionmark.circle")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(game.title). \(game.tagline). \(game.posture.label), \(game.players)."))
        .accessibilityHint(locked ? L("Jeu à débloquer") : L("Ouvre le jeu"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Débloquer un jeu

/// La fiche d'un jeu fermé : ce qu'il propose, et comment l'ouvrir (une clé, ou le Pass).
struct UnlockSheet: View {
    let game: GameID
    let onUnlocked: () -> Void
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
                        Image(systemName: game.symbol)
                            .font(.system(size: 50, weight: .bold))
                        Text(game.title)
                            .font(.paperTitle(34))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(game.tagline)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .opacity(0.75)
                        PostureBadge(posture: game.posture, players: game.players, dark: true)
                    }
                    .foregroundStyle(Paper.ink)
                    .padding(22)
                }
                .frame(minHeight: 250)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(game.howTo(duo: DuoSupport.apisAvailable).prefix(3).enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.element.symbol)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Paper.ink.opacity(0.7))
                                .frame(width: 26)
                            Text(item.element.text)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .background(PaperSheet(color: Paper.sheet, cornerRadius: 20, lift: 0.6))

                if app.keys > 0 {
                    Button {
                        if app.unlock(game) {
                            SoundPlayer.shared.play(.vault, volume: 0.8)
                            Haptics.success()
                            onUnlocked()
                        }
                    } label: {
                        Label(app.keys > 1 ? L("Utiliser une clé (\(app.keys) en poche)") : L("Utiliser ma clé"), systemImage: "key.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: game.paper, textColor: Paper.ink, height: 60))
                } else {
                    VStack(spacing: 8) {
                        let left = app.gamesPerKey - app.keyProgress
                        Label(left > 1 ? L("Joue encore \(left) parties pour gagner une clé") : L("Joue encore 1 partie pour gagner une clé"), systemImage: "key.fill")
                            .font(.plie(16, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(L("N'importe quel jeu compte."))
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.showPass = true }
                } label: {
                    Label(store.pass.map { L("Tout débloquer · \($0.displayPrice)") } ?? L("Tout débloquer avec le Pass"), systemImage: "crown.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold.paperTone(), textColor: Paper.ink, height: 56))
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .paperScreen()
        .task {
            if store.pass == nil { await store.load() }
        }
    }
}

/// Avec une clé en poche : tous les jeux encore fermés, on choisit.
struct ChooseGameSheet: View {
    let onPick: (GameID) -> Void
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var locked: [GameID] { GameID.allCases.filter { !app.isUnlocked($0, hasPass: store.hasEverything) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: L("Fermer")) { dismiss() }
                }
                Image(systemName: "key.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Paper.gold)
                Text(L("Quel jeu veux-tu ouvrir ?"))
                    .font(.paperTitle(28))
                    .multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(locked) { game in
                        GameCard(game: game, locked: false, isNew: false, progress: game.players) {
                            onPick(game)
                        } onHelp: {}
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperScreen()
    }
}

struct NewBadge: View {
    var body: some View {
        Text(L("NOUVEAU"))
            .font(.system(.caption, design: .rounded, weight: .black))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Paper.accent))
            .foregroundStyle(Paper.sheet)
            .accessibilityLabel(L("Nouveau jeu"))
    }
}

struct PostureBadge: View {
    let posture: Posture
    let players: String
    var dark = false

    var body: some View {
        HStack(spacing: 8) {
            PostureIcon(posture: posture, color: dark ? Paper.ink : .white, lineWidth: 2.4)
                .frame(width: 32, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(posture.label)
                    .font(.system(.caption, design: .rounded, weight: .heavy))
                Text(players)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .opacity(0.75)
            }
        }
        .foregroundStyle(dark ? Paper.ink : .white)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Capsule().fill((dark ? Color.white : Color.black).opacity(dark ? 0.42 : 0.35)))
    }
}

/// Le grand symbole de la carte du jour, qui flotte doucement.
struct FloatingSymbol: View {
    let symbol: String
    let animate: Bool
    @State private var up = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 112, weight: .bold))
            .foregroundStyle(Paper.ink.opacity(0.13))
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
                if store.isTestBuild && !BuildFlags.paidApp {
                    Section(L("Version de test")) {
                        Label(L("Testeur : tous les jeux et tous les niveaux sont offerts."), systemImage: "gift.fill")
                        Toggle(L("Voir l'app comme un nouveau joueur"), isOn: Binding(get: { store.simulateFree }, set: { store.setSimulateFree($0) }))
                        Text(L("Pour voir les cadenas, les clés et le Pass, comme quelqu'un qui vient d'installer l'app."))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if !BuildFlags.paidApp {
                Section(L("Pass Origamo")) {
                    if store.hasEverything {
                        Label(store.ownsPass ? L("Tout est débloqué") : L("Offert aux testeurs"), systemImage: "checkmark.seal.fill")
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
                }
                Section(L("iPhone Duo")) {
                    Text(DuoSupport.apisAvailable
                         ? L("Sur iPhone Duo, LA BOÎTE et CROCO commencent fermés : il faut ouvrir le Duo pour jouer. COUP D'ŒIL, BOMBE, PLIOU et LUCIOLE passent d'un écran à l'autre ; DESSINE-MOI, BONNETEAU et MOTS INTERDITS montrent le jeu sur l'écran extérieur, face aux autres joueurs. RAYON et BASCULE se jouent avec la charnière ; FILET, ÉCOLE, PIANO, PUISSANCE 4 et CASSE-BRIQUES plié en L ; AIR HOCKEY, BILLARD, ÉCHECS, DAMES, MORPION et DUELS à plat ; FERME se joue fermé. Chaque jeu a son mode d'emploi : touche « ? ».")
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
                    Text(L("Dans 1, 2, 3… Soleil !, DESSINE-MOI, BONNETEAU et MOTS INTERDITS, la caméra sert, directement sur le téléphone, à repérer les mouvements, à prendre en photo ceux qui devinent, ou simplement à allumer l'écran extérieur. Les photos restent dans l'app le temps de la partie, et ne sont partagées que si tu le choisis. Quand ton jardin de FERME est complet, l'app envoie un seul message anonyme pour compter l'arbre à planter : rien ne permet de savoir qui tu es."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackdrop())
            .navigationTitle(L("Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .tint(Paper.accent)
        .environment(\.colorScheme, .light)
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
                WinIcon(systemName: "crown.fill", color: Theme.gold.paperTone())
                Text(L("Pass Origamo"))
                    .font(.paperTitle(38))
                Text(L("Tous les jeux et tous les niveaux. Un seul achat, sans abonnement ni publicité."))
                    .font(.plie(17, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    benefit("lock.open.fill", Paper.gold, L("Tous les jeux, tout de suite"), L("Plus besoin de clés : les \(GameID.allCases.count - AppState.starterGames.count) jeux à débloquer s'ouvrent d'un coup."))
                    benefit("bolt.fill", Theme.duels, L("DUELS : 8 mini-duels de plus"), L("Pierre-feuille-ciseaux, nerfs d'acier, cercle parfait, ballon, l'intrus…"))
                    benefit("light.beacon.max.fill", Theme.laser, L("RAYON : \(RayonLevel.all.count - AppState.freeRayonLevels) niveaux de plus"), L("Miroirs pivotants, labyrinthes et miroirs jumeaux."))
                    benefit("square.grid.3x2.fill", Theme.briques, L("CASSE-BRIQUES : \(BriquesLevel.count - AppState.freeBriquesLevels) niveaux de plus"), L("Briques blindées, murs d'acier et balle plus rapide."))
                    benefit("shippingbox.fill", Theme.boite, L("LA BOÎTE : \(BoiteLevel.count - AppState.freeBoiteLevels) boîtes de plus"), L("Décodeurs géants, motifs en miroir et codes à l'envers."))
                    benefit("arrow.up.right.circle.fill", Theme.bascule, L("BASCULE : \(BasculeLevel.all.count - AppState.freeBasculeLevels) niveaux de plus"), L("Le vent, puis les ressorts."))
                    benefit("figure.table.tennis", Theme.filet, L("FILET : le niveau Champion"), L("Un adversaire qui smashe et vise loin de ta raquette."))
                    benefit("crown.fill", Theme.chess, L("ÉCHECS et DAMES : l'ordinateur Difficile"), L("Un adversaire qui calcule plusieurs coups à l'avance."))
                    benefit("leaf.fill", Theme.ferme, L("FERME : toutes les plantes"), L("Tulipe, lavande, bonsaï, cerisier, rose, et les séances de 45 à 90 minutes."))
                    benefit("sparkles", Theme.sun, L("Les prochains jeux et niveaux"), L("Tout ce qui sortira plus tard est inclus."))
                }
                .padding(18)
                .background(PaperSheet(color: Paper.sheet, cornerRadius: 22, ear: 22, lift: 0.8))

                if store.hasEverything {
                    Label(L("Déjà débloqué, merci !"), systemImage: "checkmark.seal.fill")
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.go)
                } else {
                    Button {
                        Task { await store.buyPass() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView().tint(Paper.ink)
                        } else if let pass = store.pass {
                            Text(L("Tout débloquer pour \(pass.displayPrice)"))
                        } else {
                            Text(store.isLoading ? L("Chargement…") : L("Indisponible pour le moment"))
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.gold.paperTone(), textColor: Paper.ink, height: 62))
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
        .paperScreen()
        .task {
            if store.pass == nil { await store.load() }
        }
    }

    private func benefit(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color.paperTone(saturation: 0.95, brightness: 0.8))
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
