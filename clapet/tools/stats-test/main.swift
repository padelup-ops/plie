// Essai autonome du temps ouvert et du mode Repos de Foldly (clapet/Shared/ClapetStats.swift), lancé sur le Mac de
// compilation avant chaque build :
//   swiftc clapet/Shared/ClapetStats.swift clapet/Shared/Flags.swift clapet/tools/stats-test/main.swift -o essai && ./essai
// Le cas d'un utilisateur : le raccourci « Foldly repos » passe le soir, « Foldly utilisé » ne passe pas le matin
// (iPhone verrouillé), le repos restait allumé pour toujours et tout le temps ouvert tombait à 0.

import Foundation

let cal = Calendar.current
/// Le jour 1 à minuit, puis des heures comptées depuis là (36 = le jour 2 à midi).
let base = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
func at(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }
let later = at(24 * 6)

func fresh() -> ClapetStats {
    var s = ClapetStats()
    s.nightOn = false   // seulement le repos du raccourci, pas les heures de repos réglées dans l'app
    return s
}

var failed = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    if !ok { failed += 1 }
    print("\(ok ? "ok    " : "RATÉ  ") \(name) : \(detail)")
}
func minutes(_ t: TimeInterval) -> Int { Int((t / 60).rounded()) }

// 1. Une nuit normale : ouvert de 22 h à 8 h, repos de 23 h à 7 h (les deux raccourcis passent).
do {
    var s = fresh()
    s.startOpen(at(22), event: true)
    s.startRest(at(23))
    s.endRest(at(31))
    s.endOpen(at(32), event: true)
    let d1 = minutes(s.openTime(at(12), now: later)), d2 = minutes(s.openTime(at(36), now: later))
    check("nuit normale", d1 == 60 && d2 == 60 && !s.isResting(at(33)) && s.restSince == nil,
          "jour 1 \(d1) min, jour 2 \(d2) min (attendu 60 et 60)")
}

// 2. « Foldly utilisé » ne passe pas : le lendemain après-midi, le temps ouvert compte de nouveau.
do {
    var s = fresh()
    s.startRest(at(23))
    s.startOpen(at(39), event: true)
    s.endOpen(at(40), event: true)
    let d2 = minutes(s.openTime(at(36), now: later))
    check("repos resté allumé, l'après-midi", d2 == 60 && s.restSince == nil && !s.isResting(at(41)),
          "jour 2 \(d2) min (attendu 60), repos fini : \(s.restSince == nil)")
}

// 3. Le même, avec une ouverture le matin (encore dans les 12 h : au repos) puis une l'après-midi (comptée).
do {
    var s = fresh()
    s.startRest(at(23))
    s.startOpen(at(33), event: true)
    s.endOpen(at(34), event: true)
    let morning = minutes(s.openTime(at(36), now: later)), rest = minutes(s.restTime(at(36), now: later))
    s.startOpen(at(36), event: true)
    s.endOpen(at(37), event: true)
    let day = minutes(s.openTime(at(36), now: later))
    check("repos resté allumé, matin puis après-midi", morning == 0 && rest == 60 && day == 60,
          "matin \(morning) min compté, \(rest) min au repos, journée \(day) min (attendu 0, 60, 60)")
}

// 4. Un repos commencé avec une ancienne version (pas de début connu) : il finit 12 h après la dernière fermeture.
do {
    var s = fresh()
    s.restSince = at(23)
    s.startOpen(at(33), event: true)
    s.endOpen(at(34), event: true)
    let began = s.restBegan
    s.startOpen(at(36), event: true)
    s.endOpen(at(37), event: true)
    let day = minutes(s.openTime(at(36), now: later))
    check("repos d'une ancienne version", began == at(23) && day == 60 && s.restSince == nil,
          "journée \(day) min (attendu 60), début retrouvé : \(began == at(23))")
}

// 5. En direct : Duo ouvert depuis 15 h, il est 15 h 30, le repos de la veille est resté allumé.
do {
    var s = fresh()
    s.startRest(at(23))
    s.startOpen(at(39), event: true)
    let live = minutes(s.openTime(at(39.5), now: at(39.5)))
    check("en direct, repos de la veille", live == 30 && !s.isResting(at(39.5)), "\(live) min (attendu 30)")
}

// 6. Pendant le repos (dans les 12 h), le temps ouvert n'est pas compté et le repos est annoncé.
do {
    var s = fresh()
    s.startOpen(at(22), event: true)
    s.startRest(at(23))
    let live = minutes(s.openTime(at(26), now: at(26))), rest = minutes(s.restTime(at(26), now: at(26)))
    check("pendant le repos", live == 0 && rest == 120 && s.isResting(at(26)),
          "\(live) min compté, \(rest) min au repos depuis minuit (attendu 0 et 120), repos annoncé : \(s.isResting(at(26)))")
}

// 7. Un nouveau « Foldly repos » le soir suivant repart de zéro, même si le précédent n'a jamais été arrêté.
do {
    var s = fresh()
    s.startRest(at(23))
    s.startRest(at(47))
    check("nouveau repos le lendemain soir", s.restBegan == at(47) && s.isResting(at(48)) && !s.isResting(at(60)),
          "début \(s.restBegan == at(47) ? "le lendemain 23 h" : "ancien"), fini 12 h après : \(!s.isResting(at(60)))")
}

// 8. Les chiffres se relisent tels quels (le début du repos compris).
do {
    var s = fresh()
    s.startRest(at(23))
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(ClapetStats.self, from: data)
    check("enregistrement", back.restBegan == s.restBegan && back.restSince == s.restSince, "début du repos relu : \(back.restBegan == s.restBegan)")
}

print("RESULT stats \(failed == 0 ? "yes" : "no") (\(failed) raté)")
exit(failed == 0 ? 0 : 1)
