import Foundation
import UIKit

/// Le journal de la détection de la main, pour l'améliorer à partir de vraies prises en main.
/// Ce qu'il garde : pour chaque appui, l'endroit sur la touche, la taille du toucher, la réaction du téléphone
/// et son inclinaison ; les changements de côté décidés seuls ; les corrections à la main. Jamais les lettres
/// tapées ni le texte. Il reste sur le téléphone : il ne part que si on le copie soi-même (menu de position).
final class KBGripLog {
    static let shared = KBGripLog()
    private let key = "foldboard.griplog.v1"
    private var events: [[String: Double]] = []
    private var contexts: [String] = []
    private var dirty = false
    private static let cap = 4_000

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Stored.self, from: d) { events = s.events; contexts = s.contexts }
    }
    private struct Stored: Codable { var events: [[String: Double]]; var contexts: [String] }

    private func ctxId(_ c: String) -> Double {
        if let i = contexts.firstIndex(of: c) { return Double(i) }
        contexts.append(c)
        return Double(contexts.count - 1)
    }

    /// `kind` : 1 appui, 2 réaction du téléphone à un appui, 3 côté décidé seul, 4 correction à la main.
    func add(_ kind: Double, context: String, _ fields: [String: Double]) {
        var e = fields
        e["k"] = kind
        e["c"] = ctxId(context)
        e["t"] = (ProcessInfo.processInfo.systemUptime * 100).rounded() / 100
        e["d"] = (Date().timeIntervalSince1970 / 60).rounded()
        events.append(e)
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
        dirty = true
    }

    func flush() {
        guard dirty, let d = try? JSONEncoder().encode(Stored(events: events, contexts: contexts)) else { return }
        UserDefaults.standard.set(d, forKey: key)
        dirty = false
    }

    var count: Int { events.count }

    /// Le journal en texte (JSON compressé en base64), à coller dans un message pour le développeur.
    func exportText(extra: [String: String]) -> String? {
        let payload: [String: Any] = ["v": 1, "contexts": contexts, "events": events, "extra": extra]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let z = try? (json as NSData).compressed(using: .zlib) else { return nil }
        return "FOLDBOARD-GRIPLOG:" + (z as Data).base64EncodedString()
    }
}
