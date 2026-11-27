// Launch.swift — Vicefold
//
// L'animation d'ouverture : le soleil se lève sur un horizon quadrillé, entre deux palmiers ; le nom de l'app
// s'allume lettre par lettre comme un tube de néon ; puis l'écran s'ouvre en deux par le milieu, comme on déplie
// un téléphone, et laisse voir l'app. Environ 2,5 s la première fois, un peu plus d'une seconde ensuite ; un
// toucher passe tout de suite à l'ouverture. Avec « Réduire les animations » : une image fixe et un fondu.
// Tout est dessiné ici, en vecteurs (Canvas) : aucune image, aucun lettrage venu d'ailleurs.

import SwiftUI

// MARK: - Le décor

/// Un lever de soleil rayé sur une grille en perspective, des étoiles et deux palmiers en ombre.
struct SynthScene: View {
    /// Fait défiler la grille et scintiller les étoiles (secondes).
    var time: Double
    /// 0 : le soleil est sous l'horizon ; 1 : il est levé.
    var sunrise: Double = 1
    var palms = true
    /// La hauteur de l'horizon, de 0 (haut) à 1 (bas).
    var horizon: CGFloat = 0.62

    var body: some View {
        Canvas(opaque: true) { ctx, size in
            SynthScene.draw(&ctx, size: size, time: CGFloat(time), rise: CGFloat(max(0, min(1, sunrise))), palms: palms, horizon: horizon)
        }
        .accessibilityHidden(true)
    }

    private static let night = Color(red: 0.016, green: 0.020, blue: 0.055)
    private static let silhouette = Color(red: 0.020, green: 0.012, blue: 0.050)

    /// Un nombre stable entre 0 et 1 (pour semer les étoiles et varier les palmes, toujours pareil).
    private static func hash(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(CGFloat(i) * 12.9898 + CGFloat(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, time t: CGFloat, rise: CGFloat, palms: Bool, horizon: CGFloat) {
        let w = size.width, h = size.height
        let hy = h * horizon
        let unit = min(w, h)
        let warm = Double(0.30 + 0.70 * rise)
        let skyRect = CGRect(x: 0, y: 0, width: w, height: hy)
        let groundRect = CGRect(x: 0, y: hy, width: w, height: h - hy)

        // Le ciel : la nuit en haut, une brume magenta près de l'horizon.
        let sky = Gradient(stops: [
            .init(color: night, location: 0),
            .init(color: Color(red: 0.07, green: 0.03, blue: 0.20), location: 0.58),
            .init(color: Color(red: 0.36 * warm, green: 0.06 * warm, blue: 0.34 * warm), location: 1),
        ])
        ctx.fill(Path(skyRect), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: hy)))

        // Les étoiles.
        for i in 0..<70 {
            let fx = hash(i, 1), fy = hash(i, 2), fs = hash(i, 3)
            let twinkle = 0.55 + 0.45 * sin(t * (1.2 + fs * 2.4) + fx * 20)
            let r = 0.5 + fs * 1.1
            let fade = 1 - fy * 0.8
            let rect = CGRect(x: fx * w - r, y: fy * hy * 0.86 - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(Double(0.8 * twinkle * fade))))
        }

