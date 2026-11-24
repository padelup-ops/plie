// Script.swift — Allô Père Noël
//
// Les textes du Père Noël sont des données (Resources/Scripts/<langue>.json), pas du code : chaque phrase existe
// pour un enfant et pour plusieurs (« tu » / « vous »), et peut dépendre de ce que le parent a rempli (qualités,
// anecdote, cadeau). On assemble ici l'appel phrase par phrase, avec les pauses pour que l'enfant réponde.
// Les tournures évitent le masculin et le féminin (« tu as un grand cœur ») : on ne demande jamais le genre.

import Foundation

struct ScriptStep: Decodable {
    var say: [String]?
    var listen: Double?
    var laugh: Bool?
    var wave: Bool?
    var spark: Double?
    var `if`: String?
    var include: String?
}

struct ScriptBook: Decodable {
    var voices: [String]
    var rate: Float
    var pitch: Float
    var and: String
    var qualities: [String: [String]]
    var qualityJoin: [String]
    var scenarios: [String: [ScriptStep]]
    var blocks: [String: [ScriptStep]]

    /// Le livre dans la langue de l'app (anglais si la langue n'est pas prise en charge).
    static func load() -> (ScriptBook, String) {
        let lang = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
        for l in [lang, "en"] {
            if let url = Bundle.main.url(forResource: l, withExtension: "json"),
               let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(ScriptBook.self, from: d) {
                return (b, l)
            }
        }
        fatalError("Scripts manquants")
    }
}

enum Segment: Equatable {
    case say(String, laugh: Bool, wave: Bool)
    case listen(Double)
    case spark(Double)

    var text: String? { if case let .say(t, _, _) = self { return t }; return nil }
}

/// Assemble l'appel : les phrases du scénario, avec les noms, qualités, anecdote et cadeau à leur place.
struct ScriptBuilder {
    var book: ScriptBook
    var lang: String
    var profile: ChildProfile
    var premium: Bool

    func build(_ scenario: Scenario) -> [Segment] {
        var out: [Segment] = []
        append(book.scenarios[scenario.rawValue] ?? [], to: &out, depth: 0)
        return out
    }

    func block(_ name: String) -> [Segment] {
        var out: [Segment] = []
        append(book.blocks[name] ?? [], to: &out, depth: 0)
        return out
    }

    private func append(_ steps: [ScriptStep], to out: inout [Segment], depth: Int) {
        for s in steps {
            if let inc = s.include, depth < 3 {
                append(book.blocks[inc] ?? [], to: &out, depth: depth + 1)
                continue
            }
            guard holds(s.if) else { continue }
            if let say = s.say, !say.isEmpty {
                let line = (profile.isPlural && say.count > 1) ? say[1] : say[0]
                out.append(.say(fill(line), laugh: s.laugh ?? false, wave: s.wave ?? false))
            }
            if let l = s.listen { out.append(.listen(l)) }
            if let sp = s.spark { out.append(.spark(sp)) }
        }
    }

    private var anecdote: String { premium ? Grammar.anecdote(profile.anecdote, names: profile.cleanNames, lang: lang, plural: profile.isPlural) : "" }
    private var gift: String { premium ? Grammar.clean(profile.gift) : "" }

    private func holds(_ cond: String?) -> Bool {
        switch cond {
        case nil: return true
        case "quality": return !profile.qualities.isEmpty
        case "noQuality": return profile.qualities.isEmpty
        case "anecdote": return !anecdote.isEmpty
        case "noAnecdote": return anecdote.isEmpty
        case "gift": return !gift.isEmpty
        case "single": return !profile.isPlural
        case "plural": return profile.isPlural
        default: return true
        }
    }

    private func fill(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: "{name}", with: Grammar.join(profile.cleanNames, and: book.and))
        s = s.replacingOccurrences(of: "{age}", with: "\(profile.age)")
        s = s.replacingOccurrences(of: "{quality}", with: qualityPhrase)
        s = s.replacingOccurrences(of: "{anecdote}", with: anecdote)
        s = s.replacingOccurrences(of: "{gift_de}", with: Grammar.frenchDe(gift))
        s = s.replacingOccurrences(of: "{gift}", with: gift)
        return s
    }

    /// Jusqu'à deux qualités, dans une tournure qui n'accorde ni au masculin ni au féminin.
    private var qualityPhrase: String {
        let picked = Quality.allCases.filter { profile.qualities.contains($0) }.prefix(2)
        let forms = picked.compactMap { book.qualities[$0.rawValue] }
        let parts = forms.map { (profile.isPlural && $0.count > 1) ? $0[1] : $0[0] }
        let join = (profile.isPlural && book.qualityJoin.count > 1) ? book.qualityJoin[1] : book.qualityJoin[0]
        return parts.joined(separator: join)
    }
}

