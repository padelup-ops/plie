// FoldJournal.swift — Foldly
//
// Le carnet des derniers plis et ouvertures comptés : d'où vient chacun (charnière, sortie d'écran, automatisation
// Raccourcis, pli déduit) et dans quelles conditions (app à l'écran ou non, en charge, verrouillé, angle). Il est joint
// au « Signaler un bug » : de quoi comprendre un pli fantôme (ex. des plis comptés la nuit, téléphone en charge).
// Rien ne quitte l'iPhone sans que l'utilisateur envoie lui-même l'e-mail.

import UIKit

/// Appelé sur le fil principal (charnière, intents de l'app, réglages).
enum FoldJournal {
    private static let key = "foldJournal"
    private static let keep = 120

    static func note(_ what: String) {
        MainActor.assumeIsolated { write(what) }
    }

    @MainActor private static func write(_ what: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        var line = "\(f.string(from: Date())) \(what)"
        switch UIApplication.shared.applicationState {
        case .active: line += " · app"
        case .inactive: line += " · inactive"
        default: line += " · background"
        }
        if charging { line += " · charging" }
        if locked { line += " · locked" }
        if let d = ClapetModel.current?.degrees { line += " · \(Int(d))°" }
        var all = UserDefaults.standard.stringArray(forKey: key) ?? []
        all.append(line)
        if all.count > keep { all.removeFirst(all.count - keep) }
        UserDefaults.standard.set(all, forKey: key)
    }

    static func recent(_ n: Int = 60) -> String {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).suffix(n).joined(separator: "\n")
    }

    @MainActor static var charging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return [.charging, .full].contains(UIDevice.current.batteryState)
    }

    @MainActor static var locked: Bool { !UIApplication.shared.isProtectedDataAvailable }

    /// La nuit, téléphone en charge et verrouillé : personne n'est en train de le plier. Un pli « déduit » (une
    /// ouverture signalée sans fermeture avant) ne doit pas être compté dans ces conditions.
    static func idleNight(_ stats: ClapetStats, now: Date = Date()) -> Bool {
        guard MainActor.assumeIsolated({ charging && locked }) else { return false }
        let h = Calendar.current.component(.hour, from: now)
        let (from, to) = stats.nightOn ? (stats.nightFrom, stats.nightTo) : (0, 6)
        return from <= to ? (h >= from && h < to) : (h >= from || h < to)
    }
}
