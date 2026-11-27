import CoreLocation
import Foundation

// Le reste de ce que fait PadelUp : radar des joueurs, profils publics, profil modifiable, mot de passe,
// outils de l'organisateur, réservations dans les clubs partenaires, communauté.

// MARK: - Modèles

enum TimeSlot: String, CaseIterable, Identifiable, Codable {
    case morning, noon, afternoon, evening, night
    var id: String { rawValue }
    var label: String {
        switch self {
        case .morning: return "Matin"
        case .noon: return "Midi"
        case .afternoon: return "Après-midi"
        case .evening: return "Soir"
        case .night: return "Nuit"
        }
    }
    var hours: String {
        switch self {
        case .morning: return "8–12 h"
        case .noon: return "12–14 h"
        case .afternoon: return "14–18 h"
        case .evening: return "18–21 h"
        case .night: return "21–24 h"
        }
    }
}

struct APIAvailability: Codable, Identifiable, Hashable {
    let id: Int
    let dayOfWeek: Int?
    let specificDate: String?
    let timeSlot: String
    let timeSlotDisplay: String?
    let radiusKm: Int?
    let minSkill: Int?
    let maxSkill: Int?
    let locationText: String?

    var slot: TimeSlot? { TimeSlot(rawValue: timeSlot) }
    var dayLabel: String {
        if let d = dayOfWeek, (0...6).contains(d) { return ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"][d] }
        if let s = specificDate, let date = ISO8601DateFormatter.day.date(from: s) { return FR.string(date, "EEEE d MMM").capitalized }
        return ""
    }
}

struct APIRadarPlayer: Codable, Identifiable, Hashable {
    let userId: Int
    let username: String
    let firstName: String?
    let avatar: String?
    let skillLevel: Int?
    let evaluationType: String?
    let tierName: String?
    let city: String?
    let distanceKm: Double
    let matchesPlayed: Int?
    let winRate: Double?
    let isFriend: Bool?
    let hasPendingProposal: Bool?
    let availability: [APIAvailability]?

    var id: Int { userId }
    var name: String { (firstName?.isEmpty == false ? firstName : nil) ?? username }
}

struct APIRadar: Codable { let results: [APIRadarPlayer]; let count: Int?; let radiusKm: Int?; let visible: Bool? }

struct APIProposal: Codable, Identifiable, Hashable {
    let id: Int
    let senderId: Int?
    let senderUsername: String
    let senderFirstName: String?
    let receiverId: Int?
    let receiverUsername: String
    let receiverFirstName: String?
    let proposedDate: String
    let proposedTimeSlot: String
    let timeSlotDisplay: String?
    let message: String?
    let locationText: String?
    let status: String
    let statusDisplay: String?

    var date: Date? { ISO8601DateFormatter.day.date(from: proposedDate) }
    var senderName: String { (senderFirstName?.isEmpty == false ? senderFirstName : nil) ?? senderUsername }
    var receiverName: String { (receiverFirstName?.isEmpty == false ? receiverFirstName : nil) ?? receiverUsername }
}

struct APIProposals: Codable { let sent: [APIProposal]; let received: [APIProposal] }

struct APIPublicProfile: Codable {
    let user: APIUser
    let profile: APIProfile?
    let stats: APIStats?
    let isFriend: Bool?
    let isOwnProfile: Bool?
    let friendRequest: APIFriendRequest?

    var name: String {
        if let f = profile?.fullName, !f.isEmpty { return f }
        let n = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? (user.username ?? "Joueur") : n
    }
}

struct APIBooking: Codable, Identifiable, Hashable {
    let id: Int
    let courtName: String?
    let clubName: String?
    let date: String
    let startTime: String
    let endTime: String?
    let duration: Int?
    let status: String?
    let statusDisplay: String?
    let totalAmount: String?
    let currency: String?

    var day: Date? { ISO8601DateFormatter.day.date(from: date) }
    var isUpcoming: Bool { (day ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) && status != "cancelled" }
}

struct APIAuthor: Codable, Hashable { let id: Int; let username: String?; let avatar: String? }

struct APIReply: Codable, Identifiable, Hashable {
    let id: Int
    let authorInfo: APIAuthor?
    let content: String
    let createdAt: String?
}

struct APIPost: Codable, Identifiable, Hashable {
    let id: Int
    let authorInfo: APIAuthor?
    let title: String
    let content: String
    let category: String?
    let categoryDisplay: String?
    let city: String?
    let likeCount: Int?
    let replyCount: Int?
    let isLiked: Bool?
    let replies: [APIReply]?
    let createdAt: String?

