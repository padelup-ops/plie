// Sheets.swift — Twinfold
//
// Tabs (both panes), bookmarks and history, pairs, saving a pair, and settings.

import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Tabs

struct TabsSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<2, id: \.self) { i in
                    let pane = browser.panes[i]
                    Section {
                        ForEach(pane.tabs) { tab in
                            Button {
                                browser.select(tab)
                                dismiss()
                            } label: {
                                TabRow(tab: tab, isCurrent: pane.tab === tab && browser.active == i)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Close", role: .destructive) { browser.close(tab) }
                                Button("Other Pane") { browser.moveToOtherPane(tab) }.tint(Brand.accent)
                            }
                            .contextMenu {
                                Button("Move to the Other Pane", systemImage: "arrow.up.arrow.down") { browser.moveToOtherPane(tab) }
                                Button("Close", systemImage: "xmark", role: .destructive) { browser.close(tab) }
                            }
                        }
                    } header: {
                        HStack {
                            Text(title(for: i))
                            Spacer()
                            Button {
                                browser.newTab(in: i, focus: true)
                                dismiss()
                            } label: { Image(systemName: "plus") }
                            .accessibilityLabel(Text("New Tab"))
                        }
                    } footer: {
                        if pane.tabs.count > 1 {
                            Button("Close Other Tabs") { browser.closeOthers(in: i) }
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("New Tab", systemImage: "plus.square") { browser.newTab(); dismiss() }
                        Button("New Private Tab", systemImage: "eye.slash") { browser.newTab(isPrivate: true); dismiss() }
                    } label: { Image(systemName: "plus") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func title(for pane: Int) -> LocalizedStringKey {
        let wide = browser.layoutSideBySide
        switch (pane, wide) {
        case (0, false): return "Top Pane"
        case (0, true): return "Left Pane"
        case (_, false): return "Bottom Pane"
        default: return "Right Pane"
        }
    }
}

private struct TabRow: View {
    let tab: Tab
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            if tab.isPrivate {
                Image(systemName: "eye.slash.fill").foregroundStyle(Brand.coral).frame(width: 28)
            } else if let url = tab.savedURL {
                Initial(text: tab.displayTitle, url: url, size: 28)
            } else {
                Image(systemName: "square.dashed").foregroundStyle(.secondary).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle).lineLimit(1)
                if !tab.displayAddress.isEmpty {
                    Text(tab.displayAddress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent { Image(systemName: "checkmark").foregroundStyle(Brand.accent) }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Bookmarks and history

struct LibrarySheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var query = ""
    @State private var importing = false
    @State private var confirmClear = false
    @State private var renaming: Bookmark?
    @State private var newName = ""

    var body: some View {
        let lib = Library.shared
        NavigationStack {
            List {
                if page == 0 {
                    let marks = filtered(lib.bookmarks)
                    if marks.isEmpty {
                        Text("No bookmarks yet. Add one from the menu, or import them from another browser.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(marks) { b in
                        Button { open(b.url) } label: { row(b.title, b.url, detail: b.folder) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in the Other Pane", systemImage: "rectangle.split.1x2") {
                                    browser.load(b.url, inPane: browser.otherIndex)
                                    if !browser.isSplit { browser.toggleSplit() }
                                    dismiss()
                                }
                                Button("Rename", systemImage: "pencil") { renaming = b; newName = b.title }
                                Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.url = b.url }
                            }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { marks[$0].id })
                        lib.deleteBookmarks(at: IndexSet(lib.bookmarks.indices.filter { ids.contains(lib.bookmarks[$0].id) }))
                    }
                    .onMove(perform: query.isEmpty ? { lib.moveBookmarks(from: $0, to: $1) } : nil)
                } else {
                    let visits = lib.history.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                        || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
                    if visits.isEmpty {
                        Text("No history.").foregroundStyle(.secondary)
                    }
                    ForEach(visits.prefix(500)) { v in
                        Button { open(v.url) } label: {
                            row(v.title, v.url, detail: v.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { lib.deleteHistory(at: $0, in: Array(visits.prefix(500))) }
                }
            }
            .searchable(text: $query)
            .navigationTitle(page == 0 ? Text("Bookmarks") : Text("History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $page) {
                        Text("Bookmarks").tag(0)
                        Text("History").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if page == 0 {
                        Menu {
                            Button("Import Bookmarks…", systemImage: "square.and.arrow.down") { importing = true }
                            EditButton()
                        } label: { Image(systemName: "ellipsis.circle") }
                    } else {
                        Button("Clear", role: .destructive) { confirmClear = true }
                            .disabled(lib.history.isEmpty)
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { lib.clearHistory() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.html, .text, .item]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let html = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
                let added = lib.importBookmarks(BookmarkFile.parse(html))
                browser.flash(String(localized: "\(added) bookmarks imported"))
            }
            .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let r = renaming { lib.rename(r, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func filtered(_ list: [Bookmark]) -> [Bookmark] {
        guard !query.isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
    }

    private func open(_ url: URL) {
        browser.load(url)
        dismiss()
    }

    private func row(_ title: String, _ url: URL, detail: String?) -> some View {
        HStack(spacing: 12) {
            Initial(text: title.isEmpty ? (url.host() ?? "?") : title, url: url, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? (url.host() ?? url.absoluteString) : title).lineLimit(1)
                Text([url.host(), detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Pairs

struct PairsSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let lib = Library.shared
        NavigationStack {
            List {
                Section {
                    if lib.pairs.isEmpty {
                        Text("A pair is two pages you use together: a video and your notes, a recipe and a timer, two news sites. Open both, then choose Save as Pair in the menu.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lib.pairs) { pair in
                        Button {
                            browser.open(pair)
                            dismiss()
                        } label: { PairRow(pair: pair) }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { lib.deletePairs(at: $0) }
                    .onMove { lib.movePairs(from: $0, to: $1) }
                } footer: {
                    if !lib.pairs.isEmpty {
                        Text("The first four pairs also open from the Twinfold icon: touch and hold it on the Home Screen.")
                    }
                }
                if browser.canSavePair {
                    Section {
                        Button("Save the Two Open Pages as a Pair", systemImage: "plus") { browser.sheet = .savePair }
                    }
                }
            }
            .navigationTitle("Pairs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { if !lib.pairs.isEmpty { EditButton() } }
            }
        }
    }
}

struct SavePairSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    Text("Both pages and the size of each pane are saved.")
                }
                Section {
                    LabeledContent(LocalizedStringKey(topLabel), value: browser.panes[0].tab?.displayAddress ?? "")
                    LabeledContent(LocalizedStringKey(bottomLabel), value: browser.panes[1].tab?.displayAddress ?? "")
                }
            }
            .navigationTitle("Save as Pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard Store.shared.isPro || Library.shared.pairs.count < 2 else {
                            Store.shared.gate(.pairs) {}
                            return
                        }
                        if let pair = browser.makePair(named: n.isEmpty ? browser.suggestedPairName() : n) {
                            Library.shared.savePair(pair)
                            browser.flash(String(localized: "Pair saved"))
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { name = browser.suggestedPairName() }
        }
        .presentationDetents([.medium])
    }

    private var wide: Bool { browser.layoutSideBySide }
    private var topLabel: String { wide ? "Left" : "Top" }
    private var bottomLabel: String { wide ? "Right" : "Bottom" }
}

// MARK: - Settings

struct SettingsSheet: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClearData = false

    var body: some View {
        @Bindable var lib = Library.shared
        NavigationStack {
            Form {
                Section {
                    if Store.shared.isPro {
                        Label { Text("Twinfold Pro") } icon: { Image(systemName: "crown.fill").foregroundStyle(Brand.accent) }
                    } else {
                        Button { Store.shared.gate(.general) {} } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill").font(.title3).foregroundStyle(Brand.mint)
                                    .frame(width: 40, height: 40).background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Twinfold Pro").font(.headline)
                                    Text("AI beside the page, unlimited pairs, your gestures").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Search") {
                    Picker("Search Engine", selection: $lib.searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                    }
                }
                Section {
                    Toggle("Block Ads and Trackers", isOn: $lib.blockTrackers)
                    Toggle("Hide Cookie Banners", isOn: $lib.hideCookieBanners)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Twinfold has no account, no server and no analytics. Your history and bookmarks stay on this iPhone; site icons come from the sites themselves. Hidden cookie banners are not answered: a site may still ask again.")
                }
                Section {
                    Toggle("Open Links from Other Apps in a New Tab", isOn: $lib.linksFromAppsInNewTab)
                } header: {
                    Text("Links")
                }
                Section {
                    NavigationLink { GestureSettings() } label: {
                        LabeledContent("Gestures", value: lib.twoFingerGestures ? String(localized: "On") : String(localized: "Off"))
                    }
                    NavigationLink("What's New") { WhatsNewList() }
                }
                Section {
                    Toggle("Dark Pages", isOn: $lib.darkPages)
                    Picker(selection: Binding(get: { lib.pageFont }, set: { f in Store.shared.gate(.pageFont) { lib.pageFont = f } })) {
                        ForEach(PageFont.allCases) { Text($0.title).tag($0) }
                    } label: { Text("Page Font") }
                    Toggle("Lock Private Tabs with Face ID", isOn: $lib.lockPrivate)
                    NavigationLink("Profiles") { ProfilesSettings() }
                    Toggle("Sync with iCloud", isOn: $lib.iCloudSync)
                } header: {
                    Text("Pages")
                } footer: {
                    Text("iCloud keeps your bookmarks, pairs and pinned apps on all your devices.")
                }
                Section {
                    Toggle("Favourites", isOn: $lib.startFavourites)
                    Toggle("Apps on the Web", isOn: $lib.startApps)
                    Toggle("Pairs", isOn: $lib.startPairs)
                    Toggle("Recently Visited", isOn: $lib.startRecent)
                } header: {
                    Text("Start Page")
                }
                Section {
                    Button("Show the Tutorial Again") { browser.sheet = .tutorial }
                }
                Section {
                    Picker("Bar", selection: $lib.barAtTop) {
                        Text("Bottom of the Page").tag(false)
                        Text("Top of the Page").tag(true)
                    }
                    NavigationLink {
                        PaletteSettings()
                    } label: {
                        LabeledContent { Text(lib.palette ? "On" : "Off") } label: {
                            Label { Text("Action Palette") } icon: { Image(systemName: "circle.grid.2x2.fill").foregroundStyle(Brand.accent) }
                        }
                    }
                    NavigationLink {
                        DownloadsList()
                    } label: {
                        Label { Text("Downloads") } icon: { Image(systemName: "arrow.down.circle").foregroundStyle(Brand.accent) }
                    }
                    Toggle("Side Bars with Tabs and Buttons", isOn: $lib.sideDock)
                    if lib.sideDock {
                        Picker("Tabs and Buttons", selection: $lib.dockTogether) {
                            Text("Together on One Side").tag(true)
                            Text("Split on Both Sides").tag(false)
                        }
                        Toggle("Dock Follows Your Hand", isOn: $lib.dockFollowsHand)
                    }
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Double tap the dock's handle to move it to the other side.")
                }
                Section {
                    Toggle("Full Screen Videos Stay in Their Page", isOn: $lib.fullscreenInPane)
                } header: {
                    Text("Videos")
                } footer: {
                    Text("A video's full-screen button fills its own page, and the other page stays in view. Applies to pages opened from now on.")
                }
                Section {
                    Toggle("Video Above When Half Folded", isOn: $lib.laptopPosture)
                } header: {
                    Text("iPhone Duo")
                } footer: {
                    Text("Stand your Duo half folded, like a small laptop: the video in the top page fills its half, the bottom page stays yours.")
                }
                Section {
                    Button("Clear Cookies and Website Data", role: .destructive) { confirmClearData = true }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Link("Help and Contact", destination: URL(string: "https://foldly.netlify.app/twinfold/en/")!)
                    Link("Privacy Policy", destination: URL(string: "https://foldly.netlify.app/twinfold/en/privacy.html")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out of every site and delete cookies, caches and saved site data?",
                                isPresented: $confirmClearData, titleVisibility: .visible) {
                Button("Clear Website Data", role: .destructive) {
                    WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                            modifiedSince: .distantPast) {
                        browser.flash(String(localized: "Website data cleared"))
                    }
                }
            }
        }
    }
}
