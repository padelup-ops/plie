import SwiftUI
import UIKit

/// Banc d'essai de la mémoire, sur simulateur (lancé avec « -shot memprobe ») : le vrai clavier à la taille du Duo
/// ouvert, toute la largeur, comme un utilisateur qui s'en sert depuis des semaines (journal, mots, appuis remplis).
/// Chaque étape note la mémoire comptée par iOS (phys_footprint) dans Documents/memprobe.txt.
/// Jamais affiché dans l'app normale.
struct MemProbeView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .systemBackground
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MemProbe.run(in: v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum MemProbe {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("memprobe.txt")
    }
    private static var lines: [String] = []
    private static var last = 0.0

    static func log(_ step: String) {
        let mb = KeyboardCanvas.footprintMB()
        let line = String(format: "%-34@ %7.1f Mo  (%+6.1f)  claviers=%d correcteurs=%d", step as NSString, mb, mb - last,
                          KeyboardCanvas.alive, KBSuggest.alive)
        last = mb
        lines.append(line)
        print("MEMPROBE " + line)
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func mark(_ m: String) {
        lines.append(m)
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Un utilisateur de longue date : journal de la main plein, mots appris, appuis mémorisés.
    static func seed() {
        for i in 0..<4_000 {
            KBGripLog.shared.add(Double(1 + i % 4), context: i % 3 == 0 ? "open-portrait" : "closed-portrait",
                                 ["ts": Double(i) * 0.3, "kx": 0.4, "dx": 0.1, "dy": -0.05, "r": 22, "side": 1,
                                  "roll": 12.5, "inc": 30.2])
        }
        KBGripLog.shared.flush()
        let ws = ["bonjour", "merci", "demain", "travail", "maison", "voiture", "manger", "ce", "soir", "on", "se", "voit"]
        for i in 0..<4_000 { KBWordStore.shared.commit(ws[i % ws.count] + (i % 7 == 0 ? "" : String(i)), after: ws[(i + 3) % ws.count]) }
        var m = KBTapMap()
        for c in "abcdefghijklmnopqrstuvwxyz " { for k in 0..<40 { m.add(key: String(c), dx: Double(k % 5) * 0.05, dy: -0.1, twoHands: k % 2 == 0) } }
        KBVault.saveTaps(m)
    }

    final class Field: KBInput {
        var text = ""
        func kbInsert(_ t: String) { text += t }
        func kbDelete() { if !text.isEmpty { text.removeLast() } }
        func kbMoveCursor(_ offset: Int) {}
        func kbTextBefore() -> String? { String(text.suffix(400)) }
        func kbTextAfter() -> String? { "" }
        func kbNextKeyboard() {}
        func kbDismiss() {}
        func kbSettingsChanged(_ settings: KBSettings) {}
        var kbNeedsGlobe: Bool { false }
        var kbFullAccess: Bool { true }
        func kbRecheckPro(_ done: @escaping (Bool) -> Void) { done(true) }
    }

    private static var field = Field()

    private static func settings(_ layout: KBLayout) -> KBSettings {
        var s = KBSettings()
        s.layout = layout
        s.mode = .full
        return s
    }

    @MainActor
    private static func make(in host: UIView, layout: KBLayout = .azerty) -> KeyboardCanvas {
        let c = KeyboardCanvas()
        c.input = field
        c.demoContext = "open-portrait"
        c.configure(settings: settings(layout), pro: true)
        let h = c.preferredHeight
        c.frame = CGRect(x: 0, y: max(0, host.bounds.height - h), width: min(669, host.bounds.width), height: h)
        host.addSubview(c)
        c.appeared()
        c.setNeedsLayout()
        c.layoutIfNeeded()
        return c
    }

    private static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static let french = "salut je suis en train de tester le clavier sur le duo ouvert et je tape une phrase assez longue pour voir "
        + "si la correction tient le coup avec des fautes comme bonjoru ou travial et des mots anglais "
    static let english = "Hello I am testing the keyboard with an english sentence to see how it goes with spendy words and typos lile thsi "

    @MainActor
    static func run(in host: UIView) {
        Task { @MainActor in
            try? FileManager.default.removeItem(at: url)
            log("0 app lancée")
            seed()
            log("1 données d'un utilisateur")
            var kb = make(in: host)
            await wait(2)
            log("2 clavier affiché (Duo ouvert, large)")
            kb.probeType(french)
            await wait(2)
            log("3 phrase française tapée")
            kb.probeType(english)
            await wait(2)
            log("4 phrase anglaise tapée")
            mark("SNAP")
            await wait(25)
            kb.probeEmoji(true)
            await wait(2)
            log("5 emojis ouverts")
            kb.probeEmoji(false)
            await wait(1)
            log("6 emojis fermés")
            // Le globe : le clavier disparaît, iOS en recrée un (dans le même processus).
            for i in 1...8 {
                kb.disappeared()
                kb.removeFromSuperview()
                await wait(0.5)
                kb = make(in: host, layout: i % 2 == 0 ? .azerty : .qwerty)
                kb.probeType("ok merci a demain ")
                await wait(1.5)
                log("7.\(i) globe, nouveau clavier")
            }
            kb.trimMemory()
            await wait(1)
            log("8 après trimMemory")
            mark("SNAP2")
            await wait(20)
            mark("DONE")
        }
    }
}
