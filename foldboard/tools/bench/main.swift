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
    var corrTime = 0.0, corrSum = 0.0, corrN = 0, glideTime = 0.0, glideSum = 0.0
    var slow: [(Double, String)] = []
    var noisy = 0, fixed = 0, clean = 0, broken = 0
    // Comme à l'espace dans le clavier (mode rapide, sans le correcteur d'iOS).
    var fixedF = 0, brokenF = 0
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
            let tc = Date()
            let out = s.correction(for: typed, before: "", touch: tm) ?? typed
            let dt = Date().timeIntervalSince(tc)
            let outF = s.correction(for: typed, before: "", touch: tm, fast: true) ?? typed
            if typed == fold(w) || typed == w { if fold(outF) != fold(w) { brokenF += 1 } } else if fold(outF) == fold(w) { fixedF += 1 }
            if corrN > 5 { corrTime = max(corrTime, dt); slow.append((dt, "corr \(typed)")) }
            corrSum += dt; corrN += 1
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
    var tN = 0, tOK = 0, tOKF = 0
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
        if let o = s.correction(for: typo, before: "", touch: nil, fast: true), fold(o) == fold(w) { tOKF += 1 }
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
        let tg = Date()
        let out = s.glide(pts, touch: tm, before: "", limit: 4).map(fold)
        let dg = Date().timeIntervalSince(tg)
        if gN > 5 { glideTime = max(glideTime, dg); slow.append((dg, "glide \(w)")) }
        glideSum += dg
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
    print("RESULT \(tag) \(L.code) rapide_frappe_corrigee \(pc(fixedF, noisy))")
    print("RESULT \(tag) \(L.code) rapide_frappe_cassee \(pc(brokenF, clean))")
    print("RESULT \(tag) \(L.code) rapide_fautes_corrigees \(pc(tOKF, tN))")
    print("RESULT \(tag) \(L.code) glisser_top1 \(pc(g1, gN)) (sur \(gN))")
    print("RESULT \(tag) \(L.code) glisser_top3 \(pc(g3, gN))")
    print("RESULT \(tag) \(L.code) glisser_rares_valides \(pc(r1, rN)) (sur \(rN))")
    print("plus lents:", slow.sorted { $0.0 > $1.0 }.prefix(8).map { String(format: "%@ %.0fms", $0.1, $0.0 * 1000) }.joined(separator: ", "))
    print("RESULT \(tag) \(L.code) correction_ms_moy \(String(format: "%.2f", 1000 * corrSum / Double(max(1, corrN))))")
    print("RESULT \(tag) \(L.code) correction_ms_max \(String(format: "%.1f", 1000 * corrTime))")
    print("RESULT \(tag) \(L.code) glisser_ms_moy \(String(format: "%.2f", 1000 * glideSum / Double(max(1, gN))))")
    print("RESULT \(tag) \(L.code) glisser_ms_max \(String(format: "%.1f", 1000 * glideTime))")
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

