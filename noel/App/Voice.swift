// Voice.swift — Allô Père Noël
//
// La voix du Père Noël et les sons, sans internet :
//  - la voix : la synthèse vocale d'iOS (la meilleure voix masculine installée dans la langue), rendue d'avance en
//    sons, puis passée dans une chaîne d'effets (voix plus grave, un peu de chaleur, une pièce en bois) ;
//  - la bouche du dessin suit le volume réel de la voix ;
//  - la sonnerie, l'ambiance de l'atelier (feu + « Douce nuit ») et l'étincelle de la surprise sont des fichiers de l'app.
// Des enregistrements de comédien pourront remplacer la synthèse plus tard (VoiceSource) sans toucher au reste.

import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class SantaVoice {
    /// Ouverture de la bouche (0…1), lissée.
    private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private let speech = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    private let music = AVAudioPlayerNode()
    private let fx = AVAudioPlayerNode()
    private let synth = AVSpeechSynthesizer()
    // stéréo : les effets (réverbération) le préfèrent ; la synthèse, en mono, y est convertie.
    private let speechFormat = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 2)!
    private var musicFormat: AVAudioFormat?
    private var ready = false
    private var voice: AVSpeechSynthesisVoice?
    private var rate: Float = 0.45
    private var pitchMultiplier: Float = 0.85

    init() {}

    /// La meilleure voix d'homme installée pour la langue (Premium > Améliorée > Standard).
    func configure(book: ScriptBook) {
        let region = Locale.current.region?.identifier
        var langs = book.voices
        if let r = region, let base = book.voices.first?.prefix(2) {
            langs.insert("\(base)-\(r)", at: 0)
        }
        let all = AVSpeechSynthesisVoice.speechVoices()
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality { case .premium: s += 300; case .enhanced: s += 200; default: s += 100 }
            if v.gender == .male { s += 60 }
            if let i = langs.firstIndex(of: v.language) { s += 40 - i * 5 }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 1000 }
            return s
        }
        let candidates = all.filter { v in langs.contains(where: { $0 == v.language }) || v.language.hasPrefix(String(book.voices.first?.prefix(2) ?? "en")) }
        voice = candidates.max(by: { score($0) < score($1) }) ?? AVSpeechSynthesisVoice(language: book.voices.first)
        rate = book.rate
        pitchMultiplier = book.pitch
    }

    var voiceName: String { voice?.name ?? "—" }
    var voiceIsBasic: Bool { (voice?.quality ?? .default) == .default }

    private func start() {
        guard !ready else { return }
        let session = AVAudioSession.sharedInstance()
        // .playback : l'appel s'entend même si l'iPhone est en mode silencieux.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        for n in [speech, music, fx] as [AVAudioNode] { engine.attach(n) }
        engine.attach(pitch); engine.attach(eq); engine.attach(reverb)
        pitch.pitch = -180          // un peu plus grave
        pitch.rate = 1.0
        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 220; eq.bands[0].gain = 3.5; eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 3200; eq.bands[1].bandwidth = 1.2; eq.bands[1].gain = -2; eq.bands[1].bypass = false
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 14
        engine.connect(speech, to: pitch, format: speechFormat)
        engine.connect(pitch, to: eq, format: speechFormat)
        engine.connect(eq, to: reverb, format: speechFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: speechFormat)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        musicFormat = stereo
        engine.connect(music, to: engine.mainMixerNode, format: stereo)
        engine.connect(fx, to: engine.mainMixerNode, format: stereo)
        speech.installTap(onBus: 0, bufferSize: 1024, format: speechFormat) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = Double(sqrt(sum / Float(max(1, n))))
            let v = min(1, rms * 7)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = self.level * 0.45 + v * 0.55
            }
        }
        engine.prepare()
        try? engine.start()
        ready = true
    }

    // MARK: Voix

    /// Rend une phrase en sons (avant l'appel : aucune attente pendant l'appel).
    func render(_ text: String) async -> [AVAudioPCMBuffer] {
        start()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = rate
        u.pitchMultiplier = pitchMultiplier
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        let target = speechFormat
        return await withCheckedContinuation { (cont: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
            let box = RenderBox(cont)
            synth.write(u) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { box.finish(); return }
                if let c = Self.convert(pcm, to: target) { box.add(c) }
            }
            // Filet de sécurité : certaines versions d'iOS n'envoient pas le dernier tampon vide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { box.finish() }
        }
    }

    nonisolated private static func convert(_ src: AVAudioPCMBuffer, to dst: AVAudioFormat) -> AVAudioPCMBuffer? {
        if src.format == dst, let copy = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: src.frameLength) {
            copy.frameLength = src.frameLength
            for c in 0..<Int(dst.channelCount) {
                if let s = src.floatChannelData?[c], let d = copy.floatChannelData?[c] { d.update(from: s, count: Int(src.frameLength)) }
            }
            return copy
        }
        guard let conv = AVAudioConverter(from: src.format, to: dst) else { return nil }
        let ratio = dst.sampleRate / src.format.sampleRate
        let cap = AVAudioFrameCount(Double(src.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return src
        }
        return err == nil && out.frameLength > 0 ? out : nil
    }

    /// Joue les sons d'une phrase et attend la fin.
    func play(_ buffers: [AVAudioPCMBuffer]) async {
        start()
        guard !buffers.isEmpty else { return }
        if !speech.isPlaying { speech.play() }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            for (i, b) in buffers.enumerated() {
                if i == buffers.count - 1 {
                    speech.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in cont.resume() }
                } else {
                    speech.scheduleBuffer(b)
                }
            }
        }
        level = 0
    }

    func stopSpeech() {
        speech.stop()
        level = 0
    }

    // MARK: Sons de l'app

    private func file(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"), let f = try? AVAudioFile(forReading: url),
              let fmt = musicFormat else { return nil }
        guard let raw = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return nil }
        try? f.read(into: raw)
        if f.processingFormat == fmt { return raw }
        return Self.convert(raw, to: fmt) ?? raw
    }

    func ring() {
        start()
        guard let b = file("ringtone") else { return }
        fx.stop()
        fx.volume = 0.9
        fx.scheduleBuffer(b, at: nil, options: .loops)
        fx.play()
    }

    func stopRing() { fx.stop() }

    func ambience(on: Bool) {
        start()
        music.stop()
        guard on, let b = file("music-call") else { return }
        music.volume = 0.26
        music.scheduleBuffer(b, at: nil, options: .loops)
        music.play()
    }

    func sparkle() {
        start()
        guard let b = file("sparkle") else { return }
        fx.stop()
        fx.volume = 0.8
        fx.scheduleBuffer(b)
        fx.play()
    }

    func stopAll() {
        speech.stop(); music.stop(); fx.stop()
        level = 0
    }
}

/// Rassemble les tampons de la synthèse et ne répond qu'une fois.
private final class RenderBox: @unchecked Sendable {
    private var buffers: [AVAudioPCMBuffer] = []
    private var cont: CheckedContinuation<[AVAudioPCMBuffer], Never>?
    private let lock = NSLock()
    init(_ c: CheckedContinuation<[AVAudioPCMBuffer], Never>) { cont = c }
    func add(_ b: AVAudioPCMBuffer) { lock.lock(); buffers.append(b); lock.unlock() }
    func finish() {
        lock.lock(); let c = cont; cont = nil; let out = buffers; lock.unlock()
        c?.resume(returning: out)
    }
}
