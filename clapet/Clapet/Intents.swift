import AppIntents
import WidgetKit

// MARK: - Actions Raccourcis
//
// Sur l'iPhone Duo, Raccourcis propose l'automatisation « When iPhone is Opened or Closed ».
// Branchée sur « Compter un pli » (iPhone fermé) et « Compter une ouverture » (iPhone ouvert),
// Duo Folds compte même quand il n'est pas à l'écran.

@MainActor
enum AutomaticCounter {
    /// Un pli. Passe par le compteur de l'app s'il tourne (pour ne pas compter deux fois), sinon par le coffre.
    static func close() -> Int {
        if let model = ClapetModel.current {
            model.automationClose()
            return model.stats.today
        }
        var stats = ClapetVault.load()
        let before = stats.today
        stats.addClose()
        stats.endOpen()
        stats.autoLast = Date()
        LimitAlerts.check(before: before, after: stats.today, limit: stats.goal, plus: stats.plus)
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
        return stats.today
    }

    static func open() {
        if let model = ClapetModel.current {
            model.automationOpen()
            return
        }
        var stats = ClapetVault.load()
        stats.addOpen()
        stats.startOpen()
        stats.autoLast = Date()
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// « Compter un pli » : à mettre dans l'automatisation « iPhone fermé ».
struct CountClapIntent: AppIntent {
    static var title: LocalizedStringResource = "Count a fold"
    static var description = IntentDescription("Adds one fold to today's count. Use it in a Shortcuts automation that runs when your Duo is closed.")
    static var openAppWhenRun = false

    /// Rien à l'écran : l'automatisation tourne en silence (le nombre reste disponible pour Raccourcis).
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let today = AutomaticCounter.close()
        return .result(value: today)
    }
}

/// « Compter une ouverture » : à mettre dans l'automatisation « iPhone ouvert » (facultatif).
struct CountOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Count an opening"
    static var description = IntentDescription("Adds one opening to today's count. Use it in a Shortcuts automation that runs when your Duo is opened.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AutomaticCounter.open()
        return .result()
    }
}

struct TodayClapsIntent: AppIntent {
    static var title: LocalizedStringResource = "Folds today"
    static var description = IntentDescription("Tells you how many times you closed your Duo today.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let today = ClapetModel.current?.stats.today ?? ClapetVault.load().today
        return .result(value: today, dialog: "\(today) folds today")
    }
}

struct ClapetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CountClapIntent(),
                    phrases: ["Count a fold in \(.applicationName)", "Add a fold in \(.applicationName)"],
                    shortTitle: "Count a fold",
                    systemImageName: "rectangle.compress.vertical")
        AppShortcut(intent: CountOpenIntent(),
                    phrases: ["Count an opening in \(.applicationName)"],
                    shortTitle: "Count an opening",
                    systemImageName: "rectangle.expand.vertical")
        AppShortcut(intent: TodayClapsIntent(),
                    phrases: ["How many folds today in \(.applicationName)", "My folds in \(.applicationName)"],
                    shortTitle: "Folds today",
                    systemImageName: "chart.bar.fill")
    }
}
