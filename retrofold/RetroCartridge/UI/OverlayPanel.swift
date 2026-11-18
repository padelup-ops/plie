//
// OverlayPanel.swift
// RetroCartridge
//
// Chrome shared by the in-hierarchy overlays (skin picker, screen settings,
// records, label designer, store).
//
// These are in-hierarchy panels rather than sheets, so they keep the console's
// retro look and sit inside whichever display layout hosts them.
//

import SwiftUI

/// Fixed colors for the overlay screens: they keep their meaning whatever
/// the skin. Everything else comes from `MenuTheme`.
enum RetroPalette {
    /// Warning amber for locked items and connection problems.
    static let amber = Color(hex: "#FFC857")
    /// Error red, matching the Brick Breaker cartridge.
    static let alert = Color(hex: "#FF6B6B")
}

// MARK: - Menu theme

/// The overlay colors that follow the equipped skin: a dark panel tone and
/// an accent picked to stay readable on it (the skin's own colors are often
/// too dark). The library and cover around the panels are the skin's case
/// itself (`consoleTheme`). Amber and alert red keep their meaning and
/// never change.
struct MenuTheme: Equatable, Sendable {
    /// Highlights, selections, capsules and filled buttons.
    var accent: Color
    /// The overlay panels' vertical gradient.
    var panelTop: Color
    var panelBottom: Color
    /// A handheld case drawn around each panel, or none.
    var shell: MenuShell? = nil

    /// The default, for Classic Grey: the original handheld's green LCD.
    /// The lightest of its four greens is the accent, on its darkest green
    /// (the same shades as the DMG Green game palette).
    /// Each panel sits in the grey case like the handheld's screen.
    static let classic: MenuTheme = {
        var theme = MenuTheme(accent: "#9BBC0F", panel: ("#143C16", "#0A240C"))
        theme.shell = .greyCase
        return theme
    }()

    /// A theme from hex values: the panel tone goes top to bottom.
    init(accent: String, panel: (String, String)) {
        self.accent = Color(hex: accent)
        self.panelTop = Color(hex: panel.0)
        self.panelBottom = Color(hex: panel.1)
    }
}

/// Case details around an overlay panel: the grey plastic with its big
/// bottom-trailing corner, the two stripes over the screen and the power LED.
struct MenuShell: Equatable, Sendable {
    var caseTop: Color
    var caseBottom: Color
    var stripes: [Color]
    var led: Color

    /// The original handheld: warm grey plastic, magenta and navy stripes,
    /// red LED.
    static let greyCase = MenuShell(
        caseTop: Color(hex: "#BDBCB6"),
        caseBottom: Color(hex: "#9A9994"),
        stripes: [Color(hex: "#A8325E"), Color(hex: "#2B2F7A")],
        led: Color(hex: "#E0301E")
    )

    /// Gap between the case edge and the screen.
    static let margin: CGFloat = 12
    /// The case corners: the bottom-trailing one is the handheld's big curve.
    static let caseShape = UnevenRoundedRectangle(
        topLeadingRadius: 26, bottomLeadingRadius: 26, bottomTrailingRadius: 72, topTrailingRadius: 26,
        style: .continuous
    )
    /// The screen inside the case follows the same curve, inset.
    static let screenShape = UnevenRoundedRectangle(
        topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 60, topTrailingRadius: 16,
        style: .continuous
    )
}

extension EnvironmentValues {
    /// The equipped skin's overlay colors, set once by `AdaptiveConsoleLayout`.
    @Entry var menuTheme: MenuTheme = .classic
    /// The equipped skin itself: the library and cover are its case, and
    /// their text is its printed `textColor`. Set with `menuTheme`.
    @Entry var consoleTheme: SkinTheme = .classicGrey
}

extension AnyTransition {
    /// Panels rise slightly and fade in; they fall back and fade out.
    static var overlayPanel: AnyTransition {
        .opacity
            .combined(with: .offset(y: 36))
            .combined(with: .scale(scale: 0.97))
    }
}

/// Dimmed backdrop behind an overlay panel. Tapping it dismisses the panel.
struct OverlayBackdrop: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Nearly opaque with Reduce Transparency, so nothing shows through
        Color.black.opacity(reduceTransparency ? 0.92 : 0.62)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
    }
}

