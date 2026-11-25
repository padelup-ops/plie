// Gestures.swift — Twinfold
//
// Gestures the person sets up: each trigger (two-finger swipes and taps, swipes from the bottom corners) runs the
// action chosen in Settings. Also: scrolling the two pages together, one pane over the whole screen for a while,
// and switching the page between a normal and a private tab.

import SwiftUI
import UIKit
import WebKit

enum GestureTrigger: String, CaseIterable, Identifiable, Codable {
    case swipeLeft, swipeRight, swipeUp, swipeDown, twoFingerTap, twoFingerDoubleTap, threeFingerTap
    case edgeLeft, edgeRight, edgeTop, edgeBottom
    case downRight, downLeft, upRight, upLeft, rightDown, rightUp, leftDown, leftUp
    var id: String { rawValue }

    static var twoFingers: [GestureTrigger] { [.swipeLeft, .swipeRight, .swipeUp, .swipeDown, .twoFingerTap, .twoFingerDoubleTap, .threeFingerTap] }
    static var edges: [GestureTrigger] { [.edgeLeft, .edgeRight, .edgeTop, .edgeBottom] }
    static var combos: [GestureTrigger] { [.downRight, .downLeft, .upRight, .upLeft, .rightDown, .rightUp, .leftDown, .leftUp] }

    var title: LocalizedStringKey {
        switch self {
        case .swipeLeft: return "Two Fingers Left"
        case .swipeRight: return "Two Fingers Right"
        case .swipeUp: return "Two Fingers Up"
        case .swipeDown: return "Two Fingers Down"
        case .twoFingerTap: return "Two-Finger Tap"
        case .twoFingerDoubleTap: return "Two-Finger Double Tap"
        case .threeFingerTap: return "Three-Finger Tap"
        case .edgeLeft: return "Swipe from the Left Edge"
        case .edgeRight: return "Swipe from the Right Edge"
        case .edgeTop: return "Swipe from the Top Edge"
        case .edgeBottom: return "Swipe from the Bottom Edge"
        case .downRight: return "Down, then Right"
        case .downLeft: return "Down, then Left"
        case .upRight: return "Up, then Right"
        case .upLeft: return "Up, then Left"
        case .rightDown: return "Right, then Down"
        case .rightUp: return "Right, then Up"
        case .leftDown: return "Left, then Down"
        case .leftUp: return "Left, then Up"
        }
    }

    var symbol: String {
        switch self {
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .twoFingerTap: return "hand.tap"
        case .twoFingerDoubleTap: return "hand.tap.fill"
        case .threeFingerTap: return "hand.raised"
        case .edgeLeft: return "arrow.left.to.line"
        case .edgeRight: return "arrow.right.to.line"
        case .edgeTop: return "arrow.up.to.line"
        case .edgeBottom: return "arrow.down.to.line"
        case .downRight: return "arrow.down.right"
        case .downLeft: return "arrow.down.left"
        case .upRight: return "arrow.up.right"
        case .upLeft: return "arrow.up.left"
        case .rightDown: return "arrow.turn.down.right"
        case .rightUp: return "arrow.turn.up.right"
        case .leftDown: return "arrow.turn.down.left"
        case .leftUp: return "arrow.turn.up.left"
        }
    }

    var defaultAction: BrowserAction {
        switch self {
        case .swipeLeft: return .back
        case .swipeRight: return .forward
        case .swipeUp: return .newTab
        case .swipeDown: return .toggleSplit
        case .twoFingerTap: return .none
        case .twoFingerDoubleTap: return .maximize
        case .threeFingerTap: return .none
        case .edgeLeft, .edgeRight, .edgeTop, .edgeBottom: return .none
        case .downRight: return .swapPanes
        case .downLeft: return .none
        case .upRight: return .newTab
        case .upLeft: return .openPalette
        case .rightDown: return .toggleSplit
        case .rightUp: return .forward
        case .leftDown: return .back
        case .leftUp: return .reload
        }
    }
}

enum BrowserAction: String, CaseIterable, Identifiable, Codable {
    case none, back, forward, reload, newTab, newPrivateTab, togglePrivate, closeTab
    case toggleSplit, toggleAxis, swapPanes, syncScroll, maximize, reader, scrollToTop, hideBar, openPalette
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .none: return "Nothing"
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .newTab: return "New Tab"
        case .newPrivateTab: return "New Private Tab"
        case .togglePrivate: return "Normal ⇄ Private"
        case .closeTab: return "Close Tab"
        case .toggleSplit: return "One or Two Pages"
        case .toggleAxis: return "Top and Bottom ⇄ Side by Side"
        case .swapPanes: return "Swap Panes"
        case .syncScroll: return "Scroll Together On or Off"
        case .maximize: return "This Page Full Screen"
        case .reader: return "Reader View"
        case .scrollToTop: return "Scroll to Top"
        case .hideBar: return "Hide the Bar for a While"
        case .openPalette: return "Open the Action Palette"
        }
    }
}

