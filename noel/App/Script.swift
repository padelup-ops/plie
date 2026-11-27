// Script.swift — Allô Père Noël
//
// Les textes du Père Noël sont des données (Resources/Scripts/<langue>.json), pas du code : chaque phrase existe
// pour un enfant et pour plusieurs (« tu » / « vous »), et peut dépendre de ce que le parent a rempli (qualités,
// anecdote, cadeau). On assemble ici l'appel phrase par phrase, avec les pauses pour que l'enfant réponde.
// Les tournures évitent le masculin et le féminin (« tu as un grand cœur ») : on ne demande jamais le genre.
//
// La voix du Père Noël est enregistrée : chaque phrase fixe a son fichier, et chaque prénom de la banque a son
// « Ho, ho, ho ! Bonjour <prénom> ! » et son « Joyeux Noël, <prénom> ! ». Ce que le parent écrit lui-même
// (l'anecdote, le cadeau) et les prénoms plus rares sont dits par le lutin du Père Noël : un autre personnage,
// une autre voix (la synthèse de l'iPhone, en voix de lutin).

import Foundation

struct ScriptStep: Decodable {
    var say: [String]?
    /// Dit par le lutin : ce que le parent a écrit.
    var elf: [String]?
    /// « Ho, ho, ho ! Bonjour <prénom> ! » : une réplique enregistrée par prénom.
    var hello: Bool?
    /// « Joyeux Noël, <prénom> ! »
    var bye: Bool?
    /// La fin de l'aperçu gratuit.
    var cut: Bool?
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
    var hello: String
    var helloAnyone: String
    var elfHello: String
    var helloAfterElf: [String]
    var bye: String
    var byeAnyone: String
    var elfBye: String
    var elfLabel: String
    var qualities: [String: [String]]
    var scenarios: [String: [ScriptStep]]
    var blocks: [String: [ScriptStep]]

    /// Le livre dans la langue de l'app (anglais si la langue n'est pas prise en charge).
    static func load() -> (ScriptBook, String) {
        if let cached { return cached }
        let lang = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
        for l in [lang, "en"] {
            if let url = Bundle.main.url(forResource: l, withExtension: "json"),
               let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(ScriptBook.self, from: d) {
                cached = (b, l)
                return (b, l)
            }
        }
        fatalError("Scripts manquants")
    }
    private static var cached: (ScriptBook, String)?
}

/// Qui parle : le Père Noël, ou son lutin (qui lit ce que le parent a écrit, et les prénoms plus rares).
enum Speaker: Equatable { case santa, elf }

/// Comment dire une phrase : des répliques enregistrées à enchaîner (avec la synthèse de l'iPhone en secours si un
/// fichier manquait), ou le lutin.
enum VoiceCue: Equatable {
    case clips([String], fallback: String)
    case elf(String)
}

enum Segment: Equatable {
    case say(String, speaker: Speaker, laugh: Bool, wave: Bool, cue: VoiceCue)
    case listen(Double)
    case spark(Double)

    var text: String? { if case let .say(t, _, _, _, _) = self { return t }; return nil }
}

/// Assemble l'appel : les phrases du scénario, avec les prénoms, l'âge, les qualités, et le lutin pour l'anecdote
/// et le cadeau.
struct ScriptBuilder {
    var book: ScriptBook
    var lang: String
    var profile: ChildProfile
    var premium: Bool

    /// L'appel entier, ou l'aperçu gratuit : l'histoire s'arrête à la coupure, et le Père Noël dit au revoir.
    func build(_ scenario: Scenario) -> (segments: [Segment], preview: Bool) {
        var out: [Segment] = []
        let cut = append(book.scenarios[scenario.rawValue] ?? [], to: &out, depth: 0)
        if cut { _ = append(book.blocks["previewEnd"] ?? [], to: &out, depth: 1) }
        return (out, cut)
    }

    func block(_ name: String) -> [Segment] {
        var out: [Segment] = []
        _ = append(book.blocks[name] ?? [], to: &out, depth: 1)
        return out
    }

    /// Une réplique seule (le calendrier de l'Avent).
    static func line(_ text: String) -> Segment {
        .say(text, speaker: .santa, laugh: false, wave: false, cue: .clips([VoiceLibrary.lineKey(text)], fallback: text))
    }

