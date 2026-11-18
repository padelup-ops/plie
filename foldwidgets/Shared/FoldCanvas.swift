import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Colors for one theme. Wallpapers use these directly, never the system appearance.
struct Ink {
    var ground: Color
    var raised: Color
    var ink: Color
    var mute: Color
    var accent: Color

    static func resolve(_ settings: FoldSettings) -> Ink {
        switch settings.theme {
        case .diptych:
            return diptych[settings.palette.rawValue]
        case .mood:
            return moods[settings.mood] ?? editorial
        default:
            return editorial
        }
    }

    static let editorial = Ink(
        ground: Color(hex: 0x12141A),
        raised: Color(hex: 0x1C2230),
        ink: Color(hex: 0xF4EFE6),
        mute: Color(hex: 0xA39B90),
        accent: Color(hex: 0xE4C27A)
    )

    static let diptych: [Ink] = [
        Ink(ground: Color(hex: 0x12141A), raised: Color(hex: 0x1C2230), ink: Color(hex: 0xF4EFE6), mute: Color(hex: 0xB7A88A), accent: Color(hex: 0xE4C27A)),
        Ink(ground: Color(hex: 0x14161E), raised: Color(hex: 0x2C241C), ink: Color(hex: 0xF7F1E8), mute: Color(hex: 0xC4A48A), accent: Color(hex: 0xF2B48A)),
        Ink(ground: Color(hex: 0x0E1C22), raised: Color(hex: 0x16343A), ink: Color(hex: 0xE7F2F2), mute: Color(hex: 0xD9CDB4), accent: Color(hex: 0xE7D7B1)),
        Ink(ground: Color(hex: 0x241018), raised: Color(hex: 0x3A1824), ink: Color(hex: 0xFBEDE8), mute: Color(hex: 0xE7C2BA), accent: Color(hex: 0xF0C9C0))
    ]

    static let moods: [Mood: Ink] = [
        .calm: Ink(ground: Color(hex: 0x1B242C), raised: Color(hex: 0x2A3844), ink: Color(hex: 0xF3F6F8), mute: Color(hex: 0xC5D2DC), accent: Color(hex: 0x8AA4B5)),
        .joy: Ink(ground: Color(hex: 0x2A2112), raised: Color(hex: 0x3E3014), ink: Color(hex: 0xFFF8E8), mute: Color(hex: 0xF0D7A0), accent: Color(hex: 0xF2C14E)),
        .focus: Ink(ground: Color(hex: 0x14182A), raised: Color(hex: 0x222848), ink: Color(hex: 0xF4F5FF), mute: Color(hex: 0xC5CAF5), accent: Color(hex: 0x7C8CFF)),
        .tender: Ink(ground: Color(hex: 0x2A1820), raised: Color(hex: 0x422430), ink: Color(hex: 0xFFF5F7), mute: Color(hex: 0xF0C9D2), accent: Color(hex: 0xE7A0B0)),
        .storm: Ink(ground: Color(hex: 0x121418), raised: Color(hex: 0x22262E), ink: Color(hex: 0xF2F4F7), mute: Color(hex: 0xC5CAD3), accent: Color(hex: 0x8E97A8)),
        .wonder: Ink(ground: Color(hex: 0x1A1424), raised: Color(hex: 0x2C2140), ink: Color(hex: 0xF8F4FC), mute: Color(hex: 0xD9CCE8), accent: Color(hex: 0xC9A6E0))
    ]
}

/// How the picture is split. WidgetKit cannot see the hinge, so a widget
/// picks this from its family: small = cover, medium = two vertical panes,
/// large = the inner diptych.
enum CanvasMode: Equatable {
    case live
    case outer
    case inner
    case widget(PanelRole)
}

enum PanelRole: Equatable {
    case cover
    case pair
    case diptych
}

private struct Board {
    enum Axis { case none, horizontal, vertical }
    var size: CGSize
    var axis: Axis
    var gap: CGFloat

    var primary: CGRect {
        switch axis {
        case .none:
            return CGRect(origin: .zero, size: size)
        case .horizontal:
            let height = max(1, (size.height - gap) / 2)
            return CGRect(x: 0, y: 0, width: size.width, height: height)
        case .vertical:
            let width = max(1, (size.width - gap) / 2)
            return CGRect(x: 0, y: 0, width: width, height: size.height)
        }
    }

    var secondary: CGRect {
        switch axis {
        case .none:
            return .zero
        case .horizontal:
            let height = max(1, (size.height - gap) / 2)
            return CGRect(x: 0, y: height + gap, width: size.width, height: height)
        case .vertical:
            let width = max(1, (size.width - gap) / 2)
            return CGRect(x: width + gap, y: 0, width: width, height: size.height)
        }
    }
}

