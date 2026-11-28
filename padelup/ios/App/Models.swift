import CoreLocation
import Foundation
import MapKit

enum ClubSource: String, Codable {
    case osm, playtomic, padelup

    var label: String {
        switch self {
        case .osm: return "OpenStreetMap"
        case .playtomic: return "Playtomic"
        case .padelup: return "PadelUp"
        }
    }
}

struct Club: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var courts: Int = 0
    var indoor: Int = 0
    var outdoor: Int = 0
    var city: String = ""
    var postcode: String = ""
    var street: String = ""
    var country: String = ""
    var website: String = ""
    var phone: String = ""
    var email: String = ""
    var openingHours: String = ""
    var source: ClubSource = .osm
    var osmID: String? = nil
    var playtomicTenantID: String? = nil
    var anybuddySlug: String? = nil
    var timezone: String? = nil
    var imageURL: String? = nil
    var backendID: Int? = nil
    var playtomicSlug: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var displayName: String { name.isEmpty ? "Terrains de padel" : name }

    var place: String {
        let parts = [street, [postcode, city].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }
        return parts.isEmpty ? String(format: "%.4f, %.4f", latitude, longitude) : parts.joined(separator: ", ")
    }

    var courtsLabel: String {
        guard courts > 0 else { return "Terrains" }
        return courts == 1 ? "1 terrain" : "\(courts) terrains"
    }

    var isMostlyIndoor: Bool { indoor > 0 && indoor >= outdoor }

    /// « 8 terrains couverts », « 5 terrains dont 3 couverts »…
    var courtsSummary: String {
        guard courts > 0 else { return "" }
        let n = courts == 1 ? "1 terrain" : "\(courts) terrains"
        if indoor >= courts { return n + (courts == 1 ? " couvert" : " couverts") }
        if outdoor >= courts { return n + (courts == 1 ? " extérieur" : " extérieurs") }
        if indoor > 0 { return n + " dont \(indoor) couvert" + (indoor > 1 ? "s" : "") }
        return n
    }

    var subtitle: String {
        let parts = [city, courtsSummary].filter { !$0.isEmpty }
        return parts.isEmpty ? "Terrains de padel" : parts.joined(separator: " · ")
    }
    var canBookWithBot: Bool { playtomicTenantID != nil || anybuddySlug != nil || (backendID != nil && courts > 0) }

    func distance(from location: CLLocation?) -> Double? {
        guard let location else { return nil }
        return location.distance(from: self.location)
    }
}

func formatDistance(_ meters: Double?) -> String {
    guard let meters else { return "" }
    if meters < 1000 { return "\(Int(meters.rounded())) m" }
    if meters < 100_000 { return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",") }
    return "\(Int((meters / 1000).rounded())) km"
}

// Créneau réservable (Playtomic, Anybuddy ou club PadelUp).
/// Montants affichés à la française (« 9 € », « 12,17 € »), et la part de chacun quand on partage un terrain.
enum Money {
    static func label(_ value: Double, currency: String = "EUR") -> String {
        let cents = (value * 100).rounded() / 100
        let amount = cents.rounded() == cents ? String(Int(cents)) : String(format: "%.2f", cents).replacingOccurrences(of: ".", with: ",")
        return currency == "EUR" ? "\(amount) €" : "\(amount) \(currency)"
    }

    /// La part de chacun, arrondie au centime supérieur : l'organisateur n'y est jamais de sa poche.
    static func share(total: Double, players: Int) -> Double {
        guard players > 0 else { return total }
        return (total * 100 / Double(players)).rounded(.up) / 100
    }

    /// « 36 », « 36,50 », « 36.5 € » → 36.5
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v
    }
}

struct BookingSlot: Identifiable, Hashable, Codable {
    var provider: BotProvider
    var clubID: String
    var resourceID: String
    var courtName: String
    var start: Date
    var duration: Int
    var price: Double?
    var currency: String
    var indoor: Bool?
    var timezone: String
    var rawStart: String
    var extra: [String: String] = [:]

