import SwiftUI
import UIKit
import Vision

// MARK: - Écrire à la craie
//
// L'enfant écrit sa réponse avec le doigt. Chaque trait est dessiné comme une craie :
// plusieurs passages fins et irréguliers, du grain, un peu de poussière. Ensuite on lit le
// nombre écrit avec la reconnaissance d'écriture d'iOS (sur le téléphone, rien n'est envoyé).

struct ChalkStroke: Equatable {
    var points: [CGPoint] = []
}

enum ChalkDrawing {
    /// Dessine les traits à la craie. Le grain dépend de la position du point (il ne scintille pas).
    static func draw(_ context: inout GraphicsContext, strokes: [ChalkStroke], width: CGFloat, color: Color) {
        for (s, stroke) in strokes.enumerated() {
            let pts = stroke.points
            guard let first = pts.first else { continue }
            if pts.count == 1 {
                context.fill(Path(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)),
                             with: .color(color.opacity(0.85)))
                continue
            }
            // Plusieurs passages décalés, comme les bords irréguliers d'un bâton de craie
            for pass in 0..<4 {
                var path = Path()
                for (i, p) in pts.enumerated() {
                    let jx = CGFloat(Draw.hash(i * 7 + pass, s * 13 + 1) - 0.5) * width * 0.45
                    let jy = CGFloat(Draw.hash(i * 7 + pass, s * 13 + 2) - 0.5) * width * 0.45
                    let q = CGPoint(x: p.x + jx, y: p.y + jy)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                let lw = width * [0.55, 0.4, 0.3, 0.7][pass]
                context.stroke(path, with: .color(color.opacity([0.55, 0.45, 0.6, 0.18][pass])),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
            // Grain : de petits trous sombres et des poussières claires le long du trait
            for (i, p) in pts.enumerated() where i % 2 == 0 {
                for k in 0..<3 {
                    let ox = CGFloat(Draw.hash(i * 3 + k, s * 17 + 5) - 0.5) * width * 1.1
                    let oy = CGFloat(Draw.hash(i * 3 + k, s * 17 + 6) - 0.5) * width * 1.1
                    let r = CGFloat(0.5 + 1.2 * Draw.hash(i * 3 + k, s * 17 + 7))
                    let dust = Draw.hash(i * 3 + k, s * 17 + 8) > 0.55
                    context.fill(Path(ellipseIn: CGRect(x: p.x + ox - r, y: p.y + oy - r, width: r * 2, height: r * 2)),
                                 with: .color(dust ? color.opacity(0.35) : Color(hex: 0x24493A).opacity(0.55)))
                }
            }
        }
    }
}

enum ChalkReader {
    /// Lit les nombres écrits. Renvoie toutes les lectures possibles (la plus probable d'abord).
    static func read(strokes: [ChalkStroke], completion: @escaping ([Int]) -> Void) {
        let all = strokes.flatMap(\.points)
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else {
            completion([])
            return
        }
        // Image noir sur blanc, à la bonne taille, pour la reconnaissance d'écriture
        let box = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        let scale = max(0.3, min(3, 160 / max(box.height, 1)))
        let margin: CGFloat = 60
        // Assez large (un « 1 » tout seul est très étroit) : la lecture de texte d'Apple aime une ligne.
        let inkW = box.width * scale, inkH = box.height * scale
        let size = CGSize(width: max(inkW + margin * 2, inkH * 2.5 + margin * 2), height: inkH + margin * 2)
        let ox = (size.width - inkW) / 2 - margin
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            for stroke in strokes {
                let path = UIBezierPath()
                path.lineWidth = 16
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                for (i, p) in stroke.points.enumerated() {
                    let q = CGPoint(x: (p.x - box.minX) * scale + margin + ox, y: (p.y - box.minY) * scale + margin)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                if stroke.points.count == 1, let p = stroke.points.first {
                    let q = CGPoint(x: (p.x - box.minX) * scale + margin + ox, y: (p.y - box.minY) * scale + margin)
                    path.addLine(to: CGPoint(x: q.x + 0.5, y: q.y + 0.5))
                }
                path.stroke()
            }
        }
        guard let cg = image.cgImage else {
            completion([])
            return
        }
        // Notre propre lecteur de chiffres (formes), qui marche même pour un chiffre tout seul.
        let shapes = DigitShapes.read(strokes: strokes)
        DispatchQueue.global(qos: .userInitiated).async {
            var readings: [Int] = []
            // La lecture de texte d'Apple, précise puis rapide.
            for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                request.minimumTextHeight = 0.1
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                // Lecture complète : les morceaux de gauche à droite
                let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
                if let n = number(in: joined), !readings.contains(n) { readings.append(n) }
                // Autres lectures possibles de chaque morceau
                for o in observations {
                    for c in o.topCandidates(5) {
                        if let n = number(in: c.string), !readings.contains(n) { readings.append(n) }
                    }
                }
                if !readings.isEmpty { break }
            }
            // Les formes : la lecture la plus probable d'abord si Apple n'a rien lu, sinon en plus.
            if readings.isEmpty {
                readings = shapes
            } else {
                for n in shapes where !readings.contains(n) { readings.append(n) }
            }
            DispatchQueue.main.async { completion(readings) }
        }
    }

    /// Les enfants écrivent parfois un 1 comme un « l », un 0 comme un « O »… on corrige.
    static func number(in text: String) -> Int? {
        let map: [Character: Character] = ["O": "0", "o": "0", "D": "0", "Q": "0", "l": "1", "I": "1", "|": "1", "i": "1", "!": "1",
                                           "Z": "2", "z": "2", "S": "5", "s": "5", "B": "8", "g": "9", "q": "9", "G": "6", "b": "6", "T": "7", "A": "4"]
        var digits = ""
        for ch in text where !ch.isWhitespace {
            if ch.isNumber, ch.isASCII {
                digits.append(ch)
            } else if let d = map[ch] {
                digits.append(d)
            } else if ch == "." || ch == "," || ch == "-" || ch == "_" {
                continue
            } else {
                return nil
            }
        }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        return Int(digits)
    }
}

/// Lecteur de chiffres écrits au doigt : on coupe le dessin en chiffres (de gauche à droite), puis chaque chiffre
/// est comparé à des modèles par nuage de points ($P, Vatavu, Anthony et Wobbrock 2012) : peu importe l'ordre
/// et le sens des traits, la taille ou la position.
enum DigitShapes {
    private typealias Pt = (x: Double, y: Double, id: Int)
    private static let n = 32

