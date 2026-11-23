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
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()
            // The pages run edge to edge (under the Duo's side band too); the controls float over the active page.
            PanesArea()
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    if browser.maximized != nil && browser.isSplit {
                        Button { browser.toggleMaximize() } label: {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(10)
                        .accessibilityLabel(Text("Back to Two Pages"))
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if browser.editingAddress {
                AddressPanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: Binding(get: { browser.overviewShown }, set: { browser.overviewShown = $0 })) {
            TabOverview()
        }
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
            case .downloads: DownloadsSheet()
            case .savePair: SavePairSheet()
            case .reader: ReaderSheet()
            case .following: FollowingSheet()
            case .whatsNew: WhatsNewSheet()
            case .tutorial: TutorialSheet().presentationDetents([.large]).presentationBackground(Brand.ink)
            }
        }
        .tint(Brand.accent)
        .onHingeChange { _, context in
            browser.hingeChanged(angle: context.hinge.map { $0.angle.degrees }, closed: context.hinge?.status == .closed)
        }
        .overlay(alignment: .bottom) {
            if let s = browser.pairSuggestion {
                PairSuggestionBanner(text: s)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                browser.notePairUse()
                browser.sleepUnusedTabs()
            }
        }
        .fullScreenCover(item: Binding(get: { Store.shared.asking }, set: { Store.shared.asking = $0 })) { f in
            ProSheet(feature: f)
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            if TutorialSheet.shouldShow() { browser.sheet = .tutorial }
            else if WhatsNew.shouldShow() { browser.sheet = .whatsNew }
        }
    }
}

// MARK: - Panes

struct PanesArea: View {
    @Environment(Browser.self) private var browser
    /// The panes' page sizes when the handle was picked up (kept until it's let go).
    @State private var frozen: [CGSize]?

    var body: some View {
        GeometryReader { geo in
            let raw = geo.reservedRegions(kind: .division, options: .includeInactive).first?.frame
            let fold = PaneLayout.usableFold(raw, in: geo.size)
            let layout = PaneLayout(size: geo.size, fold: fold, ratio: browser.ratio, axis: browser.axis, followsFold: browser.followsFold)
            let _ = ShotMode.current == nil ? () : PanesArea.note(size: geo.size, raw: raw, fold: fold, layout: layout)
            let split = browser.isSplit && browser.maximized == nil
            let insets = Self.windowInsets

            ZStack(alignment: .topLeading) {
                // Written out pane by pane (no ForEach over a fixed range: SwiftUI kept the old frames there when
                // only the split moved, so the handle went one way and the pages stayed put).
                pane(0, layout: layout, size: geo.size, split: split, insets: insets)
                pane(1, layout: layout, size: geo.size, split: split, insets: insets)
                if split {
                    PaneDivider(layout: layout, size: geo.size, frozen: $frozen)
                        .zIndex(3)
                }
                if Library.shared.palette && !browser.overviewShown && !browser.editingAddress {
                    ActionPalette(area: geo.size, insets: insets)
                        .zIndex(5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // The dock lives on the screen's edge (not a pane's): it can use the whole height, whichever page is active.
            .overlay(alignment: browser.dockOnRight ? .trailing : .leading) {
                if showsDock {
                    let right = browser.dockOnRight
                    SideDock(part: Library.shared.dockTogether ? .all : .tabs, onRight: right)
                        .frame(maxHeight: geo.size.height - insets.top - insets.bottom - 24)
                        .padding(right ? .trailing : .leading, (right ? insets.right : insets.left) + 2)
                        .padding(.top, insets.top).padding(.bottom, insets.bottom)
                }
            }
            .overlay(alignment: browser.dockOnRight ? .leading : .trailing) {
                if showsDock && !Library.shared.dockTogether {
                    let right = !browser.dockOnRight
                    SideDock(part: .apps, onRight: right)
                        .frame(maxHeight: geo.size.height - insets.top - insets.bottom - 24)
                        .padding(right ? .trailing : .leading, (right ? insets.right : insets.left) + 2)
                        .padding(.top, insets.top).padding(.bottom, insets.bottom)
                }
            }
            .coordinateSpace(.named(PaneLayout.space))
            .onAppear { browser.hasFold = fold != nil; browser.layoutSideBySide = layout.sideBySide }
            .onChange(of: layout.sideBySide) { _, v in browser.layoutSideBySide = v }
            .onChange(of: fold != nil) { _, has in
                browser.hasFold = has
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { browser.postureChanged() }
            }
            .onChange(of: geo.size.width > geo.size.height) { _, _ in
                // Turned: back to automatic, so the pages go top and bottom or side by side on their own (at once,
                // no animation fighting the system's rotation).
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { browser.postureChanged() }
            }
        }
    }
}

extension PanesArea {
    var showsDock: Bool {
        Library.shared.sideDock && !browser.overviewShown && !browser.editingAddress
    }

    @ViewBuilder
    func pane(_ i: Int, layout: PaneLayout, size: CGSize, split: Bool, insets: UIEdgeInsets) -> some View {
        let shown = split || i == (browser.maximized ?? browser.active)
        let frame = split ? (i == 0 ? layout.first : layout.second) : CGRect(origin: .zero, size: size)
        PaneView(index: i, showsActiveMark: split,
                 edges: PaneEdges(top: frame.minY <= 1 ? insets.top : 0,
                                  bottom: frame.maxY >= size.height - 1 ? insets.bottom : 0,
                                  left: frame.minX <= 1 ? insets.left : 0,
                                  right: frame.maxX >= size.width - 1 ? insets.right : 0),
                 frozenSize: split ? frozen?[i] : nil)
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PaneLayout.space)) } action: { PanesArea.drawn[i] = $0 }
            .offset(x: frame.minX, y: frame.minY)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .zIndex(i == browser.active ? 1 : 0)
    }

