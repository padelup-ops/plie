// Browser.swift — Twinfold
//
// Two panes, each with its own tabs. On an unfolded iPhone Duo the panes meet at the fold; on the cover screen or
// any other iPhone they stack with a handle to resize them. The address bar always acts on the active pane.

import Observation
import SwiftUI
import WebKit

enum PaneTool { case videoNotes }

@MainActor @Observable
final class Pane: Identifiable {
    let id = UUID()
    var tabs: [Tab] = []
    var current: Int = 0
    /// A Twinfold tool shown in this pane instead of the page (the page stays behind it).
    var tool: PaneTool?

    var tab: Tab? { tabs.indices.contains(current) ? tabs[current] : nil }
}

@MainActor @Observable
final class Browser {
    static let shared = Browser()

    /// Panes 0 and 1. Pane 0 is above (or on the leading side).
    private(set) var panes: [Pane] = [Pane(), Pane()]
    var active = 0

    /// Split on the unfolded Duo (on by default) and on the cover screen / other iPhones (off by default).
    var innerSplit = true
    var outerSplit = false
    /// The first pane's share when the handle decides (no fold, or the handle was dragged).
    var ratio: Double = 0.5
    /// The two pages scroll together (the same share of each page).
    var syncScroll = false
    /// One pane over the whole screen for a while (the split comes back with the same gesture).
    var maximized: Int?
    /// The bottom bar steps aside until then (tap the bottom edge to bring it back sooner).
    var barHiddenUntil: Date?

    /// On an unfolded Duo the panes meet at the fold until the handle is dragged (double tap the handle: back).
    var followsFold = true

    /// Top and bottom, side by side, or automatic (along the fold, or across the longer side).
    enum SplitAxis: String, CaseIterable { case auto, stacked, sideBySide }
    /// Not kept between launches, and back to automatic whenever the device turns or folds: a choice made for one
    /// posture must never lock the others.
    var axis: SplitAxis = .auto

    /// The device turned, folded or unfolded: the panes follow it again.
    func postureChanged() {
        axis = .auto
        followsFold = true
        ratio = 0.5
    }

