// SiteIcons.swift — Twinfold
//
// Real site icons (YouTube's, Gmail's…), taken from each site itself, never from a third-party icon service, and
// kept on the iPhone. A site without an icon keeps its coloured initial.

import SwiftUI
import UIKit

@MainActor @Observable
final class SiteIcons {
    static let shared = SiteIcons()
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var asked = Set<String>()
    /// Icons read from the disk while drawing (not observed: drawing must not change what is observed).
    @ObservationIgnored private var disk: [String: UIImage] = [:]

    private static var folder: URL {
        let d = Library.folder.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func key(_ url: URL) -> String? {
        guard var h = url.host()?.lowercased() else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        if h.hasPrefix("m.") { h.removeFirst(2) }
        return h
    }

    func image(for url: URL) -> UIImage? {
        guard let k = Self.key(url) else { return nil }
        if let i = images[k] ?? disk[k] { return i }
        if !asked.contains(k) {
            asked.insert(k)
            let file = Self.folder.appendingPathComponent(k + ".png")
            if let data = try? Data(contentsOf: file), let i = UIImage(data: data) {
                disk[k] = i
                return i
            }
            // Not seen yet: the site's own Home Screen icon, if it has one.
            if ShotMode.current == nil, url.scheme == "https" || url.scheme == "http",
               let guess = URL(string: "https://\(url.host() ?? "")/apple-touch-icon.png") {
                Task { await fetch(guess, for: k) }
            }
        }
        return nil
    }

    /// The icon a page announces (its Home Screen icon, or its largest icon).
    static let script = #"""
    (function () {
      var best = null, size = 0;
      document.querySelectorAll('link[rel~="apple-touch-icon"], link[rel~="icon"], link[rel="shortcut icon"]').forEach(function (l) {
        var s = 16, m = (l.getAttribute('sizes') || '').match(/(\d+)/);
        if (m) s = parseInt(m[1], 10);
        if (/apple-touch-icon/.test(l.rel)) s = Math.max(s, 180);
        if (/\.svg(\?|$)/.test(l.href)) s = Math.min(s, 15);
        if (s > size) { size = s; best = l.href; }
      });
      return best;
    })();
    """#

    /// After a page loads: keeps its icon (once per site).
    func learn(from tab: Tab) {
        guard !tab.isPrivate, let url = tab.url, let k = Self.key(url), images[k] == nil, disk[k] == nil else { return }
        tab.webView.evaluateJavaScript(Self.script) { result, _ in
            MainActor.assumeIsolated {
                guard let s = result as? String, let icon = URL(string: s), icon.scheme == "https" || icon.scheme == "http" else { return }
                Task { await self.fetch(icon, for: k) }
            }
        }
    }

    private func fetch(_ url: URL, for key: String) async {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data),
              image.size.width >= 32 else { return }
        images[key] = image
        try? image.pngData()?.write(to: Self.folder.appendingPathComponent(key + ".png"), options: .atomic)
    }
}
