import SwiftUI

// MARK: - Mode démo (version de développement seulement)
//
// Sert à filmer la vidéo de présentation sur le simulateur iPhone Duo, qui n'a pas de charnière
// et où personne ne touche l'écran :
//   -demo <scène>          la partie se joue toute seule (voir chaque jeu)
//   -demoHinge "t:a,t:a"   charnière simulée : à t secondes, angle a en degrés (interpolé entre deux)
// L'heure de départ est écrite dans Documents/demo-origin.txt pour caler la vidéo.

#if DEBUG
enum Demo {
    static var scene: String? { UserDefaults.standard.string(forKey: "demo") }

    static func isScene(_ name: String) -> Bool { scene == name }

    /// L'instant zéro de la démo : quand l'écran du jeu apparaît, plus `-demoDelay` secondes
    /// (le temps que l'app ait fini de s'afficher).
    static let origin: Date = {
        let now = Date().addingTimeInterval(UserDefaults.standard.double(forKey: "demoDelay"))
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? String(format: "%.3f", now.timeIntervalSince1970)
                .write(to: folder.appendingPathComponent("demo-origin.txt"), atomically: true, encoding: .utf8)
        }
        return now
    }()

    static var elapsed: Double { Date().timeIntervalSince(origin) }

    /// Programme des actions à des instants précis (en secondes depuis l'origine).
    static func schedule(_ name: String, _ steps: [(Double, () -> Void)]) {
        guard isScene(name) else { return }
        let base = elapsed
        for (t, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - base), execute: action)
        }
    }

    /// Répète une action (jusqu'à `until` secondes) : pour jouer les coups tout seul.
    static func every(_ name: String, _ interval: Double, from start: Double, until end: Double, _ action: @escaping () -> Void) {
        guard isScene(name) else { return }
        func step() {
            let t = elapsed
            guard t < end else { return }
            if t >= start { action() }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { step() }
        }
        step()
    }

    /// Les images clés de la charnière, s'il y en a.
    static let hingeFrames: [(Double, Double)]? = {
        guard let text = UserDefaults.standard.string(forKey: "demoHinge"), !text.isEmpty else { return nil }
        let frames = text.split(separator: ",").compactMap { part -> (Double, Double)? in
            let p = part.split(separator: ":")
            guard p.count == 2, let t = Double(p[0]), let a = Double(p[1]) else { return nil }
            return (t, a)
        }
        return frames.isEmpty ? nil : frames.sorted { $0.0 < $1.0 }
    }()

    static func hingeAngle(at t: Double) -> Double? {
        guard let frames = hingeFrames, let first = frames.first, let last = frames.last else { return nil }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for k in 1..<frames.count where t <= frames[k].0 {
            let (t0, a0) = frames[k - 1], (t1, a1) = frames[k]
            let f = (t - t0) / max(0.0001, t1 - t0)
            let smooth = f * f * (3 - 2 * f)
            return a0 + (a1 - a0) * smooth
        }
        return last.1
    }
}

/// Charnière simulée : envoie l'angle prévu 30 fois par seconde.
struct DemoHingeDriver: ViewModifier {
    let action: (Double?) -> Void

    func body(content: Content) -> some View {
        content.task {
            guard Demo.hingeFrames != nil else { return }
            while !Task.isCancelled {
                action(Demo.hingeAngle(at: Demo.elapsed))
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }
}
#endif
