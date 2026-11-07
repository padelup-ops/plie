import SwiftUI
import WidgetKit

// MARK: - Mode démo (tournage de la vidéo de présentation sur le simulateur)
//
// Arguments de lancement :
//   -demoSeed 1             un historique réaliste (45 jours) au lieu des vrais chiffres
//   -demoToday 44           les plis d'aujourd'hui au départ
//   -demoLimit 60           le niveau moyen de plis par jour (et la limite, si -demoGoalOn 1)
//   -demoGoalOn 1           limite du jour activée
//   -demoPlus 1             Foldly+ débloqué
//   -demoHinge "t:a,t:a"    charnière simulée : à t secondes, angle a en degrés (interpolé entre deux)
//   -demoDelay 2            secondes avant le temps zéro de la démo (écrit dans Documents/demo-origin.txt)
//   -screen home|history|widgets|plus|week
//   -demoScroll "records@2.5"  fait défiler l'écran jusqu'à une section à cet instant

enum Demo {
    private static let args = ProcessInfo.processInfo.arguments

    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: "-" + key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var seeded: Bool { value("demoSeed") == "1" }
    /// -demoWhy : la question « Pourquoi tu l'ouvres ? » reste à l'écran (captures).
    static var askWhy: Bool { args.contains("-demoWhy") }
    static var plus: Bool { value("demoPlus") == "1" }
    static var screen: String? { value("screen") }
    /// -demoDesk 1 : mode bureau forcé (vidéo)
    static var desk: Bool { value("demoDesk") == "1" }
    static var delay: Double { value("demoDelay").flatMap(Double.init) ?? 2 }

    static var hinge: [(t: Double, a: Double)] {
        (value("demoHinge") ?? "").split(separator: ",").compactMap { pair -> (t: Double, a: Double)? in
            let p = pair.split(separator: ":").compactMap { Double($0) }
            return p.count == 2 ? (t: p[0], a: p[1]) : nil
        }
    }

    static var scroll: (id: String, at: Double)? {
        guard let v = value("demoScroll") else { return nil }
        let p = v.split(separator: "@")
        guard p.count == 2, let t = Double(p[1]) else { return nil }
        return (String(p[0]), t)
    }

    /// Angle de la charnière à l'instant t (interpolation douce entre les points).
    static func angle(at t: Double, in keys: [(t: Double, a: Double)]) -> Double {
        guard let first = keys.first, let last = keys.last else { return 180 }
        if t <= first.t { return first.a }
        if t >= last.t { return last.a }
        for (k0, k1) in zip(keys, keys.dropFirst()) where t <= k1.t {
            let x = (t - k0.t) / max(0.001, k1.t - k0.t)
            let e = x * x * (3 - 2 * x)
            return k0.a + (k1.a - k0.a) * e
        }
        return last.a
    }

