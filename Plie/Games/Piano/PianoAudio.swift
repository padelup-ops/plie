import AVFoundation
import Foundation

/// Piano à faible latence : une note = un échantillon (do 3 à do 6) joué par l'une des 16 voix.
final class PianoSynth {
    static let shared = PianoSynth()
    static let range = 48...84

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var voices: [AVAudioPlayerNode] = []
    private var voiceNote: [Int?] = []
    private var voiceStarted: [Date] = []
    private var fades: [Int: Timer] = [:]
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private(set) var ready = false
    private var loading = false

    private init() {}

    /// Charge les échantillons et démarre le moteur audio (en arrière-plan la première fois).
    func prepare() {
        if ready {
            if !engine.isRunning { try? engine.start() }
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
        do {
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    func stop() {
        for v in voices { v.stop() }
        for t in fades.values { t.invalidate() }
        fades = [:]
        voiceNote = voiceNote.map { _ in nil }
        if engine.isRunning { engine.pause() }
    }

    func noteOn(_ midi: Int, velocity: Float = 0.9) {
        guard ready, let buffer = buffers[midi] else { return }
        if !engine.isRunning { try? engine.start() }
        // Voix libre, sinon la plus ancienne.
        var index = voiceNote.firstIndex(where: { $0 == nil }) ?? 0
        if voiceNote[index] != nil {
            index = voiceStarted.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
        }
        fades[index]?.invalidate()
        fades[index] = nil
        let node = voices[index]
        node.stop()
        node.volume = velocity
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
        voiceNote[index] = midi
        voiceStarted[index] = Date()
    }

    /// Relâche la touche : la note s'éteint en douceur.
    func noteOff(_ midi: Int) {
        for (index, note) in voiceNote.enumerated() where note == midi && fades[index] == nil {
            let node = voices[index]
            let start = node.volume
            var step = 0
            fades[index] = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] timer in
                step += 1
                node.volume = start * max(0, 1 - Float(step) / 12)
                if step >= 12 {
                    timer.invalidate()
                    node.stop()
                    self?.fades[index] = nil
                    if self?.voiceNote[index] == midi { self?.voiceNote[index] = nil }
                }
            }
        }
    }
}