    /// Where each pane really ended up on screen (for the simulator checks).
    nonisolated(unsafe) static var drawn: [Int: CGRect] = [:]
    /// The last layout, for the simulator checks.
    nonisolated(unsafe) static var lastLayout = ""
    static func note(size: CGSize, raw: CGRect?, fold: CGRect?, layout: PaneLayout) {
        lastLayout = "size \(size) raw fold \(String(describing: raw)) fold \(String(describing: fold)) sideBySide \(layout.sideBySide) atFold \(layout.atFold) first \(layout.first) second \(layout.second) gap \(layout.gap) insets \(windowInsets)"
    }

    /// The screen's own safe area (the pages ignore it, the floating bar doesn't).
    static var windowInsets: UIEdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets ?? .zero
    }
}

/// Where the two panes go. Top and bottom or side by side (the person's choice, or automatic: along the fold, or
/// across the longer side). On the fold until the handle is dragged; then wherever the handle says.
struct PaneLayout {
    let first: CGRect
    let second: CGRect
    let sideBySide: Bool
    let atFold: Bool
    /// The gap between the panes (the fold, or the handle's line).
    let gap: CGRect
    /// The first pane's share of the screen, whatever decided it (so a drag can start from the fold).
    let share: Double

    static let handleGap: CGFloat = 6
    static let space = "panes"

    /// The fold as the system reports it, kept only when it really crosses the whole screen near its middle (a band
    /// from one edge to the other, thin, and in the screen's own coordinates). Anything else, a fold reported for
    /// another orientation for instance, is ignored and the pages split by the screen's shape instead.
    static func usableFold(_ f: CGRect?, in size: CGSize) -> CGRect? {
        guard let f, size.width > 0, size.height > 0, f.width > 0 || f.height > 0 else { return nil }
        let tol: CGFloat = 0.9
        if f.height >= size.height * tol, f.width < size.width * 0.2,
           f.midX > size.width * 0.25, f.midX < size.width * 0.75, f.minY <= size.height * 0.1 {
            return CGRect(x: f.minX, y: 0, width: max(f.width, 0), height: size.height)   // vertical: side by side
        }
        if f.width >= size.width * tol, f.height < size.height * 0.2,
           f.midY > size.height * 0.25, f.midY < size.height * 0.75, f.minX <= size.width * 0.1 {
            return CGRect(x: 0, y: f.minY, width: size.width, height: max(f.height, 0))   // horizontal: top and bottom
        }
        return nil
    }

