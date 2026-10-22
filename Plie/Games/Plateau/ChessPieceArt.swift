import SwiftUI

// Fichier généré par tools/chess_art.py : dessins des pièces d'échecs dans une boîte de 100 × 100.

private struct ArtSpace {
    let r: CGRect
    var k: CGFloat { r.width / 100 }
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: r.minX + x0 * k, y: r.minY + y0 * k, width: (x1 - x0) * k, height: (y1 - y0) * k)
    }
}

/// Silhouette d'une pièce (1 pion … 6 roi).
struct ChessPieceShape: Shape {
    let type: Int8

    func path(in r: CGRect) -> Path {
        let a = ArtSpace(r: r)
        let k = a.k
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { a.pt(x, y) }
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect { a.rect(x0, y0, x1, y1) }
        _ = k
        var p = Path()
        switch type {
        case 1:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(38.5, 76))
            p.addCurve(to: pt(44.5, 55), control1: pt(40.5, 67), control2: pt(43.5, 61))
            p.addLine(to: pt(55.5, 55))
            p.addCurve(to: pt(61.5, 76), control1: pt(56.5, 61), control2: pt(59.5, 67))
            p.closeSubpath()
            p.addEllipse(in: rect(37.5, 50.4, 62.5, 57.6))
            p.addEllipse(in: rect(37.5, 27.5, 62.5, 52.5))
        case 4:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(35.5, 76))
            p.addLine(to: pt(37.5, 46))
            p.addLine(to: pt(62.5, 46))
            p.addLine(to: pt(64.5, 76))
            p.closeSubpath()
            p.addRoundedRect(in: rect(32, 41, 68, 48), cornerSize: CGSize(width: 2.5 * k, height: 2.5 * k))
            p.move(to: pt(31, 43))
            p.addLine(to: pt(31, 21))
            p.addLine(to: pt(39.5, 21))
            p.addLine(to: pt(39.5, 27.5))
            p.addLine(to: pt(46, 27.5))
            p.addLine(to: pt(46, 21))
            p.addLine(to: pt(54, 21))
            p.addLine(to: pt(54, 27.5))
            p.addLine(to: pt(60.5, 27.5))
            p.addLine(to: pt(60.5, 21))
            p.addLine(to: pt(69, 21))
            p.addLine(to: pt(69, 43))
            p.closeSubpath()
        case 2:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(31, 76))
            p.addCurve(to: pt(44, 51), control1: pt(31, 66), control2: pt(36, 58))
            p.addCurve(to: pt(30, 54.5), control1: pt(40, 50.5), control2: pt(34, 52))
            p.addCurve(to: pt(19.5, 51.5), control1: pt(26, 57), control2: pt(21, 55.5))
            p.addCurve(to: pt(23, 39), control1: pt(18, 47.5), control2: pt(20, 43))
            p.addCurve(to: pt(35, 22), control1: pt(27, 33), control2: pt(31, 27))
            p.addCurve(to: pt(42.5, 14.5), control1: pt(37.5, 18.5), control2: pt(40, 16))
            p.addLine(to: pt(43, 8))
            p.addLine(to: pt(48, 13))
            p.addCurve(to: pt(52.5, 13), control1: pt(49.5, 12.8), control2: pt(51, 12.8))
            p.addLine(to: pt(56, 8))
            p.addLine(to: pt(57, 14.5))
            p.addCurve(to: pt(73.5, 41), control1: pt(67, 18), control2: pt(73, 28))
            p.addCurve(to: pt(69, 76), control1: pt(74, 54), control2: pt(70, 64))
            p.closeSubpath()
        case 3:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(38, 76))
            p.addCurve(to: pt(43.5, 55), control1: pt(40, 67), control2: pt(43, 61))
            p.addLine(to: pt(56.5, 55))
            p.addCurve(to: pt(62, 76), control1: pt(57, 61), control2: pt(60, 67))
            p.closeSubpath()
            p.addEllipse(in: rect(36, 49.7, 64, 57.3))
            p.move(to: pt(50, 15))
            p.addCurve(to: pt(36, 40), control1: pt(39, 24), control2: pt(34.5, 32.5))
            p.addCurve(to: pt(50, 50.5), control1: pt(37.5, 47), control2: pt(43.5, 50.5))
            p.addCurve(to: pt(64, 40), control1: pt(56.5, 50.5), control2: pt(62.5, 47))
            p.addCurve(to: pt(50, 15), control1: pt(65.5, 32.5), control2: pt(61, 24))
            p.closeSubpath()
            p.addEllipse(in: rect(45.4, 7.9, 54.6, 17.1))
        case 5:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(34.5, 76))
            p.addCurve(to: pt(42, 45), control1: pt(37.5, 63), control2: pt(41, 53))
            p.addLine(to: pt(58, 45))
            p.addCurve(to: pt(65.5, 76), control1: pt(59, 53), control2: pt(62.5, 63))
            p.closeSubpath()
            p.addEllipse(in: rect(34.5, 39.8, 65.5, 48.2))
            p.move(to: pt(31, 43))
            p.addLine(to: pt(24, 20))
            p.addLine(to: pt(34, 31.5))
            p.addLine(to: pt(37.5, 13))
            p.addLine(to: pt(44.5, 29.5))
            p.addLine(to: pt(50, 9))
            p.addLine(to: pt(55.5, 29.5))
            p.addLine(to: pt(62.5, 13))
            p.addLine(to: pt(66, 31.5))
            p.addLine(to: pt(76, 20))
            p.addLine(to: pt(69, 43))
            p.closeSubpath()
            p.addEllipse(in: rect(20.1, 15.1, 27.9, 22.9))
            p.addEllipse(in: rect(33.6, 8.1, 41.4, 15.9))
            p.addEllipse(in: rect(46.1, 4.1, 53.9, 11.9))
            p.addEllipse(in: rect(58.6, 8.1, 66.4, 15.9))
            p.addEllipse(in: rect(72.1, 15.1, 79.9, 22.9))
        case 6:
            p.addRoundedRect(in: rect(21, 83, 79, 93), cornerSize: CGSize(width: 4.5 * k, height: 4.5 * k))
            p.move(to: pt(27, 85))
            p.addCurve(to: pt(36, 75), control1: pt(29, 79), control2: pt(33, 76.5))
            p.addLine(to: pt(64, 75))
            p.addCurve(to: pt(73, 85), control1: pt(67, 76.5), control2: pt(71, 79))
            p.closeSubpath()
            p.move(to: pt(34.5, 76))
            p.addCurve(to: pt(42, 45), control1: pt(37.5, 63), control2: pt(41, 53))
            p.addLine(to: pt(58, 45))
            p.addCurve(to: pt(65.5, 76), control1: pt(59, 53), control2: pt(62.5, 63))
            p.closeSubpath()
            p.addEllipse(in: rect(34.5, 39.8, 65.5, 48.2))
            p.move(to: pt(33, 43))
            p.addCurve(to: pt(50, 25), control1: pt(29.5, 32), control2: pt(37, 25))
            p.addCurve(to: pt(67, 43), control1: pt(63, 25), control2: pt(70.5, 32))
            p.closeSubpath()
            p.addRoundedRect(in: rect(46.8, 3.5, 53.2, 26.5), cornerSize: CGSize(width: 1.6 * k, height: 1.6 * k))
            p.addRoundedRect(in: rect(40.5, 9.5, 59.5, 15.9), cornerSize: CGSize(width: 1.6 * k, height: 1.6 * k))
        default:
            break
        }
        return p
    }
}

