import SwiftUI

extension Theme {
    static let magie = Color(hex: 0xB44BFF)
}

// MARK: - MAGIE
//
// Trois tours qui n'existent que grâce aux deux écrans du Duo :
// • Télépathie : le spectateur choisit une carte sur l'écran intérieur ; l'écran extérieur, tourné vers
//   le magicien, la lui souffle discrètement.
// • La pièce qui traverse : on fait « passer » une pièce à travers le téléphone en le fermant.
// • La prédiction : une enveloppe scellée sur l'écran extérieur, un calcul libre à l'intérieur… 1089.

enum MagieTrick: String, CaseIterable, Identifiable {
    case telepathy, coin, prediction
    var id: String { rawValue }

    var title: String {
        switch self {
        case .telepathy: return L("Télépathie")
        case .coin: return L("La pièce qui traverse")
        case .prediction: return L("La prédiction")
        }
    }

    var pitch: String {
        switch self {
        case .telepathy: return L("Le spectateur choisit une carte en secret. Tu la devines.")
        case .coin: return L("Une pièce passe à travers le téléphone.")
        case .prediction: return L("Ta prédiction était scellée depuis le début.")
        }
    }

    var symbol: String {
        switch self {
        case .telepathy: return "brain.head.profile"
        case .coin: return "circle.circle.fill"
        case .prediction: return "envelope.fill"
        }
    }

    /// Le secret, pour le magicien seulement.
    func secret(duo: Bool) -> [String] {
        switch self {
        case .telepathy:
            return duo
                ? [L("Ouvre le Duo et donne-le au spectateur, l'écran intérieur vers lui. Toi, tu te places en face : tu vois l'écran extérieur."),
                   L("Il choisit une carte (ou un nombre) sans te la montrer, puis la mémorise."),
                   L("L'écran extérieur affiche un ciel étoilé… et, en tout petit en bas à gauche, sa carte. Ne la regarde que d'un coup d'œil !"),
                   L("Fais durer le suspense : « Je vois du rouge… un chiffre impair… » puis annonce la carte.")]
                : [L("Donne le téléphone au spectateur : il choisit une carte (ou un nombre) sans te la montrer."),
                   L("Quand il te rend le téléphone, l'écran montre une lune dans la brume."),
                   L("Appuie longtemps sur la lune : sa carte y apparaît, très pâle, pendant une seconde."),
                   L("Fais durer le suspense, puis annonce la carte.")]
        case .coin:
            return duo
                ? [L("Montre la pièce posée sur l'écran intérieur. Annonce : « Je vais la faire passer à travers le téléphone. »"),
                   L("Touche-la trois fois, en disant une formule magique. Au troisième coup, elle s'enfonce dans l'écran."),
                   L("Ferme le Duo : la pièce tombe sur l'écran extérieur, avec le bruit."),
                   L("Rouvre-le : l'écran intérieur est vide. Elle a traversé !")]
                : [L("Montre la pièce. Touche-la trois fois : elle s'enfonce dans l'écran."),
                   L("Cache l'écran de la main, souffle dessus, puis touche n'importe où : la pièce réapparaît sous ton doigt.")]
        case .prediction:
            return duo
                ? [L("Ferme le Duo et montre l'écran extérieur : une enveloppe scellée, ta prédiction."),
                   L("Ouvre le Duo et donne-le au spectateur. Il choisit librement un nombre à 3 chiffres et suit les calculs."),
                   L("Le secret : quel que soit le nombre, le calcul (inverser, soustraire, inverser, additionner) donne toujours 1089."),
                   L("À la fin, ferme le Duo : l'enveloppe s'ouvre sur… 1089.")]
                : [L("Montre l'enveloppe scellée en haut de l'écran : ta prédiction."),
                   L("Le spectateur choisit un nombre à 3 chiffres et suit les calculs. Le résultat est toujours 1089."),
                   L("À la fin, touche l'enveloppe : elle s'ouvre sur 1089.")]
        }
    }
}

struct PlayingCard: Equatable {
    let value: Int
    let suit: Int

    static let values = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    static let suits = ["♠", "♥", "♦", "♣"]

    var label: String { Self.values[value] + Self.suits[suit] }
    var red: Bool { suit == 1 || suit == 2 }

