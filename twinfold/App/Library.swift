// Library.swift — Twinfold
//
// Bookmarks, history, saved pairs and settings, kept on the device in the app's own folder.

import Foundation
import WebKit
import Observation

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var folder: String?
}

struct Visit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var date: Date
}

/// Two pages that go together, saved to open again in one tap (and from the home-screen icon).
struct Pair: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var first: URL
    var second: URL
    /// The first pane's share of the screen when there is no fold (0.5 = half).
    var ratio: Double = 0.5
}

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case google, duckDuckGo, bing, ecosia, qwant, startpage
    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .ecosia: return "Ecosia"
        case .qwant: return "Qwant"
        case .startpage: return "Startpage"
        }
    }

    func url(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "=", "?"])) ?? query
        switch self {
        case .google: return URL(string: "https://www.google.com/search?q=\(q)")
        case .duckDuckGo: return URL(string: "https://duckduckgo.com/?q=\(q)")
        case .bing: return URL(string: "https://www.bing.com/search?q=\(q)")
        case .ecosia: return URL(string: "https://www.ecosia.org/search?q=\(q)")
        case .qwant: return URL(string: "https://www.qwant.com/?q=\(q)")
        case .startpage: return URL(string: "https://www.startpage.com/do/search?query=\(q)")
        }
    }
}

@MainActor @Observable
final class Library {
    static let shared = Library()

    private(set) var bookmarks: [Bookmark] = []
    private(set) var history: [Visit] = []
    private(set) var pairs: [Pair] = []

