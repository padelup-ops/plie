import Foundation

/// Réglages de la version envoyée.
enum BuildFlags {
    /// Version de test : sur TestFlight, les testeurs ont tous les jeux et tous les niveaux, sans payer.
    /// Sans effet sur l'App Store (le reçu y est un reçu de production), mais à remettre à `false`
    /// pour le build envoyé à la validation d'Apple : l'examinateur doit voir les cadenas et le Pass.
    static let testersGetEverything = true

    /// App payante sur l'App Store : qui l'achète a tout (tous les jeux, tous les niveaux, tous les duels).
    /// Plus de clés ni de Pass. Mettre à false pour revenir au modèle gratuit + Pass Origamo.
    static let paidApp = true

    /// « On plante un vrai arbre » : seulement quand un partenaire de reforestation est choisi.
    static let realTrees = false
}
