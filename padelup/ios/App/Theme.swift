import SwiftUI
import UIKit

// PADELUP NEO · direction « Court »
//
// Un objet de sport bien fait plutôt qu'un tableau de bord :
//  - la typographie porte l'écran : titres en SF Pro Expanded, chiffres (heures, prix, scores) en condensé à chasse fixe,
//    comme un tableau de score ;
//  - le contenu est posé sur la page (papier), séparé par des filets ; une surface blanche seulement pour ce qu'on
//    « tient » : un billet de réservation, un champ, une feuille ;
//  - deux couleurs, chacune avec un rôle : le bleu PadelUp (#094A73) pour agir, le jaune balle pour ce qui est libre,
//    en direct ou réservé. Le reste est encre et papier ;
//  - des phrases courtes, pas d'émoji, pas de sous-titre explicatif sous chaque titre.
enum UI {
    static func dyn(_ light: UInt32, _ dark: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark, alpha) : uiColor(light, alpha) })
    }

    static func uiColor(_ h: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: alpha)
    }

    static func hex(_ h: UInt32) -> Color { Color(uiColor: uiColor(h)) }

    // Papier et encre (le soir : un court de nuit, bleu-noir)
    static let paper = dyn(0xF4F2EC, 0x0B1115)
    static let raised = dyn(0xFFFFFF, 0x141B20)
    static let sunken = dyn(0xE8E5DC, 0x1C252B)
    static let ink = dyn(0x0D1B24, 0xEEF0EA)
    static let muted = dyn(0x5D676D, 0x939DA2)
    static let faint = dyn(0x9AA1A4, 0x5B666C)
    static let rule = dyn(0x0D1B24, 0xEEF0EA, 0.13)

    // Rôles
    static let court = dyn(0x094A73, 0x74B6E2)       // agir : boutons, liens, sélection
    static let onCourt = dyn(0xFFFFFF, 0x06141C)
    static let courtWash = dyn(0xDCE7EE, 0x132838)
    static let ball = hex(0xD6F04A)                    // libre, en direct, réservé
    static let onBall = hex(0x0D1B24)
    static let clay = dyn(0xB4501C, 0xF0915E)          // à faire, attention
    static let danger = dyn(0xB42318, 0xF2716A)
    static let success = dyn(0x2E7D4F, 0x86D6A3)

    static let radius: CGFloat = 16
    static let margin: CGFloat = 20

    // Typographie
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold).width(.expanded) }
    static func title(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold).width(.expanded) }
    static func headline() -> Font { .system(size: 17, weight: .semibold) }
    static func body() -> Font { .system(size: 16) }
    static func callout() -> Font { .system(size: 15) }
    static func caption() -> Font { .system(size: 13) }
    static func small() -> Font { .system(size: 12, weight: .medium) }
    /// Petite étiquette en capitales espacées (dans un billet, au-dessus d'un chiffre).
    static func label() -> Font { .system(size: 10.5, weight: .semibold).width(.expanded) }
    /// Chiffres façon tableau de score.
    static func score(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .semibold).width(.condensed).monospacedDigit() }
    static func scoreHeavy(_ size: CGFloat = 56) -> Font { .system(size: size, weight: .bold).width(.compressed).monospacedDigit() }

    static let fr = Locale(identifier: "fr_FR")
}

// MARK: - Fonds

/// Le papier de la page, avec l'ambiance de saison (l'idée de Yacine) qui tombe derrière le contenu.
struct PageBackground: View {
    var seasonal = true
    @AppStorage(SeasonSetting.key) private var seasonMode = "auto"

    var body: some View {
        ZStack {
            UI.paper
            if seasonal, let season = SeasonSetting.resolve(seasonMode) {
                SeasonalOverlay(season: season, density: 0.6)
            }
        }
        .ignoresSafeArea()
    }
}

/// Une surface qu'on « tient » : champ, liste dans une feuille, panneau sur la carte.
struct SurfaceStyle: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = UI.raised

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.rule, lineWidth: 0.5))
    }
}

extension View {
    func surface(padding: CGFloat = 16, fill: Color = UI.raised) -> some View { modifier(SurfaceStyle(padding: padding, fill: fill)) }
}

// MARK: - Mise en page

/// Écran d'onglet : un sur-titre de contexte, un grand titre, puis des blocs posés sur la page.
struct Screen<Content: View, Accessory: View>: View {
    var title: String
    var eyebrow: String? = nil
    var seasonal = true
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let eyebrow { Eyebrow(text: eyebrow) }
                        Text(title).font(UI.display()).foregroundStyle(UI.ink).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    accessory()
                }
                content()
            }
            .padding(.horizontal, UI.margin)
            .padding(.top, 10)
            .padding(.bottom, 56)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PageBackground(seasonal: seasonal))
    }
}

extension Screen where Accessory == EmptyView {
    init(title: String, eyebrow: String? = nil, seasonal: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, eyebrow: eyebrow, seasonal: seasonal, accessory: { EmptyView() }, content: content)
    }
}

