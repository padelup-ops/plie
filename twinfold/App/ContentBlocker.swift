// ContentBlocker.swift — Twinfold
//
// Blocks requests to well-known ad and tracking servers (WebKit content rules, compiled once on the device),
// and can hide the cookie banners of the common consent tools. The list is Twinfold's own, kept short and
// conservative so pages don't break.

import Foundation
import WebKit

@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private var trackers: WKContentRuleList?
    private var cookies: WKContentRuleList?
    /// The page configurations to update when a rule list or a setting changes.
    private var controllers = NSHashTable<WKUserContentController>.weakObjects()

    private init() {
        Task { await compile() }
    }

    func attach(to controller: WKUserContentController) {
        controllers.add(controller)
        apply(to: controller)
    }

    func apply() {
        for c in controllers.allObjects { apply(to: c) }
    }

    private func apply(to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        let lib = Library.shared
        if lib.blockTrackers, let trackers { controller.add(trackers) }
        if lib.hideCookieBanners, let cookies { controller.add(cookies) }
    }

    private func compile() async {
        let store = WKContentRuleListStore.default()
        trackers = await compiled(store, "twinfold-trackers-1", Self.trackerRules())
        cookies = await compiled(store, "twinfold-cookies-1", Self.cookieRules())
        apply()
    }

    private func compiled(_ store: WKContentRuleListStore?, _ id: String, _ json: String) async -> WKContentRuleList? {
        guard let store else { return nil }
        let existing: WKContentRuleList? = await withCheckedContinuation { c in
            store.lookUpContentRuleList(forIdentifier: id) { list, _ in c.resume(returning: list) }
        }
        if let existing { return existing }
        return await withCheckedContinuation { c in
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                if let error { print("Twinfold rules \(id):", error) }
                c.resume(returning: list)
            }
        }
    }

    // MARK: Rules

    /// Servers that only serve ads or tracking. Blocked when a page loads them from another site.
    static let trackerDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagservices.com", "adservice.google.com", "pagead2.googlesyndication.com",
        "amazon-adsystem.com", "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net", "criteo.com",
        "criteo.net", "casalemedia.com", "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com",
        "moatads.com", "adsrvr.org", "smartadserver.com", "teads.tv", "yieldmo.com", "sharethrough.com",
        "33across.com", "indexww.com", "bidswitch.net", "contextweb.com", "lijit.com", "sovrn.com",
        "advertising.com", "adform.net", "adition.com", "media.net", "mgid.com", "revcontent.com",
        "zemanta.com", "hotjar.com", "mouseflow.com", "fullstory.com", "crazyegg.com", "chartbeat.com",
        "chartbeat.net", "mixpanel.com", "segment.io", "amplitude.com", "branch.io", "adjust.com",
        "appsflyer.com", "bluekai.com", "demdex.net", "krxd.net", "exelator.com", "rlcdn.com",
        "agkn.com", "tapad.com", "mathtag.com", "everesttech.net", "turn.com", "serving-sys.com",
        "2mdn.net", "imrworldwide.com", "omtrdc.net", "newrelic.com", "nr-data.net", "clarity.ms",
        "ads-twitter.com", "ads.linkedin.com", "analytics.tiktok.com", "connect.facebook.net",
        "pixel.facebook.com", "an.facebook.com", "ad.doubleclick.net", "stats.g.doubleclick.net",
    ]

    static func trackerRules() -> String {
        let rules: [[String: Any]] = trackerDomains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": ["url-filter": "^https?://([^/]*\\.)?\(escaped)[:/]", "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        return json(rules)
    }

    /// The banners of the consent tools most sites use. Hidden, not answered.
    static let cookieSelectors = [
        "#onetrust-banner-sdk", "#onetrust-consent-sdk", ".onetrust-pc-dark-filter", "#CybotCookiebotDialog",
        "#CybotCookiebotDialogBodyUnderlay", ".qc-cmp2-container", "#qc-cmp2-container", ".fc-consent-root",
        "#didomi-host", ".didomi-popup-open .didomi-popup-backdrop", "#usercentrics-root", ".cc-window",
        ".cookie-notice", "#cookie-notice", "#cookie-law-info-bar", ".cky-consent-container", "#truste-consent-track",
        ".truste_box_overlay", "#sp_message_container_", "[id^='sp_message_container']", ".osano-cm-window",
        "#iubenda-cs-banner", ".iubenda-cs-container", "#cmpbox", "#cmpbox2", ".cmpboxBG", "#axeptio_overlay",
        "#tarteaucitronRoot", ".klaro .cookie-notice", "#cookiescript_injected", ".termly-styles-root",
    ]

    static func cookieRules() -> String {
        json([[
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": cookieSelectors.joined(separator: ", ")],
        ]])
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}