    var date: Date? {
        guard let createdAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }
}

enum PostCategory: String, CaseIterable, Identifiable {
    case general, looking_for_players, tips, tournaments, equipment, clubs
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "Général"
        case .looking_for_players: return "Cherche joueurs"
        case .tips: return "Conseils"
        case .tournaments: return "Tournois"
        case .equipment: return "Matériel"
        case .clubs: return "Clubs"
        }
    }
}

extension ISO8601DateFormatter {
    /// « 2026-11-28 »
    static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

// MARK: - Appels

extension ServerAPI {
    // Radar
    func radar(near c: CLLocationCoordinate2D, radiusKm: Int, minSkill: Int, maxSkill: Int, slot: TimeSlot?) async throws -> APIRadar {
        var q = [URLQueryItem(name: "lat", value: String(format: "%.4f", c.latitude)), URLQueryItem(name: "lng", value: String(format: "%.4f", c.longitude)),
                 URLQueryItem(name: "radius_km", value: "\(radiusKm)"), URLQueryItem(name: "min_skill", value: "\(minSkill)"),
                 URLQueryItem(name: "max_skill", value: "\(maxSkill)")]
        if let slot { q.append(URLQueryItem(name: "time_slot", value: slot.rawValue)) }
        return try decoder.decode(APIRadar.self, from: try await call("GET", "radar/", query: q))
    }

    /// Apparaître sur le radar (position arrondie à ~1 km par le serveur), ou disparaître.
    func setRadarVisible(_ visible: Bool, at c: CLLocationCoordinate2D?) async throws {
        if visible, let c {
            _ = try await call("PATCH", "radar/", body: ["lat": c.latitude, "lng": c.longitude, "visible": true])
        } else {
            _ = try await call("DELETE", "radar/")
        }
    }

    func availabilities() async throws -> [APIAvailability] {
        try decoder.decode([APIAvailability].self, from: try await call("GET", "availabilities/"))
    }

    func addAvailability(day: Int?, date: Date?, slot: TimeSlot, radiusKm: Int) async throws {
        var body: [String: Any] = ["time_slot": slot.rawValue, "radius_km": radiusKm]
        if let day { body["day_of_week"] = day }
        if let date { body["specific_date"] = ISO8601DateFormatter.day.string(from: date) }
        _ = try await call("POST", "availabilities/", body: body)
    }

    func deleteAvailability(_ id: Int) async throws { _ = try await call("DELETE", "availabilities/\(id)/") }

    func proposals() async throws -> APIProposals {
        try decoder.decode(APIProposals.self, from: try await call("GET", "proposals/"))
    }

    func propose(to userID: Int, date: Date, slot: TimeSlot, message: String, place: String) async throws {
        _ = try await call("POST", "proposals/", body: ["receiver_id": userID, "proposed_date": ISO8601DateFormatter.day.string(from: date),
                                                        "proposed_time_slot": slot.rawValue, "message": message, "location_text": place])
    }

    func answerProposal(_ id: Int, accept: Bool) async throws {
        _ = try await call("PUT", "proposals/\(id)/", body: ["action": accept ? "accept" : "decline"])
    }

    func cancelProposal(_ id: Int) async throws { _ = try await call("DELETE", "proposals/\(id)/") }

    // Profils
    func publicProfile(_ userID: Int) async throws -> APIPublicProfile {
        try decoder.decode(APIPublicProfile.self, from: try await call("GET", "profile/\(userID)/"))
    }

    func updateProfileDetails(fullName: String, bio: String, location: String, rightHanded: Bool) async throws {
        _ = try await call("PUT", "profile/", body: ["full_name": fullName, "bio": bio, "location": location, "right_handed": rightHanded])
        await refreshMe()
    }

    func deleteAccount() async throws {
        _ = try await call("DELETE", "profile/")
        logout()
    }

    // Mot de passe
    func requestPasswordReset(email: String) async throws { _ = try await call("POST", "auth/password-reset/", body: ["email": email]) }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        _ = try await call("POST", "auth/password-reset/confirm/", body: ["email": email, "code": code, "new_password": newPassword])
    }

