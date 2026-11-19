import AppIntents
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

    /// Joué par l'automatisation « Compter » quand Foldly n'est pas à l'écran (si le son est activé).
    static func playFromAutomation(close: Bool) async {
        let d = UserDefaults.standard
        guard d.bool(forKey: "sound"), d.bool(forKey: "soundAlways") else { return }
        await playInBackground(close ? closeEffect : .pop)
    }

    /// Le son choisi pour une action Raccourcis qui ne fait que jouer (sans ouvrir l'app).
    static func effect(_ choice: FoldlySoundChoice, closing: Bool) -> Effect {
        switch choice {
        case .setting: return closing ? closeEffect : .pop
        case .opening: return .pop
        case .soft: return .soft
        case .snap: return .clap
        }
    }

    /// Lecture courte sans ouvrir Foldly : session « lecture », la musique baisse le temps du son, puis on rend la main.
    static func playInBackground(_ effect: Effect) async {
        // L'init du lecteur remet la session en « ambiant » : on le crée avant de passer en lecture,
        // sinon iOS coupe le son dès que l'app n'est pas à l'écran.
        _ = await MainActor.run { shared }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        let duration = await MainActor.run { shared.playAndDuration(effect) }
        let wait = min(2, max(0.45, duration + 0.2))
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.ambient, options: [.mixWithOthers])
    }

    @discardableResult
    private func playAndDuration(_ e: Effect) -> TimeInterval {
        play(e)
        return players[e]?.first?.duration ?? 0.5
    }

    /// Copies des sons (ouverture, fermeture douce, clac) pour les enregistrer dans Fichiers.
    static func exportFiles() -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("foldly-sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let named: [(Effect, String)] = [(.pop, "Foldly opening"), (.soft, "Foldly soft close"), (.clap, "Foldly original close")]
        return named.compactMap { effect, name in
            guard let src = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { return nil }
            let dst = dir.appendingPathComponent(name + ".wav")
            try? FileManager.default.removeItem(at: dst)
            do { try FileManager.default.copyItem(at: src, to: dst) } catch { return nil }
            return dst
        }
    }
}

/// Le son demandé par Raccourcis : le réglage actuel, ou un son précis.
enum FoldlySoundChoice: String, AppEnum {
    case setting, opening, soft, snap

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Which sound")
    static var caseDisplayRepresentations: [FoldlySoundChoice: DisplayRepresentation] = [
        .setting: "Current setting",
        .opening: "Opening sound",
        .soft: "Soft close",
        .snap: "Original close"
    ]
}

enum ClapetHaptics {
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func clap() { heavy.impactOccurred(intensity: 1) }
    static func tick() { light.impactOccurred(intensity: 0.6) }
}
