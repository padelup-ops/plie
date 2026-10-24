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
        let scale = max(0.5, min(3, 160 / max(box.height, 1)))
        let margin: CGFloat = 40
        let size = CGSize(width: box.width * scale + margin * 2, height: box.height * scale + margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            for stroke in strokes {
                let path = UIBezierPath()
                path.lineWidth = max(6, 14 * scale / 1.5)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                for (i, p) in stroke.points.enumerated() {
                    let q = CGPoint(x: (p.x - box.minX) * scale + margin, y: (p.y - box.minY) * scale + margin)
                    if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                }
                if stroke.points.count == 1, let p = stroke.points.first {
                    let q = CGPoint(x: (p.x - box.minX) * scale + margin, y: (p.y - box.minY) * scale + margin)
                    path.addLine(to: CGPoint(x: q.x + 0.5, y: q.y + 0.5))
                }
                path.stroke()
            }
        }
        guard let cg = image.cgImage else {
            completion([])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            var readings: [Int] = []
            // Lecture complète : les morceaux de gauche à droite
            let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
            if let n = number(in: joined) { readings.append(n) }
            // Autres lectures possibles de chaque morceau
            for o in observations {
                for c in o.topCandidates(5) {
                    if let n = number(in: c.string), !readings.contains(n) { readings.append(n) }
                }
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