    /// Note l'instant zéro de la démo (pour caler la vidéo).
    static func markOrigin() -> Date {
        let now = Date()
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? String(format: "%.3f", now.timeIntervalSince1970)
                .write(to: dir.appendingPathComponent("demo-origin.txt"), atomically: true, encoding: .utf8)
        }
        return now
    }

    /// Un historique crédible : 45 jours autour d'un même niveau, qui baisse doucement.
    static func seed(_ stats: inout ClapetStats) {
        let limit = value("demoLimit").flatMap(Int.init) ?? 60
        let today = value("demoToday").flatMap(Int.init) ?? 44
        var s = ClapetStats()
        s.goal = limit
        s.goalOn = value("demoGoalOn") == "1"
        let cal = Calendar.current
        let now = Date()
        var total = 1180
        let pattern = [1.1, 0.9, 1.0, 0.8, 1.15, 0.85, 0.75, 1.0, 0.88, 1.05, 0.8, 0.92, 1.12, 0.7]
        for back in (1...45).reversed() {
            guard let d = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            // Un peu plus au début, un peu moins ensuite : l'habitude change.
            let trend = 0.78 + Double(back) / 70.0
            let n = Int((Double(limit) * trend * pattern[back % pattern.count]).rounded())
            var day = DayCount(closes: n, opens: n + (back % 3))
            // Temps fermé et ouvert : une journée type.
            let hours = back <= 9 ? 3.4 + 0.25 * Double(back % 4) : 2.2 + 0.5 * pattern[back % pattern.count]
            day.downSeconds = hours * 3600
            day.openSeconds = (2.1 + 0.3 * pattern[back % pattern.count]) * 3600
            day.peeks = 4 + back % 5
            day.longestBreak = 3600 * (1.2 + 0.1 * Double(back % 5))
            s.days[ClapetStats.key(d)] = day
            total += n
        }
        var day = DayCount(closes: today, opens: today)
        day.downSeconds = 2.6 * 3600
        day.openSeconds = 1.7 * 3600
        day.peeks = 6
        s.days[ClapetStats.key(now)] = day
        // Fermé depuis 17 minutes.
        s.autoLast = now.addingTimeInterval(-17 * 60)
        s.totalCloses = total + today
        s.totalOpens = s.totalCloses
        s.firstDay = cal.date(byAdding: .day, value: -45, to: now).map { ClapetStats.key($0) }
        s.hourlyDay = ClapetStats.key(now)
        var hours = Array(repeating: 0, count: 24)
        let shape = [0, 0, 0, 0, 0, 0, 1, 4, 8, 9, 6, 4, 6, 5, 3, 4, 5, 6, 7, 5, 4, 3, 1, 0]
        let sum = shape.reduce(0, +)
        // Une journée type (pour la vidéo, quelle que soit l'heure du tournage)
        var left = today
        for h in 0..<24 {
            let n = min(left, Int((Double(today) * Double(shape[h]) / Double(sum)).rounded()))
            hours[h] = n
            left -= n
        }
        hours[9] += left
        s.hourly = hours
        // La semaine type : plus de plis en journée, un peu plus en semaine que le week-end.
        for wd in 0..<7 {
            let weekend = wd == 0 || wd == 6
            for h in 0..<24 {
                let base = Double(shape[(h + (weekend ? 22 : 0)) % 24]) * (weekend ? 3.2 : 4.6)
                s.weekHours[wd * 24 + h] = Int((base * (0.8 + 0.4 * Double((wd * 7 + h * 3) % 5) / 4)).rounded())
            }
        }
        s.recordHour = 14
        s.lastClose = Demo.screen == "home" || Demo.screen == nil ? now.addingTimeInterval(-180) : now.addingTimeInterval(-17 * 60)
        s.plus = plus
        s.theme = 0
        // « Pourquoi tu l'ouvres ? » : une semaine de réponses (l'ennui le soir).
        var rng = SystemRandomNumberGenerator()
        for back in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { continue }
            for _ in 0..<9 {
                let roll = Int.random(in: 0..<100, using: &rng)
                let r: WhyReason = roll < 46 ? .boredom : roll < 72 ? .notification : roll < 88 ? .work : .someone
                let hour = r == .boredom ? Int.random(in: 20...22, using: &rng) : Int.random(in: 8...19, using: &rng)
                if let t = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng), second: 0, of: day), t < now { s.addWhy(r, t) }
            }
            // Les sessions : beaucoup de courtes, quelques longues le soir.
            for _ in 0..<14 {
                let roll = Int.random(in: 0..<100, using: &rng)
                let secs = roll < 45 ? Double.random(in: 8...55, using: &rng) : roll < 85 ? Double.random(in: 70...560, using: &rng) : Double.random(in: 900...3400, using: &rng)
                let hour = Int.random(in: 7...22, using: &rng)
                if let t = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng), second: 0, of: day), t < now { s.addSession(start: t, seconds: secs) }
            }
        }
        s.sessionLog.sort { $0.t < $1.t }
        stats = s
    }
}

/// L'écran d'accueil d'un iPhone avec les widgets de Foldly (pour la vidéo), ou son écran verrouillé (`-screen lock`).
struct DemoWidgetsView: View {
    @Environment(ClapetModel.self) private var model

