import SwiftUI
import UserNotifications

// MARK: - Black Friday
//
// Foldly+ à moitié prix avec le code BLACKFRIDAY (code d'offre App Store, 1,99 € au lieu de 3,99 € en France),
// jusqu'au lundi 30 novembre inclus. Réservé à ceux qui n'ont pas encore acheté Foldly+.
// - Une carte sur l'accueil, pour tous ceux qui n'ont pas Foldly+. On peut la fermer :
//   elle revient une seule fois le dernier jour, puis plus jamais.
// - Un seul rappel, le dernier jour à 18 h, seulement si les notifications sont déjà autorisées.
// - Le bouton ouvre l'App Store avec le code déjà rempli ; l'achat arrive dans l'app par Transaction.updates.

enum GiftOffer {
    static let code = "BLACKFRIDAY"
    static var redeemURL: URL {
        URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=\(UpdateCheck.appID)&code=\(code)")!
    }

    private static var paris: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }

    private static func day(_ m: Int, _ d: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = m; c.day = d; c.hour = hour
        return paris.date(from: c) ?? .distantPast
    }

    /// Fin de l'offre : le 1er décembre à 0 h (heure de Paris).
    static var end: Date { day(12, 1) }
    /// Le dernier jour : le lundi 30 novembre.
    static var lastDay: Date { day(11, 30) }

    private static let stageKey = "blackFriday2026HiddenStage"
    private static let reminderID = "foldly.blackfriday2026"

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

    /// Le rappel du dernier jour (30 novembre, 18 h), une seule fois, sans demander l'autorisation.
    static func scheduleReminder(_ stats: ClapetStats, hasPlus: Bool) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["foldly.gift", "foldly.gift2000"])
        guard !hasPlus, !Demo.seeded else { return }
        let fire = day(11, 30, hour: 18)
        guard Date() < fire else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Last day of Black Friday")
                content.body = String(localized: "Foldly+ is half price until tonight with the code BLACKFRIDAY. Paid once, yours for good.")
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

/// La carte de l'accueil : Black Friday, Foldly+ à moitié prix avec le code.
struct GiftCard: View {
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Black Friday")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Foldly+ is half price until Monday, November 30 with the code BLACKFRIDAY. Paid once, yours for good.")
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
            GiftCodeButton()
        }
    }
}

/// « Utiliser le code BLACKFRIDAY » : ouvre l'App Store avec le code rempli.
struct GiftCodeButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(GiftOffer.redeemURL) } label: {
            Label { Text("Use the code BLACKFRIDAY") } icon: { Image(systemName: "tag") }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.dfAccent)
        .foregroundStyle(Color.dfOnAccent)
    }
}