    static func randomHand(_ n: Int) -> [PlayingCard] {
        var all: [PlayingCard] = []
        for s in 0..<4 { for v in 0..<13 { all.append(PlayingCard(value: v, suit: s)) } }
        return Array(all.shuffled().prefix(n))
    }
}

@Observable
final class MagieShow {
    var trick: MagieTrick?
    var isClosed = false
    var hasHinge = false

    // Télépathie
    var hand = PlayingCard.randomHand(12)
    var chosenCard: PlayingCard?
    var chosenNumber = ""
    var useNumber = false
    var telepathyStage = 0

    // La pièce
    var coinTaps = 0
    var coinStage = 0
    var coinSpot = CGPoint(x: 0.5, y: 0.5)
    @ObservationIgnored private var sunkAt = Date.distantPast

    // La prédiction
    var predictionStage = 0
    var typed = ""
    var steps: [Int] = []

    var secretText: String {
        useNumber ? chosenNumber : (chosenCard?.label ?? "")
    }

    func reset(_ t: MagieTrick?) {
        trick = t
        hand = PlayingCard.randomHand(12)
        chosenCard = nil
        chosenNumber = ""
        telepathyStage = 0
        coinTaps = 0
        coinStage = 0
        predictionStage = 0
        typed = ""
        steps = []
    }

    func setClosed(_ closed: Bool) {
        guard closed != isClosed else { return }
        isClosed = closed
        if closed {
            if trick == .coin && coinStage == 3 {
                coinStage = 4
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    SoundPlayer.shared.play(.clack, volume: 0.9)
                    Haptics.success()
                }
            }
            if trick == .prediction && predictionStage == 2 { predictionStage = 3 }
        } else {
            if trick == .coin && coinStage == 4 { coinStage = 5 }
            if trick == .prediction && predictionStage == 0 { predictionStage = 1 }
        }
    }

    // MARK: Pièce

    func tapCoin() {
        guard coinStage < 3 else { return }
        coinTaps += 1
        SoundPlayer.shared.play(.tock, volume: 0.7)
        Haptics.tap()
        if coinTaps >= 3 {
            coinStage = 3
            sunkAt = Date()
            SoundPlayer.shared.play(.whoosh, volume: 0.7)
        } else {
            coinStage = coinTaps
        }
    }

    /// Sans charnière : la pièce réapparaît sous le doigt.
    func reappear(at p: CGPoint) {
        // Le toucher qui a fait disparaître la pièce ne compte pas.
        guard coinStage == 3, !hasHinge, Date().timeIntervalSince(sunkAt) > 0.8 else { return }
        coinSpot = p
        coinStage = 6
        SoundPlayer.shared.play(.clack, volume: 0.9)
        Haptics.success()
    }

    // MARK: Prédiction

    func pressDigit(_ d: Int) {
        guard predictionStage == 1, steps.isEmpty, typed.count < 3 else { return }
        if typed.isEmpty && d == 0 { return }
        typed += String(d)
        Haptics.tap()
    }

    func deleteDigit() {
        guard !typed.isEmpty, steps.isEmpty else { return }
        typed.removeLast()
    }

    /// Le nombre doit avoir 3 chiffres, et le premier différent du dernier.
    var typedIsValid: Bool {
        let ds = Array(typed)
        return ds.count == 3 && ds[0] != ds[2]
    }

    func compute() {
        guard typedIsValid, let n = Int(typed) else { return }
        let reversed = Int(String(String(format: "%03d", n).reversed())) ?? 0
        let diff = abs(n - reversed)
        let diffReversed = Int(String(String(format: "%03d", diff).reversed())) ?? 0
        steps = [n, reversed, diff, diffReversed, diff + diffReversed]
        SoundPlayer.shared.play(.chime, volume: 0.6)
    }

    func finishCalculation() {
        predictionStage = 2
    }
}

// MARK: - Écran

struct MagieView: View {
    @Environment(AppState.self) private var app
    @State private var show = MagieShow()
    @State private var camera = GuessersCamera()
    @State private var cameraOn = false
    @State private var outerEnabled = false
    @State private var outerAvailable = false
    @State private var secretOpen: MagieTrick?