    var body: some View {
        let entry = ClapetEntry(date: Date(), stats: model.stats)
        GeometryReader { g in
            let scale = min(g.size.width / 400, (g.size.height - 120) / 620)
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.42, green: 0.22, blue: 0.48),
                                        Color(red: 0.93, green: 0.52, blue: 0.46)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if Demo.screen == "allwidgets" {
                    AllHomeWidgets(entry: entry, scale: min(g.size.width / 760, g.size.height / 960))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if Demo.screen == "alllock" {
                    AllLockWidgets(entry: entry, scale: min(g.size.width / 520, g.size.height / 700))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.colorScheme, .dark)
                } else if Demo.screen == "lock" {
                    VStack(spacing: 14 * scale) {
                        WidgetThumb(kind: .phoneDown, family: .accessoryInline, entry: entry, scale: 1.3 * scale)
                        Text(Date(), format: .dateTime.hour().minute())
                            .font(.system(size: 120 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                        HStack(spacing: 14 * scale) {
                            WidgetThumb(kind: .folds, family: .accessoryCircular, entry: entry, scale: 1.35 * scale)
                            WidgetThumb(kind: .phoneDown, family: .accessoryRectangular, entry: entry, scale: 1.35 * scale)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 90 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.colorScheme, .dark)
                } else {
                    VStack(spacing: 22 * scale) {
                        WidgetThumb(kind: .folds, family: .systemMedium, entry: entry, scale: scale)
                        HStack(spacing: 22 * scale) {
                            WidgetThumb(kind: .phoneDown, family: .systemSmall, entry: entry, scale: scale)
                            WidgetThumb(kind: .folds, family: .systemSmall, entry: entry, scale: scale)
                        }
                        WidgetThumb(kind: .phoneDown, family: .systemMedium, entry: entry, scale: scale)
                        HStack(spacing: 22 * scale) {
                            icon("heart.fill", .pink, scale)
                            icon("message.fill", .green, scale)
                            icon("camera.fill", .gray, scale)
                            icon("music.note", .red, scale)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func icon(_ symbol: String, _ color: Color, _ scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 15 * scale, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .frame(width: 66 * scale, height: 66 * scale)
            .overlay(Image(systemName: symbol).font(.system(size: 28 * scale, weight: .semibold)).foregroundStyle(color))
    }
}

/// Tous les widgets de l'écran d'accueil, pour une image de présentation (-screen allwidgets).
struct AllHomeWidgets: View {
    let entry: ClapetEntry
    let scale: CGFloat
    private let gap: CGFloat = 22

    private func w(_ k: WidgetThumb.Kind, _ f: WidgetFamily) -> some View {
        let size = WidgetThumb.size(f)
        return WidgetThumb(kind: k, family: f, entry: entry, scale: scale)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
    }

    var body: some View {
        VStack(spacing: gap * scale) {
            HStack(alignment: .top, spacing: gap * scale) {
                w(.folds, .systemLarge)
                VStack(spacing: gap * scale) {
                    HStack(spacing: gap * scale) { w(.folds, .systemSmall); w(.phoneDown, .systemSmall) }
                    HStack(spacing: gap * scale) { w(.lifetime, .systemSmall); CountFoldButton(scale: scale) }
                }
            }
            HStack(spacing: gap * scale) { w(.folds, .systemMedium); w(.phoneDown, .systemMedium) }
            HStack(alignment: .top, spacing: gap * scale) {
                w(.hours, .systemLarge)
                w(.hours, .systemMedium)
            }
        }
    }
}

/// Le bouton « Compter un pli » (Centre de contrôle), dessiné comme dans iOS.
struct CountFoldButton: View {
    let scale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .frame(width: 158 * scale, height: 158 * scale)
            .overlay {
                VStack(spacing: 10 * scale) {
                    Circle().fill(Palette.mint)
                        .frame(width: 64 * scale, height: 64 * scale)
                        .overlay(Image(systemName: "plus").font(.system(size: 30 * scale, weight: .bold)).foregroundStyle(.black))
                    Text("Count a fold").font(.system(size: 14 * scale, weight: .semibold)).foregroundStyle(.white)
                }
            }
    }
}

/// Tous les widgets de l'écran verrouillé (-screen alllock).
struct AllLockWidgets: View {
    let entry: ClapetEntry
    let scale: CGFloat

    private func w(_ k: WidgetThumb.Kind, _ f: WidgetFamily, _ extra: CGFloat = 1.3) -> some View {
        let size = WidgetThumb.size(f)
        return WidgetThumb(kind: k, family: f, entry: entry, scale: scale * extra)
            .frame(width: size.width * scale * extra, height: size.height * scale * extra, alignment: .topLeading)
    }

    var body: some View {
        VStack(spacing: 26 * scale) {
            w(.folds, .accessoryInline)
            w(.phoneDown, .accessoryInline)
            w(.lifetime, .accessoryInline)
            Text(Date(), format: .dateTime.hour().minute())
                .font(.system(size: 110 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
            HStack(spacing: 22 * scale) {
                w(.folds, .accessoryCircular)
                w(.phoneDown, .accessoryCircular)
            }
            HStack(spacing: 22 * scale) {
                w(.folds, .accessoryRectangular, 1.1)
                w(.phoneDown, .accessoryRectangular, 1.1)
            }
            w(.lifetime, .accessoryRectangular, 1.1)
        }
        .foregroundStyle(.white)
    }
}
