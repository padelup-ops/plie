import SwiftUI

extension Theme {
    static let tape = Color(hex: 0xFF4F7B)
}

// MARK: - TAPE-TAPE
//
// Deux joueurs face à face, le téléphone à plat entre eux (sur iPhone Duo : déplié, la charnière au milieu).
// Au top, chacun tape sa moitié le plus de fois possible pendant 10, 20 ou 30 secondes.

@Observable
final class TapeGame {
    enum Phase: Equatable { case menu, countdown, playing, over }

    var phase: Phase = .menu
    var duration = 10
    /// Taps du joueur du bas (0) et du haut (1).
    var taps = [0, 0]
    /// Compte à rebours avant le départ, puis temps de jeu restant.
    var clock: Double = 0
    var paused = false

    var winner: Int? {
        guard phase == .over, taps[0] != taps[1] else { return nil }
        return taps[0] > taps[1] ? 0 : 1
    }

    func start() {
        taps = [0, 0]
        clock = 3
        paused = false
        phase = .countdown
        SoundPlayer.shared.play(.tock, volume: 0.6)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func tick(_ dt: Double) {
        guard !paused else { return }
        switch phase {
        case .countdown:
            let before = Int(ceil(clock))
            clock -= dt
            if clock <= 0 {
                clock = Double(duration)
                phase = .playing
                SoundPlayer.shared.play(.go, volume: 0.8)
                Haptics.tap()
            } else if Int(ceil(clock)) != before {
                SoundPlayer.shared.play(.tock, volume: 0.6)
            }
        case .playing:
            let before = Int(ceil(clock))
            clock -= dt
            if clock <= 0 {
                clock = 0
                phase = .over
                SoundPlayer.shared.play(.buzzer, volume: 0.7)
                UIApplication.shared.isIdleTimerDisabled = false
            } else if clock <= 3, Int(ceil(clock)) != before {
                SoundPlayer.shared.play(.clockTick, volume: 0.7)
            }
        default:
            break
        }
    }

    func tap(_ seat: Int) {
        guard phase == .playing, !paused else { return }
        taps[seat] += 1
        SoundPlayer.shared.play(.pok, volume: 0.25)
    }

    func backToMenu() {
        phase = .menu
        paused = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    static func color(_ seat: Int) -> Color { seat == 0 ? Theme.duelsA : Theme.duelsB }
}

struct TapeView: View {
    @Environment(AppState.self) private var app
    @State private var game = TapeGame()

    var body: some View {
        ZStack {
            Color(hex: 0x0B0D1E).ignoresSafeArea()
            if game.phase == .menu {
                menu
            } else {
                board
            }
        }
        .foregroundStyle(.white)
        .onFrame { dt in game.tick(dt) }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { app.recordTape(best: max(game.taps[0], game.taps[1]), seconds: game.duration) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Menu

    private var menu: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    IconButton(symbol: "chevron.left", label: L("Retour")) { app.route = .hub }
                    HowToButton(game: .tape)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                HStack(spacing: -10) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(Theme.duelsB)
                        .rotationEffect(.degrees(180))
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(Theme.duelsA)
                }
                .font(.system(size: 64, weight: .bold))
                .accessibilityHidden(true)
                Text(L("TAPE-TAPE"))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .tracking(3)
                Text(L("À deux, chacun sa moitié : tape le plus de fois possible avant la fin du chrono."))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(L("Durée"))
                    .font(.plie(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    ForEach([10, 20, 30], id: \.self) { n in
                        Button {
                            game.duration = n
                        } label: {
                            Text(L("\(n) s"))
                                .font(.plie(18, weight: .heavy))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(game.duration == n ? Theme.tape : Color.white.opacity(0.1)))
                                .foregroundStyle(game.duration == n ? Theme.ink : .white)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityAddTraits(game.duration == n ? [.isSelected] : [])
                    }
                }
                .frame(maxWidth: 360)

                if let best = app.tapeBest[game.duration], best > 0 {
                    Text(L("Record : \(best) tapes"))
                        .font(.plie(15, weight: .heavy))
                        .foregroundStyle(Theme.gold)
                }

                Button {
                    game.start()
                } label: {
                    Label(L("C'est parti !"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.tape, textColor: Theme.ink, height: 60))
                .frame(maxWidth: 380)
                Text(L("Posez le téléphone à plat entre vous deux : chacun sa moitié."))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Le plateau

    private var board: some View {
        ZStack {
            FaceToFace { seat in
                TapeHalf(game: game, seat: seat)
            }
            if game.phase == .playing && !game.paused {
                VStack(spacing: 0) {
                    MultiTapPad { game.tap(1) }
                    MultiTapPad { game.tap(0) }
                }
                .ignoresSafeArea()
            }
            if game.phase != .over {
                HStack {
                    HingeButton(symbol: game.paused ? "play.fill" : "pause.fill", label: L("Pause")) { game.paused.toggle() }
                        .padding(.leading, 10)
                    Spacer()
                }
            }
            if game.paused {
                VStack(spacing: 12) {
                    Text(L("Pause")).font(.paperTitle(28))
                    Button {
                        game.paused = false
                    } label: {
                        Label(L("Reprendre"), systemImage: "play.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.tape, textColor: Theme.ink, height: 54))
                    Button(L("Quitter la partie")) { game.backToMenu() }
                        .buttonStyle(GhostButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: 320)
                .winCard(accent: Theme.tape)
            }
        }
    }
}

/// La moitié d'un joueur : son compteur, le chrono, puis le résultat.
struct TapeHalf: View {
    let game: TapeGame
    let seat: Int

    private var color: Color { TapeGame.color(seat) }
    private var mine: Int { game.taps[seat] }
    private var theirs: Int { game.taps[1 - seat] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B0D1E), color.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            // La barre de progression : ma part des taps.
            GeometryReader { proxy in
                let total = max(1, mine + theirs)
                let share = game.phase == .countdown ? 0.5 : Double(mine) / Double(total)
                Rectangle()
                    .fill(color.opacity(0.22))
                    .frame(height: proxy.size.height * share)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.easeOut(duration: 0.15), value: share)
            }
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                switch game.phase {
                case .countdown:
                    Text(L("Prêts ?"))
                        .font(.plie(22, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                    Text("\(Int(ceil(game.clock)))")
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .monospacedDigit()
                case .playing:
                    Text(L("\(Int(ceil(game.clock))) s"))
                        .font(.plie(22, weight: .heavy))
                        .foregroundStyle(game.clock <= 3 ? Theme.coral : Theme.muted)
                        .monospacedDigit()
                    Text("\(mine)")
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(L("Tape !"))
                        .font(.plie(20, weight: .heavy))
                        .foregroundStyle(color)
                default:
                    result
                }
                Spacer(minLength: 0)
                if game.phase == .over && seat == 0 {
                    HStack(spacing: 10) {
                        Button {
                            game.start()
                        } label: {
                            Label(L("Rejouer"), systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.tape, textColor: Theme.ink, height: 50))
                        Button(L("Menu")) { game.backToMenu() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var result: some View {
        if let w = game.winner {
            Image(systemName: w == seat ? "trophy.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(w == seat ? Theme.gold : Theme.muted)
            Text(w == seat ? L("Gagné !") : L("Perdu…"))
                .font(.system(size: 44, weight: .black, design: .rounded))
        } else {
            Text(L("Égalité !"))
                .font(.system(size: 44, weight: .black, design: .rounded))
        }
        Text(L("\(mine) tapes"))
            .font(.plie(26, weight: .heavy))
            .foregroundStyle(color)
        Text("\(mine) – \(theirs)")
            .font(.plie(18, weight: .bold))
            .foregroundStyle(Theme.muted)
            .monospacedDigit()
    }
}
