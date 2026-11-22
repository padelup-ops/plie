// Everyday.swift — Twinfold
//
// What a daily browser needs, beyond two pages:
// • dark pages and your choice of font on every site,
// • private tabs locked with Face ID,
// • profiles: separate sign-ins (personal, work…), each with its own cookies,
// • tabs left unused fall asleep to free memory, and wake up with their history,
// • bookmarks, pairs and settings in iCloud, on all your devices,
// • a short tutorial on first launch.

import LocalAuthentication
import SwiftUI
import WebKit

// MARK: - Page style (dark pages, fonts)

enum PageFont: String, CaseIterable, Identifiable {
    case site, system, serif, rounded, mono
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .site: return "The Site's Own"
        case .system: return "System"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .mono: return "Monospaced"
        }
    }
    var css: String? {
        switch self {
        case .site: return nil
        case .system: return "-apple-system, system-ui, sans-serif"
        case .serif: return "ui-serif, 'New York', Georgia, serif"
        case .rounded: return "ui-rounded, 'SF Pro Rounded', -apple-system, sans-serif"
        case .mono: return "ui-monospace, Menlo, monospace"
        }
    }
}

@MainActor
final class PageStyle {
    static let shared = PageStyle()
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let views = NSHashTable<WKWebView>.weakObjects()

    func attach(_ webView: WKWebView) {
        views.add(webView)
        let c = webView.configuration.userContentController
        if !controllers.contains(c) {
            controllers.add(c)
            install(on: c)
        }
    }

    /// Settings changed: new pages get the new style, open pages change right away.
    func apply() {
        for c in controllers.allObjects { install(on: c) }
        for v in views.allObjects { v.evaluateJavaScript(Self.liveScript()) }
    }

    private func install(on c: WKUserContentController) {
        c.removeAllUserScripts()
        c.addUserScript(WKUserScript(source: MediaScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        c.addUserScript(WKUserScript(source: Self.liveScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// One <style> element, rewritten with the current settings.
    static func liveScript() -> String {
        let lib = Library.shared
        var css = ""
        if lib.darkPages {
            css += "html{filter:invert(.9) hue-rotate(180deg)!important;background:#fff!important}"
                + "img,video,picture,canvas,iframe,svg image,embed,object,[style*='background-image']{filter:invert(1) hue-rotate(180deg)!important}"
        }
        if let font = (Store.shared.isPro ? lib.pageFont : .site).css {
            css += "body,body *:not(code):not(pre):not(kbd):not(samp):not([class*='icon']):not([class*='Icon']):not([class*='material']):not(.fa):not([class^='fa-']){font-family:\(font)!important}"
        }
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        return """
        (function(){var id='__twinfold_style';var s=document.getElementById(id);
        if(!s){s=document.createElement('style');s.id=id;(document.head||document.documentElement).appendChild(s);}
        s.textContent=`\(escaped)`;})();
        """
    }
}

// MARK: - Private tabs locked with Face ID

extension Browser {
    /// Asks for Face ID (or the passcode) to see the private tabs again.
    func unlockPrivate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            privateLocked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock your private tabs")) { ok, _ in
            Task { @MainActor in if ok { withAnimation { self.privateLocked = false } } }
        }
    }

    /// The app went to the background: private tabs lock (when the setting is on).
    func lockPrivateIfNeeded() {
        guard Library.shared.lockPrivate else { return }
        if panes.contains(where: { $0.tabs.contains { $0.isPrivate } }) { privateLocked = true }
    }
}

struct PrivateLockCover: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                Image(systemName: "faceid").font(.system(size: 44, weight: .light)).foregroundStyle(Brand.coral)
                Text("Private tabs are locked").font(.headline)
                Button("Unlock") { browser.unlockPrivate() }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.coral)
            }
        }
    }
}

// MARK: - Profiles

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var hue: Double
}

extension Library {
    /// The data store of a profile (cookies, sign-ins, site data). No profile: the main one.
    static func dataStore(for profile: UUID?) -> WKWebsiteDataStore {
        guard let profile else { return .default() }
        return WKWebsiteDataStore(forIdentifier: profile)
    }

    func profile(_ id: UUID?) -> Profile? { id.flatMap { i in profiles.first { $0.id == i } } }
}

struct ProfilesSettings: View {
    @State private var newName = ""
    @State private var adding = false

