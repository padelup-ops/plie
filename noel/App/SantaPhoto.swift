// SantaPhoto.swift — Allô Père Noël
//
// Le Père Noël, en photo (un portrait créé par IA, qui n'est la photo de personne), et vivant : sa bouche s'ouvre
// avec le volume réel de sa voix (donc avec n'importe quelle phrase, prénom compris), il respire, hoche la tête quand
// il écoute, et tressaute quand il rit.
//
// La bouche, ce sont des photos préparées d'avance (tools/photo_warp.py : la mâchoire descend, le sombre de la bouche
// apparaît sous la moustache), fondues les unes dans les autres : cinq ouvertures. Rien n'est calculé sur l'iPhone,
// et l'app montre exactement les images qui ont été réglées et regardées une à une. Il ne cligne pas des yeux : des
// paupières fabriquées par déformation, derrière des lunettes, se voyaient (mieux vaut pas de clignement du tout).

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
    /// Le nombre de photos « bouche ouverte » (SantaMouth1 … SantaMouth5).
    private static let mouthFrames = 5

    private var live: Bool { !still && !reduce && ShotMode.route == nil }

    var body: some View {
        GeometryReader { geo in
            if live {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    frame(in: geo.size, t: tl.date.timeIntervalSinceReferenceDate)
                }
            } else {
                frame(in: geo.size, t: nil)
            }
        }
        .clipped()
        .task { SantaFrames.warm() }
        .accessibilityElement()
        .accessibilityLabel(Text("Santa Claus"))
    }

    private func frame(in box: CGSize, t: Double?) -> some View {
        // La photo (3:4) couvre le cadre, avec un peu de marge pour bouger sans montrer ses bords.
        let w = max(box.width, box.height * 0.75) * zoom * (t == nil ? 1 : 1.035)
        let h = w * 4 / 3
        let ox = min(0, max(box.width - w, focus.x * box.width - Self.face.x * w))
        let oy = min(0, max(box.height - h, focus.y * box.height - Self.face.y * h))
        let m = pose(t)
        return ZStack(alignment: .topLeading) {
            Color.black
            picture(w: w, h: h, open: m.open)
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

    /// La photo au repos, puis la bouche (la photo de l'ouverture juste en dessous, pleine, et la suivante qui
    /// apparaît en fondu).
    private func picture(w: CGFloat, h: CGFloat, open: Double) -> some View {
        let steps = Double(Self.mouthFrames)
        let x = min(steps, max(0, open * steps))
        let below = Int(x.rounded(.down))
        let above = min(Self.mouthFrames, below + 1)
        let mix = x - Double(below)
        return ZStack {
            SantaFrames.image("SantaPhoto").resizable()
            if below >= 1 {
                SantaFrames.image("SantaMouth\(below)").resizable()
            }
            if above > below, mix > 0.01 {
                SantaFrames.image("SantaMouth\(above)").resizable().opacity(mix)
            }
        }
        .frame(width: w, height: h)
    }

    private struct Pose {
        var open = 0.0, breath = 0.0, tilt = 0.0, dx = 0.0, dy = 0.0, fire = 0.0
    }

    private func pose(_ t: Double?) -> Pose {
        var m = Pose()
        m.open = pow(min(1, max(0, mouth) * 1.3), 0.85)
        guard let t else {
            if mood == .laughing { m.open = max(m.open, 0.55) }
            return m
        }
        m.breath = sin(t * 1.5) * 0.004
        m.tilt = sin(t * 0.6) * 0.45 + sin(t * 0.23) * 0.25
        m.dx = sin(t * 0.41) * 1.6
        m.fire = (sin(t * 7.3) * 0.5 + sin(t * 12.1) * 0.3 + sin(t * 3.1) * 0.2) * 0.035
        switch mood {
        case .talking:
            m.dy = sin(t * 2.3) * 1.4 - m.open * 1.2
            m.tilt += sin(t * 1.7) * 0.25
        case .listening:
            // Il écoute : de petits hochements de tête.
            m.dy = max(0, sin(t * 2.8)) * 4
            m.tilt += sin(t * 0.9) * 0.5
        case .laughing:
            // « Ho, ho, ho ! » : il tressaute.
            m.dy = -abs(sin(t * 9)) * 5
            m.open = max(m.open, 0.3 + 0.25 * abs(sin(t * 9)))
        case .waving:
            m.tilt += sin(t * 3.2) * 1.1
        case .surprised:
            m.open = max(m.open, 0.5)
            m.dy = -3
        case .idle:
            break
        }
        return m
    }
}

/// Les photos du Père Noël, ouvertes une fois pour toutes dès qu'il apparaît : sa première phrase ne doit pas
/// attendre qu'une image se décode (la bouche sauterait sur les premiers mots).
@MainActor
enum SantaFrames {
    private static var ready: [String: UIImage] = [:]
    private static var warming = false
    private static let names = ["SantaPhoto"] + (1...5).map { "SantaMouth\($0)" }

    static func image(_ name: String) -> Image {
        if let ui = ready[name] { return Image(uiImage: ui) }
        return Image(name)
    }

    static func warm() {
        guard !warming else { return }
        warming = true
        Task {
            for name in names {
                guard let ui = UIImage(named: name) else { continue }
                ready[name] = await ui.byPreparingForDisplay() ?? ui
            }
        }
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
