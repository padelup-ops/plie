import AppIntents
import WidgetKit

/// « Compter un clapet » : utilisable dans Raccourcis et par Siri, même app fermée.
struct CountClapIntent: AppIntent {
    static var title: LocalizedStringResource = "Count a clap"
    static var description = IntentDescription("Adds one clap to today's count.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var stats = ClapetVault.load()
        stats.addClose()
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(stats.today) claps today")
    }
}

struct TodayClapsIntent: AppIntent {
    static var title: LocalizedStringResource = "Claps today"
    static var description = IntentDescription("Tells you how many times you closed your Duo today.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let stats = ClapetVault.load()
        return .result(value: stats.today, dialog: "\(stats.today) claps today")
    }
}

struct ClapetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CountClapIntent(),
                    phrases: ["Count a clap in \(.applicationName)", "Add a clap in \(.applicationName)"],
                    shortTitle: "Count a clap",
                    systemImageName: "plus.circle.fill")
        AppShortcut(intent: TodayClapsIntent(),
                    phrases: ["How many claps today in \(.applicationName)", "My claps in \(.applicationName)"],
                    shortTitle: "Claps today",
                    systemImageName: "chart.bar.fill")
    }
}