/// Cas réels remontés par les testeurs : (texte avant, mot tapé, attendu).
let realFR: [(String, String, String)] = [
    ("je vais ", "a", "à"), ("il ", "a", "a"), ("elle ", "a", "a"), ("on ", "a", "a"), ("il y ", "a", "a"),
    ("je suis ", "a", "à"), ("c’est ", "a", "à"), ("rendez-vous ", "a", "à"), ("", "a", "à"), ("je pense ", "a", "à"),
    ("j’ai mal ", "a", "à"), ("tu ", "a", "a"), ("qui ", "a", "a"), ("on se voit ", "a", "à"), ("je t’attends ", "a", "à"),
    ("il fait beau ", "a", "à"), ("ma mère ", "a", "a"), ("le train ", "a", "a"),
    ("je ne sais pas ", "fu", "du"), ("le prix ", "fu", "du"), ("il faut ", "sue", "que"), ("je pense ", "sue", "que"),
    ("je suis ", "auncourant", "au courant"), ("on va ", "alamaison", "à la maison"), ("c’est ", "unebonne", "une bonne"),
    ("je ", "suisnla", "suis la"), ("", "bonjourtoi", "bonjour toi"),
    ("le ", "courznt", "courant"), ("", "reocnnues", "reconnues"), ("", "plur", "pour"), ("", "fe", "de"),
    ("je ", "sue", "sue"), ("", "sue", "sue"),
    // Charlotte, 15 nov. (AZERTY : le z à côté du a, l’apostrophe à côté du n)
    ("je ", "nnzi", "n’ai"), ("je vais à ", "lz", "la"), ("", "lenremplaczment", "le remplacement"),
    ("il n’y a ", "qua", "qu’à"), ("les ", "lettees", "lettres"), ("c’est ", "genizk", "génial"),
    ("il faut ", "chzngrr", "changer"), ("", "cedt", "c’est"), ("la ", "longjejr", "longueur"),
    ("il ", "fzit", "fait"), ("la ", "lzrgeur", "largeur"), ("aller ", "a", "à"), ("je voudrais aller ", "a", "à"),
    ("", "Cedt", "C’est"), ("", "Fzit", "Fait"), ("c’est ", "niugeai", "nouveau"), ("il ", "ma’que", "manque"),
    ("je ", "jzi", "j’ai"),
    // Charlotte, 16 nov.
    ("", "Cz", "Ça"), ("", "Alorsnedtce", "Alors est-ce"), ("est-ce que ça marche ", "moeiw", "mieux"),
    ("je commence à trouver ça ", "vrizment", "vraiment"), ("vraiment ", "pzs", "pas"), ("", "Jainete", "J’ai été"),
    ("", "Jaiete", "J’ai été"), ("", "Crtzit", "C’était"), ("il y ", "z", "a"), ("quarante ans ", "mzitnenant", "maintenant"),
    ("", "Edtce", "Est-ce"), ("la ", "largzurnest", "largeur est"), ("", "qiakd", "quand"), ("censé ", "sactiver", "s’activer"),
    ("", "Ke", "Je"), ("en ", "oortrzit", "portrait"), ("le ", "resrz", "reste"), ("j’ai ", "ej", "eu"),
    ("une fois ", "suffirzk", "suffirait"), ("", "Voilz", "Voilà"), ("merci ", "ooir", "pour"), ("", "Pzs", "Pas"),
    ("je pense ", "z", "à"),
    // Charlotte, 22 nov.
    ("ce n’est ", "oas", "pas"), ("je l’ai posé ", "sir", "sur"), ("il reste de l’", "esoace", "espace"),
    ("pas assez d’", "esozxe", "espace"), ("la ", "derniere", "dernière"), ("", "iphone", "iPhone"), ("mon ", "ipad", "iPad"),
]
let realEN: [(String, String, String)] = [
    ("i ", "sue", "sue"), ("", "teh", "the"), ("i am ", "inthe", "in the"), ("see you ", "tomorrownat", "tomorrow at"),
    ("", "ot", "to"), ("thank ", "tou", "you"),
]

func realCases(_ L: Lang, _ cases: [(String, String, String)], tag: String, name base: String = "cas_reels") {
    let s = KBSuggest()
    s.setLayout(L.layout)
    let ctr = centers(L.rows, insets: L.insets)
    // Deux façons : sans les touchers (nil), et avec chaque doigt posé au centre de la touche tapée (le pire cas :
    // le doigt a bien visé la mauvaise touche).
    for touched in [false, true] {
        var ok = 0
        var bad: [String] = []
        for (before, w, exp) in cases {
            var touch: KBTouchModel?
            if touched, w.allSatisfy({ $0.isLetter }) {
                let pts = w.lowercased().compactMap { ctr[Character(String($0).folding(options: .diacriticInsensitive, locale: nil))]?.first }
                if pts.count == w.count { touch = KBTouchModel(points: pts, centers: ctr, keyW: keyW, keyH: keyH) }
            }
            // Comme le clavier : l'apostrophe à la place du n d'abord (« ma’que »), puis la correction du mot.
            let out = s.apostropheTypo(w) ?? s.correction(for: w, before: before + w, touch: touch, fast: true) ?? w
            if out == exp { ok += 1 } else { bad.append("«\(before)\(w)»→\(out) (voulu \(exp))") }
        }
        let name = touched ? base + "_touche" : base
        print("RESULT \(tag) \(L.code) \(name) \(String(format: "%.1f", 100 * Double(ok) / Double(cases.count))) (sur \(cases.count))")
        if !bad.isEmpty { print("cas ratés \(tag) \(L.code)\(touched ? " (touchers)" : ""):", bad.joined(separator: " · ")) }
    }
}

