import CoreLocation
import Foundation

// Mode « captures » : l'app est lancée avec « -shot nom » (simulateur, workflow GitHub) et ouvre l'écran voulu
// avec des données d'exemple, sans réseau. La saison se choisit avec « -seasonMode christmas ».
enum ShotMode {
    static var current: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-shot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let paris = CLLocation(latitude: 48.8566, longitude: 2.3522)

    static let demoClubs: [Club] = [
        Club(id: "pt:demo-1", name: "Padel Horizon Paris", latitude: 48.8412, longitude: 2.3876, courts: 8, indoor: 8, outdoor: 0,
             city: "Paris", postcode: "75012", street: "12 quai de la Rapée", country: "FR", website: "https://playtomic.io",
             openingHours: "Mo-Su 07:00-23:30", source: .playtomic, playtomicTenantID: "demo-1", timezone: "Europe/Paris"),
        Club(id: "osm:way/1001", name: "Urban Padel Saint-Ouen", latitude: 48.9089, longitude: 2.3330, courts: 6, indoor: 6,
             city: "Saint-Ouen", source: .osm, osmID: "way/1001", playtomicTenantID: "demo-2", timezone: "Europe/Paris"),
        Club(id: "osm:way/1002", name: "Casa Padel Boulogne", latitude: 48.8352, longitude: 2.2410, courts: 5, indoor: 3, outdoor: 2,
             city: "Boulogne-Billancourt", source: .osm, osmID: "way/1002"),
        Club(id: "osm:way/1003", name: "4PADEL Bobigny", latitude: 48.9062, longitude: 2.4390, courts: 10, indoor: 10,
             city: "Bobigny", source: .osm, osmID: "way/1003", anybuddySlug: "4padel-bobigny", timezone: "Europe/Paris"),
        Club(id: "osm:way/1004", name: "Padel Club Vincennes", latitude: 48.8467, longitude: 2.4377, courts: 4, outdoor: 4,
             city: "Vincennes", source: .osm, osmID: "way/1004"),
        Club(id: "osm:way/1005", name: "Le Smash Montreuil", latitude: 48.8610, longitude: 2.4440, courts: 3, indoor: 3,
             city: "Montreuil", source: .osm, osmID: "way/1005"),
        Club(id: "osm:way/1006", name: "Padel Arena La Défense", latitude: 48.8925, longitude: 2.2366, courts: 7, indoor: 7,
             city: "Puteaux", source: .osm, osmID: "way/1006", playtomicTenantID: "demo-3", timezone: "Europe/Paris"),
        Club(id: "osm:way/1007", name: "Padel Lac Tunis", latitude: 36.8380, longitude: 10.2420, courts: 6, outdoor: 6,
             city: "Tunis", country: "TN", source: .osm, osmID: "way/1007"),
    ]

