import SwiftUI
import Combine

extension Theme {
    static let devine = Color(hex: 0xF472D0)
}

// MARK: - Qui suis-je ?
//
// Duo fermé, posé sur le front : l'écran extérieur montre un mot à tes amis, toi tu ne le vois pas.
// Ils te font deviner (indices, mimes). Penche la tête en avant : trouvé ! En arrière : on passe.
// À la fin, ouvre le Duo : le grand écran affiche ton score et tous les mots.

enum DevineCategory: Int, CaseIterable, Identifiable {
    case animals, jobs, objects, food, mime, places

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .animals: return L("Animaux")
        case .jobs: return L("Métiers")
        case .objects: return L("Objets")
        case .food: return L("À manger")
        case .mime: return L("À mimer")
        case .places: return L("Lieux")
        }
    }

    var symbol: String {
        switch self {
        case .animals: return "pawprint.fill"
        case .jobs: return "stethoscope"
        case .objects: return "umbrella.fill"
        case .food: return "fork.knife"
        case .mime: return "figure.dance"
        case .places: return "mountain.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .animals: return Color(hex: 0x8BDB4F)
        case .jobs: return Color(hex: 0x5CC8FF)
        case .objects: return Color(hex: 0xFFC53D)
        case .food: return Color(hex: 0xFF8A5C)
        case .mime: return Color(hex: 0xC59BFF)
        case .places: return Color(hex: 0x2FD08C)
        }
    }

    /// Les mots, en français et en anglais.
    var words: [(String, String)] {
        switch self {
        case .animals:
            return [("Chat", "Cat"), ("Chien", "Dog"), ("Éléphant", "Elephant"), ("Girafe", "Giraffe"), ("Lion", "Lion"),
                    ("Pingouin", "Penguin"), ("Kangourou", "Kangaroo"), ("Crocodile", "Crocodile"), ("Singe", "Monkey"),
                    ("Serpent", "Snake"), ("Lapin", "Rabbit"), ("Cheval", "Horse"), ("Vache", "Cow"), ("Cochon", "Pig"),
                    ("Poule", "Chicken"), ("Requin", "Shark"), ("Dauphin", "Dolphin"), ("Baleine", "Whale"),
                    ("Papillon", "Butterfly"), ("Abeille", "Bee"), ("Araignée", "Spider"), ("Escargot", "Snail"),
                    ("Grenouille", "Frog"), ("Hibou", "Owl"), ("Perroquet", "Parrot"), ("Tortue", "Turtle"),
                    ("Zèbre", "Zebra"), ("Ours", "Bear"), ("Loup", "Wolf"), ("Renard", "Fox")]
        case .jobs:
            return [("Pompier", "Firefighter"), ("Médecin", "Doctor"), ("Cuisinier", "Cook"), ("Pilote d'avion", "Pilot"),
                    ("Astronaute", "Astronaut"), ("Policier", "Police officer"), ("Boulanger", "Baker"), ("Coiffeur", "Hairdresser"),
                    ("Dentiste", "Dentist"), ("Jardinier", "Gardener"), ("Magicien", "Magician"), ("Chanteur", "Singer"),
                    ("Photographe", "Photographer"), ("Professeur", "Teacher"), ("Facteur", "Mail carrier"),
                    ("Vétérinaire", "Vet"), ("Pêcheur", "Fisherman"), ("Peintre", "Painter"), ("Plombier", "Plumber"),
                    ("Danseuse", "Dancer"), ("Clown", "Clown"), ("Pirate", "Pirate"), ("Chevalier", "Knight"),
                    ("Détective", "Detective"), ("Footballeur", "Soccer player")]
        case .objects:
            return [("Parapluie", "Umbrella"), ("Brosse à dents", "Toothbrush"), ("Téléphone", "Phone"), ("Guitare", "Guitar"),
                    ("Ballon", "Ball"), ("Ciseaux", "Scissors"), ("Lunettes", "Glasses"), ("Chaussette", "Sock"),
                    ("Lampe", "Lamp"), ("Horloge", "Clock"), ("Clé", "Key"), ("Bougie", "Candle"), ("Vélo", "Bike"),
                    ("Valise", "Suitcase"), ("Appareil photo", "Camera"), ("Marteau", "Hammer"), ("Échelle", "Ladder"),
                    ("Fourchette", "Fork"), ("Oreiller", "Pillow"), ("Miroir", "Mirror"), ("Trompette", "Trumpet"),
                    ("Cerf-volant", "Kite"), ("Montre", "Watch"), ("Peigne", "Comb"), ("Boussole", "Compass")]
        case .food:
            return [("Pizza", "Pizza"), ("Banane", "Banana"), ("Glace", "Ice cream"), ("Croissant", "Croissant"),
                    ("Spaghettis", "Spaghetti"), ("Fromage", "Cheese"), ("Carotte", "Carrot"), ("Pomme", "Apple"),
                    ("Chocolat", "Chocolate"), ("Gâteau", "Cake"), ("Frites", "Fries"), ("Sandwich", "Sandwich"),
                    ("Soupe", "Soup"), ("Crêpe", "Pancake"), ("Tomate", "Tomato"), ("Fraise", "Strawberry"),
                    ("Pastèque", "Watermelon"), ("Pop-corn", "Popcorn"), ("Œuf", "Egg"), ("Pain", "Bread"),
                    ("Citron", "Lemon"), ("Sushi", "Sushi"), ("Hamburger", "Burger"), ("Bonbon", "Candy"), ("Yaourt", "Yogurt")]
        case .mime:
            return [("Nager", "Swimming"), ("Dormir", "Sleeping"), ("Danser", "Dancing"), ("Éternuer", "Sneezing"),
                    ("Se brosser les dents", "Brushing your teeth"), ("Faire du vélo", "Riding a bike"), ("Conduire", "Driving"),
                    ("Cuisiner", "Cooking"), ("Jongler", "Juggling"), ("Pêcher", "Fishing"), ("Skier", "Skiing"),
                    ("Boxer", "Boxing"), ("Applaudir", "Clapping"), ("Pleurer", "Crying"), ("Rire", "Laughing"),
                    ("Courir", "Running"), ("Sauter à la corde", "Jumping rope"), ("Se maquiller", "Putting on makeup"),
                    ("Jouer de la guitare", "Playing guitar"), ("Peindre un mur", "Painting a wall"), ("Lire un livre", "Reading a book"),
                    ("Téléphoner", "Making a phone call"), ("Tricoter", "Knitting"), ("Surfer", "Surfing"), ("Marcher sur la Lune", "Walking on the Moon")]
        case .places:
            return [("Plage", "Beach"), ("Montagne", "Mountain"), ("École", "School"), ("Hôpital", "Hospital"),
                    ("Piscine", "Swimming pool"), ("Cinéma", "Movie theater"), ("Forêt", "Forest"), ("Désert", "Desert"),
                    ("Aéroport", "Airport"), ("Zoo", "Zoo"), ("Château", "Castle"), ("Bibliothèque", "Library"),
                    ("Boulangerie", "Bakery"), ("Supermarché", "Supermarket"), ("Île", "Island"), ("Volcan", "Volcano"),
                    ("Gare", "Train station"), ("Musée", "Museum"), ("Cirque", "Circus"), ("Ferme", "Farm")]
        }
    }
}

