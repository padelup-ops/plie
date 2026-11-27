// Music.swift — Allô Père Noël
//
// La musique de Noël de l'app : un pot-pourri doux de chants du domaine public sur l'accueil et pendant la préparation,
// coupée en fondu avant la sonnerie (l'appel a sa propre musique, « Douce nuit » au coin du feu, sous la voix).
// Le parent peut la couper (bouton sur l'accueil, ou Réglages) ; le choix est retenu.

import AVFoundation
import Observation

@MainActor @Observable
final class ChristmasMusic {
    static let shared = ChristmasMusic()

    var enabled: Bool = UserDefaults.standard.object(forKey: "allonoel.music") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "allonoel.music")
            if enabled { play() } else { stop() }
        }
    }

    private var player: AVAudioPlayer?
    private var wanted = false
    private let level: Float = 0.38

    /// L'écran courant veut de la musique (accueil, préparation, fin) ou du silence (attente, sonnerie, appel).
    func screen(wantsMusic: Bool) {
        wanted = wantsMusic
        if wantsMusic { play() } else { stop() }
    }

    private func play() {
        guard enabled, wanted, ShotMode.route == nil else { return }
        if player == nil, let url = Bundle.main.url(forResource: "music-home", withExtension: "m4a") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
        }
        guard let p = player else { return }
        if !p.isPlaying { p.play() }
        p.setVolume(level, fadeDuration: 1.2)
    }

    /// Baisse la musique pendant que le Père Noël parle à l'accueil.
    func duck(_ down: Bool) {
        guard let p = player else { return }
        let target: Float = down ? level * 0.22 : ((wanted && enabled) ? level : 0)
        p.setVolume(target, fadeDuration: 0.35)
    }

    private func stop() {
        guard let p = player, p.isPlaying else { return }
        p.setVolume(0, fadeDuration: 0.8)
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            if !self.wanted || !self.enabled { p.pause() }
        }
    }
}
