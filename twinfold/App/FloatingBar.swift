// FloatingBar.swift — Twinfold
//
// The controls live in one small glass bubble that floats over the active page, so both pages run edge to edge.
// While you scroll down it shrinks to the address alone; scroll up or tap it and the buttons come back.

import SwiftUI

struct FloatingBar: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let tab = browser.activeTab
        let compact = browser.barCompact
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: compact ? 0 : 2) {
                if !compact, tab?.canGoBack == true {
                    icon("chevron.backward", "Back") { tab?.webView.goBack() }
                        .transition(.scale.combined(with: .opacity))
                }
                if !compact, tab?.canGoForward == true {
                    icon("chevron.forward", "Forward") { tab?.webView.goForward() }
                        .transition(.scale.combined(with: .opacity))
                }
                Button {
                    if compact { withAnimation(.spring(response: 0.3)) { browser.barCompact = false } }
                    else { browser.editingAddress = true }
                } label: {
                    HStack(spacing: 5) {
                        if tab?.isPrivate == true {
                            Image(systemName: "eye.slash.fill").foregroundStyle(Brand.coral)
                        } else if tab?.url?.scheme == "https" || tab?.displayHost != nil {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        }
                        Text(address(tab))
                            .lineLimit(1)
                            .foregroundStyle(tab?.isBlank ?? true ? .secondary : .primary)
                    }
                    .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, compact ? 12 : 10)
                    .frame(height: compact ? 30 : 40)
                    .frame(maxWidth: compact ? 170 : 190)
                    .contentShape(Capsule())
                    .overlay(alignment: .bottom) {
                        if let tab, tab.isLoading, tab.progress < 1 {
                            GeometryReader { g in
                                Capsule().fill(Brand.accent).frame(width: max(6, g.size.width * tab.progress), height: 2)
                            }
                            .frame(height: 2)
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Address"))
                .accessibilityValue(Text(address(tab)))
                .contextMenu {
                    if let url = tab?.url { Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.url = url } }
                    Button("Paste and Go", systemImage: "doc.on.clipboard") { if let s = UIPasteboard.general.string { browser.go(s) } }
                    Button("Reload", systemImage: "arrow.clockwise") { tab?.webView.reload() }
                }

                if !compact {
                    icon(browser.isSplit ? "rectangle" : (browser.currentlySideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2"),
                         LocalizedStringKey(browser.isSplit ? "One page" : "Two pages")) { browser.toggleSplit() }
                    icon("square.on.square", "Tabs") { browser.showOverview() }
                    MainMenu(compact: true)
                }
            }
            .padding(.horizontal, compact ? 0 : 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: compact)
    }

    private func address(_ tab: Tab?) -> String {
        guard let tab, !tab.isBlank else { return String(localized: "Search") }
        return tab.displayAddress
    }

    private func icon(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Typing an address: a glass field above the keyboard, across the screen.
struct AddressPanel: View {
    var body: some View {
        AddressEditorView()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
    }
}

/// The side dock, in two parts that open and close on their own, each with its little coloured tab on the screen's
/// edge: the tab column (pinned apps and this page's tabs, scrolled with a flick or scrubbed along its dots) and the
/// rail (the browser's buttons). Together on one side, or split on both. Double tap a tab: over to the other side.
struct SideDock: View {
    @Environment(Browser.self) private var browser
    enum Part { case all, tabs, apps }
    var part: Part = .all
    var onRight = false

    var body: some View {
        // Side split: the tabs side gets the column, the other side the rail.
        let tabsHere = part != .apps
        let railHere = part != .tabs
        HStack(alignment: .center, spacing: 6) {
            if onRight {
                panels(tabs: tabsHere, rail: railHere)
                handles(tabs: tabsHere, rail: railHere)
            } else {
                handles(tabs: tabsHere, rail: railHere)
                panels(tabs: tabsHere, rail: railHere)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in browser.scheduleDockTuck() })
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.dockOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: browser.railOpen)
    }

    @ViewBuilder
    private func panels(tabs: Bool, rail: Bool) -> some View {
        // The rail sits against the edge, the tab column further in (mirrored on the left).
        let slide = AnyTransition.move(edge: onRight ? .trailing : .leading).combined(with: .opacity)
        if onRight {
            if tabs && browser.dockOpen { TabColumn(onRight: onRight).transition(slide) }
            if rail && browser.railOpen { ActionRail().transition(slide) }
        } else {
            if rail && browser.railOpen { ActionRail().transition(slide) }
            if tabs && browser.dockOpen { TabColumn(onRight: onRight).transition(slide) }
        }
    }

    private func handles(tabs: Bool, rail: Bool) -> some View {
        VStack(spacing: 10) {
            if tabs {
                EdgeHandle(symbol: "square.on.square", tint: Brand.coral, open: browser.dockOpen, onRight: onRight) {
                    browser.dockOpen.toggle(); browser.scheduleDockTuck()
                } flip: { browser.flipDock() }
                .accessibilityLabel(Text(browser.dockOpen ? "Hide the Tabs" : "Show the Tabs"))
            }
            if rail {
                EdgeHandle(symbol: "slider.vertical.3", tint: Brand.accent, open: browser.railOpen, onRight: onRight) {
                    browser.railOpen.toggle(); browser.scheduleDockTuck()
                } flip: { browser.flipDock() }
                .accessibilityLabel(Text(browser.railOpen ? "Hide the Buttons" : "Show the Buttons"))
            }
        }
    }
}

/// A coloured tab half tucked under the screen's edge: tap to open or close its panel, double tap to switch sides.
private struct EdgeHandle: View {
    let symbol: String
    let tint: Color
    let open: Bool
    let onRight: Bool
    let toggle: () -> Void
    let flip: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Image(systemName: (open != onRight) ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 14, weight: .heavy))
        }
        .foregroundStyle(.white)
        .frame(width: 24, height: 64)
        .background(tint.gradient, in: UnevenRoundedRectangle(
            topLeadingRadius: onRight ? 12 : 4, bottomLeadingRadius: onRight ? 12 : 4,
            bottomTrailingRadius: onRight ? 4 : 12, topTrailingRadius: onRight ? 4 : 12, style: .continuous))
        .shadow(color: tint.opacity(0.35), radius: 6, x: onRight ? -2 : 2)
        .opacity(open ? 1 : 0.92)
        .contentShape(Rectangle().inset(by: -8))
        .onTapGesture(count: 2) { flip() }
        .onTapGesture { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { toggle() } }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Move to the Other Side")) { flip() }
    }
}

