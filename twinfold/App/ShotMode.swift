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
        case "relayout":
            // Test: the layout changes after launch (like turning the device): panes must follow.
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { browser.setAxis(.stacked) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { browser.ratio = 0.35; browser.followsFold = false }
        case "overview":
            show(0, "video", "dailyloaf.example")
            show(0, "news", "harbornews.example")
            show(1, "recipe", "dailyloaf.example")
            show(1, "map", "trailmaps.example")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { browser.showOverview() }
        case "notes":
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            VideoNotes.shared.add("Fold the bottom third up", at: 462, for: browser.panes[0].tab?.url)
            VideoNotes.shared.add("Seam side up in the basket", at: 515, for: browser.panes[0].tab?.url)
            VideoNotes.shared.add("Score at 30°, 1 cm deep", at: 731, for: browser.panes[0].tab?.url)
            browser.panes[1].tool = .videoNotes
        case "paywall":
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Store.shared.asking = .general }
        case "dualplay":
            // Test: two videos with sound at once, then the pane buttons (sound cut, video over the pane).
            show(0, "dualtest-a", "video-a.example")
            show(1, "dualtest-b", "video-b.example")
            Task { await runDualPlayTest(browser) }
        default: // "split"
            show(0, "video", "dailyloaf.example")
            show(1, "recipe", "dailyloaf.example")
            browser.active = 1
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("twinfold-test.txt")
                try? ("layout: " + PanesArea.lastLayout + " | split \(browser.isSplit) axis \(browser.axis) hasFold \(browser.hasFold)").write(to: url, atomically: true, encoding: .utf8)
            }
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

// MARK: - Two videos at once (simulator test)

extension ShotMode {
    @MainActor
    static func runDualPlayTest(_ browser: Browser) async {
        var log: [String] = []
        func state(_ label: String) async {
            for i in 0..<2 {
                guard let tab = browser.panes[i].tab else { continue }
                let js = "(function(){var v=document.getElementById('v');return v?[v.paused,v.muted,v.currentTime.toFixed(1)].join(' '):'none';})()"
                let r = (try? await tab.webView.evaluateJavaScript(js)) as? String ?? "?"
                log.append("\(label) volet \(i) : paused muted t = \(r) | rapport : lecture \(tab.mediaPlaying) vidéo \(tab.mediaVideo) coupé \(tab.isMuted) étirée \(tab.isFilled)")
            }
        }
        try? await Task.sleep(for: .seconds(6))
        await state("6 s, au départ")
        // Mute the pane that has the sound: the other video, stopped by iOS, should start again (muted).
        for i in 0..<2 { if let t = browser.panes[i].tab, t.mediaPlaying, !t.isMuted { t.setMuted(true) } }
        for i in 0..<2 { _ = try? await browser.panes[i].tab?.webView.evaluateJavaScript("var v=document.getElementById('v');v.muted=true;v.play();1") }
        try? await Task.sleep(for: .seconds(2))
        await state("8 s, les deux sans son")
        if let t1 = browser.panes[1].tab { browser.toggleMute(t1) }
        try? await Task.sleep(for: .seconds(2))
        await state("10 s, son sur le volet 1")
        if let t0 = browser.panes[0].tab { browser.toggleMute(t0) }
        try? await Task.sleep(for: .seconds(2))
        await state("12 s, son passé au volet 0")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("twinfold-test.txt")
        try? log.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