@Observable
final class DevineGame {
    enum Phase: Equatable {
        case menu
        /// On attend que le téléphone soit posé sur le front (Duo fermé).
        case ready
        case countdown(Int)
        case playing
        /// Temps écoulé : Duo fermé, on attend qu'il soit rouvert pour montrer le score.
        case timeUp
        case results
    }

    struct Guess: Identifiable {
        let id: Int
        let word: String
        let found: Bool
    }

    private(set) var phase: Phase = .menu
    private(set) var category: DevineCategory = .animals
    var duration = 60
    private(set) var word = ""
    private(set) var guesses: [Guess] = []
    private(set) var timeLeft: Double = 60
    private(set) var flash: Bool?
    private(set) var flashAt: Double = 0
    private(set) var clock: Double = 0
    private(set) var isClosed = false
    private(set) var hasHinge = false
    private(set) var onForehead = false

    @ObservationIgnored private var deck: [String] = []
    @ObservationIgnored private var neutral = true
    @ObservationIgnored private var steadyTime: Double = 0
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var countdownTime: Double = 0

    var score: Int { guesses.filter(\.found).count }

    func choose(_ c: DevineCategory) {
        category = c
        let english = Lang.shared.isEnglish
        deck = c.words.map { english ? $0.1 : $0.0 }.shuffled()
        guesses = []
        phase = .ready
        steadyTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func backToMenu() {
        phase = .menu
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        isClosed = closed
        if !closed && phase == .timeUp { phase = .results }
    }

    /// Commencer tout de suite (bouton, ou téléphone sans capteur).
    func startNow() {
        guard phase == .ready else { return }
        startCountdown()
    }

    private func startCountdown() {
        countdownTime = 0
        phase = .countdown(3)
        SoundPlayer.shared.play(.notch)
        Haptics.tap()
    }

    /// Le téléphone tenu sur le front : en paysage, l'écran vers les amis (gravité dans le plan de l'écran).
    func motion(_ r: MotionSensor.Reading) {
        onForehead = abs(r.gz) < 0.45 && abs(r.gx) > 0.7
        switch phase {
        case .ready:
            // Duo : il faut qu'il soit fermé. Puis une seconde immobile sur le front.
            if (isClosed || !hasHinge) && onForehead {
                steadyTime += 1.0 / 30.0
                if steadyTime > 1.0 { startCountdown() }
            } else {
                steadyTime = 0
            }
        case .playing:
            guard clock - flashAt > 0.6 else { return }
            if neutral {
                if r.gz > 0.7 {
                    answer(found: true)
                } else if r.gz < -0.7 {
                    answer(found: false)
                }
            } else if abs(r.gz) < 0.35 {
                neutral = true
            }
        default:
            break
        }
    }

    func answer(found: Bool) {
        guard phase == .playing else { return }
        neutral = false
        nextID += 1
        guesses.append(Guess(id: nextID, word: word, found: found))
        flash = found
        flashAt = clock
        if found {
            SoundPlayer.shared.play(.bell, volume: 0.8)
            Haptics.success()
        } else {
            SoundPlayer.shared.play(.whoosh, volume: 0.7)
            Haptics.warning()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.phase == .playing else { return }
            self.flash = nil
            self.nextWord()
        }
    }

    private func nextWord() {
        if deck.isEmpty {
            let english = Lang.shared.isEnglish
            deck = category.words.map { english ? $0.1 : $0.0 }.filter { w in !guesses.contains { $0.word == w } }.shuffled()
            if deck.isEmpty { deck = category.words.map { english ? $0.1 : $0.0 }.shuffled() }
        }
        word = deck.removeLast()
    }

    func tick(dt: Double) {
        clock += dt
        switch phase {
        case .countdown(let n):
            countdownTime += dt
            if countdownTime >= 1 {
                countdownTime = 0
                if n > 1 {
                    phase = .countdown(n - 1)
                    SoundPlayer.shared.play(.notch)
                    Haptics.tap()
                } else {
                    phase = .playing
                    timeLeft = Double(duration)
                    neutral = true
                    nextWord()
                    SoundPlayer.shared.play(.go)
                }
            }
        case .playing:
            let before = Int(timeLeft.rounded(.up))
            timeLeft = max(0, timeLeft - dt)
            let after = Int(timeLeft.rounded(.up))
            if after != before && after <= 5 && after > 0 { SoundPlayer.shared.play(.clockTick, volume: 0.8) }
            if timeLeft <= 0 {
                flash = nil
                SoundPlayer.shared.play(.stop, volume: 0.9)
                Haptics.success()
                UIApplication.shared.isIdleTimerDisabled = false
                phase = (hasHinge && isClosed) ? .timeUp : .results
            }
        default:
            break
        }
    }
}

// MARK: - Écran

struct DevineView: View {
    @Environment(AppState.self) private var app
    @State private var game = DevineGame()
    @State private var motion = MotionSensor()
    @State private var recorded = false

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            switch game.phase {
            case .menu:
                menu
            case .ready:
                ready
            case .countdown(let n):
                bigText("\(n)", sub: L("Prêts ?"))
            case .playing:
                playing
            case .timeUp:
                bigText(L("Temps écoulé !"), sub: game.hasHinge ? L("Ouvre le Duo pour voir le score") : nil)
            case .results:
                results
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onAppear {
            motion.onReading = { reading in game.motion(reading) }
            motion.start(hz: 30)
        }
        .onDisappear {
            motion.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(ticker) { _ in game.tick(dt: 1.0 / 30.0) }
        .onChange(of: game.phase) { _, phase in
            if (phase == .results || phase == .timeUp) && !recorded {
                recorded = true
                app.recordDevine(score: game.score)
            }
            if phase == .ready { recorded = false }
        }
    }

    private var background: some View {
        Group {
            if game.phase == .playing, let found = game.flash {
                (found ? Theme.go : Color(hex: 0xFF9F1C))
            } else if game.phase == .playing {
                LinearGradient(colors: [game.category.color, game.category.color.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(hex: 0x3B1640), Color(hex: 0x14081A)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .devine)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Text(verbatim: "🤔").font(.system(size: 60)).accessibilityHidden(true)
                Text(L("Qui suis-je ?"))
                    .font(.plie(32))
                Text(L("Pose le téléphone sur ton front : tes amis voient le mot, pas toi. Ils te font deviner. Penche la tête en avant si tu trouves, en arrière pour passer."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if app.devineBest > 0 {
                    Label(L("Record : \(app.devineBest) mots"), systemImage: "trophy.fill")
                        .font(.plie(15, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                Picker(L("Durée"), selection: Binding(get: { game.duration }, set: { game.duration = $0 })) {
                    Text(L("60 s")).tag(60)
                    Text(L("90 s")).tag(90)
                    Text(L("2 min")).tag(120)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(DevineCategory.allCases) { c in
                        Button {
                            game.choose(c)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: c.symbol).font(.system(size: 30, weight: .bold))
                                Text(c.title).font(.plie(18))
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(FoldedPaper(color: c.color, cornerRadius: 22))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            header
            Spacer()
            PostureIcon(posture: .forehead, color: Theme.devine, lineWidth: 4)
                .frame(width: 120, height: 90)
            Text(game.hasHinge ? L("Ferme ton Duo et pose-le sur ton front") : L("Pose le téléphone sur ton front"))
                .font(.plie(26))
                .multilineTextAlignment(.center)
            Text(L("À l'horizontale, l'écran tourné vers tes amis. La partie démarre toute seule."))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(L("Commencer maintenant")) { game.startNow() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 300)
            Spacer()
        }
    }

    private func bigText(_ text: String, sub: String?) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.plie(120))
                .minimumScaleFactor(0.3)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let sub {
                Text(sub).font(.plie(24, weight: .bold)).multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private var playing: some View {
        VStack(spacing: 8) {
            HStack {
                Text(game.category.title).font(.plie(18, weight: .bold)).opacity(0.85)
                Spacer()
                Text("\(Int(game.timeLeft.rounded(.up)))")
                    .font(.plie(30))
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            Spacer()
            if let found = game.flash {
                Text(found ? L("Trouvé !") : L("On passe"))
                    .font(.plie(90))
                    .minimumScaleFactor(0.3)
            } else {
                Text(game.word)
                    .font(.plie(110))
                    .minimumScaleFactor(0.25)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .padding(.horizontal, 20)
            }
            Spacer()
            HStack(spacing: 14) {
                Button(L("Passer")) { game.answer(found: false) }
                    .buttonStyle(GhostButtonStyle())
                Button(L("Trouvé")) { game.answer(found: true) }
                    .buttonStyle(ChunkyButtonStyle(color: .white, textColor: Theme.ink, height: 52))
            }
            .frame(maxWidth: 420)
            .padding(.bottom, 14)
            .opacity(0.8)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                WinIcon(systemName: "star.fill", color: Theme.gold)
                Text(L("\(game.score) mot\(game.score > 1 ? "s" : "") trouvé\(game.score > 1 ? "s" : "")"))
                    .font(.plie(34))
                ShareResultButton(game: L("QUI SUIS-JE ?"), result: L("\(game.score) mots trouvés en \(game.duration) secondes"), accent: Theme.devine)
                VStack(spacing: 6) {
                    ForEach(game.guesses) { g in
                        HStack {
                            Image(systemName: g.found ? "checkmark.circle.fill" : "arrow.uturn.right.circle.fill")
                                .foregroundStyle(g.found ? Theme.go : Color(hex: 0xFF9F1C))
                            Text(g.word).font(.plie(18, weight: .bold))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 480)
                Button(L("Au suivant !")) { game.choose(game.category) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.devine, textColor: Theme.ink))
                    .frame(maxWidth: 420)
                Button(L("Changer de thème")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 420)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}