/// Pinned apps, then this page's tabs: a column that scrolls with a flick. Along its side, a dot per item: slide a
/// finger down the dots and the item under it grows out beside them; let go to open it.
private struct TabColumn: View {
    @Environment(Browser.self) private var browser
    let onRight: Bool
    @State private var scrub: Int?
    private static let item: CGFloat = 40

    private enum Item: Identifiable {
        case app(URL), tab(Tab)
        var id: String { switch self { case .app(let u): return "a" + u.absoluteString; case .tab(let t): return "t" + t.id.uuidString } }
    }

    var body: some View {
        let pane = browser.activePane
        let items: [Item] = Library.shared.dockApps.map { .app($0) } + pane.tabs.map { .tab($0) }
        let current = pane.tab.map { "t" + $0.id.uuidString }
        VStack(spacing: 6) {
            dots(items, current: current)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            cell(item, current: current)
                                .id(item.id)
                                .scaleEffect(scrub.map { items.indices.contains($0) && items[$0].id == item.id ? 1.18 : 1 } ?? 1)
                        }
                    }
                    .padding(.vertical, 4)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .frame(width: Self.item + 4, height: min(CGFloat(max(items.count, 1)) * (Self.item + 4) + 8, 6.5 * (Self.item + 4)))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                             .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
                .onChange(of: scrub) { _, i in
                    if let i, items.indices.contains(i) { withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(items[i].id, anchor: .center) } }
                }
            }
            Button { browser.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New Tab"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// One dot per item; the current one in colour. Slide along them to run through the whole list.
    private func dots(_ items: [Item], current: String?) -> some View {
        let step: CGFloat = 9
        let shown = min(items.count, 16)
        return VStack(spacing: 0) {
            ForEach(0..<shown, id: \.self) { i in
                let idx = shown < items.count ? Int(Double(i) / Double(max(shown - 1, 1)) * Double(items.count - 1)) : i
                let isCurrent = items.indices.contains(idx) && items[idx].id == current
                let isScrub = scrub == idx
                Circle()
                    .fill(isCurrent ? Brand.accent : Color.primary.opacity(isScrub ? 0.7 : 0.28))
                    .frame(width: isScrub ? 8 : 6, height: isScrub ? 8 : 6)
                    .frame(height: step)
            }
        }
        .frame(width: 36)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(scrub == nil ? 0.05 : 0.1)).frame(width: 14))
        .contentShape(Rectangle().inset(by: -10))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard !items.isEmpty else { return }
                    let f = min(1, max(0, (v.location.y - 4) / max(CGFloat(shown) * step, 1)))
                    let i = min(items.count - 1, Int(f * CGFloat(items.count)))
                    if i != scrub { UISelectionFeedbackGenerator().selectionChanged(); scrub = i }
                    browser.scheduleDockTuck()
                }
                .onEnded { _ in
                    if let i = scrub, items.indices.contains(i) { open(items[i]) }
                    withAnimation(.snappy) { scrub = nil }
                }
        )
        .overlay(alignment: onRight ? .leading : .trailing) {
            // The item under the finger, large, beside the column.
            if let i = scrub, items.indices.contains(i) {
                bubble(items[i])
                    .offset(x: onRight ? -58 : 58)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }

    private func bubble(_ item: Item) -> some View {
        VStack(spacing: 4) {
            icon(item, size: 40)
            Text(title(item)).font(.caption2.weight(.semibold)).lineLimit(1).frame(maxWidth: 90)
        }
        .padding(8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func title(_ item: Item) -> String {
        switch item { case .app(let u): return u.host()?.replacingOccurrences(of: "www.", with: "") ?? ""; case .tab(let t): return t.displayTitle }
    }

    @ViewBuilder
    private func icon(_ item: Item, size: CGFloat) -> some View {
        switch item {
        case .app(let url): Initial(text: url.host() ?? "", url: url, size: size)
        case .tab(let tab):
            if let url = tab.savedURL { Initial(text: tab.displayTitle, url: url, size: size) }
            else {
                Image(systemName: "magnifyingglass").font(.system(size: size * 0.42, weight: .bold))
                    .frame(width: size, height: size)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        }
    }

    private func open(_ item: Item) {
        switch item {
        case .app(let url): browser.load(url)
        case .tab(let tab): withAnimation(.spring(response: 0.3)) { browser.select(tab) }
        }
    }

    @ViewBuilder
    private func cell(_ item: Item, current: String?) -> some View {
        Button { open(item) } label: {
            icon(item, size: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(item.id == current ? Brand.accent : .clear, lineWidth: 2).padding(-3)
                )
                .overlay(alignment: .bottomTrailing) {
                    if case .tab(let t) = item, t.isPrivate {
                        Image(systemName: "eye.slash.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(2).background(Brand.coral, in: Circle()).offset(x: 4, y: 4)
                    }
                }
                .frame(width: Self.item, height: Self.item)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title(item)))
        .contextMenu {
            switch item {
            case .app(let url):
                Button("Open in the Other Pane", systemImage: "rectangle.split.1x2") {
                    browser.load(url, inPane: browser.otherIndex)
                    if !browser.isSplit { browser.toggleSplit() }
                }
                Button("Unpin", systemImage: "pin.slash", role: .destructive) { Library.shared.unpin(url) }
            case .tab(let tab):
                if let url = tab.savedURL { Button("Pin to the Dock", systemImage: "pin") { Library.shared.pin(url) } }
                Button("Move to the Other Pane", systemImage: "arrow.up.arrow.down") { browser.moveToOtherPane(tab) }
                Button("Close", systemImage: "xmark", role: .destructive) { browser.close(tab) }
            }
        }
    }
}

/// The browser's buttons in one column on the screen's edge, within reach of the thumb.
private struct ActionRail: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let tab = browser.activeTab
        VStack(spacing: 2) {
            button("chevron.backward", "Back", enabled: tab?.canGoBack == true) { tab?.webView.goBack() }
            button("chevron.forward", "Forward", enabled: tab?.canGoForward == true) { tab?.webView.goForward() }
            Divider().frame(width: 22).padding(.vertical, 3)
            Button { browser.showOverview() } label: {
                Text("\(browser.panes.reduce(0) { $0 + $1.tabs.count })")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 24, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary, lineWidth: 1.6))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Tabs"))
            button("plus", "New Tab") { browser.newTab() }
            button(browser.isSplit ? "rectangle" : (browser.currentlySideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2"),
                   browser.isSplit ? "One page" : "Two pages") { browser.toggleSplit() }
            if let url = tab?.url, tab?.isBlank == false {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            button("plus.magnifyingglass", "Zoom In") { zoom(tab, by: 0.1) }
            button("minus.magnifyingglass", "Zoom Out") { zoom(tab, by: -0.1) }
            button(browser.maximized == nil ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                   "This Page Full Screen") { browser.toggleMaximize() }
            button("gearshape", "Settings") { browser.sheet = .settings }
            MainMenu(compact: true)
                .frame(width: 40, height: 40)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func zoom(_ tab: Tab?, by d: CGFloat) {
        guard let wv = tab?.webView else { return }
        wv.pageZoom = min(3, max(0.5, (wv.pageZoom + d).rounded(toPlaces: 1)))
        browser.flash("\(Int((wv.pageZoom * 100).rounded())) %")
    }

    private func button(_ symbol: String, _ label: LocalizedStringKey, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(Text(label))
    }
}

private extension CGFloat {
    func rounded(toPlaces p: Int) -> CGFloat { let m = pow(10, CGFloat(p)); return (self * m).rounded() / m }
}
