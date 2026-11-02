import SwiftUI
import WatchConnectivity
import WidgetKit

// MARK: - Foldly sur l'Apple Watch (demandé dans le sondage)
//
// Les chiffres du jour au poignet : les plis d'aujourd'hui comparés à la moyenne, la semaine,
// le temps ouvert et fermé. Tout vient de l'iPhone (WatchConnectivity), rien n'est compté sur la montre.

@main
struct FoldlyWatchApp: App {
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    private(set) var data: FoldlyWatchData?

    override init() {
        data = WatchVault.load()
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let raw = context["data"] as? Data,
              let value = try? JSONDecoder().decode(FoldlyWatchData.self, from: raw) else { return }
        DispatchQueue.main.async {
            if let current = self.data, current.updated > value.updated { return }
            self.data = value
            WatchVault.save(raw)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    /// Captures de la vidéo : `-demoWatchPage today|week|time|face` montre une seule page avec les chiffres d'exemple.
    private var demoPage: String? { UserDefaults.standard.string(forKey: "demoWatchPage") }

    var body: some View {
        if let page = demoPage {
            let data = FoldlyWatchData.sample
            switch page {
            case "week": WeekPage(data: data)
            case "time": TimePage(data: data, now: Date())
            #if DEMO_FACE
            case "face": DemoFace(data: data)
            #endif
            default: TodayPage(data: data)
            }
        } else {
            live
        }
    }

    private var live: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let data = store.data?.current(at: context.date) {
                TabView {
                    TodayPage(data: data)
                    WeekPage(data: data)
                    TimePage(data: data, now: context.date)
                }
                .tabViewStyle(.verticalPage)
            } else {
                WaitingPage()
            }
        }
    }
}

/// Aujourd'hui : l'anneau (comparé à la moyenne) et le chiffre du jour.
struct TodayPage: View {
    let data: FoldlyWatchData

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(WatchPalette.track, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.001, data.progress))
                    .stroke(data.over ? WatchPalette.orange : WatchPalette.mint,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(data.today)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("folds today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
            }
            .frame(maxWidth: 140, maxHeight: 140)
            data.statusText
                .font(.footnote.weight(.medium))
                .foregroundStyle(data.over ? WatchPalette.orange : WatchPalette.mint)
                .multilineTextAlignment(.center)
        }
        .containerBackground(WatchPalette.mint.gradient.opacity(0.18), for: .tabView)
        .navigationTitle(Text(verbatim: "Foldly"))
        .accessibilityElement(children: .combine)
    }
}

/// La semaine : 7 barres, aujourd'hui en couleur.
struct WeekPage: View {
    let data: FoldlyWatchData

    var body: some View {
        let week = data.week.count == 7 ? data.week : Array(repeating: 0, count: 7)
        let top = max(1, week.max() ?? 1)
        let cal = Calendar.current
        let letters = cal.veryShortStandaloneWeekdaySymbols
        VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.headline)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
                    let wd = cal.component(.weekday, from: day) - 1
                    VStack(spacing: 3) {
                        // Le chiffre au-dessus de la barre, comme sur l'iPhone
                        Text(week[i], format: .number)
                            .font(.system(size: 10, weight: i == 6 ? .bold : .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(i == 6 ? WatchPalette.mint : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Capsule()
                            .fill(i == 6 ? WatchPalette.mint : WatchPalette.track)
                            .frame(height: max(4, 64 * CGFloat(week[i]) / CGFloat(top)))
                        Text(letters.indices.contains(wd) ? letters[wd] : "")
                            .font(.caption2)
                            .foregroundStyle(i == 6 ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 98, alignment: .bottom)
            Text("\(week.reduce(0, +)) this week")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .containerBackground(WatchPalette.mint.gradient.opacity(0.12), for: .tabView)
        .accessibilityElement(children: .combine)
    }
}

/// Le temps : fermé, ouvert, depuis quand, et l'heure où l'on plie le plus.
struct TimePage: View {
    let data: FoldlyWatchData
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row(Text("Closed today"), short(data.closedSeconds))
                row(Text("Open today"), short(data.openSeconds))
                if let since = data.openSince {
                    Label { Text("Open since \(since.formatted(date: .omitted, time: .shortened))") } icon: { Image(systemName: "iphone.gen3") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let last = data.lastClose {
                    Label { Text("Last fold \(last.formatted(date: .omitted, time: .shortened))") } icon: { Image(systemName: "moon.zzz.fill") }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let peak = data.peakHour {
                    Label { Text("Most folds around \(hour(peak))") } icon: { Image(systemName: "clock.fill") }
                        .font(.footnote)
                        .foregroundStyle(WatchPalette.mint)
                }
                Text("\(data.total) folds since day one")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WatchPalette.mint.gradient.opacity(0.08), for: .tabView)
    }

    private func row(_ title: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title.font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func short(_ t: Double) -> String {
        let minutes = Int(max(0, t) / 60)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(Double(minutes * 60)).formatted(.units(allowed: allowed, width: .narrow))
    }

    private func hour(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        return (Calendar.current.date(from: c) ?? Date()).formatted(.dateTime.hour())
    }
}

/// Avant le premier envoi de l'iPhone.
struct WaitingPage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.title)
                .foregroundStyle(WatchPalette.mint)
            Text("Open Foldly on your iPhone")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Your folds show up here in a few seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#if DEMO_FACE
/// Un cadran d'exemple avec les vraies complications de Foldly (pour la vidéo uniquement).
struct DemoFace: View {
    let data: FoldlyWatchData

    var body: some View {
        let entry = WatchEntry(date: Date(), data: data)
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                FoldlyComplicationView(entry: entry, forced: .accessoryCircular)
                    .frame(width: 52, height: 52)
                Spacer()
                Text(verbatim: "MON 2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchPalette.mint)
            }
            Text(verbatim: "10:09")
                .font(.system(size: 62, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            FoldlyComplicationView(entry: entry, forced: .accessoryRectangular)
                .frame(height: 52)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}
#endif
