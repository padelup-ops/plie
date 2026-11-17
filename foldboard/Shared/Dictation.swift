import Foundation

/// La dictée. iOS n'ouvre jamais le micro à un clavier : c'est l'app Foldboard qui l'ouvre (une fois, quelques
/// secondes au premier usage), puis reste prête en arrière-plan pendant quelques minutes. Le clavier lui parle par
/// des notifications du système (sans contenu), et le texte passe par le trousseau partagé.
/// La voix est transcrite sur l'iPhone (reconnaissance d'Apple, sans internet) : rien n'est envoyé ni gardé.
enum KBDictation {
    static let ping = "com.padelup.foldboard.dict.ping"
    static let pong = "com.padelup.foldboard.dict.pong"
    static let start = "com.padelup.foldboard.dict.start"
    static let stop = "com.padelup.foldboard.dict.stop"
    static let update = "com.padelup.foldboard.dict.update"
    static let url = URL(string: "foldboard://dictate")!
    /// Combien de temps l'app reste prête sans dictée (le point orange d'iOS reste affiché pendant ce temps).
    static let sessionMinutes: Double = 10

    /// Ce que l'app a entendu : le texte (partiel ou final) et un numéro de dictée.
    struct State: Codable, Equatable {
        var text = ""
        var final = false
        var seq = 0
    }

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
    }

    private static var handlers: [String: () -> Void] = [:]
    private static var registered = Set<String>()
    private static let lock = NSLock()

    /// Écoute une notification (une seule fonction par nom ; la dernière remplace la précédente).
    static func observe(_ name: String, _ handler: @escaping () -> Void) {
        lock.lock()
        handlers[name] = handler
        let first = registered.insert(name).inserted
        lock.unlock()
        guard first else { return }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, name, _, _ in
            guard let n = name?.rawValue as String? else { return }
            KBDictation.fire(n)
        }, name as CFString, nil, .deliverImmediately)
    }

    static func stopObserving(_ name: String) {
        lock.lock()
        handlers[name] = nil
        lock.unlock()
    }

    fileprivate static func fire(_ name: String) {
        lock.lock()
        let h = handlers[name]
        lock.unlock()
        guard let h else { return }
        DispatchQueue.main.async { h() }
    }
}
