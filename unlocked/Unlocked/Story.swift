import SwiftUI

// MARK: - La langue
//
// Le contenu des histoires est écrit en français et en anglais côte à côte : T("…", "…").

enum Lang {
    static let french: Bool = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")
}

func T(_ fr: String, _ en: String) -> String { Lang.french ? fr : en }

// MARK: - Ce que contient un téléphone

struct Contact: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    var initials: String { String(name.prefix(1)).uppercased() }
}

/// Un message d'une conversation. `fromMe` = envoyé par le propriétaire du téléphone (ou par le joueur).
struct Message: Identifiable, Hashable {
    let id: String
    let thread: String
    let fromMe: Bool
    let text: String
    let time: String
    var photo: String? = nil
}

struct Conversation: Identifiable {
    let id: String
    let contact: String
    let history: [Message]
}

enum Illustration: String {
    case pixelSleeping, polaroidPixel, birthday, loireSunset, studio, coffee, trainWindow, flowers, catOnDesk
    case streetStudio, streetHome, parkGate, station
}

struct PhotoItem: Identifiable {
    let id: String
    let art: Illustration
    let date: String
    let place: String
    /// Ce qui est écrit au dos (on retourne la photo d'un toucher).
    var back: String? = nil
    /// Une voiture garée dans le décor, à cet endroit (0…1) : on la touche pour relever sa plaque.
    var car: CGPoint? = nil
}

/// Un album protégé par un code.
struct HiddenAlbum {
    let title: String
    let code: String
    let hints: [String]
    let photos: [PhotoItem]
    let plate: String
}

/// Un rendez-vous de l'agenda.
struct CalendarEvent: Identifiable {
    let id: String
    let day: String
    let time: String
    let title: String
    var detail: String = ""
    var color: Color = .blue
}

/// Un chapitre : le fait qui le termine, et la carte de fin.
struct Chapter {
    let title: String
    let end: String
    let endText: String
    /// Le fait posé quand le chapitre commence (les messages en direct du chapitre en dépendent).
    let start: String
}

struct Note: Identifiable {
    let id: String
    let title: String
    let body: String
    let date: String
    var pinned = false
    /// La note n'apparaît qu'une fois ce fait connu.
    var requires: String? = nil
}

struct Voicemail: Identifiable {
    let id: String
    let contact: String
    let date: String
    let seconds: Int
    let transcript: String
}

/// Un message qui arrive en direct, `delay` secondes après que `after` est devenu vrai.
struct LiveMessage: Identifiable {
    let id: String
    let after: String
    let delay: Double
    let message: Message
    var sets: String? = nil
}

/// Une réponse que le joueur peut envoyer, proposée quand tous les faits de `when` sont vrais et `until` encore faux.
struct ReplyChoice: Identifiable {
    let id: String
    let thread: String
    let when: [String]
    let until: String
    let text: String
    let sets: String
}

/// Un appareil de l'écran d'accueil.
enum AppKind: String, CaseIterable, Identifiable {
    case messages, photos, notes, phone, calendar, maps, mail, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages: return T("Messages", "Messages")
        case .photos: return T("Photos", "Photos")
        case .notes: return T("Notes", "Notes")
        case .phone: return T("Téléphone", "Phone")
        case .calendar: return T("Agenda", "Calendar")
        case .maps: return T("Plans", "Maps")
        case .mail: return T("Mail", "Mail")
        case .settings: return T("Réglages", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .messages: return "message.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .notes: return "note.text"
        case .phone: return "phone.fill"
        case .calendar: return "calendar"
        case .maps: return "map.fill"
        case .mail: return "envelope.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .messages: return [Color(red: 0.36, green: 0.86, blue: 0.42), Color(red: 0.13, green: 0.68, blue: 0.27)]
        case .photos: return [Color(red: 1.0, green: 0.62, blue: 0.3), Color(red: 0.93, green: 0.3, blue: 0.5)]
        case .notes: return [Color(red: 1.0, green: 0.86, blue: 0.35), Color(red: 0.98, green: 0.72, blue: 0.1)]
        case .phone: return [Color(red: 0.36, green: 0.86, blue: 0.42), Color(red: 0.13, green: 0.68, blue: 0.27)]
        case .calendar: return [Color.white, Color(white: 0.9)]
        case .maps: return [Color(red: 0.4, green: 0.75, blue: 1.0), Color(red: 0.2, green: 0.55, blue: 0.95)]
        case .mail: return [Color(red: 0.35, green: 0.7, blue: 1.0), Color(red: 0.1, green: 0.45, blue: 0.95)]
        case .settings: return [Color(white: 0.62), Color(white: 0.42)]
        }
    }

    /// Le chapitre où l'appli s'ouvre.
    var chapter: Int {
        switch self {
        case .messages, .photos, .notes, .phone: return 1
        case .calendar: return 2
        case .maps, .settings: return 3
        case .mail: return 4
        }
    }
}

// MARK: - Une histoire

struct PhoneStory {
    let owner: String
    let passcode: String
    let lockHints: [String]
    let wallpaper: Illustration
    let contacts: [Contact]
    let conversations: [Conversation]
    let photos: [PhotoItem]
    let notes: [Note]
    let voicemails: [Voicemail]
    let live: [LiveMessage]
    let replies: [ReplyChoice]
    /// Les notifications montrées sur l'écran verrouillé au début.
    let lockNotifications: [Message]
    let events: [CalendarEvent]
    let hiddenAlbum: HiddenAlbum?
    let chapters: [Chapter]
    /// Nombre de chapitres gratuits ; la suite s'achète une fois.
    let freeChapters: Int

    func contact(_ id: String) -> Contact {
        contacts.first { $0.id == id } ?? Contact(id: id, name: id, color: .gray)
    }
}