    var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: "searchEngine") }
    }
    /// Blocks known ad and tracker servers on every page.
    var blockTrackers: Bool {
        didSet { defaults.set(blockTrackers, forKey: "blockTrackers"); ContentBlocker.shared.apply() }
    }
    /// Hides the cookie banners of the common consent tools.
    var hideCookieBanners: Bool {
        didSet { defaults.set(hideCookieBanners, forKey: "hideCookieBanners"); ContentBlocker.shared.apply() }
    }
    /// Links tapped with "open in the other pane" go there; links from other apps open in the active pane.
    var linksFromAppsInNewTab: Bool {
        didSet { defaults.set(linksFromAppsInNewTab, forKey: "linksFromAppsInNewTab") }
    }

    /// Two-finger swipes on a page: back, forward, one or two pages, new tab.
    var twoFingerGestures: Bool {
        didSet { defaults.set(twoFingerGestures, forKey: "twoFingerGestures") }
    }

    /// The floating bar sits at the top of the page instead of the bottom.
    var barAtTop: Bool = UserDefaults.standard.bool(forKey: "barAtTop") {
        didSet { UserDefaults.standard.set(barAtTop, forKey: "barAtTop") }
    }
    /// The active page's tabs as icons on its edge.
    var sideDock: Bool = UserDefaults.standard.object(forKey: "sideDock2") as? Bool ?? false {
        didSet { UserDefaults.standard.set(sideDock, forKey: "sideDock2") }
    }

    /// Tabs and pinned apps together on one edge (easier with one hand), or split: apps on one edge, tabs on the other.
    var dockTogether: Bool = UserDefaults.standard.object(forKey: "dockTogether") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dockTogether, forKey: "dockTogether") }
    }

    /// The dock goes to the side of the last touch (off once it has been sent to a side by hand).
    var dockFollowsHand: Bool = UserDefaults.standard.object(forKey: "dockFollowsHand") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dockFollowsHand, forKey: "dockFollowsHand") }
    }
    var dockRight: Bool = UserDefaults.standard.bool(forKey: "dockRight") {
        didSet { UserDefaults.standard.set(dockRight, forKey: "dockRight") }
    }

    /// A video's full-screen button fills its own pane instead of the whole display (applies to pages opened next).
    var fullscreenInPane: Bool = UserDefaults.standard.object(forKey: "fullscreenInPane") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fullscreenInPane, forKey: "fullscreenInPane") }
    }

    /// The floating action palette (in place of the side bars).
    var palette: Bool = UserDefaults.standard.object(forKey: "palette") as? Bool ?? true {
        didSet { UserDefaults.standard.set(palette, forKey: "palette") }
    }
    var paletteNames: Bool = UserDefaults.standard.object(forKey: "paletteNames") as? Bool ?? true {
        didSet { UserDefaults.standard.set(paletteNames, forKey: "paletteNames") }
    }

    /// Web apps pinned to the side dock (their site's address).
    private(set) var dockApps: [URL] = (UserDefaults.standard.array(forKey: "dockApps") as? [String])?.compactMap(URL.init(string:))
        ?? ["https://m.youtube.com", "https://mail.google.com", "https://www.google.com/maps"].compactMap(URL.init(string:))

    func pin(_ url: URL) {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.path = ""; c?.query = nil; c?.fragment = nil
        guard let home = c?.url, !dockApps.contains(where: { $0.host() == home.host() }) else { return }
        dockApps.append(home)
        if dockApps.count > 6 { dockApps.removeFirst() }
        UserDefaults.standard.set(dockApps.map(\.absoluteString), forKey: "dockApps")
        CloudSync.push()
    }

    func unpin(_ url: URL) {
        dockApps.removeAll { $0 == url }
        UserDefaults.standard.set(dockApps.map(\.absoluteString), forKey: "dockApps")
    }

    /// iPhone Duo half folded: the video above fills its half.
    var laptopPosture: Bool = UserDefaults.standard.object(forKey: "laptopPosture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(laptopPosture, forKey: "laptopPosture") }
    }

    /// Pages in dark colours (sites without a dark design are inverted, pictures kept).
    var darkPages: Bool = UserDefaults.standard.bool(forKey: "darkPages") {
        didSet { UserDefaults.standard.set(darkPages, forKey: "darkPages"); PageStyle.shared.apply() }
    }
    /// One font for every page (Pro).
    var pageFont: PageFont = PageFont(rawValue: UserDefaults.standard.string(forKey: "pageFont") ?? "") ?? .site {
        didSet { UserDefaults.standard.set(pageFont.rawValue, forKey: "pageFont"); PageStyle.shared.apply() }
    }
    /// Private tabs ask for Face ID after the app was in the background.
    var lockPrivate: Bool = UserDefaults.standard.bool(forKey: "lockPrivate") {
        didSet { UserDefaults.standard.set(lockPrivate, forKey: "lockPrivate") }
    }
    /// Bookmarks, pairs and pinned apps in iCloud.
    var iCloudSync: Bool = UserDefaults.standard.object(forKey: "iCloudSync") as? Bool ?? true {
        didSet { UserDefaults.standard.set(iCloudSync, forKey: "iCloudSync"); if iCloudSync { CloudSync.pull(); CloudSync.push() } }
    }
    /// What the start page shows.
    var startFavourites: Bool = UserDefaults.standard.object(forKey: "startFavourites") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startFavourites, forKey: "startFavourites") }
    }
    var startApps: Bool = UserDefaults.standard.object(forKey: "startApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startApps, forKey: "startApps") }
    }
    var startPairs: Bool = UserDefaults.standard.object(forKey: "startPairs") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startPairs, forKey: "startPairs") }
    }
    var startRecent: Bool = UserDefaults.standard.object(forKey: "startRecent") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startRecent, forKey: "startRecent") }
    }

    /// Other sign-ins (each with its own cookies), besides the main one.
    private(set) var profiles: [Profile] = {
        guard let d = UserDefaults.standard.data(forKey: "profiles") else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: d)) ?? []
    }()

    func addProfile(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        profiles.append(Profile(name: n, hue: Double(profiles.count) * 0.17 + 0.55))
        UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: "profiles")
    }

    func deleteProfile(_ p: Profile) {
        profiles.removeAll { $0.id == p.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(profiles), forKey: "profiles")
        WKWebsiteDataStore.remove(forIdentifier: p.id) { _ in }
    }

    /// What came from iCloud joins what is here (nothing is lost on either side).
    func mergeFromCloud(bookmarks b: [Bookmark]?, pairs p: [Pair]?, dockApps apps: [URL]?) {
        if let b {
            let known = Set(bookmarks.map(\.url))
            let new = b.filter { !known.contains($0.url) }
            if !new.isEmpty { bookmarks.append(contentsOf: new); save(bookmarks, "bookmarks") }
        }
        if let p {
            let known = Set(pairs.map { [$0.first, $0.second] })
            let new = p.filter { !known.contains([$0.first, $0.second]) }
            if !new.isEmpty { pairs.append(contentsOf: new); save(pairs, "pairs") }
        }
        if let apps, dockApps != apps, !apps.isEmpty {
            for a in apps where !dockApps.contains(a) { dockApps.append(a) }
            UserDefaults.standard.set(dockApps.map(\.absoluteString), forKey: "dockApps")
        }
    }

    /// Bumped when a gesture's action changes, so the settings list redraws.
    var gestureRevision = 0

    private let defaults = UserDefaults.standard

    private init() {
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: "searchEngine") ?? "") ?? Self.defaultEngine
        blockTrackers = defaults.object(forKey: "blockTrackers") as? Bool ?? true
        hideCookieBanners = defaults.object(forKey: "hideCookieBanners") as? Bool ?? false
        linksFromAppsInNewTab = defaults.object(forKey: "linksFromAppsInNewTab") as? Bool ?? true
        twoFingerGestures = defaults.object(forKey: "twoFingerGestures") as? Bool ?? true
        bookmarks = load("bookmarks") ?? Self.starterBookmarks
        history = load("history") ?? []
        pairs = load("pairs") ?? []
    }

    /// Ecosia or Qwant feel at home in parts of Europe, but Google is what most people expect at first.
    private static var defaultEngine: SearchEngine { .google }

    private static let starterBookmarks: [Bookmark] = [
        Bookmark(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org")!),
        Bookmark(title: "YouTube", url: URL(string: "https://m.youtube.com")!),
        Bookmark(title: "Reddit", url: URL(string: "https://www.reddit.com")!),
        Bookmark(title: "OpenStreetMap", url: URL(string: "https://www.openstreetmap.org")!),
    ]

    // MARK: Bookmarks

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(title: String, url: URL) {
        if let i = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.insert(Bookmark(title: title.isEmpty ? (url.host() ?? url.absoluteString) : title, url: url), at: 0)
        }
        save(bookmarks, "bookmarks")
    }

    func deleteBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save(bookmarks, "bookmarks")
    }

    func moveBookmarks(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        save(bookmarks, "bookmarks")
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let i = bookmarks.firstIndex(of: bookmark) else { return }
        bookmarks[i].title = title
        save(bookmarks, "bookmarks")
    }

    /// Adds bookmarks read from an exported bookmarks file (Safari, Chrome, Firefox, Edge), skipping known ones.
    @discardableResult
    func importBookmarks(_ found: [Bookmark]) -> Int {
        let known = Set(bookmarks.map(\.url))
        let new = found.filter { !known.contains($0.url) }
        bookmarks.append(contentsOf: new)
        save(bookmarks, "bookmarks")
        return new.count
    }

    // MARK: History

    func record(title: String, url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        if let last = history.first, last.url == url {
            history[0].title = title.isEmpty ? last.title : title
        } else {
            history.insert(Visit(title: title, url: url, date: Date()), at: 0)
            if history.count > 5000 { history.removeLast(history.count - 5000) }
        }
        scheduleHistorySave()
    }

    func deleteHistory(at offsets: IndexSet, in list: [Visit]) {
        let ids = Set(offsets.map { list[$0].id })
        history.removeAll { ids.contains($0.id) }
        save(history, "history")
    }

    func clearHistory() {
        history = []
        save(history, "history")
    }

    private var historySaveTask: Task<Void, Never>?
    private func scheduleHistorySave() {
        historySaveTask?.cancel()
        historySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.save(self.history, "history")
        }
    }

    /// Bookmarks and recent pages matching what is typed in the address bar.
    func suggestions(for text: String, limit: Int = 6) -> [Bookmark] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 1 else { return [] }
        var seen = Set<URL>()
        var out: [Bookmark] = []
        let candidates = bookmarks + history.map { Bookmark(title: $0.title, url: $0.url) }
        for b in candidates where out.count < limit {
            guard !seen.contains(b.url) else { continue }
            if b.title.lowercased().contains(q) || b.url.absoluteString.lowercased().contains(q) {
                seen.insert(b.url)
                out.append(b)
            }
        }
        return out
    }

    // MARK: Pairs

    func savePair(_ pair: Pair) {
        pairs.insert(pair, at: 0)
        save(pairs, "pairs")
        QuickActions.refresh()
    }

    func deletePairs(at offsets: IndexSet) {
        pairs.remove(atOffsets: offsets)
        save(pairs, "pairs")
        QuickActions.refresh()
    }

    func movePairs(from source: IndexSet, to destination: Int) {
        pairs.move(fromOffsets: source, toOffset: destination)
        save(pairs, "pairs")
        QuickActions.refresh()
    }

    /// Replaces what is shown without saving it (screenshots).
    func setSamples(bookmarks: [Bookmark], pairs: [Pair]) {
        self.bookmarks = bookmarks
        self.pairs = pairs
        history = []
        samplesOnly = true
    }

    @ObservationIgnored private var samplesOnly = false

    // MARK: Files

    static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Twinfold", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: Self.folder.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        guard !samplesOnly, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: Self.folder.appendingPathComponent(name + ".json"), options: .atomic)
        if name == "bookmarks" || name == "pairs" { CloudSync.push() }
    }

    func loadSession() -> SavedSession? { load("session") }
}