/// Fautes générées automatiquement, comme en tapant vite au pouce (des milliers de cas, pas seulement ceux des
/// testeurs) : une ou deux touches voisines (voisines à l'écran, rangée du bas décalée), deux lettres inversées
/// plus une touche voisine, deux mots collés (sans espace ou avec la lettre juste au-dessus de la barre d'espace),
/// l'apostrophe oubliée. On mesure la part corrigée exactement, et la part de mots justes abîmés.
func autoTypos(_ L: Lang, tag: String) {
    let s = KBSuggest()
    s.setLayout(L.layout)
    let cen = centers(L.rows, insets: L.insets)
    let alphabet = Set(L.rows.joined())
    var near: [Character: [Character]] = [:]
    for (k, ps) in cen {
        for (k2, ps2) in cen where k2 != k {
            if let p = ps.first, let q = ps2.first, abs(p.y - q.y) <= keyH * 1.01, abs(p.x - q.x) <= keyW * 1.01 { near[k, default: []].append(k2) }
        }
        near[k]?.sort()
    }
    guard let url = Bundle.main.url(forResource: "words-" + L.code, withExtension: "txt"), let t = try? String(contentsOf: url, encoding: .utf8) else { return }
    let list = t.split(separator: "\n").map(String.init)
    var pool: [String] = []
    var i = 40
    while i < min(list.count, 9000) { let w = list[i]; if w.count >= 5, fold(w).allSatisfy({ alphabet.contains($0) }) { pool.append(w) }; i += 11 }
    var rng = RNG(s: 777)
    func sub(_ c: inout [Character], _ k: Int) -> Bool {
        guard let ns = near[c[k]], !ns.isEmpty else { return false }
        c[k] = ns[Int(rng.next() * Double(ns.count)) % ns.count]; return true
    }
    func check(_ typo: String, _ want: String, before: String = "") -> Bool {
        let out = s.apostropheTypo(typo) ?? s.correction(for: typo, before: before + typo, touch: nil, fast: true) ?? typo
        return fold(out) == fold(want)
    }
    var n1 = 0, ok1 = 0, n2 = 0, ok2 = 0, nS = 0, okS = 0, nC = 0, okC = 0, nK = 0, broken = 0
    var miss1: [String] = [], miss2: [String] = [], missC: [String] = []
    for w in pool {
        let base = Array(fold(w))
        // Une touche voisine.
        var c = base; let k = Int(rng.next() * Double(c.count)) % c.count
        if sub(&c, k), String(c) != String(base) {
            n1 += 1; if check(String(c), w) { ok1 += 1 } else if miss1.count < 12 { miss1.append("\(String(c))→\(w)") }
        }
        // Deux touches voisines (mot de 7 lettres ou plus).
        if base.count >= 7 {
            var c2 = base
            let a = Int(rng.next() * Double(c2.count)) % c2.count
            var b2 = Int(rng.next() * Double(c2.count)) % c2.count
            if b2 == a { b2 = (a + 3) % c2.count }
            if sub(&c2, a), sub(&c2, b2), String(c2) != String(base) {
                n2 += 1; if check(String(c2), w) { ok2 += 1 } else if miss2.count < 12 { miss2.append("\(String(c2))→\(w)") }
            }
        }
        // Deux lettres inversées et une touche voisine (6 lettres ou plus).
        if base.count >= 6 {
            var c3 = base
            let a = 1 + Int(rng.next() * Double(c3.count - 2)) % (c3.count - 2)
            if c3[a] != c3[a + 1] {
                c3.swapAt(a, a + 1)
                var b3 = (a + 3) % c3.count
                if b3 == a || b3 == a + 1 || b3 == 0 { b3 = (a + 4) % c3.count }
                if b3 != a, b3 != a + 1, b3 != 0, sub(&c3, b3), String(c3) != String(base) {
                    nS += 1; if check(String(c3), w) { okS += 1 }
                }
            }
        }
        // Le mot juste ne doit pas changer.
        nK += 1
        if let o = s.correction(for: w, before: w, touch: nil, fast: true), fold(o) != fold(w) { broken += 1 }
    }
    // Deux mots collés, tirés des phrases : sans espace, ou avec c/v/b/n à la place de l'espace.
    for sen in L.sentences {
        let ws = words(sen)
        guard ws.count >= 2 else { continue }
        for j in 0..<(ws.count - 1) where ws[j].count >= 2 && ws[j + 1].count >= 3 && !ws[j].contains("’") && !ws[j + 1].contains("’") && !ws[j].contains("-") && !ws[j + 1].contains("-") {
            let glue: [String] = ["", "n", "b"]
            let g = glue[Int(rng.next() * 3) % 3]
            let typo = fold(ws[j]) + g + fold(ws[j + 1])
            let want = ws[j] + " " + ws[j + 1]
            let before = ws[..<j].joined(separator: " ") + (j > 0 ? " " : "")
            nC += 1
            if check(typo, want, before: before) { okC += 1 } else if missC.count < 12 { missC.append("\(typo)→\(want)") }
        }
    }
    func pc(_ a: Int, _ b: Int) -> String { String(format: "%.1f", 100 * Double(a) / Double(max(1, b))) }
    print("RESULT \(tag) \(L.code) auto_1touche \(pc(ok1, n1)) (sur \(n1))")
    print("RESULT \(tag) \(L.code) auto_2touches \(pc(ok2, n2)) (sur \(n2))")
    print("RESULT \(tag) \(L.code) auto_inversion_touche \(pc(okS, nS)) (sur \(nS))")
    print("RESULT \(tag) \(L.code) auto_mots_colles \(pc(okC, nC)) (sur \(nC))")
    print("RESULT \(tag) \(L.code) auto_mots_justes_abimes \(pc(broken, nK)) (sur \(nK))")
    if tag == "best" {
        print("auto ratés 1 touche \(L.code):", miss1.joined(separator: ", "))
        print("auto ratés 2 touches \(L.code):", miss2.joined(separator: ", "))
        print("auto ratés collés \(L.code):", missC.joined(separator: ", "))
    }
}

