// Essai : le modèle FUTO Swipe (encodeur) tourne-t-il sur iOS avec ExecuTorch ? Tracé synthétique de « computer ».
import Foundation
import ExecuTorch

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "enc.pte"
let letters = Array("qwertyuiopasdfghjklzxcvbnm")
let rowsY: [Double] = [1.0 / 6, 0.5, 5.0 / 6]
var centers: [Character: (Double, Double)] = [:]
for (i, c) in "qwertyuiop".enumerated() { centers[c] = (0.05 + 0.1 * Double(i), rowsY[0]) }
for (i, c) in "asdfghjkl".enumerated() { centers[c] = (0.10 + 0.1 * Double(i), rowsY[1]) }
for (i, c) in "zxcvbnm".enumerated() { centers[c] = (0.20 + 0.1 * Double(i), rowsY[2]) }
var keys = [Float](repeating: 0, count: 128), mask = [Bool](repeating: false, count: 64)
for (i, c) in letters.enumerated() { keys[2 * i] = Float(centers[c]!.0); keys[2 * i + 1] = Float(centers[c]!.1); mask[i] = true }
// Le tracé : de centre en centre, 64 points.
let word = Array("computer")
var pts: [(Double, Double)] = []
for i in 0..<(word.count - 1) {
    let a = centers[word[i]]!, b = centers[word[i + 1]]!
    for k in 0..<10 { let f = Double(k) / 10; pts.append((a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)) }
}
pts.append(centers[word.last!]!)
var feat = [Float](repeating: 0, count: 128)
for j in 0..<64 {
    let s = Double(j) * Double(pts.count - 1) / 63, i0 = Int(s), i1 = min(i0 + 1, pts.count - 1), f = s - Double(i0)
    feat[j] = Float(pts[i0].0 * (1 - f) + pts[i1].0 * f)
    feat[64 + j] = Float(pts[i0].1 * (1 - f) + pts[i1].1 * f)
}
let t0 = Date()
let module = Module(filePath: path)
do {
    try module.load("forward")
    print("chargé en", Int(Date().timeIntervalSince(t0) * 1000), "ms")
    let tf = Tensor<Float>(feat, shape: [1, 2, 64])
    let tk = Tensor<Float>(keys, shape: [1, 64, 2])
    let tm = Tensor<Bool>(mask, shape: [1, 64])
    for run in 0..<3 {
        let t1 = Date()
        let outs = try module.forward(tf, tk, tm)
        let ms = Date().timeIntervalSince(t1) * 1000
        guard let e: Tensor<Float> = try outs[0].tensor() else { print("pas de tenseur"); break }
        let arr: [Float] = e.withUnsafeBytes { Array($0) }
        print("sortie", e.shape, "en", String(format: "%.1f", ms), "ms (essai \(run))")
        var out = "", last = -1
        for t in 0..<32 {
            var best = 0; var bv = -Float.infinity
            for k in 0..<65 where arr[t * 65 + k] > bv { bv = arr[t * 65 + k]; best = k }
            if best != last && best != 64 && best < letters.count { out.append(letters[best]) }
            last = best
        }
        print("décodage glouton :", out)
    }
} catch {
    print("ERREUR", error)
}