enum Grammar {
    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!?…;,".contains(last) { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func join(_ names: [String], and: String) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + and + names.last!
    }

    /// L'anecdote telle que le Père Noël la dit à l'enfant. Le parent peut l'écrire à la 3e personne (« Il a appris
    /// à nager ») : en français et en anglais, on la remet à la 2e personne (« tu as appris à nager »).
    static func anecdote(_ raw: String, names: [String], lang: String, plural: Bool) -> String {
        var t = clean(raw)
        guard !t.isEmpty else { return "" }
        let lower = t.lowercased()
        let subjects: [String]
        switch lang {
        case "fr": subjects = ["il", "elle", "ils", "elles"] + names.map { $0.lowercased() }
        case "en": subjects = ["he", "she", "they"] + names.map { $0.lowercased() }
        default: subjects = []
        }
        var converted = false
        if lang == "fr" {
            let rules: [(String, String)] = plural
                ? [("ont", "vous avez"), ("sont", "vous êtes"), ("se sont", "vous vous êtes"), ("a", "vous avez"), ("est", "vous êtes")]
                : [("a", "tu as"), ("est", "tu es"), ("s'est", "tu t'es"), ("s’est", "tu t'es"), ("sait", "tu sais"), ("fait", "tu fais"), ("aime", "tu aimes"), ("adore", "tu adores")]
            outer: for subj in subjects.sorted(by: { $0.count > $1.count }) {
                for (verb, repl) in rules {
                    let prefix = subj + " " + verb + " "
                    if lower.hasPrefix(prefix) {
                        t = repl + " " + String(t.dropFirst(prefix.count))
                        converted = true
                        break outer
                    }
                }
            }
            if converted {
                let poss: [(String, String)] = plural ? [(" son ", " votre "), (" sa ", " votre "), (" ses ", " vos "), (" leur ", " votre "), (" leurs ", " vos ")]
                                                      : [(" son ", " ton "), (" sa ", " ta "), (" ses ", " tes ")]
                for (a, b) in poss { t = (" " + t + " ").replacingOccurrences(of: a, with: b).trimmingCharacters(in: .whitespaces) }
            }
        } else if lang == "en" {
            let rules: [(String, String)] = [("has", "you have"), ("have", "you have"), ("is", "you are"), ("are", "you are"), ("was", "you were"), ("were", "you were")]
            outer: for subj in subjects.sorted(by: { $0.count > $1.count }) {
                for (verb, repl) in rules {
                    let prefix = subj + " " + verb + " "
                    if lower.hasPrefix(prefix) { t = repl + " " + String(t.dropFirst(prefix.count)); converted = true; break outer }
                }
                if lower.hasPrefix(subj + " ") {
                    t = "you " + String(t.dropFirst(subj.count + 1)); converted = true; break
                }
            }
            if converted {
                for (a, b) in [(" his ", " your "), (" her ", " your "), (" their ", " your "), (" himself", " yourself"), (" herself", " yourself")] {
                    t = (" " + t + " ").replacingOccurrences(of: a, with: b).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // minuscule au début (sauf en allemand, où les noms prennent une majuscule)
        if lang != "de", let f = t.first, !names.contains(where: { t.hasPrefix($0) }) {
            t = f.lowercased() + t.dropFirst()
        }
        return t
    }

    /// « de » + le cadeau, avec l'élision et les contractions du français (d'un vélo, du château, des Lego).
    static func frenchDe(_ gift: String) -> String {
        let g = gift
        guard !g.isEmpty else { return "" }
        let lower = g.lowercased()
        if lower.hasPrefix("le ") { return "du " + g.dropFirst(3) }
        if lower.hasPrefix("les ") { return "des " + g.dropFirst(4) }
        if lower.hasPrefix("des ") { return "de " + g.dropFirst(4) }
        if let f = lower.first, "aeéèêiouyh".contains(f) { return "d'" + g }
        return "de " + g
    }
}
