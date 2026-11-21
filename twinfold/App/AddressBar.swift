// AddressBar.swift — Twinfold
//
// The bar at the bottom: back, forward, the address of the active pane's page, one or two pages, tabs, and the menu.
// Tapping the address turns the bar into a search field with suggestions from bookmarks and history.

import SwiftUI
import UniformTypeIdentifiers

struct AddressBar: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        Group {
            if browser.editingAddress {
                AddressEditor()
            } else {
                controls
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Glass controls, each its own piece: back and forward together, the address, then one or two pages, tabs, menu.
    private var controls: some View {
        let tab = browser.activeTab
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    navButton("chevron.backward", "Back", enabled: tab?.canGoBack ?? false) { tab?.webView.goBack() }
                    navButton("chevron.forward", "Forward", enabled: tab?.canGoForward ?? false) { tab?.webView.goForward() }
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    browser.editingAddress = true
                } label: {
                    HStack(spacing: 7) {
                        if tab?.isPrivate == true {
                            Image(systemName: "eye.slash.fill").font(.footnote.weight(.semibold)).foregroundStyle(Brand.coral)
                        } else if tab?.url?.scheme == "https" || tab?.displayHost != nil {
                            Image(systemName: "lock.fill").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        } else if tab?.isBlank ?? true {
                            Image(systemName: "magnifyingglass").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text(addressText(tab))
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(tab?.isBlank ?? true ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .padding(.horizontal, 14)
                    .overlay(alignment: .bottom) {
                        if let tab, tab.isLoading, tab.progress < 1 {
                            GeometryReader { g in
                                Capsule().fill(Brand.accent)
                                    .frame(width: max(8, g.size.width * tab.progress), height: 2.5)
                            }
                            .frame(height: 2.5)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 4)
                            .animation(.easeOut(duration: 0.2), value: tab.progress)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel(Text("Address"))
                .accessibilityValue(Text(addressText(tab)))
                .contextMenu {
                    if let url = tab?.url {
                        Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.url = url }
                    }
                    Button("Paste and Go", systemImage: "doc.on.clipboard") {
                        if let s = UIPasteboard.general.string { browser.go(s) }
                    }
                    Button("Reload", systemImage: "arrow.clockwise") { tab?.webView.reload() }
                }

                roundButton(browser.isSplit ? "rectangle" : (paneIsSideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2"),
                            LocalizedStringKey(browser.isSplit ? "One page" : "Two pages")) { browser.toggleSplit() }

                Button {
                    browser.sheet = .tabs
                } label: {
                    Text("\(browser.activePane.tabs.count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary, lineWidth: 1.8))
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("Tabs, \(browser.activePane.tabs.count)"))

                MainMenu()
            }
        }
    }

    private var paneIsSideBySide: Bool {
        switch browser.axis {
        case .stacked: return false
        case .sideBySide: return true
        case .auto:
            // Close enough for the icons: the open Duo held sideways, or any landscape screen.
            let size = UIScreen.main.bounds.size
            return size.width > size.height
        }
    }

    private func addressText(_ tab: Tab?) -> String {
        guard let tab, !tab.isBlank else { return String(localized: "Search or enter address") }
        return tab.displayAddress
    }

    private func navButton(_ symbol: String, _ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private func roundButton(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
        .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Editing the address

private struct AddressEditor: View {
    @Environment(Browser.self) private var browser
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            let suggestions = Library.shared.suggestions(for: text)
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { s in
                        Button {
                            browser.editingAddress = false
                            browser.load(s.url)
                        } label: {
                            HStack {
                                Image(systemName: Library.shared.isBookmarked(s.url) ? "star.fill" : "clock")
                                    .foregroundStyle(.secondary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title.isEmpty ? (s.url.host() ?? "") : s.title).lineLimit(1)
                                    Text(s.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            HStack(spacing: 8) {
                TextField("Search or enter address", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .glassEffect(.regular, in: .capsule)
                    .onSubmit {
                        browser.editingAddress = false
                        browser.go(text)
                    }
                Button {
                    browser.editingAddress = false
                    browser.searchTwice(text)
                } label: {
                    Image(systemName: "rectangle.split.1x2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Search in Both Panes"))
                Button("Cancel") { browser.editingAddress = false }
            }
        }
        .onAppear {
            text = browser.activeTab?.url?.absoluteString ?? ""
            focused = true
        }
    }
}

// MARK: - The menu

struct MainMenu: View {
    @Environment(Browser.self) private var browser
    @State private var importing = false

    var body: some View {
        let tab = browser.activeTab
        let lib = Library.shared
        Menu {
            Section {
                Button("New Tab", systemImage: "plus.square") { browser.newTab() }
                Button("New Private Tab", systemImage: "eye.slash") { browser.newTab(isPrivate: true) }
                if let t = browser.activeTab, !t.isBlank {
                    Button(LocalizedStringKey(t.isPrivate ? "Switch to a Normal Tab" : "Switch to a Private Tab"),
                           systemImage: t.isPrivate ? "eye" : "eye.slash.circle") { browser.togglePrivate() }
                }
                Menu {
                    ForEach([10, 30, 60], id: \.self) { sec in
                        Button(String(localized: "\(sec) Seconds")) { browser.hideBar(for: sec) }
                    }
                } label: { Label("Hide the Bar", systemImage: "chevron.down.circle") }
            }
            Section {
                if let url = tab?.url {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(LocalizedStringKey(lib.isBookmarked(url) ? "Remove Bookmark" : "Add Bookmark"),
                           systemImage: lib.isBookmarked(url) ? "star.slash" : "star") {
                        lib.toggleBookmark(title: tab?.title ?? "", url: url)
                        browser.flash(lib.isBookmarked(url) ? String(localized: "Bookmark added") : String(localized: "Bookmark removed"))
                    }
                    Button("Find on Page", systemImage: "doc.text.magnifyingglass") {
                        tab?.webView.findInteraction?.presentFindNavigator(showingReplace: false)
                    }
                    Button(LocalizedStringKey(tab?.wantsDesktop == true ? "Mobile Site" : "Desktop Site"),
                           systemImage: tab?.wantsDesktop == true ? "iphone" : "desktopcomputer") { tab?.toggleDesktop() }
                    Button("Reader View", systemImage: "doc.plaintext") { browser.sheet = .reader }
                    Button("Video Notes", systemImage: "note.text") {
                        Store.shared.gate(.videoNotes) { browser.openVideoNotes() }
                    }
                    Button("Hands-Free Reading", systemImage: "arrow.down.to.line.compact") { tab?.autoScroll(60) }
                    Button("Translate in the Other Pane", systemImage: "character.book.closed") {
                        Store.shared.gate(.bilingual) { browser.translateInOtherPane() }
                    }
                    if let feed = tab?.feedURL {
                        let following = Following.shared.isFollowing(feed: feed)
                        Button(LocalizedStringKey(following ? "Unfollow This Site" : "Follow This Site"),
                               systemImage: following ? "minus.circle" : "plus.circle") {
                            if following {
                                Following.shared.unfollow(feed: feed)
                            } else {
                                Store.shared.gate(.follow) {
                                    Following.shared.follow(title: tab?.title ?? "", site: url, feed: feed)
                                    browser.flash(String(localized: "Following \(tab?.displayAddress ?? "")"))
                                }
                            }
                        }
                    }
                    Button("Save as PDF", systemImage: "doc.richtext") { Store.shared.gate(.pdf) { browser.sharePDF() } }
                    if browser.isSplit {
                        Button("Open This Page in the Other Pane", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                            browser.load(url, inPane: browser.otherIndex)
                        }
                    }
                }
            }
            Menu {
                ForEach(Assistant.AITask.allCases) { task in
                    Section(task.title) {
                        ForEach(Assistant.allCases) { a in
                            Button(a.name) { Store.shared.gate(.ai) { browser.ask(a, task) } }
                        }
                    }
                }
                Section("Open") {
                    ForEach(Assistant.allCases) { a in
                        Button(a.name) { Store.shared.gate(.ai) { browser.ask(a, nil) } }
                    }
                }
            } label: {
                Label("Ask AI in the Other Pane", systemImage: "sparkles")
            }
            Section {
                Picker(selection: Binding(get: { browser.axis }, set: { browser.setAxis($0) })) {
                    Label("Automatic", systemImage: "rectangle.on.rectangle").tag(Browser.SplitAxis.auto)
                    Label("Top and Bottom", systemImage: "rectangle.split.1x2").tag(Browser.SplitAxis.stacked)
                    Label("Side by Side", systemImage: "rectangle.split.2x1").tag(Browser.SplitAxis.sideBySide)
                } label: {
                    Label("Two Pages", systemImage: "rectangle.split.2x1")
                }
                .pickerStyle(.menu)
                if browser.isSplit {
                    Button("Swap Panes", systemImage: "arrow.up.arrow.down") { browser.swap() }
                    Toggle(isOn: Binding(get: { browser.syncScroll }, set: { _ in browser.perform(.syncScroll) })) {
                        Label("Scroll Together", systemImage: "arrow.up.and.down.text.horizontal")
                    }
                    Button(LocalizedStringKey(browser.maximized == nil ? "This Page Full Screen" : "Back to Two Pages"),
                           systemImage: browser.maximized == nil ? "arrow.up.left.and.arrow.down.right" : "rectangle.split.2x1") {
                        browser.toggleMaximize()
                    }
                    if browser.canSavePair {
                        Button("Save as Pair", systemImage: "star.square.on.square") { browser.sheet = .savePair }
                    }
                }
                Toggle(isOn: Binding(get: { browser.linkSource != nil }, set: { _ in browser.toggleLinked() })) {
                    Label("Linked Panes", systemImage: "link")
                }
                Button("Pairs", systemImage: "square.on.square") { browser.sheet = .pairs }
                Button(Following.shared.unreadCount > 0 ? String(localized: "Following (\(Following.shared.unreadCount))") : String(localized: "Following"),
                       systemImage: "newspaper") { browser.sheet = .following }
                Button("Bookmarks and History", systemImage: "book") { browser.sheet = .library }
            }
            Section {
                Button("Settings", systemImage: "gearshape") { browser.sheet = .settings }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Menu"))
    }
}
