// Rejoue un fichier « Duo Folds » (le script Scriptable : total, days, hours, last) avec un lecteur d'historique
// donné, celui de la version en vente ou celui du dépôt, sous plusieurs réglages d'iPhone (fuseau, région,
// calendrier). Même forme que le fichier qu'un utilisateur n'a pas pu importer, avec d'autres nombres.
//   swiftc [-D HISTORY_IMPORT_TEST] HistoryImport.swift clapet/tools/import-test/sample/main.swift -o rejoue && ./rejoue

import Foundation

enum ClapetStats {
    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

let sample = #"{"total":640,"days":{"2026-11-13":21,"2026-11-14":14,"2026-11-15":19,"2026-11-16":11,"2026-11-17":33,"2026-11-18":17,"2026-11-19":12,"2026-11-20":16,"2026-11-21":22,"2026-11-22":13,"2026-11-23":18,"2026-11-24":25,"2026-11-25":31,"2026-11-26":27,"2026-11-27":20},"hours":{"date":"2026-11-27","h":[1,0,0,0,0,0,0,0,1,1,2,2,1,3,3,1,1,2,1,1,1,0,0,0]},"last":1795782000000}"#

let r = HistoryImport.parse(sample)
let label = CommandLine.arguments.dropFirst().first ?? "lecteur"
print("REJOUE \(label) · fuseau \(TimeZone.current.identifier) · région \(Locale.current.identifier) · calendrier \(Calendar.current.identifier) : \(r.days.count) jours, \(r.totalCloses) plis (attendu 15 jours, 299 plis), du \(r.first ?? "-") au \(r.last ?? "-")")