    /// Les lectures possibles (la plus probable d'abord).
    static func read(strokes: [ChalkStroke]) -> [Int] {
        let groups = split(strokes.filter { !$0.points.isEmpty })
        guard !groups.isEmpty, groups.count <= 4 else { return [] }
        var options: [[(Int, Double)]] = []
        for g in groups {
            let ranked = classify(g)
            guard let best = ranked.first else { return [] }
            // Le meilleur chiffre, et le deuxième s'il est presque aussi proche.
            var o = [best]
            if ranked.count > 1, ranked[1].1 < best.1 * 1.25 { o.append(ranked[1]) }
            options.append(o)
        }
        var numbers: [[Int]] = [[]]
        for o in options {
            numbers = numbers.flatMap { prefix in o.map { prefix + [$0.0] } }
            if numbers.count > 16 { numbers = Array(numbers.prefix(16)) }
        }
        var out: [Int] = []
        for digits in numbers {
            let v = digits.reduce(0) { $0 * 10 + $1 }
            if !out.contains(v) { out.append(v) }
        }
        return out
    }

    /// Coupe en chiffres : les traits qui se chevauchent de gauche à droite vont ensemble.
    private static func split(_ strokes: [ChalkStroke]) -> [[ChalkStroke]] {
        let all = strokes.flatMap(\.points)
        guard let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let h = max(20, maxY - minY)
        let items = strokes.map { s -> (ChalkStroke, CGFloat, CGFloat) in
            let xs = s.points.map(\.x)
            return (s, xs.min() ?? 0, xs.max() ?? 0)
        }.sorted { $0.1 < $1.1 }
        var groups: [(strokes: [ChalkStroke], x0: CGFloat, x1: CGFloat)] = []
        for (s, x0, x1) in items {
            if var last = groups.last {
                let overlap = min(last.x1, x1) - max(last.x0, x0)
                let narrow = min(last.x1 - last.x0, x1 - x0)
                // Chevauchement net, ou trait minuscule collé (barre du 7, drapeau du 1…)
                if overlap > max(4, narrow * 0.3) || (x0 - last.x1 < h * 0.08 && narrow < h * 0.25) {
                    last.strokes.append(s)
                    last.x0 = min(last.x0, x0)
                    last.x1 = max(last.x1, x1)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append(([s], x0, x1))
        }
        return groups.map(\.strokes)
    }

    /// Les chiffres, du plus proche au plus loin (distance $P).
    private static func classify(_ strokes: [ChalkStroke]) -> [(Int, Double)] {
        var raw: [Pt] = []
        for (i, s) in strokes.enumerated() {
            for p in s.points { raw.append((Double(p.x), Double(p.y), i)) }
            if s.points.count == 1, let p = s.points.first { raw.append((Double(p.x) + 0.5, Double(p.y) + 0.5, i)) }
        }
        guard raw.count >= 2 else { return [] }
        let cloud = normalize(raw)
        var best: [Int: Double] = [:]
        for t in templates {
            let d = match(cloud, t.cloud)
            if d < best[t.digit] ?? .infinity { best[t.digit] = d }
        }
        return best.sorted { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: $P

    private static func normalize(_ pts: [Pt]) -> [Pt] {
        var r = resample(pts)
        let xs = r.map(\.x), ys = r.map(\.y)
        let size = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!, 1e-6)
        let x0 = xs.min()!, y0 = ys.min()!
        r = r.map { (($0.x - x0) / size, ($0.y - y0) / size, $0.id) }
        let cx = r.map(\.x).reduce(0, +) / Double(r.count), cy = r.map(\.y).reduce(0, +) / Double(r.count)
        return r.map { ($0.x - cx, $0.y - cy, $0.id) }
    }

    private static func resample(_ pts: [Pt]) -> [Pt] {
        var length = 0.0
        for i in 1..<pts.count where pts[i].id == pts[i - 1].id { length += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        let step = length / Double(n - 1)
        guard step > 0 else { return Array(repeating: pts[0], count: n) }
        var out: [Pt] = [pts[0]]
        var acc = 0.0
        var p = pts
        var i = 1
        while i < p.count {
            if p[i].id == p[i - 1].id {
                let d = hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y)
                if acc + d >= step, d > 0 {
                    let t = (step - acc) / d
                    let q: Pt = (p[i - 1].x + t * (p[i].x - p[i - 1].x), p[i - 1].y + t * (p[i].y - p[i - 1].y), p[i].id)
                    out.append(q)
                    p.insert(q, at: i)
                    acc = 0
                } else {
                    acc += d
                }
            }
            i += 1
        }
        while out.count < n { out.append(pts[pts.count - 1]) }
        return Array(out.prefix(n))
    }

    private static func match(_ a: [Pt], _ b: [Pt]) -> Double {
        let stepN = max(1, Int(pow(Double(n), 0.5)))
        var best = Double.infinity
        var i = 0
        while i < n {
            best = min(best, cloud(a, b, i), cloud(b, a, i))
            i += stepN
        }
        return best
    }

    private static func cloud(_ a: [Pt], _ b: [Pt], _ start: Int) -> Double {
        var used = [Bool](repeating: false, count: n)
        var sum = 0.0
        var i = start
        repeat {
            var minD = Double.infinity, index = 0
            for j in 0..<n where !used[j] {
                let d = hypot(a[i].x - b[j].x, a[i].y - b[j].y)
                if d < minD { minD = d; index = j }
            }
            used[index] = true
            let weight = 1 - Double((i - start + n) % n) / Double(n)
            sum += weight * minD
            i = (i + 1) % n
        } while i != start
        return sum
    }

    // MARK: Modèles (dans un carré de 0 à 1, y vers le bas)

    private static func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double) -> [(Double, Double)] {
        let steps = 18
        return (0...steps).map { k in
            let a = (a0 + (a1 - a0) * Double(k) / Double(steps)) * .pi / 180
            return (cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    private static func line(_ pts: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for i in 0..<(pts.count - 1) {
            for k in 0..<8 {
                let t = Double(k) / 8
                out.append((pts[i].0 + t * (pts[i + 1].0 - pts[i].0), pts[i].1 + t * (pts[i + 1].1 - pts[i].1)))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private static let shapes: [(Int, [[(Double, Double)]])] = [
        (0, [arc(0.5, 0.5, 0.33, 0.5, -90, 270)]),
        (0, [arc(0.5, 0.5, 0.42, 0.5, -100, 260)]),
        (1, [line([(0.5, 0), (0.5, 1)])]),
        (1, [line([(0.25, 0.25), (0.55, 0), (0.55, 1)])]),
        (1, [line([(0.25, 0.25), (0.55, 0), (0.55, 1)]), line([(0.25, 1), (0.85, 1)])]),
        (2, [arc(0.5, 0.3, 0.38, 0.3, 190, 380) + line([(0.82, 0.42), (0.1, 1), (0.92, 1)])]),
        (2, [arc(0.5, 0.28, 0.36, 0.28, 200, 360) + line([(0.86, 0.28), (0.12, 1), (0.9, 1)])]),
        (3, [arc(0.45, 0.25, 0.35, 0.25, 200, 450) + arc(0.45, 0.74, 0.4, 0.26, 270, 520)]),
        (3, [line([(0.12, 0.02), (0.85, 0.02), (0.4, 0.42)]) + arc(0.45, 0.7, 0.4, 0.3, 280, 520)]),
        (4, [line([(0.62, 0), (0.05, 0.66), (0.92, 0.66)]), line([(0.66, 0.3), (0.66, 1)])]),
        (4, [line([(0.12, 0), (0.12, 0.6), (0.88, 0.6)]), line([(0.72, 0), (0.72, 1)])]),
        (5, [line([(0.82, 0.02), (0.22, 0.02), (0.18, 0.44)]) + arc(0.48, 0.7, 0.38, 0.3, 225, 510)]),
        (5, [line([(0.22, 0.02), (0.18, 0.44)]) + arc(0.48, 0.7, 0.38, 0.3, 225, 510), line([(0.22, 0.02), (0.85, 0.02)])]),
        (6, [line([(0.78, 0.02), (0.45, 0.15), (0.24, 0.4), (0.14, 0.68)]) + arc(0.5, 0.72, 0.36, 0.28, 180, 540)]),
        (6, [arc(0.55, 0.55, 0.42, 0.55, 290, 160) + arc(0.5, 0.74, 0.36, 0.26, 160, 520)]),
        (7, [line([(0.08, 0.02), (0.92, 0.02), (0.38, 1)])]),
        (7, [line([(0.08, 0.02), (0.92, 0.02), (0.38, 1)]), line([(0.38, 0.5), (0.82, 0.5)])]),
        (8, [arc(0.5, 0.25, 0.3, 0.25, 90, 450) + arc(0.5, 0.74, 0.36, 0.26, 270, 630)]),
        (8, [arc(0.5, 0.25, 0.28, 0.25, 0, 360), arc(0.5, 0.74, 0.36, 0.26, 0, 360)]),
        (9, [arc(0.5, 0.28, 0.34, 0.28, 0, 360) + line([(0.84, 0.28), (0.8, 1)])]),
        (9, [arc(0.48, 0.28, 0.34, 0.28, 330, 690) + line([(0.8, 0.14), (0.75, 0.6), (0.45, 1)])]),
    ]

    private static let templates: [(digit: Int, cloud: [Pt])] = shapes.map { d, strokes in
        var pts: [Pt] = []
        for (i, s) in strokes.enumerated() { for p in s { pts.append((p.0, p.1, i)) } }
        return (d, normalize(pts))
    }
}

/// L'ardoise où l'enfant écrit au doigt.
struct ChalkSlate: View {
    let lesson: EcoleLesson
    @State private var lastSound: Date = .distantPast

    var body: some View {
        GeometryReader { proxy in
            let chalk = lesson.feedback == .wrong ? Color(hex: 0xFFB3B3) : (lesson.feedback == .right ? Color(hex: 0xFFE27A) : Color(hex: 0xF4F1E6))
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x8A5A32), Color(hex: 0x5C3A1E)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2F5D46), Color(hex: 0x24493A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(ChalkDust())
                    .padding(9)
                if lesson.strokes.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text(L("Écris ta réponse ici avec le doigt"))
                            .font(.custom("ChalkboardSE-Regular", size: 20, relativeTo: .body))
                    }
                    .foregroundStyle(Color(hex: 0xF4F1E6).opacity(0.35))
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
                }
                Canvas { context, _ in
                    ChalkDrawing.draw(&context, strokes: lesson.strokes, width: max(9, min(16, proxy.size.height * 0.05)), color: chalk)
                }
                .allowsHitTesting(false)
                if lesson.reading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = value.location
                        guard p.x > 10, p.y > 10, p.x < proxy.size.width - 10, p.y < proxy.size.height - 10 else { return }
                        lesson.addChalk(p, newStroke: value.translation == .zero)
                        if Date().timeIntervalSince(lastSound) > 0.14 {
                            lastSound = Date()
                            SoundPlayer.shared.play(.chalk, volume: 0.35)
                        }
                    }
                    .onEnded { _ in lesson.endChalkStroke() }
            )
            .accessibilityElement()
            .accessibilityLabel(L("Ardoise : écris ta réponse avec le doigt"))
        }
    }
}
