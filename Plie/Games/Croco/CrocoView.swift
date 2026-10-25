import SwiftUI

extension Theme {
    static let croco = Color(hex: 0x4CD964)
}

// MARK: - CROCO
//
// Le Duo est la gueule d'un crocodile : la charnière, c'est sa mâchoire.
// Fermé, le croco dort (écran extérieur). On lui ouvre la gueule (on ouvre le Duo) :
// en haut les dents du haut, en bas les dents du bas. Chacun son tour, on appuie sur une dent…
// et l'une d'elles fait claquer la mâchoire : CROC !

@Observable
final class CrocoGame {
    enum Phase: Equatable {
        case menu
        /// Le croco dort : il faut lui ouvrir la gueule (ouvrir le Duo).
        case asleep
        case playing
        case chomp
        case over
    }

    static let teethPerJaw = 6

    private(set) var phase: Phase = .menu
    private(set) var names: [String] = []
    private(set) var lives: [Int] = []
    private(set) var current = 0
    private(set) var pressed: Set<Int> = []
    private(set) var isClosed = false
    private(set) var hasHinge = false
    private(set) var suspense = false
    /// Seul : nombre de dents appuyées sans se faire croquer.
    private(set) var streak = 0
    private(set) var loser: Int?
    var playerCount = 3
    var startLives = 1

    @ObservationIgnored private var badTooth = 0
    @ObservationIgnored private var generation = 0

    var toothCount: Int { Self.teethPerJaw * 2 }
    var solo: Bool { names.count == 1 }
    var alive: [Int] { lives.indices.filter { lives[$0] > 0 } }

    static func playerName(_ i: Int) -> String { L("Joueur \(i + 1)") }

    func start() {
        names = (0..<playerCount).map(Self.playerName)
        lives = Array(repeating: playerCount == 1 ? 1 : startLives, count: playerCount)
        current = 0
        streak = 0
        loser = nil
        newMouth()
    }

    func backToMenu() {
        generation += 1
        phase = .menu
    }

    #if DEBUG
    func demoSetBadTooth(_ tooth: Int) { badTooth = tooth }
    #endif

    private func newMouth() {
        generation += 1
        seenClosed = isClosed
        pressed = []
        suspense = false
        badTooth = Int.random(in: 0..<toothCount)
        // Duo ouvert : on le fait fermer d'abord, le croco dort. Sans charnière : on joue tout de suite.
        phase = hasHinge ? .asleep : .playing
    }

    func setClosed(_ closed: Bool, fromHinge: Bool) {
        if fromHinge { hasHinge = true }
        guard closed != isClosed else { return }
        isClosed = closed
        switch phase {
        case .asleep where !closed && seenClosed:
            // On ouvre la gueule
            phase = .playing
            SoundPlayer.shared.play(.clunk, volume: 0.5)
            Haptics.tap()
        case .chomp where closed:
            // Le croco referme sa gueule et digère : la manche suivante commence quand on rouvre.
            continueAfterChomp()
        default:
            break
        }
        if closed { seenClosed = true }
    }

    @ObservationIgnored private var seenClosed = false

    /// Sans charnière (ou pour aller vite) : ouvrir la gueule avec un bouton.
    func openMouth() {
        guard phase == .asleep else { return }
        phase = .playing
        SoundPlayer.shared.play(.clunk, volume: 0.5)
    }

    func press(_ tooth: Int) {
        guard phase == .playing, !suspense, !pressed.contains(tooth) else { return }
        pressed.insert(tooth)
        suspense = true
        SoundPlayer.shared.play(.tock, volume: 0.8)
        Haptics.tap()
        let gen = generation
        if tooth == badTooth {
            // Un instant de silence… puis CROC !
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.25...0.6)) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.chomp()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.suspense = false
                if self.solo {
                    self.streak += 1
                    // Toutes les bonnes dents trouvées : nouvelle gueule, on continue.
                    if self.pressed.count == self.toothCount - 1 {
                        SoundPlayer.shared.play(.bloom, volume: 0.7)
                        Haptics.success()
                        self.pressed = []
                        self.badTooth = Int.random(in: 0..<self.toothCount)
                    }
                } else {
                    self.nextPlayer()
                }
            }
        }
    }

    private func chomp() {
        phase = .chomp
        suspense = false
        loser = current
        lives[current] -= 1
        SoundPlayer.shared.play(.chomp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { SoundPlayer.shared.play(.roar, volume: 0.7) }
        Haptics.chomp()
    }

    /// Après le CROC : manche suivante, ou fin de partie.
    func continueAfterChomp() {
        guard phase == .chomp else { return }
        if solo {
            phase = .over
            return
        }
        if alive.count <= 1 {
            phase = .over
            SoundPlayer.shared.play(.applause, volume: 0.6)
            return
        }
        // Celui qui s'est fait croquer recommence (s'il a encore des vies), sinon le suivant.
        if lives[current] <= 0 { nextPlayer() }
        newMouth()
    }

    private func nextPlayer() {
        guard !alive.isEmpty else { return }
        var i = current
        repeat { i = (i + 1) % names.count } while lives[i] <= 0
        current = i
    }

    var winner: Int? { alive.count == 1 ? alive.first : nil }
}

