// StartPage.swift — Twinfold
//
// What a new tab shows: a search field, the favourites (bookmarks), the saved pairs and a few recent pages.

import SwiftUI

struct StartPage: View {
    @Environment(Browser.self) private var browser
    let pane: Int

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 14)]

    var body: some View {
        let lib = Library.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button {
                    browser.active = pane
                    browser.editingAddress = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search or enter address")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if !lib.bookmarks.isEmpty {
                    section("Favourites")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(lib.bookmarks.prefix(12)) { b in
                            Button { open(b.url) } label: { SiteTile(title: b.title, url: b.url) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !lib.pairs.isEmpty {
                    section("Pairs")
                    VStack(spacing: 8) {
                        ForEach(lib.pairs.prefix(4)) { pair in
                            Button { browser.open(pair) } label: { PairRow(pair: pair) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                let recent = Array(uniqueRecent(lib.history).prefix(5))
                if !recent.isEmpty {
                    section("Recently Visited")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(recent) { v in
                            Button { open(v.url) } label: {
                                HStack(spacing: 10) {
                                    Initial(text: v.title.isEmpty ? (v.url.host() ?? "?") : v.title, url: v.url, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(v.title.isEmpty ? (v.url.host() ?? "") : v.title).lineLimit(1)
                                        Text(v.url.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.headline)
    }

    private func open(_ url: URL) {
        browser.load(url, inPane: pane)
    }

    private func uniqueRecent(_ list: [Visit]) -> [Visit] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.url.host() ?? $0.url.absoluteString).inserted }
    }
}

/// A site's tile: a coloured initial (no favicons are fetched, so nothing leaks to a third party).
struct SiteTile: View {
    let title: String
    let url: URL

    var body: some View {
        VStack(spacing: 6) {
            Initial(text: title, url: url, size: 56)
            Text(title).font(.caption).lineLimit(1).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Initial: View {
    let text: String
    let url: URL
    let size: CGFloat

    var body: some View {
        let host = url.host() ?? text
        let hue = Double(host.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % 360) / 360
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.82).gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(String(text.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct PairRow: View {
    let pair: Pair

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Initial(text: pair.first.host() ?? "", url: pair.first, size: 20)
                Initial(text: pair.second.host() ?? "", url: pair.second, size: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.name).lineLimit(1)
                Text("\(pair.first.host() ?? "") · \(pair.second.host() ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "rectangle.split.1x2").foregroundStyle(Brand.accent)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