    var body: some View {
        ZStack {
            MagieCurtain()
            switch show.trick {
            case nil:
                menu
            case .telepathy?:
                MagieTelepathyView(show: show, twoScreens: outerAvailable && cameraOn, onBack: back)
            case .coin?:
                if show.isClosed { MagieCoinOuter(show: show) } else { MagieCoinView(show: show, onBack: back) }
            case .prediction?:
                if show.isClosed { MagieEnvelope(show: show) } else { MagiePredictionView(show: show, onBack: back) }
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            show.hasHinge = true
            show.setClosed(degrees < 20)
        }
        .onChange(of: show.trick) { _, trick in
            if trick == .telepathy {
                outerEnabled = true
                camera.start { ok in cameraOn = ok }
            } else {
                outerEnabled = false
                camera.stop()
            }
            if trick != nil { app.recordMagie() }
        }
        .onDisappear { camera.stop() }
        // Télépathie : l'écran extérieur souffle la carte au magicien.
        .outerScreen(isEnabled: $outerEnabled, onAvailabilityChange: { outerAvailable = $0 }) {
            MagieSecretSky(show: show)
        }
        .sheet(item: $secretOpen) { trick in secretSheet(trick) }
    }

    private func back() {
        show.reset(nil)
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                    HowToButton(game: .magie)
                    Spacer()
                }
                .padding(.top, 8)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.gold, Theme.magie], startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                Text(L("MAGIE")).font(.plie(42))
                Text(L("Trois tours à faire devant tes amis. Lis d'abord le secret, en cachette !"))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                ForEach(MagieTrick.allCases) { trick in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: trick.symbol).font(.system(size: 26, weight: .bold)).frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trick.title).font(.plie(20))
                                Text(trick.pitch)
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    .opacity(0.85)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 10) {
                            Button {
                                secretOpen = trick
                            } label: {
                                Label(L("Le secret"), systemImage: "eye.slash.fill")
                            }
                            .buttonStyle(GhostButtonStyle())
                            Button {
                                show.reset(trick)
                            } label: {
                                Label(L("Faire le tour"), systemImage: "wand.and.stars")
                            }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 52))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.35)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private func secretSheet(_ trick: MagieTrick) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    IconButton(symbol: "xmark", label: L("Fermer")) { secretOpen = nil }
                }
                Label(L("Secret du magicien"), systemImage: "eye.slash.fill")
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.magie)
                Text(trick.title).font(.plie(30))
                ForEach(Array(trick.secret(duo: show.hasHinge || DuoSupport.apisAvailable).enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(item.offset + 1)")
                            .font(.plie(16))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.magie))
                        Text(item.element)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(L("Compris, à moi de jouer !")) {
                    secretOpen = nil
                    show.reset(trick)
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 56))
            }
            .padding(22)
        }
        .foregroundStyle(.white)
        .background(Theme.ink.ignoresSafeArea())
    }
}

/// Barre du haut des tours : retour seulement (pas de texte qui trahirait le tour).
struct MagieTopBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            IconButton(symbol: "chevron.left", label: L("Retour"), action: onBack)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Télépathie

struct MagieTelepathyView: View {
    let show: MagieShow
    let twoScreens: Bool
    let onBack: () -> Void
    @State private var peek = false

    var body: some View {
        VStack(spacing: 16) {
            MagieTopBar(onBack: onBack)
            switch show.telepathyStage {
            case 0: choose
            case 1: memorize
            default: mist
            }
        }
    }

