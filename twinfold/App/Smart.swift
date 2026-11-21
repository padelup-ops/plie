// Smart.swift — Twinfold
//
// What two pages make possible:
// • Linked panes: links tapped in one page open in the other (a list on one side, what you open on the other:
//   search results, news, forums, shops — any site becomes a list and its details).
// • Bilingual reading: the same page translated in the other pane, both scrolling together.
// • Search twice: one search, two answers (your search engine, and an AI answer engine).
// • Laptop posture on iPhone Duo: half-fold it and the video in the top page fills its half, the bottom page stays
//   yours to scroll; open it flat and the page comes back.
// • Pairs that suggest themselves: two sites you keep opening together become a pair proposal.

import SwiftUI

extension Browser {
    // MARK: Linked panes

    /// Starts or stops linking: the active page becomes the list, the other one shows what it opens.
    func toggleLinked() {
        withAnimation(.spring(response: 0.3)) {
            if linkSource != nil {
                linkSource = nil
                flash(String(localized: "Links open in place"))
            } else {
                linkSource = active
                if !isSplit { isSplit = true }
                flash(String(localized: "Links open in the other pane"))
            }
        }
    }

    /// A link tapped in the list page: true if it went to the other pane.
    func routeLink(from tab: Tab, to url: URL) -> Bool {
        guard let source = linkSource, isSplit, let i = paneIndex(of: tab), i == source, panes[i].tab === tab else { return false }
        load(url, inPane: 1 - source)
        active = source
        return true
    }

    // MARK: Bilingual reading

    /// The active page, translated into the person's language, in the other pane; both scroll together.
    func translateInOtherPane() {
        guard let url = activeTab?.url else { return }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        var comps = URLComponents(string: "https://translate.google.com/translate")!
        comps.queryItems = [.init(name: "sl", value: "auto"), .init(name: "tl", value: lang), .init(name: "u", value: url.absoluteString)]
        guard let t = comps.url else { return }
        load(t, inPane: otherIndex)
        active = 1 - active
        if !isSplit { isSplit = true }
        syncScroll = true
        flash(String(localized: "Original and translation, scrolling together"))
    }

    // MARK: Search twice

    /// One search, two answers: the search engine in the active page, an AI answer engine in the other.
    func searchTwice(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let lib = Library.shared
        if let first = lib.searchEngine.url(for: q) { load(first, inPane: active) }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "=", "?", "#"])) ?? q
        if let second = URL(string: "https://www.perplexity.ai/search?q=\(encoded)") { load(second, inPane: otherIndex) }
        active = 1 - otherIndex
        if !isSplit { isSplit = true }
    }

    // MARK: Laptop posture (iPhone Duo half folded)

    /// The hinge moved: between about 60° and 140° the Duo stands like a small laptop.
    func hingeChanged(angle: Double?, closed: Bool) {
        let laptop = !closed && (angle.map { $0 > 55 && $0 < 145 } ?? false)
        guard laptop != inLaptopPosture, Library.shared.laptopPosture else { inLaptopPosture = laptop; return }
        inLaptopPosture = laptop
        guard hasFold, isSplit, !currentlySideBySide, let top = panes[0].tab else { return }
        if laptop, top.mediaVideo, !top.isFilled {
            top.toggleFill()
            active = 1
            flash(String(localized: "Video above, page below"))
        } else if !laptop, top.isFilled {
            top.toggleFill()
        }
    }

    // MARK: Pairs that suggest themselves

    /// Called every minute: two sites open side by side again and again become a pair proposal.
    func notePairUse() {
        guard isSplit, maximized == nil,
              let a = panes[0].tab?.url?.host(), let b = panes[1].tab?.url?.host(), a != b,
              !(panes[0].tab?.isPrivate ?? true), !(panes[1].tab?.isPrivate ?? true) else { return }
        let key = "pairuse." + [a, b].sorted().joined(separator: "|")
        let d = UserDefaults.standard
        let n = d.integer(forKey: key) + 1
        d.set(n, forKey: key)
        let already = Library.shared.pairs.contains { Set([$0.first.host(), $0.second.host()]) == Set([a, b]) }
        // Three minutes together, on different occasions or not, and never asked before.
        if n == 3, !already, !d.bool(forKey: key + ".asked") {
            d.set(true, forKey: key + ".asked")
            withAnimation(.spring(response: 0.35)) { pairSuggestion = "\(a.replacingOccurrences(of: "www.", with: "")) + \(b.replacingOccurrences(of: "www.", with: ""))" }
        }
    }
}

/// The proposal to save the two open pages as a pair.
struct PairSuggestionBanner: View {
    @Environment(Browser.self) private var browser
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Brand.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text("You often open these two together").font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Save as Pair") {
                browser.pairSuggestion = nil
                browser.sheet = .savePair
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button { withAnimation { browser.pairSuggestion = nil } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Close"))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
    }
}
