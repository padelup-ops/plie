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
    let id: String       // identifiant du club (tenant), le même que pour les disponibilités ; vide s'il reste à lire
    let name: String
    let slug: String     // pour la page playtomic.com/clubs/<slug>
    let countryCode: String
    let street: String
    let postalCode: String

    /// Identité stable même quand l'identifiant reste à lire sur la page du club.
    var key: String { id.isEmpty ? "slug:" + slug : id }
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
        // 1) Requête directe de l'app.
        var code = 0
        if let result = try? await URLSession.shared.data(for: await request(comps.url!)) {
            let (data, resp) = result
            code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return parseAvailability(blocks, tenantID: tenantID, dayKey: f.string(from: day), tzName: tzName)
            }
        }
        // 2) Sinon, la page Playtomic fait l'appel elle-même, comme sur le site (mêmes en-têtes qu'un navigateur).
        let path = "/api/clubs/availability?" + (comps.percentEncodedQuery ?? "")
        if let page = await HiddenBrowser.shared.pageFetch(origin: site, path: path) {
            if page.status == 200, let blocks = try? JSONSerialization.jsonObject(with: Data(page.body.utf8)) as? [[String: Any]] {
                return parseAvailability(blocks, tenantID: tenantID, dayKey: f.string(from: day), tzName: tzName)
            }
            code = page.status
        }
        // Refus ou limitation : on s'arrête (règle du dossier : ne jamais contourner, arrêter si Playtomic bloque).
        if code == 403 || code == 429 { throw PlaytomicError.blockedByPlaytomic }
        throw PlaytomicError.unavailable("Disponibilités Playtomic indisponibles (\(code)).")
    }

    static func parseAvailability(_ blocks: [[String: Any]], tenantID: String, dayKey: String, tzName: String) -> [BookingSlot] {
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
        return out.filter { $0.localDayKey == dayKey }.sorted { ($0.start, $0.duration, $0.courtName) < ($1.start, $1.duration, $1.courtName) }
    }

    // MARK: Fenêtre de réservation du club (détectée en lisant les créneaux)

    /// Le dernier jour qui a des créneaux libres donne le nombre de jours à l'avance (J-x). Si ce dernier jour ne
    /// commence qu'autour de l'heure actuelle, l'ouverture est « glissante » : chaque créneau ouvre exactement x jours
    /// avant, à la même heure. Sinon la journée entière ouvre d'un coup, à une heure fixée par le club.
    /// Quelques lectures seulement (recherche par dichotomie), gardées 6 heures.
    static func bookingWindow(tenantID: String, timezone: String?) async -> BookingWindow? {
        let key = "bookingWindow." + tenantID
        if let data = UserDefaults.standard.data(forKey: key), let w = try? JSONDecoder().decode(BookingWindow.self, from: data),
           w.checked.timeIntervalSinceNow > -6 * 3600 { return w }
        let tz = TimeZone(identifier: timezone ?? "Europe/Paris") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.startOfDay(for: Date())
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today) ?? today }
        var cache: [Int: [BookingSlot]] = [:]
        func list(_ n: Int) async throws -> [BookingSlot] {
            if let c = cache[n] { return c }
            let s = try await slots(tenantID: tenantID, day: day(n), timezone: timezone)
            cache[n] = s
            return s
        }
        do {
            var open = 0
            var closed: Int? = nil
            for probe in [7, 14, 21, 30] {
                let found = try await list(probe)
                if !found.isEmpty { open = probe } else { closed = probe; break }
            }
            guard var upper = closed else { return nil }   // plus d'un mois à l'avance : pas de limite utile
            var lower = open
            while upper - lower > 1 {
                let mid = (lower + upper) / 2
                let found = try await list(mid)
                if !found.isEmpty { lower = mid } else { upper = mid }
            }
            guard lower > 0 else { return nil }
            let last = try await list(lower)
            let previous = try await list(lower - 1)
            let now = cal.dateComponents([.hour, .minute], from: Date())
            let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            let firstLast = last.map(\.minutesOfDay).min() ?? 0
            let firstPrevious = previous.map(\.minutesOfDay).min() ?? firstLast
            let rolling = firstLast >= firstPrevious + 90 && abs(firstLast - nowMinutes) <= 150
            let w = BookingWindow(days: lower, rolling: rolling, lastDay: day(lower), checked: Date())
            if let data = try? JSONEncoder().encode(w) { UserDefaults.standard.set(data, forKey: key) }
            return w
        } catch {
            return nil
        }
    }

    // MARK: Recherche de clubs (page de recherche du site)
    //
    // La page playtomic.com/search renvoie au plus 30 clubs, classés par nom, dans le monde entier. Ajouter le pays
    // au texte (« Lille france ») sert de filtre, car l'adresse compte dans leur index. La réponse arrive soit en
    // « RSC » (Next.js), soit en HTML avec le même JSON échappé : on lit les deux.

    static func search(_ text: String) async throws -> [PlaytomicClub] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
        guard q.count >= 2 else { return [] }
        let countryWords = ["france", "belgique", "belgium", "suisse", "schweiz", "espana", "españa", "spain", "italia", "maroc", "tunisie", "algerie", "algérie", "luxembourg"]
        let hasCountry = countryWords.contains { q.lowercased().contains($0) }
        let variants = hasCountry ? [q] : [q + " france", q]
        var found: [PlaytomicClub] = []
        var lastStatus = 0
        for variant in variants {
            for rsc in [true, false] {
                var comps = URLComponents(string: "https://playtomic.com/search")!
                comps.queryItems = [URLQueryItem(name: "q", value: variant)] + (rsc ? [URLQueryItem(name: "_rsc", value: "padelup")] : [])
                guard let url = comps.url else { continue }
                let (data, resp) = try await URLSession.shared.data(for: await request(url, rsc: rsc))
                lastStatus = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if lastStatus == 403 || lastStatus == 429 { throw PlaytomicError.blockedByPlaytomic }
                guard lastStatus == 200 else { continue }
                let clubs = parseClubs(String(decoding: data, as: UTF8.self))
                for c in clubs where !found.contains(where: { $0.id == c.id }) { found.append(c) }
                if !found.isEmpty { break }
            }
            if found.count >= 3 { break }
        }
        if found.isEmpty && lastStatus != 200 && lastStatus != 0 {
            throw PlaytomicError.unavailable("Recherche Playtomic indisponible (\(lastStatus)).")
        }
        return rank(found, query: q)
    }

    /// Clubs de la zone PadelUp d'abord, puis ceux dont le nom ou l'adresse contient les mots cherchés.
    static func rank(_ clubs: [PlaytomicClub], query: String) -> [PlaytomicClub] {
        let words = query.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
        func score(_ c: PlaytomicClub) -> Int {
            let hay = "\(c.name) \(c.street) \(c.postalCode)".lowercased().folding(options: .diacriticInsensitive, locale: .current)
            var s = words.filter { hay.contains($0) }.count * 10
            if CoverageZone.countryCodes.contains(c.countryCode) || c.countryCode.isEmpty { s += 5 }
            return s
        }
        return clubs.enumerated().sorted { a, b in
            let sa = score(a.element), sb = score(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    /// Les clubs d'une réponse de recherche, quelle que soit sa forme (RSC, HTML échappé, autre clé que « clubs »).
    static func parseClubs(_ payload: String) -> [PlaytomicClub] {
        var text = payload
        var clubs = clubsArrays(text)
        if clubs.isEmpty && text.contains(#"\"slug\""#) {
            text = text.replacingOccurrences(of: #"\""#, with: "\"")
            clubs = clubsArrays(text)
        }
        if clubs.isEmpty { clubs = objectsAroundSlugs(text) }
        return clubs
    }

    private static let uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

    private static func club(from o: [String: Any]) -> PlaytomicClub? {
        let id = (o["id"] as? String) ?? (o["tenant_id"] as? String) ?? ""
        let name = (o["name"] as? String) ?? (o["tenant_name"] as? String) ?? ""
        guard let slug = o["slug"] as? String, !slug.isEmpty, !name.isEmpty,
              id.range(of: uuidPattern, options: .regularExpression) != nil else { return nil }
        let addr = o["address"] as? [String: Any] ?? [:]
        return PlaytomicClub(id: id.lowercased(), name: name.trimmingCharacters(in: .whitespaces), slug: slug,
                             countryCode: ((o["country_code"] as? String) ?? (addr["country_code"] as? String) ?? "").uppercased(),
                             street: addr["street"] as? String ?? "", postalCode: addr["postal_code"] as? String ?? "")
    }

    /// Les tableaux « "clubs": [ … ] ».
    private static func clubsArrays(_ payload: String) -> [PlaytomicClub] {
        var found: [PlaytomicClub] = []
        let chars = Array(payload.utf8)
        let marker = Array("\"clubs\":".utf8)
        var i = 0
        while i + marker.count < chars.count {
            if chars[i] == marker[0] && Array(chars[i..<(i + marker.count)]) == marker {
                var j = i + marker.count
                while j < chars.count, chars[j] == UInt8(ascii: " ") || chars[j] == UInt8(ascii: "\n") { j += 1 }
                if j < chars.count, chars[j] == UInt8(ascii: "["), let end = closingBracket(chars, from: j),
                   let json = try? JSONSerialization.jsonObject(with: Data(chars[j...end])) as? [[String: Any]] {
                    for o in json { if let c = club(from: o), !found.contains(where: { $0.id == c.id }) { found.append(c) } }
                    i = end
                }
            }
            i += 1
        }
        return found
    }

    /// Filet de sécurité : tout objet JSON qui porte un « slug », un nom et un identifiant de club.
    private static func objectsAroundSlugs(_ payload: String) -> [PlaytomicClub] {
        var found: [PlaytomicClub] = []
        let chars = Array(payload.utf8)
        let marker = Array("\"slug\":\"".utf8)
        var i = 0
        var checked = 0
        while i + marker.count < chars.count && checked < 400 {
            if chars[i] == marker[0] && Array(chars[i..<(i + marker.count)]) == marker {
                checked += 1
                var start = i
                var tries = 0
                while start > 0 && i - start < 1500 && tries < 6 {
                    start -= 1
                    guard chars[start] == UInt8(ascii: "{") else { continue }
                    tries += 1
                    if let end = closingBracket(chars, from: start), end > i,
                       let o = try? JSONSerialization.jsonObject(with: Data(chars[start...end])) as? [String: Any] {
                        if let c = club(from: o), !found.contains(where: { $0.id == c.id }) { found.append(c) }
                        break
                    }
                }
            }
            i += 1
        }
        return found
    }

    private static func closingBracket(_ c: [UInt8], from start: Int) -> Int? {
        let open = c[start]
        let close: UInt8 = open == UInt8(ascii: "[") ? UInt8(ascii: "]") : UInt8(ascii: "}")
        var depth = 0
        var inString = false
        var i = start
        while i < c.count {
            let ch = c[i]
            if inString {
                if ch == UInt8(ascii: "\\") { i += 1 } else if ch == UInt8(ascii: "\"") { inString = false }
            } else if ch == UInt8(ascii: "\"") {
                inString = true
            } else if ch == open {
                depth += 1
            } else if ch == close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    // MARK: Lien collé (partagé depuis l'app ou le site Playtomic)

    /// « playtomic.io/tenant/<uuid> », « playtomic.io/clubs/<uuid> » ou « playtomic.com/clubs/<slug> » → le club.
    static func resolve(link: String) async -> PlaytomicClub? {
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", options: .regularExpression) {
            let id = String(t[r]).lowercased()
            // playtomic.io/clubs/<uuid> redirige vers playtomic.com/clubs/<slug> : on lit le slug à l'arrivée.
            var slug = ""
            if let url = URL(string: "https://playtomic.io/clubs/\(id)"),
               let result = try? await URLSession.shared.data(for: await request(url)),
               let final = result.1.url, final.path.contains("/clubs/") {
                slug = final.lastPathComponent
            }
            let name = slug.isEmpty ? "Club Playtomic" : slug.replacingOccurrences(of: "-", with: " ").capitalized
            return PlaytomicClub(id: id, name: name, slug: slug, countryCode: "", street: "", postalCode: "")
        }
        guard let r = t.range(of: "/clubs/[a-z0-9-]+", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let slug = String(t[r].dropFirst("/clubs/".count)).lowercased()
        guard let url = URL(string: "https://playtomic.com/clubs/\(slug)"),
              let result = try? await URLSession.shared.data(for: await request(url)) else { return nil }
        let html = String(decoding: result.0, as: UTF8.self).replacingOccurrences(of: #"\""#, with: "\"")
        if let c = parseClubs(html).first(where: { $0.slug == slug }) { return c }
        // Identifiant le plus proche avant le slug dans la page.
        guard let k = html.range(of: "\"slug\":\"\(slug)\"") else { return nil }
        let before = html[html.index(k.lowerBound, offsetBy: -min(1500, html.distance(from: html.startIndex, to: k.lowerBound)))..<k.lowerBound]
        let ids = before.matches(of: #/"(?:tenant_)?id":"([0-9a-fA-F-]{36})"/#)
        guard let last = ids.last else { return nil }
        return PlaytomicClub(id: String(last.1).lowercased(), name: slug.replacingOccurrences(of: "-", with: " ").capitalized, slug: slug,
                             countryCode: "", street: "", postalCode: "")
    }

    /// Le club Playtomic qui correspond à un club de la carte (nom proche, même pays si connu).
    static func match(for club: Club) async -> PlaytomicClub? {
        guard !club.name.isEmpty else { return nil }
        func pickSimilar(_ results: [PlaytomicClub]) -> PlaytomicClub? {
            results.first { r in
                ClubDirectory.similar(r.name, club.name) && (club.country.isEmpty || r.countryCode.isEmpty || r.countryCode == club.country)
            }
        }
        for query in [club.name, [club.name, club.city].filter { !$0.isEmpty }.joined(separator: " ")] {
            if let results = try? await search(query), let hit = pickSimilar(results) { return hit }
        }
        // Le site affiche ses résultats avec JavaScript : un navigateur invisible les lit comme Safari.
        if var hit = pickSimilar(await HiddenBrowser.shared.search(club.name)) {
            if hit.id.isEmpty { hit = PlaytomicClub(id: await HiddenBrowser.shared.tenantID(slug: hit.slug) ?? "", name: hit.name, slug: hit.slug,
                                                     countryCode: hit.countryCode, street: hit.street, postalCode: hit.postalCode) }
            return hit.id.isEmpty ? nil : hit
        }
        return nil
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

    /// La page de paiement d'un créneau précis (club, terrain, début en UTC, durée), comme le bouton « Réserver » du
    /// site y mène : rien à cliquer, le joueur arrive sur le paiement et valide lui-même.
    static func paymentURL(_ d: DirectPay) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'.000Z'"
        var c = URLComponents(string: "https://app.playtomic.com/payments")!
        c.queryItems = [
            URLQueryItem(name: "type", value: "CUSTOMER_MATCH"),
            URLQueryItem(name: "tenant_id", value: d.tenantID),
            URLQueryItem(name: "resource_id", value: d.resourceID),
            URLQueryItem(name: "start", value: f.string(from: d.start)),
            URLQueryItem(name: "duration", value: String(d.duration)),
            URLQueryItem(name: "sport_id", value: "PADEL"),
        ]
        return c.url!
    }
}