    private var choose: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L("Choisis en secret…")).font(.plie(28))
                Picker("", selection: Binding(get: { show.useNumber }, set: { show.useNumber = $0 })) {
                    Text(L("Une carte")).tag(false)
                    Text(L("Un nombre")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                if show.useNumber {
                    MagieKeypad(text: show.chosenNumber, maxDigits: 2) { d in
                        if show.chosenNumber.count < 2 && !(show.chosenNumber.isEmpty && d == 0) { show.chosenNumber += String(d) }
                    } onDelete: {
                        if !show.chosenNumber.isEmpty { show.chosenNumber.removeLast() }
                    }
                    Button(L("C'est mon nombre")) { show.telepathyStage = 1 }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 54))
                        .frame(maxWidth: 320)
                        .disabled(show.chosenNumber.isEmpty)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                        ForEach(Array(show.hand.enumerated()), id: \.offset) { item in
                            Button {
                                show.chosenCard = item.element
                                show.telepathyStage = 1
                                Haptics.tap()
                            } label: {
                                MagieCardView(card: item.element)
                                    .frame(height: 120)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(item.element.label)
                        }
                    }
                    .frame(maxWidth: 640)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var memorize: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(L("Mémorise-la bien. Ne dis rien !")).font(.plie(24))
            if show.useNumber {
                Text(verbatim: show.chosenNumber).font(.system(size: 120, weight: .black, design: .rounded))
            } else if let card = show.chosenCard {
                MagieCardView(card: card).frame(width: 180, height: 260)
            }
            Button(L("C'est bon, je l'ai en tête")) {
                withAnimation(.easeInOut(duration: 0.6)) { show.telepathyStage = 2 }
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 56))
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var mist: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF6D8), Color(hex: 0xC9C2E8)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 110))
                    .frame(width: 180, height: 180)
                    .shadow(color: Color(hex: 0xC9C2E8).opacity(0.7), radius: 40)
                if peek {
                    Text(verbatim: show.secretText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x8A84A8).opacity(0.75))
                }
            }
            // Sans écran extérieur : le magicien appuie longtemps sur la lune pour voir la carte.
            .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 50, pressing: { _ in }, perform: {
                guard !twoScreens else { return }
                peek = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { peek = false }
            })
            .accessibilityHidden(true)
            Text(L("Concentre-toi sur ta pensée…")).font(.plie(26))
            Text(L("Le magicien va lire dans ton esprit."))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button(L("Recommencer")) { show.reset(.telepathy) }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 280)
                .padding(.bottom, 20)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
    }
}

/// L'écran extérieur, tourné vers le magicien : un ciel étoilé, et la carte en tout petit.
struct MagieSecretSky: View {
    let show: MagieShow

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MagieCurtain(starsOnly: true)
            VStack {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 70))
                    .foregroundStyle(Theme.gold.opacity(0.8))
                Text(L("Magie en cours…"))
                    .font(.plie(22))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            if show.trick == .telepathy && show.telepathyStage >= 1 && !show.secretText.isEmpty {
                Text(verbatim: show.secretText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(18)
            }
        }
    }
}

// MARK: - La pièce qui traverse

struct MagieCoinView: View {
    let show: MagieShow
    let onBack: () -> Void

