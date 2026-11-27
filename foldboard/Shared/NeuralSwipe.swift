import Foundation
import CoreGraphics
#if canImport(Darwin)
import Darwin
#endif
#if canImport(ExecuTorch)
import ExecuTorch
#endif

#if FOLDBOARD_NEURAL && !canImport(ExecuTorch)
#error("ExecuTorch introuvable : le glisser neuronal ne peut pas être compilé.")
#endif

/// Un mot déjà noté par la géométrie du glisser (arbre des mots, position, forme).
struct KBGlideCand {
    var word: String
    var folded: String
    var score: Double
}

/// Reclasse les candidats géométriques avec l'encodeur FUTO Swipe (poids non modifiés, licence
/// FUTO Model Weights 1.0). L'inférence passe par ExecuTorch (BSD). La bibliothèque GPL de FUTO
/// n'est pas utilisée. Si le modèle manque, ne charge pas, ou si la mémoire est juste, on rend
/// nil : le clavier garde l'ordre géométrique.
enum NeuralSwipe {
    /// Texte court pour le banc d'essai.
    static var reason = "idle"
    static var loads = 0
    static var calls = 0
    static var skips = 0
    static var inferMS = 0.0
    static var inferMaxMS = 0.0

    static var statusLine: String {
        let avg = calls > 0 ? inferMS / Double(calls) : 0
        let extra = detail.isEmpty ? "" : " (\(detail))"
        return "\(reason) loads=\(loads) inf=\(calls) moy=\(String(format: "%.1f", avg))ms max=\(String(format: "%.0f", inferMaxMS)) skips=\(skips) mem=\(String(format: "%.0f", footprintMB()))Mo\(extra)"
    }

    /// Le clavier tourne déjà vers 33–45 Mo (listes, modèle de langue projeté). On ne refuse plus
    /// à partir d'un plafond fixe : on regarde ce qu'iOS laisse encore allouer avant de fermer l'extension.
    static var detail = ""
    /// Le banc d'essai n'est pas une extension : il dépasse le budget du clavier sans être fermé par iOS.
    static var benchIgnoresBudget = false
    private static let lock = NSLock()
    private static var blocked = false
    private static let blank = 64
    private static let steps = 32
    private static let classes = 65
    private static let maxKeys = 64

    #if canImport(ExecuTorch)
    private static var module: Module?
    #endif

    /// Libère le modèle (les poids se rechargent au prochain glisser si la mémoire le permet).
    static func release() {
        lock.lock(); defer { lock.unlock() }
        #if canImport(ExecuTorch)
        module = nil
        #endif
    }

    /// Le filet mémoire du clavier (au-dessus de 45 Mo) ne doit pas jeter le modèle : à 45 Mo il reste
    /// souvent de la marge. On ne lâche les poids que lorsqu'iOS n'a presque plus rien à donner.
    static func releaseIfTight() {
        let avail = availableMB()
        guard avail > 0, avail < 8 else { return }
        release()
        reason = "mémoire"
        detail = String(format: "%.0f Mo libres", avail)
        publish()
    }

    /// Charge le modèle dès que le clavier apparaît, pour que les réglages puissent dire s'il est actif.
    static func warm() {
        #if canImport(ExecuTorch)
        lock.lock()
        _ = ensureLoaded()
        lock.unlock()
        publish()
        #else
        reason = "sans-runtime"
        publish()
        #endif
    }

    /// Ligne lue par l'app (le clavier et l'app ne partagent pas la mémoire, seulement le trousseau).
    static func userFacingStatus() -> (title: String, detail: String) {
        guard let raw = KBVault.loadNeural() else {
            return (NSLocalizedString("Neural swipe: not checked yet. Show the keyboard, then come back.", comment: "Shown before the keyboard has tried the model"), "")
        }
        let p = raw.components(separatedBy: "\t")
        func at(_ i: Int) -> String { i < p.count ? p[i] : "" }
        let code = at(0)
        let on = code == "on" || code == "chargé"
        let title: String
        if on {
            title = NSLocalizedString("Neural swipe: on", comment: "FUTO swipe model is running in the keyboard")
        } else {
            title = String(format: NSLocalizedString("Neural swipe: off (%@)", comment: "FUTO swipe model is not running. Argument is the reason."), why(code))
        }
        let numbers = String(format: NSLocalizedString("%@ MB used, %@ MB free", comment: "Keyboard memory, megabytes"), at(3), at(4))
        let extra = at(5).isEmpty || at(5) == "0.0" ? "" : " · \(at(5)) ms"
        let calls = at(2).isEmpty ? "0" : at(2)
        let swipes = String(format: NSLocalizedString("%@ swipes", comment: "How many swipes used the neural model"), calls)
        let alive = at(7).isEmpty ? "" : " · ×" + at(7)
        return (title, numbers + extra + " · " + swipes + alive)
    }

