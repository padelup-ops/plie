import Foundation
import CoreGraphics
import UIKit

// Banc d'essai de la saisie Foldboard : correction, glisser, prédiction. Tourne dans le simulateur iOS (CI).
// Les tirages sont fixes (graine) : deux versions du moteur se comparent sur exactement les mêmes essais.

struct RNG {
    var s: UInt64
    mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func gauss() -> Double { let u = max(1e-9, next()), v = next(); return sqrt(-2 * log(u)) * cos(2 * .pi * v) }
}

let keyW: CGFloat = 36, keyH: CGFloat = 46

func centers(_ rows: [String], insets: [CGFloat]) -> [Character: [CGPoint]] {
    var c: [Character: [CGPoint]] = [:]
    for (r, row) in rows.enumerated() {
        for (i, ch) in row.enumerated() {
            c[ch, default: []].append(CGPoint(x: (CGFloat(i) + 0.5 + insets[r]) * keyW, y: (CGFloat(r) + 0.5) * keyH))
        }
    }
    return c
}

func nearestKey(_ p: CGPoint, _ c: [Character: [CGPoint]]) -> Character {
    var best: Character = "a", bd = CGFloat.greatestFiniteMagnitude
    for (k, ps) in c { for q in ps { let d = hypot((q.x - p.x) / keyW, (q.y - p.y) / keyH); if d < bd { bd = d; best = k } } }
    return best
}

func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

struct Lang {
    let code: String, layout: KBLayout, rows: [String], insets: [CGFloat], sentences: [String]
}

let fr = Lang(code: "fr", layout: .azerty, rows: ["azertyuiop", "qsdfghjklm", "wxcvbn"], insets: [0, 0, 1.5], sentences: [
    "je suis en train de partir", "tu viens à quelle heure ce soir", "on se retrouve devant la gare",
    "merci beaucoup pour ton message", "je te rappelle dans cinq minutes", "est-ce que tu as reçu mon mail",
    "il fait très beau aujourd’hui", "je ne sais pas encore si je peux venir", "on mange ensemble demain midi",
    "je suis désolé pour le retard", "peux-tu m’envoyer la photo", "ça marche pour moi", "bonne journée à toi",
    "je pense que c’est une bonne idée", "on peut en parler plus tard", "tu as vu le match hier soir",
    "je vais faire les courses", "il faut que je travaille ce week-end", "je suis arrivé à la maison",
    "dis-moi quand tu es prêt", "je t’attends en bas", "c’était vraiment super", "on se voit la semaine prochaine",
    "j’ai oublié mes clés", "tu peux passer me chercher", "je n’ai pas compris ta question",
    "le train a beaucoup de retard", "je vais me coucher bonne nuit", "tu veux venir avec nous",
    "je suis en réunion jusqu’à seize heures", "il y a un problème avec la voiture", "je t’envoie l’adresse",
    "on commande une pizza ce soir", "je suis vraiment content pour toi", "à quelle heure commence le film",
    "j’ai besoin de ton aide", "je reviens tout de suite", "tu as raison", "je vais essayer de venir",
    "merci pour hier soir", "on part en vacances la semaine prochaine", "je n’ai plus de batterie",
    "est-ce que tu es libre demain", "je suis en route", "je t’appelle après le travail",
    "c’est quoi le nom du restaurant", "je viens de finir", "on se parle plus tard", "fais attention à toi",
    "je ne trouve pas mon téléphone",
])

let en = Lang(code: "en", layout: .qwerty, rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"], insets: [0, 0.5, 1.5], sentences: [
    "i am on my way", "what time are you coming tonight", "let me know when you get there",
    "thank you so much for your help", "i will call you back in five minutes", "did you get my email",
    "the weather is really nice today", "i am not sure if i can make it", "do you want to have lunch tomorrow",
    "sorry i am running late", "can you send me the picture", "that sounds good to me", "have a great day",
    "i think that is a good idea", "we can talk about it later", "did you watch the game last night",
    "i am going to the store", "i have to work this weekend", "i just got home", "let me know when you are ready",
    "i am waiting for you outside", "that was really fun", "see you next week", "i forgot my keys",
    "can you pick me up", "i do not understand your question", "the train is very late",
    "i am going to bed good night", "do you want to come with us", "i am in a meeting until four",
    "there is a problem with the car", "i will send you the address", "we are ordering pizza tonight",
    "i am really happy for you", "what time does the movie start", "i need your help", "i will be right back",
    "you are right", "i will try to come", "thanks for last night", "we are going on vacation next week",
    "my phone is about to die", "are you free tomorrow", "i am on the road", "i will call you after work",
    "what is the name of the restaurant", "i just finished", "talk to you later", "take care of yourself",
    "i can not find my phone",
])