    var body: some View {
        GeometryReader { g in
            ZStack {
                VStack {
                    MagieTopBar(onBack: onBack)
                    Spacer()
                }
                Group {
                    switch show.coinStage {
                    case 0, 1, 2:
                        MagieCoin()
                            .frame(width: 170, height: 170)
                            .rotationEffect(.degrees(Double(show.coinTaps) * 12 * (show.coinTaps % 2 == 0 ? -1 : 1)))
                            .scaleEffect(1 - CGFloat(show.coinTaps) * 0.06)
                            .animation(.spring(response: 0.25, dampingFraction: 0.4), value: show.coinTaps)
                            .onTapGesture { show.tapCoin() }
                            .accessibilityLabel(L("La pièce"))
                            .accessibilityAddTraits(.isButton)
                    case 3:
                        // La pièce s'est enfoncée : il ne reste qu'un remous.
                        Circle()
                            .stroke(Theme.gold.opacity(0.4), lineWidth: 3)
                            .frame(width: 60, height: 60)
                            .transition(.scale.combined(with: .opacity))
                    case 6:
                        MagieCoin()
                            .frame(width: 150, height: 150)
                            .position(x: show.coinSpot.x, y: show.coinSpot.y)
                            .transition(.scale)
                    default:
                        // Rouverte : la pièce n'est plus là, seulement une petite trace.
                        Ellipse()
                            .fill(RadialGradient(colors: [Color.black.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 60))
                            .frame(width: 140, height: 80)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: show.coinStage)
                VStack {
                    Spacer()
                    Text(caption)
                        .font(.plie(22))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if show.coinStage >= 5 {
                        Button(L("Recommencer")) { show.reset(.coin) }
                            .buttonStyle(GhostButtonStyle())
                            .frame(maxWidth: 280)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, max(24, g.safeAreaInsets.bottom))
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { v in show.reappear(at: v.location) }
            )
        }
    }

    private var caption: String {
        switch show.coinStage {
        case 0: return L("Touche la pièce trois fois…")
        case 1, 2: return L("Encore…")
        case 3: return show.hasHinge ? L("Elle est passée dans le téléphone ! Ferme le Duo…") : L("Elle a disparu… Cache l'écran, puis touche où tu veux.")
        case 6: return L("La revoilà !")
        default: return L("Elle a traversé le téléphone !")
        }
    }
}

/// Duo fermé : la pièce tombe sur l'écran extérieur.
struct MagieCoinOuter: View {
    let show: MagieShow
    @State private var landed = false

    var body: some View {
        ZStack {
            MagieCurtain()
            if show.coinStage >= 4 {
                MagieCoin()
                    .frame(width: 140, height: 140)
                    .offset(y: landed ? 40 : -600)
                    .rotationEffect(.degrees(landed ? 0 : -90))
                    .onAppear {
                        withAnimation(.interpolatingSpring(stiffness: 120, damping: 9).delay(0.1)) { landed = true }
                    }
                    .accessibilityLabel(L("La pièce"))
            } else {
                Text(L("Rien ici…"))
                    .font(.plie(22))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct MagieCoin: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xFFE38A), Color(hex: 0xE0A21A), Color(hex: 0xB97A0A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color(hex: 0xFFF2C2).opacity(0.8), lineWidth: 6).padding(10)
            Image(systemName: "star.fill")
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(Color(hex: 0xB97A0A).opacity(0.7))
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .compositingGroup()
    }
}

// MARK: - La prédiction

struct MagiePredictionView: View {
    let show: MagieShow
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MagieTopBar(onBack: onBack)
                if show.predictionStage == 0 {
                    // Avant le calcul : la prédiction est déjà scellée.
                    MagieEnvelopeCard(open: false)
                        .frame(width: 260, height: 170)
                    Text(show.hasHinge ? L("Ferme le Duo pour montrer la prédiction scellée, puis rouvre-le.")
                                       : L("Ma prédiction est scellée dans cette enveloppe."))
                        .font(.plie(20))
                        .multilineTextAlignment(.center)
                    Button(L("Commencer")) { show.predictionStage = 1 }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 56))
                        .frame(maxWidth: 320)
                } else if show.steps.isEmpty {
                    Text(L("Choisis un nombre à 3 chiffres, le premier différent du dernier."))
                        .font(.plie(22))
                        .multilineTextAlignment(.center)
                    MagieKeypad(text: show.typed, maxDigits: 3, onDigit: show.pressDigit, onDelete: show.deleteDigit)
                    Button(L("Calculer")) { show.compute() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 54))
                        .frame(maxWidth: 320)
                        .disabled(!show.typedIsValid)
                } else {
                    calculation
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var calculation: some View {
        let s = show.steps
        return VStack(spacing: 12) {
            row(L("Ton nombre"), String(format: "%03d", s[0]))
            row(L("À l'envers"), String(format: "%03d", s[1]))
            row(L("Le plus grand moins le plus petit"), String(format: "%03d", s[2]))
            row(L("Ce résultat à l'envers"), String(format: "%03d", s[3]))
            row(L("Additionne les deux"), "\(s[4])", big: true)
            if show.predictionStage == 1 {
                Button(show.hasHinge ? L("Ferme le Duo et ouvre la prédiction !") : L("Ouvrir la prédiction")) {
                    show.finishCalculation()
                    if !show.hasHinge { show.predictionStage = 3 }
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.magie, textColor: .white, height: 56))
                .frame(maxWidth: 380)
            } else if show.predictionStage == 2 {
                Text(L("Ferme le Duo pour ouvrir l'enveloppe…")).font(.plie(20))
            } else {
                MagieEnvelopeCard(open: true)
                    .frame(width: 260, height: 220)
                Button(L("Recommencer")) { show.reset(.prediction) }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 280)
            }
        }
    }

    private func row(_ label: String, _ value: String, big: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            Text(verbatim: value).font(.system(size: big ? 40 : 28, weight: .black, design: .rounded)).monospacedDigit()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.3)))
    }
}