/// Sur-titre : date, ville, plateforme… en petites capitales.
struct Eyebrow: View {
    var text: String
    var color: Color = UI.muted

    var body: some View {
        Text(text.uppercased(with: UI.fr)).font(UI.label()).tracking(1.1).foregroundStyle(color).lineLimit(1)
    }
}

/// Bloc éditorial : un filet d'encre, un titre, une info à droite, puis le contenu.
struct Block<Content: View>: View {
    var title: String
    var meta: String? = nil
    var live = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(UI.ink).frame(height: 1.5)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(UI.title()).foregroundStyle(UI.ink)
                    Spacer(minLength: 8)
                    if live { LiveDot().alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 } }
                    if let meta { Text(meta).font(UI.caption()).monospacedDigit().foregroundStyle(UI.muted).lineLimit(1) }
                    if let actionTitle, let action {
                        Button(actionTitle, action: action).buttonStyle(LinkButtonStyle())
                    }
                }
            }
            content()
        }
    }
}

struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(UI.rule).frame(height: 0.5).padding(.leading, inset) }
}

struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

// MARK: - Boutons

/// Action principale : bleu PadelUp, angles doux (pas de pilule).
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = UI.court
    var text: Color = UI.onCourt

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Action secondaire : un trait d'encre.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = UI.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.raised.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.ink.opacity(0.85), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Lien d'action dans le texte (« Connecter », « Tout voir »…).
struct LinkButtonStyle: ButtonStyle {
    var color: Color = UI.court

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold)).foregroundStyle(color).opacity(configuration.isPressed ? 0.45 : 1)
    }
}

/// Petit bouton rond (fermer, cloche, ajouter).
struct RoundIconButton: View {
    var systemImage: String
    var badge = false
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? UI.onCourt : UI.ink)
                .frame(width: 42, height: 42)
                .background(Circle().fill(filled ? UI.court : UI.raised))
                .overlay(Circle().strokeBorder(filled ? Color.clear : UI.rule, lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(UI.clay).frame(width: 9, height: 9).overlay(Circle().stroke(UI.paper, lineWidth: 2)).offset(x: -3, y: 3) }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sélecteurs

/// Filtre ou choix : contour fin, encre pleine quand il est actif.
struct Chip: View {
    var text: String
    var systemImage: String? = nil
    var active = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .foregroundStyle(active ? UI.paper : UI.ink)
        .background(Capsule().fill(active ? UI.ink : UI.raised))
        .overlay(Capsule().strokeBorder(active ? Color.clear : UI.rule, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Onglets soulignés (remplacent le contrôle segmenté).
struct UnderlineTabs: View {
    var items: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 24) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = i }
                } label: {
                    VStack(spacing: 9) {
                        Text(items[i])
                            .font(.system(size: 16, weight: selection == i ? .semibold : .regular))
                            .foregroundStyle(selection == i ? UI.ink : UI.muted)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if selection == i { Rectangle().fill(UI.ink).frame(height: 2).matchedGeometryEffect(id: "underline", in: ns) }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Choix compact en ligne (60 · 90 · 120 min).
struct InlinePicker<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                let on = value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(label)
                        .font(.system(size: 14, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? UI.paper : UI.ink)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? UI.ink : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(UI.sunken))
    }
}

// MARK: - Signes

/// Point vert balle qui respire : en direct, bot en veille.
struct LiveDot: View {
    var color: Color = UI.ball
    var size: CGFloat = 8
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.45)).frame(width: size * 2.2, height: size * 2.2)
                .scaleEffect(pulse ? 1 : 0.4).opacity(pulse ? 0 : 0.9)
            Circle().fill(color).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(UI.ink.opacity(0.35), lineWidth: 0.75))
        }
        .frame(width: size * 2.2, height: size * 2.2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Tampon : « Réservé », « Libre », « En direct ».
struct Stamp: View {
    enum Style { case ball, ink, outline, clay }
    var text: String
    var style: Style = .ball

    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch style {
            case .ball: return (UI.onBall, UI.ball)
            case .ink: return (UI.paper, UI.ink)
            case .outline: return (UI.ink, Color.clear)
            case .clay: return (Color.white, UI.clay)
            }
        }()
        return Text(text.uppercased(with: UI.fr))
            .font(UI.label()).tracking(0.9)
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(style == .outline ? UI.ink.opacity(0.5) : Color.clear, lineWidth: 1))
            .fixedSize()
    }
}

