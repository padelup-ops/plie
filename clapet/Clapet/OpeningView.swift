import SwiftUI
import UIKit

// MARK: - L'ouverture
//
// Au lancement, le logo de Foldly prend vie : la charnière (le trait en angle) est fermée, puis se déplie
// avec un petit « clic », pendant que l'anneau fait le tour. Ensuite l'angle laisse la place au chiffre
// du jour, qui monte jusqu'à sa valeur, et l'écran d'accueil apparaît. Environ 1,6 seconde.
// Un toucher la passe. Coupée avec « Réduire les animations », et désactivable dans les Réglages.

enum OpeningRule {
    static let key = "openingOn"

    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Au lancement seulement, et jamais au tout premier (le choix du look passe d'abord),
    /// ni pendant le tournage des vidéos et des captures.
    static func shouldShow(lookChosen: Bool) -> Bool {
        // Tournage de la vidéo : on peut la forcer.
        if Demo.value("demoOpening") == "1" { return true }
        return isOn && lookChosen && !UIAccessibility.isReduceMotionEnabled && !Demo.seeded && Demo.screen == nil
    }
}

struct OpeningView: View {
    let today: Int
    let look: DFLook
    let haptics: Bool
    let onFinish: () -> Void

    /// 0 : la charnière est fermée. 1 : ouverte, comme sur l'icône.
    @State private var hinge: Double = 0
    @State private var ring: Double = 0
    @State private var glyphGone = false
    @State private var count: Double = 0
    @State private var showCount = false
    @State private var leaving = false
    @State private var done = false

    private static let openAngle = 47.0
    private let size: CGFloat = 196

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ZStack {
                // L'anneau, comme sur l'icône.
                Circle()
                    .stroke(trackColor, lineWidth: size * 0.075)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(AngularGradient(colors: ringColors, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(ring, 0.01))),
                            style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // La charnière qui se déplie.
                ZStack {
                    OpeningArc(angle: Self.openAngle * hinge)
                        .stroke(ringColors.last ?? .accentColor, style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
                    OpeningArms(angle: Self.openAngle * hinge)
                        .stroke(armColor, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                }
                .scaleEffect(glyphGone ? 0.4 : 1)
                .opacity(glyphGone ? 0 : 1)

                // Puis le chiffre du jour.
                VStack(spacing: 2) {
                    OpeningCount(value: count)
                        .font(numberFont)
                        .foregroundStyle(armColor)
                    Text("folds today")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .scaleEffect(showCount ? 1 : 0.6)
                .opacity(showCount ? 1 : 0)
            }
            .frame(width: size, height: size)
            .scaleEffect(leaving ? 1.35 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish(fast: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Foldly"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { finish(fast: true) }
        .task { await play() }
    }

    // MARK: Le déroulé

    private func play() async {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.prepare()
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !done else { return }

        // 1. La charnière s'ouvre, l'anneau fait le tour.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { hinge = 1 }
        withAnimation(.easeInOut(duration: 0.75)) { ring = 0.8 }
        try? await Task.sleep(nanoseconds: 330_000_000)
        guard !done else { return }
        if haptics { soft.impactOccurred(intensity: 0.8) }

        // 2. L'angle s'efface, le chiffre du jour monte.
        try? await Task.sleep(nanoseconds: 420_000_000)
        guard !done else { return }
        withAnimation(.easeIn(duration: 0.22)) { glyphGone = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.1)) { showCount = true }
        withAnimation(.easeOut(duration: today > 0 ? 0.6 : 0.01).delay(0.1)) { count = Double(today) }
        withAnimation(.easeInOut(duration: 0.6).delay(0.1)) { ring = 1 }

        // 3. Le logo s'ouvre sur l'accueil.
        try? await Task.sleep(nanoseconds: 850_000_000)
        finish(fast: false)
    }

    private func finish(fast: Bool) {
        guard !done else { return }
        done = true
        withAnimation(.easeIn(duration: fast ? 0.18 : 0.32)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.2 : 0.34)) { onFinish() }
    }

    // MARK: Les couleurs du look

    private var background: Color { Color.dfBackground }

    private var armColor: Color { look == .night ? .white : .primary }

    private var trackColor: Color {
        switch look {
        case .minimal: return Color.primary.opacity(0.1)
        case .night: return Color.white.opacity(0.1)
        case .classic: return Color(uiColor: .tertiarySystemFill)
        }
    }

    private var ringColors: [Color] {
        switch look {
        case .minimal: return [Color.primary, Color.primary]
        case .night: return [Color(red: 0.43, green: 0.84, blue: 0.65), Color(red: 0.36, green: 0.89, blue: 0.85)]
        case .classic: return [Color.accentColor.opacity(0.75), Color.accentColor]
        }
    }

    private var numberFont: Font {
        switch look {
        case .minimal, .night: return .system(size: 60, weight: .light).monospacedDigit()
        case .classic: return .system(size: 56, weight: .bold, design: .rounded).monospacedDigit()
        }
    }
}

/// Le chiffre qui défile de 0 jusqu'au compte du jour.
private struct OpeningCount: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(Int(value.rounded()))")
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Les deux branches de l'angle : celle du bas ne bouge pas, l'autre se lève de `angle` degrés.
/// À 0°, le téléphone vu de profil est fermé.
private struct OpeningArms: Shape {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in r: CGRect) -> Path {
        let vertex = CGPoint(x: r.minX + r.width * 0.31, y: r.minY + r.height * 0.56)
        let a = angle * .pi / 180
        let arm = r.width * 0.25
        var p = Path()
        p.move(to: CGPoint(x: vertex.x + r.width * 0.34, y: vertex.y))
        p.addLine(to: vertex)
        p.addLine(to: CGPoint(x: vertex.x + cos(a) * arm, y: vertex.y - sin(a) * arm))
        return p
    }
}

/// Le petit arc qui mesure l'angle de la charnière.
private struct OpeningArc: Shape {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in r: CGRect) -> Path {
        let vertex = CGPoint(x: r.minX + r.width * 0.31, y: r.minY + r.height * 0.56)
        let radius = r.width * 0.17
        var p = Path()
        guard angle > 1 else { return p }
        let steps = 24
        for i in 0...steps {
            let t = angle * Double(i) / Double(steps) * .pi / 180
            let point = CGPoint(x: vertex.x + cos(t) * radius, y: vertex.y - sin(t) * radius)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}
