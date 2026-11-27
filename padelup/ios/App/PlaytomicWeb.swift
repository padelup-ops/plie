import Foundation
import SwiftUI
import WebKit

// Playtomic via son site web (playtomic.com) : leur API mobile est réservée à leur propre appli (vérification
// d'appareil). Tout se fait depuis l'iPhone du joueur, sans jamais contourner leurs protections :
//  - disponibilités en temps réel : playtomic.com/api/clubs/availability (heures UTC) ;
//  - recherche de clubs : playtomic.com/search (réponse Next.js « RSC ») ;
//  - réservation : la page du club, ouverte dans l'app avec la session Playtomic du joueur (il s'y connecte lui-même :
//    son mot de passe ne passe jamais par PadelUp).
// Les serveurs cloud sont refusés par Playtomic : tout se fait depuis l'iPhone.
struct PlaytomicClub: Identifiable, Hashable {
    let id: String       // identifiant du club (tenant), le même que pour les disponibilités
    let name: String
    let slug: String     // pour la page playtomic.com/clubs/<slug>
    let countryCode: String
    let street: String
    let postalCode: String
}

enum PlaytomicWeb {
    static let site = URL(string: "https://playtomic.com")!

    // MARK: Session du joueur (cookies du site, partagés avec les pages ouvertes dans l'app : voir ProviderWeb.swift)

    static var connected: Bool { WebAccount.isConnected(.playtomic) }

    private static func request(_ url: URL, rsc: Bool = false) async -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(rsc ? "text/x-component" : "application/json", forHTTPHeaderField: "Accept")
        req.setValue("fr-FR,fr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if rsc { req.setValue("1", forHTTPHeaderField: "RSC") }
        // Avec la session du joueur, Playtomic applique ses tarifs (membre, etc.).
        if let cookie = await WebAccount.cookieHeader(domain: "playtomic.com") { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return req
    }

    // MARK: Disponibilités en temps réel

    static func slots(tenantID: String, day: Date, timezone: String?) async throws -> [BookingSlot] {
        let tzName = timezone ?? "Europe/Paris"
        let tz = TimeZone(identifier: tzName) ?? .current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        var comps = URLComponents(string: "https://playtomic.com/api/clubs/availability")!
        comps.queryItems = [URLQueryItem(name: "tenant_id", value: tenantID), URLQueryItem(name: "date", value: f.string(from: day)),
                            URLQueryItem(name: "sport_id", value: "PADEL")]
        let (data, resp) = try await URLSession.shared.data(for: await request(comps.url!))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // Refus ou limitation : on s'arrête (règle du dossier : ne jamais contourner, arrêter si Playtomic bloque).
        if code == 403 || code == 429 { throw PlaytomicError.blockedByPlaytomic }
        guard code == 200, let blocks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PlaytomicError.unavailable("Disponibilités Playtomic indisponibles (\(code)).")
        }
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        // Le site ne donne plus le nom des terrains : « Terrain 1, 2… » dans un ordre stable.
        let resources = Array(Set(blocks.compactMap { $0["resource_id"] as? String })).sorted()
        var out: [BookingSlot] = []
        for block in blocks {
            guard let rid = block["resource_id"] as? String, let startDate = block["start_date"] as? String else { continue }
            let courtName = "Terrain \((resources.firstIndex(of: rid) ?? 0) + 1)"
            for s in block["slots"] as? [[String: Any]] ?? [] {
                guard let time = s["start_time"] as? String, let start = utc.date(from: "\(startDate)T\(time)") else { continue }
                let (price, currency) = PlaytomicPrice.parse(s["price"])
                out.append(BookingSlot(provider: .playtomic, clubID: tenantID, resourceID: rid, courtName: courtName, start: start,
                                       duration: (s["duration"] as? NSNumber)?.intValue ?? 60, price: price, currency: currency,
                                       indoor: nil, timezone: tzName, rawStart: "\(startDate)T\(time)"))
            }
        }
        return out.filter { $0.localDayKey == f.string(from: day) }.sorted { ($0.start, $0.duration, $0.courtName) < ($1.start, $1.duration, $1.courtName) }
    }

    // MARK: Recherche de clubs (page de recherche du site, réponse RSC)

    static func search(_ text: String) async throws -> [PlaytomicClub] {
        var comps = URLComponents(string: "https://playtomic.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: text.trimmingCharacters(in: .whitespaces))]
        let (data, resp) = try await URLSession.shared.data(for: await request(comps.url!, rsc: true))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw PlaytomicError.unavailable("Recherche Playtomic indisponible.") }
        var payload = String(decoding: data, as: UTF8.self)
        var clubs = parseClubs(payload)
        if clubs.isEmpty && payload.contains("\\\"clubs\\\":") {
            payload = payload.replacingOccurrences(of: "\\\"", with: "\"")
            clubs = parseClubs(payload)
        }
        return clubs
    }

    /// Les tableaux « "clubs":[…] » de la réponse, lus en JSON.
    static func parseClubs(_ payload: String) -> [PlaytomicClub] {
        var found: [PlaytomicClub] = []
        var seen = Set<String>()
        let chars = Array(payload.utf8)
        let marker = Array("\"clubs\":[".utf8)
        var i = 0
        while i + marker.count < chars.count {
            if chars[i] == marker[0] && Array(chars[i..<(i + marker.count)]) == marker {
                let start = i + marker.count - 1
                if let end = closingBracket(chars, from: start),
                   let json = try? JSONSerialization.jsonObject(with: Data(chars[start...end])) as? [[String: Any]] {
                    for o in json {
                        guard let id = o["id"] as? String, let name = o["name"] as? String, let slug = o["slug"] as? String,
                              !id.isEmpty, !seen.contains(id) else { continue }
                        seen.insert(id)
                        let addr = o["address"] as? [String: Any] ?? [:]
                        found.append(PlaytomicClub(id: id, name: name.trimmingCharacters(in: .whitespaces), slug: slug,
                                                   countryCode: (o["country_code"] as? String ?? "").uppercased(),
                                                   street: addr["street"] as? String ?? "", postalCode: addr["postal_code"] as? String ?? ""))
                    }
                    i = end
                }
            }
            i += 1
        }
        return found
    }

    private static func closingBracket(_ c: [UInt8], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var i = start
        while i < c.count {
            let ch = c[i]
            if inString {
                if ch == UInt8(ascii: "\\") { i += 1 } else if ch == UInt8(ascii: "\"") { inString = false }
            } else if ch == UInt8(ascii: "\"") {
                inString = true
            } else if ch == UInt8(ascii: "[") {
                depth += 1
            } else if ch == UInt8(ascii: "]") {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// Le club Playtomic qui correspond à un club de la carte (nom proche, même pays si connu).
    static func match(for club: Club) async -> PlaytomicClub? {
        guard !club.name.isEmpty else { return nil }
        let query = [club.name, club.city].filter { !$0.isEmpty }.joined(separator: " ")
        guard let results = try? await search(query) else { return nil }
        return results.first { r in
            ClubDirectory.similar(r.name, club.name) && (club.country.isEmpty || r.countryCode.isEmpty || r.countryCode == club.country)
        }
    }

    // MARK: Réservation

    static func bookingURL(slug: String?, tenantID: String, day: Date, timezone: String?) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: timezone ?? "Europe/Paris") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        if let slug, !slug.isEmpty {
            return URL(string: "https://playtomic.com/clubs/\(slug)?sport=PADEL&date=\(f.string(from: day))")!
        }
        return URL(string: "https://playtomic.io/clubs/\(tenantID)")!
    }
}
