// Santa.swift — Allô Père Noël
//
// Le Père Noël, dessiné en SwiftUI : bonnet, lunettes dorées, sourcils de neige, joues roses, grande barbe,
// moustache. Il respire, cligne des yeux, bouge la tête, parle (la bouche suit le volume de sa voix), écoute en
// hochant la tête, rit (yeux plissés) et fait coucou à la fin. Le dessin tient dans une boîte de 1000 × 1200 :
// on pourra le remplacer plus tard par une animation professionnelle sans toucher au reste.

import SwiftUI

enum SantaMood: Equatable { case idle, talking, listening, laughing, waving, surprised }

struct SantaView: View {
    /// Ouverture de la bouche, de 0 à 1 (le volume de la voix).
    var mouth: Double = 0
    var mood: SantaMood = .idle
    /// Seulement la tête et les épaules (avatar d'appel entrant, accueil).
    var portrait = false
    /// Un instant figé (images exportées : la carte souvenir).
    var still: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            if let still {
                Canvas { ctx, size in draw(&ctx, size: size, t: still) }
            } else {
                TimelineView(.animation(paused: reduce)) { tl in
                    Canvas { ctx, size in
                        let t = reduce ? 0 : tl.date.timeIntervalSinceReferenceDate
                        draw(&ctx, size: size, t: t)
                    }
                }
            }
        }
        .aspectRatio(portrait ? 1 : 1000 / 1200, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Santa Claus"))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        // Boîte de 1000 × 1200 (portrait : on recadre sur la tête).
        let box = portrait ? CGRect(x: 170, y: 60, width: 660, height: 660) : CGRect(x: 0, y: 0, width: 1000, height: 1200)
        let k = min(size.width / box.width, size.height / box.height)
        ctx.translateBy(x: (size.width - box.width * k) / 2 - box.minX * k, y: (size.height - box.height * k) / 2 - box.minY * k)
        ctx.scaleBy(x: k, y: k)

        let breath = sin(t * 1.6) * 0.008
        let blink = blinkAmount(t)
        var tilt = sin(t * 0.7) * 1.6
        var nod = 0.0
        switch mood {
        case .listening: nod = sin(t * 3.2) * 10; tilt += sin(t * 0.9) * 2
        case .laughing: nod = abs(sin(t * 9)) * -9
        case .talking: nod = sin(t * 2.3) * 3
        default: break
        }

        // le corps (manteau, bras)
        var body = ctx
        body.translateBy(x: 500, y: 1200)
        body.scaleBy(x: 1 + breath, y: 1 + breath * 1.4)
        body.translateBy(x: -500, y: -1200)
        drawCoat(&body)
        if mood == .waving { drawWavingArm(&body, t: t) }

        // la tête
        var head = ctx
        head.translateBy(x: 500, y: 640 + nod)
        head.rotate(by: .degrees(tilt))
        head.translateBy(x: -500, y: -640)
        drawHead(&head, t: t, blink: blink)
    }

    // MARK: Le manteau

    private func drawCoat(_ ctx: inout GraphicsContext) {
        var coat = Path()
        coat.move(to: CGPoint(x: 120, y: 1200))
        coat.addCurve(to: CGPoint(x: 300, y: 830), control1: CGPoint(x: 130, y: 1000), control2: CGPoint(x: 190, y: 870))
        coat.addQuadCurve(to: CGPoint(x: 700, y: 830), control: CGPoint(x: 500, y: 760))
        coat.addCurve(to: CGPoint(x: 880, y: 1200), control1: CGPoint(x: 810, y: 870), control2: CGPoint(x: 870, y: 1000))
        coat.closeSubpath()
        ctx.fill(coat, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.16, blue: 0.18), Noel.red, Noel.bordeaux]),
                                             startPoint: CGPoint(x: 500, y: 780), endPoint: CGPoint(x: 500, y: 1200)))
        // plis du manteau
        for x in [300.0, 700.0] {
            var fold = Path()
            fold.move(to: CGPoint(x: x, y: 900))
            fold.addQuadCurve(to: CGPoint(x: x + (x < 500 ? -40 : 40), y: 1200), control: CGPoint(x: x + (x < 500 ? 10 : -10), y: 1050))
            ctx.stroke(fold, with: .color(Noel.bordeaux.opacity(0.6)), lineWidth: 10)
        }
        // la bande de fourrure au milieu
        ctx.fill(Path(roundedRect: CGRect(x: 452, y: 860, width: 96, height: 360), cornerRadius: 40), with: .color(Noel.snow))
        for y in stride(from: 880.0, through: 1180, by: 60) {
            ctx.fill(Path(ellipseIn: CGRect(x: 440, y: y, width: 40, height: 40)), with: .color(Noel.snow))
            ctx.fill(Path(ellipseIn: CGRect(x: 520, y: y + 20, width: 40, height: 40)), with: .color(Noel.snow))
        }
        // boutons dorés
        for y in [960.0, 1080.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: 487, y: y, width: 26, height: 26)), with: .color(Noel.gold))
        }
    }

    private func drawWavingArm(_ ctx: inout GraphicsContext, t: Double) {
        var arm = ctx
        arm.translateBy(x: 780, y: 900)
        arm.rotate(by: .degrees(-35 + sin(t * 7) * 16))
        var sleeve = Path(roundedRect: CGRect(x: -55, y: -330, width: 120, height: 360), cornerRadius: 60)
        sleeve = sleeve.applying(.identity)
        arm.fill(sleeve, with: .linearGradient(Gradient(colors: [Noel.red, Noel.bordeaux]), startPoint: CGPoint(x: 0, y: -330), endPoint: CGPoint(x: 0, y: 30)))
        arm.fill(Path(roundedRect: CGRect(x: -68, y: -360, width: 146, height: 70), cornerRadius: 35), with: .color(Noel.snow))
        // la moufle
        arm.fill(Path(ellipseIn: CGRect(x: -62, y: -500, width: 130, height: 160)), with: .color(Noel.forest))
        arm.fill(Path(ellipseIn: CGRect(x: 40, y: -440, width: 56, height: 80)), with: .color(Noel.forest))
    }

    // MARK: La tête

    private func drawHead(_ ctx: inout GraphicsContext, t: Double, blink: Double) {
        let happy = mood == .laughing || mood == .waving || mood == .surprised
        // cheveux sur les côtés
        for (x, y, r) in [(318.0, 470.0, 70.0), (300.0, 540.0, 62.0), (682.0, 470.0, 70.0), (700.0, 540.0, 62.0)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.96)))
        }
        // le visage
        ctx.fill(Path(ellipseIn: CGRect(x: 340, y: 340, width: 320, height: 370)),
                 with: .radialGradient(Gradient(colors: [Noel.skin, Color(red: 0.92, green: 0.72, blue: 0.60)]),
                                       center: CGPoint(x: 480, y: 480), startRadius: 20, endRadius: 220))
        // joues
        for x in [395.0, 605.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 52, y: 520 - 40, width: 104, height: 80)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.93, green: 0.48, blue: 0.45).opacity(0.75), .clear]),
                                           center: CGPoint(x: x, y: 520), startRadius: 0, endRadius: 56))
        }
        // les yeux
        for x in [437.0, 563.0] {
            if happy {
                var arc = Path()
                arc.move(to: CGPoint(x: x - 20, y: 470))
                arc.addQuadCurve(to: CGPoint(x: x + 20, y: 470), control: CGPoint(x: x, y: 448))
                ctx.stroke(arc, with: .color(Color(red: 0.18, green: 0.11, blue: 0.09)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            } else {
                let h = 40 * max(0.08, 1 - blink)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 15, y: 466 - h / 2, width: 30, height: h)), with: .color(Color(red: 0.18, green: 0.11, blue: 0.09)))
                if blink < 0.5 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: 466 - h / 2 + 6, width: 9, height: 9 * (1 - blink))), with: .color(.white.opacity(0.9)))
                }
            }
        }
        // les lunettes dorées
        var glasses = Path()
        glasses.addEllipse(in: CGRect(x: 437 - 52, y: 466 - 44, width: 104, height: 88))
        glasses.addEllipse(in: CGRect(x: 563 - 52, y: 466 - 44, width: 104, height: 88))
        ctx.fill(glasses, with: .color(.white.opacity(0.08)))
        ctx.stroke(glasses, with: .color(Noel.gold), lineWidth: 7)
        var bridge = Path()
        bridge.move(to: CGPoint(x: 489, y: 462)); bridge.addQuadCurve(to: CGPoint(x: 511, y: 462), control: CGPoint(x: 500, y: 450))
        ctx.stroke(bridge, with: .color(Noel.gold), lineWidth: 6)
        // les sourcils, qui se lèvent quand il pose une question ou s'étonne
        let lift: Double = mood == .listening || mood == .surprised ? -14 : (mood == .talking ? sin(t * 3.1) * -4 : 0)
        for x in [437.0, 563.0] {
            var brow = Path()
            let outer: Double = x < 500 ? -1 : 1
            // côté extérieur un peu plus bas : un regard doux
            brow.move(to: CGPoint(x: x - 46 * outer, y: 400 + lift))
            brow.addQuadCurve(to: CGPoint(x: x + 46 * outer, y: 412 + lift), control: CGPoint(x: x, y: 376 + lift))
            ctx.stroke(brow, with: .color(.white), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        }
        // la barbe : un grand nuage de neige
        let beard: [(Double, Double, Double)] = [(372, 575, 92), (420, 660, 108), (500, 700, 125), (580, 660, 108), (628, 575, 92),
                                                 (440, 780, 105), (560, 780, 105), (500, 850, 100), (470, 905, 70), (530, 905, 70)]
        for (x, y, r) in beard {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [.white, Color(white: 0.90)]), center: CGPoint(x: x - r * 0.3, y: y - r * 0.4), startRadius: 0, endRadius: r * 1.2))
        }
        // la bouche (suit la voix)
        let open = mood == .laughing ? 0.55 + 0.25 * abs(sin(t * 9)) : max(0, min(1, mouth))
        let mh = 12 + open * 62
        ctx.fill(Path(ellipseIn: CGRect(x: 500 - 44, y: 612 - mh / 2 + 8, width: 88, height: mh)), with: .color(Color(red: 0.42, green: 0.12, blue: 0.13)))
        if open > 0.25 {
            ctx.fill(Path(ellipseIn: CGRect(x: 500 - 26, y: 612 + mh / 2 - 18, width: 52, height: 22)), with: .color(Color(red: 0.85, green: 0.42, blue: 0.45)))
        }
        // la moustache
        for dir in [-1.0, 1.0] {
            var m = Path()
            m.move(to: CGPoint(x: 500, y: 560))
            m.addCurve(to: CGPoint(x: 500 + dir * 150, y: 585), control1: CGPoint(x: 500 + dir * 40, y: 540), control2: CGPoint(x: 500 + dir * 110, y: 545))
            m.addQuadCurve(to: CGPoint(x: 500 + dir * 175, y: 550), control: CGPoint(x: 500 + dir * 180, y: 580))
            m.addCurve(to: CGPoint(x: 500, y: 612), control1: CGPoint(x: 500 + dir * 170, y: 625), control2: CGPoint(x: 500 + dir * 60, y: 630))
            m.closeSubpath()
            ctx.fill(m, with: .color(.white))
            ctx.stroke(m, with: .color(Color(white: 0.86)), lineWidth: 3)
        }
        // le nez
        ctx.fill(Path(ellipseIn: CGRect(x: 462, y: 498, width: 76, height: 66)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.98, green: 0.70, blue: 0.62), Color(red: 0.88, green: 0.50, blue: 0.45)]),
                                       center: CGPoint(x: 488, y: 515), startRadius: 0, endRadius: 50))
        ctx.fill(Path(ellipseIn: CGRect(x: 478, y: 508, width: 18, height: 12)), with: .color(.white.opacity(0.6)))
        // le bonnet
        drawHat(&ctx, t: t)
    }

    private func drawHat(_ ctx: inout GraphicsContext, t: Double) {
        let sway = sin(t * 1.3) * 10
        var cone = Path()
        cone.move(to: CGPoint(x: 330, y: 360))
        cone.addCurve(to: CGPoint(x: 600, y: 140), control1: CGPoint(x: 340, y: 230), control2: CGPoint(x: 470, y: 130))
        cone.addCurve(to: CGPoint(x: 800 + sway, y: 300 + sway * 0.5), control1: CGPoint(x: 700, y: 150), control2: CGPoint(x: 790 + sway, y: 220))
        cone.addCurve(to: CGPoint(x: 680, y: 360), control1: CGPoint(x: 760 + sway, y: 280), control2: CGPoint(x: 700, y: 260))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color(red: 0.82, green: 0.17, blue: 0.19), Noel.red, Noel.bordeaux]),
                                             startPoint: CGPoint(x: 400, y: 160), endPoint: CGPoint(x: 700, y: 360)))
        // la fourrure du bonnet
        ctx.fill(Path(roundedRect: CGRect(x: 300, y: 320, width: 400, height: 95), cornerRadius: 47), with: .color(.white))
        for x in stride(from: 320.0, through: 680, by: 52) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 26, y: 306, width: 52, height: 46)), with: .color(.white))
        }
        // le pompon
        let p = CGPoint(x: 808 + sway, y: 318 + sway * 0.5)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 58, y: p.y - 58, width: 116, height: 116)),
                 with: .radialGradient(Gradient(colors: [.white, Color(white: 0.88)]), center: CGPoint(x: p.x - 18, y: p.y - 22), startRadius: 0, endRadius: 70))
    }

    /// Un clignement toutes les 3 à 5 secondes, très bref.
    private func blinkAmount(_ t: Double) -> Double {
        let period = 3.7
        let phase = t.truncatingRemainder(dividingBy: period)
        let d = abs(phase - 0.08)
        return d < 0.09 ? 1 - d / 0.09 : 0
    }
}
