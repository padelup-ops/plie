// Following.swift — Twinfold
//
// Follow a site: when a page offers a feed (RSS or Atom), Twinfold can follow it and gather the new articles of
// every followed site in one list. Feeds are fetched straight from each site, from the iPhone; nothing else is
// contacted.

import Foundation
import SwiftUI

struct Follow: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var site: URL
    var feed: URL
}

struct FeedItem: Identifiable, Hashable {
    var id: String { link.absoluteString }
    var title: String
    var link: URL
    var date: Date?
    var source: String
}

/// Finds a page's feed link.
enum FeedFinder {
    static let script = #"""
    (function () {
      var l = document.querySelector('link[rel~="alternate"][type*="rss"], link[rel~="alternate"][type*="atom"], link[rel~="alternate"][type*="feed+json"]');
      return l ? l.href : null;
    })();
    """#
}

@MainActor @Observable
final class Following {
    static let shared = Following()

    private(set) var follows: [Follow] = []
    private(set) var items: [FeedItem] = []
    private(set) var read: Set<String> = []
    private(set) var loading = false

    private init() {
        follows = Self.load("follows") ?? []
        read = Set(Self.load("read") ?? [String]())
    }

    var unreadCount: Int { items.filter { !read.contains($0.id) }.count }

    func isFollowing(feed: URL?) -> Bool {
        guard let feed else { return false }
        return follows.contains { $0.feed == feed }
    }

    func follow(title: String, site: URL, feed: URL) {
        guard !isFollowing(feed: feed) else { return }
        var name = title
        if name.isEmpty { name = site.host() ?? feed.absoluteString }
        follows.insert(Follow(title: name, site: site, feed: feed), at: 0)
        save()
        Task { await refresh() }
    }

    func unfollow(feed: URL) {
        follows.removeAll { $0.feed == feed }
        items.removeAll { item in !follows.contains { $0.title == item.source } }
        save()
    }

    func delete(at offsets: IndexSet) {
        follows.remove(atOffsets: offsets)
        save()
    }

    func markRead(_ item: FeedItem) {
        read.insert(item.id)
        if read.count > 4000 { read = Set(read.suffix(3000)) }
        Self.store(Array(read), "read")
    }

    func markAllRead() {
        read.formUnion(items.map(\.id))
        Self.store(Array(read), "read")
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var all: [FeedItem] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for f in follows {
                group.addTask { await Self.fetch(f) }
            }
            for await list in group { all.append(contentsOf: list) }
        }
        items = all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    nonisolated static func fetch(_ follow: Follow) async -> [FeedItem] {
        var req = URLRequest(url: follow.feed, timeoutInterval: 20)
        req.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return FeedParser(source: follow.title, base: follow.site).parse(data).prefix(40).map { $0 }
    }

    private func save() { Self.store(follows, "follows") }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: Library.folder.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func store<T: Encodable>(_ value: T, _ name: String) {
        guard ShotMode.current == nil, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: Library.folder.appendingPathComponent(name + ".json"), options: .atomic)
    }
}

/// Reads RSS 2.0, RSS 1.0 and Atom.
final class FeedParser: NSObject, XMLParserDelegate {
    private let source: String
    private let base: URL
    private var items: [FeedItem] = []
    private var inItem = false
    private var text = ""
    private var title = ""
    private var link: String?
    private var date: Date?

    init(source: String, base: URL) {
        self.source = source
        self.base = base
    }

    func parse(_ data: Data) -> [FeedItem] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let n = name.lowercased()
        if n == "item" || n == "entry" {
            inItem = true
            title = ""; link = nil; date = nil
        } else if inItem, n == "link", let href = attributes["href"],
                  attributes["rel"] == nil || attributes["rel"] == "alternate" {
            link = href
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inItem else { return }
        switch n {
        case "title": title = value
        case "link": if link == nil, !value.isEmpty { link = value }
        case "pubdate", "published", "updated", "dc:date", "date":
            if date == nil { date = Self.parseDate(value) }
        case "item", "entry":
            inItem = false
            if let link, let url = URL(string: link, relativeTo: base)?.absoluteURL, !title.isEmpty {
                items.append(FeedItem(title: title, link: url, date: date, source: source))
            }
        default: break
        }
    }

    private static let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        for f in rfc822 { if let d = f.date(from: s) { return d } }
        return nil
    }
}

struct FollowingSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var showSites = false

    var body: some View {
        let f = Following.shared
        NavigationStack {
            List {
                if f.follows.isEmpty {
                    Text("Follow a site to see its new articles here. On a site with a feed, choose Follow This Site in the menu.")
                        .foregroundStyle(.secondary)
                } else if showSites {
                    ForEach(f.follows) { site in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.title).lineLimit(1)
                            Text(site.site.host() ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { f.delete(at: $0) }
                } else {
                    ForEach(f.items.prefix(300)) { item in
                        let unread = !f.read.contains(item.id)
                        Button {
                            f.markRead(item)
                            browser.load(item.link)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(unread ? Brand.accent : .clear).frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).fontWeight(unread ? .semibold : .regular).lineLimit(3)
                                    Text([item.source, item.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open in the Other Pane", systemImage: "rectangle.split.1x2") {
                                f.markRead(item)
                                browser.load(item.link, inPane: browser.otherIndex)
                                if !browser.isSplit { browser.toggleSplit() }
                                dismiss()
                            }
                        }
                    }
                }
            }
            .refreshable { await f.refresh() }
            .overlay { if f.loading && f.items.isEmpty { ProgressView() } }
            .navigationTitle(showSites ? Text("Followed Sites") : Text("Following"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Mark All as Read", systemImage: "checkmark.circle") { f.markAllRead() }
                        Toggle("Show Followed Sites", isOn: $showSites)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task { await f.refresh() }
        }
    }
}