@MainActor
extension Library {
    func action(for trigger: GestureTrigger) -> BrowserAction {
        BrowserAction(rawValue: UserDefaults.standard.string(forKey: "gesture." + trigger.rawValue) ?? "") ?? trigger.defaultAction
    }

    func setAction(_ action: BrowserAction, for trigger: GestureTrigger) {
        UserDefaults.standard.set(action.rawValue, forKey: "gesture." + trigger.rawValue)
        gestureRevision += 1
        for pane in Browser.shared.panes {
            for tab in pane.tabs { tab.refreshGestures() }
        }
    }
}

extension Browser {
    func perform(_ action: BrowserAction) {
        let tab = activeTab
        switch action {
        case .none: break
        case .back: if tab?.canGoBack == true { tab?.webView.goBack() }
        case .forward: if tab?.canGoForward == true { tab?.webView.goForward() }
        case .reload: tab?.webView.reload()
        case .newTab: newTab()
        case .newPrivateTab: newTab(isPrivate: true)
        case .togglePrivate: togglePrivate()
        case .closeTab: if let tab { close(tab) }
        case .toggleSplit: toggleSplit()
        case .toggleAxis: setAxis(currentlySideBySide ? .stacked : .sideBySide)
        case .swapPanes: swap()
        case .syncScroll:
            guard syncScroll || Store.shared.isPro else { Store.shared.gate(.syncScroll) {}; return }
            syncScroll.toggle()
            flash(syncScroll ? String(localized: "Scrolling together") : String(localized: "Scrolling separately"))
        case .maximize: toggleMaximize()
        case .reader: sheet = .reader
        case .scrollToTop: tab?.webView.scrollView.setContentOffset(CGPoint(x: 0, y: -(tab?.webView.scrollView.adjustedContentInset.top ?? 0)), animated: true)
        case .hideBar: hideBar(for: 20)
        case .openPalette:
            Library.shared.palette = true
            // The palette view appears on the next turn; the request opens it once it is on screen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self.paletteOpenRequest &+= 1
            }
        }
    }

    /// The page moves between a normal tab and a private tab (same address, same pane).
    func togglePrivate() {
        guard let tab = activeTab, let i = paneIndex(of: tab) else { return }
        let new = makeTab(in: i, isPrivate: !tab.isPrivate)
        let p = panes[i]
        if let t = p.tabs.firstIndex(where: { $0 === tab }) {
            if let url = tab.url, !tab.isBlank { new.load(url) }
            p.tabs.insert(new, at: t + 1)
            p.current = t + 1
            // A private page left behind is closed; a normal one stays in the tab list.
            if tab.isPrivate {
                tab.close()
                p.tabs.remove(at: t)
                p.current = t
            }
        }
        flash(new.isPrivate ? String(localized: "Private tab") : String(localized: "Normal tab"))
    }

    func toggleMaximize() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            maximized = maximized == nil ? active : nil
        }
    }

    func hideBar(for seconds: Int) {
        withAnimation { barHiddenUntil = Date().addingTimeInterval(TimeInterval(seconds)) }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation { if let until = self.barHiddenUntil, until <= Date() { self.barHiddenUntil = nil } }
        }
    }

    var barHidden: Bool { barHiddenUntil.map { $0 > Date() } ?? false }

    /// Whether the panes are side by side right now (for the icons and the layout toggle).
    var currentlySideBySide: Bool { layoutSideBySide }
}

// MARK: - Recognizers on each page

