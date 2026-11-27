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
        let amount = price.rounded() == price ? String(Int(price)) : String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
        return currency == "EUR" ? "\(amount) €" : "\(amount) \(currency)"
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
            return "Depuis novembre 2026, Playtomic n'accepte plus la connexion des applications tierces (vérification d'appareil) : le bot ne peut pas réserver chez eux tant qu'ils n'ouvrent pas d'accès partenaire. Les clubs partenaires PadelUp, eux, sont réservés automatiquement."
        case .anybuddy:
            return "Le bot surveille les créneaux à la seconde et lance la réservation ; Anybuddy fait payer par carte, la validation finale se fait en un geste."
        case .padelup:
            return "Réservation directe et immédiate dans les clubs partenaires PadelUp."
        }
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
