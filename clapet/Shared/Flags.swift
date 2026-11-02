import Foundation

/// Comment Foldly est vendu.
enum DuoFolds {
    /// false : app gratuite, tout se débloque avec l'achat intégré Foldly+.
    /// (La 1.0 était payante : ses acheteurs gardent tout, voir ClapetStore.earlyBuyer.)
    static let paidApp = false
    /// Premier build de l'app gratuite. Qui a téléchargé un build plus ancien avait payé l'app.
    static let firstFreeBuild = 48
}
