// Tab.swift — Twinfold
//
// One web page and its history: a WKWebView, with what the bars need to show (title, address, progress).

import Observation
import UIKit
import WebKit

@MainActor @Observable
final class Tab: NSObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    let isPrivate: Bool

    private(set) var title = ""
    private(set) var url: URL?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var hasOnlySecureContent = true
    /// Asks sites for their computer layout.
    var wantsDesktop = false
    /// A page restored from the last session, loaded only when the tab is shown.
    var pendingURL: URL?
    /// Shown in the address bar instead of the real address (sample pages for the App Store screenshots).
    var displayHost: String?

    /// The last picture of the page, for the tab overview.
    var thumbnail: UIImage?
    /// Hands-free reading speed (points per second), 0 when the page doesn't scroll by itself.
    var autoScrollSpeed: Double = 0
    /// The page's feed (RSS or Atom), when it offers one: the site can be followed.
    private(set) var feedURL: URL?
    /// Something plays in the page (sound or video), and whether it is a video.
    private(set) var mediaPlaying = false
    private(set) var mediaVideo = false
    /// The pane's sound is cut (every video and sound in the page, iframes included).
    private(set) var isMuted = false
    /// The playing video is stretched over the whole pane.
    var isFilled = false
    @ObservationIgnored private var frameMedia: [Bool: (Bool, Bool)] = [:]

    /// Set by the browser: the pane this tab belongs to became the one the bars act on.
    @ObservationIgnored var onActivate: (() -> Void)?
    /// Set by the browser: a page asked for a new window, or the person chose "Open in Other Pane".
    @ObservationIgnored var onOpen: ((URL?, WKWebViewConfiguration?, LinkTarget) -> WKWebView?)?

    enum LinkTarget { case newTab, otherPane }

    /// Set by the browser: a gesture chosen in Settings was made on this page.
    @ObservationIgnored var onTrigger: ((GestureTrigger) -> Void)?
    /// Set by the browser: where the page was touched (0 left edge … 1 right edge), for the side dock.
    @ObservationIgnored var onTouch: ((CGFloat) -> Void)?
    /// Set by the browser: a tapped link may go to the other pane (linked panes).
    @ObservationIgnored var onRouteLink: ((URL) -> Bool)?
    @ObservationIgnored private var gestures: GestureHost?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// The profile whose cookies and sign-ins this tab uses (nil: the main one).
    let profile: UUID?
    /// Asleep: the page gave its memory back; it wakes up, with its history, when shown.
    @ObservationIgnored private(set) var isAsleep = false
    @ObservationIgnored private var sleptState: Any?
    @ObservationIgnored var lastShown = Date()

    init(isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil, profile: UUID? = nil) {
        self.isPrivate = isPrivate
        self.profile = isPrivate ? nil : profile
        let config = configuration ?? Tab.makeConfiguration(isPrivate: isPrivate, profile: profile)
        webView = EdgeWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isInspectable = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Edge to edge, like the system's own full-screen apps: the page runs under the status band, the camera and
        // the home indicator instead of leaving black strips (the floating bar keeps clear of them itself).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false

        MediaRouter.shared.register(self)
        PageStyle.shared.attach(webView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        webView.addGestureRecognizer(tap)

        let host = GestureHost(webView: webView)
        host.run = { [weak self] trigger in
            self?.onActivate?()
            self?.onTrigger?(trigger)
        }
        gestures = host
        ScrollSync.shared.watch(self)

        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { if self?.isAsleep == false { self?.title = wv.title ?? "" } } },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { if self?.isAsleep == false { self?.url = wv.url ?? self?.url } } },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { self?.progress = wv.estimatedProgress } },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { self?.isLoading = wv.isLoading } },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack } },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward } },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] wv, _ in MainActor.assumeIsolated { self?.hasOnlySecureContent = wv.hasOnlySecureContent } },
        ]
    }

    static func makeConfiguration(isPrivate: Bool, profile: UUID? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : Library.dataStore(for: profile)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = ShotMode.current == "dualplay" ? [] : .all
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Full screen in the pane (the default): the page's own full-screen button fills just this pane.
        config.preferences.isElementFullscreenEnabled = !Library.shared.fullscreenInPane
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.dataDetectorTypes = [.phoneNumber, .link, .address, .calendarEvent]
        ContentBlocker.shared.attach(to: config.userContentController)
        return config
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let displayHost { return displayHost }
        return (url ?? pendingURL)?.host() ?? String(localized: "New Tab")
    }

    var displayAddress: String {
        if let displayHost { return displayHost }
        guard let url = url ?? pendingURL else { return "" }
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    var isBlank: Bool { url == nil && pendingURL == nil && displayHost == nil && !isLoading }

    /// The address to keep for the next launch.
    var savedURL: URL? { url ?? pendingURL }

    func loadPendingIfNeeded() {
        lastShown = Date()
        if isAsleep { wake(); return }
        guard let pendingURL else { return }
        self.pendingURL = nil
        load(pendingURL)
    }

    /// Gives the page's memory back, keeping its history to come back to.
    func sleep() {
        guard !isAsleep else { return }
        sleptState = webView.interactionState
        isAsleep = true
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func wake() {
        isAsleep = false
        if let s = sleptState { webView.interactionState = s } else if let url { webView.load(URLRequest(url: url)) }
        sleptState = nil
    }

    func load(_ url: URL) {
        pendingURL = nil
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func toggleDesktop() {
        wantsDesktop.toggle()
        webView.reload()
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onActivate?()
        let w = max(1, webView.bounds.width)
        onTouch?(g.location(in: webView).x / w)
    }


    // MARK: Media

    /// When this page last started playing, and when it last stopped (to tell a pause by the other pane from a
    /// pause by the person).
    @ObservationIgnored private(set) var startedAt = Date.distantPast
    @ObservationIgnored private(set) var stoppedAt = Date.distantPast
    @ObservationIgnored var onMediaStopped: (() -> Void)?

    func mediaReport(playing: Bool, video: Bool, mainFrame: Bool) {
        // The main page and its frames report separately; something plays if any of them plays.
        let was = mediaPlaying
        frameMedia[mainFrame] = (playing, video)
        let all = frameMedia.values
        mediaPlaying = all.contains { $0.0 }
        mediaVideo = all.contains { $0.1 }
        if mediaPlaying && !was { startedAt = Date() }
        if !mediaPlaying && was {
            stoppedAt = Date()
            onMediaStopped?()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        webView.evaluateJavaScript("window.__twinfold && window.__twinfold.setMuted(\(muted))")
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Plays again, muted, the video the other pane's video stopped.
    func resumeMuted() {
        isMuted = true
        webView.evaluateJavaScript("window.__twinfold ? window.__twinfold.resumeMuted() : false")
    }

    func toggleFill() {
        webView.evaluateJavaScript("window.__twinfold ? window.__twinfold.toggleFill() : false") { [weak self] result, _ in
            MainActor.assumeIsolated { self?.isFilled = (result as? Bool) ?? false }
        }
    }


    func close() {
        observations.forEach { $0.invalidate() }
        observations = []
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }
}

extension Tab: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

// MARK: - Navigation

extension Tab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = wantsDesktop ? .desktop : .mobile
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow, preferences)
            return
        }
        // Phone numbers, mail, maps and App Store links leave the browser for the app that handles them.
        if !["http", "https", "about", "file", "data", "blob", "javascript"].contains(scheme) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel, preferences)
            return
        }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame == true,
           scheme == "http" || scheme == "https", onRouteLink?(url) == true {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        feedURL = nil
        autoScrollSpeed = 0
        frameMedia = [:]
        mediaPlaying = false
        mediaVideo = false
        isFilled = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        SiteIcons.shared.learn(from: self)
        webView.evaluateJavaScript(FeedFinder.script) { [weak self] result, _ in
            MainActor.assumeIsolated {
                if let s = result as? String, let u = URL(string: s), u.scheme == "https" || u.scheme == "http" { self?.feedURL = u }
            }
        }
        if isMuted { webView.evaluateJavaScript("window.__twinfold && window.__twinfold.setMuted(true)") }
        if !isPrivate, displayHost == nil, let url = webView.url {
            Library.shared.record(title: webView.title ?? "", url: url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - Windows and the link menu

extension Tab: WKUIDelegate {
    /// A link meant for a new window (target="_blank", window.open after a tap) opens in a new tab of this pane.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        onOpen?(action.request.url, configuration, .newTab)
    }

    func webViewDidClose(_ webView: WKWebView) {
        // The page closed its own window: nothing else to do, the tab stays until the person closes it.
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void) {
        guard let link = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            let other = UIAction(title: String(localized: "Open in Other Pane"), image: UIImage(systemName: "rectangle.split.1x2")) { _ in
                MainActor.assumeIsolated { _ = self?.onOpen?(link, nil, .otherPane) }
            }
            let newTab = UIAction(title: String(localized: "Open in New Tab"), image: UIImage(systemName: "plus.square.on.square")) { _ in
                MainActor.assumeIsolated { _ = self?.onOpen?(link, nil, .newTab) }
            }
            return UIMenu(children: [UIMenu(options: .displayInline, children: [other, newTab])] + suggested)
        }
        completionHandler(config)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable () -> Void) {
        present(alert: UIAlertController(title: frame.request.url?.host(), message: message, preferredStyle: .alert),
                actions: [UIAlertAction(title: String(localized: "OK"), style: .default) { _ in completionHandler() }],
                fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        present(alert: UIAlertController(title: frame.request.url?.host(), message: message, preferredStyle: .alert),
                actions: [UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in completionHandler(false) },
                          UIAlertAction(title: String(localized: "OK"), style: .default) { _ in completionHandler(true) }],
                fallback: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = UIAlertController(title: frame.request.url?.host(), message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        present(alert: alert,
                actions: [UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in completionHandler(nil) },
                          UIAlertAction(title: String(localized: "OK"), style: .default) { [weak alert] _ in
                              completionHandler(alert?.textFields?.first?.text) }],
                fallback: { completionHandler(nil) })
    }

    private func present(alert: UIAlertController, actions: [UIAlertAction], fallback: @escaping @MainActor () -> Void) {
        actions.forEach(alert.addAction)
        guard let top = Self.topController() else {
            fallback()
            return
        }
        top.present(alert, animated: true)
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}


/// A web view that ignores the screen's safe area: the page fills its whole pane, on every screen of the Duo.
final class EdgeWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}
