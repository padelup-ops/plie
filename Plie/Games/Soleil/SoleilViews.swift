import SwiftUI
import UIKit

struct SoleilView: View {
    @Environment(AppState.self) private var app
    @State private var game = SoleilGame()
    @State private var recorded = false

    var body: some View {
        @Bindable var game = game

        ZStack {
            switch game.phase {
            case .setup:
                setupView
            case .won:
                wonView
            default:
                if game.playersUseOuterScreen {
                    hostView
                } else {
                    playersView
                }
            }
        }
        .onHingeAngle { degrees in
            guard degrees != nil, !game.hingeDetected else { return }
            game.hingeDetected = true
            // Sur iPhone Duo, on propose d'office le signal sur l'écran extérieur.
            if DuoSupport.apisAvailable && game.phase == .setup {
                Task { await game.setUseOuterScreen(true) }
            }
        }
        .onChange(of: game.outerAvailable) { _, _ in
            Task { await game.syncCamera() }
        }
        .task { await game.prepareCamera() }
        .onAppear { MusicPlayer.shared.duck(true) }
        .onDisappear {
            game.shutdown()
            MusicPlayer.shared.duck(false)
        }
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .won && !recorded {
                recorded = true
                app.recordSoleilGame()
            }
            if newPhase == .setup { recorded = false }
        }
        // Sur iPhone Duo ouvert, le signal s'affiche sur l'écran extérieur, face aux joueurs.
        .outerScreen(isEnabled: $game.outerEnabled,
                     onAvailabilityChange: { game.outerAvailable = $0 }) {
            SoleilOuterView(game: game)
        }
    }

    // MARK: Préparation

    private var setupView: some View {
        VStack(spacing: 0) {
            GameHeader(title: L("1, 2, 3… SOLEIL !"), subtitle: L("Le téléphone fait l'arbitre"), onBack: {
                game.shutdown()
                app.route = .hub
            }) {
                EmptyView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 18) {
                    previewCard

                    VStack(alignment: .leading, spacing: 10) {
                        step("1", L("Pose le téléphone debout à l'autre bout de la pièce, la caméra tournée vers les joueurs."))
                        step("2", L("Tout le monde part du fond. Quand la voix dit « soleil », on se fige."))
                        step("3", L("Le téléphone voit qui bouge : photo, et retour au départ."))
                        step("4", L("Le premier qui arrive appuie sur « Touché ! » et gagne."))
                    }
                    .padding(16)
                    .background(GlassPanel(cornerRadius: 20))

                    VStack(spacing: 10) {
                        SectionTitle(text: L("Sévérité de l'arbitre"))
                        Picker(L("Sévérité"), selection: Binding(get: { game.sensitivity }, set: { game.sensitivity = $0 })) {
                            ForEach(SoleilSensitivity.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(game.sensitivity.detail)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if game.hingeDetected && DuoSupport.apisAvailable {
                        duoCard
                    }

                    Button {
                        game.start()
                    } label: {
                        Label(L("Lancer la partie"), systemImage: "play.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.sun, height: 62))
                    .disabled(!game.cameraReady)
                    .opacity(game.cameraReady ? 1 : 0.5)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black)
            if game.cameraAllowed {
                CameraPreview(session: game.camera.session, readyToken: game.cameraToken)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack {
                    Spacer()
                    Text(L("Tous les joueurs doivent être dans le cadre"))
                        .font(.plie(14, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(12)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.sun)
                    Text(L("L'arbitre a besoin de la caméra pour voir qui bouge."))
                        .font(.plie(16, weight: .bold))
                        .multilineTextAlignment(.center)
                    Button(L("Ouvrir les Réglages")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .padding(20)
            }
        }
        .frame(height: 280)
    }

    private var duoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { game.useOuterScreen },
                                 set: { value in Task { await game.setUseOuterScreen(value) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Signal sur l'écran extérieur"))
                        .font(.plie(17, weight: .bold))
                    Text(L("Les joueurs voient AVANCEZ / STOP sur l'écran extérieur. Toi, tu vois la caméra et l'arbitre sur l'écran intérieur."))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.sun)
            if game.useOuterScreen {
                Label(game.outerAvailable ? L("Écran extérieur prêt") : L("Ouvre le Duo et garde Origamo en plein écran"),
                      systemImage: game.outerAvailable ? "checkmark.circle.fill" : "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(game.outerAvailable ? Theme.go : Theme.gold)
            }
        }
        .padding(16)
        .background(GlassPanel(cornerRadius: 20))
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.plie(15))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.sun))
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Pendant la partie, écran face aux joueurs

    private var playersView: some View {
        ZStack {
            SoleilSignal(game: game, large: true)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    IconButton(symbol: "xmark", label: L("Arrêter la partie")) { game.backToSetup() }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        CameraPreview(session: game.camera.session, readyToken: game.cameraToken)
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        MotionMeter(level: game.motionLevel, active: game.phase == .stop)
                            .frame(width: 96)
                    }
                }
                Spacer()
                WinButton { game.win() }
                    .frame(maxWidth: 520)
            }
            .padding(16)

            if game.phase == .caught, let snapshot = game.lastSnapshot {
                CaughtCard(image: snapshot, catches: game.catches)
                    .padding(20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: game.phase)
    }

    // MARK: Pendant la partie, iPhone Duo : écran de l'arbitre

    private var hostView: some View {
        VStack(spacing: 14) {
            HStack {
                IconButton(symbol: "xmark", label: L("Arrêter la partie")) { game.backToSetup() }
                Spacer()
                Pill(text: formatSeconds(game.elapsed), color: Theme.card)
                Pill(text: L("\(game.catches) pris"), color: Theme.card)
            }
            ZStack(alignment: .top) {
                CameraPreview(session: game.camera.session, readyToken: game.cameraToken)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                SoleilSignal(game: game, large: false)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(10)
                if game.phase == .caught, let snapshot = game.lastSnapshot {
                    CaughtCard(image: snapshot, catches: game.catches)
                        .padding(20)
                        .frame(maxHeight: .infinity)
                }
            }
            MotionMeter(level: game.motionLevel, active: game.phase == .stop)
            if game.unstable {
                Text(L("Le téléphone bouge : pose-le bien droit."))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
            Text(L("Les joueurs voient le signal sur l'écran extérieur. Le gagnant touche « Touché ! » de son côté."))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button(L("Déclarer un gagnant")) { game.win() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(16)
    }

    // MARK: Fin

    private var wonView: some View {
        ScrollView {
            VStack(spacing: 18) {
                WinIcon(systemName: "trophy.fill", color: Theme.gold)
                    .padding(.top, 30)
                Text(L("On a un gagnant !"))
                    .font(.plie(34))
                Text(L("Partie en \(formatSeconds(game.elapsed)) · \(game.catches) joueur\(game.catches > 1 ? "s" : "") pris en flagrant délit"))
                    .font(.plie(16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                if !game.snapshots.isEmpty {
                    SectionTitle(text: L("Les flagrants délits"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(game.snapshots.enumerated()), id: \.offset) { item in
                                VStack(spacing: 8) {
                                    Image(uiImage: item.element)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    ShareLink(item: Image(uiImage: item.element),
                                              preview: SharePreview(L("Pris en flagrant délit"), image: Image(uiImage: item.element))) {
                                        Label(L("Partager"), systemImage: "square.and.arrow.up")
                                            .font(.plie(14, weight: .bold))
                                    }
                                }
                            }
                        }
                    }
                    Text(L("Ces photos restent dans l'app le temps de la partie. Elles ne sont partagées que si tu appuies sur « Partager »."))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }

                Button {
                    game.start()
                } label: {
                    Label(L("Rejouer"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sun, height: 60))
                Button(L("Changer les réglages")) { game.backToSetup() }
                    .buttonStyle(GhostButtonStyle())
                Button(L("Retour aux jeux")) {
                    game.shutdown()
                    app.route = .hub
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) { ConfettiView().frame(height: 600) }
    }
}

// MARK: - Le signal (AVANCEZ / STOP)

struct SoleilSignal: View {
    let game: SoleilGame
    let large: Bool

    var body: some View {
        ZStack {
            color
            // Rayons de soleil qui tournent doucement derrière le texte
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let reach = max(size.width, size.height)
                    for k in 0..<12 {
                        let a = Double(k) * .pi / 6 + t * 0.15
                        var ray = Path()
                        ray.move(to: c)
                        ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - 0.11)) * reach, y: c.y + CGFloat(sin(a - 0.11)) * reach))
                        ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + 0.11)) * reach, y: c.y + CGFloat(sin(a + 0.11)) * reach))
                        ray.closeSubpath()
                        context.fill(ray, with: .color(.white.opacity(0.06)))
                    }
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .radialGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.25)]),
                                                       center: c, startRadius: 0, endRadius: reach * 0.6))
                }
            }
            .allowsHitTesting(false)
            VStack(spacing: large ? 12 : 2) {
                Text(title)
                    .font(.plie(large ? 92 : 28))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                if large, let subtitle {
                    Text(subtitle)
                        .font(.plie(24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .animation(.easeOut(duration: 0.12), value: game.phase)
    }

    private var color: Color {
        switch game.phase {
        case .go: return Theme.go
        case .freezing, .stop: return Theme.stop
        case .caught: return Color(hex: 0x7A1020)
        default: return Theme.ink
        }
    }

    private var title: String {
        switch game.phase {
        case .countdown(let n): return "\(n)"
        case .go: return L("AVANCEZ !")
        case .freezing, .stop: return L("STOP !")
        case .caught: return L("BOUGÉ !")
        case .won: return L("GAGNÉ !")
        case .setup: return L("Prêts ?")
        }
    }

    private var subtitle: String? {
        switch game.phase {
        case .countdown: return L("Placez-vous au fond de la pièce")
        case .go: return L("Avancez pendant que la voix parle")
        case .freezing, .stop: return L("On ne bouge plus !")
        case .caught: return L("Retour au départ")
        default: return nil
        }
    }
}

struct WinButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L("TOUCHÉ ! J'ai gagné"), systemImage: "hand.raised.fill")
        }
        .buttonStyle(ChunkyButtonStyle(color: Theme.gold, textColor: Theme.ink, height: 76))
    }
}