    var body: some View {
        let lib = Library.shared
        List {
            Section {
                Label("Main", systemImage: "person.crop.circle.fill").foregroundStyle(.primary)
                ForEach(lib.profiles) { p in
                    Label { Text(p.name) } icon: { Circle().fill(Color(hue: p.hue, saturation: 0.6, brightness: 0.8)).frame(width: 18, height: 18) }
                }
                .onDelete { offsets in
                    for i in offsets { lib.deleteProfile(lib.profiles[i]) }
                }
            } footer: {
                Text("Each profile has its own cookies and sign-ins: two Google accounts, personal and work, side by side. Open a tab in a profile from the menu.")
            }
            Section {
                Button("Add a Profile", systemImage: "plus") { Store.shared.gate(.profiles) { adding = true } }
            }
        }
        .navigationTitle("Profiles")
        .alert("New Profile", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Add") { lib.addProfile(newName); newName = "" }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - Tabs that fall asleep

extension Browser {
    /// Tabs not on screen for 15 minutes give their memory back; they wake up, with their history, when shown.
    func sleepUnusedTabs() {
        let shown = Set(panes.compactMap { $0.tab.map(ObjectIdentifier.init) })
        let limit = Date().addingTimeInterval(-15 * 60)
        for p in panes {
            for t in p.tabs where !shown.contains(ObjectIdentifier(t)) && !t.isPrivate && !t.isAsleep && t.lastShown < limit && t.url != nil {
                t.sleep()
            }
        }
    }
}

// MARK: - iCloud

/// Bookmarks, pairs, pinned apps and settings follow the person's Apple Account (iCloud key-value storage).
@MainActor
enum CloudSync {
    private static var store: NSUbiquitousKeyValueStore { .default }

    static func start() {
        guard ShotMode.current == nil else { return }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { pull() }
        }
        store.synchronize()
        pull()
    }

    static func push() {
        guard ShotMode.current == nil, Library.shared.iCloudSync else { return }
        let lib = Library.shared
        if let d = try? JSONEncoder().encode(lib.bookmarks), d.count < 900_000 { store.set(d, forKey: "bookmarks") }
        if let d = try? JSONEncoder().encode(lib.pairs) { store.set(d, forKey: "pairs") }
        store.set(lib.dockApps.map(\.absoluteString), forKey: "dockApps")
        store.set(lib.searchEngine.rawValue, forKey: "searchEngine")
        store.set(Date().timeIntervalSince1970, forKey: "updated")
    }

    static func pull() {
        guard Library.shared.iCloudSync else { return }
        let lib = Library.shared
        let b = store.data(forKey: "bookmarks").flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) }
        let p = store.data(forKey: "pairs").flatMap { try? JSONDecoder().decode([Pair].self, from: $0) }
        let apps = (store.array(forKey: "dockApps") as? [String])?.compactMap(URL.init(string:))
        lib.mergeFromCloud(bookmarks: b, pairs: p, dockApps: apps)
    }
}

// MARK: - First launch

struct TutorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let steps: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("rectangle.split.1x2", "Two pages at once", "On iPhone Duo they meet at the fold. Anywhere else, the split button in the bubble shows two pages."),
        ("hand.tap", "Tap a page to make it active", "The bubble and the address act on the active page, outlined in colour."),
        ("arrow.up.and.down", "Drag the handle", "Give one page more room. Touch and hold it for sizes: half, a third, video priority."),
        ("hand.point.up.left", "Touch and hold a link", "Open it in the other pane. Or turn on Linked Panes: every link goes there."),
        ("square.on.square", "Save pairs", "Two pages you use together open in one tap, even from the Home Screen icon."),
        ("hand.draw", "Two-finger gestures", "Back, forward, a new tab… choose what each gesture does in Settings."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        Spacer()
                        Image(systemName: steps[i].0)
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(Brand.accent)
                            .frame(width: 120, height: 120)
                            .glassEffect(.regular, in: .circle)
                        Text(steps[i].1).font(.system(.title2, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
                        Text(steps[i].2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < steps.count - 1 { withAnimation { page += 1 } } else { dismiss() }
            } label: {
                Text(page < steps.count - 1 ? "Next" : "Start Browsing")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.accent)
            .padding(20)
        }
        .overlay(alignment: .topTrailing) {
            Button("Skip") { dismiss() }.padding(18)
        }
    }

    /// Once, on the first launch (never in screenshots).
    static func shouldShow() -> Bool {
        guard ShotMode.current == nil, !UserDefaults.standard.bool(forKey: "tutorialSeen") else { return false }
        UserDefaults.standard.set(true, forKey: "tutorialSeen")
        return true
    }
}

// MARK: - Asking AI about several tabs

extension Browser {
    /// The chosen tabs' pages, in one question, to the assistant in the other pane.
    func ask(_ assistant: Assistant, about tabs: [Tab]) {
        let lines = tabs.compactMap { t in t.url.map { "- \(t.title.isEmpty ? ($0.host() ?? "") : t.title): \($0.absoluteString)" } }
        guard !lines.isEmpty else { return }
        let prompt = String(localized: "Compare and summarize these pages, then tell me what matters most:") + "\n" + lines.joined(separator: "\n")
        let pane = otherIndex
        if let url = assistant.url(asking: prompt) {
            load(url, inPane: pane)
        } else {
            UIPasteboard.general.string = prompt
            load(assistant.home, inPane: pane)
            flash(String(localized: "Question copied: paste it in \(assistant.name)"))
        }
        if !isSplit { isSplit = true }
    }
}
