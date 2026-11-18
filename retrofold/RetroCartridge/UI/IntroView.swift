//
// IntroView.swift
// RetroCartridge
//
// The how-to-play intro: five short pages with pixel-art pictures, shown
// over everything the first time the app opens, on whichever display it
// opens on. It covers picking a cartridge, unfolding to play, the
// controls, ejecting, and the toolbar's customization. Closing it at any
// point counts as seen; Records opens it again. Hosted by
// `LibraryOverlays` (never as a sheet).
//

import SwiftUI

// MARK: - Pages

/// One page of the intro.
enum IntroPage: Int, CaseIterable, Identifiable {
    case welcome
    case unfold
    case controls
    case eject
    case customize

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return String(localized: "WELCOME")
        case .unfold: return String(localized: "UNFOLD TO PLAY")
        case .controls: return String(localized: "CONTROLS")
        case .eject: return String(localized: "EJECT")
        case .customize: return String(localized: "MAKE IT YOURS")
        }
    }

    var text: String {
        switch self {
        case .welcome:
            return String(localized: "RetroFold turns iPhone Duo into a handheld console. Pick a cartridge: swipe through them on the cover, or tap one on the shelf.")
        case .unfold:
            return String(localized: "Open the device and the cartridge goes in, with the screen on one side of the fold and the controls on the other. Fold it again to pause.")
        case .controls:
            return String(localized: "Play with the D-Pad and A / B. A starts a round, left and right on the title screen switch modes, and Start pauses. The pause menu changes the screen and the palette, and turns the music and the sound on or off.")
        case .eject:
            return String(localized: "Press Select to eject the cartridge. The screen powers off and the shelf comes back.")
        case .customize:
            return String(localized: "Skins, Screen and Labels in the toolbar restyle the console, the display and your cartridge art. Records keeps your scores and achievements.")
        }
    }

    /// The page's picture; the welcome page shows the selected cartridge instead.
    var art: PixelArt? {
        switch self {
        case .welcome: return nil
        case .unfold: return .introUnfold
        case .controls: return .introControls
        case .eject: return .introEject
        case .customize: return .introCustomize
        }
    }
}

// MARK: - View

struct IntroView: View {
    @Environment(AppState.self) private var appState
    @Environment(StoreManager.self) private var storeManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(PostureManager.self) private var postureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuTheme) private var menuTheme

    @State private var page: IntroPage = .welcome
    /// Whether the last page change went forward, for the slide's direction.
    @State private var isMovingForward = true

    var body: some View {
        OverlayPanel(
            title: "HOW TO PLAY",
            subtitle: "RETROFOLD",
            onClose: finish
        ) {
            pageContent
                .id(page)
                .transition(pageTransition)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(swipe)
        } footer: {
            // Outside the scrolling page, so Next is always in view, even on
            // the short cover display or with large text
            VStack(spacing: 14) {
                pageDots
                controls
            }
        }
    }

    // MARK: - Page

    /// The picture above the text; beside it on the cover display, which
    /// is too short to stack them.
    @ViewBuilder
    private var pageContent: some View {
        if postureManager.isCompactWidth {
            HStack(alignment: .top, spacing: 20) {
                picture(side: 88)
                pageText(alignment: .leading)
            }
        } else {
            VStack(spacing: 16) {
                picture(side: 112)
                pageText(alignment: .center)
            }
        }
    }

    private func pageText(alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .leading ? .leading : .center

        return VStack(alignment: alignment, spacing: 10) {
            Text(page.title)
                .retroFont(18, weight: .black)
                .tracking(2.5)
                .foregroundStyle(menuTheme.accent)
                .multilineTextAlignment(textAlignment)
            Text(page.text)
                .retroFont(13, weight: .medium)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: Alignment(horizontal: alignment, vertical: .center))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(localized: "Page \(page.rawValue + 1) of \(IntroPage.allCases.count)"))
    }

    private func picture(side: CGFloat) -> some View {
        picture
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var picture: some View {
        if let art = page.art {
            PixelArtView(art: art, palette: .intro)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        } else {
            CartridgeView(game: appState.selectedGameType)
                .aspectRatio(CartridgeView.aspectRatio, contentMode: .fit)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// Swiping sideways turns the page, like a book.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -40 {
                    turn(by: 1)
                } else if value.translation.width > 40 {
                    turn(by: -1)
                }
            }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(IntroPage.allCases) { dot in
                Capsule()
                    .fill(dot == page ? menuTheme.accent : Color.white.opacity(0.2))
                    .frame(width: dot == page ? 18 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
    }

    // MARK: - Controls

    private var isLastPage: Bool {
        page == IntroPage.allCases.last
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if page != .welcome {
                Button {
                    turn(by: -1)
                } label: {
                    RetroCapsuleLabel(title: String(localized: "BACK"), systemImage: "chevron.left", tint: .white.opacity(0.8))
                }
                .buttonStyle(CartridgePressStyle())
            }

            Spacer(minLength: 0)

            Button {
                if isLastPage {
                    play()
                } else {
                    turn(by: 1)
                }
            } label: {
                RetroCapsuleLabel(
                    title: isLastPage ? String(localized: "LET'S PLAY") : String(localized: "NEXT"),
                    systemImage: isLastPage ? "play.fill" : "chevron.right",
                    tint: menuTheme.accent,
                    filled: true
                )
            }
            .buttonStyle(CartridgePressStyle())
        }
    }

    // MARK: - Actions

    private func turn(by step: Int) {
        guard let next = IntroPage(rawValue: page.rawValue + step) else { return }
        hapticManager.playHaptic(.buttonPress)
        isMovingForward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.9)) {
            page = next
        }
    }

    /// Closes the intro; on the inner display it also inserts the selected
    /// cartridge, since unfolding didn't while the intro was showing.
    private func play() {
        hapticManager.playHaptic(.buttonPress)
        let selected = appState.selectedGameType
        let insertsCartridge = !postureManager.isCompactWidth && storeManager.isUnlocked(selected)
        withAnimation(LibraryOverlays.animation) {
            appState.finishIntro()
        }
        if insertsCartridge {
            hapticManager.playHaptic(.cartridgeInsert)
            appState.startGame(type: selected)
        }
    }

    private func finish() {
        withAnimation(LibraryOverlays.animation) {
            appState.finishIntro()
        }
    }
}

