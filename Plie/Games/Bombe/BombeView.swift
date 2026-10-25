import SwiftUI
import Combine

extension Theme {
    static let bombe = Color(hex: 0xFF4D4D)
}

// MARK: - La bombe
//
// Les joueurs sont en cercle. Duo fermé, l'écran extérieur montre le défi (« un animal »,
// « un mot en B »…) et une mèche qui brûle. On dit un mot, on touche l'écran, on passe le Duo.
// La mèche est cachée : personne ne sait quand ça explose. Après le BOUM, on ouvre le Duo
// pour marquer qui avait la bombe. Trois bombes et c'est perdu.

struct BombeChallenge: Equatable {
    let text: String
}

enum BombeDeck {
    /// Thèmes, en français et en anglais.
    static let themes: [(String, String)] = [
        ("Un animal", "An animal"), ("Un fruit ou un légume", "A fruit or vegetable"), ("Un pays", "A country"),
        ("Un prénom", "A first name"), ("Un métier", "A job"), ("Une couleur", "A color"), ("Un sport", "A sport"),
        ("Un objet de la cuisine", "Something in the kitchen"), ("Quelque chose qui vole", "Something that flies"),
        ("Quelque chose de froid", "Something cold"), ("Un instrument de musique", "A musical instrument"),
        ("Quelque chose qu'on trouve à la plage", "Something you find at the beach"), ("Un vêtement", "A piece of clothing"),
        ("Un moyen de transport", "A way to travel"), ("Une partie du corps", "A part of the body"),
        ("Quelque chose de rond", "Something round"), ("Un dessert", "A dessert"), ("Une ville", "A city"),
        ("Un animal de la mer", "A sea animal"), ("Quelque chose qui fait du bruit", "Something noisy"),
        ("Un jouet", "A toy"), ("Quelque chose de rouge", "Something red"), ("Un super-pouvoir", "A superpower"),
        ("Un mot qui rime avec « eau »", "A word that rhymes with \"day\""), ("Quelque chose dans une école", "Something in a school")
    ]

    static let lettersFR = Array("ABCDEFGHIJLMNOPRSTV").map(String.init)
    static let lettersEN = Array("ABCDEFGHIJLMNOPRSTW").map(String.init)

    static func draw(lettersOnly: Bool) -> BombeChallenge {
        let english = Lang.shared.isEnglish
        if lettersOnly || Bool.random() && Int.random(in: 0..<3) == 0 {
            let letter = (english ? lettersEN : lettersFR).randomElement() ?? "A"
            return BombeChallenge(text: L("Un mot qui commence par \(letter)"))
        }
        let theme = themes.randomElement() ?? themes[0]
        return BombeChallenge(text: english ? theme.1 : theme.0)
    }
}

@Observable
final class BombeGame {
    enum Phase: Equatable {
        case menu
        /// La bombe est prête : on ferme le Duo (ou on touche « Allumer »).
        case armed
        case ticking
        case boom
        /// Qui avait la bombe ?
        case blame
        case over
    }

    private(set) var phase: Phase = .menu
    private(set) var names: [String] = []
    private(set) var strikes: [Int] = []
    private(set) var challenge = BombeChallenge(text: "")
    private(set) var passes = 0
    private(set) var clock: Double = 0
    private(set) var boomAt: Double = 0
    private(set) var isClosed = false
    private(set) var hasHinge = false
    private(set) var loser: Int?
    var lettersOnly = false
    static let maxStrikes = 3

    @ObservationIgnored private var fuseLength: Double = 20
    @ObservationIgnored private var startedAt: Double = 0
    @ObservationIgnored private var lastTick: Double = 0

    var burned: Double {
        guard phase == .ticking else { return phase == .boom || phase == .blame ? 1 : 0 }
        return min(1, (clock - startedAt) / fuseLength)
    }

    func start(players: Int) {
        names = (0..<players).map { L("Joueur \($0 + 1)") }
        strikes = Array(repeating: 0, count: players)
        loser = nil
        arm()
    }

    func backToMenu() {
        phase = .menu
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func arm() {
        challenge = BombeDeck.draw(lettersOnly: lettersOnly)
        passes = 0
        phase = .armed
        UIApplication.shared.isIdleTimerDisabled = true
        if isClosed { light() }
    }

    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        if closed && phase == .armed { light() }
        if !closed && phase == .boom { phase = .blame }
    }

    /// Allume la mèche : entre 12 et 40 secondes, personne ne sait combien.
    func light() {
        guard phase == .armed else { return }
        fuseLength = Double.random(in: 12...40)
        startedAt = clock
        lastTick = clock
        phase = .ticking
        SoundPlayer.shared.play(.go, volume: 0.6)
        Haptics.tap()
    }

