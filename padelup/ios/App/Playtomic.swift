import CoreLocation
import Foundation
import Security

// Trousseau iOS : les jetons des plateformes ne quittent jamais l'iPhone (sauf si le joueur active le bot 24 h/24
// sur le serveur PadelUp). Le mot de passe Playtomic n'est jamais enregistré.
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

struct PlaytomicSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var email: String
    var expiresAt: Date
}

enum PlaytomicError: LocalizedError {
    case notConnected, badCredentials, sessionExpired, unavailable(String), slotTaken

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Connecte ton compte Playtomic."
        case .badCredentials: return "Identifiants Playtomic refusés."
        case .sessionExpired: return "Session Playtomic expirée : reconnecte ton compte."
        case .unavailable(let m): return m
        case .slotTaken: return "Ce créneau vient d'être pris."
        }
    }
}

// Client Playtomic embarqué : mêmes appels que le bot serveur (booking_bot/providers/playtomic.py).
// Playtomic ne propose pas d'API publique aux applications tierces : ces appels suivent leur propre application
// et peuvent évoluer. Disponibilités et recherche de clubs sans compte ; réservation avec le compte du joueur.
actor PlaytomicAPI {
    static let shared = PlaytomicAPI()
    private let base = URL(string: "https://api.playtomic.io")!
    private let sessionKey = "playtomic.session"
    private var tenantCache: [String: [String: Any]] = [:]

    nonisolated var isConnected: Bool { Keychain.getCodable(PlaytomicSession.self, for: "playtomic.session") != nil }
    nonisolated var connectedEmail: String? { Keychain.getCodable(PlaytomicSession.self, for: "playtomic.session")?.email }

    // MARK: HTTP

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil, auth: Bool = false,
                         retried: Bool = false) async throws -> (Int, Any?) {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("com.playtomic.web", forHTTPHeaderField: "X-Requested-With")
        if auth {
            let token = try await validToken()
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && auth && !retried {
            try await refresh()
            return try await request(method, path, query: query, body: body, auth: auth, retried: true)
        }
        if code == 401 && auth { throw PlaytomicError.sessionExpired }
        var json: Any? = nil
        if !data.isEmpty { json = try? JSONSerialization.jsonObject(with: data) }
        return (code, json)
    }

    private static func message(_ json: Any?, _ code: Int) -> String {
        if let d = json as? [String: Any] {
            return (d["localized_message"] as? String) ?? (d["message"] as? String) ?? (d["status"] as? String) ?? "erreur \(code)"
        }
        return "erreur \(code)"
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    // MARK: Compte

    func connect(email: String, password: String) async throws {
        let (code, json) = try await request("POST", "/v3/auth/login", body: ["grant_type": "password", "email": email, "password": password])
        guard code < 300, let d = json as? [String: Any], let token = d["access_token"] as? String else {
            throw (400...404).contains(code) ? PlaytomicError.badCredentials : PlaytomicError.unavailable("Connexion Playtomic impossible (\(Self.message(json, code))).")
        }
        let userID = (d["user_id"] as? String) ?? (d["user_id"] as? NSNumber)?.stringValue ?? ""
        let session = PlaytomicSession(accessToken: token, refreshToken: d["refresh_token"] as? String ?? "", userID: userID,
                                       email: email, expiresAt: Self.date(d["access_token_expiration"]) ?? Date().addingTimeInterval(3600))
        Keychain.setCodable(session, for: sessionKey)
    }

    func disconnect() { Keychain.set(nil, for: sessionKey) }

    private func refresh() async throws {
        guard var s = Keychain.getCodable(PlaytomicSession.self, for: sessionKey), !s.refreshToken.isEmpty else {
            throw PlaytomicError.sessionExpired
        }
        let (code, json) = try await request("POST", "/v3/auth/token", body: ["grant_type": "refresh_token", "refresh_token": s.refreshToken])
        guard code < 300, let d = json as? [String: Any], let token = d["access_token"] as? String else { throw PlaytomicError.sessionExpired }
        s.accessToken = token
        if let r = d["refresh_token"] as? String, !r.isEmpty { s.refreshToken = r }
        s.expiresAt = Self.date(d["access_token_expiration"]) ?? Date().addingTimeInterval(3600)
        Keychain.setCodable(s, for: sessionKey)
    }

    private func validToken() async throws -> String {
        guard let s = Keychain.getCodable(PlaytomicSession.self, for: sessionKey) else { throw PlaytomicError.notConnected }
        if s.expiresAt > Date().addingTimeInterval(60) { return s.accessToken }
        try await refresh()
        return Keychain.getCodable(PlaytomicSession.self, for: sessionKey)?.accessToken ?? s.accessToken
    }

    // MARK: Clubs

    func tenants(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async throws -> [Club] {
        let (code, json) = try await request("GET", "/v1/tenants", query: [
            URLQueryItem(name: "coordinate", value: String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)),
            URLQueryItem(name: "sport_id", value: "PADEL"),
            URLQueryItem(name: "radius", value: String(Int(radiusKm * 1000))),
            URLQueryItem(name: "size", value: "50"),
        ])
        guard code < 300 else { throw PlaytomicError.unavailable("Recherche Playtomic impossible.") }
        let list = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        return list.compactMap { t in
            guard let id = t["tenant_id"] as? String else { return nil }
            tenantCache[id] = t
            return Self.club(from: t)
        }
    }

    static func club(from t: [String: Any]) -> Club? {
        guard let id = t["tenant_id"] as? String else { return nil }
        let addr = t["address"] as? [String: Any] ?? [:]
        let coord = (addr["coordinate"] as? [String: Any]) ?? (addr["geo_location"] as? [String: Any]) ?? [:]
        guard let lat = (coord["lat"] as? NSNumber)?.doubleValue, let lon = ((coord["lon"] ?? coord["lng"]) as? NSNumber)?.doubleValue else { return nil }
        let resources = (t["resources"] as? [[String: Any]] ?? []).filter { ($0["sport_id"] as? String ?? "PADEL") == "PADEL" }
        let indoor = resources.filter { (($0["properties"] as? [String: Any])?["resource_type"] as? String)?.lowercased() == "indoor" }.count
        return Club(id: "pt:" + id, name: t["tenant_name"] as? String ?? "Club Playtomic", latitude: lat, longitude: lon,
                    courts: resources.count, indoor: indoor, outdoor: resources.count - indoor,
                    city: addr["city"] as? String ?? "", postcode: addr["postal_code"] as? String ?? "",
                    street: addr["street"] as? String ?? "", country: addr["country_code"] as? String ?? "",
                    source: .playtomic, playtomicTenantID: id, timezone: addr["timezone"] as? String,
                    imageURL: (t["images"] as? [String])?.first)
    }

    private func tenant(_ id: String) async throws -> [String: Any] {
        if let t = tenantCache[id], t["resources"] != nil { return t }
        let (code, json) = try await request("GET", "/v1/tenants/\(id)")
        guard code < 300, var t = json as? [String: Any] else { throw PlaytomicError.unavailable("Club Playtomic introuvable.") }
        if t["resources"] == nil {
            let (c2, j2) = try await request("GET", "/v1/tenants/\(id)/resources")
            if c2 < 300, let res = j2 as? [[String: Any]] { t["resources"] = res }
        }
        tenantCache[id] = t
        return t
    }

    // MARK: Disponibilités (heures UTC chez Playtomic, affichées à l'heure du club)

    func slots(tenantID: String, day: Date) async throws -> [BookingSlot] {
        let t = try await tenant(tenantID)
        let tzName = (t["address"] as? [String: Any])?["timezone"] as? String ?? TimeZone.current.identifier
        let tz = TimeZone(identifier: tzName) ?? .current
        var resources: [String: (String, Bool?)] = [:]
        for r in t["resources"] as? [[String: Any]] ?? [] {
            guard let rid = r["resource_id"] as? String, (r["sport_id"] as? String ?? "PADEL") == "PADEL" else { continue }
            let kind = ((r["properties"] as? [String: Any])?["resource_type"] as? String)?.lowercased()
            resources[rid] = (r["name"] as? String ?? "Terrain", kind == "indoor" ? true : (kind == "outdoor" ? false : nil))
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.startOfDay(for: day)
        let end = start.addingTimeInterval(86_399)
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let (code, json) = try await request("GET", "/v1/availability", query: [
            URLQueryItem(name: "sport_id", value: "PADEL"),
            URLQueryItem(name: "tenant_id", value: tenantID),
            URLQueryItem(name: "start_min", value: utc.string(from: start)),
            URLQueryItem(name: "start_max", value: utc.string(from: end)),
        ])
        guard code < 300 else { throw PlaytomicError.unavailable("Disponibilités Playtomic illisibles (\(Self.message(json, code))).") }
        var out: [BookingSlot] = []
        for block in json as? [[String: Any]] ?? [] {
            guard let rid = block["resource_id"] as? String, let startDate = block["start_date"] as? String else { continue }
            let info: (String, Bool?) = resources[rid] ?? ("Terrain", nil)
            for s in block["slots"] as? [[String: Any]] ?? [] {
                guard let time = s["start_time"] as? String else { continue }
                let raw = "\(startDate)T\(time)"
                guard let date = utc.date(from: raw) else { continue }
                let (price, currency) = Self.price(s["price"])
                out.append(BookingSlot(provider: .playtomic, clubID: tenantID, resourceID: rid, courtName: info.0, start: date,
                                       duration: (s["duration"] as? NSNumber)?.intValue ?? 60, price: price, currency: currency,
                                       indoor: info.1, timezone: tzName, rawStart: raw))
            }
        }
        return out.sorted { ($0.start, $0.duration, $0.courtName) < ($1.start, $1.duration, $1.courtName) }
    }

    static func price(_ value: Any?) -> (Double?, String) {
        if let n = value as? NSNumber { return (n.doubleValue, "EUR") }
        guard let s = value as? String else { return (nil, "EUR") }
        var amount: Double? = nil
        var currency = "EUR"
        for part in s.replacingOccurrences(of: "€", with: " EUR").replacingOccurrences(of: ",", with: ".").split(separator: " ") {
            if let d = Double(part) { amount = d } else if part.count == 3, part.allSatisfy(\.isLetter) { currency = part.uppercased() }
        }
        return (amount, currency)
    }

    // MARK: Réservation : panier, moyen de paiement enregistré, confirmation

    func book(_ slot: BookingSlot) async throws -> BookingOutcome {
        guard let s = Keychain.getCodable(PlaytomicSession.self, for: sessionKey), !s.userID.isEmpty else { throw PlaytomicError.notConnected }
        let clubURL = URL(string: "https://playtomic.io/tenant/\(slot.clubID)")
        let cart: [String: Any] = [
            "allowed_payment_method_types": ["OFFER", "CASH", "MERCHANT_WALLET", "DIRECT", "SWISH", "IDEAL", "BANCONTACT", "PAYTRAIL", "CREDIT_CARD", "QUICK_PAY"],
            "user_id": s.userID,
            "cart": ["requested_item": [
                "cart_item_type": "CUSTOMER_MATCH",
                "cart_item_voucher_id": NSNull(),
                "cart_item_data": [
                    "supports_split_payment": true, "number_of_players": 4, "tenant_id": slot.clubID, "resource_id": slot.resourceID,
                    "start": slot.rawStart, "duration": slot.duration,
                    "match_registrations": [["user_id": s.userID, "pay_now": true] as [String: Any]],
                ] as [String: Any],
            ] as [String: Any]],
        ]
        let (code, json) = try await request("POST", "/v1/payment_intents", body: cart, auth: true)
        if code == 409 || code == 422 { throw PlaytomicError.slotTaken }
        guard code < 300, let intent = json as? [String: Any],
              let pid = (intent["payment_intent_id"] as? String) ?? (intent["id"] as? String) else {
            return BookingOutcome(status: .failed, message: "Playtomic a refusé le panier (\(Self.message(json, code))).")
        }
        guard let method = Self.chooseMethod(intent["available_payment_methods"] as? [Any] ?? []) else {
            return BookingOutcome(status: .needsAction, message: "Ce club demande la carte : termine la réservation dans l'app Playtomic.",
                                  externalID: pid, actionURL: clubURL)
        }
        let (c2, j2) = try await request("PATCH", "/v1/payment_intents/\(pid)",
                                         body: ["selected_payment_method_id": method, "selected_payment_method_data": NSNull()] as [String: Any], auth: true)
        guard c2 < 300 else { return BookingOutcome(status: .failed, message: "Moyen de paiement refusé (\(Self.message(j2, c2))).") }
        let (c3, j3) = try await request("POST", "/v1/payment_intents/\(pid)/confirmation", auth: true)
        let state = ((j3 as? [String: Any])?["status"] as? String ?? "").uppercased()
        if (c3 < 300 && ["SUCCEEDED", "PAYMENT_SUCCEEDED", "CONFIRMED", "COMPLETED", ""].contains(state)) || (c3 == 422 && state == "PAYMENT_INTENT_STATUS_INVALID") {
            return BookingOutcome(status: .booked, message: "Réservé sur Playtomic ✅", externalID: Self.findMatchID(j3) ?? pid)
        }
        if ["REQUIRES_ACTION", "REQUIRES_PAYMENT_METHOD", "PENDING"].contains(state) {
            return BookingOutcome(status: .needsAction, message: "Ta banque demande une validation : termine dans l'app Playtomic.", externalID: pid, actionURL: clubURL)
        }
        if c3 == 409 || c3 == 422 { throw PlaytomicError.slotTaken }
        return BookingOutcome(status: .failed, message: "Confirmation refusée (\(Self.message(j3, c3))).")
    }

    static func chooseMethod(_ methods: [Any]) -> String? {
        func ident(_ m: Any) -> String? {
            if let s = m as? String { return s }
            let d = m as? [String: Any]
            return (d?["payment_method_id"] as? String) ?? (d?["id"] as? String)
        }
        func kind(_ m: Any) -> String {
            if let s = m as? String { return s.uppercased() }
            let d = m as? [String: Any] ?? [:]
            return ["method_type", "payment_method_type", "type", "code", "name", "payment_method_id"]
                .compactMap { d[$0] as? String }.joined(separator: " ").uppercased().replacingOccurrences(of: " ", with: "_")
        }
        for wanted in ["MERCHANT_WALLET", "OFFER", "CASH", "AT_THE_CLUB"] {
            if let m = methods.first(where: { ident($0) != nil && kind($0).contains(wanted) }) { return ident(m) }
        }
        return nil
    }

    static func findMatchID(_ json: Any?) -> String? {
        if let d = json as? [String: Any] {
            if let m = d["match_id"] as? String, !m.isEmpty { return m }
            for v in d.values { if let f = findMatchID(v) { return f } }
        } else if let a = json as? [Any] {
            for v in a { if let f = findMatchID(v) { return f } }
        }
        return nil
    }
}

// Anybuddy : disponibilités publiques (site anybuddyapp.com). Paiement par carte : la réservation se termine
// sur la page du créneau, ouverte directement par le bot.
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

    static func clubURL(_ slug: String) -> URL? { URL(string: "https://www.anybuddyapp.com/fr/club/\(slug)") }

    static func slots(slug: String, day: Date) async throws -> [BookingSlot] {
        let tz = TimeZone(identifier: "Europe/Paris")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        let dayString = f.string(from: day)
        var comps = URLComponents(string: "https://www.anybuddyapp.com/api/v1/availabilities")!
        comps.queryItems = [URLQueryItem(name: "clubSlug", value: slug), URLQueryItem(name: "dateFrom", value: dayString),
                            URLQueryItem(name: "dateTo", value: dayString + "T23:59"), URLQueryItem(name: "activity", value: "padel")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://www.anybuddyapp.com", forHTTPHeaderField: "Origin")
        req.setValue("https://www.anybuddyapp.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaytomicError.unavailable("Disponibilités Anybuddy indisponibles.")
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = tz
        local.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var out: [BookingSlot] = []
        for group in root["data"] as? [[String: Any]] ?? [] {
            guard let raw = group["startDateTime"] as? String, let start = local.date(from: String(raw.prefix(16))) else { continue }
            for svc in group["services"] as? [[String: Any]] ?? [] {
                let cents = (svc["discountPrice"] as? NSNumber)?.doubleValue ?? (svc["price"] as? NSNumber)?.doubleValue
                out.append(BookingSlot(provider: .anybuddy, clubID: slug, resourceID: svc["id"] as? String ?? "", courtName: svc["name"] as? String ?? "Padel",
                                       start: start, duration: (svc["duration"] as? NSNumber)?.intValue ?? 60, price: cents.map { $0 / 100 },
                                       currency: "EUR", indoor: nil, timezone: tz.identifier, rawStart: raw,
                                       extra: ["slotId": svc["slotId"] as? String ?? ""]))
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
