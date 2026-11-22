// TabOverview.swift — Twinfold
//
// Every tab at a glance: full-screen thumbnails of the pages, normal or private, each marked with its pane, and a
// tile for a new tab. Tap one to go back to it; swipe it away to close it.

import SwiftUI
import WebKit

extension Tab {
    /// Takes a picture of the page for the overview (only when it is on screen; otherwise the last one stays).
    func captureThumbnail() async {
        guard webView.window != nil, webView.bounds.width > 10 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 360
        if let image = try? await webView.takeSnapshot(configuration: config) { thumbnail = image }
    }
}

extension Browser {
    func showOverview() {
        Task {
            for p in panes { await p.tab?.captureThumbnail() }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { overviewShown = true }
        }
    }
}

struct TabOverview: View {
    @Environment(Browser.self) private var browser
    @State private var privateMode = false
    /// Choosing tabs to ask AI about them together.
    @State private var selecting = false
    @State private var picked = Set<UUID>()
    @Namespace private var space

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]

    var body: some View {
        let all = browser.panes.indices.flatMap { i in browser.panes[i].tabs.map { (i, $0) } }
        let shown = all.filter { $0.1.isPrivate == privateMode }
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(shown, id: \.1.id) { item in
                        let (pane, tab) = item
                        TabCard(tab: tab, pane: pane, current: browser.panes[pane].tab === tab && browser.active == pane,
                                sideBySide: browser.currentlySideBySide) {
                            if selecting {
                                if picked.contains(tab.id) { picked.remove(tab.id) } else { picked.insert(tab.id) }
                            } else {
                                browser.select(tab)
                                close()
                            }
                        } onClose: {
                            withAnimation(.spring(response: 0.3)) { browser.close(tab) }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if selecting {
                                Image(systemName: picked.contains(tab.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(picked.contains(tab.id) ? Brand.accent : .secondary)
                                    .background(Circle().fill(Color(.systemBackground)))
                                    .padding(10).padding(.bottom, 22)
                            }
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    Button {
                        browser.newTab(isPrivate: privateMode)
                        close()
                    } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary))
                                .aspectRatio(0.72, contentMode: .fit)
                            Text(privateMode ? "New Private Tab" : "New Tab").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Button("Cancel") { withAnimation { selecting = false } }
                        Spacer()
                        Menu {
                            ForEach(Assistant.allCases) { a in
                                Button(a.name) {
                                    let tabs = all.map(\.1).filter { picked.contains($0.id) }
                                    browser.ask(a, about: tabs)
                                    selecting = false
                                    close()
                                }
                            }
                        } label: {
                            Label(String(localized: "Ask AI (\(picked.count))"), systemImage: "sparkles")
                                .font(.headline)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(picked.isEmpty)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $privateMode.animation(.spring(response: 0.3))) {
                        Text("Normal (\(all.filter { !$0.1.isPrivate }.count))").tag(false)
                        Text("Private (\(all.filter { $0.1.isPrivate }.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Bookmarks and History", systemImage: "book") { close(); browser.sheet = .library }
                        Button("Pairs", systemImage: "square.on.square") { close(); browser.sheet = .pairs }
                        Button("Close Other Tabs", systemImage: "xmark.square") { browser.closeOthers(in: browser.active) }
                        Button("Ask AI About Tabs…", systemImage: "sparkles") {
                            Store.shared.gate(.ai) { withAnimation { selecting = true; picked = [] } }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onAppear { privateMode = browser.activeTab?.isPrivate ?? false }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { browser.overviewShown = false }
    }
}

private struct TabCard: View {
    let tab: Tab
    let pane: Int
    let current: Bool
    let sideBySide: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = tab.thumbnail {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let url = tab.savedURL {
                        ZStack {
                            Color(.secondarySystemBackground)
                            Initial(text: tab.displayTitle, url: url, size: 54)
                        }
                    } else {
                        ZStack {
                            Color(.secondarySystemBackground)
                            Image(systemName: "magnifyingglass").font(.title).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.72, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(current ? (tab.isPrivate ? Brand.coral : Brand.accent) : Color.primary.opacity(0.08), lineWidth: current ? 3 : 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                .overlay(alignment: .topLeading) {
                    Label(paneName, systemImage: pane == 0 ? (sideBySide ? "rectangle.lefthalf.filled" : "rectangle.tophalf.filled")
                                                         : (sideBySide ? "rectangle.righthalf.filled" : "rectangle.bottomhalf.filled"))
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .padding(7)
                        .glassEffect(.regular, in: .circle)
                        .padding(8)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(8)
                .accessibilityLabel(Text("Close"))
            }
            HStack(spacing: 5) {
                if let url = tab.savedURL { Initial(text: tab.displayTitle, url: url, size: 14) }
                Text(tab.displayTitle).font(.caption.weight(.medium)).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .offset(x: drag)
        .opacity(1 - Double(min(abs(drag), 160) / 220))
        .gesture(DragGesture(minimumDistance: 20)
            .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { drag = v.translation.width } }
            .onEnded { v in
                if abs(v.translation.width) > 110 { onClose() } else { withAnimation(.spring(response: 0.3)) { drag = 0 } }
            })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Close")) { onClose() }
    }

    private var paneName: LocalizedStringKey {
        switch (pane, sideBySide) {
        case (0, false): return "Top Pane"
        case (0, true): return "Left Pane"
        case (_, false): return "Bottom Pane"
        default: return "Right Pane"
        }
    }
}
