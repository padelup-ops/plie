// WebHost.swift — Twinfold
//
// Puts a tab's web view on screen. The web view belongs to the tab, so switching tabs or panes never reloads a page.

import SwiftUI
import WebKit

struct WebHost: UIViewRepresentable {
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

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.clipsToBounds = true
        v.layer.cornerCurve = .continuous
        v.layer.cornerRadius = cornerRadius
        v.frozenSize = frozenSize
        v.show(tab.webView)
        tab.webView.scrollView.contentInset.top = topInset
        tab.webView.scrollView.contentOffset.y = -topInset
        tab.loadPendingIfNeeded()
        return v
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.show(tab.webView)
        view.layer.cornerRadius = cornerRadius
        if view.frozenSize != frozenSize { view.frozenSize = frozenSize; view.setNeedsLayout() }
        let sv = tab.webView.scrollView
        if sv.contentInset.top != topInset {
            let atTop = sv.contentOffset.y <= -sv.contentInset.top + 1
            sv.contentInset.top = topInset
            sv.verticalScrollIndicatorInsets.top = topInset
            if atTop { sv.contentOffset.y = -topInset }
        }
        tab.loadPendingIfNeeded()
    }

    final class HostView: UIView {
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
}
