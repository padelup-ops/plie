import AVFoundation
import UIKit

/// Petits sons du jeu, lus depuis les fichiers .wav du dossier Sounds.
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case notch, decoy, clunk, lock, wrong, vault, win, beam, go, stop, caught
    }

    static let shared = SoundPlayer()

    var enabled = true
    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var nextIndex: [Effect: Int] = [:]

    private init() {
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            // Plusieurs lecteurs par son : les crans du coffre peuvent s'enchaîner très vite.
            let copies = (effect == .notch || effect == .decoy) ? 4 : 1
            var list: [AVAudioPlayer] = []
            for _ in 0..<copies {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    list.append(player)
                }
            }
            players[effect] = list
        }
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard enabled, let list = players[effect], !list.isEmpty else { return }
        let index = (nextIndex[effect] ?? 0) % list.count
        nextIndex[effect] = index + 1
        let player = list[index]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Session audio par défaut : les sons se mélangent à la musique en cours.
    static func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

/// Vibrations. Le coffre en dépend : chaque cran se sent sous les doigts.
enum Haptics {
    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        guard enabled else { return }
        light.prepare()
        rigid.prepare()
        heavy.prepare()
    }

    /// Un cran ordinaire.
    static func notch() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.55)
    }

    /// Un faux cran, pour brouiller les pistes.
    static func decoy(strength: CGFloat = 0.7) {
        guard enabled else { return }
        rigid.impactOccurred(intensity: strength)
    }

    /// Le bon cran.
    static func correct(subtle: Bool) {
        guard enabled else { return }
        if subtle {
            rigid.impactOccurred(intensity: 0.95)
        } else {
            heavy.impactOccurred(intensity: 1)
        }
    }

    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.8)
    }

    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    static func error() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }

    static func warning() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }
}