    init(size: CGSize, fold: CGRect?, ratio: Double, axis: Browser.SplitAxis, followsFold: Bool) {
        let foldSideBySide: Bool? = fold.map { $0.height > $0.width }
        switch axis {
        case .stacked: sideBySide = false
        case .sideBySide: sideBySide = true
        case .auto: sideBySide = foldSideBySide ?? (size.width > size.height)
        }
        if let fold, followsFold, foldSideBySide == sideBySide {
            atFold = true
            if sideBySide {
                let lo = max(0, fold.minX), hi = min(size.width, fold.maxX)
                first = CGRect(x: 0, y: 0, width: lo, height: size.height)
                second = CGRect(x: hi, y: 0, width: size.width - hi, height: size.height)
                gap = CGRect(x: lo, y: 0, width: hi - lo, height: size.height)
                share = Double((lo + hi) / 2 / max(size.width, 1))
            } else {
                let lo = max(0, fold.minY), hi = min(size.height, fold.maxY)
                first = CGRect(x: 0, y: 0, width: size.width, height: lo)
                second = CGRect(x: 0, y: hi, width: size.width, height: size.height - hi)
                gap = CGRect(x: 0, y: lo, width: size.width, height: hi - lo)
                share = Double((lo + hi) / 2 / max(size.height, 1))
            }
        } else {
            atFold = false
            share = ratio
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
    @Binding var frozen: [CGSize]?
    @State private var lastSnap: Double?

    var body: some View {
        let g = layout.gap
        ZStack {
            Rectangle().fill(Color(.separator).opacity(layout.atFold ? 0 : 0.6))
            // The grip: drag it to give one page more room, even on the fold. Long press: sizes and layouts, the
            // menu opening from the grip itself (not from the whole line, which slid the handle off to one side).
            Capsule()
                .fill(Brand.coral)
                .frame(width: layout.sideBySide ? 5 : 46, height: layout.sideBySide ? 46 : 5)
                .shadow(color: .black.opacity(0.25), radius: 2)
                .scaleEffect(frozen == nil ? 1 : 1.25)
                .padding(layout.sideBySide ? EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18) : EdgeInsets(top: 18, leading: 10, bottom: 18, trailing: 10))
                .contentShape(.contextMenuPreview, Capsule())
                .contextMenu {
            Section("Size") {
                Button("Half and Half", systemImage: "rectangle.split.1x2") { setRatio(0.5) }
                Button(LocalizedStringKey(layout.sideBySide ? "Left One Third" : "Top One Third"), systemImage: "rectangle.tophalf.inset.filled") { setRatio(1.0 / 3) }
                Button(LocalizedStringKey(layout.sideBySide ? "Left Two Thirds" : "Top Two Thirds"), systemImage: "rectangle.bottomhalf.inset.filled") { setRatio(2.0 / 3) }
                if !layout.sideBySide {
                    // Just tall enough for a 16:9 video across the width, the rest for the other page.
                    Button("Video Priority", systemImage: "play.rectangle") {
                        setRatio(min(0.7, max(0.2, Double(size.width * 9 / 16 + 8) / Double(max(size.height, 1)))))
                    }
                }
            }
            Button("Swap Panes", systemImage: "arrow.up.arrow.down") { browser.swap() }
            Button(LocalizedStringKey(layout.sideBySide ? "Top and Bottom" : "Side by Side"),
                   systemImage: layout.sideBySide ? "rectangle.split.1x2" : "rectangle.split.2x1") {
                browser.setAxis(layout.sideBySide ? .stacked : .sideBySide)
            }
            Button("One Page", systemImage: "rectangle") { browser.toggleSplit() }
            if browser.canSavePair {
                Button("Save as Pair", systemImage: "star") { browser.sheet = .savePair }
            }
        } preview: {
                    Capsule()
                        .fill(Brand.coral)
                        .frame(width: layout.sideBySide ? 8 : 64, height: layout.sideBySide ? 64 : 8)
                        .padding(18)
                        .background(.regularMaterial, in: Capsule())
                }
        }
        .frame(width: max(g.width, 1), height: max(g.height, 1))
        // Only the grip (and a finger's width around it) catches touches: the rest of the line leaves the pages'
        // edge swipes (back and forward) alone.
        .contentShape(Rectangle().size(width: layout.sideBySide ? max(g.width, 1) + 40 : 120,
                                       height: layout.sideBySide ? 120 : max(g.height, 1) + 40)
                        .offset(x: layout.sideBySide ? -20 : max(g.width, 1) / 2 - 60,
                                y: layout.sideBySide ? max(g.height, 1) / 2 - 60 : -20))
        .highPriorityGesture(drag)
        .onTapGesture(count: 2) {
            // Back to the fold (or half and half).
            withAnimation(.spring(response: 0.3)) {
                browser.ratio = 0.5
                browser.followsFold = true
            }
        }
        .position(x: g.midX, y: g.midY)
        .accessibilityLabel("Divider between the two pages")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: browser.ratio = min(0.8, browser.ratio + 0.1)
            case .decrement: browser.ratio = max(0.2, browser.ratio - 0.1)
            default: break
            }
        }
    }

    private func setRatio(_ r: Double) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            browser.followsFold = false
            browser.ratio = r
        }
    }

    private var drag: some Gesture {
        // Live: the pages follow the finger, measured in the panes' own space. Their web content keeps the size it
        // had when the handle was picked up (only cut, never laid out again), so it stays smooth; it settles into
        // its new size once, when the handle is let go.
        DragGesture(minimumDistance: 1, coordinateSpace: .named(PaneLayout.space))
            .onChanged { v in
                if frozen == nil {
                    frozen = [layout.first.size, layout.second.size]
                    withAnimation(.easeOut(duration: 0.12)) { browser.resizing = true }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                let total = layout.sideBySide ? size.width : size.height
                let at = (layout.sideBySide ? v.location.x : v.location.y) / max(total, 1)
                var p = min(0.85, max(0.15, Double(at)))
                var snapped: Double?
                for snap in [1.0 / 3, 0.5, 2.0 / 3] where abs(p - snap) < 0.02 { p = snap; snapped = snap }
                if let snapped, snapped != lastSnap { UISelectionFeedbackGenerator().selectionChanged() }
                lastSnap = snapped
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    browser.followsFold = false
                    browser.ratio = p
                }
            }
            .onEnded { _ in
                frozen = nil
                // The page takes its new size under the veil, then the veil lifts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeInOut(duration: 0.22)) { browser.resizing = false }
                }
                lastSnap = nil
            }
    }
}

