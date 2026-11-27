import CoreLocation
import Foundation
import MapKit

// Clubs de padel de la zone PadelUp (France, Belgique, Suisse, pays frontaliers de la France, Maroc, Algérie, Tunisie),
// sans passer par le serveur PadelUp :
// 1. le fichier OpenStreetMap embarqué dans l'app (hors ligne, instantané) ;
// 2. une mise à jour en direct de la zone affichée via l'API Overpass (OpenStreetMap) ;
// 3. les clubs Playtomic de la zone (leur recherche publique), fusionnés avec les clubs OSM proches.

/// Zone couverte : contours simplifiés (rectangles) des pays retenus.
enum CoverageZone {
    static let countries = "France, Belgique, Suisse, Luxembourg, Allemagne, Italie, Monaco, Andorre, Espagne, Maroc, Algérie, Tunisie"
    static let short = "France, pays voisins et Maghreb"

    // (sud, ouest, nord, est)
    private static let boxes: [(Double, Double, Double, Double)] = [
        (41.3, -5.3, 51.2, 9.7),     // France (Corse comprise), Monaco
        (49.4, 2.5, 51.6, 6.5),      // Belgique, Luxembourg
        (47.2, 5.8, 55.1, 15.1),     // Allemagne
        (45.8, 5.9, 47.9, 10.6),     // Suisse
        (35.4, 6.6, 47.1, 18.6),     // Italie (Sicile, Sardaigne)
        (35.9, -9.4, 43.9, 4.4),     // Espagne (Baléares), Andorre
        (27.6, -18.2, 29.5, -13.4),  // Canaries
        (27.6, -13.2, 35.95, -1.0),  // Maroc
        (18.9, -8.7, 37.1, 12.0),    // Algérie
        (30.2, 7.5, 37.6, 11.7),     // Tunisie
    ]

    static func contains(latitude: Double, longitude: Double) -> Bool {
        boxes.contains { latitude >= $0.0 && longitude >= $0.1 && latitude <= $0.2 && longitude <= $0.3 }
    }

    static let overview = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.5, longitude: 4.5),
                                             span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 24))
}
@MainActor
final class ClubDirectory: ObservableObject {
    static let shared = ClubDirectory()

    @Published private(set) var loaded = false
    @Published private(set) var totalCount = 0
    @Published private(set) var liveStatus = ""
    @Published private(set) var revision = 0

    private var clubs: [String: Club] = [:]
    private var grid: [GridKey: [String]] = [:]
    private var refreshing = Set<String>()
    private var lastLiveRefresh: [String: Date] = [:]

    struct GridKey: Hashable { let x: Int; let y: Int }

    private func key(_ lat: Double, _ lon: Double) -> GridKey { GridKey(x: Int(floor(lat)), y: Int(floor(lon))) }

    func load() async {
        guard !loaded else { return }
        let loadedClubs = await Task.detached(priority: .userInitiated) { () -> [Club] in
            var all = Self.decodeBundled()
            all.append(contentsOf: Self.loadCache())
            return all
        }.value
        for club in loadedClubs { insert(club) }
        loaded = true
        totalCount = clubs.count
        revision += 1
    }

