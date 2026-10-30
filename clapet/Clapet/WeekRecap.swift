import Charts
import SwiftUI
import UserNotifications

// MARK: - Le bilan de la semaine
//
// Chaque semaine (le dernier jour de la semaine, à partir de 18 h) : les plis de la semaine, comparés à la semaine
// d'avant, le temps ouvert et fermé, le jour record et le plus calme, et une carte à partager.
// Une carte l'annonce sur l'accueil pendant 3 jours, et une notification arrive à 19 h.

enum WeekRecapRule {
    private static let seenKey = "weekRecap.seen"

    /// Le bilan à montrer maintenant.
    static func current(_ stats: ClapetStats, now: Date = Date()) -> WeekRecap {
        stats.weekRecap(endingOn: ClapetStats.recapEnd(now: now), now: now)
    }

    /// La carte « Ta semaine est prête » : jusqu'à 3 jours après la fin de la semaine, tant qu'on ne l'a pas ouverte.
    static func shouldShowCard(_ stats: ClapetStats, now: Date = Date()) -> Bool {
        let recap = current(stats, now: now)
        guard !recap.isEmpty, UserDefaults.standard.string(forKey: seenKey) != recap.id else { return false }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: recap.end), to: now).day ?? 99
        return days <= 3
    }

    static func markSeen(_ recap: WeekRecap) {
        UserDefaults.standard.set(recap.id, forKey: seenKey)
    }

    /// « 12 % de moins que la semaine d'avant ».
    static func changeText(_ change: Double?) -> Text {
        guard let change else { return Text("Your first week with Foldly") }
        if abs(change) < 0.005 { return Text("Same as the week before") }
        let pct = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return change > 0 ? Text("\(pct) more than the week before") : Text("\(pct) less than the week before")
    }
}

/// La notification du bilan : chaque semaine, le dernier jour de la semaine à 19 h.
enum WeekRecapNotice {
    private static let key = "weekRecap.notify"
    private static let id = "foldly.week"

    /// Activée par défaut.
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Renvoie faux si iOS refuse les notifications.
    static func setOn(_ on: Bool) async -> Bool {
        if on {
            let ok = await LimitAlerts.requestPermission()
            UserDefaults.standard.set(ok, forKey: key)
            if ok { await add() }
            return ok
        }
        UserDefaults.standard.set(false, forKey: key)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        return true
    }