    private static func why(_ code: String) -> String {
        switch code {
        case "mémoire", "mémoire-après": return NSLocalizedString("not enough memory", comment: "Neural swipe stayed off")
        case "modèle-absent": return NSLocalizedString("model file missing", comment: "Neural swipe stayed off")
        case "chargement": return NSLocalizedString("could not load", comment: "Neural swipe stayed off")
        case "inférence": return NSLocalizedString("inference failed", comment: "Neural swipe stayed off")
        case "ctc-faible": return NSLocalizedString("model unsure", comment: "Neural swipe stayed off")
        case "lent": return NSLocalizedString("too slow", comment: "Neural swipe stayed off")
        case "sans-runtime": return NSLocalizedString("runtime missing", comment: "Neural swipe stayed off")
        case "idle": return NSLocalizedString("not used yet", comment: "Neural swipe stayed off")
        default: return code.isEmpty ? NSLocalizedString("not used yet", comment: "") : code
        }
    }

    private static var lastPublished = ""
    private static func publish() {
        let avg = calls > 0 ? inferMS / Double(calls) : 0
        let line = [reason, "\(loads)", "\(calls)",
                    String(format: "%.0f", footprintMB()),
                    String(format: "%.0f", availableMB()),
                    String(format: "%.1f", avg),
                    detail,
                    "\(KeyboardCanvas.alive)"].joined(separator: "\t")
        guard line != lastPublished else { return }
        lastPublished = line
        KBVault.saveNeural(line)
    }

    /// Renvoie les candidats avec un score mélangé, ou nil pour garder la géométrie telle quelle.
    static func rerank(_ items: [KBGlideCand], raw: [CGPoint], times: [TimeInterval], touch: KBTouchModel, weight: Double) -> [KBGlideCand]? {
        guard weight > 0, items.count >= 2, raw.count >= 2 else { skips += 1; return nil }
        guard !blocked else { skips += 1; reason = "off"; return nil }
        guard let logp = emissions(raw, times: times, touch: touch) else { skips += 1; return nil }
        let slots = keySlots(touch)
        guard !slots.isEmpty else { return nil }
        let start = raw[0]
        var out = items
        let n = min(40, out.count)
        var bestCTC = -Float.greatestFiniteMagnitude
        var ctcs = [Float](repeating: -.greatestFiniteMagnitude, count: n)
        var any = false
        for i in 0..<n {
            guard let seq = keySequence(out[i].folded, slots: slots, from: start), !seq.isEmpty else { continue }
            let c = ctc(logp, seq)
            ctcs[i] = c
            if c > bestCTC { bestCTC = c }
            any = true
        }
        guard any, bestCTC > -80 else { reason = "ctc-faible"; publish(); return nil }
        for i in 0..<n where ctcs[i] > -1e20 {
            out[i].score += weight * Double(ctcs[i] - bestCTC)
        }
        reason = "on"
        if calls == 1 || calls % 25 == 0 { publish() }
        return out
    }

    // MARK: Inférence

    private static func emissions(_ raw: [CGPoint], times: [TimeInterval], touch: KBTouchModel) -> [Float]? {
        #if canImport(ExecuTorch)
        lock.lock()
        defer { lock.unlock() }
        let canvas = canvasSize(touch, path: raw)
        guard canvas.width > 8, canvas.height > 8 else { reason = "canevas"; return nil }
        guard ensureLoaded() else { publish(); return nil }
        guard let module else { return nil }
        let pts = resample(raw, times: times)
        var feat = [Float](repeating: 0, count: 128)
        for j in 0..<64 {
            feat[j] = Float(pts[j].x / canvas.width)
            feat[64 + j] = Float(pts[j].y / canvas.height)
        }
        let slots = keySlots(touch)
        guard !slots.isEmpty, slots.count <= maxKeys else { reason = "touches"; return nil }
        var kx = [Float](repeating: 0, count: maxKeys * 2)
        var mask = [Bool](repeating: false, count: maxKeys)
        for s in slots {
            kx[2 * s.index] = Float(s.center.x / canvas.width)
            kx[2 * s.index + 1] = Float(s.center.y / canvas.height)
            mask[s.index] = true
        }
        let t0 = Date()
        do {
            let tf = Tensor<Float>(feat, shape: [1, 2, 64])
            let tk = Tensor<Float>(kx, shape: [1, maxKeys, 2])
            let tm = Tensor<Bool>(mask, shape: [1, maxKeys])
            let outs = try module.forward(tf, tk, tm)
            guard let first = outs.first, let e: Tensor<Float> = first.tensor() else { blocked = true; reason = "sortie"; return nil }
            let arr: [Float] = e.withUnsafeBytes { Array($0) }
            guard arr.count == steps * classes, arr.allSatisfy({ $0.isFinite }) else { blocked = true; reason = "forme"; return nil }
            let ms = Date().timeIntervalSince(t0) * 1000
            calls += 1
            inferMS += ms
            if calls > 1 { inferMaxMS = max(inferMaxMS, ms) }
            // Un passage lent (le simulateur a des pics) ne coupe pas le modèle pour la suite :
            // la moyenne reste autour de 2 ms, et le doigt est déjà levé.
            return arr
        } catch {
            blocked = true
            self.module = nil
            reason = "inférence"
            detail = String(describing: error).prefix(120).description
            return nil
        }
        #else
        reason = "sans-runtime"
        return nil
        #endif
    }

