// LeonidaMap.swift — Vicefold
//
// La carte de Leonida : la « GTA VI Community Map » v18 de Yanis et de la communauté de cartographie, en tuiles de
// GTADB.org, sous licence Creative Commons Attribution 4.0 — recadrée sur l'État (sans la légende de la source).
// Une carte de fans, pas celle de Rockstar. Les niveaux 0 à 4 sont dans l'app (pas besoin de réseau) : on ne dessine
// que les tuiles à l'écran, au niveau de détail qui correspond au zoom.

import SwiftUI
import UIKit

enum Leonida {
    /// Le cadre de la carte, en mètres du jeu : de -11 264 à 3 840 m d'ouest en est, de 11 264 à -9 216 m du nord au
    /// sud. Les positions des lieux et des épingles sont de 0 à 1 dans ce cadre.
    static let size = CGSize(width: 15104, height: 20480)
    /// L'eau, de la même couleur que celle des tuiles (pas de raccord visible au bord).
    static let water = Color(red: 44 / 255, green: 103 / 255, blue: 164 / 255)
    static let maxLevel = 4

    static let credit = "Map: GTA VI Community Map v18 by Yanis & the mapping community, via GTADB.org (CC BY 4.0), cropped"
    static let sourceURL = URL(string: "https://map.gtadb.org")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    /// Le niveau de tuiles qui donne une image nette sans en charger trop, pour `s` points d'écran par mètre.
    static func level(pointsPerMeter s: CGFloat, scale: CGFloat) -> Int {
        let wanted = log2(max(0.0001, 32 * s * scale * 0.7))
        return max(0, min(maxLevel, Int(wanted.rounded(.up))))
    }

    /// Les tuiles du niveau `z` qui touchent `r` (coordonnées de la carte, en mètres depuis le coin haut-gauche).
    static func tiles(level z: Int, in r: CGRect) -> [(name: String, rect: CGRect)] {
        let side = 256 * 32 / pow(2, CGFloat(z))
        let frame = CGRect(origin: .zero, size: size)
        let v = r.intersection(frame)
        guard !v.isNull, !v.isEmpty else { return [] }
        let x0 = Int(floor((v.minX + 5120) / side)), x1 = Int(floor((v.maxX + 5120) / side))
        let y0 = Int(floor((v.minY + 5120) / side)), y1 = Int(floor((v.maxY + 5120) / side))
        var out: [(String, CGRect)] = []
        for ty in y0...y1 {
            for tx in x0...x1 {
                out.append(("\(z),\(ty),\(tx)", CGRect(x: CGFloat(tx) * side - 5120, y: CGFloat(ty) * side - 5120, width: side, height: side)))
            }
        }
        return out
    }

    /// Dessine la carte : d'abord un niveau grossier (jamais de trou pendant qu'on zoome), puis le bon niveau.
    /// `holo` : la carte recolorée en hologramme (voir `hologram`) ; sinon ses couleurs d'origine, un peu assombries
    /// pour la nuit.
    @MainActor
    static func draw(_ ctx: inout GraphicsContext, visible r: CGRect, level z: Int, holo: Bool) {
        var base = ctx
        if holo { base.addFilter(.colorMatrix(hologram)) }
        base.fill(Path(r.insetBy(dx: -size.width, dy: -size.height)), with: .color(water))
        var c = base
        c.clip(to: Path(CGRect(origin: .zero, size: size)))
        let levels = z > 1 ? [max(0, z - 2), z] : [z]
        for lv in levels {
            for t in tiles(level: lv, in: r) {
                if let img = TileCache.shared.image(level: lv, name: t.name) {
                    c.draw(Image(uiImage: img), in: t.rect)
                }
            }
        }
        if !holo { ctx.fill(Path(r.insetBy(dx: -size.width, dy: -size.height)), with: .color(.black.opacity(0.22))) }
    }

    /// Le réglage « couleurs d'origine » (faux par défaut : hologramme).
    static let styleKey = "vicefold.mapOriginal"

    /// L'hologramme : une simple transformation des couleurs de la même carte, faite à l'affichage (les tuiles ne
    /// sont pas modifiées). La mer devient bleu nuit, la terre un cyan sombre, les routes un cyan clair ; une part
    /// de la teinte d'origine reste, pour distinguer parcs, plages et quartiers.
    /// sortie = bleu nuit + (1,25 × rouge − 0,15) × teinte + 0,3 × chrominance d'origine.
    static let hologram: ColorMatrix = {
        var m = ColorMatrix()
        m.r1 = 0.2862; m.r2 = -0.2146; m.r3 = -0.0217; m.r4 = 0; m.r5 = 0.014
        m.g1 = 0.3862; m.g2 = 0.0854; m.g3 = -0.0217; m.g4 = 0; m.g5 = -0.014
        m.b1 = 0.5362; m.b2 = -0.2146; m.b3 = 0.2783; m.b4 = 0; m.b5 = 0.038
        m.a1 = 0; m.a2 = 0; m.a3 = 0; m.a4 = 1; m.a5 = 0
        return m
    }()
}

/// Les tuiles déjà décodées (on en garde quelques centaines en mémoire).
@MainActor
final class TileCache {
    static let shared = TileCache()
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()
    private var missing = Set<String>()

    func image(level z: Int, name: String) -> UIImage? {
        if let i = cache.object(forKey: name as NSString) { return i }
        if missing.contains(name) { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Tiles/\(z)"),
              let img = UIImage(contentsOfFile: url.path) else {
            missing.insert(name)
            return nil
        }
        let ready = img.preparingForDisplay() ?? img
        cache.setObject(ready, forKey: name as NSString)
        return ready
    }
}