    var id: String { "\(provider.rawValue):\(clubID):\(resourceID):\(rawStart):\(duration)" }

    var priceLabel: String {
        guard let price else { return "" }
        return Money.label(price, currency: currency)
    }

    var timeZoneValue: TimeZone { TimeZone(identifier: timezone) ?? .current }

    var localTime: String {
        let f = DateFormatter()
        f.timeZone = timeZoneValue
        f.dateFormat = "HH:mm"
        return f.string(from: start)
    }

    var localDayKey: String {
        let f = DateFormatter()
        f.timeZone = timeZoneValue
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }

    var minutesOfDay: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZoneValue
        let c = cal.dateComponents([.hour, .minute], from: start)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 0 = lundi ... 6 = dimanche (comme le serveur)
    var weekdayIndex: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZoneValue
        return (cal.component(.weekday, from: start) + 5) % 7
    }
}

enum BotProvider: String, Codable, CaseIterable, Identifiable {
    case playtomic, anybuddy, padelup

    var id: String { rawValue }

    var name: String {
        switch self {
        case .playtomic: return "Playtomic"
        case .anybuddy: return "Anybuddy"
        case .padelup: return "PadelUp"
        }
    }

    var color: (Double, Double, Double) {
        switch self {
        case .playtomic: return (0.20, 0.85, 0.60)
        case .anybuddy: return (1.0, 0.45, 0.35)
        case .padelup: return (0.83, 1.0, 0.23)
        }
    }

    /// Ce que le bot sait faire tout seul sur cette plateforme.
    var automationNote: String {
        switch self {
        case .playtomic:
            return "Je lis les créneaux en direct sur Playtomic, depuis ton iPhone. Dès qu'un créneau correspond, je t'ouvre la réservation déjà remplie : tu confirmes en un geste."
        case .anybuddy:
            return "Les créneaux sont lus sur la page Anybuddy du club, comme tu la verrais, depuis ton iPhone. Si Anybuddy demande une vérification, on s'arrête et la page s'ouvre pour toi. La réservation se termine sur Anybuddy, déjà connecté."
        case .padelup:
            return "Réservation directe et immédiate dans les clubs partenaires PadelUp."
        }
    }
}

/// Combien de jours à l'avance un club ouvre ses créneaux, et comment.
struct BookingWindow: Codable, Hashable {
    let days: Int          // J-x
    let rolling: Bool      // glissant : chaque créneau ouvre x jours avant, à la même heure
    let lastDay: Date      // dernier jour réservable aujourd'hui
    let checked: Date

    var title: String { "Réservable \(days) jour\(days > 1 ? "s" : "") à l'avance" }

    func explanation(example minutes: Int = 19 * 60) -> String {
        let h = BotRule.hhmm(minutes)
        if rolling {
            return "Ouverture glissante : chaque créneau ouvre exactement \(days) jours avant, à la même heure. Le \(h) du \(FR.shortDay(lastDay.addingTimeInterval(86_400))) ouvrira demain à \(h)."
        }
        return "La journée entière ouvre d'un coup, \(days) jours à l'avance, à une heure fixée par le club (souvent minuit ou 8 h) : vérifie ses règles de réservation."
    }
}

enum BookingOutcomeStatus: String, Codable {
    case booked, needsAction, failed, authError
}

struct BookingOutcome {
    var status: BookingOutcomeStatus
    var message: String
    var externalID: String = ""
    var actionURL: URL? = nil
}

struct WeatherHour: Identifiable {
    var time: Date
    var temperature: Double
    var rainChance: Int
    var wind: Double
    var code: Int

    var id: Date { time }

    /// Indice de jeu en extérieur sur 100 (pluie, vent, température).
    var playScore: Int {
        var score = 100.0
        score -= Double(rainChance) * 0.9
        if wind > 20 { score -= (wind - 20) * 2.2 }
        if temperature < 10 { score -= (10 - temperature) * 4 }
        if temperature > 31 { score -= (temperature - 31) * 5 }
        return max(0, min(100, Int(score.rounded())))
    }

    var symbol: String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
