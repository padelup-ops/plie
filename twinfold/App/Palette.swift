// Palette.swift — Twinfold
//
// The action palette: one round glass button that floats over the pages, anywhere you put it. Tap it and your
// actions open in a ring around it; or press and slide straight toward one, and it runs when you let go. Hold the
// button still for a moment to move it. The ring's actions and their order are yours (Settings).

import SwiftUI
import UIKit

enum PaletteAction: String, CaseIterable, Identifiable, Codable {
    case back, forward, reload, tabs, newTab, search, share, closeTab, split, swap, fullScreen
    case privateMode, reader, top, bookmarks, downloads, settings, newPrivateTab

    var id: String { rawValue }

    static let defaults: [PaletteAction] = [.back, .tabs, .newTab, .search, .forward, .split, .share, .closeTab]
    static let maximum = 8

    var title: LocalizedStringKey {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .reload: return "Reload"
        case .tabs: return "Tabs"
        case .newTab: return "New Tab"
        case .search: return "Search or Address"
        case .share: return "Share"
        case .closeTab: return "Close Tab"
        case .split: return "One or Two Pages"
        case .swap: return "Swap Panes"
        case .fullScreen: return "This Page Full Screen"
        case .privateMode: return "Normal ⇄ Private"
        case .reader: return "Reader View"
        case .top: return "Scroll to Top"
        case .bookmarks: return "Bookmarks"
        case .downloads: return "Downloads"
        case .settings: return "Settings"
        case .newPrivateTab: return "New Private Tab"
        }
    }

    /// The short name under the icon in the ring.
    var short: LocalizedStringKey {
        switch self {
        case .search: return "Search"
        case .split: return "Pages"
        case .fullScreen: return "Full Screen"
        case .privateMode: return "Private"
        case .top: return "Top"
        case .closeTab: return "Close"
        case .newPrivateTab: return "Private Tab"
        case .reader: return "Reader"
        case .swap: return "Swap"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .reload: return "arrow.clockwise"
        case .tabs: return "square.on.square"
        case .newTab: return "plus.square"
        case .search: return "magnifyingglass"
        case .share: return "square.and.arrow.up"
        case .closeTab: return "xmark.square"
        case .split: return "rectangle.split.1x2"
        case .swap: return "arrow.up.arrow.down"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .privateMode: return "eye.slash"
        case .reader: return "doc.plaintext"
        case .top: return "arrow.up.to.line"
        case .bookmarks: return "book"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .newPrivateTab: return "plus.square.dashed"
        }
    }

    @MainActor
    func run(_ browser: Browser) {
        let tab = browser.activeTab
        switch self {
        case .back: tab?.webView.goBack()
        case .forward: tab?.webView.goForward()
        case .reload: tab?.webView.reload()
        case .tabs: browser.showOverview()
        case .newTab: browser.newTab()
        case .search: withAnimation(.spring(response: 0.35)) { browser.editingAddress = true }
        case .share:
            if let url = tab?.url, tab?.isBlank == false { Sharing.present([url]) }
        case .closeTab: browser.perform(.closeTab)
        case .split: browser.perform(.toggleSplit)
        case .swap: browser.perform(.swapPanes)
        case .fullScreen: browser.perform(.maximize)
        case .privateMode: browser.perform(.togglePrivate)
        case .reader: browser.perform(.reader)
        case .top: browser.perform(.scrollToTop)
        case .bookmarks: browser.sheet = .library
        case .downloads: browser.sheet = .downloads
        case .settings: browser.sheet = .settings
        case .newPrivateTab: browser.perform(.newPrivateTab)
        }
    }

    @MainActor
    func isEnabled(_ browser: Browser) -> Bool {
        let tab = browser.activeTab
        switch self {
        case .back: return tab?.canGoBack == true
        case .forward: return tab?.canGoForward == true
        case .share: return tab?.isBlank == false
        default: return true
        }
    }
}

/// The system share sheet, from anywhere.
@MainActor
enum Sharing {
    static func present(_ items: [Any]) {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?
            .keyWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
    }
}

extension Library {
    /// The palette's actions, in their order around the ring.
    var paletteActions: [PaletteAction] {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: "paletteActions") ?? []
            let list = raw.compactMap(PaletteAction.init(rawValue:))
            return list.isEmpty ? PaletteAction.defaults : list
        }
        set { UserDefaults.standard.set(newValue.prefix(PaletteAction.maximum).map(\.rawValue), forKey: "paletteActions") }
    }
}

// MARK: - The floating button and its ring

struct ActionPalette: View {
    @Environment(Browser.self) private var browser
    let area: CGSize
    /// The screen's safe edges: the button never sits under the status band, the camera or the home indicator.
    var insets: UIEdgeInsets = .zero

