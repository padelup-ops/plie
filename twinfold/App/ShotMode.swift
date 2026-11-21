// ShotMode.swift — Twinfold
//
// App Store screenshots: launched with `-shot <name>`, the app opens sample pages bundled with it (invented sites,
// written for Twinfold) instead of the last session, and nothing is saved.

import Foundation

enum ShotMode {
    static let current: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-shot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    private static func page(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "html")
    }

    @MainActor
    static func configure(_ browser: Browser, _ shot: String) {
        Library.shared.useSamples()
        func show(_ pane: Int, _ name: String, _ host: String) {
            let tab = browser.makeTab(in: pane)
            tab.displayHost = host
            if let url = page(name) { tab.load(url) }
            browser.panes[pane].tabs.append(tab)
            browser.panes[pane].current = browser.panes[pane].tabs.count - 1
        }
        func blank(_ pane: Int) {
            browser.panes[pane].tabs.append(browser.makeTab(in: pane))
            browser.panes[pane].current = browser.panes[pane].tabs.count - 1
        }
        browser.innerSplit = true
        browser.outerSplit = true
        switch shot {
        case "start":
            show(0, "video", "dailyloaf.example")
            blank(1)
            browser.active = 1
        case "news":
            show(0, "news", "harbornews.example")
            show(1, "map", "trailmaps.example")
        case "single":
            browser.outerSplit = false
            show(0, "recipe", "dailyloaf.example")
            show(1, "video", "dailyloaf.example")
        case "tabs":
            show(0, "news", "harbornews.example")
            show(0, "video", "dailyloaf.example")
            show(1, "map", "trailmaps.example")
            show(1, "recipe", "dailyloaf.example")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { browser.sheet = .tabs }
        case "pairs":
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { browser.sheet = .pairs }
        default: // "split"
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            browser.active = 1
        }
    }
}

extension Library {
    /// Sample bookmarks and pairs for the screenshots (kept in memory only).
    func useSamples() {
        let ex = { (s: String) in URL(string: "https://\(s).example/")! }
        setSamples(
            bookmarks: [
                Bookmark(title: "Daily Loaf", url: ex("dailyloaf")),
                Bookmark(title: "Harbor News", url: ex("harbornews")),
                Bookmark(title: "Trail Maps", url: ex("trailmaps")),
                Bookmark(title: "Field Notes", url: ex("fieldnotes")),
                Bookmark(title: "Market Watch", url: ex("marketboard")),
                Bookmark(title: "Language Lab", url: ex("languagelab")),
                Bookmark(title: "Pixel Forum", url: ex("pixelforum")),
                Bookmark(title: "Weather", url: ex("skycast")),
            ],
            pairs: [
                Pair(name: "Bake along", first: ex("dailyloaf"), second: ex("fieldnotes")),
                Pair(name: "Morning read", first: ex("harbornews"), second: ex("marketboard")),
                Pair(name: "Weekend hike", first: ex("trailmaps"), second: ex("skycast")),
                Pair(name: "Study hour", first: ex("languagelab"), second: ex("fieldnotes")),
            ]
        )
    }
}
