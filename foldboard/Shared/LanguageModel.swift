import Foundation

/// Le modèle de langue (français, anglais) : quels mots suivent quels mots, appris sur des millions de phrases
/// (corpus de Leipzig, CC BY 4.0 ; construit par tools/build_lm.py). Comme les claviers de Google ou Microsoft :
/// un modèle « n-grammes » compressé, lu directement dans le fichier (mémoire projetée, quelques Mo), en
/// moins d'une milliseconde par touche.
final class KBLanguageModel {
    let lang: String
    private let data: Data
    private let V: Int
    private var ids: [String: Int] = [:]
    private var words: [String] = []
    private let uniAt: Int, biOffAt: Int, biIdAt: Int, biScAt: Int
    private let nCtx: Int, ctxKeyAt: Int, ctxOffAt: Int, triIdAt: Int, triScAt: Int
    private static let scale = 12.0

    init?(lang: String) {
        guard let url = Bundle.main.url(forResource: "lm-" + lang, withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 24,
              d.prefix(4) == Data("FBLM".utf8) else { return nil }
        self.lang = lang
        data = d
        func u32(_ o: Int) -> Int { d.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) } }
        V = u32(8)
        let nBi = u32(12)
        nCtx = u32(16)
        let nTri = u32(20)
        var p = 24
        words.reserveCapacity(V)
        ids.reserveCapacity(V)
        d.withUnsafeBytes { raw in
            for i in 0..<V {
                let len = Int(raw[p]); p += 1
                let w = String(decoding: UnsafeRawBufferPointer(rebasing: raw[p..<(p + len)]), as: UTF8.self)
                p += len
                words.append(w)
                if ids[w] == nil { ids[w] = i }
            }
        }
        uniAt = p; p += V
        biOffAt = p; p += 4 * (V + 1)
        biIdAt = p; p += 2 * nBi
        biScAt = p; p += nBi
        ctxKeyAt = p; p += 4 * nCtx
        ctxOffAt = p; p += 4 * (nCtx + 1)
        triIdAt = p; p += 2 * nTri
        triScAt = p; p += nTri
        guard p <= d.count else { return nil }
    }

    // MARK: Lecture

    private func u8(_ o: Int) -> Int { data.withUnsafeBytes { Int($0[o]) } }
    private func u16(_ o: Int) -> Int { data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) } }
    private func u32(_ o: Int) -> Int { data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) } }

    private func id(_ w: String) -> Int? { ids[w.lowercased().replacingOccurrences(of: "'", with: "’")] }

    /// Les suites d'un mot seul : (id, score) ; score = -ln p × 12.
    private func bigrams(_ a: Int) -> [(Int, Int)] {
        let s = u32(biOffAt + 4 * a), e = u32(biOffAt + 4 * (a + 1))
        return (s..<e).map { (u16(biIdAt + 2 * $0), u8(biScAt + $0)) }
    }

    /// Les suites d'une paire de mots (recherche dichotomique dans les clés triées).
    private func trigrams(_ a: Int, _ b: Int) -> [(Int, Int)] {
        let key = (a << 16) | b
        var lo = 0, hi = nCtx - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let k = u32(ctxKeyAt + 4 * mid)
            if k == key {
                let s = u32(ctxOffAt + 4 * mid), e = u32(ctxOffAt + 4 * (mid + 1))
                return (s..<e).map { (u16(triIdAt + 2 * $0), u8(triScAt + $0)) }
            }
            if k < key { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    // MARK: Le contexte

    /// Les deux derniers mots de la phrase en cours (avant le mot qu'on tape), découpés comme le modèle :
    /// en français, « l’ » est un mot à part. nil = début de phrase.
    func context(_ before: String) -> (Int?, Int) {
        var toks: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { toks.append(cur.lowercased()); cur = "" } }
        for ch in before.suffix(80) {
            if ".!?…\n".contains(ch) { flush(); toks.removeAll(); continue }
            if ch.isLetter || ch == "-" { cur.append(ch); continue }
            if ch == "’" || ch == "'" {
                if lang == "fr" { cur.append("’"); flush() } else { cur.append("’") }
                continue
            }
            flush()
        }
        flush()
        // Le dernier élément est le mot en cours s'il n'est pas terminé (pas d'espace après) : on l'enlève.
        if let last = before.last, last.isLetter || last == "-" { toks.removeLast() }
        let ids = toks.suffix(2).map { id($0) ?? -1 }
        if ids.isEmpty { return (nil, 0) }
        if ids.count == 1 { return (0, ids[0]) }
        return (ids[0], ids[1])
    }

    // MARK: Ce qu'on demande au modèle

    /// La « log-probabilité » d'un mot après le contexte (plus haut = plus probable), avec repli progressif :
    /// paire de mots, puis mot seul, puis fréquence du mot.
    func score(_ word: String, before: String) -> Double? {
        guard let w = id(word) else { return nil }
        let (a, b) = context(before)
        if b >= 0, let a, a >= 0, let s = trigrams(a, b).first(where: { $0.0 == w }) { return -Double(s.1) / Self.scale }
        if b >= 0, let s = bigrams(b).first(where: { $0.0 == w }) { return -Double(s.1) / Self.scale - 0.9 }
        return -Double(u8(uniAt + w)) / Self.scale - 1.8
    }

    /// Les mots les plus probables ensuite (pour la barre, après une espace).
    func next(before: String, limit: Int) -> [String] {
        let (a, b) = context(before)
        var out: [String] = []
        if b >= 0, let a, a >= 0 { out = trigrams(a, b).map { words[$0.0] } }
        if b >= 0 { for (i, _) in bigrams(b) where !out.contains(words[i]) { out.append(words[i]) } }
        // « l’ », « d’ »… ne se proposent pas seuls : ils se collent au mot suivant.
        return Array(out.filter { $0 != "<s>" && !$0.hasSuffix("’") }.prefix(limit))
    }

    /// Le mot existe-t-il dans le modèle (et à quel rang de fréquence) ?
    func rank(_ word: String) -> Int? { id(word) }
}
