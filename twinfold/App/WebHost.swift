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

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.show(tab.webView)
        tab.webView.scrollView.contentInset.top = topInset
        tab.webView.scrollView.contentOffset.y = -topInset
        tab.loadPendingIfNeeded()
        return v
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.show(tab.webView)
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
        func show(_ webView: WKWebView) {
            guard webView.superview !== self else { return }
            subviews.forEach { $0.removeFromSuperview() }
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
}
