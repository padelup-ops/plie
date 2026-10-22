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
        .onDisappear { game.shutdown() }
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
            GameHeader(title: "1, 2, 3… SOLEIL !", subtitle: "Le téléphone fait l'arbitre", onBack: {
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
                        step("1", "Pose le téléphone debout à l'autre bout de la pièce, la caméra tournée vers les joueurs.")
                        step("2", "Tout le monde part du fond. Quand la voix dit « soleil », on se fige.")
                        step("3", "Le téléphone voit qui bouge : photo, et retour au départ.")
                        step("4", "Le premier qui arrive appuie sur « Touché ! » et gagne.")
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))

                    VStack(spacing: 10) {
                        SectionTitle(text: "Sévérité de l'arbitre")
                        Picker("Sévérité", selection: Binding(get: { game.sensitivity }, set: { game.sensitivity = $0 })) {
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
                        Label("Lancer la partie", systemImage: "play.fill")
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
                    Text("Tous les joueurs doivent être dans le cadre")
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
                    Text("L'arbitre a besoin de la caméra pour voir qui bouge.")
                        .font(.plie(16, weight: .bold))
                        .multilineTextAlignment(.center)
                    Button("Ouvrir les Réglages") {
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
                    Text("Signal sur l'écran extérieur")
                        .font(.plie(17, weight: .bold))
                    Text("Les joueurs voient AVANCEZ / STOP sur l'écran extérieur. Toi, tu vois la caméra et l'arbitre sur l'écran intérieur.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.sun)
            if game.useOuterScreen {
                Label(game.outerAvailable ? "Écran extérieur prêt" : "Ouvre le Duo et garde Plié en plein écran",
                      systemImage: game.outerAvailable ? "checkmark.circle.fill" : "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(game.outerAvailable ? Theme.go : Theme.gold)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
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
                    IconButton(symbol: "xmark", label: "Arrêter la partie") { game.backToSetup() }
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
                IconButton(symbol: "xmark", label: "Arrêter la partie") { game.backToSetup() }
                Spacer()
                Pill(text: formatSeconds(game.elapsed), color: Theme.card)
                Pill(text: "\(game.catches) pris", color: Theme.card)
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
                Text("Le téléphone bouge : pose-le bien droit.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
            Text("Les joueurs voient le signal sur l'écran extérieur. Le gagnant touche « Touché ! » de son côté.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Déclarer un gagnant") { game.win() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(16)
    }

    // MARK: Fin

    private var wonView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .padding(.top, 30)
                Text("On a un gagnant !")
                    .font(.plie(34))
                Text("Partie en \(formatSeconds(game.elapsed)) · \(game.catches) joueur\(game.catches > 1 ? "s" : "") pris en flagrant délit")
                    .font(.plie(16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                if !game.snapshots.isEmpty {
                    SectionTitle(text: "Les flagrants délits")
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
                                              preview: SharePreview("Pris en flagrant délit", image: Image(uiImage: item.element))) {
                                        Label("Partager", systemImage: "square.and.arrow.up")
                                            .font(.plie(14, weight: .bold))
                                    }
                                }
                            }
                        }
                    }
                    Text("Ces photos restent dans l'app le temps de la partie. Elles ne sont partagées que si tu appuies sur « Partager ».")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }

                Button {
                    game.start()
                } label: {
                    Label("Rejouer", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.sun, height: 60))
                Button("Changer les réglages") { game.backToSetup() }
                    .buttonStyle(GhostButtonStyle())
                Button("Retour aux jeux") {
                    game.shutdown()
                    app.route = .hub
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Le signal (AVANCEZ / STOP)

struct SoleilSignal: View {
    let game: SoleilGame
    let large: Bool

    var body: some View {
        ZStack {
            color
            VStack(spacing: large ? 12 : 2) {
                Text(title)
                    .font(.plie(large ? 92 : 28))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
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
        case .go: return "AVANCEZ !"
        case .freezing, .stop: return "STOP !"
        case .caught: return "BOUGÉ !"
        case .won: return "GAGNÉ !"
        case .setup: return "Prêts ?"
        }
    }

    private var subtitle: String? {
        switch game.phase {
        case .countdown: return "Placez-vous au fond de la pièce"
        case .go: return "Avancez pendant que la voix parle"
        case .freezing, .stop: return "On ne bouge plus !"
        case .caught: return "Retour au départ"
        default: return nil
        }
    }
}

struct WinButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("TOUCHÉ ! J'ai gagné", systemImage: "hand.raised.fill")
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
            Text(active ? "Mouvement détecté" : "L'arbitre attend le STOP")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityLabel(active ? "Niveau de mouvement" : "Arbitre en attente")
    }
}

struct CaughtCard: View {
    let image: UIImage
    let catches: Int

    var body: some View {
        VStack(spacing: 10) {
            Text("BOUGÉ !")
                .font(.plie(40))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxHeight: 320)
            Text("Le joueur encadré en rouge retourne au départ.")
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