/// Le logo : une balle de padel, à plat, couture à l'encre.
struct BallMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(UI.ball)
            Circle().trim(from: 0.1, to: 0.4).stroke(UI.onBall, lineWidth: size * 0.06).rotationEffect(.degrees(-36)).padding(size * 0.15)
            Circle().trim(from: 0.6, to: 0.9).stroke(UI.onBall, lineWidth: size * 0.06).rotationEffect(.degrees(-36)).padding(size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Initiales dans un rond, d'une teinte stable par joueur (pas tous en bleu).
struct Avatar: View {
    var name: String
    var size: CGFloat = 40

    static let tones: [UInt32] = [0x094A73, 0xB4501C, 0x4F6B2E, 0x5A4A86, 0x2E5E63, 0x8A3B54]

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0) }
        return (letters.isEmpty ? "?" : letters.joined()).uppercased()
    }

    private var tone: Color {
        let h = name.unicodeScalars.reduce(UInt(5381)) { ($0 &* 33) &+ UInt($1.value) }
        return UI.hex(Self.tones[Int(h % UInt(Self.tones.count))])
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold).width(.expanded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(tone))
            .accessibilityLabel(name)
    }
}

/// Niveau en barres montantes (1 à 8 ou 10) : se lit d'un coup d'œil.
struct LevelBars: View {
    var level: Int
    var count: Int = 8
    var height: CGFloat = 14
    var barWidth: CGFloat = 3
    var color: Color = UI.ink

    var body: some View {
        HStack(alignment: .bottom, spacing: barWidth * 0.8) {
            ForEach(1...max(1, count), id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(i <= level ? color : UI.rule)
                    .frame(width: barWidth, height: height * (0.3 + 0.7 * CGFloat(i) / CGFloat(max(1, count))))
            }
        }
        .accessibilityLabel("Niveau \(level) sur \(count)")
    }
}

/// Valeur + étiquette (statistiques, faits d'un club).
struct StatColumn: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(UI.score(28)).foregroundStyle(UI.ink).lineLimit(1).minimumScaleFactor(0.6)
            Eyebrow(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rangée de statistiques séparées par des filets verticaux.
struct StatsRow: View {
    var items: [(String, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(UI.rule).frame(width: 0.5, height: 40).padding(.trailing, 14) }
                StatColumn(value: items[i].0, label: items[i].1)
            }
        }
    }
}

/// Note discrète quand il n'y a rien à montrer : alignée à gauche, une phrase, une action.
struct EmptyNote: View {
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(UI.headline()).foregroundStyle(UI.ink)
            if let message { Text(message).font(UI.callout()).foregroundStyle(UI.muted).fixedSize(horizontal: false, vertical: true) }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(LinkButtonStyle()).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// Champ de saisie : blanc, filet fin.
struct InputField: View {
    var title: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(UI.muted) }
            Group {
                if secure { SecureField(title, text: $text) } else {
                    TextField(title, text: $text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .font(UI.body())
            .foregroundStyle(UI.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.rule, lineWidth: 1))
    }
}

/// Ligne de liste : titre, détail, valeur à droite, chevron.
struct ListRow: View {
    var title: String
    var detail: String? = nil
    var value: String? = nil
    var systemImage: String? = nil
    var chevron = true
    var titleColor: Color = UI.ink

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 16, weight: .regular)).foregroundStyle(UI.ink).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.body()).foregroundStyle(titleColor)
                if let detail { Text(detail).font(UI.caption()).foregroundStyle(UI.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(UI.callout()).foregroundStyle(UI.muted).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(UI.faint) }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Le billet (signature de l'app : une réservation, un créneau, un match)

/// Rectangle aux angles doux, entaillé des deux côtés à la hauteur de la perforation.
struct TicketShape: Shape {
    var cut: CGFloat
    var radius: CGFloat = 18
    var notch: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let base = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        let y = min(max(cut, notch + radius), rect.height - notch - radius)
        let left = Path(ellipseIn: CGRect(x: rect.minX - notch, y: rect.minY + y - notch, width: notch * 2, height: notch * 2))
        let right = Path(ellipseIn: CGRect(x: rect.maxX - notch, y: rect.minY + y - notch, width: notch * 2, height: notch * 2))
        return base.subtracting(left).subtracting(right)
    }
}

struct Ticket<Main: View, Stub: View>: View {
    var fill: Color = UI.raised
    @ViewBuilder var main: () -> Main
    @ViewBuilder var stub: () -> Stub
    @State private var cut: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            main()
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cut = $0 }
            HLine().stroke(UI.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(height: 1).padding(.horizontal, 18)
            stub()
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TicketShape(cut: cut).fill(fill))
        .overlay(TicketShape(cut: cut).stroke(UI.rule, lineWidth: 0.5))
    }
}

// MARK: - Dates en français

enum FR {
    static func string(_ date: Date, _ format: String, tz: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = UI.fr
        f.timeZone = tz
        f.dateFormat = format
        return f.string(from: date)
    }

    /// « ven. 27 nov. »
    static func shortDay(_ date: Date, tz: TimeZone = .current) -> String { string(date, "EEE d MMM", tz: tz) }
    /// « vendredi 27 novembre »
    static func longDay(_ date: Date, tz: TimeZone = .current) -> String { string(date, "EEEE d MMMM", tz: tz) }
    /// « 19:30 »
    static func time(_ date: Date, tz: TimeZone = .current) -> String { string(date, "HH:mm", tz: tz) }
    /// « il y a 9 min »
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = UI.fr
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
