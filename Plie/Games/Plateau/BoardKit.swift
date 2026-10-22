import SwiftUI

// MARK: - Réglages communs aux jeux de plateau

enum BoardOpponent: Equatable, Codable {
    case human
    case computer(level: Int)

    var isComputer: Bool {
        if case .computer = self { return true }
        return false
    }

    var level: Int {
        if case .computer(let level) = self { return level }
        return 0
    }

    static func levelName(_ level: Int) -> String {
        switch level {
        case 1: return L("Facile")
        case 2: return L("Moyen")
        default: return L("Difficile")
        }
    }
}

enum ClockSetting: Int, CaseIterable, Identifiable, Codable {
    case none = 0, ten, five, blitz

    var id: Int { rawValue }
    var seconds: Double? { [nil, 600, 300, 180][rawValue] }
    var increment: Double { self == .blitz ? 2 : 0 }

    var label: String {
        switch self {
        case .none: return L("Sans pendule")
        case .ten: return L("10 min")
        case .five: return L("5 min")
        case .blitz: return L("3 min + 2 s")
        }
    }
}

/// Une demande faite à l'autre joueur, qui doit l'accepter de son côté de la table.
enum BoardRequest: Equatable {
    case undo(from: Int)
    case draw(from: Int)

    var from: Int {
        switch self {
        case .undo(let f), .draw(let f): return f
        }
    }
}

// MARK: - Pendule

@Observable
final class BoardClock {
    private(set) var remaining: [Double] = [0, 0]
    private(set) var setting: ClockSetting = .none
    /// Le camp (0 = Blancs, 1 = Noirs) dont la pendule tourne.
    var running: Int?

    var enabled: Bool { setting != .none }

    func reset(_ s: ClockSetting) {
        setting = s
        let t = s.seconds ?? 0
        remaining = [t, t]
        running = nil
    }

    func restore(_ s: ClockSetting, remaining r: [Double]) {
        setting = s
        remaining = r.count == 2 ? r : [s.seconds ?? 0, s.seconds ?? 0]
        running = nil
    }

    /// Fait avancer la pendule ; renvoie le camp dont le drapeau tombe.
    func tick(_ dt: Double, paused: Bool) -> Int? {
        guard enabled, !paused, let side = running else { return nil }
        let before = remaining[side]
        remaining[side] = max(0, before - dt)
        if before > 10.5 && remaining[side] <= 10.5 { SoundPlayer.shared.play(.clockTick, volume: 0.5) }
        if remaining[side] < 10 && floor(before) != floor(remaining[side]) {
            SoundPlayer.shared.play(.clockTick, volume: 0.35)
        }
        return remaining[side] <= 0 ? side : nil
    }

    func moved(by side: Int) {
        guard enabled else { return }
        if running != nil { remaining[side] += setting.increment }
        running = 1 - side
    }

