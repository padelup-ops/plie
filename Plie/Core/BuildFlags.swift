import Foundation

/// Réglages de la version envoyée.
enum BuildFlags {
    /// Version de test : sur TestFlight, les testeurs ont tous les jeux et tous les niveaux, sans payer.
    /// Sans effet sur l'App Store (le reçu y est un reçu de production), mais à remettre à `false`
    /// pour le build envoyé à la validation d'Apple : l'examinateur doit voir les cadenas et le Pass.
    static let testersGetEverything = true
}