/// The open tabs, kept for the next launch (private tabs are never saved).
struct SavedSession: Codable {
    struct PaneState: Codable {
        var urls: [URL]
        var current: Int
    }
    var panes: [PaneState]
    var innerSplit: Bool
    var outerSplit: Bool
    var ratio: Double
    var active: Int
}

/// Reads the bookmark files browsers export ("Netscape bookmark" HTML), keeping folder names.
enum BookmarkFile {
    static func parse(_ html: String) -> [Bookmark] {
        var out: [Bookmark] = []
        var folders: [String] = []
        let scanner = html as NSString
        let pattern = #"<H3[^>]*>(.*?)</H3>|</DL>|<A\s[^>]*HREF="([^"]+)"[^>]*>(.*?)</A>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        for m in re.matches(in: html, range: NSRange(location: 0, length: scanner.length)) {
            if m.range(at: 1).location != NSNotFound {
                folders.append(decode(scanner.substring(with: m.range(at: 1))))
            } else if m.range(at: 2).location != NSNotFound {
                let href = scanner.substring(with: m.range(at: 2))
                guard let url = URL(string: href), url.scheme == "http" || url.scheme == "https" else { continue }
                let title = decode(scanner.substring(with: m.range(at: 3)))
                out.append(Bookmark(title: title.isEmpty ? (url.host() ?? href) : title, url: url, folder: folders.last))
            } else if !folders.isEmpty {
                folders.removeLast()
            }
        }
        return out
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
