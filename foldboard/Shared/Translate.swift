// Translate.swift — Foldboard
//
// Traduire sans quitter le clavier : ce qu'on dicte (parlé en français, écrit en anglais, et l'inverse), ou le texte
// déjà tapé (bouton 🌐 de la barre). Tout se fait sur l'iPhone : la traduction d'Apple (langues téléchargées dans
// Réglages › Apps › Traduire, ou depuis l'app Foldboard), sinon le modèle d'Apple Intelligence.

import Foundation
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

enum KBTranslate {
    /// Les langues proposées (codes ISO), et leur nom dans la langue de l'iPhone.
    static let languages = ["en", "fr", "es", "de", "it", "pt", "nl", "ja", "ko", "zh", "ru", "ar", "tr", "pl", "uk", "hi"]

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: Locale.current) ?? code
    }

    /// La langue d'un texte (au moins quelques mots), ou nil.
    static func detect(_ text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let l = r.dominantLanguage else { return nil }
        let code = String(l.rawValue.prefix(2))
        return code == "zh" ? "zh" : code
    }

    /// La paire : ce qui est dit dans l'une part dans l'autre (français ⇄ anglais par défaut).
    static func target(for text: String, pair: [String]) -> (from: String, to: String)? {
        guard pair.count == 2 else { return nil }
        let src = detect(text) ?? pair[0]
        if src == pair[0] { return (src, pair[1]) }
        if src == pair[1] { return (src, pair[0]) }
        // Une troisième langue : vers la première de la paire.
        return (src, pair[0])
    }

    enum Failure: Error { case notInstalled(String, String), unavailable }

    /// Le texte traduit. `notInstalled` : les langues ne sont pas encore sur l'iPhone (à télécharger dans l'app).
    static func translate(_ text: String, from: String, to: String) async -> Result<String, Failure> {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, from != to else { return .success(text) }
        #if canImport(Translation)
        if #available(iOS 26.0, *) {
            let src = Locale.Language(identifier: from), dst = Locale.Language(identifier: to)
            let status = await LanguageAvailability().status(from: src, to: dst)
            if status == .installed {
                let session = TranslationSession(installedSource: src, target: dst)
                if let r = try? await session.translate(t) { return .success(r.targetText) }
            }
            if let r = await viaModel(t, to: to) { return .success(r) }
            if status == .supported { return .failure(.notInstalled(from, to)) }
            return .failure(.unavailable)
        }
        #endif
        if let r = await viaModel(t, to: to) { return .success(r) }
        return .failure(.unavailable)
    }

    /// Le modèle d'Apple Intelligence, quand la traduction d'Apple n'a pas ces langues sur l'iPhone.
    private static func viaModel(_ text: String, to: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let lang = Locale(identifier: "en").localizedString(forLanguageCode: to) ?? to
            let session = LanguageModelSession(instructions: """
            You translate. Translate the user's text into \(lang). Keep the meaning, tone, names, emojis and line \
            breaks. Reply with the translation only, with no quotes and no comment.
            """)
            guard let r = try? await session.respond(to: text) else { return nil }
            let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        }
        #endif
        return nil
    }
}
