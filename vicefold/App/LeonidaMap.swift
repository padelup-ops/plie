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
    @MainActor
    static func draw(_ ctx: inout GraphicsContext, visible r: CGRect, level z: Int, dark: Bool) {
        ctx.fill(Path(r.insetBy(dx: -size.width, dy: -size.height)), with: .color(water))
        var c = ctx
        c.clip(to: Path(CGRect(origin: .zero, size: size)))
        let levels = z > 1 ? [max(0, z - 2), z] : [z]
        for lv in levels {
            for t in tiles(level: lv, in: r) {
                if let img = TileCache.shared.image(level: lv, name: t.name) {
                    c.draw(Image(uiImage: img), in: t.rect)
                }
            }
        }
        if dark { c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.18))) }
    }
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
