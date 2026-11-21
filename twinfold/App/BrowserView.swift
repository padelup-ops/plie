// BrowserView.swift — Twinfold
//
// The screen: one or two panes, and the bar at the bottom. On an unfolded iPhone Duo the two panes meet exactly at
// the fold (the `.division` reserved region); elsewhere they share the screen at a ratio the handle changes.

import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var browser = browser
        VStack(spacing: 0) {
            PanesArea()
            AddressBar()
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            if let toast = browser.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $browser.sheet) { kind in
            switch kind {
            case .tabs: TabsSheet()
            case .library: LibrarySheet()
            case .pairs: PairsSheet()
            case .settings: SettingsSheet()
            case .savePair: SavePairSheet()
            case .reader: ReaderSheet()
            case .following: FollowingSheet()
            }
        }
        .tint(Brand.accent)
    }
}

// MARK: - Panes

struct PanesArea: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        GeometryReader { geo in
            let fold = geo.reservedRegions(kind: .division, options: .includeInactive).first?.frame
            let layout = PaneLayout(size: geo.size, fold: fold, ratio: browser.ratio)
            let split = browser.isSplit

            ZStack(alignment: .topLeading) {
                ForEach(0..<2, id: \.self) { i in
                    let shown = split || i == browser.active
                    let frame = split ? (i == 0 ? layout.first : layout.second) : CGRect(origin: .zero, size: geo.size)
                    PaneView(index: i, showsActiveMark: split)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .zIndex(i == browser.active ? 1 : 0)
                }
                if split {
                    PaneDivider(layout: layout, size: geo.size)
                        .zIndex(2)
                }
            }
            .onAppear { browser.hasFold = fold != nil }
            .onChange(of: fold != nil) { _, has in browser.hasFold = has }
        }
    }
}

/// Where the two panes go. With a fold, the split is the fold; without one, the ratio decides, across the longer side.
struct PaneLayout {
    let first: CGRect
    let second: CGRect
    let sideBySide: Bool
    let atFold: Bool
    /// The gap between the panes (the fold, or the handle's line).
    let gap: CGRect

    static let handleGap: CGFloat = 6

    init(size: CGSize, fold: CGRect?, ratio: Double) {
        if let fold, fold.width != fold.height {
            atFold = true
            sideBySide = fold.height > fold.width
            if sideBySide {
                let lo = max(0, fold.minX), hi = min(size.width, fold.maxX)
                first = CGRect(x: 0, y: 0, width: lo, height: size.height)
                second = CGRect(x: hi, y: 0, width: size.width - hi, height: size.height)
                gap = CGRect(x: lo, y: 0, width: hi - lo, height: size.height)
            } else {
                let lo = max(0, fold.minY), hi = min(size.height, fold.maxY)
                first = CGRect(x: 0, y: 0, width: size.width, height: lo)
                second = CGRect(x: 0, y: hi, width: size.width, height: size.height - hi)
                gap = CGRect(x: 0, y: lo, width: size.width, height: hi - lo)
            }
        } else {
            atFold = false
            sideBySide = size.width > size.height
            let g = Self.handleGap
            if sideBySide {
                let w = (size.width - g) * ratio
                first = CGRect(x: 0, y: 0, width: w, height: size.height)
                second = CGRect(x: w + g, y: 0, width: size.width - w - g, height: size.height)
                gap = CGRect(x: w, y: 0, width: g, height: size.height)
            } else {
                let h = (size.height - g) * ratio
                first = CGRect(x: 0, y: 0, width: size.width, height: h)
                second = CGRect(x: 0, y: h + g, width: size.width, height: size.height - h - g)
                gap = CGRect(x: 0, y: h, width: size.width, height: g)
            }
        }
    }
}

/// The line between the panes. Without a fold, its grip resizes them (double tap: back to half and half).
private struct PaneDivider: View {
    @Environment(Browser.self) private var browser
    let layout: PaneLayout
    let size: CGSize
    @State private var startRatio: Double?

