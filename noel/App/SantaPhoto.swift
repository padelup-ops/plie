// SantaPhoto.swift — Allô Père Noël
//
// Le Père Noël, en photo (un portrait créé par IA, qui n'est la photo de personne), et vivant : sa bouche s'ouvre
// avec le volume réel de sa voix (donc avec n'importe quelle phrase, prénom compris), il cligne des yeux, respire,
// hoche la tête quand il écoute, et tressaute quand il rit. La déformation est faite par App/Santa.metal, à chaque
// image. Sans carte graphique, avec « Réduire les animations » ou dans les captures : deux photos (bouche fermée,
// bouche ouverte) fondues l'une dans l'autre.

import Metal
import SwiftUI

enum SantaMood: Equatable { case idle, talking, listening, laughing, waving, surprised }

struct SantaPhoto: View {
    /// Ouverture de la bouche, de 0 à 1 (le volume de la voix).
    var mouth: Double = 0
    var mood: SantaMood = .idle
    /// 1 : la photo remplit juste le cadre ; plus : on se rapproche du visage.
    var zoom: CGFloat = 1
    /// Où tombe le milieu du visage dans le cadre.
    var focus: UnitPoint = UnitPoint(x: 0.5, y: 0.38)
    /// Une image fixe (cartes exportées, captures).
    var still = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Le milieu du visage sur la photo (entre les yeux et la bouche).
    private static let face = UnitPoint(x: 0.569, y: 0.44)
    private static let canShade: Bool = MTLCreateSystemDefaultDevice() != nil

    /// (« calllive » : une capture de contrôle, avec la vraie déformation, pour vérifier qu'elle se dessine.)
    private var live: Bool { !still && !reduce && (ShotMode.route == nil || ShotMode.route == "calllive") && Self.canShade }