// MARK: - Pictures

extension GamePalette {
    /// The intro pictures' colors, matching the overlays.
    static let intro = GamePalette(
        background: Color(hex: "#101418"),
        guide: Color(hex: "#8A9099"),          // hinge, frames, cartridge shell
        player: Color(hex: "#4A5058"),         // console body
        playerHighlight: Color(hex: "#9CFFB8"), // screen glow
        pickup: Color(hex: "#FF6B6B"),         // cartridge label
        pickupAlt: Color(hex: "#FFD166"),
        hazard: Color(hex: "#FF4D6D"),         // buttons, the heart
        hazardAlt: Color(hex: "#FFD166"),      // pencil
        outline: .black,
        spectrum: [Color(hex: "#FF6B6B"), Color(hex: "#FFD166"), Color(hex: "#9CFFB8"), Color(hex: "#4D9DE0"), Color(hex: "#C77DFF")]
    )
}

extension PixelArt {
    /// The console unfolded: the screen above the hinge, the controls below.
    static let introUnfold = PixelArt(rows: [
        "................",
        ".PPPPPPPPPPPPPP.",
        ".PHHHHHHHHHHHHP.",
        ".PHHHHHHHHHHHHP.",
        ".PHHHWHHHHHHHHP.",
        ".PHHHHHHHHHHHHP.",
        ".PHHHHHHHHHHHHP.",
        ".PPPPPPPPPPPPPP.",
        "GGGGGGGGGGGGGGGG",
        ".PPPPPPPPPPPPPP.",
        ".PP.PPPPPPPPPPP.",
        ".P...PPPPPXPPPP.",
        ".PP.PPPPPPPPXPP.",
        ".PPPPPPPPPPPPPP.",
        ".PPPPPGGPGGPPPP.",
        ".PPPPPPPPPPPPPP."
    ])

    /// The D-Pad, A and B, and Select and Start.
    static let introControls = PixelArt(rows: [
        "................",
        "................",
        "...GGG..........",
        "...GGG......XX..",
        "...GGG.....XXXX.",
        "GGGGGGGGG..XXXX.",
        "GGGGGGGGG...XX..",
        "GGGGGGGGG.......",
        "...GGG...XX.....",
        "...GGG..XXXX....",
        "...GGG..XXXX....",
        ".........XX.....",
        "................",
        "....WWW..WWW....",
        "................",
        "................"
    ])

    /// A cartridge popping up out of the slot.
    static let introEject = PixelArt(rows: [
        ".......W........",
        "......WWW.......",
        ".....WWWWW......",
        ".......W........",
        ".......W........",
        "................",
        "...GGGGGGGG.....",
        "...GGGGGGGGG....",
        "...GFFFFFFFG....",
        "...GFFHHFFFG....",
        "...GFFHHFFFG....",
        "...GFFFFFFFG....",
        "...GGGGGGGGG....",
        "..PPPPPPPPPPP...",
        "..P.........P...",
        "..PPPPPPPPPPP..."
    ])

    /// A heart drawn on the label grid, the pencil and the palette.
    static let introCustomize = PixelArt(rows: [
        "................",
        ".GGGGGGGGGG...YY",
        ".G........G..YYY",
        ".G.XX.XX..G.YYY.",
        ".GXXXXXXX.GYYY..",
        ".GXXXXXXX.YYY...",
        ".G.XXXXX.WYY....",
        ".G..XXX..WG.....",
        ".G...X....G.....",
        ".G........G.....",
        ".GGGGGGGGGG.....",
        "................",
        "..0.1.2.3.4.....",
        "..0.1.2.3.4.....",
        "................",
        "................"
    ])
}