    var body: some View {
        let g = layout.gap
        ZStack {
            Rectangle().fill(Color(.separator).opacity(layout.atFold ? 0 : 0.6))
            if !layout.atFold {
                Capsule()
                    .fill(Brand.accent)
                    .frame(width: layout.sideBySide ? 4 : 44, height: layout.sideBySide ? 44 : 4)
            }
        }
        .frame(width: g.width, height: g.height)
        .contentShape(Rectangle().inset(by: -14))
        .offset(x: g.minX, y: g.minY)
        .gesture(drag, isEnabled: !layout.atFold)
        .onTapGesture(count: 2) {
            guard !layout.atFold else { return }
            withAnimation(.spring(response: 0.3)) { browser.ratio = 0.5 }
        }
        .contextMenu {
            Button("Swap Panes", systemImage: "arrow.up.arrow.down") { browser.swap() }
            Button("One Page", systemImage: "rectangle") { browser.toggleSplit() }
            if browser.canSavePair {
                Button("Save as Pair", systemImage: "star") { browser.sheet = .savePair }
            }
        }
        .accessibilityLabel("Divider between the two pages")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: browser.ratio = min(0.8, browser.ratio + 0.1)
            case .decrement: browser.ratio = max(0.2, browser.ratio - 0.1)
            default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let start = startRatio ?? browser.ratio
                if startRatio == nil { startRatio = start }
                let total = layout.sideBySide ? size.width : size.height
                let delta = (layout.sideBySide ? v.translation.width : v.translation.height) / max(total, 1)
                browser.ratio = min(0.8, max(0.2, start + delta))
            }
            .onEnded { _ in
                startRatio = nil
                // Snaps to thirds and half when close.
                for snap in [1.0 / 3, 0.5, 2.0 / 3] where abs(browser.ratio - snap) < 0.03 {
                    withAnimation(.spring(response: 0.25)) { browser.ratio = snap }
                }
            }
    }
}

struct PaneView: View {
    @Environment(Browser.self) private var browser
    let index: Int
    let showsActiveMark: Bool

    var body: some View {
        let pane = browser.panes[index]
        ZStack(alignment: .top) {
            if let tab = pane.tab {
                WebHost(tab: tab)
                    .id(tab.id)
                if tab.isBlank {
                    StartPage(pane: index)
                }
                if tab.isLoading && tab.progress < 1 {
                    ProgressView(value: tab.progress)
                        .progressViewStyle(.linear)
                        .tint(Brand.accent)
                        .frame(height: 2)
                        .scaleEffect(x: 1, y: 0.7, anchor: .top)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let tab = pane.tab, tab.mediaPlaying || tab.isMuted || tab.isFilled {
                MediaControls(tab: tab)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: pane.tab?.mediaPlaying)
        .overlay {
            if showsActiveMark && browser.active == index {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Brand.accent.opacity(0.85), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .simultaneousGesture(TapGesture().onEnded {
            if browser.active != index { withAnimation(.easeOut(duration: 0.15)) { browser.active = index } }
        })
    }
}

enum Brand {
    /// Twinfold teal.
    static let accent = Color(red: 0.05, green: 0.62, blue: 0.56)
    /// Twinfold coral, for the private tabs.
    static let coral = Color(red: 0.98, green: 0.42, blue: 0.33)
    static let ink = Color(red: 0.07, green: 0.12, blue: 0.15)
}

/// The pane's own sound and video buttons, shown while something plays: cut this pane's sound (the other pane keeps
/// playing), and stretch the video over the whole pane.
struct MediaControls: View {
    let tab: Tab

    var body: some View {
        HStack(spacing: 2) {
            Button { tab.toggleMute() } label: {
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel(Text(tab.isMuted ? "Turn Sound On" : "Mute This Pane"))
            if tab.mediaVideo || tab.isFilled {
                Button { tab.toggleFill() } label: {
                    Image(systemName: tab.isFilled ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel(Text(tab.isFilled ? "Back to the Page" : "Fill the Pane with the Video"))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: Capsule())
        .buttonStyle(.plain)
    }
}
