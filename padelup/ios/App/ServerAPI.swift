import Foundation

// Serveur PadelUp (backend Django du dépôt padelup/backend) : compte joueur, matchs, classement,
// et bot 24 h/24 (le serveur réserve même quand l'iPhone est éteint).
struct APIUser: Codable, Hashable { let id: Int; let username: String?; let firstName: String?; let lastName: String? }

struct APIProfile: Codable, Hashable {
    let fullName: String?
    let skillLevel: Int?
    let tierName: String?
    let avatarUrl: String?
    let location: String?
    let evaluationType: String?
    let isCompleted: Bool?
}

struct APIStats: Codable, Hashable {
    let matchesPlayed: Int?
    let matchesWon: Int?
    let matchesLost: Int?
    let winRate: Double?
    let totalHours: Double?
}

struct APIMe: Codable { let id: Int; let username: String; let email: String?; let firstName: String?; let profile: APIProfile?; let stats: APIStats? }

struct APILeader: Codable, Identifiable, Hashable {
    let id: Int
    let username: String?
    let matchesPlayed: Int?
    let matchesWon: Int?
    let winRate: Double?
    let skillLevel: Int?
    let user: APIUser?

    var displayName: String { [user?.firstName, user?.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces).isEmpty ? (username ?? user?.username ?? "Joueur") : [user?.firstName, user?.lastName].compactMap { $0 }.joined(separator: " ") }
}

struct APIParticipant: Codable, Hashable, Identifiable { let id: Int; let userName: String?; let userAvatar: String?; let userSkillLevel: Int?; let status: String? }
struct APILocation: Codable, Hashable { let clubName: String?; let address: String?; let latitude: Double?; let longitude: Double? }

struct APIMatch: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let description: String?
    let matchType: String?
    let club: Int?
    let clubName: String?
    let courtName: String?
    let dateTime: String
    let duration: Int?
    let organizerName: String?
    let maxPlayers: Int?
    let participantsCount: Int?
    let minSkillLevel: Int?
    let maxSkillLevel: Int?
    let pricePerPlayer: String?
    let currency: String?
    let status: String?
    let isPublic: Bool?
    let location: APILocation?
    let participants: [APIParticipant]?

    var date: Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: dateTime) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: dateTime)
    }

    var spotsLeft: Int { max(0, (maxPlayers ?? 4) - (participantsCount ?? 1)) }

    var typeLabel: String {
        switch matchType {
        case "competitive": return "Compétitif"
        case "tournament": return "Tournoi"
        case "training": return "Entraînement"
        default: return "Amical"
        }
    }
}

struct APIPage<T: Codable>: Codable { let results: [T]? }

struct ServerError: LocalizedError {
    let message: String
    var reconnect = false
    var errorDescription: String? { message }
}

@MainActor
final class ServerAPI: ObservableObject {
    static let shared = ServerAPI()

    @Published private(set) var me: APIMe? = nil
    @Published var token: String? = Keychain.get("padelup.token").flatMap { String(data: $0, encoding: .utf8) } {
        didSet { Keychain.set(token?.data(using: .utf8), for: "padelup.token") }
    }

    var isLoggedIn: Bool { token != nil }
    var botServerEnabled: Bool { isLoggedIn && UserDefaults.standard.object(forKey: "botServer") as? Bool ?? true }