    nonisolated private static func decodeBundled() -> [Club] {
        guard let url = Bundle.main.url(forResource: "clubs-zone", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decodeCompact(data)
    }

    nonisolated static func decodeCompact(_ data: Data) -> [Club] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["clubs"] as? [[Any]] else { return [] }
        let fields = (root["fields"] as? [String]) ?? []
        func idx(_ name: String) -> Int? { fields.firstIndex(of: name) }
        let iID = idx("id"), iName = idx("name"), iLat = idx("lat"), iLon = idx("lon"), iCourts = idx("courts"),
            iIn = idx("indoor"), iOut = idx("outdoor"), iCity = idx("city"), iPost = idx("postcode"),
            iStreet = idx("street"), iCountry = idx("country"), iWeb = idx("website"), iPhone = idx("phone"),
            iMail = idx("email"), iHours = idx("opening_hours")
        func str(_ row: [Any], _ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] as? String : nil } ?? "" }
        func num(_ row: [Any], _ i: Int?) -> Double? {
            guard let i, i < row.count else { return nil }
            if let d = row[i] as? Double { return d }
            if let n = row[i] as? NSNumber { return n.doubleValue }
            return nil
        }
        var out: [Club] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard let lat = num(row, iLat), let lon = num(row, iLon) else { continue }
            let osm = str(row, iID)
            out.append(Club(id: "osm:" + osm, name: str(row, iName), latitude: lat, longitude: lon,
                            courts: Int(num(row, iCourts) ?? 0), indoor: Int(num(row, iIn) ?? 0), outdoor: Int(num(row, iOut) ?? 0),
                            city: str(row, iCity), postcode: str(row, iPost), street: str(row, iStreet), country: str(row, iCountry),
                            website: str(row, iWeb), phone: str(row, iPhone), email: str(row, iMail), openingHours: str(row, iHours),
                            source: .osm, osmID: osm))
        }
        return out
    }

    private func insert(_ club: Club) {
        if let old = clubs[club.id] {
            let k = key(old.latitude, old.longitude)
            grid[k]?.removeAll { $0 == club.id }
        }
        clubs[club.id] = club
        grid[key(club.latitude, club.longitude), default: []].append(club.id)
    }

    func club(id: String) -> Club? { clubs[id] }

    /// Clubs dans la zone visible, les plus proches du centre d'abord.
    func clubs(in region: MKCoordinateRegion, limit: Int = 300) -> [Club] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        var found: [Club] = []
        let x0 = Int(floor(minLat)), x1 = Int(floor(maxLat))
        let y0 = Int(floor(minLon)), y1 = Int(floor(maxLon))
        if (x1 - x0 + 1) * (y1 - y0 + 1) > 1600 {
            // Vue très large (continent, monde) : on parcourt tout, c'est plus rapide que les cases.
            found = clubs.values.filter { $0.latitude >= minLat && $0.latitude <= maxLat && $0.longitude >= minLon && $0.longitude <= maxLon }
        } else {
            for x in x0...x1 {
                for y in y0...y1 {
                    for id in grid[GridKey(x: x, y: y)] ?? [] {
                        if let c = clubs[id], c.latitude >= minLat, c.latitude <= maxLat, c.longitude >= minLon, c.longitude <= maxLon {
                            found.append(c)
                        }
                    }
                }
            }
        }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        if found.count > limit {
            // Beaucoup de clubs : on garde les plus grands et les plus proches du centre.
            found.sort { ($0.courts, -$0.location.distance(from: center)) > ($1.courts, -$1.location.distance(from: center)) }
            found = Array(found.prefix(limit))
        }
        return found.sorted { $0.location.distance(from: center) < $1.location.distance(from: center) }
    }

    func nearest(to location: CLLocation, limit: Int = 30, maxKm: Double = 80) -> [Club] {
        var radius = 1
        var found: [Club] = []
        let k = key(location.coordinate.latitude, location.coordinate.longitude)
        while found.count < limit && radius <= 4 {
            found = []
            for x in (k.x - radius)...(k.x + radius) {
                for y in (k.y - radius)...(k.y + radius) {
                    for id in grid[GridKey(x: x, y: y)] ?? [] { if let c = clubs[id] { found.append(c) } }
                }
            }
            radius += 1
        }
        return found
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= maxKm * 1000 }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    func search(_ text: String, near location: CLLocation?, limit: Int = 40) -> [Club] {
        let q = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var hits: [Club] = []
        for c in clubs.values {
            let hay = (c.name + " " + c.city).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if hay.contains(q) { hits.append(c) }
            if hits.count > 2000 { break }
        }
        if let location {
            hits.sort { $0.location.distance(from: location) < $1.location.distance(from: location) }
        } else {
            hits.sort { $0.courts > $1.courts }
        }
        return Array(hits.prefix(limit))
    }

    // MARK: - En direct : OpenStreetMap (Overpass) et Playtomic pour la zone affichée

    func refreshLive(region: MKCoordinateRegion) async {
        guard region.span.latitudeDelta < 1.2, region.span.longitudeDelta < 1.6 else {
            liveStatus = "Zoome pour actualiser les clubs en direct"
            return
        }
        guard CoverageZone.contains(latitude: region.center.latitude, longitude: region.center.longitude) else {
            liveStatus = "Hors zone PadelUp (\(CoverageZone.short))"
            return
        }
        let zoneKey = "\(Int(region.center.latitude * 20)):\(Int(region.center.longitude * 20))"
        if refreshing.contains(zoneKey) { return }
        if let last = lastLiveRefresh[zoneKey], Date().timeIntervalSince(last) < 600 { return }
        refreshing.insert(zoneKey)
        defer { refreshing.remove(zoneKey) }
        liveStatus = "Actualisation OpenStreetMap…"
        let s = region.center.latitude - region.span.latitudeDelta / 2
        let n = region.center.latitude + region.span.latitudeDelta / 2
        let w = region.center.longitude - region.span.longitudeDelta / 2
        let e = region.center.longitude + region.span.longitudeDelta / 2
        var added = 0
        do {
            let fresh = try await Overpass.clubs(south: s, west: w, north: n, east: e)
                .filter { CoverageZone.contains(latitude: $0.latitude, longitude: $0.longitude) }
            for c in fresh {
                if var existing = clubs[c.id] {
                    existing.name = c.name.isEmpty ? existing.name : c.name
                    existing.courts = max(existing.courts, c.courts)
                    existing.website = c.website.isEmpty ? existing.website : c.website
                    existing.phone = c.phone.isEmpty ? existing.phone : c.phone
                    insert(existing)
                } else {
                    insert(c)
                    added += 1
                }
            }
            lastLiveRefresh[zoneKey] = Date()
            liveStatus = added > 0 ? "\(added) nouveau(x) club(s) OpenStreetMap" : "Zone à jour (OpenStreetMap)"
        } catch {
            liveStatus = "OpenStreetMap indisponible, données embarquées"
        }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let radiusKm = max(5, min(60, region.span.latitudeDelta * 111 / 2))
        if let tenants = try? await PlaytomicAPI.shared.tenants(near: center.coordinate, radiusKm: radiusKm) {
            for t in tenants where CoverageZone.contains(latitude: t.latitude, longitude: t.longitude) { merge(playtomic: t) }
        }
        totalCount = clubs.count
        revision += 1
        saveCache()
    }

    /// Un club Playtomic : s'il correspond à un club OSM proche, on l'y rattache, sinon il devient un club à part.
    func merge(playtomic t: Club) {
        guard let tenant = t.playtomicTenantID else { return }
        if clubs.values.contains(where: { $0.playtomicTenantID == tenant }) { return }
        let candidates = nearest(to: t.location, limit: 8, maxKm: 0.35)
        if var host = candidates.first(where: { Self.similar($0.name, t.name) || $0.location.distance(from: t.location) < 120 }) {
            host.playtomicTenantID = tenant
            host.timezone = t.timezone
            if host.name.isEmpty { host.name = t.name }
            if host.imageURL == nil { host.imageURL = t.imageURL }
            if host.courts == 0 { host.courts = t.courts }
            insert(host)
        } else {
            insert(t)
        }
    }

    nonisolated static func similar(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let stop: Set<String> = ["padel", "club", "de", "du", "la", "le", "les", "the", "center", "centre", "sport", "sports"]
            return Set(folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 && !stop.contains($0) })
        }
        let wa = words(a), wb = words(b)
        return !wa.isEmpty && !wa.isDisjoint(with: wb)
    }

    // Les clubs vus en direct sont gardés en cache (l'app reste utile hors ligne).
    nonisolated private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("clubs-live.json")
    }

    nonisolated private static func loadCache() -> [Club] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([Club].self, from: data)) ?? []
    }

    private func saveCache() {
        let live = clubs.values.filter { $0.source != .osm || $0.playtomicTenantID != nil || $0.id.hasPrefix("osm:live") }
        let snapshot = Array(live.prefix(5000))
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: Self.cacheURL, options: .atomic) }
        }
    }

    /// Démo pour les captures d'écran (mode « -shot »).
    func installDemo(_ demo: [Club]) {
        for c in demo { insert(c) }
        loaded = true
        totalCount = clubs.count
        revision += 1
    }
}