/// A dark, rounded console-accessory panel with a title bar and a close
/// button. Content that doesn't fit vertically scrolls; an optional footer
/// stays in view below it, for controls that must never scroll away.
struct OverlayPanel<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    @Environment(\.menuTheme) private var menuTheme

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            divider

            ViewThatFits(in: .vertical) {
                content
                    .padding(22)
                ScrollView {
                    content
                        .padding(22)
                }
                .scrollIndicators(.hidden)
            }

            if Footer.self != EmptyView.self {
                footer
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        }
        .background(
            screenShape.fill(
                LinearGradient(
                    colors: [menuTheme.panelTop, menuTheme.panelBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
        .clipShape(screenShape)
        .overlay(
            screenShape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.16), .white.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .modifier(ShellCase(shell: menuTheme.shell))
        .frame(maxWidth: 580)
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .avoidingOcclusion()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// The panel's own outline: a plain rounded rectangle, or the screen
    /// shape when it sits in a case.
    private var screenShape: AnyShape {
        menuTheme.shell == nil
            ? AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            : AnyShape(MenuShell.screenShape)
    }

    /// The line under the header, or the case's two stripes.
    @ViewBuilder
    private var divider: some View {
        if let shell = menuTheme.shell {
            VStack(spacing: 3) {
                ForEach(shell.stripes.indices, id: \.self) { index in
                    Rectangle()
                        .fill(shell.stripes[index])
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 22)
            .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var header: some View {
        // The case's power LED, or a dot in the accent
        let led = menuTheme.shell?.led ?? menuTheme.accent

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(led)
                        .frame(width: 7, height: 7)
                        .shadow(color: led.opacity(0.8), radius: 4)
                    Text(title)
                        .retroFont(20, weight: .black, maxScale: 1.5, wraps: false)
                        .tracking(3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(subtitle)
                    .retroFont(11, weight: .semibold)
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(CartridgePressStyle())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

/// Puts a panel in its handheld case when the theme has one.
private struct ShellCase: ViewModifier {
    let shell: MenuShell?

    func body(content: Content) -> some View {
        if let shell {
            content
                .padding(MenuShell.margin)
                .background(
                    MenuShell.caseShape.fill(
                        LinearGradient(colors: [shell.caseTop, shell.caseBottom], startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(
                    // Moulded edge: light on top, dark below
                    MenuShell.caseShape.stroke(
                        LinearGradient(colors: [.white.opacity(0.45), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
                )
        } else {
            content
        }
    }
}

extension OverlayPanel where Footer == EmptyView {
    /// A panel without a footer: everything scrolls together.
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, onClose: onClose, content: content) {
            EmptyView()
        }
    }
}

/// A capsule label used for statuses and small actions in the overlays.
struct RetroCapsuleLabel: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .white
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .retroFont(11, weight: .heavy, design: .default)
            }
            Text(title)
                .retroFont(12, weight: .heavy)
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(filled ? Color.black.opacity(0.85) : tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.08)))
        )
        .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.45), lineWidth: 1))
    }
}

// MARK: - Cards

extension View {
    /// Chrome for a selectable card in an overlay grid (skins, screens).
    func overlayCard(isSelected: Bool) -> some View {
        modifier(OverlayCard(isSelected: isSelected))
    }
}

/// The card chrome behind `overlayCard(isSelected:)`, outlined in the menu
/// accent when selected.
private struct OverlayCard: ViewModifier {
    let isSelected: Bool

    @Environment(\.menuTheme) private var menuTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return content
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Color.white.opacity(isSelected ? 0.07 : 0.035)))
            .overlay(
                shape.stroke(
                    isSelected ? menuTheme.accent : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .shadow(color: isSelected ? menuTheme.accent.opacity(0.25) : .clear, radius: 14)
            .contentShape(shape)
    }
}

/// Padlock badge drawn over locked items in the overlays.
struct OverlayLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.black.opacity(0.7)))
            .overlay(Circle().stroke(RetroPalette.amber.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }
}

// MARK: - Library overlays

/// Hosts the skin picker, screen settings, records, label designer, store and
/// intro as in-hierarchy overlays.
/// The store stacks above the others, and each backdrop tap closes only the
/// top panel.
struct LibraryOverlays: View {
    @Environment(AppState.self) private var appState
    
    /// When false, both overlays stay hidden, e.g. over a running console.
    var isEnabled: Bool = true
    
    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.86)
    
    var body: some View {
        let showsSkinPicker = isEnabled && appState.isSkinSelectorVisible
        let showsScreenSettings = isEnabled && appState.isScreenSettingsVisible
        let showsRecords = isEnabled && appState.isRecordsVisible
        let showsLabelDesigner = isEnabled && appState.isLabelDesignerVisible
        let showsStore = isEnabled && appState.isStoreVisible
        let showsIntro = isEnabled && appState.isIntroVisible
        
        ZStack {
            if showsSkinPicker {
                OverlayBackdrop { close(\.isSkinSelectorVisible) }
                    .transition(.opacity)
                    .zIndex(10)
                SkinPickerView()
                    .transition(.overlayPanel)
                    .zIndex(11)
            }
            
            if showsScreenSettings {
                OverlayBackdrop { close(\.isScreenSettingsVisible) }
                    .transition(.opacity)
                    .zIndex(10)
                ScreenSettingsView()
                    .transition(.overlayPanel)
                    .zIndex(11)
            }
            
            if showsRecords {
                OverlayBackdrop { close(\.isRecordsVisible) }
                    .transition(.opacity)
                    .zIndex(10)
                RecordsView()
                    .transition(.overlayPanel)
                    .zIndex(11)
            }
            
            if showsLabelDesigner {
                OverlayBackdrop { close(\.isLabelDesignerVisible) }
                    .transition(.opacity)
                    .zIndex(10)
                LabelDesignerView()
                    .transition(.overlayPanel)
                    .zIndex(11)
            }
            
            if showsStore {
                OverlayBackdrop { close(\.isStoreVisible) }
                    .transition(.opacity)
                    .zIndex(12)
                StoreView()
                    .transition(.overlayPanel)
                    .zIndex(13)
            }

            if showsIntro {
                OverlayBackdrop {
                    withAnimation(Self.animation) { appState.finishIntro() }
                }
                .transition(.opacity)
                .zIndex(14)
                IntroView()
                    .transition(.overlayPanel)
                    .zIndex(15)
            }
        }
        .animation(Self.animation, value: showsSkinPicker)
        .animation(Self.animation, value: showsScreenSettings)
        .animation(Self.animation, value: showsRecords)
        .animation(Self.animation, value: showsLabelDesigner)
        .animation(Self.animation, value: showsStore)
        .animation(Self.animation, value: showsIntro)
    }
    
    private func close(_ flag: ReferenceWritableKeyPath<AppState, Bool>) {
        withAnimation(Self.animation) {
            appState[keyPath: flag] = false
        }
    }
}
