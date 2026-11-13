import SwiftUI
import UserNotifications

// MARK: - Merci pour les 2 000 téléchargements
//
// Foldly+ à moitié prix pour tout le monde (prix public de l'App Store baissé), jusqu'au 17 novembre inclus.
// - Une carte sur l'accueil, pour tous ceux qui n'ont pas Foldly+, nouveaux comme anciens. On peut la fermer :
//   elle revient une seule fois le dernier jour, puis plus jamais.
// - Un seul rappel, le dernier jour à 18 h, seulement si les notifications sont déjà autorisées.
// - Le bouton ouvre Foldly+ : le prix affiché est déjà le prix réduit.

enum GiftOffer {
    static let code = "FOLDLY1000"
    static var redeemURL: URL {
        URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=\(UpdateCheck.appID)&code=\(code)")!
    }

    private static var paris: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }

    private static func day(_ d: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = d; c.hour = hour
        return paris.date(from: c) ?? .distantPast
    }

    /// Fin de l'offre : le 18 novembre à 0 h (heure de Paris).
    static var end: Date { day(18) }
    /// Le dernier jour : le 17 novembre.
    static var lastDay: Date { day(17) }

    private static let stageKey = "gift2000HiddenStage"
    private static let reminderID = "foldly.gift2000"

    /// -demoGift : la carte s'affiche même avec l'historique de démo (captures).
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demoGift") }

    static var isOn: Bool { Date() < end }

    static func shouldShow(_ stats: ClapetStats, hasPlus: Bool, now: Date = Date()) -> Bool {
        if demo { return !hasPlus }
        guard !hasPlus, !Demo.seeded, now < end else { return false }
        switch UserDefaults.standard.integer(forKey: stageKey) {
        case 0: return true
        case 1: return now >= lastDay
        default: return false
        }
    }

    /// Fermer : la carte revient le dernier jour (une fois), puis disparaît.
    static func hide(now: Date = Date()) {
        let d = UserDefaults.standard
        d.set(now >= lastDay ? 2 : max(1, d.integer(forKey: stageKey) + 1), forKey: stageKey)
    }

    /// Le rappel du dernier jour (17 novembre, 18 h), une seule fois, sans demander l'autorisation.
    static func scheduleReminder(_ stats: ClapetStats, hasPlus: Bool) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["foldly.gift"])
        guard !hasPlus, !Demo.seeded else { return }
        let fire = day(17, hour: 18)
        guard Date() < fire else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Last day: Foldly+ at half price")
                content.body = String(localized: "Thanks for 2,000 downloads: Foldly+ is half price until tonight. Paid once, yours for good.")
                content.userInfo = ["url": "clapet://offer"]
                let comps = paris.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: reminderID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                try? await center.add(request)
            default:
                break
            }
        }
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
    }
}

/// La carte de l'accueil : merci pour les 1 000 téléchargements, Foldly+ à moitié prix.
struct GiftCard: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("2,000 downloads, thank you!")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("To celebrate, Foldly+ is half price for everyone until November 17. Paid once, yours for good.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.dfFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Not now"))
            }
            Button(action: onOpen) {
                Label { Text("Get Foldly+ at half price") } icon: { Image(systemName: "gift") }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
        }
    }
}