func words(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

func run(_ L: Lang, tag: String) {
    let s = KBSuggest()
    s.setLayout(L.layout)
    let cen = centers(L.rows, insets: L.insets)
    let alphabet = Set(L.rows.joined())
    var vocab: [String] = []
    for sen in L.sentences { for w in words(sen) where !vocab.contains(w) { vocab.append(w) } }
    if let url = Bundle.main.url(forResource: "words-" + L.code, withExtension: "txt"), let t = try? String(contentsOf: url, encoding: .utf8) {
        let list = t.split(separator: "\n").map(String.init)
        var i = 60
        while i < min(list.count, 6000) { let w = list[i]; if w.count >= 3, fold(w).allSatisfy({ alphabet.contains($0) }) { vocab.append(w) }; i += 23 }
    }
    let testWords = vocab.filter { $0.count >= 2 && fold($0).allSatisfy { alphabet.contains($0) } }
    var rng = RNG(s: 12345)

    // 1. Frappe imprécise : le doigt tombe à côté du centre ; ce que le clavier lit, puis ce qu'il corrige.
    var noisy = 0, fixed = 0, clean = 0, broken = 0
    var cMiss: [String] = []
    for _ in 0..<3 {
        for w in testWords {
            let target = Array(fold(w))
            var pts: [CGPoint] = [], typed = ""
            for ch in target {
                guard let c = cen[ch]?.first else { continue }
                let p = CGPoint(x: c.x + CGFloat(rng.gauss() * 0.30) * keyW, y: c.y + CGFloat(rng.gauss() * 0.24) * keyH)
                pts.append(p); typed.append(nearestKey(p, cen))
            }
            let tm = KBTouchModel(points: pts, centers: cen, keyW: keyW, keyH: keyH)
            let out = s.correction(for: typed, before: "", touch: tm) ?? typed
            if typed == fold(w) || typed == w {
                clean += 1
                if fold(out) != fold(w) { broken += 1 }
            } else {
                noisy += 1
                if fold(out) == fold(w) { fixed += 1 } else if cMiss.count < 14 { cMiss.append("\(w):\(typed)→\(out)") }
            }
        }
    }
    // 2. Fautes de frappe classiques (sans position des doigts) : inversion, lettre en trop, lettre oubliée.
    var tN = 0, tOK = 0
    for w in testWords where w.count >= 4 {
        var c = Array(fold(w))
        let k = Int(rng.next() * Double(c.count - 1))
        switch Int(rng.next() * 3) {
        case 0: c.swapAt(k, k + 1)
        case 1: c.remove(at: k + 1)
        default: c.insert(c[k], at: k)
        }
        let typo = String(c)
        guard typo != fold(w) else { continue }
        tN += 1
        if let o = s.correction(for: typo, before: "", touch: nil), fold(o) == fold(w) { tOK += 1 }
    }
    // 3. Glisser : le tracé passe par les touches avec un peu d'imprécision.
    var gN = 0, g1 = 0, g3 = 0
    var misses: [String] = []
    for w in testWords where w.count >= 2 {
        var pts: [CGPoint] = []
        var prev: CGPoint?
        let off = CGPoint(x: CGFloat(rng.gauss() * 0.15) * keyW, y: CGFloat(rng.gauss() * 0.12) * keyH)
        for ch in fold(w) {
            guard let c0 = cen[ch]?.first else { continue }
            let c = CGPoint(x: c0.x + off.x + CGFloat(rng.gauss() * 0.18) * keyW, y: c0.y + off.y + CGFloat(rng.gauss() * 0.15) * keyH + 4)
            if let p = prev {
                for t in 1...8 { let f = CGFloat(t) / 8; pts.append(CGPoint(x: p.x + (c.x - p.x) * f, y: p.y + (c.y - p.y) * f)) }
            } else { pts.append(c) }
            prev = c
        }
        guard pts.count >= 2 else { continue }
        gN += 1
        let tm = KBTouchModel(points: [], centers: cen, keyW: keyW, keyH: keyH)
        let out = s.glide(pts, touch: tm, before: "", limit: 4).map(fold)
        if out.first == fold(w) { g1 += 1 } else if misses.count < 12 { misses.append("\(w)→\(out.first ?? "-")") }
        if out.prefix(3).contains(fold(w)) { g3 += 1 }
    }
    // 3b. Glisser des mots rares mais valides (absents du modèle de langue) : ce qu'un filtre anti-coquilles risque de casser.
    var rN = 0, r1 = 0
    if let url = Bundle.main.url(forResource: "words-" + L.code, withExtension: "txt"), let t = try? String(contentsOf: url, encoding: .utf8) {
        let list = t.split(separator: "\n").map(String.init)
        let checker = UITextChecker()
        let lang = L.code == "fr" ? "fr_FR" : "en_US"
        var i = 3000
        while i < min(list.count, 15000) && rN < 120 {
            let w = list[i]; i += 37
            guard w.count >= 4, fold(w).allSatisfy({ alphabet.contains($0) }), rareCheck(w, L.code) else { continue }
            let ns = w as NSString
            guard checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: ns.length), startingAt: 0, wrap: false, language: lang).location == NSNotFound else { continue }
            var pts: [CGPoint] = []
            var prev: CGPoint?
            for ch in fold(w) {
                guard let c0 = cen[ch]?.first else { continue }
                let c = CGPoint(x: c0.x + CGFloat(rng.gauss() * 0.18) * keyW, y: c0.y + CGFloat(rng.gauss() * 0.15) * keyH + 4)
                if let p = prev { for t in 1...8 { let f = CGFloat(t) / 8; pts.append(CGPoint(x: p.x + (c.x - p.x) * f, y: p.y + (c.y - p.y) * f)) } } else { pts.append(c) }
                prev = c
            }
            rN += 1
            let tm = KBTouchModel(points: [], centers: cen, keyW: keyW, keyH: keyH)
            if s.glide(pts, touch: tm, before: "", limit: 4).map(fold).first == fold(w) { r1 += 1 }
        }
    }
    // 4. Prédiction du mot suivant, et complétion après deux lettres.
    var pN = 0, p3 = 0, cN = 0, c3 = 0, saved = 0, total = 0
    var pMiss: [String] = []
    for sen in L.sentences {
        let ws = words(sen)
        var before = ""
        for (i, w) in ws.enumerated() {
            total += w.count + 1
            if i > 0 {
                pN += 1
                let pr = s.predictions(before: before).map { $0.lowercased() }
                if pr.prefix(3).contains(w.lowercased()) { p3 += 1; saved += w.count } else if pMiss.count < 10 { pMiss.append("…\(ws[i-1]) [\(w)] → \(pr.prefix(3).joined(separator: "/"))") }
                else if w.count >= 3 {
                    cN += 1
                    let typed = String(w.prefix(2))
                    let sug = s.suggestions(for: typed, before: before + typed, touch: nil).items.map { $0.lowercased() }
                    if sug.prefix(3).contains(w.lowercased()) { c3 += 1; saved += w.count - 2 }
                }
            }
            before += w + " "
        }
    }
    func pc(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.1f %%", 100 * Double(a) / Double(b)) }
    print("== \(tag) \(L.code)")
    print("RESULT \(tag) \(L.code) frappe_corrigee \(pc(fixed, noisy)) (sur \(noisy))")
    print("RESULT \(tag) \(L.code) frappe_cassee \(pc(broken, clean)) (sur \(clean))")
    print("RESULT \(tag) \(L.code) fautes_corrigees \(pc(tOK, tN)) (sur \(tN))")
    print("RESULT \(tag) \(L.code) glisser_top1 \(pc(g1, gN)) (sur \(gN))")
    print("RESULT \(tag) \(L.code) glisser_top3 \(pc(g3, gN))")
    print("RESULT \(tag) \(L.code) glisser_rares_valides \(pc(r1, rN)) (sur \(rN))")
    print("RESULT \(tag) \(L.code) prediction_top3 \(pc(p3, pN)) (sur \(pN))")
    print("RESULT \(tag) \(L.code) completion_2lettres_top3 \(pc(c3, cN)) (sur \(cN))")
    print("RESULT \(tag) \(L.code) frappes_economisees \(pc(saved, total))")
    if tag == "base" || tag == "best" {
        print("glisser ratés:", misses.joined(separator: ", "))
        print("correction ratés:", cMiss.joined(separator: ", "))
        print("prédiction ratés:", pMiss.joined(separator: ", "))
    }
}

