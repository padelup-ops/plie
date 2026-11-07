import SwiftUI
import UIKit
import UserNotifications

// MARK: - « Pourquoi tu l'ouvres ? » (Foldly+)
//
// Quand on déplie le Duo, Foldly demande en un toucher pourquoi : une notif, l'ennui, le boulot, quelqu'un.
// Le soir et la semaine, on voit la vraie raison de ses ouvertures. Tout reste sur l'iPhone.

enum WhyRule {
    static let key = "whyOn"
    static let closedKey = "whyClosedOn"
    private static let lastAskKey = "whyLastAsk"
    /// Pas plus d'une question toutes les 2 minutes.
    static let gap: TimeInterval = 120
    static let category = "FOLDLY_WHY"

    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var closedOn: Bool { UserDefaults.standard.bool(forKey: closedKey) }

    /// On peut poser la question maintenant ? (et on note l'heure)
    static func claim(plus: Bool, now: Date = Date()) -> Bool {
        guard plus, isOn, !Demo.seeded else { return false }
        let last = UserDefaults.standard.object(forKey: lastAskKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= gap else { return false }
        UserDefaults.standard.set(now, forKey: lastAskKey)
        return true
    }

    static func label(_ r: WhyReason) -> LocalizedStringKey {
        switch r {
        case .notification: return "A notification"
        case .boredom: return "Boredom"
        case .work: return "Work"
        case .someone: return "Someone"
        }
    }

    static func labelString(_ r: WhyReason) -> String {
        switch r {
        case .notification: return String(localized: "A notification")
        case .boredom: return String(localized: "Boredom")
        case .work: return String(localized: "Work")
        case .someone: return String(localized: "Someone")
        }
    }

    static func color(_ r: WhyReason) -> Color {
        switch r {
        case .notification: return Color(red: 1.0, green: 0.62, blue: 0.25)
        case .boredom: return Color(red: 0.62, green: 0.56, blue: 1.0)
        case .work: return Color(red: 0.35, green: 0.72, blue: 1.0)
        case .someone: return Color(red: 1.0, green: 0.42, blue: 0.55)
        }
    }

    // MARK: Foldly fermé : une notification avec les 4 réponses

    static func registerCategory() {
        let actions = WhyReason.allCases.map {
            UNNotificationAction(identifier: "why.\($0.rawValue)", title: "\($0.emoji) \(labelString($0))", options: [])
        }
        let cat = UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var all = existing.filter { $0.identifier != category }
            all.insert(cat)
            UNUserNotificationCenter.current().setNotificationCategories(all)
        }
    }

    /// Le Duo vient d'être ouvert alors que Foldly n'est pas à l'écran.
    static func askByNotification(plus: Bool) {
        guard closedOn else { return }
        Task { @MainActor in
            guard UIApplication.shared.applicationState != .active, claim(plus: plus) else { return }
            let c = UNMutableNotificationContent()
            c.title = String(localized: "Why did you open it?")
            c.body = String(localized: "Touch and hold to answer in one tap.")
            c.categoryIdentifier = category
            c.interruptionLevel = .passive
            let r = UNNotificationRequest(identifier: "foldly.why", content: c, trigger: nil)
            try? await UNUserNotificationCenter.current().add(r)
            // La question ne sert plus après une minute.
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["foldly.why"])
        }
    }

    /// Une réponse donnée depuis la notification.
    @MainActor static func handle(action: String) {
        guard action.hasPrefix("why."), let n = Int(action.dropFirst(4)), let r = WhyReason(rawValue: n) else { return }
        if let model = ClapetModel.current {
            model.recordWhy(r)
        } else {
            var stats = ClapetVault.load()
            stats.addWhy(r)
            ClapetVault.save(stats)
        }
    }
}

/// La question, en bas de l'écran, juste après avoir déplié le Duo.
struct WhyPrompt: View {
    @Environment(ClapetModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Why did you open it?")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Button { withAnimation { model.askWhy = false } } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Not now"))
            }
            HStack(spacing: 10) {
                ForEach(WhyReason.allCases, id: \.self) { r in
                    Button {
                        withAnimation(.spring(duration: 0.35)) { model.recordWhy(r) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: r.symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(WhyRule.color(r)).frame(height: 32)
                            Text(WhyRule.label(r))
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WhyRule.color(r).opacity(0.18)))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: 560)
        .task {
            // Sans réponse, la question s'en va toute seule.
            guard !Demo.askWhy else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation { model.askWhy = false }
        }
    }
}

/// La carte de l'historique : la vraie raison de tes ouvertures, cette semaine.
struct WhyCard: View {
    let stats: ClapetStats
    var locked = false
    var onUnlock: () -> Void = {}

    var body: some View {
        let counts = stats.whyCounts()
        let total = counts.reduce(0, +)
        let top = WhyReason.allCases.max { counts[$0.rawValue] < counts[$1.rawValue] } ?? .boredom
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                Text("Why you open it")
                Spacer()
                if locked { PlusBadge() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            if locked {
                Text("Each time you unfold your Duo, answer in one tap: a notification, boredom, work or someone. See the real reasons behind your opens.")
                    .font(.subheadline)
                Button(action: onUnlock) {
                    Text("Unlock Foldly+").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.dfAccent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if total == 0 {
                Text("When you unfold your Duo, answer the question in one tap. Your reasons for the week show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let pct = Int((Double(counts[top.rawValue]) / Double(total) * 100).rounded())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your number one reason this week").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(WhyRule.label(top))
                        Spacer()
                        Text(verbatim: "\(pct) %").foregroundStyle(WhyRule.color(top))
                    }
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    if let peak = stats.whyPeak(top) {
                        Text("Mostly between \(HoursText.hour(peak)) and \(HoursText.hour((peak + 2) % 24))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(WhyReason.allCases, id: \.self) { r in
                        let n = counts[r.rawValue]
                        HStack(spacing: 10) {
                            Image(systemName: r.symbol).font(.subheadline).foregroundStyle(.secondary).frame(width: 26)
                            Text(WhyRule.label(r)).font(.subheadline.weight(.medium)).frame(width: 120, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(WhyRule.color(r)).frame(width: max(6, g.size.width * Double(n) / Double(max(1, total))))
                                }
                            }
                            .frame(height: 10)
                            Text(verbatim: "\(Int((Double(n) / Double(total) * 100).rounded())) %")
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Text("\(total) answers in the last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.dfCard))
    }
}
