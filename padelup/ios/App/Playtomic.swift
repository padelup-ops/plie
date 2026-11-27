import CoreLocation
import Foundation
import Security

// Trousseau iOS (jeton PadelUp). Aucun mot de passe de plateforme n'est jamais demandé ni enregistré : la connexion
// Playtomic se fait sur leur propre site, dans l'app, et seule leur session (cookies) reste sur l'iPhone.
enum Keychain {
    static func set(_ data: Data?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.padelup.neo",
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.padelup.neo",
                                    kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func setCodable<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }

    static func getCodable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        get(key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

enum PlaytomicError: LocalizedError {
    case unavailable(String), blockedByPlaytomic

    var errorDescription: String? {
        switch self {
        case .unavailable(let m): return m
        case .blockedByPlaytomic:
            return "Playtomic limite les requêtes depuis ce réseau. Le bot s'arrête et réessaiera plus tard."
        }
    }
}

enum PlaytomicPrice {
    /// « 36 EUR », « 36,00 € » ou un nombre.
    static func parse(_ value: Any?) -> (Double?, String) {
        if let n = value as? NSNumber { return (n.doubleValue, "EUR") }
        guard let s = value as? String else { return (nil, "EUR") }
        var amount: Double? = nil
        var currency = "EUR"
        for part in s.replacingOccurrences(of: "€", with: " EUR").replacingOccurrences(of: ",", with: ".").split(separator: " ") {
            if let d = Double(part) { amount = d } else if part.count == 3, part.allSatisfy(\.isLetter) { currency = part.uppercased() }
        }
        return (amount, currency)
    }
}

// Anybuddy : la session du joueur vit dans la vue web de l'app (connexion sur leur site, voir ProviderWeb.swift).
// Leurs disponibilités sont chargées par la page elle-même, derrière une vérification anti-robot (captcha, limite de
// requêtes) : PadelUp ne les lit pas à sa place. On ouvre la page du club, ou leur réservation automatique, connecté.
enum AnybuddyAPI {
    static func slug(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = t.range(of: "/club/") {
            let rest = t[r.upperBound...]
            let slug = rest.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
            return slug.isEmpty ? nil : slug
        }
        return t.range(of: "^[a-z0-9-]{2,120}$", options: .regularExpression) != nil ? t : nil
    }

    /// Page du club (format vérifié : /fr/club/<slug>, 8 000 clubs au plan du site), ouverte sur la réservation.
    static func clubURL(_ slug: String) -> URL? { URL(string: "https://www.anybuddyapp.com/fr/club/\(slug)#booking-section") }

    /// La réservation automatique d'Anybuddy (leur propre fonction, sur le compte du joueur).
    static let autoBookingURL = URL(string: "https://www.anybuddyapp.com/fr/reservation-automatique")!

    static let protectedMessage = "Anybuddy protège ses créneaux (vérification anti-robot) : ouvre la page du club, déjà connecté, pour les voir."

    static func slots(slug: String, day: Date) async throws -> [BookingSlot] {
        throw PlaytomicError.unavailable(protectedMessage)
    }
}