struct MotionMeter: View {
    let level: Double
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let limit = width / 1.5
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.35))
                    Capsule()
                        .fill(level >= 1 ? Theme.stop : Theme.gold)
                        .frame(width: active ? min(width, max(4, width * level / 1.5)) : 0)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: limit)
                }
            }
            .frame(height: 10)
            Text(active ? L("Mouvement détecté") : L("L'arbitre attend le STOP"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityLabel(active ? L("Niveau de mouvement") : L("Arbitre en attente"))
    }
}

struct CaughtCard: View {
    let image: UIImage
    let catches: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(L("BOUGÉ !"))
                .font(.plie(40))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxHeight: 320)
            Text(L("Le joueur encadré en rouge retourne au départ."))
                .font(.plie(16, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x7A1020)))
    }
}

/// Ce que voient les joueurs sur l'écran extérieur de l'iPhone Duo.
struct SoleilOuterView: View {
    let game: SoleilGame

    var body: some View {
        ZStack {
            SoleilSignal(game: game, large: true)
                .ignoresSafeArea()
            if game.phase == .caught, let snapshot = game.lastSnapshot {
                CaughtCard(image: snapshot, catches: game.catches)
                    .padding(16)
            }
            if game.isPlaying && game.phase != .caught {
                VStack {
                    Spacer()
                    WinButton { game.win() }
                        .padding(16)
                }
            }
        }
    }
}
