import AVFoundation
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
        allowDuringRecording()
        if #available(iOS 17.5, *) {
            haptic = UIImpactFeedbackGenerator(style: .light, view: view)
            heavy = UIImpactFeedbackGenerator(style: .medium, view: view)
            attached = view
            viewBound = true
        } else {
            haptic = UIImpactFeedbackGenerator(style: .light)
            heavy = UIImpactFeedbackGenerator(style: .medium)
        }
        haptic.prepare()
    }

    private weak var attached: UIView?
    /// Les vibrations sont rattachées à une vue : si elle n'est plus à l'écran, elles ne vibrent plus.
    private var viewBound = false

    /// Le clavier s'en va : les vibrations ne le retiennent plus (de nouvelles seront rattachées à la prochaine apparition).
    func detach(from view: UIView) {
        guard attached === view else { return }
        haptic = UIImpactFeedbackGenerator(style: .light)
        heavy = UIImpactFeedbackGenerator(style: .medium)
        attached = nil
        viewBound = false
    }

    /// iOS coupe les vibrations et les sons du système tant qu'un micro est ouvert (la dictée, une app qui enregistre) :
    /// c'est le « ça vibre, puis plus, puis de nouveau ». On les garde.
    private func allowDuringRecording() {
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    private var lastTap: TimeInterval = 0

    /// Un appui : le son choisi et une vibration de la force choisie.
    func tap(sound: KBSound, haptics: Double, strong: Bool = false) {
        if sound != .off, let id = ids[sound] { AudioServicesPlaySystemSound(id) }
        let now = ProcessInfo.processInfo.systemUptime
        // Après une pause, un générateur neuf : un vieux générateur s'endort parfois et ne vibre plus du tout.
        let orphan = viewBound && attached?.window == nil
        if haptics > 0.01, now - lastTap > 20 || orphan {
            if #available(iOS 17.5, *), let v = attached, v.window != nil {
                haptic = UIImpactFeedbackGenerator(style: .light, view: v)
                heavy = UIImpactFeedbackGenerator(style: .medium, view: v)
            } else {
                haptic = UIImpactFeedbackGenerator(style: .light)
                heavy = UIImpactFeedbackGenerator(style: .medium)
                viewBound = false
            }
            allowDuringRecording()
        }
        lastTap = now
        if haptics > 0.01 {
            let g = strong ? heavy : haptic
            g.impactOccurred(intensity: CGFloat(min(1, max(0.05, haptics))))
            g.prepare()
        }
    }
}
