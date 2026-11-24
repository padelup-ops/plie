// Theme.swift — Allô Père Noël
//
// La palette du brief (vert sapin, rouge Noël, or, crème, bleu nuit), les polices (Fraunces, sous licence OFL,
// pour les titres de conte ; SF Rounded pour le reste) et les décors : la nuit du pôle Nord, la neige qui tombe,
// l'atelier chaleureux. Tout est dessiné ici, en SwiftUI.

import SwiftUI

enum Noel {
    static let fir = Color(red: 0x12 / 255, green: 0x3B / 255, blue: 0x2A / 255)
    static let forest = Color(red: 0x1B / 255, green: 0x4D / 255, blue: 0x36 / 255)
    static let red = Color(red: 0xB8 / 255, green: 0x20 / 255, blue: 0x25 / 255)
    static let bordeaux = Color(red: 0x79 / 255, green: 0x1B / 255, blue: 0x24 / 255)
    static let gold = Color(red: 0xD6 / 255, green: 0xB5 / 255, blue: 0x68 / 255)
    static let cream = Color(red: 1, green: 0xF7 / 255, blue: 0xEB / 255)
    static let snow = Color.white
    static let night = Color(red: 0x10 / 255, green: 0x1C / 255, blue: 0x32 / 255)
    static let skin = Color(red: 0.96, green: 0.80, blue: 0.68)
    static let goldLight = Color(red: 0.95, green: 0.85, blue: 0.58)
    static let goldGradient = LinearGradient(colors: [goldLight, gold, Color(red: 0.72, green: 0.56, blue: 0.27)],
                                             startPoint: .top, endPoint: .bottom)
}

extension Font {
    /// Titres de conte : Fraunces, doux et chaleureux.
    static func tale(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("FrauncesDisplay-SemiBold", size: size, relativeTo: style)
    }
    /// Phrases du Père Noël et petites touches : Fraunces italique.
    static func story(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
        .custom("FrauncesText-MediumItalic", size: size, relativeTo: style)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Boutons

/// Le bouton principal : un ruban doré qui luit doucement.
struct MagicButtonStyle: ButtonStyle {
    var glow = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(19, .bold))
            .foregroundStyle(Noel.night)
            .padding(.vertical, 18).padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .background {
                Capsule().fill(Noel.goldGradient)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1).blendMode(.overlay))
            }
            .shadow(color: Noel.gold.opacity(glow ? 0.55 : 0), radius: 18, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Le bouton secondaire : un fil crème (ou, posé sur la neige, une capsule de nuit).
struct QuietButtonStyle: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(17, .semibold))
            .foregroundStyle(Noel.cream)
            .padding(.vertical, 15).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background {
                if filled {
                    Capsule().fill(Noel.night.opacity(0.82))
                } else {
                    Capsule().strokeBorder(Noel.cream.opacity(0.45), lineWidth: 1.2)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Un bouton rond de la barre du haut (retour, réglages).
struct RoundIcon: View {
    var symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Noel.cream)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Noel.night.opacity(0.55)))
            .overlay(Circle().strokeBorder(Noel.cream.opacity(0.18), lineWidth: 1))
    }
}

/// Le portrait du Père Noël dans son médaillon doré.
struct SantaMedallion: View {
    var size: CGFloat = 220
    var mood: SantaMood = .idle
    var still: Double? = nil
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Noel.goldLight.opacity(0.35), .clear], center: .center, startRadius: size * 0.3, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
            Circle().fill(LinearGradient(colors: [Color(red: 0.42, green: 0.17, blue: 0.12), Color(red: 0.22, green: 0.08, blue: 0.07)], startPoint: .top, endPoint: .bottom))
            SantaView(mood: mood, portrait: true, still: still)
                .padding(size * 0.02)
                .clipShape(Circle())
            Circle().strokeBorder(Noel.goldGradient, lineWidth: size * 0.035)
            Circle().strokeBorder(Noel.cream.opacity(0.35), lineWidth: 1).padding(size * 0.035)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Neige