/// One drawing of a theme at an exact size. The parent chooses the size
/// (widget bounds, or the wallpaper pixel size) so export does not depend on GeometryReader.
struct FoldArtwork: View {
    var settings: FoldSettings
    var mode: CanvasMode
    var date: Date
    var openAmount: Double
    var size: CGSize

    private var ink: Ink { Ink.resolve(settings) }

    private var reveal: Double {
        switch mode {
        case .live:
            return min(1, max(0, openAmount))
        case .outer:
            return 0
        case .inner:
            return 1
        case .widget(let role):
            switch role {
            case .cover: return 0
            case .pair, .diptych: return 1
            }
        }
    }

    private var board: Board {
        let shortest = min(size.width, size.height)
        let axis: Board.Axis
        let gap: CGFloat
        switch mode {
        case .outer, .widget(.cover):
            axis = .none
            gap = 0
        case .inner:
            axis = .horizontal
            gap = shortest * 0.012
        case .widget(.pair):
            axis = .vertical
            gap = shortest * 0.03
        case .widget(.diptych):
            axis = size.width >= size.height ? .vertical : .horizontal
            gap = shortest * 0.02
        case .live:
            if openAmount < 0.04 {
                axis = .none
                gap = 0
            } else {
                axis = size.width > size.height ? .vertical : .horizontal
                gap = shortest * 0.012 * openAmount
            }
        }
        return Board(size: size, axis: axis, gap: gap)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [ink.raised, ink.ground], startPoint: .topLeading, endPoint: .bottomTrailing)
            themeBody
            if showsCoverHinge {
                Rectangle()
                    .fill(ink.accent.opacity(0.45))
                    .frame(width: max(2, size.width * 0.008), height: size.height)
                    .position(x: size.width * 0.018, y: size.height / 2)
            }
            if board.axis != .none {
                seam
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var showsCoverHinge: Bool {
        switch mode {
        case .outer, .widget(.cover):
            return true
        case .live:
            return openAmount < 0.04
        default:
            return false
        }
    }

    private var seam: some View {
        let thickness = max(1, board.gap == 0 ? size.width * 0.004 : board.gap)
        return Rectangle()
            .fill(ink.accent.opacity(0.55))
            .frame(
                width: board.axis == .vertical ? thickness : size.width,
                height: board.axis == .horizontal ? thickness : size.height
            )
            .position(x: size.width / 2, y: size.height / 2)
    }

    @ViewBuilder
    private var themeBody: some View {
        switch settings.theme {
        case .revelation: revelation
        case .hour: hour
        case .quote: quote
        case .diptych: diptych
        case .countdown: countdown
        case .mood: mood
        }
    }

    private func pane<V: View>(_ rect: CGRect, @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .position(x: rect.midX, y: rect.midY)
    }

    private func serif(_ rect: CGRect, _ factor: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: min(rect.width, rect.height) * factor, weight: weight, design: .serif)
    }

    private func rounded(_ rect: CGRect, _ factor: CGFloat, weight: Font.Weight = .thin) -> Font {
        .system(size: min(rect.width, rect.height) * factor, weight: weight, design: .rounded)
    }

    // MARK: Révélation

