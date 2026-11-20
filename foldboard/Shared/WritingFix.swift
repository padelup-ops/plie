// WritingFix.swift — Foldboard
//
// « Corriger » dans la barre du clavier : la phrase (le paragraphe) avant le curseur est corrigée par le modèle de
// langue d'Apple Intelligence, sur l'iPhone (rien n'est envoyé). Orthographe, grammaire, ponctuation ; même langue,
// même ton. Le bouton n'apparaît que si le modèle est disponible (iPhone compatible, Apple Intelligence activé).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum KBWritingFix {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Le texte corrigé, ou nil si le modèle n'a pas répondu.
    static func fix(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
            You fix typing. Correct the spelling, grammar, accents and punctuation of the user's text. \
            Keep the same language, meaning, tone, wording and line breaks; change as little as possible. \
            Reply with the corrected text only, with no quotes and no comment.
            """)
            guard let r = try? await session.respond(to: text) else { return nil }
            let out = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : out
        }
        #endif
        return nil
    }
}
