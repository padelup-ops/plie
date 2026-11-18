import Foundation

/// The six themes. Raw values are the WidgetKit kinds: don't rename them.
enum FoldTheme: String, Codable, CaseIterable, Identifiable, Equatable {
    case revelation
    case hour
    case quote
    case diptych
    case countdown
    case mood

    var id: String { rawValue }

    var nameKey: String {
        switch self {
        case .revelation: return "Revelation"
        case .hour: return "Hour"
        case .quote: return "Quote"
        case .diptych: return "Diptych"
        case .countdown: return "Countdown"
        case .mood: return "Mood"
        }
    }

    var detailKey: String {
        switch self {
        case .revelation: return "A word that finishes when the phone opens."
        case .hour: return "The time, split the way the Duo folds."
        case .quote: return "A short sentence, on the cover or across the inside."
        case .diptych: return "Two panes that belong together."
        case .countdown: return "Days left, in large type."
        case .mood: return "Today's color, chosen by you."
        }
    }
}

enum Mood: String, Codable, CaseIterable, Identifiable, Hashable {
    case calm, joy, focus, tender, storm, wonder
    var id: String { rawValue }
    var nameKey: String {
        switch self {
        case .calm: return "Calm"
        case .joy: return "Joy"
        case .focus: return "Focus"
        case .tender: return "Tender"
        case .storm: return "Storm"
        case .wonder: return "Wonder"
        }
    }
}

enum DiptychPalette: Int, CaseIterable, Identifiable, Equatable {
    case inkGold = 0
    case nightDawn
    case seaSand
    case berryCream
    var id: Int { rawValue }
    var nameKey: String {
        switch self {
        case .inkGold: return "Ink and gold"
        case .nightDawn: return "Night and dawn"
        case .seaSand: return "Sea and sand"
        case .berryCream: return "Berry and cream"
        }
    }
}

struct Quote {
    var textFR: String
    var textEN: String
    var authorFR: String
    var authorEN: String

    static let catalog: [Quote] = [
        Quote(textFR: "Ce qui se plie peut se rouvrir.", textEN: "What folds can open again.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "Deux écrans, une idée calme.", textEN: "Two screens, one quiet idea.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "Garde l'intérieur pour quand tu ouvres.", textEN: "Leave the inside for when you open.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "La charnière est une pause, pas un mur.", textEN: "The hinge is a pause, not a wall.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "Un jour est plus court quand on le compte.", textEN: "A day is shorter when you count it.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "Mets la chose bruyante sur la couverture.", textEN: "Put the loud thing on the cover.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "La seconde moitié attendait.", textEN: "The second half was waiting.", authorFR: "Fold Widgets", authorEN: "Fold Widgets"),
        Quote(textFR: "Ouvre doucement. Le reste peut attendre.", textEN: "Open slowly. The rest can wait.", authorFR: "Fold Widgets", authorEN: "Fold Widgets")
    ]

    func text(french: Bool) -> String { french ? textFR : textEN }
    func author(french: Bool) -> String { french ? authorFR : authorEN }

    /// Splits the sentence in two so each half can sit on one side of the fold.
    func halves(french: Bool) -> (String, String) {
        let words = text(french: french).split(separator: " ").map(String.init)
        guard words.count > 1 else { return (text(french: french), "") }
        let mid = words.count / 2
        return (words[..<mid].joined(separator: " "), words[mid...].joined(separator: " "))
    }
}

struct CountdownReading: Equatable {
    var number: String
    var unitKey: String
    var progress: Double
    var finished: Bool
}

struct FoldSettings: Codable, Equatable {
    var theme: FoldTheme = .revelation
    var revelationWord: String = ""
    var quoteIndex: Int = 0
    var customQuote: String = ""
    var customAuthor: String = ""
    var countdownDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
    var countdownTitle: String = ""
    var mood: Mood = .calm
    var diptychPalette: Int = 0

    var prefersFrench: Bool {
        Locale.current.language.languageCode == .french
    }

    var revelationDisplay: String {
        let trimmed = revelationWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return prefersFrench ? "OUVERT" : "OPEN"
    }

    var countdownTitleDisplay: String {
        let trimmed = countdownTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NSLocalizedString("The day", comment: "")
    }

    var resolvedQuote: Quote {
        let custom = customQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            let author = customAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
            let signed = author.isEmpty ? "Fold Widgets" : author
            return Quote(textFR: custom, textEN: custom, authorFR: signed, authorEN: signed)
        }
        let list = Quote.catalog
        let i = ((quoteIndex % list.count) + list.count) % list.count
        return list[i]
    }

    var palette: DiptychPalette {
        DiptychPalette(rawValue: ((diptychPalette % 4) + 4) % 4) ?? .inkGold
    }

    func countdown(at now: Date) -> CountdownReading {
        let span = countdownDate.timeIntervalSince(now)
        if span <= 0 {
            return CountdownReading(number: "0", unitKey: "Today", progress: 1, finished: true)
        }
        let days = Int(span / 86400)
        if days >= 1 {
            return CountdownReading(number: String(days), unitKey: "Days", progress: min(1, Double(days) / 30), finished: false)
        }
        let hours = Int(span / 3600)
        if hours >= 1 {
            return CountdownReading(number: String(hours), unitKey: "Hours", progress: min(1, span / 86400), finished: false)
        }
        let minutes = max(1, Int(span / 60))
        return CountdownReading(number: String(minutes), unitKey: "Minutes", progress: min(1, span / 3600), finished: false)
    }

    func clockParts(at date: Date) -> (hour: String, minute: String) {
        let calendar = Calendar.current
        let hourValue = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        let uses24h = !template.contains("a")
        let hour: Int
        if uses24h {
            hour = hourValue
        } else {
            hour = hourValue % 12 == 0 ? 12 : hourValue % 12
        }
        return (String(format: "%02d", hour), String(format: "%02d", minute))
    }

    func dateLine(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }

    /// One short line for the Lock Screen. WidgetKit never tells us the fold.
    func inline(at date: Date) -> String {
        switch theme {
        case .revelation:
            return revelationDisplay
        case .hour:
            let parts = clockParts(at: date)
            return "\(parts.hour):\(parts.minute)"
        case .quote:
            return resolvedQuote.text(french: prefersFrench)
        case .diptych:
            return NSLocalizedString(palette.nameKey, comment: "")
        case .countdown:
            let reading = countdown(at: date)
            return "\(reading.number) \(NSLocalizedString(reading.unitKey, comment: ""))"
        case .mood:
            return NSLocalizedString(mood.nameKey, comment: "")
        }
    }

    func badge(at date: Date) -> String {
        switch theme {
        case .revelation:
            return String(revelationDisplay.prefix(1))
        case .hour:
            return clockParts(at: date).hour
        case .quote:
            return "“"
        case .diptych:
            return "II"
        case .countdown:
            return countdown(at: date).number
        case .mood:
            return String(NSLocalizedString(mood.nameKey, comment: "").prefix(1))
        }
    }
}
