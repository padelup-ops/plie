import Foundation

/// Le modèle de langue (français, anglais) : quels mots suivent quels mots, appris sur des millions de phrases
/// (corpus de Leipzig, CC BY 4.0 ; construit par tools/build_lm.py). Comme les claviers de Google ou Microsoft :
/// un modèle « n-grammes » compressé, lu directement dans le fichier (mémoire projetée). Les 60 000 mots ne sont
/// plus recopiés dans un dictionnaire : on les relit dans le fichier, classés une fois pour la recherche.
final class KBLanguageModel {
    let lang: String
    private let data: Data
    private let off: [UInt32]
    private let order: [UInt32]
    private let uniAt: Int, biOffAt: Int, biIdAt: Int, biScAt: Int
    private let nCtx: Int, ctxKeyAt: Int, ctxOffAt: Int, triIdAt: Int, triScAt: Int
    private static let scale = 12.0

    init?(lang: String) {
        guard let url = Bundle.main.url(forResource: "lm-" + lang, withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count > 24,
              d.prefix(4) == Data("FBLM".utf8) else { return nil }
        self.lang = lang
        data = d
        func u32(_ o: Int) -> Int { d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) } }
        let count = u32(8)
        let nBi = u32(12)
        nCtx = u32(16)
        let nTri = u32(20)
        var starts = [UInt32]()
        starts.reserveCapacity(count)
        let end = d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            var p = 24
            for _ in 0..<count {
                guard p < raw.count else { return -1 }
                starts.append(UInt32(p))
                p += 1 + Int(raw[p])
            }
            return p
        }
        guard end > 0, starts.count == count else { return nil }
        off = starts
        var p = end
        uniAt = p; p += count
        biOffAt = p; p += 4 * (count + 1)
        biIdAt = p; p += 2 * nBi
        biScAt = p; p += nBi
        ctxKeyAt = p; p += 4 * nCtx
        ctxOffAt = p; p += 4 * (nCtx + 1)
        triIdAt = p; p += 2 * nTri
        triScAt = p; p += nTri
        guard p <= d.count else { return nil }
        let bytes = d
        let offsets = starts
        // Classés par leurs octets (pas de chaînes fabriquées : 60 000 mots triés en quelques millisecondes).
        var idx = Array(0..<count)
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            idx.sort {
                let c = Self.compare(raw, Int(offsets[$0]), raw, Int(offsets[$1]))
                // Un mot présent deux fois : le premier du fichier d'abord (c'est lui que la recherche rend).
                return c != 0 ? c < 0 : $0 < $1
            }
        }
        order = idx.map { UInt32($0) }
    }

    /// Compare deux mots du fichier (un octet de longueur, puis les octets UTF-8) : < 0, 0 ou > 0.
    private static func compare(_ a: UnsafeRawBufferPointer, _ ao: Int, _ b: UnsafeRawBufferPointer, _ bo: Int) -> Int {
        guard ao < a.count, bo < b.count else { return ao < a.count ? 1 : (bo < b.count ? -1 : 0) }
        let an = min(Int(a[ao]), a.count - ao - 1), bn = min(Int(b[bo]), b.count - bo - 1)
        let n = min(an, bn)
        if n > 0 {
            let r = memcmp(a.baseAddress! + ao + 1, b.baseAddress! + bo + 1, n)
            if r != 0 { return Int(r) }
        }
        return an - bn
    }

    private func wordAt(_ i: Int) -> String {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String in
            let o = Int(off[i])
            guard o < raw.count else { return "" }
            let n = Int(raw[o])
            let a = o + 1, b = min(a + n, raw.count)
            return String(decoding: UnsafeRawBufferPointer(rebasing: raw[a..<b]), as: UTF8.self)
        }
    }

    // MARK: Lecture

    private func u8(_ o: Int) -> Int { data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in Int(raw[o]) } }
    private func u16(_ o: Int) -> Int { data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) } }
    private func u32(_ o: Int) -> Int { data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) } }

    private func id(_ word: String) -> Int? {
        var key = word.lowercased().replacingOccurrences(of: "'", with: "’")
        if !key.utf8.allSatisfy({ $0 < 0x80 }) { key = key.precomposedStringWithCanonicalMapping }
        // Le mot cherché, au format du fichier (longueur puis octets), comparé octet par octet.
        var probe: [UInt8] = [0]
        probe.append(contentsOf: key.utf8)
        guard probe.count <= 256 else { return nil }
        probe[0] = UInt8(probe.count - 1)
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            probe.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> Int? in
                var lo = 0, hi = order.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if Self.compare(raw, Int(off[Int(order[mid])]), p, 0) < 0 { lo = mid + 1 } else { hi = mid }
                }
                guard lo < order.count, Self.compare(raw, Int(off[Int(order[lo])]), p, 0) == 0 else { return nil }
                return Int(order[lo])
            }
        }
    }

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
        if b >= 0, let a, a >= 0 { out = trigrams(a, b).map { wordAt($0.0) } }
        if b >= 0 { for (i, _) in bigrams(b) where !out.contains(wordAt(i)) { out.append(wordAt(i)) } }
        return Array(out.filter { $0 != "<s>" && !$0.hasSuffix("’") }.prefix(limit))
    }

    /// Le mot existe-t-il dans le modèle (et à quel rang de fréquence) ?
    func rank(_ word: String) -> Int? { id(word) }
}
