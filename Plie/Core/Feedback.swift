import AVFoundation
import UIKit

/// Petits sons du jeu, lus depuis les fichiers .wav du dossier Sounds.
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case notch, decoy, clunk, lock, wrong, vault, win, beam, go, stop, caught, splat
        case whoosh, swish, thud, pop, puck, goal, bloom
        case tock, pok, smash, net, applause, point
        case pieceMove, pieceCapture, checkBell, promote, clockTick
        case clack, pocket, chime, bell, chalk, cave
        case boom, roar, chomp
        case zap, bang, splash, sonar, buzzer, simon0, simon1, simon2, simon3
    }

    static let shared = SoundPlayer()

    var enabled = true
    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var nextIndex: [Effect: Int] = [:]

    private init() {
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            // Plusieurs lecteurs par son : certains sons (crans, gemmes) s'enchaînent très vite.
            let copies: Int
            switch effect {
            case .notch, .decoy, .puck: copies = 4
            case .thud, .pop, .whoosh, .tock, .pok, .pieceMove, .clockTick: copies = 3
            case .pieceCapture, .clack, .chime: copies = 4
            case .pocket, .chalk, .zap, .splash: copies = 2
            default: copies = 1
            }
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

    /// Session audio par défaut : les sons et la musique respectent le mode silencieux
    /// et se mélangent à ce que l'utilisateur écoute déjà.
    static func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Le piano est un instrument : il joue même en mode silencieux, comme GarageBand.
    static func configureInstrumentSession() {
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

    /// La mâchoire du croco qui claque : trois grands coups.
    static func chomp() {
        guard enabled else { return }
        heavy.impactOccurred(intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { heavy.impactOccurred(intensity: 1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { rigid.impactOccurred(intensity: 0.8) }
    }
}

/// Musique d'ambiance douce, en boucle. Se tait si une autre app joue déjà de la musique.
final class MusicPlayer {
    static let shared = MusicPlayer()

    private var player: AVAudioPlayer?
    private var enabled = true
    private var ducked = 0

    private init() {
        if let url = Bundle.main.url(forResource: "ambient", withExtension: "m4a"),
           let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            player = p
        }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        update()
    }

    /// Les jeux qui ont besoin d'entendre de petits sons (coffre, voix de Soleil) baissent la musique.
    func duck(_ on: Bool) {
        ducked = max(0, ducked + (on ? 1 : -1))
        update()
    }

    private func update() {
        guard let player else { return }
        let shouldPlay = enabled && ducked == 0 && !AVAudioSession.sharedInstance().isOtherAudioPlaying
        if shouldPlay {
            if !player.isPlaying { player.play() }
            player.setVolume(0.32, fadeDuration: 1.2)
        } else if player.isPlaying {
            player.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, let player = self.player, !(self.enabled && self.ducked == 0) else { return }
                player.pause()
            }
        }
    }
}