/// How much of each edge of a pane is under the system's bars (the status band, the home indicator).
struct PaneEdges: Equatable {
    var top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0
}

struct PaneView: View {
    @Environment(Browser.self) private var browser
    let index: Int
    let showsActiveMark: Bool
    var edges = PaneEdges()
    /// While the handle is dragged: the size this pane's page keeps.
    var frozenSize: CGSize? = nil

    var body: some View {
        let pane = browser.panes[index]
        ZStack(alignment: .top) {
            if let tab = pane.tab {
                WebHost(tab: tab, topInset: edges.top, cornerRadius: showsActiveMark ? 18 : 0, frozenSize: frozenSize)
                    .id(tab.id)
                if tab.isBlank {
                    StartPage(pane: index)
                        .clipShape(RoundedRectangle(cornerRadius: showsActiveMark ? 18 : 0, style: .continuous))
                }
                if tab.isPrivate && browser.privateLocked {
                    PrivateLockCover()
                        .clipShape(RoundedRectangle(cornerRadius: showsActiveMark ? 18 : 0, style: .continuous))
                }
                if pane.tool == .videoNotes {
                    VideoNotesPane(pane: index)
                        .clipShape(RoundedRectangle(cornerRadius: showsActiveMark ? 18 : 0, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if browser.resizing {
                    // Like iPhone and iPad split view while the divider moves: the page goes frosted behind its
                    // site's icon, and comes back sharp at its new size once the handle is let go. Nothing has to
                    // be laid out while the finger moves, so it stays perfectly smooth.
                    ResizeVeil(url: tab.savedURL, title: tab.displayTitle)
                        .clipShape(RoundedRectangle(cornerRadius: showsActiveMark ? 18 : 0, style: .continuous))
                        .transition(.opacity)
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
        .overlay(alignment: .bottom) {
            if let tab = pane.tab, tab.autoScrollSpeed > 0, pane.tool == nil {
                AutoScrollControls(tab: tab).padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let tab = pane.tab, pane.tool == nil, tab.mediaPlaying || tab.isMuted || tab.isFilled {
                MediaControls(tab: tab)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: pane.tab?.mediaPlaying)
        .overlay(alignment: .topLeading) {
            if showsActiveMark, let source = browser.linkSource {
                Label(source == index ? "Links from here" : "Links open here", systemImage: "link")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showsActiveMark {
                let isActive = browser.active == index
                let tint = pane.tab?.isPrivate == true ? Brand.coral : Brand.accent
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isActive ? tint : Color.primary.opacity(0.08), lineWidth: isActive ? 2.5 : 1)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.2), value: isActive)
            }
        }
        .padding(showsActiveMark ? 3 : 0)
        // The controls float over the active page, clear of the system's bars.
        .overlay(alignment: Library.shared.barAtTop ? .top : .bottom) {
            if browser.active == index && !browser.editingAddress && !browser.barHidden && !browser.overviewShown {
                FloatingBar()
                    .padding(Library.shared.barAtTop ? .top : .bottom,
                             (Library.shared.barAtTop ? edges.top : edges.bottom) + 10)
                    .padding(.leading, edges.left + 10)
                    .padding(.trailing, edges.right + 10)
                    .transition(.opacity)
            }
        }
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
    /// A light mint, for Pro.
    static let mint = Color(red: 0.42, green: 0.91, blue: 0.80)
}

/// The pane's own sound and video buttons, shown while something plays: cut this pane's sound (the other pane keeps
/// playing), and stretch the video over the whole pane.
struct MediaControls: View {
    @Environment(Browser.self) private var browser
    let tab: Tab

    var body: some View {
        HStack(spacing: 2) {
            Button { browser.toggleMute(tab) } label: {
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


/// The frosted cover over a page while the panes are being resized, with the site's icon in the middle.
private struct ResizeVeil: View {
    let url: URL?
    let title: String

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color(uiColor: .systemBackground).opacity(0.35))
            Group {
                if let url {
                    Initial(text: title, url: url, size: 64)
                } else {
                    Image(systemName: "safari").font(.system(size: 34, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .allowsHitTesting(false)
    }
}