/// Vrais swipes (jeu de données FUTO swipe.futo.org, licence MIT) : des tracés de vraies personnes sur téléphone,
/// en anglais (QWERTY) et en français (AZERTY). Coordonnées entre 0 et 1 sur le clavier ; touches dans `layout`.
/// On mesure le mot proposé en premier (top 1) et dans les 4 propositions (top 4), sur tous les mots et sur ceux
/// de notre liste (les autres ne peuvent pas sortir : noms propres, mots rares de Wikipédia).
func realSwipes(_ L: Lang, file: String, layout: String, tag: String, limit: Int = 2000) {
    guard let fu = Bundle.main.url(forResource: file, withExtension: "jsonl"), let text = try? String(contentsOf: fu, encoding: .utf8),
          let lu = Bundle.main.url(forResource: layout, withExtension: "json"), let ld = try? Data(contentsOf: lu),
          let lj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any], let keys = lj["keys"] as? [[String: Any]] else {
        print("RESULT \(tag) \(L.code) vrais_swipes absent (\(file))"); return
    }
    let s = KBSuggest()
    s.setLayout(L.layout)
    var vocab = Set<String>()
    if let url = Bundle.main.url(forResource: "words-" + L.code, withExtension: "txt"), let t = try? String(contentsOf: url, encoding: .utf8) {
        for w in t.split(separator: "\n") { vocab.insert(fold(String(w))) }
    }
    NeuralSwipe.calls = 0
    NeuralSwipe.skips = 0
    NeuralSwipe.inferMS = 0
    NeuralSwipe.inferMaxMS = 0
    var n = 0, t1 = 0, t4 = 0, inN = 0, in1 = 0, in4 = 0, ms = 0.0, msMax = 0.0
    var miss: [String] = []
    for line in text.split(separator: "\n") {
        guard n < limit, let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let w = d["w"] as? String, let p = d["p"] as? [[Double]], p.count >= 2,
              let cw = (d["cw"] as? Double) ?? (d["cw"] as? Int).map(Double.init),
              let ch = (d["ch"] as? Double) ?? (d["ch"] as? Int).map(Double.init) else { continue }
        let target = fold(w.trimmingCharacters(in: .punctuationCharacters))
        guard target.count >= 2, target.allSatisfy({ $0.isLetter }) else { continue }
        var cen: [Character: [CGPoint]] = [:]
        var kw = 0.0, kh = 0.0
        for k in keys {
            guard let l = (k["letter"] as? String)?.first, let cx = k["cx"] as? Double, let cy = k["cy"] as? Double else { continue }
            cen[Character(fold(String(l))), default: []].append(CGPoint(x: cx * cw, y: cy * ch))
            if let rx = k["rx"] as? Double, let ry = k["ry"] as? Double { kw = 2 * rx * cw; kh = 2 * ry * ch }
        }
        guard kw > 0, kh > 0 else { continue }
        let pts = p.map { CGPoint(x: $0[0] * cw, y: $0[1] * ch) }
        var tm = KBTouchModel(points: [], centers: cen, keyW: CGFloat(kw), keyH: CGFloat(kh))
        tm.canvas = CGSize(width: cw, height: ch)
        let before = (d["b"] as? String) ?? ""
        let times = p.map { $0.count > 2 ? $0[2] : 0 }
        let tg = Date()
        let out = s.glide(pts, touch: tm, before: before, limit: 4, times: times).map(fold)
        let dt = Date().timeIntervalSince(tg)
        n += 1; ms += dt; if n > 5 { msMax = max(msMax, dt) }
        let inside = vocab.contains(target)
        if inside { inN += 1 }
        if out.first == target { t1 += 1; if inside { in1 += 1 } } else if inside && miss.count < 25 { miss.append("\(target)→\(out.first ?? "-")") }
        if out.contains(target) { t4 += 1; if inside { in4 += 1 } }
    }
    func pc(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.1f %%", 100 * Double(a) / Double(b)) }
    print("RESULT \(tag) \(L.code) vrais_swipes_top1 \(pc(t1, n)) (sur \(n), \(file))")
    print("RESULT \(tag) \(L.code) vrais_swipes_top4 \(pc(t4, n))")
    print("RESULT \(tag) \(L.code) vrais_swipes_connus_top1 \(pc(in1, inN)) (sur \(inN) mots de la liste)")
    print("RESULT \(tag) \(L.code) vrais_swipes_connus_top4 \(pc(in4, inN))")
    print("RESULT \(tag) \(L.code) vrais_swipes_ms_moy \(String(format: "%.1f", 1000 * ms / Double(max(1, n)))) max \(String(format: "%.0f", 1000 * msMax))")
    print("RESULT \(tag) \(L.code) neural \(NeuralSwipe.statusLine)")
    if tag == "best" { print("vrais swipes ratés \(L.code):", miss.joined(separator: ", ")) }
}