    private static func ensureLoaded() -> Bool {
        #if canImport(ExecuTorch)
        if module != nil { return true }
        guard memoryAllows() else {
            reason = "mémoire"
            detail = String(format: "%.0f Mo libres, %.0f Mo utilisés", availableMB(), footprintMB())
            return false
        }
        guard let url = Bundle.main.url(forResource: "futo-swipe-encoder-int8", withExtension: "pte") else {
            blocked = true
            reason = "modèle-absent"
            return false
        }
        let m = Module(filePath: url.path)
        do {
            try m.load("forward")
        } catch {
            blocked = true
            reason = "chargement"
            detail = String(describing: error).prefix(120).description
            return false
        }
        let left = availableMB()
        if left > 0, left < 6 {
            reason = "mémoire-après"
            detail = String(format: "%.0f Mo libres", left)
            blocked = true
            return false
        }
        module = m
        loads += 1
        reason = "on"
        return true
        #else
        reason = "sans-runtime"
        return false
        #endif
    }

    /// La mémoire qu'iOS compte pour fermer le clavier, en Mo. On ne charge pas le modèle si on est déjà haut
    /// (le clavier tourne autour de 33 Mo en frappe, et iOS le ferme vers 60–70 Mo).
    static func footprintMB() -> Double {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
        #else
        return 0
        #endif
    }

    static func availableMB() -> Double {
        #if canImport(Darwin)
        return Double(os_proc_available_memory()) / 1_048_576
        #else
        return 0
        #endif
    }

    /// Assez de marge avant qu'iOS ferme l'extension (souvent 60–70 Mo au total). Le fichier fait 1 Mo,
    /// l'activation quelques Mo : 12 Mo libres suffisent. Un plafond à 46 Mo d'empreinte refusait le
    /// modèle alors que le clavier y est déjà en écrivant.
    /// Au-dessus de 48 Mo, charger le modèle pousserait l'extension vers la fermeture (~60–70 Mo).
    private static func memoryAllows() -> Bool {
        if !benchIgnoresBudget, footprintMB() > 48 { return false }
        let avail = availableMB()
        // 18 Mo libres : le modèle chargé, il en reste plus que le palier « serré » du clavier (14), qui le rendrait.
        if avail > 0 { return avail >= 18 }
        return benchIgnoresBudget || footprintMB() < 48
    }

    /// À appeler quand le clavier mesure sa mémoire, pour que les réglages affichent l'empreinte.
    static func noteFootprint() { publish() }

    // MARK: Touches et CTC

    private struct Slot {
        var ch: Character
        var center: CGPoint
        var index: Int
    }

    private static func keySlots(_ touch: KBTouchModel) -> [Slot] {
        var pairs: [(Character, CGPoint)] = []
        for (ch, pts) in touch.centers {
            let base = Character(String(ch).folding(options: .diacriticInsensitive, locale: nil).lowercased())
            for p in pts { pairs.append((base, p)) }
        }
        pairs.sort { a, b in
            if abs(a.1.y - b.1.y) > 2 { return a.1.y < b.1.y }
            return a.1.x < b.1.x
        }
        var out: [Slot] = []
        for (ch, p) in pairs.prefix(maxKeys) {
            out.append(Slot(ch: ch, center: p, index: out.count))
        }
        return out
    }

    /// La suite de touches du mot, lettres doublées fondues (un glisser ne les sépare pas).
    private static func keySequence(_ folded: String, slots: [Slot], from start: CGPoint) -> [Int]? {
        var seq: [Int] = []
        var anchor = start
        for ch in folded {
            let base = Character(String(ch).folding(options: .diacriticInsensitive, locale: nil).lowercased())
            var best: Slot?
            var bestD = CGFloat.greatestFiniteMagnitude
            for s in slots where s.ch == base {
                let d = hypot(s.center.x - anchor.x, s.center.y - anchor.y)
                if d < bestD { bestD = d; best = s }
            }
            guard let best else { return nil }
            if seq.last != best.index { seq.append(best.index) }
            anchor = best.center
        }
        return seq
    }

