// Gestures.swift — Twinfold
//
// Gestures the person sets up: each trigger (two-finger swipes and taps, swipes from the bottom corners) runs the
// action chosen in Settings. Also: scrolling the two pages together, one pane over the whole screen for a while,
// and switching the page between a normal and a private tab.

import SwiftUI
import UIKit

enum GestureTrigger: String, CaseIterable, Identifiable, Codable {
    case swipeLeft, swipeRight, swipeUp, swipeDown, twoFingerTap, twoFingerDoubleTap, threeFingerTap
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .swipeLeft: return "Two Fingers Left"
        case .swipeRight: return "Two Fingers Right"
        case .swipeUp: return "Two Fingers Up"
        case .swipeDown: return "Two Fingers Down"
        case .twoFingerTap: return "Two-Finger Tap"
        case .twoFingerDoubleTap: return "Two-Finger Double Tap"
        case .threeFingerTap: return "Three-Finger Tap"
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
        }
    }
}

enum BrowserAction: String, CaseIterable, Identifiable, Codable {
    case none, back, forward, reload, newTab, newPrivateTab, togglePrivate, closeTab
    case toggleSplit, toggleAxis, swapPanes, syncScroll, maximize, reader, scrollToTop, hideBar
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
            syncScroll.toggle()
            flash(syncScroll ? String(localized: "Scrolling together") : String(localized: "Scrolling separately"))
        case .maximize: toggleMaximize()
        case .reader: sheet = .reader
        case .scrollToTop: tab?.webView.scrollView.setContentOffset(CGPoint(x: 0, y: -(tab?.webView.scrollView.adjustedContentInset.top ?? 0)), animated: true)
        case .hideBar: hideBar(for: 20)
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
    var currentlySideBySide: Bool {
        switch axis {
        case .stacked: return false
        case .sideBySide: return true
        case .auto:
            let size = UIScreen.main.bounds.size
            return size.width > size.height
        }
    }
}

// MARK: - Recognizers on each page

@MainActor
final class GestureHost: NSObject, UIGestureRecognizerDelegate {
    weak var tab: Tab?
    var run: ((GestureTrigger) -> Void)?

    init(webView: UIView) {
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
    }

    @objc private func fire(_ g: UIGestureRecognizer) {
        guard let t = (g as? TriggerSwipe)?.trigger ?? (g as? TriggerTap)?.trigger else { return }
        run?(t)
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard Library.shared.twoFingerGestures else { return false }
            let trigger = (g as? TriggerSwipe)?.trigger ?? (g as? TriggerTap)?.trigger
            return trigger.map { Library.shared.action(for: $0) != .none } ?? false
        }
    }
}

final class TriggerSwipe: UISwipeGestureRecognizer { var trigger: GestureTrigger = .swipeLeft }
final class TriggerTap: UITapGestureRecognizer { var trigger: GestureTrigger = .twoFingerTap }

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

    private func scrolled(_ tab: Tab, _ sv: UIScrollView) {
        let browser = Browser.shared
        guard browser.syncScroll, browser.isSplit, browser.maximized == nil, !applying,
              sv.isTracking || sv.isDragging || sv.isDecelerating,
              let i = browser.paneIndex(of: tab), browser.panes[i].tab === tab,
              let other = browser.panes[1 - i].tab?.webView.scrollView else { return }
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
    @State private var revision = 0

    var body: some View {
        let lib = Library.shared
        Form {
            Section {
                @Bindable var lib = lib
                Toggle("Gestures On", isOn: $lib.twoFingerGestures)
            } footer: {
                Text("Swipe or tap with two fingers anywhere on a page. Each gesture does what you choose below.")
            }
            Section {
                ForEach(GestureTrigger.allCases) { trigger in
                    Picker(selection: Binding(get: { _ = lib.gestureRevision; return lib.action(for: trigger) },
                                              set: { lib.setAction($0, for: trigger) })) {
                        ForEach(BrowserAction.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label(trigger.title, systemImage: trigger.symbol)
                    }
                }
            }
            .disabled(!lib.twoFingerGestures)
            Section {
                Button("Restore the Usual Gestures") {
                    for t in GestureTrigger.allCases { lib.setAction(t.defaultAction, for: t) }
                }
            }
        }
        .navigationTitle("Gestures")
    }
}
