// LeonidaMap.swift — Vicefold
//
// Notre carte de Leonida, dessinée ici (pas celle du jeu) : un État de fiction inspiré de la Floride, en style plan,
// avec ses régions, ses autoroutes et leurs numéros. Les coordonnées vont de 0 à 1000 (largeur) et de 0 à 1300
// (hauteur). Pour la vraie carte du jeu, chacun importe sa propre capture (voir MapView).

import SwiftUI

enum Leonida {
    static let size = CGSize(width: 1000, height: 1300)

    /// La terre ferme : le nord de l'État et la péninsule.
    static let mainland: [CGPoint] = [
        p(0, 0), p(1000, 0), p(1000, 170), p(962, 240), p(936, 330), p(918, 430), p(902, 540), p(888, 640), p(874, 730),
        p(860, 800), p(846, 870), p(822, 940), p(786, 995), p(738, 1035), p(676, 1060), p(610, 1062), p(556, 1040),
        p(508, 1000), p(468, 948), p(440, 890), p(418, 830), p(400, 770), p(388, 700), p(368, 640), p(336, 590),
        p(292, 546), p(246, 508), p(196, 470), p(150, 430), p(104, 398), p(56, 372), p(0, 360)
    ]

    /// L'île barrière face à Vice City (la plage).
    static let beachIsland: [CGPoint] = [p(905, 760), p(918, 762), p(902, 900), p(872, 968), p(864, 962), p(890, 880)]

    /// L'archipel du sud, en arc.
    static let keys: [[CGPoint]] = {
        let centers: [(Double, Double, Double)] = [(690, 1092, 30), (640, 1112, 26), (588, 1134, 34), (532, 1156, 24), (478, 1172, 30),
                                                    (420, 1186, 22), (366, 1198, 28), (310, 1206, 20), (262, 1212, 26), (214, 1216, 18)]
        return centers.map { c in
            (0..<8).map { i in
                let a = Double(i) / 8 * 2 * .pi
                return p(c.0 + cos(a) * c.2 * (1 + 0.25 * sin(a * 3)), c.1 + sin(a) * c.2 * 0.38)
            }
        }
    }()

    /// Le grand lac du centre.
    static let lake: [CGPoint] = [p(560, 420), p(612, 430), p(640, 470), p(632, 520), p(596, 548), p(548, 540), p(522, 500), p(530, 450)]

    /// Les zones colorées : parc national au nord, marais au sud-ouest, villes.
    static let park: [CGPoint] = [p(380, 40), p(560, 30), p(640, 110), p(600, 210), p(470, 230), p(380, 160)]
    static let wetlands: [CGPoint] = [p(460, 760), p(640, 740), p(760, 820), p(760, 960), p(660, 1040), p(560, 1030), p(490, 960), p(440, 860)]
    static let viceCity: [CGPoint] = [p(790, 700), p(880, 690), p(872, 800), p(850, 900), p(800, 930), p(770, 840)]
    static let gellhorn: [CGPoint] = [p(110, 300), p(230, 290), p(260, 380), p(190, 430), p(120, 390)]
    static let ambrosia: [CGPoint] = [p(470, 560), p(560, 570), p(580, 640), p(500, 660), p(460, 620)]

    struct Road { var name: String; var points: [CGPoint]; var major: Bool }

    static let roads: [Road] = [
        Road(name: "1", points: [p(960, 20), p(950, 200), p(925, 330), p(905, 470), p(890, 600), p(878, 700), p(862, 820), p(836, 920), p(780, 1000), p(700, 1050), p(640, 1100), p(560, 1140), p(470, 1170), p(360, 1196), p(230, 1214)], major: true),
        Road(name: "75", points: [p(120, 330), p(250, 420), p(340, 520), p(400, 640), p(440, 760), p(520, 820), p(660, 820), p(800, 800)], major: true),
        Road(name: "27", points: [p(560, 10), p(570, 200), p(580, 330), p(650, 470), p(620, 600), p(560, 700), p(520, 820)], major: true),
        Road(name: "41", points: [p(470, 900), p(560, 905), p(680, 890), p(810, 860)], major: false),
        Road(name: "10", points: [p(0, 250), p(200, 240), p(420, 260), p(640, 250), p(860, 230), p(1000, 220)], major: true),
        Road(name: "60", points: [p(330, 560), p(450, 520), p(580, 410), p(760, 380), p(915, 380)], major: false),
        Road(name: "98", points: [p(30, 330), p(110, 300), p(230, 290)], major: false),
    ]

    struct Label { var text: String; var at: CGPoint; var size: CGFloat }

