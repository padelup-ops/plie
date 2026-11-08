import SwiftUI
import UserNotifications

// MARK: - Le cadeau des 1 000 téléchargements
//
// Foldly+ à moitié prix avec le code FOLDLY1000 (code d'offre App Store), jusqu'au 16 novembre inclus.
// - Une carte sur l'accueil, seulement sans Foldly+ et après 2 jours suivis. On peut la fermer :
//   elle revient une seule fois le dernier jour, puis plus jamais.
// - Un seul rappel, la veille de la fin, seulement si les notifications sont déjà autorisées.
// - Le bouton ouvre la page de l'App Store avec le code déjà rempli. Le prix public ne change pas.

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

    /// Fin de l'offre : le 17 novembre à 0 h (heure de Paris).
    static var end: Date { day(17) }
    /// Le dernier jour : le 16 novembre.
    static var lastDay: Date { day(16) }

    private static let stageKey = "giftHiddenStage"
    private static let reminderID = "foldly.gift"

    /// -demoGift : la carte s'affiche même avec l'historique de démo (captures).
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demoGift") }

    static var isOn: Bool { Date() < end }

    static func shouldShow(_ stats: ClapetStats, hasPlus: Bool, now: Date = Date()) -> Bool {
        if demo { return !hasPlus }
        guard !hasPlus, !Demo.seeded, now < end, stats.daysCounted >= 2 else { return false }
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

    /// Le rappel de la veille (15 novembre, 18 h), une seule fois, sans demander l'autorisation.
    static func scheduleReminder(_ stats: ClapetStats, hasPlus: Bool) {
        guard !hasPlus, !Demo.seeded, stats.daysCounted >= 1 else { return }
        let fire = day(15, hour: 18)
        guard Date() < fire else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Foldly+ at its lowest price ends tomorrow")
                content.body = String(localized: "To celebrate 1,000 downloads, the code FOLDLY1000 gives you Foldly+ at half the regular price until November 16. Paid once, yours for good.")
                content.userInfo = ["url": redeemURL.absoluteString]
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
                    Text("1,000 downloads in 3 days, thank you!")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("To celebrate, this code gives you Foldly+ at its lowest price ever, half the regular price, until November 16. Paid once, yours for good.")
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
            HStack(spacing: 8) {
                Image(systemName: "ticket.fill").foregroundStyle(Color.dfAccent)
                Text(verbatim: GiftOffer.code)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                Spacer()
                Text("Filled in for you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            Button(action: onOpen) {
                Label { Text("Get Foldly+ for less") } icon: { Image(systemName: "gift") }
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