    @State private var open = false
    @State private var highlighted: Int?
    @State private var moving = false
    @State private var dragStart: Date?
    @State private var movedFar = false
    @State private var position: CGPoint = ActionPalette.savedPosition()
    @State private var dragOffset: CGSize = .zero
    @State private var actions: [PaletteAction] = Library.shared.paletteActions

    private let button: CGFloat = 54
    private let radius: CGFloat = 92
    private let item: CGFloat = 50

    var body: some View {
        let center = buttonCenter
        let ring = ringCenter(for: center)
        ZStack(alignment: .topLeading) {
            if open {
                // A touch anywhere else closes it.
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .transition(.opacity)
                ringView(at: ring)
            }
            if moving {
                // While it's being moved: drop it here to hide it (it comes back from the menu or Settings).
                hideTarget
                    .position(hideSpot)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            core
                .position(center)
                .opacity(moving && overHide ? 0.5 : 1)
        }
        .frame(width: area.width, height: area.height)
        .onAppear { actions = Library.shared.paletteActions }
        .onChange(of: open) { _, o in if o { actions = Library.shared.paletteActions } }
    }

    // MARK: Geometry

    private var buttonCenter: CGPoint {
        let p = CGPoint(x: position.x * area.width + dragOffset.width, y: position.y * area.height + dragOffset.height)
        return clamp(p, margin: button / 2 + 6)
    }

    /// The ring moves inward when the button sits near an edge, so every action stays on screen.
    private func ringCenter(for c: CGPoint) -> CGPoint {
        clamp(c, margin: radius + item / 2 + 8)
    }

    private func clamp(_ p: CGPoint, margin: CGFloat) -> CGPoint {
        let l = insets.left + margin, r = area.width - insets.right - margin
        let t = insets.top + margin, b = area.height - insets.bottom - margin
        return CGPoint(x: min(max(p.x, l), max(r, l)), y: min(max(p.y, t), max(b, t)))
    }

    private func angle(_ i: Int) -> Double {
        -Double.pi / 2 + Double(i) / Double(max(actions.count, 1)) * 2 * .pi
    }

    private func spot(_ i: Int, around c: CGPoint) -> CGPoint {
        CGPoint(x: c.x + radius * cos(angle(i)), y: c.y + radius * sin(angle(i)))
    }

    /// The action in the finger's direction, once it's left the middle.
    private func index(toward p: CGPoint, from c: CGPoint) -> Int? {
        let dx = p.x - c.x, dy = p.y - c.y
        guard hypot(dx, dy) > 34, !actions.isEmpty else { return nil }
        var a = atan2(dy, dx) + .pi / 2
        if a < 0 { a += 2 * .pi }
        let step = 2 * Double.pi / Double(actions.count)
        return Int((a + step / 2) / step) % actions.count
    }

    // MARK: Hiding

    private var hideSpot: CGPoint { CGPoint(x: area.width / 2, y: area.height - insets.bottom - 56) }
    private var overHide: Bool { hypot(buttonCenter.x - hideSpot.x, buttonCenter.y - hideSpot.y) < 56 }

    private var hideTarget: some View {
        VStack(spacing: 4) {
            Image(systemName: "eye.slash")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 58, height: 58)
                .glassEffect(overHide ? .regular.tint(Brand.coral) : .regular, in: .circle)
                .scaleEffect(overHide ? 1.15 : 1)
            Text("Hide").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(overHide ? Color.white : Color.primary)
        .animation(.snappy(duration: 0.15), value: overHide)
        .allowsHitTesting(false)
    }

    // MARK: Views

    private var core: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35)).glassEffect(.regular.interactive(), in: .circle)
            if open {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Concentric rings, like a floating control button: easy to spot, nothing to read.
                Circle().stroke(.white.opacity(0.35), lineWidth: 2).frame(width: 34, height: 34)
                Circle().stroke(.white.opacity(0.6), lineWidth: 2).frame(width: 24, height: 24)
                Circle().fill(.white.opacity(0.95)).frame(width: 15, height: 15)
            }
        }
        .frame(width: button, height: button)
        .scaleEffect(moving ? 1.15 : 1)
        .shadow(color: .black.opacity(moving ? 0.28 : 0.15), radius: moving ? 14 : 8, y: 4)
        .opacity(open || moving ? 1 : 0.88)
        .gesture(press)
        .accessibilityElement()
        .accessibilityLabel(Text("Action Palette"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { open.toggle() } }
        .accessibilityActions {
            ForEach(actions) { a in Button(a.title) { a.run(browser) } }
        }
    }

    private func ringView(at c: CGPoint) -> some View {
        let names = Library.shared.paletteNames
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: .circle)
                .frame(width: (radius + item / 2 + 10) * 2, height: (radius + item / 2 + 10) * 2)
                .position(c)
                .allowsHitTesting(false)
            ForEach(Array(actions.enumerated()), id: \.element) { i, a in
                let on = highlighted == i
                let enabled = a.isEnabled(browser)
                Button { run(a) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: a.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 34)
                        if names {
                            Text(a.short).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: item + 10, height: item)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? AnyShapeStyle(Brand.accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .scaleEffect(on ? 1.14 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.35)
                .position(spot(i, around: c))
                .accessibilityLabel(Text(a.title))
            }
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    // MARK: The one gesture: tap, slide to an action, or hold to move

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(PaneLayout.space))
            .onChanged { v in
                let now = Date()
                if dragStart == nil {
                    dragStart = now
                    movedFar = false
                    // Held still: the button lifts and can be moved.
                    let started = now
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        if dragStart == started, !movedFar, !open {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.25)) { moving = true }
                        }
                    }
                }
                let dist = hypot(v.translation.width, v.translation.height)
                if moving {
                    dragOffset = v.translation
                    return
                }
                if dist > 10 && !movedFar {
                    movedFar = true
                    if !open {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { open = true }
                    }
                }
                if movedFar {
                    let ring = ringCenter(for: buttonCenter)
                    let i = index(toward: v.location, from: ring)
                    if i != highlighted {
                        if i != nil { UISelectionFeedbackGenerator().selectionChanged() }
                        withAnimation(.snappy(duration: 0.15)) { highlighted = i }
                    }
                }
            }
            .onEnded { v in
                defer { dragStart = nil; movedFar = false }
                if moving, overHide {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3)) {
                        moving = false
                        dragOffset = .zero
                        Library.shared.palette = false
                    }
                    browser.flash(String(localized: "Palette hidden. Bring it back from the ⋯ menu."))
                    return
                }
                if moving {
                    let c = clamp(CGPoint(x: position.x * area.width + v.translation.width,
                                          y: position.y * area.height + v.translation.height), margin: button / 2 + 6)
                    // Settles against the nearest side edge.
                    let x = c.x < area.width / 2 ? insets.left + button / 2 + 10 : area.width - insets.right - button / 2 - 10
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        position = CGPoint(x: x / max(area.width, 1), y: c.y / max(area.height, 1))
                        dragOffset = .zero
                        moving = false
                    }
                    Self.save(position)
                    return
                }
                if movedFar {
                    // Slid: what's under the finger runs; nothing chosen leaves the ring open.
                    if let i = highlighted, actions.indices.contains(i), actions[i].isEnabled(browser) {
                        run(actions[i])
                    }
                    highlighted = nil
                    return
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { open.toggle() }
            }
    }

    private func run(_ a: PaletteAction) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        close()
        a.run(browser)
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            open = false
            highlighted = nil
        }
    }

    // MARK: Where it sits (kept as a share of the screen, so it survives turning and folding)

    private static func savedPosition() -> CGPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: "palette.x") != nil else { return CGPoint(x: 0.88, y: 0.72) }
        return CGPoint(x: d.double(forKey: "palette.x"), y: d.double(forKey: "palette.y"))
    }

    private static func save(_ p: CGPoint) {
        UserDefaults.standard.set(p.x, forKey: "palette.x")
        UserDefaults.standard.set(p.y, forKey: "palette.y")
    }
}

