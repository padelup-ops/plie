// Essai autonome du lecteur d'historique de Foldly (clapet/Shared/HistoryImport.swift), lancé sur le Mac de
// compilation avant chaque build :
//   swiftc -D HISTORY_IMPORT_TEST clapet/Shared/HistoryImport.swift clapet/tools/import-test/main.swift -o essai && ./essai
// Chaque cas : un fichier comme en écrivent Scriptable, Raccourcis ou un tableur, et ce que Foldly doit y trouver.

import Foundation

/// La clé du jour, comme dans l'app (ClapetStats.key).
enum ClapetStats {
    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

struct Case {
    var name: String
    var text: String
    /// Nombre de jours attendu (nil : dépend du fuseau, on ne regarde que les totaux).
    var days: Int?
    var closes: Int
    var opens: Int
}

let cases: [Case] = [
    Case(name: "Scriptable : total, days, hours", text: #"{"total":493,"days":{"2025-10-27":47,"2025-10-28":52},"hours":{"08":3}}"#, days: 2, closes: 99, opens: 0),
    Case(name: "marque invisible en tête de fichier", text: "\u{FEFF}" + #"{"total":493,"days":{"2025-10-27":47,"2025-10-28":52}}"#, days: 2, closes: 99, opens: 0),
    Case(name: "nombres écrits en texte", text: #"{"2025-10-27":"47","2025-10-28":"52"}"#, days: 2, closes: 99, opens: 0),
    Case(name: "dates d'un bloc (20251027)", text: #"{"days":{"20251027":47,"20251028":52}}"#, days: 2, closes: 99, opens: 0),
    Case(name: "champs f et u", text: #"{"daily":{"2025-10-27":{"f":47,"u":45}}}"#, days: 1, closes: 47, opens: 45),
    Case(name: "tranches horaires par jour", text: #"{"2025-10-27":{"08":3,"09":5}}"#, days: 1, closes: 8, opens: 0),
    Case(name: "liste des plis par jour", text: #"{"2025-10-27":[1761550000000,1761553600000,1761557200000]}"#, days: 1, closes: 3, opens: 0),
    Case(name: "paire [plis, ouvertures] par jour", text: #"{"2025-10-27":[47,45]}"#, days: 1, closes: 47, opens: 45),
    Case(name: "lignes [date, plis, ouvertures]", text: #"[["2025-10-27",47,45],["2025-10-28",52,50]]"#, days: 2, closes: 99, opens: 95),
    Case(name: "journal, un objet par ligne", text: """
        {"date":"2025-10-27T08:00:00","state":"closed"}
        {"date":"2025-10-27T08:05:00","state":"open"}
        {"date":"2025-10-28T09:00:00","state":"closed"}
        """, days: 2, closes: 2, opens: 1),
    Case(name: "horodatages dans un champ ts", text: #"{"folds":[{"ts":1761550000000},{"ts":1761553600000}]}"#, days: nil, closes: 2, opens: 0),
    Case(name: "vrai/faux : open", text: #"[{"time":"2025-10-27T08:00:00","open":true},{"time":"2025-10-27T08:01:00","open":false}]"#, days: 1, closes: 1, opens: 1),
    Case(name: "fichier JavaScript autour du JSON", text: #"const data = {"2025-10-27": 47, "2025-10-28": 52};"#, days: 2, closes: 99, opens: 0),
    Case(name: "JSON avec une virgule en trop", text: #"{"2025-10-27": 47, "2025-10-28": 52,}"#, days: 2, closes: 99, opens: 0),
    Case(name: "liste d'objets par jour", text: #"[{"date":"2025-10-27","folds":47,"unfolds":45},{"date":"2025-10-28","count":52}]"#, days: 2, closes: 99, opens: 45),
    Case(name: "historique rangé en profondeur", text: #"{"data":{"stats":{"history":{"2025-10-27":{"count":47,"lastState":"closed"}}}}}"#, days: 1, closes: 47, opens: 0),
    Case(name: "count passe avant total", text: #"[{"date":"2025-10-27","count":5,"total":493}]"#, days: 1, closes: 5, opens: 0),
    Case(name: "liste de dates (un pli chacune)", text: #"["2025-10-27T08:00:00","2025-10-27T09:00:00","2025-10-28T09:00:00"]"#, days: 2, closes: 3, opens: 0),
    Case(name: "CSV avec en-tête", text: "date,folds,unfolds\n2025-10-27,47,45\n2025-10-28,52,50", days: 2, closes: 99, opens: 95),
    Case(name: "une ligne par pli (Raccourcis)", text: "Oct 27, 2025 at 8:17 PM\nOct 27, 2025 at 9:17 PM", days: 1, closes: 2, opens: 0),
    Case(name: "JSON sans date", text: #"{"hello":"world","n":3}"#, days: 0, closes: 0, opens: 0),
    Case(name: "texte quelconque", text: "bonjour", days: 0, closes: 0, opens: 0),
]

var failed = 0
for c in cases {
    let r = HistoryImport.parse(c.text)
    let ok = (c.days == nil || r.days.count == c.days) && r.totalCloses == c.closes && r.totalOpens == c.opens
    if !ok { failed += 1 }
    print("\(ok ? "ok    " : "RATÉ  ") \(c.name) : \(r.days.count) jours, \(r.totalCloses) plis, \(r.totalOpens) ouvertures"
        + (ok ? "" : " (attendu \(c.days.map(String.init) ?? "?") jours, \(c.closes) plis, \(c.opens) ouvertures)"))
}
print("RESULT import \(cases.count - failed)/\(cases.count) \(failed == 0 ? "yes" : "no")")
exit(failed == 0 ? 0 : 1)
