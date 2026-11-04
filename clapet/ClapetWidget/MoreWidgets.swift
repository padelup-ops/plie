import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Les nouveaux widgets (demandés dans le sondage)
//
// « Tes heures » : quand tu déplies le plus (semaine type, heure par heure).
// « Depuis le début » : le compteur kilométrique de la charnière.
// « Compter un pli » : un bouton dans le Centre de contrôle et sur l'écran verrouillé (iOS 18).

struct HoursWidget: Widget {
    let kind = "FoldlyHours"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            HoursWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Your hours"))
        .description(Text("When you unfold the most: your typical week, hour by hour."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct LifetimeWidget: Widget {
    let kind = "FoldlyLifetime"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClapetProvider()) { entry in
            LifetimeWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Since day one"))
        .description(Text("Every fold since you started, like an odometer for your hinge."))
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Le bouton « Compter un pli » (Centre de contrôle, iOS 18)

/// Ajoute un pli, sans ouvrir l'app.
struct CountFoldControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Count a fold"
    static var description = IntentDescription("Adds one fold to today's count.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var stats = ClapetVault.load()
        stats.addClose()
        stats.endOpen(event: true)
        ClapetVault.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 18.0, *)
struct CountFoldControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FoldlyCountControl") {
            ControlWidgetButton(action: CountFoldControlIntent()) {
                Label { Text("Count a fold") } icon: { Image(systemName: "plus.circle") }
            }
        }
        .displayName("Count a fold")
        .description("Adds one fold to today's count.")
    }
}