    func setAxis(_ a: SplitAxis) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            axis = a
            followsFold = true
            if !isSplit { isSplit = true }
        }
    }
    /// Set by the view: the display has a fold (an unfolded iPhone Duo).
    var hasFold = false

    var isSplit: Bool {
        get { hasFold ? innerSplit : outerSplit }
        set { if hasFold { innerSplit = newValue } else { outerSplit = newValue } }
    }

    // What the screen shows on top of the pages.
    var sheet: SheetKind?
    var editingAddress = false
    var toast: String?
    /// Private tabs are hidden until Face ID.
    var privateLocked = false
    /// The tab overview covers the screen.
    var overviewShown = false
    /// What the screen shows right now: pages side by side (or top and bottom). Set by the panes' layout.
    var layoutSideBySide = false

    /// The side dock sits on the side last touched, and tucks itself away after a few seconds.
    var dockOnRight = UserDefaults.standard.bool(forKey: "dockRight")
    var dockOpen = false
    /// The handle between the panes is being dragged: the web views keep their size until it's let go.
    var resizing = false
    @ObservationIgnored private var dockTimer: Task<Void, Never>?

    /// A touch on a page: the dock moves to that side of the screen (the right page side by side: the right edge)
    /// and gets out of the way at once. It only shows when its little tab is touched.
    func touched(atFraction x: CGFloat, pane: Int?) {
        let right: Bool
        if !Library.shared.dockFollowsHand { right = dockOnRight }
        else if isSplit, maximized == nil, layoutSideBySide, let pane { right = pane == 1 } else { right = x > 0.5 }
        if right != dockOnRight || dockOpen {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dockOnRight = right
                dockOpen = false
            }
        }
        dockTimer?.cancel()
    }

    /// Double tap on the dock's handle: over to the other side.
    func flipDock() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { dockOnRight.toggle() }
        // Sent there by hand: it stays there (Settings brings back "follows your hand").
        Library.shared.dockRight = dockOnRight
        Library.shared.dockFollowsHand = false
        if dockOpen { scheduleDockTuck() }
    }

    /// The dock tucks itself away soon after its last use.
    func scheduleDockTuck() {
        dockTimer?.cancel()
        dockTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { self?.dockOpen = false }
        }
    }

    /// The floating bubble shows only the address (while scrolling down).
    var barCompact = false
    /// Linked panes: links tapped in this pane open in the other one.
    var linkSource: Int?
    /// The Duo stands half folded, like a small laptop.
    var inLaptopPosture = false
    /// Two sites often open together, offered as a pair.
    var pairSuggestion: String?

    enum SheetKind: String, Identifiable {
        case tabs, library, pairs, settings, savePair, reader, following, whatsNew, tutorial
        var id: String { rawValue }
    }

    private init() {
        if let shot = ShotMode.current {
            ShotMode.configure(self, shot)
            return
        }
        restoreSession()
        for i in panes.indices where panes[i].tabs.isEmpty { panes[i].tabs = [makeTab(in: i)] }
    }

    var activePane: Pane { panes[active] }
    var activeTab: Tab? { activePane.tab }
    var otherIndex: Int { 1 - active }

    // MARK: Tabs

    func makeTab(in pane: Int, isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, profile: UUID? = nil) -> Tab {
        // A new tab stays in the profile of the page it comes from, unless one is chosen.
        let inherited = panes.indices.contains(pane) ? panes[pane].tab?.profile : nil
        let tab = Tab(isPrivate: isPrivate, configuration: configuration, profile: profile ?? inherited)
        wire(tab)
        return tab
    }

    private func wire(_ tab: Tab) {
        tab.onActivate = { [weak self, weak tab] in
            guard let self, let tab, let i = self.paneIndex(of: tab), i != self.active else { return }
            withAnimation(.easeOut(duration: 0.15)) { self.active = i }
        }
        tab.onMediaStopped = { [weak self, weak tab] in
            guard let self, let tab else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard let i = self.paneIndex(of: tab), let other = self.panes[1 - i].tab, self.isSplit,
                      other.mediaPlaying, abs(other.startedAt.timeIntervalSince(tab.stoppedAt)) < 1.0 else { return }
                // The other pane's video took the sound: this one keeps playing, muted.
                tab.resumeMuted()
            }
        }
        tab.onRouteLink = { [weak self, weak tab] url in
            guard let self, let tab else { return false }
            return self.routeLink(from: tab, to: url)
        }
        tab.onTouch = { [weak self, weak tab] x in
            guard let self else { return }
            self.touched(atFraction: x, pane: tab.flatMap { self.paneIndex(of: $0) })
        }
        tab.onTrigger = { [weak self] trigger in
            guard let self else { return }
            self.perform(Library.shared.action(for: trigger))
        }
        tab.onOpen = { [weak self, weak tab] url, configuration, target in
            guard let self, let tab, let i = self.paneIndex(of: tab) else { return nil }
            switch target {
            case .newTab:
                let new = self.makeTab(in: i, isPrivate: tab.isPrivate, configuration: configuration)
                self.insert(new, in: i)
                if configuration == nil, let url { new.load(url) }
                return new.webView
            case .otherPane:
                guard let url else { return nil }
                let other = 1 - i
                let new = self.makeTab(in: other, isPrivate: tab.isPrivate)
                self.insert(new, in: other)
                new.load(url)
                if !self.isSplit { withAnimation { self.isSplit = true } }
                return nil
            }
        }
    }

    func paneIndex(of tab: Tab) -> Int? {
        panes.firstIndex { $0.tabs.contains { $0 === tab } }
    }

    private func insert(_ tab: Tab, in pane: Int) {
        let p = panes[pane]
        let at = min(p.current + 1, p.tabs.count)
        p.tabs.insert(tab, at: at)
        p.current = at
        active = pane
    }

    func newTab(isPrivate: Bool = false, in pane: Int? = nil, focus: Bool = true, profile: UUID? = nil) {
        let i = pane ?? active
        insert(makeTab(in: i, isPrivate: isPrivate, profile: profile), in: i)
        if focus { editingAddress = true }
    }

    func select(_ tab: Tab) {
        guard let i = paneIndex(of: tab), let t = panes[i].tabs.firstIndex(where: { $0 === tab }) else { return }
        panes[i].current = t
        active = i
    }

    func close(_ tab: Tab) {
        guard let i = paneIndex(of: tab), let t = panes[i].tabs.firstIndex(where: { $0 === tab }) else { return }
        let p = panes[i]
        tab.close()
        p.tabs.remove(at: t)
        if p.tabs.isEmpty { p.tabs = [makeTab(in: i)] }
        p.current = min(t >= p.current ? p.current : p.current - 1, p.tabs.count - 1)
        p.current = max(0, p.current)
    }

    func closeOthers(in pane: Int) {
        let p = panes[pane]
        guard let keep = p.tab else { return }
        for t in p.tabs where t !== keep { t.close() }
        p.tabs = [keep]
        p.current = 0
    }

    func moveToOtherPane(_ tab: Tab) {
        guard let i = paneIndex(of: tab), let t = panes[i].tabs.firstIndex(where: { $0 === tab }) else { return }
        let from = panes[i]
        from.tabs.remove(at: t)
        if from.tabs.isEmpty { from.tabs = [makeTab(in: i)] }
        from.current = min(from.current, from.tabs.count - 1)
        let to = panes[1 - i]
        to.tabs.append(tab)
        to.current = to.tabs.count - 1
        active = 1 - i
        if !isSplit { isSplit = true }
    }

    // MARK: Loading

    /// What the person typed: an address, or words to search for.
    func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.url(from: trimmed, engine: Library.shared.searchEngine) else { return }
        if activeTab == nil { newTab(focus: false) }
        activeTab?.displayHost = nil
        activeTab?.load(url)
    }

    static func url(from text: String, engine: SearchEngine) -> URL? {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"), let u = URL(string: text) { return u }
        let looksLikeHost = !text.contains(" ") && text.contains(".") && !text.hasSuffix(".")
            && text.range(of: #"^[^\s/]+\.[a-zA-Z]{2,}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil
        if looksLikeHost || lower.hasPrefix("localhost"), let u = URL(string: "https://" + text) { return u }
        return engine.url(for: text)
    }

    func load(_ url: URL, inPane pane: Int? = nil) {
        let i = pane ?? active
        if panes[i].tab == nil { panes[i].tabs = [makeTab(in: i)] }
        panes[i].tab?.displayHost = nil
        panes[i].tab?.load(url)
        active = i
    }

    /// A link from another app (or, once Twinfold is the default browser, any link).
    func handleIncoming(_ url: URL) {
        var target = url
        if url.scheme == "twinfold" {
            // twinfold://open?url=… opens that page; twinfold://https://… also works.
            let s = url.absoluteString.dropFirst("twinfold://".count)
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let q = comps.queryItems?.first(where: { $0.name == "url" })?.value, let u = URL(string: q) {
                target = u
            } else if let u = URL(string: String(s)), u.scheme == "http" || u.scheme == "https" {
                target = u
            } else {
                return
            }
        }
        guard target.scheme == "http" || target.scheme == "https" else { return }
        if Library.shared.linksFromAppsInNewTab, let tab = activeTab, !tab.isBlank {
            newTab(focus: false)
        }
        load(target)
    }

    // MARK: Layout

    func toggleSplit() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isSplit.toggle() }
    }

    func swap() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            panes.swapAt(0, 1)
            active = 1 - active
            if let s = linkSource { linkSource = 1 - s }
            ratio = 1 - ratio
        }
    }

    // MARK: Pairs

    var canSavePair: Bool {
        panes[0].tab?.savedURL != nil && panes[1].tab?.savedURL != nil
    }

    func makePair(named name: String) -> Pair? {
        guard let a = panes[0].tab?.savedURL, let b = panes[1].tab?.savedURL else { return nil }
        return Pair(name: name, first: a, second: b, ratio: ratio)
    }

    func suggestedPairName() -> String {
        let a = panes[0].tab?.displayAddress ?? ""
        let b = panes[1].tab?.displayAddress ?? ""
        return [a, b].filter { !$0.isEmpty }.joined(separator: " + ")
    }

    func open(_ pair: Pair) {
        for (i, url) in [pair.first, pair.second].enumerated() {
            if let tab = panes[i].tab, tab.isBlank || tab.url == url {
                tab.load(url)
            } else {
                let new = makeTab(in: i)
                insert(new, in: i)
                new.load(url)
            }
        }
        ratio = pair.ratio
        active = 0
        withAnimation { isSplit = true }
    }

    // MARK: Session

    func saveSession() {
        guard ShotMode.current == nil else { return }
        let states = panes.map { p -> SavedSession.PaneState in
            let saved = p.tabs.filter { !$0.isPrivate && $0.savedURL != nil }
            let urls = saved.compactMap(\.savedURL)
            let cur = p.tab.flatMap { t in saved.firstIndex { $0 === t } } ?? max(0, urls.count - 1)
            return .init(urls: urls, current: cur)
        }
        Library.shared.save(SavedSession(panes: states, innerSplit: innerSplit, outerSplit: outerSplit, ratio: ratio, active: active), "session")
    }

    private func restoreSession() {
        guard let s = Library.shared.loadSession() else { return }
        innerSplit = s.innerSplit
        outerSplit = s.outerSplit
        ratio = min(max(s.ratio, 0.2), 0.8)
        for (i, state) in s.panes.prefix(2).enumerated() {
            panes[i].tabs = state.urls.map { url in
                let t = makeTab(in: i)
                t.pendingURL = url
                return t
            }
            panes[i].current = min(max(state.current, 0), max(0, state.urls.count - 1))
        }
        active = min(max(s.active, 0), 1)
    }

    func flash(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { if self.toast == message { self.toast = nil } }
        }
    }

    /// One pane's sound at a time (iOS plays only one video with sound): turning a pane's sound on mutes the other.
    func toggleMute(_ tab: Tab) {
        if tab.isMuted, let i = paneIndex(of: tab), let other = panes[1 - i].tab, other.mediaPlaying, !other.isMuted {
            other.setMuted(true)
        }
        tab.toggleMute()
    }

    /// The other pane becomes a notebook timed to the video in this one.
    func openVideoNotes() {
        let video = active
        withAnimation(.spring(response: 0.35)) {
            panes[1 - video].tool = .videoNotes
            if !isSplit { isSplit = true }
        }
    }

    func closeTool(in pane: Int) {
        withAnimation(.spring(response: 0.3)) { panes[pane].tool = nil }
    }
}