    /// Le joueur a dit son mot : il touche l'écran et passe la bombe.
    func pass() {
        guard phase == .ticking else { return }
        passes += 1
        SoundPlayer.shared.play(.whoosh, volume: 0.6)
        Haptics.tap()
    }

    func tick(dt: Double) {
        clock += dt
        guard phase == .ticking else { return }
        let left = fuseLength - (clock - startedAt)
        // Le tic-tac accélère, sans dire combien il reste.
        let interval = max(0.18, min(0.9, left / 18))
        if clock - lastTick > interval {
            lastTick = clock
            SoundPlayer.shared.play(.clockTick, volume: 0.7)
        }
        if left <= 0 {
            phase = .boom
            boomAt = clock
            SoundPlayer.shared.play(.boom, volume: 1)
            Haptics.error()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Haptics.error() }
            if !hasHinge || !isClosed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                    if self?.phase == .boom { self?.phase = .blame }
                }
            }
        }
    }

    func blame(_ player: Int) {
        guard phase == .blame, strikes.indices.contains(player) else { return }
        strikes[player] += 1
        SoundPlayer.shared.play(.wrong, volume: 0.6)
        if strikes[player] >= Self.maxStrikes {
            loser = player
            phase = .over
            UIApplication.shared.isIdleTimerDisabled = false
            SoundPlayer.shared.play(.applause, volume: 0.6)
            return
        }
        arm()
    }
}

// MARK: - Écran

