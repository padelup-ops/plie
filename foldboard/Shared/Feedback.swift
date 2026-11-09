import AudioToolbox
import UIKit

/// Les sons de frappe et les vibrations.
final class KBFeedback {
    static let shared = KBFeedback()
    private var ids: [KBSound: SystemSoundID] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .medium)

    private init() {
        for s in KBSound.allCases where s != .off {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav") else { continue }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError { ids[s] = id }
        }
    }

    func prepare() {
        haptic.prepare()
    }

    /// Un appui : le son choisi et une vibration de la force choisie.
    func tap(sound: KBSound, haptics: Double, strong: Bool = false) {
        if sound != .off, let id = ids[sound] { AudioServicesPlaySystemSound(id) }
        if haptics > 0.01 {
            let g = strong ? heavy : haptic
            g.impactOccurred(intensity: CGFloat(min(1, max(0.05, haptics))))
            g.prepare()
        }
    }
}
