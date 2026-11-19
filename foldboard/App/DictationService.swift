import AVFoundation
import Speech
import SwiftUI
import UIKit

/// La dictée côté app : le micro ouvert pour le clavier (qui n'y a pas droit), et la transcription sur l'iPhone.
/// L'app reste prête en arrière-plan quelques minutes ; le clavier lui demande de commencer et d'arrêter.
/// Discrète : en attente, l'app reste éveillée avec un son muet, sans micro (pas de point orange d'iOS) ; le micro
/// ne s'ouvre que pendant la dictée. Si iOS refuse de l'ouvrir en arrière-plan, l'app revient au premier plan une
/// fois et garde alors le micro ouvert pour la session (comme avant).
@Observable
final class DictationService {
    static let shared = DictationService()

    enum Status: Equatable { case off, starting, ready, listening, denied, unavailable }
    var status: Status = .off
    var heard = ""
    var endsAt: Date?

    private let engine = AVAudioEngine()
    /// Le son muet qui garde l'app prête en arrière-plan (sortie seulement : le micro reste fermé).
    private let keepAlive = AVAudioEngine()
    private let silence = AVAudioPlayerNode()
    private var keepAliveRunning = false
    /// iOS a refusé d'ouvrir le micro en arrière-plan : il reste ouvert pendant la session.
    private var micAlwaysOn = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var seq = 0
    private var idleTimer: Timer?
    private var finishTimer: Timer?
    private var engineRunning = false
    /// Le niveau de la voix (0 à 1), envoyé au clavier une dizaine de fois par seconde pendant la dictée.
    private var level: Float = 0
    private var levelTimer: Timer?
    /// Le nouveau moteur d'iOS 26, prêt pour la langue (nil : l'ancien moteur).
    private var modernReady: AnyObject?
    private var modern: AnyObject?
    /// Le son du micro va aussi au nouveau moteur pendant la dictée.
    private var modernSink: ((AVAudioPCMBuffer) -> Void)?
    /// Arrêt tout seul quand on se tait : le dernier moment où la voix a été entendue.
    private var lastVoice = Date()
    private var startedAt = Date()

