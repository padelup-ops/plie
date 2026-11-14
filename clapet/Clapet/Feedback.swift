import AVFoundation
import UIKit

final class ClapetSound {
    enum Effect: String, CaseIterable { case clap, pop, soft }
    static let shared = ClapetSound()
    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var next: [Effect: Int] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for e in Effect.allCases {
            guard let url = Bundle.main.url(forResource: e.rawValue, withExtension: "wav") else { continue }
            players[e] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                return p
            }
        }
    }

    func play(_ e: Effect) {
        guard let list = players[e], !list.isEmpty else { return }
        let i = (next[e] ?? 0) % list.count
        next[e] = i + 1
        list[i].currentTime = 0
        list[i].play()
    }

    /// Le son de fermeture choisi : un « chhht » doux (par défaut) ou le clac d'origine.
    static var closeEffect: Effect { UserDefaults.standard.object(forKey: "softClose") as? Bool ?? true ? .soft : .clap }

    /// Joué par l'automatisation quand Foldly n'est pas à l'écran (si iOS le permet à ce moment-là).
    static func playFromAutomation(close: Bool) async {
        let d = UserDefaults.standard
        guard d.bool(forKey: "sound"), d.bool(forKey: "soundAlways") else { return }
        // En arrière-plan, le mode « ambiant » est coupé par iOS : on passe en lecture le temps du son
        // (mélangé à la musique en cours, sans la couper), puis on rend la main.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        await MainActor.run { shared.play(close ? closeEffect : .pop) }
        try? await Task.sleep(nanoseconds: 600_000_000)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }
}

enum ClapetHaptics {
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func clap() { heavy.impactOccurred(intensity: 1) }
    static func tick() { light.impactOccurred(intensity: 0.6) }
}