    var body: some View {
        GeometryReader { geo in
            if live {
                TimelineView(.animation(minimumInterval: Motion.every(1.0 / 30))) { tl in
                    frame(in: geo.size, t: tl.date.timeIntervalSinceReferenceDate)
                }
            } else {
                frame(in: geo.size, t: nil)
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(Text("Santa Claus"))
    }

    private func frame(in box: CGSize, t: Double?) -> some View {
        // La photo (3:4) couvre le cadre, avec un peu de marge pour bouger sans montrer ses bords.
        let w = max(box.width, box.height * 0.75) * zoom * (t == nil ? 1 : 1.035)
        let h = w * 4 / 3
        let ox = min(0, max(box.width - w, focus.x * box.width - Self.face.x * w))
        let oy = min(0, max(box.height - h, focus.y * box.height - Self.face.y * h))
        let m = motion(t)
        return ZStack(alignment: .topLeading) {
            Color.black
            picture(w: w, h: h, open: m.open, blink: m.blink, shaded: t != nil)
                .scaleEffect(CGFloat(1 + m.breath), anchor: UnitPoint(x: Self.face.x, y: 0.9))
                .rotationEffect(.degrees(m.tilt), anchor: UnitPoint(x: Self.face.x, y: 0.85))
                .offset(x: ox + CGFloat(m.dx), y: oy + CGFloat(m.dy))
            // La lueur du feu qui danse, en bas à gauche.
            RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.2).opacity(0.16 + m.fire), .clear],
                           center: UnitPoint(x: 0.05, y: 0.75), startRadius: 0, endRadius: max(box.width, box.height) * 0.7)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func picture(w: CGFloat, h: CGFloat, open: Double, blink: Double, shaded: Bool) -> some View {
        if shaded {
            // La même photo dessous, sans effet : si la déformation ne pouvait pas se dessiner sur un appareil,
            // le Père Noël resterait là (immobile), jamais un écran noir.
            ZStack {
                Image("SantaPhoto").resizable()
                Image("SantaPhoto")
                    .resizable()
                    .layerEffect(ShaderLibrary.santaFace(.float2(w, h), .float(open), .float(blink)),
                                 maxSampleOffset: CGSize(width: 0, height: h * 0.07))
            }
            .frame(width: w, height: h)
        } else {
            ZStack {
                Image("SantaPhoto").resizable()
                Image("SantaPhotoOpen").resizable().opacity(min(1, open * 1.4))
            }
            .frame(width: w, height: h)
        }
    }

    private struct Motion {
        var open = 0.0, blink = 0.0, breath = 0.0, tilt = 0.0, dx = 0.0, dy = 0.0, fire = 0.0
    }

    private func motion(_ t: Double?) -> Motion {
        var m = Motion()
        m.open = pow(min(1, max(0, mouth) * 1.3), 0.85)
        guard let t else {
            if mood == .laughing { m.open = max(m.open, 0.55) }
            return m
        }
        m.breath = sin(t * 1.5) * 0.004
        m.tilt = sin(t * 0.6) * 0.45 + sin(t * 0.23) * 0.25
        m.dx = sin(t * 0.41) * 1.6
        m.fire = (sin(t * 7.3) * 0.5 + sin(t * 12.1) * 0.3 + sin(t * 3.1) * 0.2) * 0.035
        m.blink = Self.blink(t)
        switch mood {
        case .talking:
            m.dy = sin(t * 2.3) * 1.4 - m.open * 1.2
            m.tilt += sin(t * 1.7) * 0.25
        case .listening:
            // Il écoute : de petits hochements de tête.
            m.dy = max(0, sin(t * 2.8)) * 4
            m.tilt += sin(t * 0.9) * 0.5
        case .laughing:
            // « Ho, ho, ho ! » : il tressaute, les yeux plissés.
            m.dy = -abs(sin(t * 9)) * 5
            m.open = max(m.open, 0.3 + 0.25 * abs(sin(t * 9)))
            m.blink = max(m.blink, 0.42)
        case .waving:
            m.tilt += sin(t * 3.2) * 1.1
            m.blink = max(m.blink, 0.25)
        case .surprised:
            m.open = max(m.open, 0.5)
            m.dy = -3
        case .idle:
            break
        }
        return m
    }

    /// Un clignement de temps en temps (toutes les 3 à 5 secondes, parfois deux de suite).
    private static func blink(_ t: Double) -> Double {
        let period = 4.1
        let k = floor(t / period)
        let jitter = fract(sin(k * 12.9898) * 43758.5453) * 1.6
        let p = t - k * period - jitter
        func one(_ p: Double) -> Double {
            guard p > 0, p < 0.2 else { return 0 }
            return p < 0.07 ? p / 0.07 : max(0, 1 - (p - 0.07) / 0.13)
        }
        let twice = fract(sin(k * 78.233) * 12345.678) > 0.72
        return max(one(p), twice ? one(p - 0.32) : 0)
    }
}

/// Le portrait du Père Noël dans son médaillon doré.
struct SantaMedallion: View {
    var size: CGFloat = 220
    var mood: SantaMood = .idle
    var mouth: Double = 0
    /// Une image fixe (cartes exportées).
    var still: Double? = nil
    var body: some View {
        // La photo, cerclée d'or : l'anneau est à la taille de la photo, le halo dépasse derrière.
        SantaPhoto(mouth: mouth, mood: mood, zoom: 1.32, focus: UnitPoint(x: 0.5, y: 0.5), still: still != nil)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Noel.goldGradient, lineWidth: size * 0.035))
            .overlay(Circle().strokeBorder(Noel.cream.opacity(0.35), lineWidth: 1).padding(size * 0.035))
            .background(
                Circle().fill(RadialGradient(colors: [Noel.goldLight.opacity(0.35), .clear], center: .center,
                                             startRadius: size * 0.3, endRadius: size * 0.75))
                    .frame(width: size * 1.5, height: size * 1.5)
            )
        .frame(width: size, height: size)
    }
}
