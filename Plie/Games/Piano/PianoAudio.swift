import AVFoundation
import Foundation

/// Piano à faible latence : une note = un échantillon (do 3 à do 6) joué par l'une des 16 voix.
///
/// Le moteur audio peut s'arrêter tout seul (appel, Siri, changement de sortie audio, réglages de
/// la session). On ne joue donc une note que si le moteur tourne vraiment : jouer sur un moteur
/// arrêté fait planter l'app.
final class PianoSynth {
    static let shared = PianoSynth()
    static let range = 48...84

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var voices: [AVAudioPlayerNode] = []
    private var voiceNote: [Int?] = []
    private var voiceStarted: [Date] = []
    /// Fondu de chaque voix relâchée : volume de départ et moment du relâchement.
    private var fades: [Int: (start: Float, at: Date)] = [:]
    private var fadeTimer: Timer?
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private(set) var ready = false
    private var loading = false
    private var wired = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.recover()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.recover() }
        })
    }

    /// Charge les échantillons et démarre le moteur audio (en arrière-plan la première fois).
    func prepare() {
        if ready {
            _ = ensureRunning()
            return
        }
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded: [Int: AVAudioPCMBuffer] = [:]
            for midi in Self.range {
                guard let url = Bundle.main.url(forResource: "piano\(midi)", withExtension: "m4a"),
                      let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
                else { continue }
                try? file.read(into: buffer)
                loaded[midi] = buffer
            }
            DispatchQueue.main.async {
                self.buffers = loaded
                self.setUpEngine()
                self.loading = false
            }
        }
    }

    private func setUpEngine() {
        guard let format = buffers.values.first?.format else { return }
        if !wired {
            engine.attach(mixer)
            engine.attach(reverb)
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = 16
            for _ in 0..<16 {
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: mixer, format: format)
                voices.append(node)
                voiceNote.append(nil)
                voiceStarted.append(.distantPast)
            }
            engine.connect(mixer, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.9
            engine.prepare()
            wired = true
        }
        // Même si le démarrage échoue maintenant, on réessaiera à la première note.
        ensureRunning()
        ready = true
    }

    /// Le moteur tourne-t-il ? Sinon, on essaie de le relancer.
    @discardableResult
    private func ensureRunning() -> Bool {
        guard wired else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
        } catch {
            return false
        }
        return engine.isRunning
    }

    /// Après une coupure (appel, changement de sortie audio) : on oublie les notes en cours et on relance.
    private func recover() {
        guard wired else { return }
        for i in voiceNote.indices { voiceNote[i] = nil }
        fades = [:]
        ensureRunning()
    }

    func stop() {
        guard wired else { return }
        if engine.isRunning {
            for v in voices { v.stop() }
        }
        fades = [:]
        fadeTimer?.invalidate()
        fadeTimer = nil
        voiceNote = voiceNote.map { _ in nil }
        if engine.isRunning { engine.pause() }
    }

    func noteOn(_ midi: Int, velocity: Float = 0.9) {
        guard wired, let buffer = buffers[midi], ensureRunning() else { return }
        // Voix libre, sinon la plus ancienne.
        var index = voiceNote.firstIndex(where: { $0 == nil }) ?? 0
        if voiceNote[index] != nil {
            index = voiceStarted.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
        }
        fades[index] = nil
        let node = voices[index]
        node.stop()
        node.volume = velocity
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        guard engine.isRunning else { return }
        node.play()
        voiceNote[index] = midi
        voiceStarted[index] = Date()
    }

    /// Relâche la touche : la note s'éteint en douceur (0,3 s).
    func noteOff(_ midi: Int) {
        guard wired else { return }
        for (index, note) in voiceNote.enumerated() where note == midi && fades[index] == nil {
            fades[index] = (voices[index].volume, Date())
        }
        if !fades.isEmpty && fadeTimer == nil {
            let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.stepFades() }
            RunLoop.main.add(timer, forMode: .common)
            fadeTimer = timer
        }
    }

    private func stepFades() {
        let now = Date()
        for (index, fade) in fades {
            let k = Float(now.timeIntervalSince(fade.at) / 0.3)
            let node = voices[index]
            if k >= 1 {
                if engine.isRunning { node.stop() }
                node.volume = 0
                fades[index] = nil
                voiceNote[index] = nil
            } else {
                node.volume = fade.start * (1 - k)
            }
        }
        if fades.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }
}