/// Traits de détail (bandeaux, fente du fou, crinière).
struct ChessPieceDetail: Shape {
    let type: Int8

    func path(in r: CGRect) -> Path {
        let a = ArtSpace(r: r)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { a.pt(x, y) }
        var p = Path()
        switch type {
        case 4:
            p.move(to: pt(34, 36))
            p.addLine(to: pt(66, 36))
            p.move(to: pt(37.5, 52))
            p.addLine(to: pt(62.5, 52))
        case 2:
            p.move(to: pt(57, 16))
            p.addCurve(to: pt(69, 42), control1: pt(64, 21), control2: pt(68.5, 30))
        case 3:
            p.move(to: pt(56.5, 25))
            p.addLine(to: pt(47.5, 37))
        case 5:
            p.move(to: pt(32.5, 38))
            p.addLine(to: pt(67.5, 38))
        case 6:
            p.move(to: pt(35.5, 37.5))
            p.addLine(to: pt(64.5, 37.5))
        default:
            break
        }
        return p
    }
}

/// Petits points pleins (œil et naseau du cavalier).
struct ChessPieceDots: Shape {
    let type: Int8

    func path(in r: CGRect) -> Path {
        let a = ArtSpace(r: r)
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect { a.rect(x0, y0, x1, y1) }
        var p = Path()
        switch type {
        case 2:
            p.addEllipse(in: rect(34.9, 24.4, 40.1, 29.6))
            p.addEllipse(in: rect(21.7, 45.5, 24.7, 48.5))
        default:
            break
        }
        return p
    }
}
