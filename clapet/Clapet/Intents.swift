import AppIntents
import WidgetKit

/// « Compter un pli » : utilisable dans Raccourcis et par Siri, même app fermée.
struct CountClapIntent: AppIntent {
    static var title: LocalizedStringResource = "Count a fold"
    static var description = IntentDescription("Adds one fold to today's count.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var stats = ClapetVault.load()
        let before = stats.today
        stats.addClose()
        LimitAlerts.check(before: before, after: stats.today, limit: stats.goal, plus: stats.plus)
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(stats.today) folds today")
    }
}

struct TodayClapsIntent: AppIntent {
    static var title: LocalizedStringResource = "Folds today"
    static var description = IntentDescription("Tells you how many times you closed your Duo today.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let stats = ClapetVault.load()
        return .result(value: stats.today, dialog: "\(stats.today) folds today")
    }
}

struct ClapetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CountClapIntent(),
                    phrases: ["Count a fold in \(.applicationName)", "Add a fold in \(.applicationName)"],
                    shortTitle: "Count a fold",
                    systemImageName: "plus.circle.fill")
        AppShortcut(intent: TodayClapsIntent(),
                    phrases: ["How many folds today in \(.applicationName)", "My folds in \(.applicationName)"],
                    shortTitle: "Folds today",
                    systemImageName: "chart.bar.fill")
    }
}
