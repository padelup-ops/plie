import Foundation

// CrashNote.swift — Foldboard
//
// Le carnet des dernières étapes du clavier, pour comprendre un clavier qui « saute » (par exemple après la touche
// globe sur l'écran déplié) : quelques repères écrits directement dans un fichier, un par étape, et, si le clavier
// plante, le genre de plantage et la pile d'appels. Au redémarrage suivant, le relevé de diagnostic (appui long sur
// « masquer le clavier ») montre la fin du carnet d'avant. Aucun texte tapé, rien ne quitte l'iPhone tout seul.
//
// Un fichier et non les préférences : une écriture dans les préférences n'est pas garantie si le clavier est tué
// dans la seconde, alors qu'une ligne écrite dans un fichier lui survit.

/// Le fichier ouvert du carnet, et la place pour la pile d'appels : globaux, parce qu'un gestionnaire de signal ne
/// peut rien capturer ni allouer.
private var kbCrashFD: Int32 = -1
private var kbCrashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

/// Le clavier plante (accès mémoire, piège de Swift, abandon) : on note le signal et la pile, puis on laisse iOS
/// faire son rapport comme d'habitude.
private func kbCrashSignal(_ sig: Int32) {
    let fd = kbCrashFD
    if fd >= 0 {
        // « signal NN\n », sans allocation.
        var line: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (115, 105, 103, 110, 97, 108, 32, UInt8(48 + (sig / 10) % 10), UInt8(48 + sig % 10), 10)
        withUnsafeBytes(of: &line) { _ = write(fd, $0.baseAddress, 10) }
        if let frames = kbCrashFrames {
            let n = backtrace(frames, 40)
            backtrace_symbols_fd(frames, n, fd)
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

enum KBCrashNote {
    /// La fin du carnet de la fois d'avant (le clavier a redémarré depuis) : vide si rien à signaler.
    private(set) static var previous = ""
    private static var installed = false
    private static var written = 0
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd/MM HH:mm:ss.SSS"
        return f
    }()

    private static var path: String {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("foldboard-etapes.txt")
    }

    /// Une fois par démarrage du clavier : on garde la fin du carnet précédent, puis on repart d'un carnet vide.
    static func install() {
        guard !installed else { return }
        installed = true
        if let data = FileManager.default.contents(atPath: path), !data.isEmpty {
            let text = String(decoding: data.suffix(2600), as: UTF8.self)
            previous = text.split(separator: "\n").suffix(22).map { String($0.prefix(170)) }.joined(separator: "\n")
        }
        kbCrashFD = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o600)
        kbCrashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 40)
        kbCrashFrames?.initialize(repeating: nil, count: 40)
        NSSetUncaughtExceptionHandler { e in
            KBCrashNote.step("exception \(e.name.rawValue) : \(e.reason ?? "")")
            KBCrashNote.step(e.callStackSymbols.prefix(16).joined(separator: "\n"))
        }
        for sig in [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] { signal(sig, kbCrashSignal) }
        step("démarrage")
    }

    /// Un repère, écrit tout de suite. Le carnet repart de zéro quand il devient long (un seul démarrage peut durer
    /// des jours).
    static func step(_ what: String) {
        guard kbCrashFD >= 0 else { return }
        if written > 24_000 {
            ftruncate(kbCrashFD, 0)
            written = 0
        }
        let line = clock.string(from: Date()) + " " + what + "\n"
        let bytes = Array(line.utf8)
        written += bytes.count
        bytes.withUnsafeBufferPointer { _ = write(kbCrashFD, $0.baseAddress, $0.count) }
    }
}