/// La neige qui tombe : chaque flocon a sa vitesse, sa taille et son balancement. Calculé à partir du temps,
/// sans état : léger, et figé si « Réduire les animations » est activé.
struct Snowfall: View {
    var count = 90
    var speed = 1.0
    var opacity = 0.9
    /// Neige figée (images exportées).
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if still {
                Canvas { ctx, size in flakes(&ctx, size, t: 40) }
            } else {
                TimelineView(.animation(minimumInterval: Motion.interval, paused: reduce)) { tl in
                    Canvas { ctx, size in flakes(&ctx, size, t: reduce ? 40 : tl.date.timeIntervalSinceReferenceDate) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func flakes(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double) {
        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let r1 = fract(sin(seed) * 43758.5453), r2 = fract(sin(seed * 1.7) * 23421.631), r3 = fract(sin(seed * 2.3) * 9631.7)
            let depth = 0.35 + r3 * 0.65
            let fall = (18 + 34 * depth) * speed
            let y = (r2 * (size.height + 40) + t * fall).truncatingRemainder(dividingBy: size.height + 40) - 20
            let x = r1 * size.width + sin(t * (0.4 + r3) + seed) * 14 * depth
            let d = 1.4 + depth * 3.2
            ctx.opacity = opacity * (0.35 + 0.65 * depth)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white))
        }
    }
}

func fract(_ x: Double) -> Double { x - floor(x) }

// MARK: - La nuit du pôle Nord

/// Le ciel de nuit, la lune, les étoiles qui scintillent, les collines enneigées et les sapins.
struct NightScene: View {
    var moon = true
    var trees = true
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.03, green: 0.06, blue: 0.13), Noel.night, Color(red: 0.07, green: 0.20, blue: 0.20)],
                               startPoint: .top, endPoint: .bottom)
                // aurore boréale très discrète
                Ellipse().fill(RadialGradient(colors: [Noel.forest.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: w * 0.7))
                    .frame(width: w * 1.6, height: h * 0.35).rotationEffect(.degrees(-12)).offset(x: w * 0.1, y: -h * 0.22).blur(radius: 30)
                if still {
                    Canvas { ctx, size in stars(&ctx, size, t: 0) }
                } else {
                    TimelineView(.animation(minimumInterval: Motion.interval ?? 1 / 20, paused: reduce)) { tl in
                        Canvas { ctx, size in stars(&ctx, size, t: tl.date.timeIntervalSinceReferenceDate) }
                    }
                }
                if moon {
                    Circle().fill(RadialGradient(colors: [Noel.goldLight.opacity(0.45), .clear], center: .center, startRadius: 30, endRadius: 150))
                        .frame(width: 300, height: 300).position(x: w * 0.78, y: h * 0.13)
                    Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.84), Noel.goldLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 74, height: 74)
                        .overlay(Circle().fill(Noel.gold.opacity(0.25)).frame(width: 14, height: 14).offset(x: -12, y: -8))
                        .overlay(Circle().fill(Noel.gold.opacity(0.2)).frame(width: 9, height: 9).offset(x: 14, y: 12))
                        .position(x: w * 0.78, y: h * 0.13)
                }
                if trees { Hills(width: w, height: h) }
            }
        }
        .ignoresSafeArea()
    }

    private func stars(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double) {
        let fixed = reduce || still
        for i in 0..<70 {
            let s = Double(i) * 7.31
            let x = fract(sin(s) * 9182.3) * size.width
            let y = fract(sin(s * 1.3) * 5121.7) * size.height * 0.62
            let tw = fixed ? 0.55 + 0.45 * fract(s * 3.1) : 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (0.6 + fract(s) * 1.4) + s))
            let d = 1 + fract(sin(s * 2.1) * 311.1) * 1.8
            ctx.opacity = tw
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(Noel.cream))
        }
    }
}

/// Les collines de neige et les sapins, en trois plans pour la profondeur.
struct Hills: View {
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        ZStack {
            hill(top: 0.70, amp: 0.035, color: Color(red: 0.62, green: 0.70, blue: 0.78))
            trees(at: [0.06, 0.14, 0.88, 0.95], base: 0.735, scale: 0.55, color: Color(red: 0.08, green: 0.22, blue: 0.20))
            hill(top: 0.77, amp: 0.04, color: Color(red: 0.80, green: 0.86, blue: 0.90))
            trees(at: [0.03, 0.18, 0.82, 0.97], base: 0.81, scale: 0.85, color: Noel.fir)
            hill(top: 0.86, amp: 0.03, color: Color(red: 0.95, green: 0.97, blue: 0.98))
        }
    }

    private func hill(top: CGFloat, amp: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: height * top))
            p.addCurve(to: CGPoint(x: width, y: height * (top - amp * 0.5)),
                       control1: CGPoint(x: width * 0.3, y: height * (top - amp * 1.6)),
                       control2: CGPoint(x: width * 0.65, y: height * (top + amp)))
            p.addLine(to: CGPoint(x: width, y: height)); p.addLine(to: CGPoint(x: 0, y: height)); p.closeSubpath()
        }
        .fill(color)
    }

    private func trees(at xs: [CGFloat], base: CGFloat, scale: CGFloat, color: Color) -> some View {
        ZStack {
            ForEach(Array(xs.enumerated()), id: \.offset) { i, x in
                FirTree(color: color)
                    .frame(width: 70 * scale * (i % 2 == 0 ? 1 : 0.8), height: 120 * scale * (i % 2 == 0 ? 1 : 0.8))
                    .position(x: width * x, y: height * base - 50 * scale * (i % 2 == 0 ? 1 : 0.8))
            }
        }
    }
}

