import AudioToolbox
import UIKit

/// Les sons de frappe et les vibrations.
final class KBFeedback {
    static let shared = KBFeedback()
    private var ids: [KBSound: SystemSoundID] = [:]
    private var haptic = UIImpactFeedbackGenerator(style: .light)
    private var heavy = UIImpactFeedbackGenerator(style: .medium)

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

    /// À chaque apparition du clavier : des vibrations neuves, rattachées au clavier affiché. Un générateur gardé
    /// d'une apparition à l'autre finit parfois par ne plus vibrer du tout (« ça vibre, puis plus, puis de nouveau »).
    func attach(to view: UIView) {
        if #available(iOS 17.5, *) {
            haptic = UIImpactFeedbackGenerator(style: .light, view: view)
            heavy = UIImpactFeedbackGenerator(style: .medium, view: view)
        } else {
            haptic = UIImpactFeedbackGenerator(style: .light)
            heavy = UIImpactFeedbackGenerator(style: .medium)
        }
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
