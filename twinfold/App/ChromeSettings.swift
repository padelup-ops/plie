// ChromeSettings.swift — Twinfold
//
// Where the bars and the rail sit, and which Home Screen icon Twinfold wears.

import SwiftUI
import UIKit

struct LayoutSettings: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var lib = Library.shared
        Form {
            Section {
                Picker("Address Bar, Page 1", selection: $lib.addressTop0) {
                    Text("Bottom").tag(false)
                    Text("Top").tag(true)
                }
                Picker("Address Bar, Page 2", selection: $lib.addressTop1) {
                    Text("Bottom").tag(false)
                    Text("Top").tag(true)
                }
                Toggle("Tab Bar on Each Page", isOn: $lib.showPaneTabs)
                if lib.showPaneTabs {
                    Picker("Tab Bar, Page 1", selection: $lib.tabTop0) {
                        Text("Bottom").tag(false)
                        Text("Top").tag(true)
                    }
                    Picker("Tab Bar, Page 2", selection: $lib.tabTop1) {
                        Text("Bottom").tag(false)
                        Text("Top").tag(true)
                    }
                }
            } header: {
                Text("Bars")
            } footer: {
                Text("Page 1 is the top page, or the left page when the two pages sit side by side. Switching tabs keeps both pages open.")
            }
            Section {
                Toggle("Side Bars with Tabs and Buttons", isOn: $lib.sideDock)
                if lib.sideDock {
                    Picker("Tabs and Buttons", selection: $lib.dockTogether) {
                        Text("Together on One Side").tag(true)
                        Text("Split on Both Sides").tag(false)
                    }
                    Toggle("Dock Follows Your Hand", isOn: $lib.dockFollowsHand)
                    Picker("Rail Side", selection: Binding(get: { browser.dockOnRight }, set: { value in
                        browser.dockOnRight = value
                        lib.dockRight = value
                        lib.dockFollowsHand = false
                    })) {
                        Text("Left").tag(false)
                        Text("Right").tag(true)
                    }
                    Picker("Rail Width", selection: $lib.railWidth) {
                        ForEach(RailWidth.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Rail Icon Size", selection: $lib.railIconSize) {
                        ForEach(RailIconSize.allCases) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Side Rail")
            } footer: {
                Text("Double tap the dock's handle to move it to the other side. The rail tucks away when you turn the device, so it doesn't get stuck between the pages.")
            }
        }
        .navigationTitle("Bars and Rail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum AppIconChoice: String, CaseIterable, Identifiable {
    case duo, night, split, mint, fold
    var id: String { rawValue }

    /// nil is the primary icon.
    var alternateName: String? {
        switch self {
        case .duo: return nil
        case .night: return "AppIconNight"
        case .split: return "AppIconSplit"
        case .mint: return "AppIconMint"
        case .fold: return "AppIconFold"
        }
    }

    var pro: Bool { self != .duo }

    var title: LocalizedStringKey {
        switch self {
        case .duo: return "Two Screens"
        case .night: return "Night"
        case .split: return "Split Tone"
        case .mint: return "Mint"
        case .fold: return "Fold"
        }
    }

    static var current: AppIconChoice {
        switch UIApplication.shared.alternateIconName {
        case "AppIconNight": return .night
        case "AppIconSplit": return .split
        case "AppIconMint": return .mint
        case "AppIconFold": return .fold
        default: return .duo
        }
    }

    @MainActor
    func apply(_ done: @escaping (AppIconChoice) -> Void) {
        if pro && !Store.shared.isPro {
            Store.shared.gate(.icons) {}
            return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
            Browser.shared.flash(String(localized: "This device can't change the icon."))
            return
        }
        UIApplication.shared.setAlternateIconName(alternateName) { error in
            Task { @MainActor in
                if let error {
                    Browser.shared.flash(error.localizedDescription)
                } else {
                    done(self)
                }
            }
        }
    }
}

struct IconSettings: View {
    @State private var selected = AppIconChoice.current

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 14)], spacing: 16) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button {
                            choice.apply { selected = $0 }
                        } label: {
                            VStack(spacing: 6) {
                                IconMark(choice: choice)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(selected == choice ? Brand.accent : Color.clear, lineWidth: 3)
                                    }
                                Text(choice.title).font(.caption2).foregroundStyle(.primary).lineLimit(1)
                                if choice.pro && !Store.shared.isPro {
                                    Image(systemName: "crown.fill").font(.caption2).foregroundStyle(Brand.mint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Choose the icon on your Home Screen. Two Screens is included. The other four are part of Twinfold Pro.")
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small drawing of each icon, the same two screens as the Home Screen artwork.
struct IconMark: View {
    let choice: AppIconChoice

    var body: some View {
        ZStack {
            background
            VStack(spacing: 4) {
                screen
                Capsule().fill(hinge).frame(width: 16, height: 4)
                screen
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch choice {
        case .duo:
            Brand.accent
        case .night:
            Color(red: 0.06, green: 0.09, blue: 0.11)
        case .split:
            HStack(spacing: 0) {
                Brand.accent
                Brand.coral
            }
        case .mint:
            Brand.mint
        case .fold:
            Color(red: 0.03, green: 0.19, blue: 0.24)
        }
    }

    private var hinge: Color {
        switch choice {
        case .duo, .mint: return Brand.coral
        case .night: return Brand.mint
        case .split: return Brand.ink
        case .fold: return .white
        }
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(screenFill)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(bar)
                    .frame(height: 4)
                    .padding(.horizontal, 6)
                    .padding(.top, 5)
            }
            .frame(height: 18)
            .overlay {
                if choice == .night {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.mint, lineWidth: 1)
                }
            }
    }

    private var screenFill: Color {
        switch choice {
        case .duo, .split: return .white
        case .night: return Color(red: 0.05, green: 0.16, blue: 0.17)
        case .mint, .fold: return choice == .mint ? Brand.ink : Color(red: 0.93, green: 0.98, blue: 0.97)
        }
    }

    private var bar: Color {
        switch choice {
        case .duo, .mint: return Brand.coral
        case .night, .fold: return choice == .night ? Brand.mint : Brand.accent
        case .split: return Brand.ink
        }
    }
}
