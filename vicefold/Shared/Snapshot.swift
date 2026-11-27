// Snapshot.swift — Vicefold
//
// Ce que l'app partage avec ses widgets (écran d'accueil et écran verrouillé) : la progression, la prochaine mission
// et le temps de jeu. Écrit par l'app dans le groupe d'apps, lu par le widget.

import Foundation
import Security
import SwiftUI

struct VFSnapshot: Codable, Equatable {
    var percent: Double = 0
    var missions: Double = 0
    var places: Double = 0
    var collectibles: Double = 0
    var challenges: Double = 0
    var nextMission: String?
    var nextChapter: String?
    var hours: Double = 0
    var pro = false
    var updated = Date()
    // Les comptes affichés par le grand widget (fait / total).
    var counts: [Int] = []          // missions, lieux, objets, défis : fait, total, fait, total…
    var eggs: [Int] = []            // trouvés, total
    var chapter: Int = 1

    static let group = "group.com.padelup.vicefold"
    private static let key = "vicefold.snapshot"

    /// Groupe de trousseau commun à l'app et au widget (« ÉQUIPE.com.padelup.vicefold.shared »), comme Foldly.
    private static var keychainGroup: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "VicefoldKeychainGroup") as? String,
              !g.hasPrefix("."), !g.isEmpty, !g.hasPrefix("$") else { return nil }
        return g
    }

    private static func query(_ group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "com.padelup.vicefold",
                                kSecAttrAccount as String: key]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func load() -> VFSnapshot {
        for g in [keychainGroup, nil] {
            var q = query(g)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
               let s = try? JSONDecoder().decode(VFSnapshot.self, from: d) { return s }
            if keychainGroup == nil { break }
        }
        // Secours (simulateur, développement) : le groupe d'apps.
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key),
              let s = try? JSONDecoder().decode(VFSnapshot.self, from: d) else { return VFSnapshot() }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(d, forKey: Self.key)
        if Self.write(d, group: Self.keychainGroup) != errSecSuccess, Self.keychainGroup != nil {
            _ = Self.write(d, group: nil)
        }
    }

    private static func write(_ data: Data, group: String?) -> OSStatus {
        let q = query(group)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }
}