/// Duo fermé : l'enveloppe scellée, qui s'ouvre à la fin du calcul.
struct MagieEnvelope: View {
    let show: MagieShow

    var body: some View {
        ZStack {
            MagieCurtain()
            if show.predictionStage >= 3 {
                ConfettiView().ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 18) {
                Text(show.predictionStage >= 3 ? L("Je le savais !") : L("Ma prédiction"))
                    .font(.plie(30))
                MagieEnvelopeCard(open: show.predictionStage >= 3)
                    .frame(width: 280, height: show.predictionStage >= 3 ? 240 : 180)
                Text(show.predictionStage >= 3 ? " " : L("Ne pas ouvrir avant la fin"))
                    .font(.plie(16, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onChange(of: show.predictionStage) { _, stage in
            if stage == 3 {
                SoundPlayer.shared.play(.win, volume: 0.8)
                Haptics.success()
            }
        }
    }
}

struct MagieEnvelopeCard: View {
    let open: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFF3DC), Color(hex: 0xE9D3A8)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            if open {
                Text(verbatim: "1089")
                    .font(.system(size: 70, weight: .black, design: .serif))
                    .foregroundStyle(Color(hex: 0x6A1B2E))
                    .transition(.scale.combined(with: .opacity))
            } else {
                GeometryReader { g in
                    Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: g.size.width / 2, y: g.size.height * 0.55))
                        p.addLine(to: CGPoint(x: g.size.width, y: 0))
                    }
                    .stroke(Color(hex: 0xC9A970), lineWidth: 2)
                }
                Circle()
                    .fill(Color(hex: 0xB0182A))
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xFFD27A)))
                    .offset(y: 8)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: open)
        .accessibilityLabel(open ? L("La prédiction : 1089") : L("Une enveloppe scellée"))
    }
}

// MARK: - Éléments communs

struct MagieCardView: View {
    let card: PlayingCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
            VStack(spacing: 2) {
                Text(verbatim: PlayingCard.values[card.value]).font(.system(size: 30, weight: .black, design: .serif))
                Text(verbatim: PlayingCard.suits[card.suit]).font(.system(size: 34))
            }
            .foregroundStyle(card.red ? Color(hex: 0xD62839) : Color(hex: 0x1A1A2E))
        }
        .aspectRatio(0.7, contentMode: .fit)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct MagieKeypad: View {
    let text: String
    let maxDigits: Int
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: text.isEmpty ? String(repeating: "–", count: maxDigits) : text)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .monospacedDigit()
                .frame(height: 70)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, -2, 0, -1], id: \.self) { key in
                    if key == -2 {
                        Color.clear.frame(height: 58)
                    } else {
                        Button {
                            if key < 0 { onDelete() } else { onDigit(key) }
                        } label: {
                            Group {
                                if key < 0 {
                                    Image(systemName: "delete.left.fill").font(.system(size: 22, weight: .bold))
                                } else {
                                    Text(verbatim: "\(key)").font(.system(size: 28, weight: .black, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(key < 0 ? L("Effacer") : "\(key)")
                    }
                }
            }
            .frame(maxWidth: 320)
        }
    }
}

/// Fond de scène : rideau violet profond et quelques étoiles. Dessiné une fois.
struct MagieCurtain: View {
    var starsOnly = false

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: starsOnly ? [Color(hex: 0x05061A), Color(hex: 0x0E1235)] : [Color(hex: 0x2A0B45), Color(hex: 0x12051F)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            if !starsOnly {
                // Plis du rideau
                for k in 0..<12 {
                    let x = size.width * CGFloat(k) / 11
                    context.fill(Path(CGRect(x: x - 14, y: 0, width: 28, height: size.height)),
                                 with: .linearGradient(Gradient(colors: [.clear, Color.black.opacity(0.25), .clear]),
                                                       startPoint: CGPoint(x: x - 14, y: 0), endPoint: CGPoint(x: x + 14, y: 0)))
                }
            }
            for i in 0..<50 {
                let x = CGFloat(Draw.hash(i, 81)) * size.width
                let y = CGFloat(Draw.hash(i, 82)) * size.height
                let r = CGFloat(1 + Draw.hash(i, 83) * 2)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.2 + 0.5 * Draw.hash(i, 84))))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