    static func format(_ t: Double) -> String {
        if t < 10 { return String(format: "%.1f", max(0, t)) }
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Disposition face à face
//
// Duo déplié et posé à plat : la charnière coupe l'écran en deux, et chaque joueur a sa moitié.
// Le plateau est centré sur la charnière ; chaque joueur a son panneau (pendule, prises, boutons)
// tourné vers lui, de son côté de la table.

struct TableLayout {
    let size: CGSize
    let safe: EdgeInsets
    let facing: Bool
    let alongX: Bool
    let boardSide: CGFloat
    let center: CGPoint

    init(size: CGSize, safe: EdgeInsets, hingePresent: Bool, facing: Bool) {
        self.size = size
        self.safe = safe
        self.facing = facing
        // Avec une charnière, les joueurs s'assoient de part et d'autre de la pliure ;
        // sans charnière, aux deux bouts du téléphone.
        if facing {
            alongX = hingePresent ? size.width < size.height : size.width > size.height
        } else {
            alongX = size.width > size.height * 1.15
        }
        let along = alongX ? size.width : size.height
        let across = alongX ? size.height - safe.top - safe.bottom : size.width - safe.leading - safe.trailing
        let panelMin: CGFloat = facing ? 74 : 92
        boardSide = max(160, min(across - 12, along - 2 * panelMin - (alongX ? 0 : safe.top + safe.bottom)))
        center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Orientation du panneau du siège 0 (en bas ou à gauche) et du siège 1 (en haut ou à droite).
    func seatAngle(_ seat: Int) -> Double {
        guard facing else { return 0 }
        if alongX { return seat == 0 ? 90 : -90 }
        return seat == 0 ? 0 : 180
    }

    /// Zone du panneau à l'écran, sans les bords non sûrs (encoche, barre d'accueil).
    func seatRect(_ seat: Int) -> CGRect {
        let half = boardSide / 2
        var r: CGRect
        if alongX {
            r = seat == 0 ? CGRect(x: 0, y: 0, width: center.x - half, height: size.height)
                          : CGRect(x: center.x + half, y: 0, width: size.width - center.x - half, height: size.height)
        } else {
            r = seat == 0 ? CGRect(x: 0, y: center.y + half, width: size.width, height: size.height - center.y - half)
                          : CGRect(x: 0, y: 0, width: size.width, height: center.y - half)
        }
        let safeRect = CGRect(x: safe.leading, y: safe.top,
                              width: size.width - safe.leading - safe.trailing,
                              height: size.height - safe.top - safe.bottom)
        r = r.intersection(safeRect)
        return r.insetBy(dx: 6, dy: 6)
    }

    /// Taille du panneau dans son propre sens de lecture.
    func seatLocalSize(_ seat: Int) -> CGSize {
        let r = seatRect(seat)
        return abs(seatAngle(seat)) == 90 ? CGSize(width: r.height, height: r.width) : r.size
    }
}

/// Place un contenu dans la zone d'un siège, tourné vers le joueur assis là.
struct SeatContainer<Content: View>: View {
    let layout: TableLayout
    let seat: Int
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        let rect = layout.seatRect(seat)
        let local = layout.seatLocalSize(seat)
        if rect.width > 20 && rect.height > 20 {
            content(local)
                .frame(width: local.width, height: local.height)
                .rotationEffect(.degrees(layout.seatAngle(seat)))
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Petits éléments

struct RoundGlassButton: View {
    let symbol: String
    let label: String
    var tint: Color = .white
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
                .background(Circle().fill(Color.black.opacity(0.25)))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Bouton plein, compact, pour les panneaux.
struct SeatButton: View {
    let title: String
    var color: Color = Theme.gold
    var textColor: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.plie(15, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Capsule().fill(color))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Affichage de la pendule d'un joueur.
struct ClockFace: View {
    let time: Double
    let active: Bool
    let accent: Color

    var body: some View {
        let low = time < 10
        Text(BoardClock.format(time))
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(low ? Color(hex: 0xFF6B6B) : (active ? Theme.ink : .white.opacity(0.85)))
            .padding(.horizontal, 12)
            .frame(minWidth: 92, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(Color.black.opacity(0.35)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(active ? 0.5 : 0.12), lineWidth: 1))
            .shadow(color: active ? accent.opacity(0.6) : .clear, radius: 10)
            .accessibilityLabel(L("Temps restant : \(BoardClock.format(time))"))
    }
}

// MARK: - Bois et marbre

enum Wood {
    /// Veines du bois sur une case (droites et un peu ondulées).
    static func grain(_ context: inout GraphicsContext, rect: CGRect, horizontal: Bool, seed: Int, color: Color, opacity: Double) {
        let s = rect.width
        let n = 7
        for k in 0..<n {
            let off = (Double(k) + 0.5 + (Draw.hash(seed, k) - 0.5) * 0.6) / Double(n)
            let amp = Double(s) * (0.015 + 0.03 * Draw.hash(seed, k + 20))
            let phase = Draw.hash(seed, k + 40) * 6.28
            let freq = 0.6 + Draw.hash(seed, k + 60)
            var line = Path()
            for j in 0...8 {
                let t = Double(j) / 8
                let wave = amp * sin(t * 6.28 * freq + phase)
                let p = horizontal
                    ? CGPoint(x: rect.minX + CGFloat(t) * s, y: rect.minY + CGFloat(off) * s + CGFloat(wave))
                    : CGPoint(x: rect.minX + CGFloat(off) * s + CGFloat(wave), y: rect.minY + CGFloat(t) * s)
                if j == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            let width = 0.5 + 1.1 * Draw.hash(seed, k + 80)
            context.stroke(line, with: .color(color.opacity(opacity * (0.5 + Draw.hash(seed, k + 90)))), lineWidth: CGFloat(width))
        }
    }

    /// Une veine de marbre douce.
    static func marble(_ context: inout GraphicsContext, rect: CGRect, seed: Int, color: Color) {
        let s = rect.width
        var vein = Path()
        let base = 0.2 + 0.6 * Draw.hash(seed, 3)
        for j in 0...6 {
            let t = Double(j) / 6
            let p = CGPoint(x: rect.minX + CGFloat(t) * s,
                            y: rect.minY + CGFloat(base) * s + CGFloat(0.18 * sin(t * 5 + Draw.hash(seed, 4) * 6)) * s)
            if j == 0 { vein.move(to: p) } else { vein.addLine(to: p) }
        }
        context.stroke(vein, with: .color(color), lineWidth: 0.9)
    }
}

// MARK: - Pièces d'échecs

/// Pièce d'échecs : ivoire ou ébène, avec contour, reflet et ombre.
struct ChessPieceView: View {
    let type: Int8
    let white: Bool
    var lifted = false

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let line = s * 0.05
            ZStack {
                ChessPieceShape(type: type)
                    .stroke(white ? Color(hex: 0x2A1D12) : Color(hex: 0x050507), style: StrokeStyle(lineWidth: line, lineJoin: .round))
                ChessPieceShape(type: type)
                    .fill(white
                          ? LinearGradient(colors: [.white, Color(hex: 0xF3EAD8), Color(hex: 0xD6C3A0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color(hex: 0x5A5A68), Color(hex: 0x2A2A33), Color(hex: 0x0C0C10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if !white {
                    ChessPieceShape(type: type)
                        .stroke(Color(hex: 0xB9B9CC).opacity(0.45), lineWidth: s * 0.016)
                }
                LinearGradient(colors: [.white.opacity(white ? 0.45 : 0.32), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.45, y: 0.5))
                    .mask(ChessPieceShape(type: type))
                ChessPieceDetail(type: type)
                    .stroke((white ? Color(hex: 0x2A1D12) : Color(hex: 0xD8D8E6)).opacity(0.55),
                            style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
                ChessPieceDots(type: type)
                    .fill((white ? Color(hex: 0x2A1D12) : Color(hex: 0xD8D8E6)).opacity(0.85))
            }
            .frame(width: s, height: s)
            .compositingGroup()
            .shadow(color: .black.opacity(lifted ? 0.45 : 0.35), radius: lifted ? s * 0.06 : s * 0.025,
                    x: s * 0.03, y: lifted ? s * 0.08 : s * 0.04)
            .scaleEffect(lifted ? 1.1 : 1)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pions de dames

struct DraughtsPieceView: View {
    let white: Bool
    let king: Bool
    var lifted = false

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let r = s * 0.41
            ZStack {
                if king {
                    disc(r: r, s: s).offset(y: s * 0.05)
                }
                disc(r: r, s: s).offset(y: king ? -s * 0.05 : 0)
                if king {
                    Image(systemName: "crown.fill")
                        .font(.system(size: s * 0.3, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE3A0), Color(hex: 0xC8902E)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                        .offset(y: -s * 0.06)
                }
            }
            .frame(width: s, height: s)
            .compositingGroup()
            .shadow(color: .black.opacity(lifted ? 0.5 : 0.4), radius: lifted ? s * 0.07 : s * 0.035,
                    x: s * 0.03, y: lifted ? s * 0.09 : s * 0.05)
            .scaleEffect(lifted ? 1.1 : 1)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private func disc(r: CGFloat, s: CGFloat) -> some View {
        let edge = white ? Color(hex: 0xA89070) : Color.black
        let groove = white ? Color(hex: 0x8C7556) : Color(hex: 0x6A6A78)
        let face = white
            ? RadialGradient(colors: [.white, Color(hex: 0xEFE3CB), Color(hex: 0xCDB894)], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: r * 1.5)
            : RadialGradient(colors: [Color(hex: 0x5C5C68), Color(hex: 0x26262E), Color(hex: 0x0B0B0E)], center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: r * 1.5)
        return ZStack {
            Circle().fill(edge).frame(width: r * 2, height: r * 2).offset(y: s * 0.05)
            Circle().fill(face).frame(width: r * 2, height: r * 2)
            Circle().strokeBorder(groove.opacity(0.55), lineWidth: s * 0.03).frame(width: r * 1.44, height: r * 1.44)
            Circle().strokeBorder(groove.opacity(0.45), lineWidth: s * 0.025).frame(width: r * 0.84, height: r * 0.84)
            Circle()
                .trim(from: 0.55, to: 0.78)
                .stroke(.white.opacity(white ? 0.6 : 0.3), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
                .frame(width: r * 1.6, height: r * 1.6)
        }
    }
}

// MARK: - Écran de réglage d'une partie

/// Carte de départ commune aux échecs et aux dames.
struct BoardSetupCard: View {
    let title: String
    let symbolView: AnyView
    let accent: Color
    let rules: String
    let hingeHint: String
    let savedSummary: String?
    let passLocked: (Int) -> Bool
    let onResume: () -> Void
    let onStart: (BoardOpponent, ClockSetting, Bool) -> Void
    let onPass: () -> Void

    @State private var vsComputer = false
    @State private var level = 2
    @State private var clock: ClockSetting = .none
    @State private var playWhite = true

    var body: some View {
        VStack(spacing: 14) {
            symbolView.frame(width: 76, height: 76)
            Text(title).font(.plie(30))
            Text(rules)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            if let savedSummary {
                Button(action: onResume) {
                    Label(L("Reprendre la partie · \(savedSummary)"), systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: accent, textColor: Theme.ink, height: 52))
            }

            Picker("", selection: $vsComputer) {
                Text(L("À deux, face à face")).tag(false)
                Text(L("Contre l'ordinateur")).tag(true)
            }
            .pickerStyle(.segmented)

            if vsComputer {
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { l in
                        let locked = passLocked(l)
                        Button {
                            if locked { onPass() } else { level = l }
                        } label: {
                            HStack(spacing: 4) {
                                if locked { Image(systemName: "crown.fill").font(.system(size: 11)) }
                                Text(BoardOpponent.levelName(l))
                            }
                            .font(.plie(14, weight: .bold))
                            .foregroundStyle(level == l ? Theme.ink : .white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Capsule().fill(level == l ? accent : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Picker("", selection: $playWhite) {
                    Text(L("Je joue les Blancs")).tag(true)
                    Text(L("Je joue les Noirs")).tag(false)
                }
                .pickerStyle(.segmented)
            } else {
                Text(hingeHint)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Picker("", selection: $clock) {
                    ForEach(ClockSetting.allCases) { c in
                        Text(c.label).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button(savedSummary == nil ? L("Jouer") : L("Nouvelle partie")) {
                onStart(vsComputer ? .computer(level: level) : .human, vsComputer ? .none : clock, vsComputer ? playWhite : true)
            }
            .buttonStyle(ChunkyButtonStyle(color: savedSummary == nil ? accent : Theme.cardHigh,
                                           textColor: savedSummary == nil ? Theme.ink : .white, height: 54))
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: 480)
        .winCard(accent: accent)
        .padding(16)
    }
}

// MARK: - Panneau d'un joueur

struct SeatPromptButton {
    let title: String
    var color: Color = Theme.gold
    var textColor: Color = Theme.ink
    let action: () -> Void
}

/// Ce qu'un panneau affiche à la place des boutons : une question, un résultat, le menu…
struct SeatPrompt {
    let message: String
    var detail: String?
    var buttons: [SeatPromptButton] = []
    var extra: AnyView?
}

struct SeatAction: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void
}

/// Le panneau d'un joueur, de son côté de la table : nom, état, pièces prises, pendule, boutons.
struct SeatPanel: View {
    let size: CGSize
    let name: String
    let status: String
    var statusColor: Color = Theme.muted
    let isTurn: Bool
    let accent: Color
    let avatar: AnyView
    let captured: AnyView
    var clock: (time: Double, active: Bool)?
    var actions: [SeatAction] = []
    var prompt: SeatPrompt?

    var body: some View {
        let compact = size.height < 118
        ZStack {
            GlassPanel(cornerRadius: 22)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [accent.opacity(isTurn ? 0.95 : 0.0), accent.opacity(isTurn ? 0.3 : 0)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 2)
                .shadow(color: accent.opacity(isTurn ? 0.55 : 0), radius: 14)
            Group {
                if let prompt {
                    promptView(prompt, compact: compact)
                } else if compact {
                    HStack(spacing: 12) {
                        identity
                        if size.width > 470 { captured.frame(maxWidth: .infinity, alignment: .leading) } else { Spacer(minLength: 0) }
                        if let clock { ClockFace(time: clock.time, active: clock.active, accent: accent) }
                        actionButtons
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            identity
                            Spacer(minLength: 0)
                            if let clock { ClockFace(time: clock.time, active: clock.active, accent: accent) }
                        }
                        HStack(spacing: 10) {
                            captured.frame(maxWidth: .infinity, alignment: .leading)
                            actionButtons
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .animation(.easeOut(duration: 0.2), value: isTurn)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.25)))
                .overlay(Circle().strokeBorder(accent.opacity(isTurn ? 0.9 : 0.2), lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.plie(17, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(status)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(actions) { a in
                RoundGlassButton(symbol: a.symbol, label: a.label, size: 38, action: a.action)
                    .disabled(!a.enabled)
                    .opacity(a.enabled ? 1 : 0.35)
            }
        }
    }

    @ViewBuilder
    private func promptView(_ p: SeatPrompt, compact: Bool) -> some View {
        let buttons = HStack(spacing: 8) {
            ForEach(Array(p.buttons.enumerated()), id: \.offset) { item in
                SeatButton(title: item.element.title, color: item.element.color, textColor: item.element.textColor, action: item.element.action)
            }
        }
        let texts = VStack(alignment: compact ? .leading : .center, spacing: 2) {
            Text(p.message)
                .font(.plie(compact ? 17 : 20, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let d = p.detail {
                Text(d)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        if compact {
            HStack(spacing: 12) {
                texts
                if let extra = p.extra { extra }
                Spacer(minLength: 0)
                buttons
            }
        } else {
            VStack(spacing: 10) {
                texts.multilineTextAlignment(.center)
                if let extra = p.extra { extra }
                buttons
            }
        }
    }
}