// MARK: - Écran

struct CrocoView: View {
    @Environment(AppState.self) private var app
    @State private var game = CrocoGame()

    var body: some View {
        ZStack {
            switch game.phase {
            case .menu:
                menu
            case .asleep:
                if game.isClosed { CrocoAsleep(game: game) } else { closeFirst }
            case .playing, .chomp:
                if game.isClosed { CrocoAsleep(game: game) } else { CrocoMouth(game: game) }
            case .over:
                over
            }
        }
        .foregroundStyle(.white)
        .onHingeAngle { degrees in
            guard let degrees else { return }
            game.setClosed(degrees < 20, fromHinge: true)
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordCroco(streak: game.solo ? game.streak : -1) }
        }
        .onAppear {
            #if DEBUG
            Demo.schedule("croco", [
                (0.0, { game.playerCount = 2; game.start(); game.demoSetBadTooth(9) }),
                (3.9, { game.press(2) }), (4.6, { game.press(8) }), (5.3, { game.press(3) }), (6.0, { game.press(9) })
            ])
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "chevron.left", label: L("Retour")) {
                if game.phase == .menu { app.route = .hub } else { game.backToMenu() }
            }
            HowToButton(game: .croco)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var menu: some View {
        ZStack {
            CrocoSwamp()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    CrocoHead(open: 0.35, blink: false)
                        .frame(width: 260, height: 170)
                    Text(L("CROCO")).font(.plie(44))
                    Text(L("Le Duo est la gueule du croco. Ouvre-la, appuie sur une dent chacun son tour… et gare à celle qui le fait mordre !"))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    Stepper(value: Binding(get: { game.playerCount }, set: { game.playerCount = $0 }), in: 1...6) {
                        Label(game.playerCount == 1 ? L("Seul : record de dents") : L("\(game.playerCount) joueurs"), systemImage: "person.3.fill")
                            .font(.plie(18, weight: .bold))
                    }
                    .frame(maxWidth: 360)
                    if game.playerCount > 1 {
                        Picker(L("Vies"), selection: Binding(get: { game.startLives }, set: { game.startLives = $0 })) {
                            Text(L("1 vie")).tag(1)
                            Text(L("3 vies")).tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }
                    if game.playerCount == 1 && app.crocoBest > 0 {
                        Text(L("Ton record : \(app.crocoBest) dents"))
                            .font(.plie(16, weight: .bold))
                            .foregroundStyle(Theme.gold)
                    }
                    Button {
                        game.start()
                    } label: {
                        Label(L("Jouer"), systemImage: "play.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.croco, textColor: Theme.ink, height: 60))
                    .frame(maxWidth: 380)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Duo ouvert au début : on le ferme d'abord, le croco s'endort.
    private var closeFirst: some View {
        ZStack {
            CrocoSwamp()
            VStack(spacing: 18) {
                header
                Spacer()
                PostureIcon(posture: .closed, color: Theme.croco, lineWidth: 4)
                    .frame(width: 120, height: 80)
                Text(L("Ferme le Duo : le croco ferme sa gueule."))
                    .font(.plie(26))
                    .multilineTextAlignment(.center)
                Text(L("Puis ouvre-la doucement pour voir ses dents."))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button(L("Ouvrir sans fermer")) { game.openMouth() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 280)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private var over: some View {
        ZStack {
            CrocoSwamp()
            VStack(spacing: 16) {
                header
                Spacer()
                CrocoHead(open: 0.15, blink: false)
                    .frame(width: 220, height: 140)
                if game.solo {
                    Text(L("\(game.streak) dents !")).font(.plie(40))
                    Text(game.streak >= app.crocoBest && game.streak > 0 ? L("Nouveau record !") : L("Ton record : \(app.crocoBest) dents"))
                        .font(.plie(18, weight: .bold))
                        .foregroundStyle(Theme.gold)
                } else if let w = game.winner {
                    Text(L("\(game.names[w]) gagne !")).font(.plie(38))
                    Text(L("Le croco n'a pas réussi à le croquer."))
                        .font(.plie(17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Button(L("Rejouer")) { game.start() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.croco, textColor: Theme.ink, height: 58))
                    .frame(maxWidth: 360)
                Button(L("Menu")) { game.backToMenu() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: 360)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - La gueule ouverte (écran intérieur)

struct CrocoMouth: View {
    let game: CrocoGame
    @State private var snap: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let n = CrocoGame.teethPerJaw
            let toothW = min(size.width / CGFloat(n) * 0.82, size.height * 0.16)
            let toothH = toothW * 1.25
            let gum = size.height * 0.12
            // Pendant le CROC, les deux mâchoires se rejoignent au milieu (la charnière).
            let travel = (size.height / 2 - gum - toothH * 0.4) * snap
            ZStack {
                // Le fond de la gorge
                RadialGradient(colors: [Color(hex: 0x3A0710), Color(hex: 0x7A1424), Color(hex: 0xB4283C)],
                               center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.6)
                // La langue, sur la mâchoire du bas
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0xFF7A8A), Color(hex: 0xE04A63)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size.width * 0.55, height: size.height * 0.24)
                    .position(x: size.width / 2, y: size.height * 0.68)
                // Mâchoire du haut
                jaw(top: true, size: size, n: n, toothW: toothW, toothH: toothH, gum: gum)
                    .offset(y: travel)
                // Mâchoire du bas
                jaw(top: false, size: size, n: n, toothW: toothW, toothH: toothH, gum: gum)
                    .offset(y: -travel)
                // Le joueur dont c'est le tour
                VStack {
                    HStack(spacing: 10) {
                        IconButton(symbol: "chevron.left", label: L("Retour")) { game.backToMenu() }
                        HowToButton(game: .croco)
                        Spacer()
                        livesBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, max(gum + 4, proxy.safeAreaInsets.top))
                    Spacer()
                    status
                        .padding(.bottom, gum + toothH * 0.2 + max(8, proxy.safeAreaInsets.bottom))
                }
                if game.phase == .chomp {
                    chompOverlay
                }
            }
            .frame(width: size.width, height: size.height)
            .modifier(BoiteShake(animatableData: snap * 3))
        }
        .ignoresSafeArea()
        .onChange(of: game.phase) { _, phase in
            if phase == .chomp {
                withAnimation(.easeIn(duration: 0.12)) { snap = 1 }
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { snap = 0 }
            }
        }
    }

    private func jaw(top: Bool, size: CGSize, n: Int, toothW: CGFloat, toothH: CGFloat, gum: CGFloat) -> some View {
        let spacing = size.width / CGFloat(n)
        return ZStack {
            // La gencive
            RoundedRectangle(cornerRadius: gum * 0.5, style: .continuous)
                .fill(LinearGradient(colors: top ? [Color(hex: 0x2E8B3E), Color(hex: 0xE86A7E)] : [Color(hex: 0xE86A7E), Color(hex: 0x2E8B3E)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size.width + 40, height: gum * 1.6)
                .position(x: size.width / 2, y: top ? gum * 0.3 : size.height - gum * 0.3)
            ForEach(0..<n, id: \.self) { k in
                let tooth = top ? k : n + k
                let down = game.pressed.contains(tooth)
                let x = spacing * (CGFloat(k) + 0.5)
                let baseY = top ? gum + toothH / 2 : size.height - gum - toothH / 2
                CrocoTooth(pointsDown: top, pressed: down)
                    .frame(width: toothW, height: toothH)
                    .position(x: x, y: baseY + (down ? (top ? -toothH * 0.55 : toothH * 0.55) : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: down)
                    .onTapGesture { game.press(tooth) }
                    .accessibilityElement()
                    .accessibilityLabel(top ? L("Dent du haut \(k + 1)") : L("Dent du bas \(k + 1)"))
                    .accessibilityValue(down ? L("enfoncée") : "")
                    .accessibilityAddTraits(down ? [] : [.isButton])
            }
        }
    }

    private var livesBar: some View {
        HStack(spacing: 6) {
            if game.solo {
                Label("\(game.streak)", systemImage: "hand.point.up.fill")
                    .font(.plie(18))
            } else {
                ForEach(game.names.indices, id: \.self) { i in
                    HStack(spacing: 2) {
                        Text(verbatim: "\(i + 1)").font(.plie(14))
                        ForEach(0..<max(0, game.lives[i]), id: \.self) { _ in
                            Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.coral)
                        }
                    }
                    .opacity(game.lives[i] > 0 ? 1 : 0.35)
                    .padding(.horizontal, 7)
                    .frame(height: 30)
                    .background(Capsule().fill(i == game.current ? Theme.croco.opacity(0.5) : Color.black.opacity(0.3)))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.solo ? L("\(game.streak) dents") : L("Tour de \(game.names[game.current])"))
    }

    private var status: some View {
        Text(game.solo ? L("Appuie sur une dent…") : L("\(game.names[game.current]), appuie sur une dent…"))
            .font(.plie(22))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .opacity(game.phase == .playing ? 1 : 0)
    }

    private var chompOverlay: some View {
        ZStack {
            Color.red.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L("CROC !"))
                    .font(.system(size: 90, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                if let l = game.loser {
                    Text(game.solo ? L("Croqué ! \(game.streak) dents") : L("\(game.names[l]) s'est fait croquer !"))
                        .font(.plie(24))
                        .multilineTextAlignment(.center)
                }
                Text(game.hasHinge ? L("Ferme le Duo : le croco referme sa gueule.") : " ")
                    .font(.plie(17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Button(game.solo ? L("Voir mon score") : L("Continuer")) { game.continueAfterChomp() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.croco, textColor: Theme.ink, height: 54))
                    .frame(maxWidth: 300)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.55)))
            .padding(24)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct CrocoTooth: View {
    let pointsDown: Bool
    let pressed: Bool

    var body: some View {
        CrocoToothShape(pointsDown: pointsDown)
            .fill(LinearGradient(colors: pressed ? [Color(hex: 0xD8D2BE), Color(hex: 0xB8B09A)] : [.white, Color(hex: 0xF1EBD8)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(CrocoToothShape(pointsDown: pointsDown).stroke(Color(hex: 0x8E866E).opacity(0.6), lineWidth: 2))
            .contentShape(Rectangle())
    }
}

struct CrocoToothShape: Shape {
    let pointsDown: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = pointsDown ? rect.minY : rect.maxY
        let tipY = pointsDown ? rect.maxY : rect.minY
        p.move(to: CGPoint(x: rect.minX, y: baseY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: tipY), control: CGPoint(x: rect.minX + rect.width * 0.1, y: (baseY + tipY) / 2 + (tipY - baseY) * 0.25))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: baseY), control: CGPoint(x: rect.maxX - rect.width * 0.1, y: (baseY + tipY) / 2 + (tipY - baseY) * 0.25))
        p.closeSubpath()
        return p
    }
}

// MARK: - Duo fermé : le croco dort (écran extérieur)

struct CrocoAsleep: View {
    let game: CrocoGame

    var body: some View {
        ZStack {
            CrocoSwamp()
            VStack(spacing: 16) {
                Spacer()
                CrocoHead(open: 0, blink: true)
                    .frame(width: 280, height: 170)
                Text(game.phase == .chomp ? L("Miam… le croco digère.") : L("Chut, le croco dort…"))
                    .font(.plie(26))
                    .multilineTextAlignment(.center)
                Text(game.phase == .chomp ? L("Rouvre le Duo pour la manche suivante.") : L("Ouvre-lui la gueule : ouvre le Duo !"))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }
}

/// La tête du croco, de profil. `open` (0…1) : la gueule entrouverte.
struct CrocoHead: View {
    let open: CGFloat
    let blink: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !blink)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width, h = size.height
                let green = Color(hex: 0x3FAE4F), dark = Color(hex: 0x2A7A36), belly = Color(hex: 0xC8E68A)
                let angle = Double(open) * 0.35
                let hinge = CGPoint(x: w * 0.78, y: h * 0.55)
                // Mâchoire du bas
                var lower = context
                lower.translateBy(x: hinge.x, y: hinge.y)
                lower.rotate(by: .radians(angle))
                lower.fill(Path(roundedRect: CGRect(x: -w * 0.74, y: 0, width: w * 0.78, height: h * 0.2), cornerRadius: h * 0.1), with: .color(belly))
                for k in 0..<6 {
                    var tooth = Path()
                    let x = -w * 0.68 + CGFloat(k) * w * 0.1
                    tooth.move(to: CGPoint(x: x, y: 0))
                    tooth.addLine(to: CGPoint(x: x + w * 0.03, y: -h * 0.07))
                    tooth.addLine(to: CGPoint(x: x + w * 0.06, y: 0))
                    lower.fill(tooth, with: .color(.white))
                }
                // Mâchoire du haut et tête
                var upper = context
                upper.translateBy(x: hinge.x, y: hinge.y)
                upper.rotate(by: .radians(-angle))
                upper.fill(Path(roundedRect: CGRect(x: -w * 0.76, y: -h * 0.26, width: w * 0.8, height: h * 0.26), cornerRadius: h * 0.12), with: .color(green))
                for k in 0..<6 {
                    var tooth = Path()
                    let x = -w * 0.7 + CGFloat(k) * w * 0.1
                    tooth.move(to: CGPoint(x: x, y: 0))
                    tooth.addLine(to: CGPoint(x: x + w * 0.03, y: h * 0.07))
                    tooth.addLine(to: CGPoint(x: x + w * 0.06, y: 0))
                    upper.fill(tooth, with: .color(.white))
                }
                // Bosses du dos et narine
                for k in 0..<4 {
                    upper.fill(Path(ellipseIn: CGRect(x: -w * 0.5 + CGFloat(k) * w * 0.12, y: -h * 0.32, width: w * 0.08, height: h * 0.1)), with: .color(dark))
                }
                upper.fill(Path(ellipseIn: CGRect(x: -w * 0.74, y: -h * 0.24, width: w * 0.05, height: h * 0.05)), with: .color(dark))
                // L'œil
                let eye = CGRect(x: -w * 0.08, y: -h * 0.48, width: w * 0.16, height: h * 0.24)
                upper.fill(Path(ellipseIn: eye.insetBy(dx: -w * 0.02, dy: -h * 0.02)), with: .color(green))
                let closed = blink && Int(t * 2) % 7 != 0
                if closed {
                    var lid = Path()
                    lid.addArc(center: CGPoint(x: eye.midX, y: eye.midY), radius: eye.width / 2.4, startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
                    upper.stroke(lid, with: .color(dark), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else {
                    upper.fill(Path(ellipseIn: eye), with: .color(Color(hex: 0xFFE14D)))
                    upper.fill(Path(ellipseIn: CGRect(x: eye.midX - eye.width * 0.1, y: eye.minY + 3, width: eye.width * 0.2, height: eye.height - 6)), with: .color(.black))
                }
                // Zzz quand il dort
                if blink {
                    for k in 0..<3 {
                        let phase = (t * 0.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                        context.opacity = 1 - phase
                        context.draw(Text(verbatim: "z").font(.system(size: 18 + CGFloat(k) * 8, weight: .black, design: .rounded)).foregroundColor(.white),
                                     at: CGPoint(x: w * (0.86 + 0.04 * CGFloat(k)), y: h * (0.3 - 0.25 * CGFloat(phase))))
                        context.opacity = 1
                    }
                }
            }
        }
        .accessibilityLabel(blink ? L("Le croco dort") : L("Le croco"))
    }
}

/// Le marais : eau verte, nénuphars. Dessiné une fois.
struct CrocoSwamp: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x0E3B2C), Color(hex: 0x0A5A44), Color(hex: 0x063326)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for i in 0..<9 {
                let x = CGFloat(Draw.hash(i, 51)) * size.width
                let y = CGFloat(Draw.hash(i, 52)) * size.height
                let r = CGFloat(18 + Draw.hash(i, 53) * 26)
                var pad = Path()
                pad.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .degrees(20), endAngle: .degrees(340), clockwise: false)
                pad.addLine(to: CGPoint(x: x, y: y))
                pad.closeSubpath()
                context.fill(pad, with: .color(Color(hex: 0x3FAE4F).opacity(0.45)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
