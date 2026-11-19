import AVFoundation
import Speech

/// Le moteur de dictée d'iOS 26 (SpeechAnalyzer + SpeechTranscriber) : plus rapide et plus juste que l'ancien
/// SFSpeechRecognizer, ponctuation comprise, tout sur l'iPhone. L'ancien reste en secours (iOS 17 à 25, langue
/// absente, échec).
@available(iOS 26.0, *)
final class ModernDictation {
    /// La langue et le format audio attendu, une fois le modèle de la langue présent sur l'iPhone.
    struct Ready { let locale: Locale; let format: AVAudioFormat }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Prépare la langue : télécharge son modèle si iOS ne l'a pas encore (une seule fois, partagé avec le système).
    static func prepare(localeID: String) async -> Ready? {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else { return nil }
        let t = makeTranscriber(locale)
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
        } catch { return nil }
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { return nil }
        return Ready(locale: locale, format: fmt)
    }

    private let ready: Ready
    private var analyzer: SpeechAnalyzer?
    private var cont: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var results: Task<Void, Never>?
    private let lock = NSLock()

    init(_ ready: Ready) { self.ready = ready }

    /// Démarre ; `onText(texte, final)` est appelé à chaque mot entendu, puis une dernière fois avec `final`.
    func start(onText: @escaping @Sendable (String, Bool) -> Void) async throws {
        let t = Self.makeTranscriber(ready.locale)
        let a = SpeechAnalyzer(modules: [t])
        let (stream, c) = AsyncStream<AnalyzerInput>.makeStream()
        lock.lock(); cont = c; analyzer = a; lock.unlock()
        results = Task {
            var done = ""
            do {
                for try await r in t.results {
                    let piece = String(r.text.characters)
                    if r.isFinal { done = Self.join(done, piece); onText(done, false) }
                    else { onText(Self.join(done, piece), false) }
                }
            } catch {}
            onText(done.trimmingCharacters(in: .whitespaces), true)
        }
        try await a.start(inputSequence: stream)
    }

    static func join(_ a: String, _ b: String) -> String {
        guard !a.isEmpty else { return b.trimmingCharacters(in: .whitespaces) }
        if a.hasSuffix(" ") || b.hasPrefix(" ") || b.isEmpty { return a + b }
        return a + " " + b
    }

    /// Un morceau de son du micro (appelé sur le fil audio), converti au format du modèle.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let cont else { return }
        let fmt = ready.format
        if buffer.format == fmt { cont.yield(AnalyzerInput(buffer: buffer)); return }
        if converter == nil || converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: fmt) }
        guard let converter else { return }
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * fmt.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return buffer
        }
        if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
    }

    /// Fin de la parole : le modèle termine ce qu'il a entendu, puis `onText(…, true)`.
    func finish() async {
        lock.lock(); let c = cont, a = analyzer; cont = nil; lock.unlock()
        c?.finish()
        try? await a?.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() {
        lock.lock(); let c = cont, a = analyzer; cont = nil; lock.unlock()
        c?.finish()
        results?.cancel()
        Task { await a?.cancelAndFinishNow() }
    }
}
