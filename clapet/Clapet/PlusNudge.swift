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
        c.year = 2026; c.month = 11; c.day = 18
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
                Text("Half price until November 17")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dfAccent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var summary: Text {
        if let peak = stats.peakHour {
            return Text("\(FoldUnit.shown(stats.totalCloses)) folds so far, your peak is at \(HoursText.hour(peak)).")
        }
        return Text("\(FoldUnit.shown(stats.totalCloses)) folds so far.")
    }
}

/// « Pourquoi tu l'ouvres ? » : des barres floutées, la raison n°1 cachée.
struct WhyTeaser: View {
    private let sample: [(WhyReason, Double)] = [(.boredom, 0.46), (.notification, 0.31), (.work, 0.15), (.someone, 0.08)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                Text("Why you open it")
                Spacer()
                PlusBadge()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            ZStack {
                VStack(spacing: 7) {
                    ForEach(sample, id: \.0) { r, v in
                        HStack(spacing: 8) {
                            Image(systemName: r.symbol).font(.footnote).foregroundStyle(.secondary).frame(width: 22)
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

// MARK: - Nouveau : importer ses anciennes stats (demandé par plusieurs utilisateurs)

enum ImportPromoRule {
    private static let key = "importPromoHidden"
    /// -demoImport : la carte s'affiche même avec l'historique de démo (captures).
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demoImport") }

    static var shouldShow: Bool {
        if demo { return true }
        return !Demo.seeded && !UserDefaults.standard.bool(forKey: key)
    }

    static func hide() { UserDefaults.standard.set(true, forKey: key) }
}

struct ImportPromo: View {
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Bring your past folds").font(.headline)
                        Text("New").font(.footnote.weight(.medium)).foregroundStyle(Color.dfAccent)
                    }
                    Text("Import your history from Scriptable, a shortcut or another app, day by day, or add past days by hand.")
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
                Label { Text("Import my history") } icon: { Image(systemName: "tray.and.arrow.down.fill") }
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

// MARK: - Mise à jour disponible
//
// Apple ne permet pas de forcer une mise à jour : Foldly regarde lui-même la version sur l'App Store
// et propose de mettre à jour (bandeau qu'on peut fermer). Si foldly.netlify.app/app.json donne
// { "minVersion": "1.0.7" }, les versions plus anciennes affichent un écran plein (cas d'un bug grave).

@Observable
final class UpdateCheck {
    static let shared = UpdateCheck()
    static let appID = "6827349081"
    static var storeURL: URL { URL(string: "https://apps.apple.com/app/id\(appID)")! }

    var latest: String?
    var minimum: String?
    private var checked = false

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    private static let hiddenKey = "updateHiddenFor"

    /// -demoUpdate : le bandeau s'affiche (captures).
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demoUpdate") }

    var showBanner: Bool {
        if Self.demo { return true }
        guard let latest, Self.isOlder(Self.current, than: latest) else { return false }
        return UserDefaults.standard.string(forKey: Self.hiddenKey) != latest
    }

    var mustUpdate: Bool {
        guard let minimum else { return false }
        return Self.isOlder(Self.current, than: minimum)
    }

    func hide() {
        if let latest { UserDefaults.standard.set(latest, forKey: Self.hiddenKey) }
    }

    static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }

    @MainActor
    func run() async {
        guard !checked, !Demo.seeded else { return }
        checked = true
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        if let url = URL(string: "https://itunes.apple.com/lookup?id=\(Self.appID)&country=\(country)&t=\(Int(Date().timeIntervalSince1970 / 3600))"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let first = (json["results"] as? [[String: Any]])?.first,
           let v = first["version"] as? String {
            latest = v
        }
        if let url = URL(string: "https://foldly.netlify.app/app.json"),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = json["minVersion"] as? String {
            minimum = m
        }
    }
}

struct UpdateBanner: View {
    @Environment(\.openURL) private var openURL
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.title2)
                .foregroundStyle(Color.dfAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("A new version is available").font(.subheadline.weight(.bold))
                Text("Update Foldly to get the latest features and fixes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button { openURL(UpdateCheck.storeURL) } label: {
                Text("Update").font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
            Button(action: onHide) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Not now"))
        }
    }
}

/// Écran plein, seulement si une version minimale est fixée (bug grave).
struct MustUpdateView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.down.app.fill").font(.system(size: 60)).foregroundStyle(Color.dfAccent)
            Text("Please update Foldly").font(.title.weight(.bold)).multilineTextAlignment(.center)
            Text("This version has a problem that is fixed in the latest one. Your folds are safe and stay on your iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { openURL(UpdateCheck.storeURL) } label: {
                Text("Update").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dfAccent)
            .foregroundStyle(Color.dfOnAccent)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dfBackground.ignoresSafeArea())
    }
}
