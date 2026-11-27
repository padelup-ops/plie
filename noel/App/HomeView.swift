// HomeView.swift — Allô Père Noël
//
// Le lancement (le titre qui apparaît dans la nuit) et l'accueil : la nuit du pôle Nord, la lune, la neige,
// le Père Noël dans son médaillon doré, le compte à rebours, et un seul geste principal : préparer l'appel.

import AVKit
import SwiftUI
import UIKit

struct SplashView: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        ZStack {
            NightScene(trees: true)
            Snowfall(count: 70)
            VStack(spacing: 6) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Noel.goldGradient)
                    .rotationEffect(.degrees(-18))
                    .padding(.bottom, 8)
                Text("Allô")
                    .font(.story(34))
                    .foregroundStyle(Noel.goldLight)
                Text("Père Noël")
                    .font(.tale(54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 24)
                    .foregroundStyle(Noel.cream)
                    .shadow(color: Noel.goldLight.opacity(0.5), radius: 18)
            }
            .offset(y: -60)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
        }
        .task {
            withAnimation(.easeOut(duration: 0.9)) { shown = true }
            try? await Task.sleep(for: .milliseconds(1700))
            model.go(.home)
        }
        .accessibilityElement(children: .combine)
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false
    @State private var music = ChristmasMusic.shared
    @State private var greeting = GreetingPlayback()
    @State private var greetingMood: SantaMood = .idle

    var body: some View {
        ZStack {
            NightScene()
            Snowfall()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CountdownChip()
                    Spacer()
                    Button { music.enabled.toggle() } label: {
                        RoundIcon(symbol: music.enabled ? "music.note" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(Text(music.enabled ? "Turn the music off" : "Turn the music on"))
                    Button { model.sheet = .settings } label: { RoundIcon(symbol: "gearshape.fill") }
                        .accessibilityLabel(Text("Settings"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)
                Button {
                    Task { await playGreeting(again: true) }
                } label: {
                    ZStack {
                        if let player = greeting.player {
                            GreetingVideo(player: player)
                                .frame(width: 210, height: 210)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Noel.goldGradient, lineWidth: 7))
                        } else {
                            SantaMedallion(size: 210, mood: greetingMood, mouth: greetingMood == .talking ? model.call.mouth : 0)
                        }
                    }
                    .scaleEffect(appeared ? 1 : 0.94)
                    .opacity(appeared ? 1 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hear Santa's greeting"))
                Spacer(minLength: 18)

                VStack(spacing: 12) {
                    Text("Santa has a message for you…")
                        .font(.tale(34))
                        .foregroundStyle(Noel.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    Text("Prepare a magical moment your child will never forget.")
                        .font(.ui(17))
                        .foregroundStyle(Noel.cream.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button { model.go(.setup) } label: { Text("✨ Prepare a magic call") }
                        .buttonStyle(MagicButtonStyle())
                    Button { model.sheet = .discover } label: { Text("Discover the magic") }
                        .buttonStyle(QuietButtonStyle(filled: true))
                    Button { model.sheet = .advent } label: { Text("Advent calendar") }
                        .buttonStyle(QuietButtonStyle(filled: true))
                    Text("A magical moment to share as a family")
                        .font(.story(15))
                        .foregroundStyle(Noel.night.opacity(0.62))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.9)) { appeared = true } }
        .task { await playGreeting(again: false) }
        .onDisappear {
            greeting.stop()
            greetingMood = .idle
            model.call.voice.stopSpeech()
            music.duck(false)
        }
    }

    /// La vidéo `santa-accueil.mp4` (768×1024, voir Resources/Video/SPEC.txt) si elle est dans l'app,
    /// sinon le monologue enregistré `santa-accueil.m4a`.
    private func playGreeting(again: Bool) async {
        guard ShotMode.route == nil else { return }
        if !again && GreetingPlayback.played { return }
        GreetingPlayback.played = true
        try? await Task.sleep(for: .milliseconds(again ? 0 : 500))
        guard !Task.isCancelled else { return }
        music.duck(true)
        if greeting.startVideo() {
            greetingMood = .idle
            return
        }
        greetingMood = .talking
        let heard = await model.call.voice.playResource("santa-accueil")
        greetingMood = .idle
        if !heard { music.duck(false) }
        else { music.duck(false) }
    }
}

/// Lecture de la vidéo d'accueil. Le fichier n'est pas encore dans l'app : le chemin est réservé.
@MainActor @Observable
final class GreetingPlayback {
    static var played = false
    private(set) var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func startVideo() -> Bool {
        stop()
        guard let url = Bundle.main.url(forResource: "santa-accueil", withExtension: "mp4", subdirectory: "Video")
                ?? Bundle.main.url(forResource: "santa-accueil", withExtension: "mp4") else { return false }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.pause()
                ChristmasMusic.shared.duck(false)
            }
        }
        player.play()
        return true
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

/// La vidéo, sans les contrôles, recadrée sur le visage.
struct GreetingVideo: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> GreetingPlayerView {
        let view = GreetingPlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: GreetingPlayerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class GreetingPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// « Plus que 30 jours avant Noël 🎄 », avec une petite étoile qui scintille.
struct CountdownChip: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Noel.goldLight)
                .symbolEffect(.pulse, options: .repeating)
            Text(Countdown.text)
                .font(.ui(14, .semibold))
                .foregroundStyle(Noel.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Noel.night.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Noel.gold.opacity(0.45), lineWidth: 1))
    }
}
