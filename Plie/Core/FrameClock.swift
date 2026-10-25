import SwiftUI
import QuartzCore

// MARK: - Horloge des jeux, calée sur l'écran
//
// Avant, chaque jeu avançait avec un minuteur (Timer) à 60 ou 30 images par seconde. Un minuteur
// n'est pas synchronisé avec l'affichage : certaines images arrivaient en double, d'autres sautaient,
// d'où de petits à-coups. CADisplayLink, lui, bat exactement au rythme de l'écran.
// On garde un pas fixe (1/60 s) pour que la physique des jeux reste la même.

final class FrameClock: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var pending: Double = 0
    var step: Double = 1.0 / 60.0
    var onStep: ((Double) -> Void)?

    func start() {
        guard link == nil else { return }
        last = 0
        pending = 0
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        let fps = Float(min(60, max(15, (1 / step).rounded())))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: 60, preferred: fps)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        guard last > 0 else {
            last = now
            return
        }
        // Après une pause (appli en arrière-plan…), on ne rattrape pas tout d'un coup.
        pending += min(0.1, now - last)
        last = now
        var steps = 0
        while pending >= step - 0.0005 && steps < 4 {
            onStep?(step)
            pending -= step
            steps += 1
        }
        if steps == 4 { pending = 0 }
    }

    deinit {
        link?.invalidate()
    }
}

private struct FrameTick: ViewModifier {
    let step: Double
    let action: (Double) -> Void
    @State private var clock = FrameClock()

    func body(content: Content) -> some View {
        content
            .onAppear {
                clock.step = step
                clock.onStep = action
                clock.start()
            }
            .onDisappear { clock.stop() }
    }
}

extension View {
    /// Appelé à pas fixe (par défaut 1/60 s), au rythme de l'écran.
    func onFrame(step: Double = 1.0 / 60.0, perform action: @escaping (Double) -> Void) -> some View {
        modifier(FrameTick(step: step, action: action))
    }
}