    func changePassword(old: String, new: String) async throws {
        let data = try await call("POST", "auth/change-password/", body: ["old_password": old, "new_password": new])
        // Le serveur révoque les anciens jetons et peut en renvoyer un nouveau.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = json["token"] as? String { token = t }
    }

    func resendCode(email: String) async throws { _ = try await call("POST", "auth/register/resend/", body: ["email": email]) }

    // Matchs : historique et outils de l'organisateur
    func matchHistory() async throws -> [APIMatch] {
        let data = try await call("GET", "matches/", query: [URLQueryItem(name: "my_matches", value: "true"),
                                                             URLQueryItem(name: "status", value: "completed")])
        if let page = try? decoder.decode(APIPage<APIMatch>.self, from: data), let r = page.results { return r }
        return (try? decoder.decode([APIMatch].self, from: data)) ?? []
    }

    func updateMatch(_ id: Int, title: String, date: Date, duration: Int, minLevel: Int, maxLevel: Int, isPublic: Bool) async throws {
        _ = try await call("PUT", "matches/\(id)/", body: ["title": title, "date_time": ISO8601DateFormatter().string(from: date), "duration": duration,
                                                           "min_skill_level": minLevel, "max_skill_level": maxLevel, "is_public": isPublic])
    }

    func cancelMatch(_ id: Int) async throws { _ = try await call("PUT", "matches/\(id)/", body: ["action": "cancel"]) }

    func deleteMatch(_ id: Int) async throws { _ = try await call("DELETE", "matches/\(id)/") }

    func removeParticipant(match: Int, participant: Int) async throws {
        _ = try await call("DELETE", "matches/\(match)/participants/\(participant)/")
    }

    func invite(match: Int, friends: [Int]) async throws {
        _ = try await call("POST", "matches/\(match)/invite/", body: ["friend_ids": friends])
    }

    // Réservations dans les clubs partenaires
    func myBookings() async throws -> [APIBooking] {
        let data = try await call("GET", "bookings/")
        if let page = try? decoder.decode(APIPage<APIBooking>.self, from: data), let r = page.results { return r }
        return (try? decoder.decode([APIBooking].self, from: data)) ?? []
    }

    func cancelBooking(_ id: Int) async throws { _ = try await call("DELETE", "bookings/\(id)/") }

    // Communauté
    func posts(category: PostCategory?) async throws -> [APIPost] {
        var q: [URLQueryItem] = []
        if let category { q.append(URLQueryItem(name: "category", value: category.rawValue)) }
        let data = try await call("GET", "community/posts/", query: q)
        if let page = try? decoder.decode(APIPage<APIPost>.self, from: data), let r = page.results { return r }
        return (try? decoder.decode([APIPost].self, from: data)) ?? []
    }

    func createPost(title: String, content: String, category: PostCategory, city: String) async throws {
        _ = try await call("POST", "community/posts/", body: ["title": title, "content": content, "category": category.rawValue, "city": city])
    }

    func toggleLike(_ postID: Int) async throws -> Bool {
        let data = try await call("POST", "community/posts/\(postID)/like/")
        return ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["liked"] as? Bool) ?? false
    }

    func replies(_ postID: Int) async throws -> [APIReply] {
        try decoder.decode([APIReply].self, from: try await call("GET", "community/posts/\(postID)/replies/"))
    }

    func reply(_ postID: Int, content: String) async throws {
        _ = try await call("POST", "community/posts/\(postID)/replies/", body: ["content": content])
    }
}

// MARK: - Clubs favoris (sur l'iPhone, marche aussi sans compte)

@MainActor
final class Favorites: ObservableObject {
    static let shared = Favorites()
    @Published private(set) var clubs: [Club] = []
    private let key = "favoriteClubs"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([Club].self, from: data) { clubs = list }
    }

    func contains(_ club: Club) -> Bool { clubs.contains { $0.id == club.id } }

    func toggle(_ club: Club) {
        if contains(club) { clubs.removeAll { $0.id == club.id } } else { clubs.insert(club, at: 0) }
        if let data = try? JSONEncoder().encode(clubs) { UserDefaults.standard.set(data, forKey: key) }
    }

    func setDemo(_ list: [Club]) { clubs = list }
}