let t0 = Date()
NeuralSwipe.benchIgnoresBudget = true
func mem(_ name: String) { print("RESULT mem \(name) \(String(format: "%.1f", NeuralSwipe.footprintMB())) Mo alive \(KeyboardCanvas.alive)") }
mem("demarrage")
let probe = KBSuggest()
probe.setLayout(.qwerty)
mem("liste_en")
probe.setLayout(.azerty)
mem("liste_fr")
mem("modele_langue")
// Les réglages à comparer : chaque ligne « nom k=v,k=v » (vide = valeurs par défaut du clavier).
/// Les vraies fautes (Wikipédia, codespell ; accents oubliés en français) : un échantillon fixe de N cas.
/// Comme le clavier à l'espace : la correction rapide, puis la proposition de la barre si elle n'a rien trouvé.
func corpus(_ L: Lang, tag: String, n: Int = 2500) {
    guard let url = Bundle.main.url(forResource: "typos-" + L.code, withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { print("pas de typos-\(L.code).txt"); return }
    var all = text.split(separator: "\n").compactMap { l -> (String, String)? in
        let p = l.components(separatedBy: "->"); return p.count == 2 ? (p[0], p[1]) : nil
    }
    var rng = RNG(s: 42)
    for i in stride(from: all.count - 1, to: 0, by: -1) { let j = Int(rng.next() * Double(i + 1)); all.swapAt(i, j) }
    let s = KBSuggest()
    s.setLayout(L.layout)
    var fast = 0, withBar = 0, wrong = 0
    var miss: [String] = [], bad: [String] = []
    let cases = all.prefix(n)
    for (w, want) in cases {
        let before = (L.code == "en" ? "the " : "le ") + w
        let f = s.correction(for: w, before: before, touch: nil, fast: true)
        var out = f ?? w
        if fold(out) == fold(want) { fast += 1; withBar += 1; continue }
        if f == nil {
            let items = s.suggestions(for: w, before: before).items
            if let b = s.barFix(w, items: Array(items.dropFirst()), before: before) { out = b }
            if fold(out) == fold(want) { withBar += 1; continue }
        }
        if out != w { wrong += 1; if bad.count < 25 { bad.append("\(w)→\(out) (voulu \(want))") } }
        else if miss.count < 40 { miss.append("\(w)→? (voulu \(want))") }
    }
    let c = Double(max(1, cases.count))
    print("RESULT \(tag) \(L.code) vraies_fautes_espace \(String(format: "%.1f", 100 * Double(fast) / c)) (sur \(cases.count))")
    print("RESULT \(tag) \(L.code) vraies_fautes_avec_barre \(String(format: "%.1f", 100 * Double(withBar) / c))")
    print("RESULT \(tag) \(L.code) vraies_fautes_mauvais_mot \(String(format: "%.1f", 100 * Double(wrong) / c))")
    print("non corrigées \(tag) \(L.code):", miss.joined(separator: " · "))
    print("mauvais mot \(tag) \(L.code):", bad.joined(separator: " · "))
}

let configs: [(String, [String: Double])] = [
    // L'ancienne d'abord : la première configuration paie le chargement des dictionnaires (temps faussés).
    // gNeural à 0 : le glisser géométrique seul, pour le comparer au reclassement FUTO Swipe.
    ("sans_nouveau", ["scan2": 0, "genElision": 0, "oneLetterFix": 0, "hyphenTypo": 0, "bilingual": 0, "gNeural": 0]),
    ("best", [:]),
]
/// De l'anglais tapé sur le clavier français (AZERTY) : corrigé en anglais, jamais « francisé ».
let mixedFR: [(String, String, String)] = [
    ("i think ", "the", "the"), ("can you send me ", "teh", "the"), ("see you ", "tomorow", "tomorrow"),
    ("thank you for ", "yout", "your"), ("i will call you ", "later", "later"), ("this is a ", "test", "test"),
    ("we are going to ", "the", "the"), ("let me know if ", "tou", "you"), ("i hope you are ", "doing", "doing"),
    ("it was a great ", "day", "day"), ("what do you ", "thinl", "think"), ("i am ", "a", "a"),
    ("", "i", "I"), ("i ", "dont", "don’t"), ("i ", "cant", "can’t"), ("my ", "iphone", "iPhone"),
    // Et le français reste français.
    ("je vais ", "a", "à"), ("il fait ", "tres", "très"), ("on se voit ", "apres", "après"),
]
let memoryOK = KeyboardCanvas.simulateFoldCycles()
let visibilityOK = KeyboardCanvas.verifyVisibility()
let sheetOK = KeyboardCanvas.verifyBarSheet()
let laptopOK = KeyboardCanvas.verifyLaptopLayout()
let touchOK = KeyboardCanvas.verifyTouchSafety()
let shedOK = KeyboardCanvas.verifyMemoryShed()
let hostOK = KeyboardCanvas.verifyHostHeight()
let hapticsOK = KeyboardCanvas.verifyHaptics()
// Retours des testeurs du 27 novembre : raccourci des dispositions à gauche, bouton de position seulement Duo ouvert,
// emojis du côté, flèche unique, conseils coupés, message devant le raccourci, ordre des positions.
let barOptionsOK = KeyboardCanvas.verifyBarOptions()
let toastsOK = KeyboardCanvas.verifyToasts()
let orderOK = KeyboardCanvas.verifyPositionOrder()
// Retours du testeur (27 novembre, suite) : le fichier de réglages se relit à l'identique et un fichier quelconque est
// refusé ; dans une version de test, un essai lancé ne se termine pas (sauf « fin d'essai simulée »), et dans la
// version de l'App Store il se termine comme avant.
let backupOK: Bool = {
    var s = KBSettings()
    s.mode = .right
    s.globeAsEmoji = true
    s.phrases = ["À tout de suite", "On my way"]
    s.myWords = ["Foldboard"]
    s.keyHeight = 51
    s.positionOrder = ["split", "full"]
    let back = KBSettingsFile.data(s).flatMap { KBSettingsFile.read($0) }
    let same = back == s
    let fields = back?.mode == .right && back?.globeAsEmoji == true && back?.phrases == s.phrases
        && back?.myWords == s.myWords && back?.keyHeight == 51 && back?.positionOrder == s.positionOrder
    let foreign = KBSettingsFile.read(Data("{}".utf8)) == nil
        && KBSettingsFile.read(Data(#"{"mode":"left","phrases":[]}"#.utf8)) == nil
        && KBSettingsFile.read(Data("bonjour".utf8)) == nil
    var old = KBAccess()
    old.trialStart = Date().addingTimeInterval(-10 * 86400)
    let store = !old.isPro() && old.trialOver()
    var tester = old
    tester.tester = true
    let kept = tester.isPro() && !tester.trialOver()
    var simulated = tester
    simulated.simulated = true
    let simulatedOver = !simulated.isPro() && simulated.trialOver()
    var never = KBAccess()
    never.tester = true
    let locked = !never.isPro()
    let ok = same && fields && foreign && store && kept && simulatedOver && locked
    print("RESULT reglages_fichier identique=\(same) champs=\(fields) fichier_etranger_refuse=\(foreign) essai_app_store_fini=\(store) essai_version_test_garde=\(kept) fin_simulee=\(simulatedOver) sans_essai_bloque=\(locked) \(ok ? "yes" : "no")")
    return ok
}()
/// La dictée écrite là où est le curseur : (texte avant, entendu, langue, attendu).
let dictCases: [(String, String, String, String)] = [
    ("", "bonjour tout le monde", "fr", "Bonjour tout le monde"),
    ("Je pense que", "Il fait beau.", "fr", " il fait beau."),
    ("Je pense que ", "Il fait beau.", "fr", "il fait beau."),
    ("Salut. ", "comment ça va ?", "fr", "Comment ça va ?"),
    ("Hier j’ai vu ", "Marie au marché.", "fr", "Marie au marché."),
    ("Bonjour", "À la ligne comment vas-tu ?", "fr", "\nComment vas-tu ?"),
    ("", "Bonjour Paul. À la ligne. Merci pour hier, nouveau paragraphe à bientôt", "fr", "Bonjour Paul.\nMerci pour hier\n\nÀ bientôt"),
    ("On se voit ", "L’autre jour.", "fr", "l’autre jour."),
    ("I think ", "The weather is nice.", "en", "the weather is nice."),
    ("I think", "I will come.", "en", " I will come."),
    ("See you ", "NASA said so", "en", "NASA said so"),
    ("Hello.", "how are you? New line. Fine", "en", " How are you?\nFine"),
    ("Dear John", "New paragraph thank you", "en", "\n\nThank you"),
    ("Ich glaube ", "Der Hund schläft.", "de", "der Hund schläft."),
    ("Ich sehe ", "Hunde im Park.", "de", "Hunde im Park."),
    ("(", "Voilà", "fr", "voilà"),
    ("Merci", ", à demain", "fr", ", à demain"),
]
var dictOK = true
for (before, heard, lang, want) in dictCases {
    let got = KBDictationText.prepare(heard, before: before, lang: lang)
    if got != want { dictOK = false; print("dictée ratée: «\(before)» + «\(heard)» → «\(got)» (voulu «\(want)»)") }
}
print("RESULT dictee mise_en_forme \(dictOK ? "yes" : "no") (sur \(dictCases.count))")
/// Le sens de la traduction d'une dictée : de la langue parlée vers l'autre, même pour une phrase courte.
let dirCases: [(String, String, [String], String)] = [
    ("Salut ça va", "fr", ["fr", "en"], "fr>en"), ("Ciao", "fr", ["fr", "en"], "fr>en"), ("Ok", "en", ["fr", "en"], "en>fr"),
    ("Hello, how are you doing today my friend?", "fr", ["fr", "en"], "en>fr"),
    ("Bonjour, comment allez-vous aujourd’hui mon ami ?", "en", ["fr", "en"], "fr>en"),
    ("Guten Morgen zusammen, wie geht es euch heute?", "de", ["fr", "en"], "de>fr"),
]
for (text, spoken, pair, want) in dirCases {
    let d = KBTranslate.direction(for: text, spoken: spoken, pair: pair).map { $0.from + ">" + $0.to } ?? "-"
    if d != want { dictOK = false; print("sens raté: «\(text)» parlé \(spoken) → \(d) (voulu \(want))") }
}
print("RESULT dictee sens_traduction \(dictOK ? "yes" : "no") (sur \(dirCases.count))")
if !memoryOK || !visibilityOK || !sheetOK || !laptopOK || !touchOK || !shedOK || !hostOK || !hapticsOK || !dictOK
    || !barOptionsOK || !toastsOK || !orderOK || !backupOK {
    fputs("mémoire pas stable ou interrupteurs ignorés\n", stderr)
    exit(1)
}

for (tag, cfg) in configs {
    KBSuggest.tune = cfg
    realCases(fr, realFR, tag: tag)
    realCases(en, realEN, tag: tag)
    realCases(fr, mixedFR, tag: tag, name: "anglais_sur_azerty")
    corpus(fr, tag: tag)
    corpus(en, tag: tag)
    autoTypos(fr, tag: tag)
    autoTypos(en, tag: tag)
    run(fr, tag: tag)
    run(en, tag: tag)
    realSwipes(en, file: "test-en-qwerty", layout: "qwerty", tag: tag)
    realSwipes(fr, file: "s5-fr-azerty", layout: "azerty", tag: tag)
}
print(String(format: "durée %.1f s", Date().timeIntervalSince(t0)))
