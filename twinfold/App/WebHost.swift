// WebHost.swift — Twinfold
//
// Puts a tab's web view on screen. The web view belongs to the tab, so switching tabs or panes never reloads a page.
// Full screen fills this page by default (the other page stays up). Whole Display, in Settings, presents from the
// window instead, covering both pages and both screens of an iPhone Duo.

import SwiftUI
import WebKit

struct WebHost: UIViewControllerRepresentable {
    let tab: Tab
    /// The status band above the page when the pane touches the top of an iPhone or iPad screen: the page starts
    /// below it (its own colour fills the band). Sides and bottom always run edge to edge.
    var topInset: CGFloat = 0
    /// Rounded corners, drawn by the layer itself (a SwiftUI clip over a web view costs a whole extra render pass
    /// every frame).
    var cornerRadius: CGFloat = 0
    /// While the handle is dragged: the size the page keeps (it is only cut, not laid out again, so it follows the
    /// finger smoothly; it takes its new size once, when the handle is let go).
    var frozenSize: CGSize?

    func makeUIViewController(context: Context) -> WebPaneController {
        let vc = WebPaneController()
        vc.attach(webView: tab.webView, topInset: topInset, cornerRadius: cornerRadius, frozenSize: frozenSize)
        tab.loadPendingIfNeeded()
        return vc
    }

    func updateUIViewController(_ vc: WebPaneController, context: Context) {
        vc.attach(webView: tab.webView, topInset: topInset, cornerRadius: cornerRadius, frozenSize: frozenSize)
        tab.loadPendingIfNeeded()
    }
}

/// The view controller nearest the web view. WebKit asks this controller to present element full screen; we hand
/// that presentation to the window's root so the video isn't clipped to the pane.
final class WebPaneController: UIViewController {
    let host = WebPaneHost()
    private var web: WKWebView?
    private var topInset: CGFloat = 0
    private var corner: CGFloat = 0
    private var forwarding = false

    /// Presentations that ask to cover only the current context stay inside this page, not the whole window.
    override var definesPresentationContext: Bool {
        get { true }
        set { }
    }

    func attach(webView: WKWebView, topInset: CGFloat, cornerRadius: CGFloat, frozenSize: CGSize?) {
        web = webView
        self.topInset = topInset
        corner = cornerRadius
        host.frozenSize = frozenSize
        host.layer.cornerRadius = cornerRadius
        host.setNeedsLayout()
        guard isViewLoaded else { return }
        view.layer.cornerRadius = cornerRadius
        host.show(webView)
        applyInset()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = corner
        host.clipsToBounds = true
        host.layer.cornerCurve = .continuous
        host.layer.cornerRadius = corner
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.frame = view.bounds
        view.addSubview(host)
        if let web { host.show(web); applyInset() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        host.frame = view.bounds
        view.layer.cornerRadius = corner
    }

    /// Alerts stay where they are. Page-only full screen is kept inside this page. Whole Display covers the window.
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if forwarding || viewControllerToPresent is UIAlertController || !FullscreenBridge.wantsWindow(viewControllerToPresent) {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
            return
        }
        if Library.shared.fullscreenPage {
            viewControllerToPresent.modalPresentationStyle = .overCurrentContext
            viewControllerToPresent.modalPresentationCapturesStatusBarAppearance = false
            super.present(viewControllerToPresent, animated: flag) { [weak self] in
                self?.keepFullscreenInsidePane(viewControllerToPresent)
                if let web = self?.web { Browser.shared.setFullscreen(true, webView: web) }
                completion?()
            }
            return
        }
        guard let top = FullscreenBridge.topPresenter(), top !== self else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
            return
        }
        viewControllerToPresent.modalPresentationStyle = .overFullScreen
        viewControllerToPresent.modalPresentationCapturesStatusBarAppearance = true
        forwarding = true
        top.present(viewControllerToPresent, animated: flag) { [weak self] in
            self?.forwarding = false
            FullscreenBridge.expandToWindow(viewControllerToPresent)
            completion?()
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        let fullscreen = presentedViewController.map(FullscreenBridge.wantsWindow) ?? false
        let web = web
        super.dismiss(animated: flag) {
            if fullscreen, let web { Browser.shared.setFullscreen(false, webView: web) }
            completion?()
        }
    }

    /// If WebKit still built a full-screen view, pin it to this page so the other page stays visible and usable.
    private func keepFullscreenInsidePane(_ vc: UIViewController) {
        vc.view.translatesAutoresizingMaskIntoConstraints = true
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if vc.view.superview !== view {
            vc.view.removeFromSuperview()
            view.addSubview(vc.view)
        }
        vc.view.frame = view.bounds
        view.clipsToBounds = true
    }

    private func applyInset() {
        guard let web else { return }
        let sv = web.scrollView
        if sv.contentInset.top != topInset {
            let atTop = sv.contentOffset.y <= -sv.contentInset.top + 1
            sv.contentInset.top = topInset
            sv.verticalScrollIndicatorInsets.top = topInset
            if atTop { sv.contentOffset.y = -topInset }
        }
    }
}

/// Hosts the web view and keeps its size frozen while the pane divider moves.
final class WebPaneHost: UIView {
    var frozenSize: CGSize?

    func show(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = []
        addSubview(webView)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let web = subviews.first else { return }
        backgroundColor = (web as? WKWebView)?.underPageBackgroundColor ?? .systemBackground
        let size = frozenSize ?? bounds.size
        let target = CGRect(origin: .zero, size: size)
        if web.frame != target { web.frame = target }
    }
}

/// Makes a full-screen video cover the window (both Duo screens), even when WebKit builds it inside the pane.
enum FullscreenBridge {
    static func start() {
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? UIWindow else { return }
                let name = NSStringFromClass(type(of: window))
                let root = window.rootViewController.map { NSStringFromClass(type(of: $0)) } ?? ""
                guard !Library.shared.fullscreenPage else { return }
                guard name.contains("FullScreen") || name.contains("Fullscreen")
                        || root.contains("FullScreen") || root.contains("Fullscreen")
                        || root.contains("AVPlayer") else { return }
                expand(window)
            }
        }
    }

    static func wantsWindow(_ vc: UIViewController) -> Bool {
        let name = NSStringFromClass(type(of: vc))
        if name.contains("FullScreen") || name.contains("Fullscreen") || name.contains("AVPlayer") || name.contains("AVFull") {
            return true
        }
        let style = vc.modalPresentationStyle
        let styled = style == .fullScreen || style == .overFullScreen || style == .custom
        return styled && (name.contains("WK") || name.contains("WebKit"))
    }

    static func topPresenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return nil }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// If WebKit inserted its full-screen container inside the web view, move it onto the window.
    static func adopt(_ view: UIView) {
        guard !Library.shared.fullscreenPage else { return }
        guard let scene = view.window?.windowScene
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow ?? scene.windows.first else { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.frame = window.bounds
        window.addSubview(view)
    }

    static func expandToWindow(_ vc: UIViewController) {
        DispatchQueue.main.async {
            guard let window = vc.view.window else { return }
            let bounds = window.bounds
            if vc.view.bounds.width < bounds.width * 0.92 || vc.view.bounds.height < bounds.height * 0.92 {
                vc.view.frame = bounds
                vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }
    }

    private static func expand(_ window: UIWindow) {
        guard let scene = window.windowScene else { return }
        let bounds = scene.coordinateSpace.bounds
        if window.frame != bounds { window.frame = bounds }
        let above = UIWindow.Level.normal.rawValue + 1
        if window.windowLevel.rawValue < above {
            window.windowLevel = UIWindow.Level(rawValue: above)
        }
    }
}