    var baseURL: URL {
        let custom = UserDefaults.standard.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = Bundle.main.object(forInfoDictionaryKey: "PadelUpAPIBaseURL") as? String ?? "https://padelup-api.onrender.com/api"
        var s = custom.isEmpty ? fallback : custom
        if !s.hasSuffix("/") { s += "/" }
        return URL(string: s) ?? URL(string: "https://padelup-api.onrender.com/api/")!
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: HTTP

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw ServerError(message: "Adresse du serveur invalide.") }
        var req = URLRequest(url: url, timeoutInterval: 40)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Token " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ServerError(message: "Serveur PadelUp injoignable. Vérifie l'adresse dans Réglages.")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && path.hasPrefix("bot/") == false && token != nil {
            token = nil
            me = nil
        }
        guard (200..<300).contains(code) else { throw Self.error(from: data, code: code) }
        return data
    }

    private static func error(from data: Data, code: Int) -> ServerError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let reconnect = json?["reconnect"] as? Bool ?? false
        if let m = json?["error"] as? String { return ServerError(message: m, reconnect: reconnect) }
        if let m = json?["detail"] as? String { return ServerError(message: m, reconnect: reconnect) }
        if let first = json?.values.compactMap({ ($0 as? [String])?.first }).first { return ServerError(message: first) }
        return ServerError(message: code >= 500 ? "Le serveur PadelUp a un souci, réessaie." : "Requête refusée (\(code)).")
    }

    // MARK: Compte

    func login(identifier: String, password: String) async throws {
        let key = identifier.contains("@") ? "email" : "username"
        let data = try await call("POST", "auth/login/", body: [key: identifier, "password": password])
        try storeToken(data)
        await refreshMe()
    }

    /// Renvoie true si un code de confirmation a été envoyé par e-mail.
    func register(username: String, email: String, password: String, fullName: String) async throws -> Bool {
        let data = try await call("POST", "auth/register/", body: ["username": username, "email": email, "password": password,
                                                                    "password2": password, "full_name": fullName])
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["verification_required"] as? Bool ?? true
    }

    func verify(email: String, code: String) async throws {
        let data = try await call("POST", "auth/register/verify/", body: ["email": email, "code": code])
        try storeToken(data)
        await refreshMe()
    }

    func appleLogin(identityToken: String, firstName: String?, lastName: String?) async throws {
        let data = try await call("POST", "auth/apple/", body: ["identity_token": identityToken, "first_name": firstName ?? "",
                                                                 "last_name": lastName ?? ""])
        try storeToken(data)
        await refreshMe()
    }

    private func storeToken(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = json["token"] as? String else {
            throw ServerError(message: "Réponse de connexion inattendue.")
        }
        token = t
    }

    func logout() {
        me = nil
        Task {
            _ = try? await call("POST", "auth/logout/")  // révoque le jeton côté serveur
            token = nil
        }
    }

    func refreshMe() async {
        guard isLoggedIn, let data = try? await call("GET", "profile/") else { return }
        me = try? decoder.decode(APIMe.self, from: data)
    }

    // MARK: Clubs partenaires (tableau de bord PadelUp), lecture publique

    func partnerClubs(maxPages: Int = 10) async -> [Club] {
        var out: [Club] = []
        for page in 1...maxPages {
            guard let data = try? await call("GET", "clubs/", query: [URLQueryItem(name: "page", value: String(page)),
                                                                     URLQueryItem(name: "page_size", value: "100")]),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            for c in json["results"] as? [[String: Any]] ?? [] {
                func text(_ k: String) -> String { (c[k] as? String) ?? "" }
                func number(_ k: String) -> Double? { (c[k] as? NSNumber)?.doubleValue ?? (c[k] as? String).flatMap(Double.init) }
                guard let id = c["id"] as? Int, let lat = number("latitude"), let lon = number("longitude") else { continue }
                let courts = c["courts"] as? [[String: Any]] ?? []
                let indoor = courts.filter { $0["is_indoor"] as? Bool == true }.count
                out.append(Club(id: "pu:\(id)", name: text("name"), latitude: lat, longitude: lon, courts: courts.count, indoor: indoor,
                                outdoor: courts.count - indoor, city: text("city"), postcode: text("postal_code"), street: text("address"),
                                country: text("country"), website: text("website"), phone: text("phone"), email: text("email"),
                                source: .padelup, osmID: text("osm_id").isEmpty ? nil : text("osm_id"),
                                playtomicTenantID: text("playtomic_tenant_id").isEmpty ? nil : text("playtomic_tenant_id"),
                                anybuddySlug: text("anybuddy_slug").isEmpty ? nil : text("anybuddy_slug"), backendID: id))
            }
            if json["next"] == nil || json["next"] is NSNull { break }
        }
        return out
    }

    // MARK: Matchs et classement

    func matches(mine: Bool = false) async throws -> [APIMatch] {
        var q = [URLQueryItem(name: "page", value: "1")]
        if mine { q.append(URLQueryItem(name: "my_matches", value: "true")) }
        let data = try await call("GET", "matches/", query: q)
        if let page = try? decoder.decode(APIPage<APIMatch>.self, from: data), let r = page.results { return r }
        return (try? decoder.decode([APIMatch].self, from: data)) ?? []
    }

    func join(matchID: Int) async throws { _ = try await call("POST", "matches/\(matchID)/join/") }
    func leave(matchID: Int) async throws { _ = try await call("DELETE", "matches/\(matchID)/join/") }

    func leaderboard() async throws -> [APILeader] {
        let data = try await call("GET", "leaderboard/", query: [URLQueryItem(name: "limit", value: "50")])
        return try decoder.decode([APILeader].self, from: data)
    }

    /// Un club OpenStreetMap devient un club PadelUp (pour y créer un match).
    func adoptClub(_ club: Club) async throws -> Int {
        if let id = club.backendID { return id }
        guard let osm = club.osmID else { throw ServerError(message: "Ce club n'a pas d'identifiant OpenStreetMap.") }
        let data = try await call("POST", "clubs/from-osm/", body: ["osm_id": osm, "name": club.name])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? Int else {
            throw ServerError(message: "Club non ajouté.")
        }
        return id
    }

    func createMatch(club: Club, date: Date, duration: Int, title: String, maxPlayers: Int, minLevel: Int, maxLevel: Int,
                     isPublic: Bool, price: Double) async throws -> APIMatch {
        let clubID = try await adoptClub(club)
        let iso = ISO8601DateFormatter()
        let data = try await call("POST", "matches/", body: [
            "club": clubID, "date_time": iso.string(from: date), "duration": duration, "title": title, "max_players": maxPlayers,
            "min_skill_level": minLevel, "max_skill_level": maxLevel, "is_public": isPublic, "price_per_player": String(format: "%.2f", price),
        ])
        return try decoder.decode(APIMatch.self, from: data)
    }

    // MARK: Bot 24 h/24 sur le serveur

    func connectBotAccount(provider: BotProvider, email: String, password: String) async throws {
        _ = try await call("POST", "bot/accounts/", body: ["provider": provider.rawValue, "email": email, "password": password])
    }

    func botSlots(provider: BotProvider, clubID: String, day: Date) async throws -> [BookingSlot] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let data = try await call("GET", "bot/slots/", query: [URLQueryItem(name: "provider", value: provider.rawValue),
                                                               URLQueryItem(name: "club_id", value: clubID),
                                                               URLQueryItem(name: "date", value: f.string(from: day))])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let iso = ISO8601DateFormatter()
        var out: [BookingSlot] = []
        for block in json["days"] as? [[String: Any]] ?? [] {
            for s in block["slots"] as? [[String: Any]] ?? [] {
                guard let startString = s["start"] as? String, let start = iso.date(from: startString) else { continue }
                out.append(BookingSlot(provider: provider, clubID: s["club_id"] as? String ?? clubID, resourceID: s["resource_id"] as? String ?? "",
                                       courtName: s["court_name"] as? String ?? "Terrain", start: start, duration: s["duration"] as? Int ?? 60,
                                       price: (s["price"] as? String).flatMap(Double.init), currency: s["currency"] as? String ?? "EUR",
                                       indoor: s["indoor"] as? Bool, timezone: (s["timezone"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? TimeZone.current.identifier,
                                       rawStart: s["raw_start"] as? String ?? startString))
            }
        }
        return out
    }

    func botBook(_ slot: BookingSlot, clubName: String) async throws -> BookingOutcome {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "provider": slot.provider.rawValue, "club_name": clubName,
            "slot": ["club_id": slot.clubID, "resource_id": slot.resourceID, "court_name": slot.courtName, "start": iso.string(from: slot.start),
                     "duration": slot.duration, "price": slot.price.map { String($0) as Any } ?? NSNull(), "currency": slot.currency,
                     "timezone": slot.timezone, "raw_start": slot.rawStart] as [String: Any],
        ]
        do {
            let data = try await call("POST", "bot/book/", body: payload)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let status = json["status"] as? String ?? ""
            let url = (json["action_url"] as? String).flatMap(URL.init(string:))
            return BookingOutcome(status: status == "booked" ? .booked : .needsAction, message: json["message"] as? String ?? "", actionURL: url)
        } catch let e as ServerError {
            return BookingOutcome(status: e.reconnect ? .authError : .failed, message: e.message)
        }
    }

    /// La règle part sur le serveur : il la surveille 24 h/24. Renvoie l'identifiant de la règle serveur.
    func pushRule(_ rule: BotRule) async throws -> Int {
        let data = try await call("POST", "bot/rules/", body: [
            "provider": rule.provider.rawValue, "club_external_id": rule.clubID, "club_name": rule.clubName, "club_city": rule.clubCity,
            "club_timezone": rule.timezone, "weekdays": Array(rule.weekdays).sorted(), "time_from": BotRule.hhmm(rule.timeFrom),
            "time_to": BotRule.hhmm(rule.timeTo), "durations": rule.durations, "court_preference": rule.court.rawValue,
            "max_price": rule.maxPrice.map { String(format: "%.2f", $0) as Any } ?? NSNull(), "days_ahead": rule.daysAhead,
            "min_notice_minutes": rule.minNoticeMinutes, "mode": rule.autoBook ? "book" : "notify", "max_bookings": rule.maxBookings,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? Int else {
            throw ServerError(message: "Règle non enregistrée sur le serveur.")
        }
        return id
    }

    func serverRuleStatus(_ id: Int) async -> (active: Bool, status: String, message: String)? {
        guard let data = try? await call("GET", "bot/rules/\(id)/"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["is_active"] as? Bool ?? false, json["last_status"] as? String ?? "", json["last_message"] as? String ?? "")
    }

    func deleteServerRule(_ id: Int) async { _ = try? await call("DELETE", "bot/rules/\(id)/") }
}