        // Le soleil : un halo, puis un disque rayé (jaune en haut, magenta en bas), coupé par l'horizon.
        let radius = unit * 0.24
        let cx = w / 2
        let cy = hy + radius * (1.08 - 1.38 * rise)
        var above = ctx
        above.clip(to: Path(skyRect))
        let halo = Gradient(colors: [Color(red: 1, green: 0.38, blue: 0.50).opacity(0.55 * warm), Color(red: 1, green: 0.26, blue: 0.60).opacity(0)])
        above.fill(Path(ellipseIn: CGRect(x: cx - radius * 3.2, y: hy - radius * 3.2, width: radius * 6.4, height: radius * 6.4)),
                   with: .radialGradient(halo, center: CGPoint(x: cx, y: hy), startRadius: 0, endRadius: radius * 3.2))
        var slices = Path()
        slices.addRect(CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 0.70))
        var y = cy - radius * 0.30
        var gap = radius * 0.025
        var band = radius * 0.14
        while y < cy + radius {
            y += gap
            slices.addRect(CGRect(x: cx - radius, y: y, width: radius * 2, height: band))
            y += band
            gap *= 1.35
            band *= 0.88
        }
        var sunCtx = above
        sunCtx.clip(to: slices)
        let sun = Gradient(stops: [
            .init(color: Color(red: 1.0, green: 0.86, blue: 0.36), location: 0),
            .init(color: Color(red: 1.0, green: 0.54, blue: 0.24), location: 0.45),
            .init(color: Color(red: 1.0, green: 0.26, blue: 0.60), location: 0.85),
            .init(color: Color(red: 0.62, green: 0.22, blue: 0.86), location: 1),
        ])
        sunCtx.fill(Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)),
                    with: .linearGradient(sun, startPoint: CGPoint(x: cx, y: cy - radius), endPoint: CGPoint(x: cx, y: cy + radius)))

        // Le sol, puis la grille : des lignes qui fuient vers l'horizon et des traverses qui avancent vers nous.
        let ground = Gradient(colors: [Color(red: 0.11 * warm, green: 0.02, blue: 0.17 * warm), night])
        ctx.fill(Path(groundRect), with: .linearGradient(ground, startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h)))
        var grid = ctx
        grid.clip(to: Path(groundRect))
        var rays = Path()
        let spacing = max(w / 6, 64)
        for i in -18...18 {
            rays.move(to: CGPoint(x: cx, y: hy))
            rays.addLine(to: CGPoint(x: cx + CGFloat(i) * spacing, y: h))
        }
        let rayShade = Gradient(colors: [Color(red: 0.24, green: 0.90, blue: 0.95).opacity(0.10 * warm), Color(red: 1, green: 0.26, blue: 0.60).opacity(0.85 * warm)])
        let shading = GraphicsContext.Shading.linearGradient(rayShade, startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h))
        grid.stroke(rays, with: .color(Color(red: 1, green: 0.26, blue: 0.60).opacity(0.10 * warm)), lineWidth: 4)
        grid.stroke(rays, with: shading, lineWidth: 1.1)
        let rows = 11
        let phase = (t * 0.32) - floor(t * 0.32)
        for k in 0..<rows {
            let z = (CGFloat(k) + phase) / CGFloat(rows)
            let ly = hy + (h - hy) * pow(z, 2.3)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: ly))
            line.addLine(to: CGPoint(x: w, y: ly))
            let alpha = Double(0.12 + 0.78 * z) * warm
            grid.stroke(line, with: .color(Color(red: 1, green: 0.26, blue: 0.60).opacity(alpha * 0.22)), lineWidth: 4)
            grid.stroke(line, with: .color(Color(red: 1, green: 0.45, blue: 0.72).opacity(alpha)), lineWidth: 1.1)
        }

        // L'horizon : un trait de lumière.
        let glow = Gradient(colors: [Color(red: 1, green: 0.40, blue: 0.66).opacity(0.55 * warm), Color(red: 1, green: 0.40, blue: 0.66).opacity(0)])
        ctx.fill(Path(CGRect(x: 0, y: hy, width: w, height: unit * 0.05)),
                 with: .linearGradient(glow, startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: hy + unit * 0.05)))
        var edge = Path()
        edge.move(to: CGPoint(x: 0, y: hy))
        edge.addLine(to: CGPoint(x: w, y: hy))
        ctx.stroke(edge, with: .color(Color(red: 1, green: 0.82, blue: 0.90).opacity(0.9 * warm)), lineWidth: 1.5)

        // Les palmiers, en ombre devant le ciel.
        if palms {
            let sway = sin(t * 0.9) * 2.2
            palm(&ctx, base: CGPoint(x: w * 0.09, y: hy + (h - hy) * 0.42), height: unit * 0.56, lean: 0.55, sway: sway, seed: 0)
            palm(&ctx, base: CGPoint(x: w * 0.93, y: hy + (h - hy) * 0.26), height: unit * 0.42, lean: -0.5, sway: -sway, seed: 20)
        }
    }

    /// Un palmier : un tronc courbe et des palmes en croissant qui retombent.
    private static func palm(_ ctx: inout GraphicsContext, base: CGPoint, height: CGFloat, lean: CGFloat, sway: CGFloat, seed: Int) {
        let crown = CGPoint(x: base.x + lean * height * 0.28, y: base.y - height)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: crown, control: CGPoint(x: base.x + lean * height * 0.02, y: base.y - height * 0.55))
        ctx.stroke(trunk, with: .color(silhouette), style: StrokeStyle(lineWidth: max(2, height * 0.036), lineCap: .round))
        let reach = height * 0.48
        let angles: [CGFloat] = [208, 176, 146, 116, 84, 54, 24, -10]
        var fronds = Path()
        for (i, degrees) in angles.enumerated() {
            let a = (degrees + (i % 2 == 0 ? sway : -sway)) * .pi / 180
            let length = reach * (0.80 + 0.20 * hash(i + seed, 9))
            let dx = cos(a), dy = -sin(a)
            let tip = CGPoint(x: crown.x + dx * length, y: crown.y + dy * length + length * 0.32)
            let mid = CGPoint(x: crown.x + dx * length * 0.5, y: crown.y + dy * length * 0.5)
            fronds.move(to: crown)
            fronds.addQuadCurve(to: tip, control: CGPoint(x: mid.x, y: mid.y - length * 0.44))
            fronds.addQuadCurve(to: crown, control: CGPoint(x: mid.x, y: mid.y - length * 0.08))
            fronds.closeSubpath()
        }
        ctx.fill(fronds, with: .color(silhouette))
        ctx.stroke(fronds, with: .color(Color(red: 1, green: 0.30, blue: 0.62).opacity(0.22)), lineWidth: 0.8)
        let nut = height * 0.035
        ctx.fill(Path(ellipseIn: CGRect(x: crown.x - nut, y: crown.y - nut, width: nut * 2, height: nut * 2)), with: .color(silhouette))
    }
}