    private init() {
        // Quand le micro s'ouvre ou se ferme, iOS reconfigure l'audio et arrête le son muet : on le relance tout de
        // suite, sinon l'app s'endort en arrière-plan et le clavier doit la rouvrir à chaque dictée.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: keepAlive, queue: .main) { [weak self] _ in
            self?.ensureKeepAlive()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.status == .ready || self.status == .listening,
                  let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            self.ensureKeepAlive()
        }
    }

    /// Le son muet doit tourner tant que la dictée est prête.
    private func ensureKeepAlive() {
        guard status == .ready || status == .listening else { return }
        if keepAliveRunning, !keepAlive.isRunning { keepAliveRunning = false }
        if !keepAliveRunning { try? startKeepAlive() }
    }

    /// Ouvre le micro et prépare la reconnaissance (l'app est au premier plan : iOS demande les autorisations).
    func startSession() {
        listen()
        if status == .ready || status == .listening {
            if micAlwaysOn, !engineRunning { try? startMic() }
            touch()
            return
        }
        status = .starting
        SFSpeechRecognizer.requestAuthorization { auth in
            AVAudioApplication.requestRecordPermission { mic in
                DispatchQueue.main.async { self.prepare(speech: auth == .authorized, mic: mic) }
            }
        }
    }

    private func prepare(speech: Bool, mic: Bool) {
        guard mic else { status = .denied; return }
        let r = SFSpeechRecognizer(locale: Locale(identifier: Self.localeID()))
        recognizer = speech && r?.supportsOnDeviceRecognition == true ? r : nil
        // Le nouveau moteur se prépare en parallèle (téléchargement du modèle de la langue la première fois).
        if #available(iOS 26.0, *) {
            let id = Self.localeID()
            Task { [weak self] in
                let ready = await ModernDictation.prepare(localeID: id)
                await MainActor.run {
                    guard let self else { return }
                    self.modernReady = ready.map { Box($0) }
                    if self.status == .unavailable, ready != nil { try? self.startEngine(); self.status = .ready; self.touch() }
                }
            }
        }
        guard recognizer != nil || !speech else { status = .unavailable; return }
        if recognizer == nil { status = .denied; return }
        do {
            try startEngine()
        } catch {
            status = .unavailable
            return
        }
        status = .ready
        touch()
    }

    /// La langue de la dictée : celle de la disposition du clavier.
    static func localeID() -> String {
        switch KBVault.loadSettings().layout {
        case .azerty: return "fr-FR"
        case .qwertz: return "de-DE"
        case .spanish: return "es-ES"
        case .swedish: return "sv-SE"
        case .qwerty: return Locale.current.language.languageCode?.identifier == "en" ? Locale.current.identifier : "en-US"
        }
    }

    private func startEngine() throws {
        let s = AVAudioSession.sharedInstance()
        // La musique continue pendant que la dictée est prête.
        try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try s.setActive(true)
        try startKeepAlive()
        if micAlwaysOn { try startMic() }
    }

    private func startKeepAlive() throws {
        guard !keepAliveRunning else { return }
        silence.stop()
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44_100) else { return }
        buf.frameLength = 44_100
        if let ch = buf.floatChannelData { ch[0].update(repeating: 0, count: Int(buf.frameLength)) }
        if silence.engine == nil { keepAlive.attach(silence) }
        keepAlive.connect(silence, to: keepAlive.mainMixerNode, format: fmt)
        keepAlive.prepare()
        try keepAlive.start()
        silence.scheduleBuffer(buf, at: nil, options: .loops)
        silence.play()
        keepAliveRunning = true
    }

    private func stopKeepAlive() {
        guard keepAliveRunning else { return }
        silence.stop()
        keepAlive.stop()
        keepAliveRunning = false
    }

    private struct MicUnavailable: Error {}

    /// Le micro, seulement pendant la dictée.
    private func startMic() throws {
        guard !engineRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // En arrière-plan, iOS peut ne donner aucun micro (format vide) : on ne l'installe pas.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicUnavailable() }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // Le niveau de la voix, pour les barres du panneau dans le clavier.
            var lvl: Float = 0
            let n = Int(buffer.frameLength)
            if let ch = buffer.floatChannelData?[0], n > 0 {
                var sum: Float = 0
                var k = 0
                while k < n { sum += ch[k] * ch[k]; k += 4 }
                lvl = min(1, sqrt(sum / Float(max(1, n / 4))) * 14)
            }
            self.lock.lock()
            let r = self.request
            let sink = self.modernSink
            self.level = max(lvl, self.level * 0.6)
            self.lock.unlock()
            r?.append(buffer)
            sink?(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        engineRunning = true
    }

    private func stopMic() {
        guard engineRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineRunning = false
    }

    /// Ferme le micro (fin de la session, ou « Arrêter la dictée »).
    func stopSession() {
        endRecognition()
        idleTimer?.invalidate()
        idleTimer = nil
        stopMic()
        stopKeepAlive()
        micAlwaysOn = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = .off
        endsAt = nil
    }

    /// Les demandes du clavier.
    private func listen() {
        KBDictation.observe(KBDictation.ping) { [weak self] in
            guard let self, self.status == .ready || self.status == .listening else { return }
            self.touch()
            KBDictation.post(KBDictation.pong)
        }
        KBDictation.observe(KBDictation.start) { [weak self] in self?.beginRecognition() }
        KBDictation.observe(KBDictation.stop) { [weak self] in self?.endRecognition() }
    }

    private func beginRecognition() {
        guard status == .ready || status == .listening, recognizer != nil || modernReady != nil else { return }
        ensureKeepAlive()
        do {
            try startMic()
            ensureKeepAlive()
        } catch {
            // iOS n'ouvre pas le micro en arrière-plan : le clavier ramène l'app une fois au premier plan, et le micro
            // restera ouvert pour cette session.
            micAlwaysOn = true
            KBDictation.post(KBDictation.needApp)
            return
        }
        task?.cancel()
        if #available(iOS 26.0, *), let box = modernReady as? Box<ModernDictation.Ready> {
            beginModern(box.value)
            return
        }
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.addsPunctuation = true
        lock.lock()
        request = req
        lock.unlock()
        seq += 1
        let mine = seq
        heard = ""
        status = .listening
        save("", final: false, seq: mine)
        startLevelTimer(mine)
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let t = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.heard = t }
                self.save(t, final: result.isFinal, seq: mine)
            }
            if result?.isFinal == true || error != nil {
                DispatchQueue.main.async {
                    if error != nil && result?.isFinal != true { self.save(self.heard, final: true, seq: mine) }
                    self.finishRecognition()
                }
            }
        }
        touch()
    }

    /// Le niveau de la voix vers le clavier, et l'arrêt tout seul quand on se tait (2,5 s après la dernière parole,
    /// ou 8 s si rien n'a été dit).
    private func startLevelTimer(_ mine: Int) {
        lastVoice = Date(); startedAt = Date()
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.status == .listening, self.seq == mine else { return }
            self.lock.lock(); let l = self.level; self.lock.unlock()
            if l > 0.12 { self.lastVoice = Date() }
            self.save(self.heard, final: false, seq: mine)
            let quiet = Date().timeIntervalSince(self.lastVoice)
            let said = !self.heard.trimmingCharacters(in: .whitespaces).isEmpty
            if self.finishTimer == nil || self.finishTimer?.isValid == false,
               (said && quiet > 2.5) || (!said && Date().timeIntervalSince(self.startedAt) > 8) {
                self.endRecognition()
            }
        }
    }

    @available(iOS 26.0, *)
    private func beginModern(_ ready: ModernDictation.Ready) {
        let m = ModernDictation(ready)
        modern = m
        lock.lock(); modernSink = { [weak m] b in m?.append(b) }; lock.unlock()
        seq += 1
        let mine = seq
        heard = ""
        status = .listening
        save("", final: false, seq: mine)
        startLevelTimer(mine)
        Task { [weak self] in
            do {
                try await m.start { text, final in
                    DispatchQueue.main.async {
                        guard let self, self.seq == mine else { return }
                        if !final { self.heard = text; self.save(text, final: false, seq: mine); return }
                        guard self.status == .listening else { return }
                        self.save(text.isEmpty ? self.heard : text, final: true, seq: mine)
                        self.finishRecognition()
                    }
                }
            } catch {
                // Le nouveau moteur refuse : l'ancien prend le relais pour les dictées suivantes.
                DispatchQueue.main.async {
                    guard let self, self.seq == mine else { return }
                    self.modernReady = nil
                    self.save(self.heard, final: true, seq: mine)
                    self.finishRecognition()
                }
            }
        }
        touch()
    }

    private func endRecognition() {
        lock.lock()
        let r = request
        lock.unlock()
        if #available(iOS 26.0, *), let m = modern as? ModernDictation {
            Task { await m.finish() }
        } else {
            guard let r else { return }
            r.endAudio()
        }
        // Le dernier résultat arrive d'habitude tout de suite ; sinon on rend ce qui a été entendu.
        finishTimer?.invalidate()
        let mine = seq
        finishTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, self.status == .listening, self.seq == mine else { return }
            self.save(self.heard, final: true, seq: mine)
            self.finishRecognition()
        }
    }

    private func finishRecognition() {
        levelTimer?.invalidate()
        levelTimer = nil
        lock.lock()
        request = nil
        modernSink = nil
        level = 0
        lock.unlock()
        modern = nil
        task = nil
        finishTimer?.invalidate()
        if status == .listening { status = .ready }
        // Le micro se referme dès la fin de la dictée (le point orange d'iOS disparaît).
        if !micAlwaysOn { stopMic() }
        ensureKeepAlive()
        touch()
    }

    private func save(_ text: String, final: Bool, seq: Int) {
        lock.lock()
        let l = level
        lock.unlock()
        KBVault.saveDictation(KBDictation.State(text: text, final: final, seq: seq, level: final ? 0 : l))
        KBDictation.post(KBDictation.update)
    }

    /// Encore quelques minutes de session après chaque usage, puis le micro se ferme tout seul.
    private func touch() {
        guard status == .ready || status == .listening else { return }
        endsAt = Date().addingTimeInterval(KBDictation.sessionMinutes * 60)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: KBDictation.sessionMinutes * 60, repeats: false) { [weak self] _ in
            guard let self, self.status != .listening else { return }
            self.stopSession()
        }
    }
}

