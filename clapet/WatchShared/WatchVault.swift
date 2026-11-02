import Foundation
import Security
import SwiftUI

// MARK: - Le coffre de la montre
//
// L'app Apple Watch y range le dernier résumé reçu de l'iPhone ; les complications le lisent.
// Groupe de trousseau commun (« ÉQUIPE.com.padelup.clapet.watch »), avec une copie de secours pour l'app.

enum WatchVault {
    private static let service = "com.padelup.clapet.watch"
    private static let account = "summary"

    private static var group: String? {
        guard let g = Bundle.main.object(forInfoDictionaryKey: "FoldlyKeychainGroup") as? String,
              !g.hasPrefix("."), !g.isEmpty, !g.hasPrefix("$") else { return nil }
        return g
    }

    private static func query(_ group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func load() -> FoldlyWatchData? {
        for g in [group, nil] {
            var q = query(g)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
               let value = try? JSONDecoder().decode(FoldlyWatchData.self, from: data) {
                return value
            }
            if group == nil { break }
        }
        if let data = UserDefaults.standard.data(forKey: "foldly.watch"),
           let value = try? JSONDecoder().decode(FoldlyWatchData.self, from: data) {
            return value
        }
        return nil
    }

    static func save(_ data: Data) {
        UserDefaults.standard.set(data, forKey: "foldly.watch")
        if write(data, group: group) != errSecSuccess && group != nil {
            _ = write(data, group: nil)
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

/// Les couleurs de la montre (celles du look Moderne).
enum WatchPalette {
    static let mint = Color(red: 0.43, green: 0.84, blue: 0.65)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.32)
    static let track = Color.white.opacity(0.16)
}

extension FoldlyWatchData {
    /// « 9 below your average », « Limit reached »…
    var statusText: Text {
        guard let ref = reference, ref > 0 else { return Text("Your first days") }
        if limitOn {
            let left = ref - today
            if left > 0 { return Text("\(left) left today") }
            if left == 0 { return Text("Limit reached") }
            return Text("\(-left) over the limit")
        }
        let diff = today - ref
        if diff == 0 { return Text("Right on your average") }
        return diff < 0 ? Text("\(-diff) below your average") : Text("\(diff) above your average")
    }

    /// 0 à 1 : aujourd'hui comparé à la moyenne (ou à la limite).
    var progress: Double {
        guard let ref = reference, ref > 0 else { return 0 }
        return min(1, Double(today) / Double(ref))
    }

    var over: Bool { limitOn && (reference.map { today > $0 } ?? false) }
}