    /// Log-probabilité CTC de la suite de touches (blanc = 64). `logp` est [32, 65].
    private static func ctc(_ logp: [Float], _ labels: [Int]) -> Float {
        guard !labels.isEmpty else { return -1e30 }
        var ext: [Int] = []
        ext.reserveCapacity(labels.count * 2 + 1)
        for lab in labels {
            ext.append(blank)
            ext.append(lab)
        }
        ext.append(blank)
        let u = ext.count
        let neg: Float = -1e30
        var prev = [Float](repeating: neg, count: u)
        prev[0] = logp[ext[0]]
        if u > 1 { prev[1] = logp[ext[1]] }
        for t in 1..<steps {
            var cur = [Float](repeating: neg, count: u)
            let row = t * classes
            for s in 0..<u {
                var a = prev[s]
                if s > 0 { a = logSum(a, prev[s - 1]) }
                if s > 1, ext[s] != blank, ext[s] != ext[s - 2] { a = logSum(a, prev[s - 2]) }
                cur[s] = a + logp[row + ext[s]]
            }
            prev = cur
        }
        if u == 1 { return prev[0] }
        return logSum(prev[u - 1], prev[u - 2])
    }

    private static func logSum(_ a: Float, _ b: Float) -> Float {
        if a < -1e20 { return b }
        if b < -1e20 { return a }
        let m = max(a, b)
        return m + log(1 + exp(min(a, b) - m))
    }

    private static func canvasSize(_ touch: KBTouchModel, path: [CGPoint]) -> CGSize {
        if touch.canvas.width > 8, touch.canvas.height > 8 { return touch.canvas }
        let xs = touch.centers.values.flatMap { $0.map(\.x) } + path.map(\.x)
        let ys = touch.centers.values.flatMap { $0.map(\.y) } + path.map(\.y)
        let w = (xs.max() ?? 0) + touch.keyW * 0.65
        let h = (ys.max() ?? 0) + touch.keyH * 0.65
        return CGSize(width: w, height: h)
    }

    /// Comme l'exemple FUTO : horloge à 60 Hz quand on a les temps, puis 64 points. Les temps du clavier
    /// sont en secondes ; ceux du jeu de données sont en millisecondes.
    private static func resample(_ raw: [CGPoint], times: [TimeInterval]) -> [CGPoint] {
        var p = raw
        if p.count == 1 { return Array(repeating: p[0], count: 64) }
        if times.count == p.count, let a = times.first, let b = times.last, b > a {
            let scale: Double = (b - a) > 30 ? 1 : 1000
            var pp: [CGPoint] = [p[0]]
            var tt: [Double] = [times[0] * scale]
            for i in 1..<p.count {
                let ms = times[i] * scale
                if ms > tt[tt.count - 1] {
                    pp.append(p[i])
                    tt.append(ms)
                }
            }
            if pp.count >= 2 {
                let step = 1000.0 / 60.0
                var grid: [Double] = []
                var g = tt[0]
                let end = tt[tt.count - 1]
                while g <= end + 1e-6 && grid.count < 4000 {
                    grid.append(g)
                    g += step
                }
                if grid.count >= 2 {
                    var sampled: [CGPoint] = []
                    sampled.reserveCapacity(grid.count)
                    var j = 0
                    for x in grid {
                        while j + 1 < tt.count && tt[j + 1] < x { j += 1 }
                        let j1 = min(j + 1, tt.count - 1)
                        let span = tt[j1] - tt[j]
                        let f = span > 0 ? (x - tt[j]) / span : 0
                        let q = pp[j], r = pp[j1]
                        sampled.append(CGPoint(x: q.x + CGFloat(f) * (r.x - q.x), y: q.y + CGFloat(f) * (r.y - q.y)))
                    }
                    p = sampled
                }
            }
        }
        let n = 64
        if p.count == 1 { return Array(repeating: p[0], count: n) }
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        let last = Double(p.count - 1)
        for j in 0..<n {
            let s = last * Double(j) / Double(n - 1)
            let i0 = Int(s)
            let i1 = min(i0 + 1, p.count - 1)
            let f = CGFloat(s - Double(i0))
            let a = p[i0], b = p[i1]
            out.append(CGPoint(x: a.x + f * (b.x - a.x), y: a.y + f * (b.y - a.y)))
        }
        return out
    }
}