    @MainActor
    static func install(_ shot: String, directory: ClubDirectory, bot: BotEngine, location: LocationManager, server: ServerAPI) {
        directory.installDemo(demoClubs)
        location.setDemo(paris)
        server.setDemo(APIMe(id: 3, username: "camille", email: nil, firstName: "Camille",
                             profile: APIProfile(fullName: "Camille Laurent", skillLevel: 4, tierName: "Intermédiaire", avatarUrl: nil, location: "Lille",
                                                 evaluationType: "new", isCompleted: true, rightHanded: true),
                             stats: APIStats(matchesPlayed: 24, matchesWon: 15, matchesLost: 9, winRate: 62.5, totalHours: 36)))
        bot.rules = [
            BotRule(provider: .playtomic, clubID: "demo-1", clubName: "Padel Horizon Paris", clubCity: "Paris", timezone: "Europe/Paris",
                    weekdays: [1, 3], timeFrom: 19 * 60, timeTo: 21 * 60, durations: [90], maxBookings: 0, bookingsMade: 3,
                    lastCheck: Date(), lastStatus: "Rien de libre pour l'instant · 2 dates surveillées", clubSlug: "padel-horizon-paris",
                    releaseDays: 7, releaseMinutes: 8 * 60),
            BotRule(provider: .anybuddy, clubID: "4padel-bobigny", clubName: "4PADEL Bobigny", clubCity: "Bobigny", timezone: "Europe/Paris",
                    weekdays: [5, 6], timeFrom: 10 * 60, timeTo: 12 * 60, durations: [60, 90], autoBook: false,
                    lastCheck: Date(), lastStatus: "Suivi par la réservation automatique Anybuddy"),
        ]
        if shot == "snipe", let first = bot.rules.first {
            bot.snipe = Snipe(ruleID: first.id, clubName: first.clubName, release: Date().addingTimeInterval(97),
                              day: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(), timezone: "Europe/Paris")
        }
        let slotStart = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
        bot.log = [
            BotLogEntry(date: Date().addingTimeInterval(-540), kind: .booked, clubName: "Padel Horizon Paris",
                        message: "Réservé sur Playtomic · paiement sur place", slotStart: slotStart, court: "Pista 4", price: "36 €"),
            BotLogEntry(date: Date().addingTimeInterval(-3_600), kind: .found, clubName: "Urban Padel Saint-Ouen",
                        message: "Libre · 90 min · Terrain 2", slotStart: slotStart.addingTimeInterval(86_400), court: "Terrain 2", price: "42 €",
                        actionURL: "https://playtomic.com/clubs/urban-padel-saint-ouen"),
            BotLogEntry(date: Date().addingTimeInterval(-86_400), kind: .needsAction, clubName: "Padel Arena La Défense",
                        message: "Ouvert à l'instant · 60 min", slotStart: Date().addingTimeInterval(-3_600), court: "Terrain 5", price: "28 €"),
        ]
    }

    static func route(_ shot: String, router: Router) {
        switch shot {
        case "clubs": router.tab = .clubs
        case "club": router.tab = .clubs; router.openClub = demoClubs[0]
        case "bot", "snipe": router.tab = .bot
        case "matches": router.tab = .matches
        case "profile": router.tab = .profile
        case "match": router.tab = .matches; router.openMatch = demoMatches().first
        case "level": router.tab = .profile; router.showLevel = true
        case "friends": router.tab = .profile; router.showFriends = true
        default: router.tab = .home
        }
    }

    static func demoLeaders() -> [APILeader] {
        let people: [(String, String, Int, Int)] = [("Inès", "Marchand", 41, 31), ("Yacine", "B.", 38, 27), ("Camille", "L.", 24, 15),
                                                     ("Léa", "Morel", 30, 17), ("Sami", "K.", 19, 10)]
        return people.enumerated().map { i, p in
            APILeader(id: i + 1, username: p.0.lowercased(), matchesPlayed: p.2, matchesWon: p.3, winRate: Double(p.3) / Double(p.2) * 100,
                      skillLevel: 5, user: APIUser(id: i + 1, username: p.0.lowercased(), firstName: p.0, lastName: p.1))
        }
    }

    static func demoFriends() -> [APIFriendship] {
        let people: [(String, Int, String)] = [("Yacine Benali", 5, "Lille"), ("Inès Marchand", 6, "Paris"), ("Sami Karoui", 4, "Tunis"), ("Léa Morel", 3, "Genève")]
        return people.enumerated().map { i, p in
            APIFriendship(id: i + 1, friend: APIPerson(id: i + 10, username: nil, fullName: p.0, avatar: nil, skillLevel: p.1, evaluationType: "new",
                                                       city: p.2, isFriend: true, hasPendingRequest: false))
        }
    }

    static func demoMessages() -> [APIMessage] {
        [APIMessage(id: 1, sender: 1, senderName: "Yacine", content: "Qui apporte les balles ?", createdAt: nil),
         APIMessage(id: 2, sender: 3, senderName: "Camille", content: "Moi, un tube neuf.", createdAt: nil),
         APIMessage(id: 3, sender: 2, senderName: "Inès", content: "Parfait, j'arrive 10 min avant.", createdAt: nil)]
    }

