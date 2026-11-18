import Foundation
import WidgetKit

/// Settings shared by the app and the widget through one App Group.
/// The group id is also in the entitlements. It follows this repo's prefix
/// (`group.com.padelup.foldwidgets`), not `group.app.foldwidgets.shared`.
enum FoldStore {
    static let suiteName = "group.com.padelup.foldwidgets"
    static let storageKey = "fold.settings.v1"

    static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static var hasSaved: Bool {
        suite.data(forKey: storageKey) != nil
    }

    static func load() -> FoldSettings {
        guard let data = suite.data(forKey: storageKey) else { return FoldSettings() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FoldSettings.self, from: data)) ?? FoldSettings()
    }

    static func save(_ settings: FoldSettings) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(settings) else { return }
        suite.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
