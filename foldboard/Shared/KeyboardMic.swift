// KeyboardMic.swift — Foldboard
//
// La dictée directement dans le clavier : le son vient de WebAudioCapture (WebKit tient le micro), la reconnaissance
// est celle d'Apple, sur l'iPhone. Plus besoin d'ouvrir l'app Foldboard pour dicter : il suffit que le micro et la
// reconnaissance vocale aient été permis une fois dans l'app, et que l'accès complet soit activé.
// Elle s'arrête toute seule 2,5 s après la dernière parole (8 s si rien n'est dit).

import AVFoundation
import Speech
import UIKit

@MainActor
final class KeyboardMic {
    /// Le texte entendu (final : la dictée est finie).
    var onText: ((String, Bool) -> Void)?
    /// Le niveau de la voix, de 0 à 1.
    var onLevel: ((Float) -> Void)?
    /// La dictée n'a pas pu se faire dans le clavier (le clavier se rabat sur l'app).
    var onFail: ((String) -> Void)?

    private let capture = WebAudioCapture()
    private var attached = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: WebAudioCapture.sampleRate,
                                       channels: 1, interleaved: true)!
    private var text = ""
    private var running = false
    private var finished = false
    private var pendingStart = false
    private var startedAt = Date()
    private var lastVoice = Date.distantPast
    private var watch: Timer?
    private var finalTimer: Timer?

    /// Tout est là pour dicter dans le clavier.
    static func canUse(fullAccess: Bool) -> Bool {
        fullAccess
            && AVAudioApplication.shared.recordPermission == .granted
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    init() {
        capture.onReady = { [weak self] in
            guard let self, self.pendingStart else { return }
            self.pendingStart = false
            self.capture.start()
        }
        capture.onAudio = { [weak self] data, rms in self?.append(data, rms: rms) }
        capture.onEnded = { [weak self] reason in self?.captureEnded(reason) }
    }

    /// La page cachée doit être dans la fenêtre du clavier.
    func attach(to view: UIView) {
        guard !attached else { return }
        attached = true
        capture.attach(to: view)
    }

    func start(localeID: String) {
        guard !running else { return }
        let r = SFSpeechRecognizer(locale: Locale(identifier: localeID)) ?? SFSpeechRecognizer()
        guard let r, r.isAvailable else {
            onFail?("speech unavailable")
            return
        }
        recognizer = r
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        text = ""
        merger = KBTranscriptMerger()
        finished = false
        running = true
        startedAt = Date()
        lastVoice = .distantPast
        task = r.recognitionTask(with: req) { [weak self] result, error in
            let t = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async { self?.recognized(t, final: isFinal, failed: failed) }
        }
        if capture.isReady { capture.start() } else { pendingStart = true }
        // Arrêt tout seul : 2,5 s après la dernière parole, 8 s si rien n'est dit.
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                let now = Date()
                let spoke = self.lastVoice > self.startedAt
                if spoke && now.timeIntervalSince(self.lastVoice) > 4.5 { self.stop() }
                else if !spoke && now.timeIntervalSince(self.startedAt) > 8 { self.stop() }
                // Le micro n'a jamais démarré : on laisse la main à l'app.
                else if !self.capture.isCapturing && !self.pendingStart && now.timeIntervalSince(self.startedAt) > 3 && self.text.isEmpty {
                    self.fail("capture didn't start")
                }
            }
        }
    }

    /// Fin de la dictée : le texte final arrive juste après.
    func stop() {
        guard running else { return }
        running = false
        pendingStart = false
        watch?.invalidate()
        capture.stop()
        request?.endAudio()
        finalTimer?.invalidate()
        finalTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverFinal() }
        }
    }

    /// Annuler : rien n'est rendu.
    func cancel() {
        running = false
        pendingStart = false
        finished = true
        watch?.invalidate()
        finalTimer?.invalidate()
        capture.stop()
        task?.cancel()
        task = nil
        request = nil
    }

    func tearDown() {
        cancel()
        capture.tearDown()
        attached = false
    }

    private func append(_ data: Data, rms: Float) {
        guard running else { return }
        if rms > 0.02 { lastVoice = Date() }
        onLevel?(min(1, rms * 8))
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0, let request, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            if let src = raw.bindMemory(to: Int16.self).baseAddress {
                buffer.int16ChannelData![0].update(from: src, count: Int(frames))
            }
        }
        request.append(buffer)
    }

    private var merger = KBTranscriptMerger()

    private func recognized(_ t: String?, final: Bool, failed: Bool) {
        guard !finished else { return }
        if let raw = t, !raw.isEmpty {
            let t = merger.merge(raw)
            text = t
            if !final { onText?(t, false) }
        }
        if final { deliverFinal() }
        else if failed {
            // Rien entendu et la reconnaissance a échoué : l'app prend le relais.
            if text.isEmpty && running { fail("speech error") } else if !running { deliverFinal() }
        }
    }

    private func captureEnded(_ reason: String) {
        // Le micro s'est coupé tout seul (appel, autre app) : on finit avec ce qui a été entendu.
        if running {
            if reason.hasPrefix("failed") && text.isEmpty {
                fail(reason)
            } else {
                stop()
            }
        }
    }

    private func deliverFinal() {
        guard !finished else { return }
        finished = true
        finalTimer?.invalidate()
        task = nil
        request = nil
        onText?(text, true)
    }

    private func fail(_ reason: String) {
        guard !finished else { return }
        cancel()
        onFail?(reason)
    }
}