/// Une valeur rangée dans un objet (pour garder un type d'iOS 26 dans une propriété disponible dès iOS 17).
final class Box<T> { let value: T; init(_ v: T) { value = v } }

/// L'écran qui s'ouvre quand le clavier demande la dictée : on autorise, puis on revient à son app.
struct DictationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let service = DictationService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if service.status == .ready || service.status == .listening {
                    // La flèche vers « ◀ app » d'iOS, en haut à gauche : le chemin du retour.
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left").symbolEffect(.pulse)
                        Text("Back to your app")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(service.status == .ready || service.status == .listening ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, isActive: service.status == .listening)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if service.status == .listening, !service.heard.isEmpty {
                    Text(service.heard)
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                }
                if service.status == .denied {
                    Button("Open Settings") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Label("Your voice is transcribed on your iPhone. Nothing is sent or kept.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if service.status == .ready || service.status == .listening {
                    Button("Stop dictation", role: .destructive) {
                        service.stopSession()
                        dismiss()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var icon: String {
        switch service.status {
        case .denied, .unavailable: return "mic.slash"
        default: return "mic.fill"
        }
    }

    private var title: LocalizedStringKey {
        switch service.status {
        case .off, .starting: return "Turning on dictation…"
        case .ready, .listening: return "Dictation is ready"
        case .denied: return "Foldboard needs the microphone"
        case .unavailable: return "Dictation isn't available"
        }
    }

    private var detail: LocalizedStringKey {
        switch service.status {
        case .off, .starting: return "Allow the microphone and speech recognition when iOS asks."
        case .ready, .listening: return "Go back to your app (top left): Foldboard starts listening right away. Dictation stays ready for 10 minutes, then turns off by itself."
        case .denied: return "Allow the microphone and speech recognition for Foldboard in Settings."
        case .unavailable: return "On-device dictation isn't available for this language on your iPhone."
        }
    }
}