    static let labels: [Label] = [
        Label(text: "VICE CITY", at: p(820, 790), size: 22),
        Label(text: "LEONIDA KEYS", at: p(450, 1240), size: 16),
        Label(text: "GRASSRIVERS", at: p(600, 930), size: 18),
        Label(text: "PORT GELLHORN", at: p(185, 355), size: 16),
        Label(text: "AMBROSIA", at: p(520, 610), size: 15),
        Label(text: "MOUNT KALAGA", at: p(500, 120), size: 15),
    ]

    static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    // MARK: Couleurs (plan clair ou sombre)

    struct Palette {
        var water, land, park, wetland, city, road, highway, label, outline: Color

        static func make(dark: Bool) -> Palette {
            dark
            ? Palette(water: Color(red: 0.05, green: 0.14, blue: 0.21), land: Color(red: 0.13, green: 0.14, blue: 0.16),
                      park: Color(red: 0.12, green: 0.21, blue: 0.15), wetland: Color(red: 0.14, green: 0.2, blue: 0.15),
                      city: Color(red: 0.19, green: 0.18, blue: 0.21), road: Color(white: 0.36), highway: Color(red: 0.62, green: 0.5, blue: 0.22),
                      label: Color(white: 0.78), outline: Color(white: 0.3))
            : Palette(water: Color(red: 0.66, green: 0.84, blue: 0.94), land: Color(red: 0.96, green: 0.95, blue: 0.91),
                      park: Color(red: 0.8, green: 0.9, blue: 0.76), wetland: Color(red: 0.85, green: 0.91, blue: 0.79),
                      city: Color(red: 0.93, green: 0.89, blue: 0.85), road: .white, highway: Color(red: 0.99, green: 0.83, blue: 0.36),
                      label: Color(white: 0.35), outline: Color(white: 0.75))
        }
    }

    /// Dessine la carte dans `ctx`, déjà mis à l'échelle de la vue (coordonnées de la carte).
    static func draw(_ ctx: inout GraphicsContext, palette c: Palette, zoom: CGFloat, outlineOnly: Bool = false) {
        func path(_ pts: [CGPoint]) -> Path {
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            return p
        }
        let land = path(mainland)
        if outlineOnly {
            ctx.stroke(land, with: .color(.white), lineWidth: 3 / zoom)
            ctx.stroke(path(beachIsland), with: .color(.white), lineWidth: 2 / zoom)
            for k in keys { ctx.stroke(path(k), with: .color(.white), lineWidth: 2 / zoom) }
            ctx.stroke(path(lake), with: .color(.white), lineWidth: 2 / zoom)
            return
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c.water))
        ctx.fill(land, with: .color(c.land))
        ctx.fill(path(beachIsland), with: .color(c.land))
        for k in keys { ctx.fill(path(k), with: .color(c.land)) }
        ctx.fill(path(park), with: .color(c.park))
        ctx.fill(path(wetlands), with: .color(c.wetland))
        for city in [viceCity, gellhorn, ambrosia] { ctx.fill(path(city), with: .color(c.city)) }
        ctx.fill(path(lake), with: .color(c.water))
        ctx.stroke(land, with: .color(c.outline), lineWidth: 1 / zoom)

        // Routes : un liseré, puis la route, comme un plan.
        for r in roads {
            var p = Path()
            p.addLines(r.points)
            let w: CGFloat = (r.major ? 7 : 4.5) / max(1, zoom * 0.6)
            ctx.stroke(p, with: .color(c.outline), style: StrokeStyle(lineWidth: w + 2 / zoom, lineCap: .round, lineJoin: .round))
            ctx.stroke(p, with: .color(r.major ? c.highway : c.road), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        // Le pont vers les îles.
        var bridge = Path()
        bridge.move(to: p(880, 820)); bridge.addLine(to: p(900, 815))
        ctx.stroke(bridge, with: .color(c.road), lineWidth: 3 / zoom)

        // Numéros de route : un écusson au milieu de chaque route.
        for r in roads {
            let mid = r.points[r.points.count / 2]
            let s: CGFloat = 22 / zoom
            let shield = Path(roundedRect: CGRect(x: mid.x - s * 0.75, y: mid.y - s * 0.5, width: s * 1.5, height: s), cornerRadius: s * 0.25)
            ctx.fill(shield, with: .color(r.major ? Color(red: 0.13, green: 0.36, blue: 0.75) : Color(red: 0.2, green: 0.55, blue: 0.3)))
            ctx.draw(Text(r.name).font(.system(size: 12 / zoom, weight: .heavy)).foregroundStyle(.white), at: mid)
        }

        for l in labels {
            ctx.draw(Text(l.text).font(.system(size: l.size / max(1, sqrt(zoom)), weight: .semibold)).tracking(2).foregroundStyle(c.label), at: l.at)
        }
    }
}