// MARK: - Settings: which actions, in which order

struct PaletteSettings: View {
    @State private var chosen = Library.shared.paletteActions
    @State private var editMode: EditMode = .active

    var body: some View {
        @Bindable var lib = Library.shared
        List {
            Section {
                Toggle("Floating Palette Button", isOn: $lib.palette)
                Toggle("Names Under the Actions", isOn: $lib.paletteNames)
            } footer: {
                Text("Tap the round button: your actions open around it. Or press and slide toward one: it runs when you let go. Hold the button still to move it, or drop it on “Hide” at the bottom.")
            }
            Section {
                ForEach(chosen) { a in
                    Label { Text(a.title) } icon: { Image(systemName: a.symbol).foregroundStyle(Brand.accent) }
                }
                .onMove { chosen.move(fromOffsets: $0, toOffset: $1); save() }
                .onDelete { chosen.remove(atOffsets: $0); save() }
            } header: {
                Text("In the Ring (\(chosen.count)/\(PaletteAction.maximum))")
            }
            Section {
                ForEach(PaletteAction.allCases.filter { !chosen.contains($0) }) { a in
                    Button {
                        guard chosen.count < PaletteAction.maximum else { return }
                        withAnimation { chosen.append(a) }
                        save()
                    } label: {
                        Label { Text(a.title).foregroundStyle(.primary) } icon: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(chosen.count < PaletteAction.maximum ? Color.green : Color.secondary)
                        }
                    }
                    .disabled(chosen.count >= PaletteAction.maximum)
                }
            } header: {
                Text("More Actions")
            }
            Section {
                Button("Back to the Usual Actions") { chosen = PaletteAction.defaults; save() }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Action Palette")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() { Library.shared.paletteActions = chosen }
}