/// Un sapin en trois étages, la neige posée sur chaque branche.
struct FirTree: View {
    var color: Color
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            ctx.fill(Path(CGRect(x: w * 0.45, y: h * 0.86, width: w * 0.1, height: h * 0.14)), with: .color(Color(red: 0.25, green: 0.16, blue: 0.10)))
            for (i, tier) in [(0.0, 0.42), (0.22, 0.66), (0.44, 0.9)].enumerated() {
                let top = h * tier.0, bottom = h * tier.1, half = w * (0.26 + 0.12 * Double(i))
                var p = Path()
                p.move(to: CGPoint(x: w / 2, y: top))
                p.addLine(to: CGPoint(x: w / 2 + half, y: bottom))
                p.addLine(to: CGPoint(x: w / 2 - half, y: bottom))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
                var snow = Path()
                snow.move(to: CGPoint(x: w / 2 - half * 0.95, y: bottom))
                snow.addQuadCurve(to: CGPoint(x: w / 2 + half * 0.95, y: bottom), control: CGPoint(x: w / 2, y: bottom - h * 0.07))
                snow.addQuadCurve(to: CGPoint(x: w / 2 - half * 0.95, y: bottom), control: CGPoint(x: w / 2, y: bottom + h * 0.03))
                ctx.fill(snow, with: .color(.white.opacity(0.9)))
            }
        }
    }
}

// MARK: - L'atelier du Père Noël

/// L'atelier : murs de bois chauds, la fenêtre sur la nuit enneigée, une guirlande, le feu qui rougeoie.
struct WorkshopScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.10, blue: 0.08), Color(red: 0.36, green: 0.16, blue: 0.10), Color(red: 0.20, green: 0.08, blue: 0.07)],
                               startPoint: .top, endPoint: .bottom)
                // planches du mur
                Canvas { ctx, s in
                    for i in 0..<9 {
                        let x = s.width * Double(i) / 8
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1.2, height: s.height)), with: .color(.black.opacity(0.18)))
                    }
                }
                // la fenêtre
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.20), Noel.night], startPoint: .top, endPoint: .bottom))
                    Snowfall(count: 26, speed: 0.6, opacity: 0.8).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    Circle().fill(Noel.goldLight).frame(width: 26, height: 26).offset(x: 34, y: -46).shadow(color: Noel.goldLight, radius: 12)
                    Rectangle().fill(Color(red: 0.42, green: 0.22, blue: 0.13)).frame(width: 7)
                    Rectangle().fill(Color(red: 0.42, green: 0.22, blue: 0.13)).frame(height: 7)
                    RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(red: 0.46, green: 0.25, blue: 0.14), lineWidth: 10)
                    VStack { Spacer(); Capsule().fill(.white).frame(height: 16).padding(.horizontal, 4) }
                }
                .frame(width: w * 0.36, height: h * 0.25)
                .position(x: w * 0.2, y: h * 0.27)
                // étagère et paquets
                shelf(w: w, h: h)
                // la lueur du feu, en bas
                TimelineView(.animation(minimumInterval: Motion.interval ?? 1 / 15, paused: reduce)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let flicker = reduce ? 0.8 : 0.72 + 0.12 * sin(t * 7.3) + 0.08 * sin(t * 13.1)
                    Ellipse().fill(RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(0.55 * flicker), .clear], center: .center, startRadius: 0, endRadius: w * 0.7))
                        .frame(width: w * 1.6, height: h * 0.5)
                        .position(x: w * 0.5, y: h * 1.0)
                }
                Garland(width: w).frame(height: 70).position(x: w / 2, y: 46)
            }
        }
        .ignoresSafeArea()
    }

    private func shelf(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Color(red: 0.42, green: 0.22, blue: 0.13)).frame(width: w * 0.34, height: 10)
            HStack(alignment: .bottom, spacing: 6) {
                Gift(color: Noel.forest, ribbon: Noel.gold).frame(width: 34, height: 30)
                Gift(color: Noel.red, ribbon: Noel.cream).frame(width: 26, height: 40)
                Gift(color: Noel.gold, ribbon: Noel.red).frame(width: 30, height: 24)
            }
            .padding(.bottom, 10)
        }
        .position(x: w * 0.82, y: h * 0.33)
    }
}