    /// À l'ouverture de l'app : programme la notification si c'est permis. Sans réponse encore,
    /// on demande des notifications « discrètes » (sans fenêtre : elles arrivent dans le centre de notifications).
    static func schedule(_ stats: ClapetStats) {
        guard isOn, !Demo.seeded else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                await add()
            case .notDetermined:
                if (try? await center.requestAuthorization(options: [.provisional, .alert, .sound])) == true { await add() }
            default:
                break
            }
        }
    }

    private static func add() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your week with Foldly")
        content.body = String(localized: "Your weekly recap is ready: your folds, time open and closed, and your busiest day.")
        var at = DateComponents()
        at.weekday = ClapetStats.recapWeekday
        at.hour = 19
        at.minute = 0
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: at, repeats: true))
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// La carte de l'accueil : « Ta semaine est prête ».
struct WeekRecapPromo: View {
    let recap: WeekRecap
    var onOpen: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title2)
                    .foregroundStyle(Color.dfAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your week is ready")
                        .font(.headline)
                    Text("\(recap.total) folds · \(WeekRecapRule.changeText(recap.change))")
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
                Label { Text("See my week") } icon: { Image(systemName: "chart.bar.fill") }
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

/// Le bilan, semaine par semaine.
struct WeekRecapView: View {
    @Environment(ClapetModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var end = ClapetStats.recapEnd()
    @State private var image: Image?

    private var latest: Date { ClapetStats.recapEnd() }

    var body: some View {
        let s = model.stats
        let recap = s.weekRecap(endingOn: end)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    picker(recap)
                    if recap.isEmpty {
                        Text("No folds counted this week.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    } else {
                        summary(recap)
                        chart(recap)
                        grid(recap)
                        highlights(recap)
                        share
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color.dfBackground.ignoresSafeArea())
            .navigationTitle(Text("Your week"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .task(id: recap.id) { await render(recap) }
            .onAppear { WeekRecapRule.markSeen(WeekRecapRule.current(s)) }
        }
        .tint(.dfAccent)
    }

    // MARK: Morceaux

    private func range(_ recap: WeekRecap) -> String {
        (recap.start..<recap.end).formatted(.interval.day().month(.abbreviated))
    }

    private func picker(_ recap: WeekRecap) -> some View {
        let first = model.stats.firstDay.flatMap(ClapetStats.date)
        let canGoBack = first.map { recap.start > $0 } ?? false
        let canGoForward = ClapetStats.key(end) < ClapetStats.key(latest)
        return HStack {
            Button { move(-7) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .disabled(!canGoBack)
                .accessibilityLabel(Text("Previous week"))
            Spacer()
            Text(range(recap))
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button { move(7) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .disabled(!canGoForward)
                .accessibilityLabel(Text("Next week"))
        }
        .font(.body.weight(.semibold))
    }

    private func move(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: end) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { end = min(next, latest) }
    }

    private func summary(_ recap: WeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(recap.total)")
                    .font(.system(size: 64, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("folds")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            WeekRecapRule.changeText(recap.change)
                .font(.headline)
                .foregroundStyle(Color.dfAccent)
        }
    }

    private func chart(_ recap: WeekRecap) -> some View {
        let busiest = recap.busiest.map { ClapetStats.key($0.date) }
        let avg = Double(recap.perDay)
        return Chart {
            ForEach(0..<recap.days.count, id: \.self) { i in
                let d = recap.days[i]
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Folds", d.closes), width: .ratio(0.7))
                    .foregroundStyle(ClapetStats.key(d.date) == busiest ? Color.dfAccent : Color.dfBar)
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(d.closes)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
            }
            if avg > 0 {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: 170)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }

    private func grid(_ recap: WeekRecap) -> some View {
        let measured = model.stats.autoLast != nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(Text("Per day"), "\(recap.perDay)", detail: Text("on the days counted"))
            tile(Text("Time open"), TimeFormat.short(recap.open),
                 detail: recap.openChange.map { WeekRecapRule.changeText($0) })
            tile(Text("Time closed"), measured || recap.closed > 0 ? TimeFormat.short(recap.closed) : "—",
                 detail: measured ? nil : Text("Needs the Shortcuts automations"))
            tile(Text("Quick checks"), "\(recap.peeks)", detail: Text("Opened less than 10 s"))
            tile(Text("Longest break"), TimeFormat.short(recap.longestBreak), detail: nil)
            tile(Text("Days counted"), "\(recap.tracked)", detail: nil)
        }
    }

    private func tile(_ title: Text, _ value: String, detail: Text?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.dfCard))
        .accessibilityElement(children: .combine)
    }

    private func highlights(_ recap: WeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = recap.busiest {
                highlight("arrow.up.circle.fill", Text("Busiest day"),
                          Text("\(Text(b.date, format: .dateTime.weekday(.wide))) · \(b.closes) folds"))
            }
            if let c = recap.calmest {
                highlight("arrow.down.circle.fill", Text("Calmest day"),
                          Text("\(Text(c.date, format: .dateTime.weekday(.wide))) · \(c.closes) folds"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dfCard))
    }

    private func highlight(_ symbol: String, _ title: Text, _ value: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.dfAccent)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.footnote).foregroundStyle(.secondary)
                value.font(.headline)
            }
        }
    }

    @ViewBuilder
    private var share: some View {
        if let image {
            ShareLink(item: image,
                      message: Text("My week with Foldly: \(ShareDaySheet.appStoreURL)"),
                      preview: SharePreview(Text(verbatim: "Foldly"), image: image)) {
                Label { Text("Share my week") } icon: { Image(systemName: "square.and.arrow.up") }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.dfAccent))
                    .foregroundStyle(Color.dfOnAccent)
            }
            .padding(.top, 4)
        }
    }

    @MainActor
    private func render(_ recap: WeekRecap) {
        let renderer = ImageRenderer(content: WeekShareCard(recap: recap))
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// L'image à partager : la semaine en un coup d'œil. Couleurs fixes, pour qu'elle rende pareil partout.
struct WeekShareCard: View {
    let recap: WeekRecap

    private let top = Color(red: 0.055, green: 0.078, blue: 0.078)
    private let bottom = Color(red: 0.05, green: 0.21, blue: 0.19)
    private let mint = Color(red: 0.36, green: 0.89, blue: 0.78)
    private let bar = Color(red: 0.12, green: 0.42, blue: 0.37)

    var body: some View {
        let highest = max(1, recap.days.map(\.closes).max() ?? 1)
        let busiest = recap.busiest.map { ClapetStats.key($0.date) }
        VStack(alignment: .leading, spacing: 0) {
            Text((recap.start..<recap.end).formatted(.interval.day().month(.wide)))
                .font(.system(size: 14, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(mint)
            Spacer(minLength: 12)
            Text("This week I folded my phone")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(recap.total)")
                    .font(.system(size: 88, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                Text("times")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.7))
            }
            WeekRecapRule.changeText(recap.change)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(mint)
            Spacer(minLength: 18)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<recap.days.count, id: \.self) { i in
                    let d = recap.days[i]
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ClapetStats.key(d.date) == busiest ? mint : bar)
                            .frame(height: max(6, 80 * CGFloat(d.closes) / CGFloat(highest)))
                        Text(d.date, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104, alignment: .bottom)
            Spacer(minLength: 14)
            HStack {
                Text("\(TimeFormat.short(recap.open)) open")
                Spacer()
                if recap.closed > 0 { Text("\(TimeFormat.short(recap.closed)) closed") }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 14)
            HStack(spacing: 10) {
                Image("TutorialIcon")
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Foldly")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("The fold counter · App Store")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(26)
        .frame(width: 360, height: 480)
        .background(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
    }
}
