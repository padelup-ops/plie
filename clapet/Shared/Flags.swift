import Foundation

/// Comment Foldly est vendu.
enum DuoFolds {
    /// App payante (version 1.0) : qui l'a achetée a tout. À partir de la 1.0.1, l'app est gratuite
    /// et Foldly+ s'achète une fois, à vie (widgets, alertes, historique, couleurs, export).
    static let paidApp = false

    /// Le premier build gratuit publié sur l'App Store (le build de la 1.0.1).
    /// Ceux qui ont téléchargé l'app avant (quand elle était payante) gardent Foldly+ sans rien payer.
    /// 0 : pas encore fixé (l'outil de mise en production refuse d'envoyer la version tant que c'est 0).
    static let firstFreeBuild = 0
}