@MainActor
final class GestureHost: NSObject, UIGestureRecognizerDelegate {
    weak var tab: Tab?
    var run: ((GestureTrigger) -> Void)?
    private weak var webView: WKWebView?
    private var stroke: [CGPoint] = []
    private var strokeStart = Date()

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        for (dir, trigger) in [(UISwipeGestureRecognizer.Direction.left, GestureTrigger.swipeLeft), (.right, .swipeRight),
                               (.up, .swipeUp), (.down, .swipeDown)] {
            let g = TriggerSwipe(target: self, action: #selector(fire(_:)))
            g.direction = dir
            g.numberOfTouchesRequired = 2
            g.trigger = trigger
            g.delegate = self
            webView.addGestureRecognizer(g)
        }
        let double = TriggerTap(target: self, action: #selector(fire(_:)))
        double.numberOfTouchesRequired = 2
        double.numberOfTapsRequired = 2
        double.trigger = .twoFingerDoubleTap
        double.delegate = self
        webView.addGestureRecognizer(double)
        let single = TriggerTap(target: self, action: #selector(fire(_:)))
        single.numberOfTouchesRequired = 2
        single.trigger = .twoFingerTap
        single.delegate = self
        single.require(toFail: double)
        webView.addGestureRecognizer(single)
        let three = TriggerTap(target: self, action: #selector(fire(_:)))
        three.numberOfTouchesRequired = 3
        three.trigger = .threeFingerTap
        three.delegate = self
        webView.addGestureRecognizer(three)

        for trigger in GestureTrigger.edges {
            let g = EdgeMark(target: self, action: #selector(edge(_:)))
            g.trigger = trigger
            g.maximumNumberOfTouches = 1
            g.cancelsTouchesInView = false
            g.delegate = self
            webView.addGestureRecognizer(g)
        }
        let combo = ComboPan(target: self, action: #selector(combo(_:)))
        combo.maximumNumberOfTouches = 1
        combo.cancelsTouchesInView = false
        combo.delegate = self
        webView.addGestureRecognizer(combo)
        refreshSystemEdges()
    }

    /// The system's back and forward edge swipes stay until a page edge is given its own action.
    func refreshSystemEdges() {
        let lib = Library.shared
        let custom = lib.twoFingerGestures && (lib.action(for: .edgeLeft) != .none || lib.action(for: .edgeRight) != .none)
        webView?.allowsBackForwardNavigationGestures = !custom
    }

    @objc private func fire(_ g: UIGestureRecognizer) {
        guard let t = (g as? TriggerSwipe)?.trigger ?? (g as? TriggerTap)?.trigger else { return }
        run?(t)
    }

    @objc private func edge(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended, let t = (g as? EdgeMark)?.trigger else { return }
        let tr = g.translation(in: g.view)
        let distance: CGFloat = 56
        let ok: Bool
        switch t {
        case .edgeLeft: ok = tr.x > distance && abs(tr.x) > abs(tr.y)
        case .edgeRight: ok = tr.x < -distance && abs(tr.x) > abs(tr.y)
        case .edgeTop: ok = tr.y > distance && abs(tr.y) > abs(tr.x)
        case .edgeBottom: ok = tr.y < -distance && abs(tr.y) > abs(tr.x)
        default: ok = false
        }
        if ok { run?(t) }
    }

    @objc private func combo(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stroke = [g.location(in: g.view)]
            strokeStart = Date()
        case .changed:
            stroke.append(g.location(in: g.view))
        case .ended:
            let pts = stroke
            let dt = Date().timeIntervalSince(strokeStart)
            stroke = []
            if let t = ComboStroke.match(pts, duration: dt, in: g.view?.bounds ?? .zero) { run?(t) }
        default:
            stroke = []
        }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard Library.shared.twoFingerGestures else { return false }
            if let edge = g as? EdgeMark {
                refreshSystemEdges()
                guard Library.shared.action(for: edge.trigger) != .none else { return false }
                let p = edge.location(in: edge.view)
                let b = edge.view?.bounds ?? .zero
                let m: CGFloat = 32
                switch edge.trigger {
                case .edgeLeft: return p.x <= m
                case .edgeRight: return b.width - p.x <= m
                case .edgeTop: return p.y <= m
                case .edgeBottom: return b.height - p.y <= m
                default: return false
                }
            }
            if g is ComboPan {
                return GestureTrigger.combos.contains { Library.shared.action(for: $0) != .none }
            }
            let trigger = (g as? TriggerSwipe)?.trigger ?? (g as? TriggerTap)?.trigger
            return trigger.map { Library.shared.action(for: $0) != .none } ?? false
        }
    }
}

final class TriggerSwipe: UISwipeGestureRecognizer { var trigger: GestureTrigger = .swipeLeft }
final class TriggerTap: UITapGestureRecognizer { var trigger: GestureTrigger = .twoFingerTap }
final class EdgeMark: UIPanGestureRecognizer { var trigger: GestureTrigger = .edgeLeft }
final class ComboPan: UIPanGestureRecognizer {}

/// A corner drawn with one finger (down, then right). A straight scroll never matches.
enum ComboStroke {
    private enum Dir { case left, right, up, down }

    static func match(_ points: [CGPoint], duration: TimeInterval, in bounds: CGRect) -> GestureTrigger? {
        guard points.count >= 4, duration > 0.05, duration < 0.95, bounds.width > 1 else { return nil }
        let start = points[0]
        let margin: CGFloat = 36
        if start.x < margin || start.y < margin || bounds.width - start.x < margin || bounds.height - start.y < margin {
            return nil
        }
        let end = points[points.count - 1]
        var best = (index: 0, score: CGFloat(0))
        for i in 1..<(points.count - 1) {
            let v1 = CGPoint(x: points[i].x - start.x, y: points[i].y - start.y)
            let v2 = CGPoint(x: end.x - points[i].x, y: end.y - points[i].y)
            let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
            guard l1 > 64, l2 > 64 else { continue }
            let dot = (v1.x * v2.x + v1.y * v2.y) / (l1 * l2)
            guard abs(dot) < 0.45 else { continue }
            let score = l1 + l2
            if score > best.score { best = (i, score) }
        }
        guard best.score > 0 else { return nil }
        let corner = points[best.index]
        guard let d1 = direction(from: start, to: corner), let d2 = direction(from: corner, to: end), d1 != d2 else { return nil }
        switch (d1, d2) {
        case (.down, .right): return .downRight
        case (.down, .left): return .downLeft
        case (.up, .right): return .upRight
        case (.up, .left): return .upLeft
        case (.right, .down): return .rightDown
        case (.right, .up): return .rightUp
        case (.left, .down): return .leftDown
        case (.left, .up): return .leftUp
        default: return nil
        }
    }

    private static func direction(from a: CGPoint, to b: CGPoint) -> Dir? {
        let dx = b.x - a.x, dy = b.y - a.y
        if abs(dx) < 24 && abs(dy) < 24 { return nil }
        if abs(dx) > abs(dy) * 1.2 { return dx > 0 ? .right : .left }
        if abs(dy) > abs(dx) * 1.2 { return dy > 0 ? .down : .up }
        return nil
    }
}

// MARK: - Scrolling the two pages together

@MainActor
final class ScrollSync {
    static let shared = ScrollSync()
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var applying = false

    func watch(_ tab: Tab) {
        let sv = tab.webView.scrollView
        observations[ObjectIdentifier(sv)] = sv.observe(\.contentOffset, options: [.new]) { [weak tab] sv, _ in
            MainActor.assumeIsolated {
                guard let tab else { return }
                ScrollSync.shared.scrolled(tab, sv)
            }
        }
    }

    private var lastY: [ObjectIdentifier: CGFloat] = [:]

    private func scrolled(_ tab: Tab, _ sv: UIScrollView) {
        let browser = Browser.shared
        // The floating bubble shrinks while reading down, and comes back when scrolling up.
        let id = ObjectIdentifier(sv)
        let y = sv.contentOffset.y
        if sv.isDragging, browser.activeTab === tab, let last = lastY[id] {
            let dy = y - last
            let atTop = y <= -sv.adjustedContentInset.top + 4
            if (dy > 6 && !browser.barCompact && !atTop) || ((dy < -6 || atTop) && browser.barCompact) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { browser.barCompact = dy > 6 && !atTop }
            }
        }
        lastY[id] = y
        guard browser.syncScroll, browser.isSplit, browser.maximized == nil, !applying,
              sv.isTracking || sv.isDragging || sv.isDecelerating,
              let i = browser.paneIndex(of: tab), browser.panes[i].tab === tab,
              let other = browser.panes[1 - i].tab?.webView.scrollView else { return }
        _ = id
        // The same share of each page: halfway down here, halfway down there.
        let range = max(1, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.top + sv.adjustedContentInset.bottom)
        let f = min(1, max(0, (sv.contentOffset.y + sv.adjustedContentInset.top) / range))
        let otherRange = max(0, other.contentSize.height - other.bounds.height + other.adjustedContentInset.top + other.adjustedContentInset.bottom)
        applying = true
        other.contentOffset.y = f * otherRange - other.adjustedContentInset.top
        applying = false
    }
}

// MARK: - Settings

struct GestureSettings: View {
    var body: some View {
        let lib = Library.shared
        Form {
            Section {
                @Bindable var lib = lib
                Toggle("Gestures On", isOn: $lib.twoFingerGestures)
            } footer: {
                Text("One finger from a page's edge, a corner such as down then right, or two fingers. Each one does what you choose. A straight scroll stays a scroll. The usual back and forward swipes stay until you set that edge to something else.")
            }
            group("Edge Swipes", GestureTrigger.edges, lib: lib)
            group("Two-Direction Gestures", GestureTrigger.combos, lib: lib)
            group("Two Fingers", GestureTrigger.twoFingers, lib: lib)
            Section {
                Button("Restore the Usual Gestures") {
                    for t in GestureTrigger.allCases { lib.setAction(t.defaultAction, for: t) }
                }
            }
        }
        .navigationTitle("Gestures")
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ triggers: [GestureTrigger], lib: Library) -> some View {
        Section {
            ForEach(triggers) { trigger in
                Picker(selection: Binding(get: { _ = lib.gestureRevision; return lib.action(for: trigger) },
                                          set: { a in Store.shared.gate(.gestures) { lib.setAction(a, for: trigger) } })) {
                    ForEach(BrowserAction.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label(trigger.title, systemImage: trigger.symbol)
                }
            }
        } header: {
            Text(title)
        }
        .disabled(!lib.twoFingerGestures)
    }
}
