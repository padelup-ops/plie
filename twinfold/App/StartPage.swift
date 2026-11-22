// StartPage.swift — Twinfold
//
// What a new tab shows: a search field, the favourites (bookmarks), the saved pairs and a few recent pages.

import SwiftUI

struct StartPage: View {
    @Environment(Browser.self) private var browser
    let pane: Int

    private let columns = [GridItem(.adaptive(minimum: 70, maximum: 92), spacing: 14)]

    var body: some View {
        let lib = Library.shared
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(LocalizedStringKey(pane == 0 ? (browser.currentlySideBySide ? "Left page" : "Top page") : (browser.currentlySideBySide ? "Right page" : "Bottom page")))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Brand.accent)
                }
                .padding(.top, 8)

                Button {
                    browser.active = pane
                    browser.editingAddress = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
                        Text("Search or enter address")
                        Spacer()
                        Image(systemName: "mic.fill").foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(Color(.systemBackground), in: Capsule())
                    .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                }
                .buttonStyle(.plain)

                if lib.startFavourites && !lib.bookmarks.isEmpty {
                    section("Favourites")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(lib.bookmarks.prefix(8)) { b in
                            Button { open(b.url) } label: { SiteTile(title: b.title, url: b.url) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if lib.startApps {
                section("Apps on the Web", detail: "Open them here, next to your other page")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(WebApp.all) { app in
                        Button { open(app.url) } label: { SiteTile(title: app.name, url: app.url) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in the Other Pane", systemImage: "rectangle.split.1x2") {
                                    browser.load(app.url, inPane: 1 - pane)
                                    if !browser.isSplit { browser.toggleSplit() }
                                }
                                Button("Pin to the Dock", systemImage: "pin") { Library.shared.pin(app.url) }
                            }
                    }
                }

                }

                if lib.startPairs && !lib.pairs.isEmpty {
                    section("Pairs")
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(lib.pairs.prefix(8)) { pair in
                                Button { browser.open(pair) } label: { PairCard(pair: pair) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                let recent = lib.startRecent ? Array(uniqueRecent(lib.history).prefix(5)) : []
                if !recent.isEmpty {
                    section("Recently Visited")
                    VStack(spacing: 0) {
                        ForEach(recent) { v in
                            Button { open(v.url) } label: {
                                HStack(spacing: 12) {
                                    Initial(text: v.title.isEmpty ? (v.url.host() ?? "?") : v.title, url: v.url, size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(v.title.isEmpty ? (v.url.host() ?? "") : v.title).lineLimit(1)
                                        Text(v.url.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if !Store.shared.isPro {
                    Button { Store.shared.gate(.general) {} } label: { ProBanner() }
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(.secondarySystemBackground))
    }

    private var greeting: LocalizedStringKey {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func section(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func open(_ url: URL) {
        browser.load(url, inPane: pane)
    }

    private func uniqueRecent(_ list: [Visit]) -> [Visit] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.url.host() ?? $0.url.absoluteString).inserted }
    }
}

/// Web versions of popular apps: they run in a pane, next to the other page.
struct WebApp: Identifiable {
    let name: String
    let url: URL
    var id: String { name }

    static let all: [WebApp] = [
        ("YouTube", "https://m.youtube.com"), ("Maps", "https://www.google.com/maps"), ("Gmail", "https://mail.google.com"),
        ("Docs", "https://docs.google.com"), ("Notion", "https://www.notion.so"), ("X", "https://x.com"),
        ("Instagram", "https://www.instagram.com"), ("Reddit", "https://www.reddit.com"), ("Wikipedia", "https://www.wikipedia.org"),
        ("Spotify", "https://open.spotify.com"), ("Translate", "https://translate.google.com"), ("WhatsApp", "https://web.whatsapp.com"),
    ].map { WebApp(name: $0.0, url: URL(string: $0.1)!) }
}

private struct ProBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            ProHero(phase: false)
                .scaleEffect(0.28)
                .frame(width: 70, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Twinfold Pro").font(.headline).foregroundStyle(.white)
                Text("AI beside the page, unlimited pairs, your own gestures.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Brand.mint)
        }
        .padding(16)
        .background(LinearGradient(colors: [Brand.ink, Color(red: 0.03, green: 0.27, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A pair as two little stacked pages.
struct PairCard: View {
    let pair: Pair

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 3) {
                strip(pair.first)
                strip(pair.second)
            }
            .padding(6)
            .background(Brand.ink.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(pair.name).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .frame(width: 150)
    }

    private func strip(_ url: URL) -> some View {
        let host = url.host() ?? ""
        return HStack(spacing: 6) {
            Initial(text: host.replacingOccurrences(of: "www.", with: ""), url: url, size: 22)
            Text(host.replacingOccurrences(of: "www.", with: "")).font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(height: 40)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        if let icon = SiteIcons.shared.image(for: url) {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.04)
                .accessibilityHidden(true)
        } else {
            letter
        }
    }

    private var letter: some View {
        let host = url.host() ?? text
        let hue = Double(host.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % 360) / 360
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.42, brightness: 0.9), Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.72)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: Color(hue: hue, saturation: 0.6, brightness: 0.5).opacity(0.25), radius: size * 0.08, y: size * 0.04)
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