// MARK: - Le nom en néon

/// « VICEFOLD » en tubes de néon : VICE en magenta, FOLD en cyan. `lit` donne l'allumage de chaque lettre (0…1).
struct NeonWordmark: View {
    var lit: [Double]
    var size: CGFloat

    private static let letters: [String] = ["V", "I", "C", "E", "F", "O", "L", "D"]

    var body: some View {
        HStack(spacing: size * 0.05) {
            ForEach(0..<Self.letters.count, id: \.self) { i in
                NeonLetter(letter: Self.letters[i], lit: i < lit.count ? lit[i] : 1, color: i < 4 ? VF.flamingo : VF.cyan, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Vicefold"))
    }
}

private struct NeonLetter: View {
    var letter: String
    var lit: Double
    var color: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            // Le tube éteint.
            Text(verbatim: letter).foregroundStyle(color.opacity(0.22))
            // Le tube allumé : presque blanc au cœur, la couleur dans le halo.
            Text(verbatim: letter)
                .foregroundStyle(LinearGradient(colors: [.white, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.95), radius: size * 0.045)
                .shadow(color: color.opacity(0.65), radius: size * 0.16)
                .shadow(color: color.opacity(0.40), radius: size * 0.42)
                .opacity(lit)
        }
        .font(.custom("Anton-Regular", fixedSize: size))
    }
}

// MARK: - Le déroulé

/// Les temps de l'animation (secondes). `full` : la première ouverture ; `short` : les suivantes.
struct LaunchScript {
    var sunFrom: Double
    var sunDuration: Double
    var lettersAt: Double
    var letterStep: Double
    var taglineAt: Double
    var seamAt: Double
    var foldAt: Double
    var foldDuration: Double

    static let full = LaunchScript(sunFrom: 0, sunDuration: 1.25, lettersAt: 0.70, letterStep: 0.075, taglineAt: 1.40, seamAt: 1.72, foldAt: 2.0, foldDuration: 0.55)
    static let short = LaunchScript(sunFrom: 0.55, sunDuration: 0.55, lettersAt: 0.08, letterStep: 0.03, taglineAt: 0.32, seamAt: 0.52, foldAt: 0.75, foldDuration: 0.45)

    var total: Double { foldAt + foldDuration }

    func sunrise(_ t: Double) -> Double {
        let p = max(0, min(1, t / sunDuration))
        return sunFrom + (1 - sunFrom) * (1 - pow(1 - p, 3))
    }

    /// L'allumage d'une lettre : elle s'allume, clignote deux fois comme un tube qui chauffe, puis reste.
    func lit(_ t: Double, letter i: Int) -> Double {
        let dt = t - (lettersAt + Double(i) * letterStep)
        if dt < 0 { return 0 }
        if dt < 0.05 { return 1 }
        if dt < 0.09 { return 0.12 }
        if dt < 0.15 { return 0.9 }
        if dt < 0.19 { return 0.3 }
        return 1
    }

    func tagline(_ t: Double) -> Double { max(0, min(1, (t - taglineAt) / 0.25)) }
    func seam(_ t: Double) -> Double { max(0, min(1, (t - seamAt) / max(0.01, foldAt - seamAt))) }
    func fold(_ t: Double) -> Double { max(0, min(1, (t - foldAt) / foldDuration)) }
}

/// Une image de l'animation, à l'instant `t`.
struct LaunchFrame: View {
    var t: Double
    var script: LaunchScript
    /// Le décor bouge-t-il (grille, étoiles) ? Non avec « Réduire les animations ».
    var moving = true

    var body: some View {
        GeometryReader { geo in
            let p = script.fold(t)
            if p <= 0 {
                scene(geo.size)
            } else {
                // L'ouverture : deux moitiés qui pivotent autour des bords de l'écran, comme un téléphone qu'on déplie.
                let eased = p * p * (3 - 2 * p)
                ZStack {
                    half(geo.size, leading: true, p: eased)
                    half(geo.size, leading: false, p: eased)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func half(_ size: CGSize, leading: Bool, p: Double) -> some View {
        scene(size)
            // Les moitiés s'assombrissent en s'ouvrant (un voile noir par-dessus : elles restent opaques).
            .overlay(Color.black.opacity(0.45 * p))
            .mask(alignment: leading ? .leading : .trailing) { Rectangle().frame(width: size.width / 2 + 0.5) }
            .compositingGroup()
            .rotation3DEffect(.degrees((leading ? -1 : 1) * 100 * p), axis: (x: 0, y: 1, z: 0),
                              anchor: leading ? .leading : .trailing, anchorZ: 0, perspective: 0.45)
            .opacity(1 - p * p * p)
    }

    private func scene(_ size: CGSize) -> some View {
        let wide = size.width > size.height
        let letter = min(size.width / 5.4, size.height * (wide ? 0.17 : 0.12), 132)
        let lit = (0..<8).map { script.lit(t, letter: $0) }
        let seam = script.seam(t)
        return ZStack {
            SynthScene(time: moving ? t : 0, sunrise: script.sunrise(t), horizon: wide ? 0.66 : 0.62)
            VStack(spacing: letter * 0.14) {
                NeonWordmark(lit: lit, size: letter)
                Text("Unofficial fan companion")
                    .vfHUD(VF.text.opacity(0.85), size: max(10, letter * 0.13))
                    .opacity(script.tagline(t))
            }
            .frame(maxWidth: .infinity)
            .position(x: size.width / 2, y: size.height * (wide ? 0.20 : 0.25))
            // Le pli : un trait de lumière au milieu, juste avant l'ouverture.
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: size.height * seam)
                .shadow(color: VF.cyan.opacity(0.9), radius: 6)
                .shadow(color: VF.cyan.opacity(0.6), radius: 18)
                .opacity(seam > 0 ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// L'animation d'ouverture, posée par-dessus l'app au démarrage à froid.
struct LaunchView: View {
    var finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// Un toucher : on saute directement à l'ouverture.
    @State private var skippedAt: Double?
    @State private var faded = false

    private static let seenKey = "vicefold.launchSeen"
    // Choisi une fois, à l'ouverture (un état : il ne change pas si la vue est recréée pendant l'animation).
    @State private var script: LaunchScript = UserDefaults.standard.bool(forKey: LaunchView.seenKey) ? .short : .full

    /// Au démarrage : toujours, sauf pendant les captures (où seules les routes « launch… » la montrent, figée).
    static var wanted: Bool { ShotMode.route == nil || ShotMode.launchFrame != nil }

    var body: some View {
        Group {
            if let frozen = ShotMode.launchFrame {
                LaunchFrame(t: frozen, script: .full, moving: false)
            } else if reduceMotion {
                LaunchFrame(t: script.foldAt - 0.001, script: script, moving: false)
                    .opacity(faded ? 0 : 1)
                    .task {
                        try? await Task.sleep(for: .seconds(0.9))
                        withAnimation(.easeInOut(duration: 0.35)) { faded = true }
                        try? await Task.sleep(for: .seconds(0.4))
                        finished()
                    }
            } else {
                TimelineView(.animation) { tl in
                    LaunchFrame(t: clock(tl.date), script: script)
                }
                .task(id: skippedAt) {
                    let left = script.total - clock(Date())
                    if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                    if !Task.isCancelled { finished() }
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { skip() }
        .onAppear { UserDefaults.standard.set(true, forKey: Self.seenKey) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Vicefold"))
        .accessibilityHint("Skip the intro")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { skip() }
    }

    private func clock(_ now: Date) -> Double {
        let elapsed = now.timeIntervalSince(start)
        guard let s = skippedAt, s < script.foldAt else { return elapsed }
        return script.foldAt + max(0, elapsed - s)
    }

    private func skip() {
        guard ShotMode.launchFrame == nil else { return }
        if reduceMotion { finished(); return }
        let now = Date().timeIntervalSince(start)
        if skippedAt == nil, now < script.foldAt { skippedAt = now }
    }
}
