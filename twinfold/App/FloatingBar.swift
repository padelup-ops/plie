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

/// The side dock: the active page's tabs as little icons on its edge, one tap to switch, + for a new one.
struct SideDock: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let pane = browser.activePane
        VStack(spacing: 6) {
            ForEach(Array(pane.tabs.suffix(7))) { tab in
                Button { withAnimation(.spring(response: 0.3)) { browser.select(tab) } } label: {
                    Group {
                        if let url = tab.savedURL {
                            Initial(text: tab.displayTitle, url: url, size: 28)
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(pane.tab === tab ? (tab.isPrivate ? Brand.coral : Brand.accent) : .clear, lineWidth: 2)
                            .padding(-3)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if tab.isPrivate {
                            Image(systemName: "eye.slash.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(2).background(Brand.coral, in: Circle()).offset(x: 4, y: 4)
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.displayTitle))
                .contextMenu {
                    Button("Move to the Other Pane", systemImage: "arrow.up.arrow.down") { browser.moveToOtherPane(tab) }
                    Button("Close", systemImage: "xmark", role: .destructive) { browser.close(tab) }
                }
            }
            Button { browser.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New Tab"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