    private var revelation: some View {
        let word = settings.revelationDisplay
        let chars = Array(word)
        return ZStack {
            if board.axis == .none {
                pane(board.primary) {
                    VStack(spacing: board.primary.height * 0.04) {
                        Text(String(chars.first.map { String($0) } ?? " "))
                            .font(serif(board.primary, 0.46))
                            .foregroundStyle(ink.ink)
                            .minimumScaleFactor(0.2)
                            .lineLimit(1)
                        Text(String(repeating: "·", count: min(8, chars.count)))
                            .font(rounded(board.primary, 0.04, weight: .regular))
                            .foregroundStyle(ink.accent)
                            .tracking(6)
                    }
                }
            } else {
                let mid = max(1, chars.count / 2)
                pane(board.primary) {
                    Text(String(chars.prefix(mid)))
                        .font(serif(board.primary, 0.28))
                        .foregroundStyle(ink.ink)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                }
                pane(board.secondary) {
                    Text(String(chars.suffix(chars.count - mid)))
                        .font(serif(board.secondary, 0.28))
                        .foregroundStyle(ink.ink)
                        .opacity(reveal > 0.45 ? 1 : 0.2)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Heure

    private var hour: some View {
        let parts = settings.clockParts(at: date)
        return ZStack {
            if board.axis == .none {
                pane(board.primary) {
                    VStack(spacing: board.primary.height * 0.02) {
                        Text(parts.hour)
                            .font(rounded(board.primary, 0.34))
                            .foregroundStyle(ink.ink)
                            .monospacedDigit()
                        Rectangle().fill(ink.accent).frame(width: board.primary.width * 0.18, height: max(1, board.primary.height * 0.004))
                        Text(parts.minute)
                            .font(rounded(board.primary, 0.34))
                            .foregroundStyle(ink.mute)
                            .monospacedDigit()
                        Text(settings.dateLine(at: date))
                            .font(rounded(board.primary, 0.045, weight: .regular))
                            .foregroundStyle(ink.mute)
                    }
                }
            } else {
                pane(board.primary) {
                    Text(parts.hour)
                        .font(rounded(board.primary, 0.42))
                        .foregroundStyle(ink.ink)
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                pane(board.secondary) {
                    VStack(spacing: board.secondary.height * 0.04) {
                        Text(parts.minute)
                            .font(rounded(board.secondary, 0.42))
                            .foregroundStyle(ink.ink)
                            .monospacedDigit()
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                        Text(settings.dateLine(at: date))
                            .font(rounded(board.secondary, 0.07, weight: .regular))
                            .foregroundStyle(ink.mute)
                    }
                }
            }
        }
    }

    // MARK: Citation

    private var quote: some View {
        let quote = settings.resolvedQuote
        let french = settings.prefersFrench
        let halves = quote.halves(french: french)
        return ZStack {
            if board.axis == .none {
                pane(board.primary) {
                    VStack(alignment: .leading, spacing: board.primary.height * 0.03) {
                        Text("“")
                            .font(serif(board.primary, 0.22))
                            .foregroundStyle(ink.accent)
                        Text(halves.0.isEmpty ? quote.text(french: french) : halves.0)
                            .font(serif(board.primary, 0.075))
                            .foregroundStyle(ink.ink)
                            .minimumScaleFactor(0.5)
                            .lineLimit(4)
                        Text(quote.author(french: french))
                            .font(rounded(board.primary, 0.04, weight: .medium))
                            .foregroundStyle(ink.mute)
                            .tracking(1.5)
                    }
                    .padding(board.primary.width * 0.1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                pane(board.primary) {
                    VStack(alignment: .leading, spacing: board.primary.height * 0.04) {
                        Text("“")
                            .font(serif(board.primary, 0.16))
                            .foregroundStyle(ink.accent)
                        Text(halves.0)
                            .font(serif(board.primary, 0.09))
                            .foregroundStyle(ink.ink)
                            .minimumScaleFactor(0.4)
                            .lineLimit(6)
                    }
                    .padding(board.primary.width * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                pane(board.secondary) {
                    VStack(alignment: .leading, spacing: board.secondary.height * 0.05) {
                        Text(halves.1)
                            .font(serif(board.secondary, 0.09))
                            .foregroundStyle(ink.ink)
                            .minimumScaleFactor(0.4)
                            .lineLimit(6)
                        Text(quote.author(french: french))
                            .font(rounded(board.secondary, 0.05, weight: .medium))
                            .foregroundStyle(ink.accent)
                    }
                    .padding(board.secondary.width * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
    }

    // MARK: Diptyque

    private var diptych: some View {
        ZStack {
            pane(board.primary) { motif(board.primary, filled: true) }
            if board.axis != .none {
                pane(board.secondary) { motif(board.secondary, filled: false) }
            }
            pane(labelRect) {
                Text(NSLocalizedString(settings.palette.nameKey, comment: ""))
                    .font(rounded(labelRect, 0.28, weight: .medium))
                    .foregroundStyle(ink.mute)
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func motif(_ rect: CGRect, filled: Bool) -> some View {
        let side = min(rect.width, rect.height) * 0.62
        return ZStack {
            if filled {
                Circle().fill(ink.accent).frame(width: side, height: side)
                Circle().fill(ink.ground).frame(width: side * 0.28, height: side * 0.28).offset(x: side * 0.18, y: -side * 0.16)
            } else {
                Circle().stroke(ink.accent, lineWidth: max(2, side * 0.035)).frame(width: side, height: side)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ink.ink.opacity(0.85))
                    .frame(width: side * 0.16, height: side * 0.16)
                    .offset(x: -side * 0.22, y: side * 0.2)
            }
        }
        .frame(width: rect.width, height: rect.height)
    }

    // MARK: Compte à rebours

    private var countdown: some View {
        let reading = settings.countdown(at: date)
        return ZStack {
            if board.axis == .none {
                pane(board.primary) {
                    VStack(spacing: board.primary.height * 0.02) {
                        Text(reading.number)
                            .font(rounded(board.primary, 0.38, weight: .light))
                            .foregroundStyle(ink.ink)
                            .monospacedDigit()
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                        Text(NSLocalizedString(reading.unitKey, comment: ""))
                            .font(rounded(board.primary, 0.06, weight: .medium))
                            .foregroundStyle(ink.accent)
                            .textCase(.uppercase)
                            .tracking(3)
                        Text(settings.countdownTitleDisplay)
                            .font(serif(board.primary, 0.05))
                            .foregroundStyle(ink.mute)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, board.primary.width * 0.08)
                }
            } else {
                pane(board.primary) {
                    Text(reading.number)
                        .font(rounded(board.primary, 0.46, weight: .light))
                        .foregroundStyle(ink.ink)
                        .monospacedDigit()
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                }
                pane(board.secondary) {
                    VStack(spacing: board.secondary.height * 0.06) {
                        ring(reading.progress, in: board.secondary)
                        Text(NSLocalizedString(reading.unitKey, comment: ""))
                            .font(rounded(board.secondary, 0.08, weight: .medium))
                            .foregroundStyle(ink.accent)
                            .textCase(.uppercase)
                            .tracking(2)
                        Text(settings.countdownTitleDisplay)
                            .font(serif(board.secondary, 0.07))
                            .foregroundStyle(ink.mute)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, board.secondary.width * 0.1)
                    }
                }
            }
        }
    }

    private func ring(_ progress: Double, in rect: CGRect) -> some View {
        let side = min(rect.width, rect.height) * 0.34
        let line = max(3, side * 0.06)
        return ZStack {
            Circle().stroke(ink.ink.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(ink.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: side, height: side)
    }

    // MARK: Humeur

    private var mood: some View {
        let name = NSLocalizedString(settings.mood.nameKey, comment: "")
        return ZStack {
            Circle()
                .fill(ink.accent.opacity(0.9))
                .frame(width: size.width * 0.72, height: size.width * 0.72)
                .position(x: size.width * 0.82, y: size.height * (board.axis == .none ? 0.22 : 0.18))
            if board.axis == .none {
                pane(board.primary) {
                    Text(name)
                        .font(serif(board.primary, 0.16))
                        .foregroundStyle(ink.ink)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(.horizontal, board.primary.width * 0.08)
                }
            } else {
                pane(board.primary) {
                    Text(name)
                        .font(serif(board.primary, 0.18))
                        .foregroundStyle(ink.ink)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }
                pane(board.secondary) {
                    moodGlyph(board.secondary)
                }
            }
        }
    }

    private func moodGlyph(_ rect: CGRect) -> some View {
        let side = min(rect.width, rect.height) * 0.42
        return ZStack {
            switch settings.mood {
            case .calm:
                Capsule().fill(ink.ink.opacity(0.85)).frame(width: side * 1.1, height: side * 0.18)
                Capsule().fill(ink.ink.opacity(0.45)).frame(width: side * 0.7, height: side * 0.12).offset(y: side * 0.28)
            case .joy:
                Circle().fill(ink.ink).frame(width: side * 0.7, height: side * 0.7)
            case .focus:
                RoundedRectangle(cornerRadius: 6).stroke(ink.ink, lineWidth: max(2, side * 0.04)).frame(width: side * 0.7, height: side * 0.7)
            case .tender:
                Circle().fill(ink.ink.opacity(0.9)).frame(width: side * 0.38, height: side * 0.38).offset(x: -side * 0.22)
                Circle().fill(ink.ink.opacity(0.9)).frame(width: side * 0.38, height: side * 0.38).offset(x: side * 0.22)
            case .storm:
                Rectangle().fill(ink.ink.opacity(0.8)).frame(width: max(2, side * 0.04), height: side).rotationEffect(.degrees(18))
                Rectangle().fill(ink.ink.opacity(0.45)).frame(width: max(2, side * 0.04), height: side * 0.7).rotationEffect(.degrees(-14))
            case .wonder:
                Circle().stroke(ink.ink, lineWidth: max(2, side * 0.035)).frame(width: side * 0.85, height: side * 0.85)
                Circle().fill(ink.ink).frame(width: side * 0.12, height: side * 0.12)
            }
        }
        .frame(width: rect.width, height: rect.height)
    }

    private var labelRect: CGRect {
        let height = max(18, size.height * 0.06)
        if board.axis == .horizontal {
            return CGRect(x: 0, y: size.height - height * 1.4, width: size.width, height: height)
        }
        return CGRect(x: 0, y: size.height - height * 1.6, width: size.width, height: height)
    }
}
