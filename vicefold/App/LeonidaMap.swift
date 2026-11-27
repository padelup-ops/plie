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
    /// `holo` : la carte recolorée en hologramme (voir `TileCache.hologram`) ; sinon ses couleurs d'origine, un peu
    /// assombries pour la nuit.
    @MainActor
    static func draw(_ ctx: inout GraphicsContext, visible r: CGRect, level z: Int, holo: Bool) {
        let around = Path(r.insetBy(dx: -size.width, dy: -size.height))
        ctx.fill(around, with: .color(holo ? holoWater : water))
        var c = ctx
        c.clip(to: Path(CGRect(origin: .zero, size: size)))
        let levels = z > 1 ? [max(0, z - 2), z] : [z]
        for lv in levels {
            for t in tiles(level: lv, in: r) {
                if let img = TileCache.shared.image(level: lv, name: t.name, holo: holo) {
                    c.draw(Image(uiImage: img), in: t.rect)
                }
            }
        }
        if !holo { ctx.fill(around, with: .color(.black.opacity(0.22))) }
    }

    /// Le réglage « couleurs d'origine » (faux par défaut : hologramme).
    static let styleKey = "vicefold.mapOriginal"
    /// L'eau en hologramme : la couleur `water` passée par la même transformation que les tuiles.
    static let holoWater = Color(red: 0, green: 18 / 255, blue: 57 / 255)
}

/// Les tuiles déjà décodées (on en garde quelques centaines en mémoire), dans leurs couleurs d'origine ou en
/// hologramme.
@MainActor
final class TileCache {
    static let shared = TileCache()
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()
    private var missing = Set<String>()

    func image(level z: Int, name: String, holo: Bool = false) -> UIImage? {
        let key = (holo ? "h:" + name : name) as NSString
        if let i = cache.object(forKey: key) { return i }
        if missing.contains(name) { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Tiles/\(z)"),
              let img = UIImage(contentsOfFile: url.path) else {
            missing.insert(name)
            return nil
        }
        let shown = holo ? (Self.hologram(img) ?? img) : img
        let ready = shown.preparingForDisplay() ?? shown
        cache.setObject(ready, forKey: key)
        return ready
    }

    /// L'hologramme : une simple transformation des couleurs de la même carte, faite une fois par tuile au moment de
    /// l'afficher (les fichiers ne sont pas modifiés ; rien à recalculer ensuite pendant qu'on déplace la carte).
    /// La mer devient bleu nuit, la terre un cyan sombre, les routes un cyan clair ; une part de la teinte d'origine
    /// reste, pour distinguer parcs, plages et quartiers.
    /// sortie = bleu nuit + (1,25 × rouge − 0,15) × teinte + 0,3 × chrominance d'origine (coefficients × 1 024).
    static func hologram(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var o = 0
        let end = w * h * 4
        while o < end {
            let r = Int(px[o]), g = Int(px[o + 1]), b = Int(px[o + 2])
            let nr = (293 * r - 220 * g - 22 * b) / 1024 + 4
            let ng = (395 * r + 87 * g - 22 * b) / 1024 - 4
            let nb = (549 * r - 220 * g + 285 * b) / 1024 + 10
            px[o] = UInt8(max(0, min(255, nr)))
            px[o + 1] = UInt8(max(0, min(255, ng)))
            px[o + 2] = UInt8(max(0, min(255, nb)))
            o += 4
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }
}
