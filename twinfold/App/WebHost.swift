// WebHost.swift — Twinfold
//
// Puts a tab's web view on screen. The web view belongs to the tab, so switching tabs or panes never reloads a page.

import SwiftUI
import WebKit

struct WebHost: UIViewRepresentable {
    let tab: Tab

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.show(tab.webView)
        tab.loadPendingIfNeeded()
        return v
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.show(tab.webView)
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