// MARK: - Overpass (OpenStreetMap)

enum Overpass {
    static let mirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]

    static func clubs(south: Double, west: Double, north: Double, east: Double) async throws -> [Club] {
        let query = String(format: "[out:json][timeout:25];nwr[\"sport\"~\"(^|;)padel(;|$)\"](%.5f,%.5f,%.5f,%.5f);out center tags;",
                           south, west, north, east)
        var lastError: Error = URLError(.badServerResponse)
        for mirror in mirrors {
            guard let url = URL(string: mirror) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            req.httpBody = body.data(using: .utf8)
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let elements = root?["elements"] as? [[String: Any]] ?? []
                return group(elements)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private struct Venue {
        var club: Club
        var courts = 0
        var indoor = 0
        var outdoor = 0
    }

    /// Même regroupement que le serveur (app/opendata.py) : les terrains rejoignent le lieu nommé le plus proche.
    static func group(_ elements: [[String: Any]]) -> [Club] {
        var venues: [Venue] = []
        var pitches: [(CLLocation, [String: String], String)] = []
        for el in elements {
            guard let type = el["type"] as? String, let id = (el["id"] as? NSNumber)?.int64Value else { continue }
            let tags = (el["tags"] as? [String: String]) ?? [:]
            var lat = (el["lat"] as? NSNumber)?.doubleValue
            var lon = (el["lon"] as? NSNumber)?.doubleValue
            if lat == nil, let c = el["center"] as? [String: Any] {
                lat = (c["lat"] as? NSNumber)?.doubleValue
                lon = (c["lon"] as? NSNumber)?.doubleValue
            }
            guard let lat, let lon, tags["access"] != "private", tags["access"] != "no" else { continue }
            let osm = "\(type)/\(id)"
            if tags["leisure"] == "pitch" {
                pitches.append((CLLocation(latitude: lat, longitude: lon), tags, osm))
            } else {
                venues.append(Venue(club: club(osm: osm, lat: lat, lon: lon, tags: tags)))
            }
        }
        for (loc, tags, osm) in pitches {
            var best: Int? = nil
            var bestD = 300.0
            for (i, v) in venues.enumerated() {
                let d = v.club.location.distance(from: loc)
                if d < bestD { best = i; bestD = d }
            }
            if best == nil {
                // pas de lieu cartographié : les terrains proches forment un club à eux seuls
                for (i, v) in venues.enumerated() where v.club.id.hasPrefix("osm:") && v.club.location.distance(from: loc) < 200 {
                    best = i; break
                }
            }
            let index: Int
            if let best { index = best } else {
                venues.append(Venue(club: club(osm: osm, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, tags: tags)))
                index = venues.count - 1
            }
            if venues[index].club.name.isEmpty, let name = tags["name"] { venues[index].club.name = name }
            if venues[index].club.city.isEmpty, let city = tags["addr:city"] { venues[index].club.city = city }
            venues[index].courts += Int(tags["courts"] ?? "") ?? 1
            if tags["indoor"] == "yes" || tags["covered"] == "yes" { venues[index].indoor += 1 }
            else if tags["indoor"] == "no" || tags["covered"] == "no" { venues[index].outdoor += 1 }
        }
        return venues.compactMap { v in
            var c = v.club
            c.courts = v.courts
            c.indoor = v.indoor
            c.outdoor = v.outdoor
            return (c.courts == 0 && c.name.isEmpty) ? nil : c
        }
    }

    private static func club(osm: String, lat: Double, lon: Double, tags: [String: String]) -> Club {
        var website = (tags["website"] ?? tags["contact:website"] ?? tags["url"] ?? "").components(separatedBy: ";").first ?? ""
        if !website.isEmpty && !website.hasPrefix("http") { website = "https://" + website }
        let street = [tags["addr:housenumber"], tags["addr:street"]].compactMap { $0 }.joined(separator: " ")
        return Club(id: "osm:" + osm, name: tags["name"] ?? tags["operator"] ?? "", latitude: lat, longitude: lon,
                    city: tags["addr:city"] ?? tags["addr:town"] ?? tags["addr:village"] ?? "", postcode: tags["addr:postcode"] ?? "",
                    street: street, country: (tags["addr:country"] ?? "").uppercased(), website: website,
                    phone: (tags["phone"] ?? tags["contact:phone"] ?? "").components(separatedBy: ";").first ?? "",
                    email: tags["email"] ?? tags["contact:email"] ?? "", openingHours: tags["opening_hours"] ?? "",
                    source: .osm, osmID: osm)
    }
}

// MARK: - Recherche de lieux (villes, pays) avec MapKit, partout dans le monde

enum PlaceSearch {
    struct Place: Identifiable, Hashable {
        var id: String { "\(name)|\(latitude)|\(longitude)" }
        var name: String
        var detail: String
        var latitude: Double
        var longitude: Double
        var spanKm: Double
    }

    static func search(_ text: String) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address]
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(8).compactMap { item in
            let pm = item.placemark
            let name = item.name ?? pm.locality ?? text
            let detail = [pm.administrativeArea, pm.country].compactMap { $0 }.joined(separator: ", ")
            let span: Double = pm.locality != nil ? 25 : (pm.administrativeArea != nil ? 150 : 600)
            return Place(name: name, detail: detail, latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude, spanKm: span)
        }
    }
}
