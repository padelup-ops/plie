// Fichier généré par tools/pliage_gen.py : ne pas modifier à la main.
// Chaque niveau a été vérifié : « par » est exactement le nombre minimal de plis.
// Cases : 0 = papier, 1 = rouge, 2 = jaune, 4 = bleu, et leurs mélanges (somme).

import Foundation

extension PliageLevel {
    static let all: [PliageLevel] = [
        PliageLevel(number: 1, world: 1, width: 4, height: 4, start: "0000040400040000", target: "0000444440040000", par: 1, solution: "v2"),
        PliageLevel(number: 2, world: 1, width: 4, height: 4, start: "0000440000040000", target: "0000440444040000", par: 1, solution: "h2"),
        PliageLevel(number: 3, world: 1, width: 4, height: 4, start: "0400400004000000", target: "0400440044000400", par: 1, solution: "h2"),
        PliageLevel(number: 4, world: 1, width: 4, height: 4, start: "0000004040004000", target: "4000404040404000", par: 1, solution: "h2"),
        PliageLevel(number: 5, world: 1, width: 4, height: 4, start: "0000000000004000", target: "0000000040044004", par: 2, solution: "h3 v2"),
        PliageLevel(number: 6, world: 1, width: 4, height: 4, start: "0400000000000000", target: "4400000000004400", par: 2, solution: "v1 h2"),
        PliageLevel(number: 7, world: 1, width: 4, height: 4, start: "0000000000040000", target: "0000000000440044", par: 2, solution: "h3 v3"),
        PliageLevel(number: 8, world: 1, width: 4, height: 4, start: "0000040000000040", target: "0000040000440044", par: 2, solution: "h3 v3"),
        PliageLevel(number: 9, world: 1, width: 4, height: 4, start: "0040000000040000", target: "0044004400440000", par: 2, solution: "v3 h1"),
        PliageLevel(number: 10, world: 1, width: 4, height: 4, start: "0400000000000044", target: "0440044000004444", par: 2, solution: "h1 v2"),
        PliageLevel(number: 11, world: 1, width: 4, height: 4, start: "0000000400000040", target: "0440400440040440", par: 2, solution: "v2 h2"),
        PliageLevel(number: 12, world: 1, width: 4, height: 4, start: "0000000000440000", target: "0000000044444444", par: 2, solution: "h3 v2"),
        PliageLevel(number: 13, world: 1, width: 4, height: 4, start: "0000000000040004", target: "4004400440044004", par: 2, solution: "v2 h2"),
        PliageLevel(number: 14, world: 1, width: 4, height: 4, start: "0040000000000040", target: "0444000000000444", par: 2, solution: "v2 v3"),
        PliageLevel(number: 15, world: 1, width: 4, height: 4, start: "0040004000000000", target: "4444444400000000", par: 2, solution: "v3 v2"),
        PliageLevel(number: 16, world: 2, width: 5, height: 5, start: "0500000000000000000000000", target: "5500055000000000000000000", par: 2, solution: "h1 v1"),
        PliageLevel(number: 17, world: 2, width: 5, height: 5, start: "2000000030000000000002000", target: "2200000033000000000022000", par: 2, solution: "v1 v4"),
        PliageLevel(number: 18, world: 2, width: 5, height: 5, start: "0420004000000000000200000", target: "0660004400000000000200002", par: 2, solution: "v2 h4"),
        PliageLevel(number: 19, world: 2, width: 5, height: 5, start: "0001000000000000000000030", target: "0011000330000000000000330", par: 2, solution: "v3 h3"),
        PliageLevel(number: 20, world: 2, width: 5, height: 5, start: "0020060000020000000000000", target: "6620066200220000000000000", par: 2, solution: "h1 v1"),
        PliageLevel(number: 21, world: 2, width: 5, height: 5, start: "0000000100004000001100000", target: "0000000110015510155100110", par: 2, solution: "h3 v3"),
        PliageLevel(number: 22, world: 2, width: 5, height: 5, start: "0300000000000000001000000", target: "0300003000000110001103000", par: 3, solution: "h1 h3 v4"),
        PliageLevel(number: 23, world: 2, width: 5, height: 5, start: "0000000010000000401100000", target: "0000001111000004511500000", par: 3, solution: "v4 v1 v3"),
        PliageLevel(number: 24, world: 2, width: 5, height: 5, start: "0000000000002400400000000", target: "0000000000662404440044400", par: 3, solution: "h4 v2 v1"),
        PliageLevel(number: 25, world: 2, width: 5, height: 5, start: "0020000400000000000200000", target: "0266200660006600266200000", par: 3, solution: "v3 h1 h2"),
        PliageLevel(number: 26, world: 2, width: 5, height: 5, start: "0000000000001200000000001", target: "0000001331003300033001331", par: 3, solution: "h2 v3 h3"),
        PliageLevel(number: 27, world: 2, width: 5, height: 5, start: "0000000020001020100000000", target: "0000000220031130333303333", par: 3, solution: "v3 h3 h4"),
        PliageLevel(number: 28, world: 2, width: 5, height: 5, start: "0000000020004020000000000", target: "0000022220466460000000000", par: 3, solution: "v2 v3 v2"),
        PliageLevel(number: 29, world: 2, width: 5, height: 5, start: "0000041000000000000041000", target: "0000055144000000000055144", par: 3, solution: "v2 v1 v4"),
        PliageLevel(number: 30, world: 2, width: 5, height: 5, start: "0000000104000010000000000", target: "0000055555111110000000000", par: 3, solution: "v3 v4 v2"),
        PliageLevel(number: 31, world: 3, width: 6, height: 6, start: "002001000000000000000040000000000000", target: "002055002011002011002055000000000000", par: 3, solution: "h1 v5 h2"),
        PliageLevel(number: 32, world: 3, width: 6, height: 6, start: "000002000000100004000000000000000000", target: "220002000000550005550005000000220002", par: 3, solution: "v3 h3 v1"),
        PliageLevel(number: 33, world: 3, width: 6, height: 6, start: "004000000000000002000000000001000000", target: "006006003003003003006006001001004004", par: 3, solution: "h3 h2 v4"),
        PliageLevel(number: 34, world: 3, width: 6, height: 6, start: "000000000000002001000000000040000000", target: "000000303303303303000000044440000000", par: 3, solution: "h2 v4 v3"),
        PliageLevel(number: 35, world: 3, width: 6, height: 6, start: "040000000000001200000000000000010004", target: "054044000000001233001233000000054044", par: 3, solution: "h3 v4 v5"),
        PliageLevel(number: 36, world: 3, width: 6, height: 6, start: "000000001000500200100000000000000000", target: "000000001111507227101001101001507227", par: 3, solution: "v3 v4 h4"),
        PliageLevel(number: 37, world: 3, width: 6, height: 6, start: "000000000200014040000000000000400000", target: "400044002200054455054455002200400044", par: 3, solution: "v3 h3 v5"),
        PliageLevel(number: 38, world: 3, width: 6, height: 6, start: "004000100000000000000000000000200000", target: "334000114000000000000000334000334000", par: 4, solution: "v1 h1 h3 h5"),
        PliageLevel(number: 39, world: 3, width: 6, height: 6, start: "000000002000000000000000000000400001", target: "000000202222000000000000501155501155", par: 4, solution: "v4 v3 h5 v5"),
        PliageLevel(number: 40, world: 3, width: 6, height: 6, start: "000000000000002000000100000000400000", target: "003300003300402204001100001100402204", par: 4, solution: "h2 h4 v3 h1"),
        PliageLevel(number: 41, world: 3, width: 6, height: 6, start: "000000400000000000000200000000002100", target: "003300443304002200002200443304003300", par: 4, solution: "v3 v1 h5 h3"),
        PliageLevel(number: 42, world: 3, width: 6, height: 6, start: "000100000000000020000000400200100000", target: "100120700720100120100120700720100120", par: 4, solution: "h2 h1 h3 v2"),
        PliageLevel(number: 43, world: 3, width: 6, height: 6, start: "000000000000000000000000000000000241", target: "000000342243342243000000000000342243", par: 4, solution: "h4 v2 v3 h2"),
        PliageLevel(number: 44, world: 3, width: 6, height: 6, start: "000012004000000000000000000000000000", target: "330033004400004400330033004400330033", par: 4, solution: "v5 v3 h3 h2"),
        PliageLevel(number: 45, world: 3, width: 6, height: 6, start: "000000000200000410000000002000000000", target: "000000002200014411002200016611016611", par: 4, solution: "h4 v3 v5 h5")
    ]
}