struct BombeView: View {
    @Environment(AppState.self) private var app
    @State private var game = BombeGame()
    @State private var players = 4

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2A0E0E), Color(hex: 0x120606)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch game.phase {
            case .menu: menu
            case .armed: armed
            case .ticking: BombeFuseView(game: game)
            case .boom: boom
            case .blame: blame
            case .over: over
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onReceive(ticker) { _ in game.tick(dt: 1.0 / 30.0) }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordBombe() }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .bombe)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                BombeDrawing(burned: 0, clock: 0).frame(width: 140, height: 140)
                Text(L("La bombe")).font(.plie(34))
                Text(L("Mettez-vous en cercle. Dis un mot du thème, touche l'écran et passe le Duo fermé à ton voisin, vite ! Personne ne sait quand la bombe explose."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Stepper(value: $players, in: 3...8) {
                    Label(L("\(players) joueurs"), systemImage: "person.3.fill")
                        .font(.plie(18, weight: .bold))
                }
                .frame(maxWidth: 340)
                Toggle(isOn: Binding(get: { game.lettersOnly }, set: { game.lettersOnly = $0 })) {
                    Text(L("Seulement des lettres (plus dur)")).font(.plie(16, weight: .bold))
                }
                .tint(Theme.bombe)
                .frame(maxWidth: 340)
                Button {
                    game.start(players: players)
                } label: {
                    Label(L("Préparer la bombe"), systemImage: "flame.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bombe, height: 60))
                .frame(maxWidth: 380)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var armed: some View {
        VStack(spacing: 18) {
            header
            Spacer()
            Text(game.challenge.text)
                .font(.plie(36))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if game.hasHinge {
                PostureIcon(posture: .closed, color: Theme.bombe, lineWidth: 4).frame(width: 110, height: 70)
                Text(L("Ferme le Duo pour allumer la mèche"))
                    .font(.plie(20, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            Button {
                game.light()
            } label: {
                Label(L("Allumer la mèche"), systemImage: "flame.fill")
            }
            .buttonStyle(ChunkyButtonStyle(color: Theme.bombe, height: 60))
            .frame(maxWidth: 360)
            Spacer()
        }
    }

    private var boom: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let age = max(0, game.clock - game.boomAt)
            ZStack {
                RadialGradient(colors: [Color(hex: 0xFFE08A), Color(hex: 0xFF5B1A), Color(hex: 0x3A0A0A)],
                               center: .center, startRadius: 0, endRadius: 200 + CGFloat(age) * 400)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    Text(L("BOUM !"))
                        .font(.plie(110))
                        .minimumScaleFactor(0.3)
                        .scaleEffect(1 + 0.15 * CGFloat(sin(age * 20)) * CGFloat(max(0, 1 - age)))
                    Text(game.hasHinge && game.isClosed ? L("Celui qui tient le Duo l'a eue ! Ouvre-le pour noter.") : L("Celui qui tient le téléphone l'a eue !"))
                        .font(.plie(20, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private var blame: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Text(L("Qui avait la bombe ?")).font(.plie(30))
                Text(L("\(game.passes) passes avant le BOUM"))
                    .font(.plie(16, weight: .bold))
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(game.names.indices, id: \.self) { i in
                        Button {
                            game.blame(i)
                        } label: {
                            VStack(spacing: 6) {
                                Text(game.names[i]).font(.plie(20))
                                HStack(spacing: 4) {
                                    ForEach(0..<BombeGame.maxStrikes, id: \.self) { k in
                                        Image(systemName: k < game.strikes[i] ? "flame.fill" : "circle")
                                            .foregroundStyle(k < game.strikes[i] ? Theme.bombe : .white.opacity(0.4))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(L("\(game.names[i]), \(game.strikes[i]) bombes"))
                    }
                }
                .padding(.horizontal, 16)
                Text(L("Touche le joueur qui avait la bombe. Trois bombes et c'est perdu."))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var over: some View {
        VStack(spacing: 16) {
            header
            Spacer()
            Text(verbatim: "💥").font(.system(size: 80)).accessibilityHidden(true)
            if let l = game.loser {
                Text(L("\(game.names[l]) a perdu !")).font(.plie(34))
            }
            Text(L("Tous les autres ont gagné. Une revanche ?"))
                .font(.plie(18, weight: .bold))
                .foregroundStyle(Theme.muted)
            Button(L("Revanche")) { game.start(players: game.names.count) }
                .buttonStyle(ChunkyButtonStyle(color: Theme.bombe, height: 58))
                .frame(maxWidth: 360)
            Button(L("Changer de joueurs")) { game.backToMenu() }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: 360)
            Spacer()
        }
    }
}

/// Ce que voient les joueurs pendant que la mèche brûle (Duo fermé : l'écran extérieur).
struct BombeFuseView: View {
    let game: BombeGame

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            VStack(spacing: 14) {
                Text(game.challenge.text)
                    .font(.plie(34))
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                BombeDrawing(burned: game.burned, clock: game.clock)
                    .frame(maxWidth: 240, maxHeight: 240)
                Text(L("\(game.passes) passes"))
                    .font(.plie(16, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Button {
                    game.pass()
                } label: {
                    Label(L("J'ai dit mon mot, je passe !"), systemImage: "arrow.uturn.right")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink, height: 70))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

/// La bombe dessinée, avec sa mèche et l'étincelle.
struct BombeDrawing: View {
    let burned: Double
    let clock: Double

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height * 0.58)
            let r = s * 0.32
            let shake = burned > 0.7 ? CGFloat(sin(clock * 60)) * s * 0.01 * CGFloat(burned) : 0
            let body = CGRect(x: c.x - r + shake, y: c.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: body), with: .radialGradient(Gradient(colors: [Color(hex: 0x5A5A6A), Color(hex: 0x15151C)]),
                                                                     center: CGPoint(x: body.midX - r * 0.35, y: body.midY - r * 0.35),
                                                                     startRadius: 0, endRadius: r * 1.4))
            context.fill(Path(ellipseIn: CGRect(x: body.midX - r * 0.55, y: body.midY - r * 0.6, width: r * 0.4, height: r * 0.25)), with: .color(.white.opacity(0.35)))
            // Le col
            let neck = CGRect(x: c.x - r * 0.25 + shake, y: c.y - r * 1.12, width: r * 0.5, height: r * 0.3)
            context.fill(Path(roundedRect: neck, cornerRadius: 3), with: .color(Color(hex: 0x3A3A48)))
            // La mèche (de plus en plus courte… mais on ne sait pas de combien)
            let start = CGPoint(x: neck.midX, y: neck.minY)
            var fuse = Path()
            fuse.move(to: start)
            fuse.addQuadCurve(to: CGPoint(x: start.x + s * 0.22, y: start.y - s * 0.2), control: CGPoint(x: start.x + s * 0.02, y: start.y - s * 0.22))
            let visible = 0.35 + 0.65 * (1 - min(1, burned * 0.5))
            context.stroke(fuse.trimmedPath(from: 0, to: CGFloat(visible)), with: .color(Color(hex: 0xC8A46A)), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
            // L'étincelle au bout
            if burned > 0 && burned < 1 {
                let tip = fuse.trimmedPath(from: CGFloat(visible) - 0.001, to: CGFloat(visible)).currentPoint ?? start
                let flick = 0.7 + 0.3 * sin(clock * 37)
                context.fill(Path(ellipseIn: CGRect(x: tip.x - s * 0.08, y: tip.y - s * 0.08, width: s * 0.16, height: s * 0.16)),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF3B0).opacity(flick), Color(hex: 0xFF7A1A).opacity(0.6 * flick), .clear]),
                                                   center: tip, startRadius: 0, endRadius: s * 0.08))
                for k in 0..<6 {
                    let a = Double(k) * 1.05 + clock * 9
                    let d = s * CGFloat(0.05 + 0.04 * abs(sin(clock * 13 + Double(k))))
                    context.fill(Path(ellipseIn: CGRect(x: tip.x + CGFloat(cos(a)) * d - 1.5, y: tip.y + CGFloat(sin(a)) * d - 1.5, width: 3, height: 3)),
                                 with: .color(Color(hex: 0xFFD25A)))
                }
            }
        }
        .accessibilityLabel(L("Une bombe dont la mèche brûle"))
    }
}
