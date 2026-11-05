import SwiftUI

// MARK: - Montrer Foldly+ au bon moment (sans insister)
//
// 1. Après 3 jours suivis : une carte sur l'accueil avec ses vrais chiffres et un aperçu flouté de « Pourquoi tu l'ouvres ».
// 2. Limite du jour dépassée : une seule fois par jour, on propose les alertes (80 % et 100 %).
// 3. Jusqu'au 13 novembre : le prix de lancement est rappelé sur l'écran Foldly+.

enum PlusNudgeRule {
    private static let hiddenKey = "plusNudgeHiddenUntil"
    private static let limitKey = "plusLimitNudgeDay"

    /// -demoNudge : la carte s'affiche même avec l'historique de démo (captures).
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demoNudge") }

    static func shouldShowCard(_ stats: ClapetStats, hasPlus: Bool) -> Bool {
        if demo { return !hasPlus }
        guard !hasPlus, !Demo.seeded, stats.daysCounted >= 3 else { return false }
        return Date().timeIntervalSince1970 >= UserDefaults.standard.double(forKey: hiddenKey)
    }

    /// « Plus tard » : la carte revient dans 10 jours.
    static func hide() {
        UserDefaults.standard.set(Date().addingTimeInterval(10 * 86_400).timeIntervalSince1970, forKey: hiddenKey)
    }

    /// Limite dépassée aujourd'hui, sans Foldly+ : on le propose une fois (et on le note).
    static func claimLimit(_ stats: ClapetStats, hasPlus: Bool) -> Bool {
        guard !hasPlus, !Demo.seeded, stats.activeLimit > 0, stats.today > stats.activeLimit else { return false }
        let d = UserDefaults.standard
        let today = ClapetStats.key()
        guard d.string(forKey: limitKey) != today else { return false }
        d.set(today, forKey: limitKey)
        return true
    }
}

/// Le prix de lancement : jusqu'au 13 novembre 2026 à 0 h (heure de Paris), quand le prix normal démarre sur l'App Store.
enum LaunchPrice {
    static let end: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 13
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal.date(from: c) ?? .distantPast
    }()

    static var isOn: Bool { Date() < end }
}

/// La carte de l'accueil, après 3 jours : tes chiffres, ton heure de pointe, et la vraie raison… floutée.
struct PlusNudgeCard: View {
    let stats: ClapetStats
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your first days")
                        .font(.headline)
                    summary
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
            WhyTeaser()
            Button(action: onOpen) {
                Label { Text("Unlock your trends") } icon: { Image(systemName: "lock.open.fill") }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
            if LaunchPrice.isOn {
                Text("Launch price until November 13")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dfAccent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var summary: Text {
        if let peak = stats.peakHour {
            return Text("\(stats.totalCloses) folds so far, your peak is at \(HoursText.hour(peak)).")
        }
        return Text("\(stats.totalCloses) folds so far.")
    }
}

/// « Pourquoi tu l'ouvres ? » : des barres floutées, la raison n°1 cachée.
struct WhyTeaser: View {
    private let sample: [(WhyReason, Double)] = [(.boredom, 0.46), (.notification, 0.31), (.work, 0.15), (.someone, 0.08)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                Text("WHY YOU OPEN IT").tracking(0.8)
                Spacer()
                PlusBadge()
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            ZStack {
                VStack(spacing: 7) {
                    ForEach(sample, id: \.0) { r, v in
                        HStack(spacing: 8) {
                            Text(r.emoji).frame(width: 22)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule().fill(WhyRule.color(r)).frame(width: g.size.width * v)
                                }
                            }
                            .frame(height: 9)
                        }
                    }
                }
                .blur(radius: 5)
                .accessibilityHidden(true)
                Text("Your number one reason: ???")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
