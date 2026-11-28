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
    static func install(_ shot: String, directory: ClubDirectory, bot: BotEngine, location: LocationManager, server: ServerAPI, favorites: Favorites) {
        directory.installDemo(demoClubs)
        favorites.setDemo([demoClubs[0], demoClubs[3]])
        location.setDemo(paris)
        server.setDemo(APIMe(id: 3, username: "camille", email: nil, firstName: "Camille",
                             profile: APIProfile(fullName: "Camille Laurent", skillLevel: 4, tierName: "Intermédiaire", avatarUrl: nil, location: "Lille",
                                                 evaluationType: "new", isCompleted: true, rightHanded: true),
                             stats: APIStats(matchesPlayed: 24, matchesWon: 15, matchesLost: 9, winRate: 62.5, totalHours: 36)))
        bot.rules = [
            BotRule(provider: .playtomic, clubID: "demo-1", clubName: "Padel Horizon Paris", clubCity: "Paris", timezone: "Europe/Paris",
                    weekdays: [1, 3], timeFrom: 18 * 60, timeTo: 21 * 60 + 30, durations: [90], maxBookings: 0, bookingsMade: 3,
                    lastCheck: Date(), lastStatus: "Je guette… rien de libre pour l'instant.", clubSlug: "padel-horizon-paris",
                    releaseDays: 7, releaseMinutes: 8 * 60),
            BotRule(provider: .anybuddy, clubID: "4padel-bobigny", clubName: "4PADEL Bobigny", clubCity: "Bobigny", timezone: "Europe/Paris",
                    weekdays: [5, 6], timeFrom: 8 * 60, timeTo: 11 * 60 + 30, durations: [90], autoBook: false,
                    lastCheck: Date(), lastStatus: "Trouvé ! 2 créneaux libres samedi matin."),
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
        case "bot", "snipe", "wizard", "wizard-moment", "wizard-ticket": router.tab = .bot
        case "radar": router.tab = .matches
        case "community": router.tab = .home; router.sheet = .community
        case "player": router.tab = .matches; router.sheet = .player(10)
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

    static func demoRadar() -> [APIRadarPlayer] {
        func avail(_ id: Int, _ day: Int, _ slot: TimeSlot) -> APIAvailability {
            APIAvailability(id: id, dayOfWeek: day, specificDate: nil, timeSlot: slot.rawValue, timeSlotDisplay: slot.label, radiusKm: 10,
                            minSkill: 3, maxSkill: 6, locationText: nil)
        }
        let people: [(Int, String, Int, String, Double, Bool, [APIAvailability])] = [
            (10, "Yacine", 5, "Paris 11e", 1.5, true, [avail(1, 1, .evening), avail(2, 3, .evening)]),
            (11, "Inès", 4, "Montreuil", 3.0, false, [avail(3, 5, .morning)]),
            (12, "Sami", 4, "Vincennes", 4.5, false, [avail(4, 2, .noon), avail(5, 6, .afternoon)]),
            (13, "Léa", 3, "Paris 20e", 6.0, false, []),
            (14, "Malik", 5, "Bobigny", 9.5, true, [avail(6, 4, .night)]),
            (15, "Chloé", 4, "Saint-Ouen", 12.0, false, [avail(7, 0, .evening)]),
        ]
        return people.map { p in
            APIRadarPlayer(userId: p.0, username: p.1.lowercased(), firstName: p.1, avatar: nil, skillLevel: p.2, evaluationType: "new",
                           tierName: PadelLevel.name(p.2, scale: "new"), city: p.3, distanceKm: p.4, matchesPlayed: 20, winRate: 55,
                           isFriend: p.5, hasPendingProposal: p.0 == 11, availability: p.6)
        }
    }

    static func demoProposals() -> APIProposals {
        let day = ISO8601DateFormatter.day.string(from: Date().addingTimeInterval(3 * 86_400))
        let later = ISO8601DateFormatter.day.string(from: Date().addingTimeInterval(5 * 86_400))
        return APIProposals(
            sent: [APIProposal(id: 2, senderId: 3, senderUsername: "camille", senderFirstName: "Camille", receiverId: 11, receiverUsername: "ines",
                               receiverFirstName: "Inès", proposedDate: later, proposedTimeSlot: "morning", timeSlotDisplay: "Matin", message: nil,
                               locationText: "Padel Horizon Paris", status: "pending", statusDisplay: "En attente")],
            received: [APIProposal(id: 1, senderId: 12, senderUsername: "sami", senderFirstName: "Sami", receiverId: 3, receiverUsername: "camille",
                                   receiverFirstName: "Camille", proposedDate: day, proposedTimeSlot: "evening", timeSlotDisplay: "Soir",
                                   message: "Partant pour un 2 contre 2 ?", locationText: "Vincennes", status: "pending", statusDisplay: "En attente")])
    }

    static func demoAvailabilities() -> [APIAvailability] {
        [APIAvailability(id: 1, dayOfWeek: 1, specificDate: nil, timeSlot: "evening", timeSlotDisplay: "Soir", radiusKm: 10, minSkill: 3, maxSkill: 5, locationText: nil),
         APIAvailability(id: 2, dayOfWeek: 5, specificDate: nil, timeSlot: "morning", timeSlotDisplay: "Matin", radiusKm: 15, minSkill: 3, maxSkill: 5, locationText: nil)]
    }

    static func demoPublicProfile() -> APIPublicProfile {
        APIPublicProfile(user: APIUser(id: 10, username: "yacine", firstName: "Yacine", lastName: "Benali"),
                         profile: APIProfile(fullName: "Yacine Benali", skillLevel: 5, tierName: "Confirmé", avatarUrl: nil, location: "Paris 11e",
                                             evaluationType: "new", isCompleted: true, rightHanded: false,
                                             bio: "Joueur de gauche, bandeja solide. Dispo le mardi et le jeudi soir."),
                         stats: APIStats(matchesPlayed: 38, matchesWon: 27, matchesLost: 11, winRate: 71, totalHours: 57),
                         isFriend: true, isOwnProfile: false, friendRequest: nil)
    }

    static func demoPosts() -> [APIPost] {
        let iso = ISO8601DateFormatter()
        return [
            APIPost(id: 1, authorInfo: APIAuthor(id: 10, username: "yacine", avatar: nil), title: "Cherche un 4e jeudi 19 h",
                    content: "Padel Horizon Paris, terrain réservé, niveau 4 à 5. Il manque une personne, on partage les 40 €.",
                    category: "looking_for_players", categoryDisplay: "Recherche de joueurs", city: "Paris", likeCount: 4, replyCount: 2,
                    isLiked: false, replies: [APIReply(id: 1, authorInfo: APIAuthor(id: 11, username: "ines", avatar: nil), content: "Je viens !", createdAt: nil)],
                    createdAt: iso.string(from: Date().addingTimeInterval(-2 * 3600))),
            APIPost(id: 2, authorInfo: APIAuthor(id: 12, username: "sami", avatar: nil), title: "La bandeja, enfin",
                    content: "Astuce de mon coach : frapper la balle sur le côté, épaule vers le filet, et finir le geste vers la vitre latérale.",
                    category: "tips", categoryDisplay: "Conseils & Astuces", city: "Tunis", likeCount: 12, replyCount: 3, isLiked: true, replies: [],
                    createdAt: iso.string(from: Date().addingTimeInterval(-26 * 3600))),
        ]
    }

    static func demoHistory() -> [APIMatch] {
        demoMatches().map { m in
            APIMatch(id: m.id + 100, title: m.id == 1 ? "Revanche du dimanche" : "Match amical", description: nil, matchType: m.matchType, club: m.club,
                     clubName: m.clubName, court: m.court, courtName: m.courtName,
                     dateTime: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(m.id) * 6 * 86_400)), duration: 90,
                     organizer: m.organizer, organizerName: m.organizerName, maxPlayers: 4, participantsCount: 4, minSkillLevel: m.minSkillLevel,
                     maxSkillLevel: m.maxSkillLevel, pricePerPlayer: m.pricePerPlayer, currency: "EUR", status: "completed", isPublic: true,
                     location: m.location, participants: m.participants)
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