/// Le mot est-il absent du modèle de langue ? (les mots que le filtre anti-coquilles vise)
var lmVocab: [String: Set<String>] = [:]
func rareCheck(_ w: String, _ code: String) -> Bool {
    if lmVocab[code] == nil {
        var v = Set<String>()
        if let url = Bundle.main.url(forResource: "lm-" + code, withExtension: "bin"), let d = try? Data(contentsOf: url) {
            let n = Int(d[8]) | Int(d[9]) << 8 | Int(d[10]) << 16 | Int(d[11]) << 24
            var p = 24
            for _ in 0..<n { let l = Int(d[p]); v.insert(String(decoding: d[(p + 1)..<(p + 1 + l)], as: UTF8.self)); p += 1 + l }
        }
        lmVocab[code] = v
    }
    return !(lmVocab[code]!.contains(w))
}

let t0 = Date()
// Les réglages à comparer : chaque ligne « nom k=v,k=v » (vide = valeurs par défaut du clavier).
let configs: [(String, [String: Double])] = [
    ("best", [:]),
    ("old", ["doubtRank": 99_999, "gJunk": 0, "gJunkValid": 0, "gLoc": 7, "gShape": 6, "gPrior": 0.6, "tScan": 0]),
]
for (tag, cfg) in configs {
    KBSuggest.tune = cfg
    run(fr, tag: tag)
    run(en, tag: tag)
}
print(String(format: "durée %.1f s", Date().timeIntervalSince(t0)))
