import AVFoundation
import UIKit

final class ClapetSound {
    enum Effect: String, CaseIterable { case clap, pop }
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
}

enum ClapetHaptics {
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func clap() { heavy.impactOccurred(intensity: 1) }
    static func tick() { light.impactOccurred(intensity: 0.6) }
}