    static func demoSlots(for club: Club) -> [BookingSlot] {
        let tz = TimeZone(identifier: "Europe/Paris")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let times: [(Int, Int, String, Double)] = [(9 * 60, 90, "Terrain 1", 28), (10 * 60 + 30, 90, "Terrain 3", 28), (12 * 60, 90, "Terrain 2", 32),
                                                   (17 * 60 + 30, 90, "Terrain 4", 36), (19 * 60, 90, "Terrain 1", 40), (19 * 60, 90, "Terrain 3", 38),
                                                   (19 * 60, 90, "Terrain 5", 40), (19 * 60 + 30, 90, "Terrain 6", 40), (21 * 60, 90, "Terrain 2", 36),
                                                   (22 * 60, 60, "Terrain 5", 24)]
        return times.map { m, d, court, price in
            let start = tomorrow.addingTimeInterval(Double(m) * 60)
            return BookingSlot(provider: .playtomic, clubID: club.playtomicTenantID ?? "demo", resourceID: court, courtName: court, start: start,
                               duration: d, price: price, currency: "EUR", indoor: true, timezone: tz.identifier, rawStart: "\(m):\(court)")
        }
    }

    static func demoWeather() -> [WeatherHour] {
        let start = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: Date()), minute: 0, second: 0, of: Date()) ?? Date()
        return (0..<24).map { i in
            let h = Calendar.current.component(.hour, from: start.addingTimeInterval(Double(i) * 3600))
            let warm = h >= 11 && h <= 17
            return WeatherHour(time: start.addingTimeInterval(Double(i) * 3600), temperature: warm ? 12 : 7, rainChance: i > 14 && i < 18 ? 60 : 10,
                               wind: 12 + Double(i % 5) * 3, code: i > 14 && i < 18 ? 61 : (warm ? 2 : 3))
        }
    }

    static func demoMatches() -> [APIMatch] {
        let base = Date().addingTimeInterval(86_400)
        let iso = ISO8601DateFormatter()
        func p(_ id: Int, _ name: String) -> APIParticipant { APIParticipant(id: id, user: id, userName: name, userAvatar: nil, userSkillLevel: 5, status: "confirmed") }
        return [
            APIMatch(id: 1, title: "Soirée compet' — niveau 5", description: nil, matchType: "competitive", club: 1, clubName: "Padel Horizon Paris",
                     court: 4, courtName: "Pista 4", dateTime: iso.string(from: base.addingTimeInterval(3 * 3600)), duration: 90, organizer: 1, organizerName: "Yacine",
                     maxPlayers: 4, participantsCount: 3, minSkillLevel: 4, maxSkillLevel: 6, pricePerPlayer: "10.00", currency: "EUR", status: "open",
                     isPublic: true, location: APILocation(clubName: "Padel Horizon Paris", address: "12 quai de la Rapée, Paris", latitude: nil, longitude: nil),
                     participants: [p(1, "Yacine"), p(2, "Inès"), p(3, "Camille")]),
            APIMatch(id: 2, title: "Matinale du samedi", description: nil, matchType: "casual", club: 2, clubName: "4PADEL Bobigny",
                     court: nil, courtName: nil, dateTime: iso.string(from: base.addingTimeInterval(2 * 86_400)), duration: 90, organizer: 4, organizerName: "Sami",
                     maxPlayers: 4, participantsCount: 2, minSkillLevel: 2, maxSkillLevel: 5, pricePerPlayer: "9.00", currency: "EUR", status: "open",
                     isPublic: true, location: APILocation(clubName: "4PADEL Bobigny", address: "Bobigny", latitude: nil, longitude: nil),
                     participants: [p(4, "Sami"), p(5, "Léa")]),
        ]
    }
}
