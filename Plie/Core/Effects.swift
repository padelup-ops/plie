import SwiftUI

// MARK: - Confettis de victoire

/// Pluie de confettis qui part du haut de l'écran, joue une fois (environ 3 secondes).
struct ConfettiView: View {
    var colors: [Color] = [Theme.laser, Theme.gold, Theme.paint, Theme.sun, Color(hex: 0x8BDB4F)]
    var count = 90

    @State private var start = Date()
    @State private var pieces: [Piece] = []

    struct Piece {
        let x: Double
        let vx: Double
        let vy: Double
        let spin: Double
        let size: Double
        let color: Int
        let delay: Double
        let shape: Int
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < 4 else { return }
                for p in pieces {
                    let lt = t - p.delay
                    guard lt > 0 else { continue }
                    let w0 = Double(size.width)
                    let h0 = Double(size.height)
                    let xd: Double = (p.x + p.vx * lt) * w0 + sin(lt * 3 + p.spin) * 12
                    let fall: Double = p.vy * lt + 0.45 * lt * lt
                    let yd: Double = -20 + fall * h0 * 0.35
                    guard yd < h0 + 20 else { continue }
                    let x = CGFloat(xd)
                    let y = CGFloat(yd)
                    let fade = max(0, min(1, (3.6 - lt) / 0.8))
                    var c = context
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin + lt * 5))
                    let w = p.size
                    let rect = CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)
                    let path = p.shape == 0 ? Path(roundedRect: rect, cornerRadius: 1.5) : Path(ellipseIn: CGRect(x: -w / 3, y: -w / 3, width: w / 1.5, height: w / 1.5))
                    c.fill(path, with: .color(colors[p.color % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            start = Date()
            var g = SystemRandomNumberGenerator()
            pieces = (0..<count).map { _ in
                Piece(x: Double.random(in: 0.05...0.95, using: &g),
                      vx: Double.random(in: -0.12...0.12, using: &g),
                      vy: Double.random(in: 0.2...1.1, using: &g),
                      spin: Double.random(in: 0...6.28, using: &g),
                      size: Double.random(in: 7...13, using: &g),
                      color: Int.random(in: 0..<10, using: &g),
                      delay: Double.random(in: 0...0.5, using: &g),
                      shape: Int.random(in: 0...3, using: &g) == 0 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Fond animé

/// Fond doux : de grandes taches de lumière qui dérivent lentement.
/// Les taches sont des dégradés (pas de flou à recalculer) et c'est Core Animation qui les déplace :
/// rien n'est redessiné image par image, l'accueil reste fluide quand on fait défiler.
struct AmbientBackdrop: View {
    var colors: [Color] = [Color(hex: 0x3DE0FF), Color(hex: 0xFF4F9A), Color(hex: 0xFFC53D)]
    var base: Color = Theme.ink
    var intensity: Double = 0.22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { g in
            let s = max(g.size.width, g.size.height)
            ZStack {
                base
                ForEach(Array(colors.enumerated()), id: \.offset) { item in
                    let k = Double(item.offset)
                    let phase = drift ? 1.0 : 0.0
                    Circle()
                        .fill(RadialGradient(colors: [item.element.opacity(min(1, intensity * 1.8)), item.element.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: s * 0.42))
                        .frame(width: s * 0.84, height: s * 0.84)
                        .position(x: g.size.width * (0.5 + 0.34 * sin(k * 2.1 + phase * 1.3)),
                                  y: g.size.height * (0.4 + 0.3 * cos(k * 1.7 + phase * 1.1)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - Aides de dessin

enum Draw {
    /// Étoile à 5 branches.
    static func star(center: CGPoint, radius: CGFloat, inner: CGFloat = 0.45, rotation: Double = 0) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * inner
            let a = Double(i) * .pi / 5 - .pi / 2 + rotation
            let point = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    /// Petit éclat lumineux (scintillement).
    static func sparkle(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: center.x, y: center.y - radius))
        p.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: center)
        return p
    }

    /// Nombre pseudo-aléatoire stable (pour placer des étoiles, des nuages… toujours au même endroit).
    static func hash(_ i: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40_503 &+ 97)
        x ^= x >> 13
        x = x &* 0x5bd1e995
        x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }

    /// Tache de peinture brillante, aux bords légèrement irréguliers (forme stable grâce à `seed`).
    static func paintDab(_ context: inout GraphicsContext, in rect: CGRect, color: Color, seed: Int) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let n = 12
        var points: [CGPoint] = []
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * .pi
            let ca = abs(cos(a)), sa = abs(sin(a))
            let squircle = 1 / pow(pow(ca, 4) + pow(sa, 4), 0.25)
            let jitter = 0.88 + 0.12 * hash(seed, k)
            let rx = Double(rect.width) / 2 * squircle * jitter
            let ry = Double(rect.height) / 2 * squircle * jitter
            points.append(CGPoint(x: center.x + CGFloat(cos(a) * rx), y: center.y + CGFloat(sin(a) * ry)))
        }
        var blob = Path()
        func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        blob.move(to: mid(points[n - 1], points[0]))
        for k in 0..<n {
            blob.addQuadCurve(to: mid(points[k], points[(k + 1) % n]), control: points[k])
        }
        blob.closeSubpath()
        context.fill(blob.offsetBy(dx: 0, dy: rect.height * 0.04), with: .color(.black.opacity(0.12)))
        context.fill(blob, with: .color(color))
        context.fill(blob, with: .linearGradient(Gradient(colors: [.white.opacity(0.3), .clear, .black.opacity(0.14)]),
                                                 startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                                 endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        let hl = CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.16,
                        width: rect.width * 0.26, height: rect.height * 0.16)
        context.fill(Path(ellipseIn: hl), with: .color(.white.opacity(0.38)))
    }

    /// Grain de papier : petits points clairs et sombres.
    static func paperGrain(_ context: inout GraphicsContext, in rect: CGRect, seed: Int, density: Int = 140) {
        for i in 0..<density {
            let x = rect.minX + CGFloat(hash(i, seed)) * rect.width
            let y = rect.minY + CGFloat(hash(i, seed + 1)) * rect.height
            let r = CGFloat(0.5 + hash(i, seed + 2))
            let dark = i % 2 == 0
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(dark ? .black.opacity(0.05) : .white.opacity(0.18)))
        }
    }

    /// Bille ou balle avec ombrage (lumière en haut à gauche).
    static func shadedBall(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, highlight: Color = .white) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect.offsetBy(dx: radius * 0.15, dy: radius * 0.25)), with: .color(.black.opacity(0.25)))
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [highlight.opacity(0.9), color, color.opacity(0.75)]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
            startRadius: 0, endRadius: radius * 1.5))
    }
}

// MARK: - Écran de victoire

/// Fond d'un écran de victoire : assombrit le jeu, ajoute un halo et des confettis.
struct CelebrationBackdrop: View {
    var accent: Color = Theme.gold
    var confetti = true

    var body: some View {
        ZStack {
            Color(hex: 0x120E18).opacity(0.55)
            RadialGradient(colors: [accent.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 420)
            if confetti { ConfettiView() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }
}

/// Les cartes de fin de partie et de pause : une feuille de papier collée sur le jeu par un ruban
/// de la couleur du jeu. Son contenu passe en mode clair (encre sur papier).
struct WinCardModifier: ViewModifier {
    var accent: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Paper.ink)
            .background(PaperSheet(color: Paper.sheet, cornerRadius: 30, ear: 28, lift: 1.8))
            .overlay(alignment: .top) {
                WashiTape(color: accent).offset(y: -13)
            }
            .environment(\.colorScheme, .light)
    }
}

/// Icône de victoire : une médaille de papier de la couleur du jeu, qui arrive en tournant.
struct WinIcon: View {
    let systemName: String
    var color: Color = Theme.gold
    @State private var pop = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 96, height: 96)
                .scaleEffect(pop ? 1 : 0.5)
            ZStack {
                Circle().fill(color)
                Circle().fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.32), location: 0),
                    .init(color: .white.opacity(0.06), location: 0.5),
                    .init(color: Paper.shadow.opacity(0.04), location: 0.503),
                    .init(color: Paper.shadow.opacity(0.14), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Paper.ink)
            }
            .frame(width: 70, height: 70)
            .compositingGroup()
            .shadow(color: Paper.shadow.opacity(0.25), radius: 6, y: 3)
            .scaleEffect(pop ? 1 : 0.3)
            .rotationEffect(.degrees(pop ? 0 : -25))
        }
        .frame(height: 92)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { pop = true }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func winCard(accent: Color = Theme.gold) -> some View {
        modifier(WinCardModifier(accent: accent))
    }
}

// MARK: - Case de niveau

/// Fond d'une case de niveau. Sur le papier : une petite feuille, colorée une fois réussie.
/// Dans la nuit d'un jeu : verre sombre, ou couleur du jeu qui brille.
struct LevelTile: View {
    var done: Bool
    var accent: Color
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if scheme == .light {
            PaperSheet(color: done ? accent.paperTone() : Paper.sheet, cornerRadius: cornerRadius, lift: 0.5, crease: done)
        } else {
            ZStack {
                if done {
                    shape.fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: accent.opacity(0.45), radius: 8, y: 3)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
                } else {
                    // Pas de verre dépoli : il recalculait le flou du fond animé à chaque image, sur chaque case.
                    shape.fill(LinearGradient(colors: [Theme.cardHigh.opacity(0.92), Theme.card.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
        }
    }
}

/// Panneau en verre dépoli, pour les bandeaux d'aide et les cartes.
struct GlassPanel: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        LevelTile(done: false, accent: .clear, cornerRadius: cornerRadius)
    }
}
