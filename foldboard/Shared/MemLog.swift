import Foundation

/// La mémoire du clavier, apparition par apparition : à quoi ressemblait le clavier quand iOS l'a fermé
/// (situation, disposition, emojis ouverts, mémoire au départ et au plus haut). Gardé sur l'iPhone (10 dernières),
/// joint aux données de la main copiées pour le développeur et montré par l'appui long sur « masquer ».
/// Aucun texte tapé.
enum KBMemLog {
    private static let key = "foldboard.memlog.v1"
    private static var current: String?
    private static var start = 0.0
    private static var peak = 0.0
    private static var lastWrite = 0.0

    /// Le clavier apparaît : une nouvelle ligne.
    static func begin(mb: Double, context: String, mode: String) {
        start = mb
        peak = mb
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        current = "\(f.string(from: Date())) \(context) \(mode)"
        write(emoji: false, force: true)
    }

    /// Une mesure : la ligne en cours garde le plus haut (écrite au plus toutes les 2 secondes, et tout de suite
    /// quand la mémoire monte beaucoup : c'est peut-être la dernière avant qu'iOS ferme le clavier).
    static func note(mb: Double, emoji: Bool, alive: Int = 1) {
        guard current != nil else { return }
        let jump = mb > peak + 3 || alive != keyboards
        peak = max(peak, mb)
        keyboards = alive
        write(emoji: emoji, force: jump)
    }

    /// Combien de claviers vivent en même temps (plus d'un longtemps : un clavier jeté par iOS mais pas libéré).
    private static var keyboards = 1

    private static func write(emoji: Bool, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastWrite > 2, let c = current else { return }
        lastWrite = now
        let line = c + String(format: " %.0f→%.0f Mo ×%d", start, peak, keyboards) + (emoji ? " emoji" : "")
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        if let last = list.last, last.hasPrefix(c) { list[list.count - 1] = line } else { list.append(line) }
        if list.count > 10 { list.removeFirst(list.count - 10) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
}