/// Un paquet cadeau.
struct Gift: View {
    var color: Color
    var ribbon: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(color)
            Rectangle().fill(ribbon).frame(width: 5)
            Rectangle().fill(ribbon).frame(height: 5)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 0) { Circle().stroke(ribbon, lineWidth: 3).frame(width: 9); Circle().stroke(ribbon, lineWidth: 3).frame(width: 9) }.offset(y: -7)
        }
    }
}

/// La guirlande d'ampoules chaudes qui traverse le haut de l'atelier.
struct Garland: View {
    var width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.interval ?? 1 / 12, paused: reduce)) { tl in
            Canvas { ctx, s in
                let t = tl.date.timeIntervalSinceReferenceDate
                var wire = Path()
                wire.move(to: CGPoint(x: -10, y: 10))
                wire.addQuadCurve(to: CGPoint(x: s.width / 2, y: 18), control: CGPoint(x: s.width / 4, y: 50))
                wire.addQuadCurve(to: CGPoint(x: s.width + 10, y: 10), control: CGPoint(x: s.width * 0.75, y: 50))
                ctx.stroke(wire, with: .color(.black.opacity(0.5)), lineWidth: 1.5)
                let colors: [Color] = [Noel.gold, Noel.red, Noel.goldLight, Color(red: 0.45, green: 0.85, blue: 0.55)]
                for i in 0..<12 {
                    let u = (Double(i) + 0.5) / 12
                    let x = u * s.width
                    let half = u < 0.5 ? u * 2 : (u - 0.5) * 2
                    let y = 12 + 20 * sin(.pi * half)
                    let on = reduce ? 1 : 0.6 + 0.4 * (0.5 + 0.5 * sin(t * 2 + Double(i) * 1.7))
                    let c = colors[i % colors.count]
                    ctx.opacity = on
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 14, y: y - 8, width: 28, height: 28)), with: .color(c.opacity(0.25)))
                    ctx.opacity = 1
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y + 2, width: 10, height: 13)), with: .color(c.opacity(on)))
                }
            }
        }
    }
}

// MARK: - Étincelles

/// Une pluie d'étoiles dorées (la surprise de fin d'appel, la fin magique).
struct StarBurst: View {
    var start: Date
    var count = 40

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.interval)) { tl in
            Canvas { ctx, s in
                let t = tl.date.timeIntervalSince(start)
                guard t >= 0 else { return }
                let c = CGPoint(x: s.width / 2, y: s.height * 0.42)
                for i in 0..<count {
                    let seed = Double(i) * 3.7
                    let ang = fract(sin(seed) * 1000) * .pi * 2
                    let speed = 120 + fract(sin(seed * 2) * 800) * 260
                    let life = 2.4 + fract(sin(seed * 3) * 500)
                    guard t < life else { continue }
                    let k = t / life
                    let p = CGPoint(x: c.x + cos(ang) * speed * t, y: c.y + sin(ang) * speed * t + 60 * t * t)
                    let size = (4 + fract(sin(seed * 5) * 90) * 9) * (1 - k * 0.6)
                    ctx.opacity = 1 - k
                    ctx.fill(starPath(center: p, r: size), with: .color(i % 3 == 0 ? Noel.cream : Noel.goldLight))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

func starPath(center c: CGPoint, r: CGFloat, points: Int = 5) -> Path {
    var p = Path()
    for i in 0..<(points * 2) {
        let a = -Double.pi / 2 + Double(i) * .pi / Double(points)
        let rr = i % 2 == 0 ? r : r * 0.42
        let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path { starPath(center: CGPoint(x: rect.midX, y: rect.midY), r: min(rect.width, rect.height) / 2) }
}