    /// Vrai si l'aperçu gratuit s'est arrêté là.
    private func append(_ steps: [ScriptStep], to out: inout [Segment], depth: Int) -> Bool {
        for s in steps {
            if s.cut == true {
                if !premium && depth == 0 { return true }
                continue
            }
            if let inc = s.include, depth < 3 {
                if append(book.blocks[inc] ?? [], to: &out, depth: depth + 1) { return true }
                continue
            }
            guard holds(s.if) else { continue }
            let laugh = s.laugh ?? false, wave = s.wave ?? false
            if s.hello == true { hello(&out, laugh: laugh) }
            if s.bye == true { bye(&out, wave: wave) }
            if let say = s.say, !say.isEmpty {
                let text = fill(pick(say))
                out.append(.say(text, speaker: .santa, laugh: laugh, wave: wave,
                                cue: .clips([VoiceLibrary.lineKey(text)], fallback: text)))
            }
            if let elf = s.elf, !elf.isEmpty {
                let text = fill(pick(elf))
                out.append(.say(text, speaker: .elf, laugh: false, wave: false, cue: .elf(text)))
            }
            if let l = s.listen { out.append(.listen(l)) }
            if let sp = s.spark { out.append(.spark(sp)) }
        }
        return false
    }

    private func pick(_ forms: [String]) -> String { profile.isPlural && forms.count > 1 ? forms[1] : forms[0] }

    private var names: [String] { profile.cleanNames }
    private var joinedNames: String { Grammar.join(names, and: book.and) }
    /// La voix enregistrée sert-elle dans cette langue ? Sinon c'est la voix de l'iPhone, qui sait dire tous les prénoms.
    private var recorded: Bool { VoiceLibrary.shared.ready(lang: lang) }
    /// Le Père Noël dit-il ces prénoms ? Oui s'il les a tous enregistrés (ou s'il parle avec la voix de l'iPhone).
    private var namesKnown: Bool {
        !names.isEmpty && (!recorded || names.allSatisfy { VoiceLibrary.shared.knows(name: $0, lang: lang) })
    }

    private func hello(_ out: inout [Segment], laugh: Bool) {
        if namesKnown {
            let text = book.hello.replacingOccurrences(of: "{name}", with: joinedNames)
            out.append(.say(text, speaker: .santa, laugh: laugh, wave: false,
                            cue: .clips(names.map { VoiceLibrary.helloKey($0) }, fallback: text)))
            return
        }
        // Un prénom que le Père Noël n'a pas enregistré : il salue sans le dire. Une seule voix dans l'appel.
        out.append(.say(book.helloAnyone, speaker: .santa, laugh: laugh, wave: false,
                        cue: .clips([VoiceLibrary.lineKey(book.helloAnyone)], fallback: book.helloAnyone)))
    }

    private func bye(_ out: inout [Segment], wave: Bool) {
        if namesKnown, !recorded || names.allSatisfy({ VoiceLibrary.shared.knowsBye(name: $0, lang: lang) }) {
            let text = book.bye.replacingOccurrences(of: "{name}", with: joinedNames)
            out.append(.say(text, speaker: .santa, laugh: false, wave: wave,
                            cue: .clips(names.map { VoiceLibrary.byeKey($0) }, fallback: text)))
            return
        }
        // Sans le prénom : il dit simplement au revoir.
        out.append(.say(book.byeAnyone, speaker: .santa, laugh: true, wave: wave,
                        cue: .clips([VoiceLibrary.lineKey(book.byeAnyone)], fallback: book.byeAnyone)))
    }

    private var anecdote: String { premium ? Grammar.clean(profile.anecdote) : "" }
    private var gift: String { premium ? Grammar.clean(profile.gift) : "" }
    private var picked: [Quality] { Array(Quality.allCases.filter { profile.qualities.contains($0) }.prefix(2)) }

    private func holds(_ cond: String?) -> Bool {
        switch cond {
        case nil: return true
        case "quality": return !picked.isEmpty
        case "quality2": return picked.count > 1
        case "noQuality": return picked.isEmpty
        case "anecdote": return !anecdote.isEmpty
        case "noAnecdote": return anecdote.isEmpty
        case "gift": return !gift.isEmpty
        case "single": return !profile.isPlural
        case "plural": return profile.isPlural
        default: return true
        }
    }

    private func quality(_ i: Int) -> String {
        guard i < picked.count, let forms = book.qualities[picked[i].rawValue], !forms.isEmpty else { return "" }
        return pick(forms)
    }

    private func fill(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: "{name}", with: joinedNames)
        s = s.replacingOccurrences(of: "{age}", with: "\(min(10, max(3, profile.age)))")
        s = s.replacingOccurrences(of: "{q1}", with: quality(0))
        s = s.replacingOccurrences(of: "{q2}", with: quality(1))
        s = s.replacingOccurrences(of: "{anecdote}", with: anecdote)
        s = s.replacingOccurrences(of: "{gift}", with: gift)
        return s
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
}
