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
    static func install(_ shot: String, directory: ClubDirectory, bot: BotEngine, location: LocationManager) {
        directory.installDemo(demoClubs)
        location.setDemo(paris)
        bot.rules = [
            BotRule(provider: .playtomic, clubID: "demo-1", clubName: "Padel Horizon Paris", clubCity: "Paris", timezone: "Europe/Paris",
                    weekdays: [1, 3], timeFrom: 19 * 60, timeTo: 21 * 60, durations: [90], maxBookings: 0, bookingsMade: 3,
                    lastCheck: Date(), lastStatus: "Réservé : jeudi 3 déc. à 19:30, Pista 4"),
            BotRule(provider: .anybuddy, clubID: "4padel-bobigny", clubName: "4PADEL Bobigny", clubCity: "Bobigny", timezone: "Europe/Paris",
                    weekdays: [5, 6], timeFrom: 10 * 60, timeTo: 12 * 60, durations: [60, 90], autoBook: false,
                    lastCheck: Date(), lastStatus: "2 créneaux libres repérés"),
        ]
        let slotStart = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
        bot.log = [
            BotLogEntry(date: Date().addingTimeInterval(-540), kind: .booked, clubName: "Padel Horizon Paris",
                        message: "Réservé sur Playtomic ✅ (paiement sur place)", slotStart: slotStart, court: "Pista 4", price: "36 €"),
            BotLogEntry(date: Date().addingTimeInterval(-3_600), kind: .found, clubName: "4PADEL Bobigny",
                        message: "Créneau libre repéré : samedi 10:30, 90 min", slotStart: slotStart, court: "Padel 2", price: "42 €",
                        actionURL: "https://www.anybuddyapp.com/fr/club/4padel-bobigny"),
        ]
    }

    static func route(_ shot: String, router: Router) {
        switch shot {
        case "clubs": router.tab = .clubs
        case "club": router.tab = .clubs; router.openClub = demoClubs[0]
        case "bot": router.tab = .bot
        case "matches": router.tab = .matches
        case "profile": router.tab = .profile
        default: router.tab = .home
        }
    }

    static func demoSlots(for club: Club) -> [BookingSlot] {
        let tz = TimeZone(identifier: "Europe/Paris")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let times: [(Int, Int, String, Double)] = [(9 * 60, 90, "Pista 1", 28), (10 * 60 + 30, 90, "Pista 3", 28), (12 * 60, 90, "Pista 2", 32),
                                                   (17 * 60 + 30, 90, "Pista 4", 36), (19 * 60, 90, "Pista 1", 40), (19 * 60 + 30, 90, "Pista 6", 40),
                                                   (21 * 60, 90, "Pista 2", 36), (22 * 60, 60, "Pista 5", 24)]
        return times.map { m, d, court, price in
            let start = tomorrow.addingTimeInterval(Double(m) * 60)
            return BookingSlot(provider: .playtomic, clubID: club.playtomicTenantID ?? "demo", resourceID: court, courtName: court, start: start,
                               duration: d, price: price, currency: "EUR", indoor: true, timezone: tz.identifier, rawStart: "\(m)")
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
        func p(_ id: Int, _ name: String) -> APIParticipant { APIParticipant(id: id, userName: name, userAvatar: nil, userSkillLevel: 5, status: "confirmed") }
        return [
            APIMatch(id: 1, title: "Soirée compet' — niveau 5", description: nil, matchType: "competitive", club: 1, clubName: "Padel Horizon Paris",
                     courtName: "Pista 4", dateTime: iso.string(from: base.addingTimeInterval(3 * 3600)), duration: 90, organizerName: "Yacine",
                     maxPlayers: 4, participantsCount: 3, minSkillLevel: 4, maxSkillLevel: 6, pricePerPlayer: "10.00", currency: "EUR", status: "open",
                     isPublic: true, location: APILocation(clubName: "Padel Horizon Paris", address: "12 quai de la Rapée, Paris", latitude: nil, longitude: nil),
                     participants: [p(1, "Yacine"), p(2, "Inès"), p(3, "Hamza")]),
            APIMatch(id: 2, title: "Matinale du samedi", description: nil, matchType: "casual", club: 2, clubName: "4PADEL Bobigny",
                     courtName: nil, dateTime: iso.string(from: base.addingTimeInterval(2 * 86_400)), duration: 90, organizerName: "Sami",
                     maxPlayers: 4, participantsCount: 2, minSkillLevel: 2, maxSkillLevel: 5, pricePerPlayer: "9.00", currency: "EUR", status: "open",
                     isPublic: true, location: APILocation(clubName: "4PADEL Bobigny", address: "Bobigny", latitude: nil, longitude: nil),
                     participants: [p(4, "Sami"), p(5, "Léa")]),
        ]
    }
}
