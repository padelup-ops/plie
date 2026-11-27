// Voice.swift — Allô Père Noël
//
// La voix du Père Noël et les sons, sans internet :
//  - le Père Noël : des répliques enregistrées (Resources/Audio/voice/<langue>/…), une voix de dessin animé
//    fabriquée d'avance (Chatterbox, calé sur le Père Noël de Kokoro ; aucune voix de personne réelle, voir
//    tools/voice.py). Chaque phrase fixe a son fichier, chaque prénom de la banque aussi ;
//  - le lutin : ce que le parent a écrit (anecdote, cadeau) et les prénoms plus rares, dits par la synthèse de
//    l'iPhone rendue aiguë et vive. Un autre personnage, donc une autre voix ;
//  - la bouche du Père Noël suit le volume réel de sa voix ;
//  - la sonnerie, l'ambiance de l'atelier (feu + « Douce nuit ») et l'étincelle de la surprise sont des fichiers de l'app.

import AVFoundation
import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class SantaVoice {
    /// Ouverture de la bouche du Père Noël (0…1), lissée.
    private(set) var level: Double = 0
    /// Le lutin est en train de parler (0…1).
    private(set) var elfLevel: Double = 0

    private let engine = AVAudioEngine()
    private let speech = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    private let elf = AVAudioPlayerNode()
    private let elfPitch = AVAudioUnitTimePitch()
    private let elfEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let music = AVAudioPlayerNode()
    private let fx = AVAudioPlayerNode()
    private let synth = AVSpeechSynthesizer()
    // stéréo : les effets (réverbération) le préfèrent ; la synthèse, en mono, y est convertie.
    private let speechFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 2)!
    private var musicFormat: AVAudioFormat?
    private var ready = false
    private var voice: AVSpeechSynthesisVoice?
    private var elfVoice: AVSpeechSynthesisVoice?
    private var rate: Float = 0.45
    private var pitchMultiplier: Float = 0.85
    private var lang = "en"

    init() {}

    /// La langue des répliques, et les voix de l'iPhone pour le lutin (et le secours du Père Noël).
    func configure(book: ScriptBook, lang: String) {
        self.lang = lang
        let region = Locale.current.region?.identifier
        var langs = book.voices
        if let r = region, let base = book.voices.first?.prefix(2) {
            langs.insert("\(base)-\(r)", at: 0)
        }
        let all = AVSpeechSynthesisVoice.speechVoices()
        func score(_ v: AVSpeechSynthesisVoice, male: Bool) -> Int {
            var s = 0
            switch v.quality { case .premium: s += 300; case .enhanced: s += 200; default: s += 100 }
            if (v.gender == .male) == male { s += 60 }
            if let i = langs.firstIndex(of: v.language) { s += 40 - i * 5 }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 1000 }
            // Les vieilles voix de synthèse (« Eloquence ») sonnent comme des robots.
            if v.identifier.lowercased().contains("eloquence") { s -= 500 }
            return s
        }
        let prefix = String(book.voices.first?.prefix(2) ?? "en")
        let candidates = all.filter { v in langs.contains(where: { $0 == v.language }) || v.language.hasPrefix(prefix) }
        voice = candidates.max(by: { score($0, male: true) < score($1, male: true) }) ?? AVSpeechSynthesisVoice(language: book.voices.first)
        // Le lutin lit les mots écrits par le parent : la voix la plus naturelle de la langue, telle quelle.
        elfVoice = candidates.max(by: { score($0, male: false) < score($1, male: false) }) ?? voice
        rate = book.rate
        pitchMultiplier = book.pitch
    }

    private func start() {
        guard !ready else { return }
        let session = AVAudioSession.sharedInstance()
        // .playback : l'appel s'entend même si l'iPhone est en mode silencieux.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        for n in [speech, elf, music, fx] as [AVAudioNode] { engine.attach(n) }
        for n in [pitch, eq, reverb, elfPitch, elfEQ] as [AVAudioNode] { engine.attach(n) }
        pitch.pitch = 0
        pitch.rate = 1.0
        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 220; eq.bands[0].gain = 2.5; eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 3200; eq.bands[1].bandwidth = 1.2; eq.bands[1].gain = -1; eq.bands[1].bypass = false
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 7
        engine.connect(speech, to: pitch, format: speechFormat)
        engine.connect(pitch, to: eq, format: speechFormat)
        engine.connect(eq, to: reverb, format: speechFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: speechFormat)
        // Le lutin : une voix douce et naturelle, sans effet (une voix montée dans les aigus faisait peur).
        elfPitch.pitch = 0
        elfPitch.rate = 1.0
        elfEQ.bands[0].filterType = .highShelf; elfEQ.bands[0].frequency = 3500; elfEQ.bands[0].gain = 0; elfEQ.bands[0].bypass = true
        engine.connect(elf, to: elfPitch, format: speechFormat)
        engine.connect(elfPitch, to: elfEQ, format: speechFormat)
        engine.connect(elfEQ, to: engine.mainMixerNode, format: speechFormat)
        elf.volume = 0.9
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        musicFormat = stereo
        engine.connect(music, to: engine.mainMixerNode, format: stereo)
        engine.connect(fx, to: engine.mainMixerNode, format: stereo)
        speech.installTap(onBus: 0, bufferSize: 1024, format: speechFormat) { [weak self] buf, _ in
            let v = Self.loudness(buf)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = self.level * 0.4 + v * 0.6
            }
        }
        elf.installTap(onBus: 0, bufferSize: 1024, format: speechFormat) { [weak self] buf, _ in
            let v = Self.loudness(buf)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elfLevel = self.elfLevel * 0.4 + v * 0.6
            }
        }
        engine.prepare()
        try? engine.start()
        ready = true
    }

    nonisolated private static func loudness(_ buf: AVAudioPCMBuffer) -> Double {
        guard let ch = buf.floatChannelData?[0] else { return 0 }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = Double(sqrt(sum / Float(max(1, n))))
        return min(1, rms * 7)
    }

    // MARK: Voix

    struct SpokenAudio {
        enum Kind { case recorded, santaDevice, elf }
        var buffers: [AVAudioPCMBuffer]
        var kind: Kind
    }

    /// Une phrase : les fichiers enregistrés s'ils sont tous là, sinon la synthèse de l'iPhone (voix grave) ; le lutin
    /// passe toujours par la synthèse.
    func render(cue: VoiceCue) async -> SpokenAudio {
        start()
        switch cue {
        case let .clips(keys, fallback):
            if let buffers = VoiceLibrary.shared.sequence(keys, lang: lang, format: speechFormat, gap: 0.22) {
                return SpokenAudio(buffers: buffers, kind: .recorded)
            }
            return SpokenAudio(buffers: await synthesize(fallback, elf: false), kind: .santaDevice)
        case let .elf(text):
            return SpokenAudio(buffers: await synthesize(text, elf: true), kind: .elf)
        }
    }

    /// Rend une phrase avec la synthèse de l'iPhone (avant l'appel : aucune attente pendant l'appel).
    private func synthesize(_ text: String, elf: Bool) async -> [AVAudioPCMBuffer] {
        start()
        let u = AVSpeechUtterance(string: text)
        u.voice = elf ? elfVoice : voice
        u.rate = elf ? AVSpeechUtteranceDefaultSpeechRate * 0.94 : rate
        u.pitchMultiplier = elf ? 1.0 : pitchMultiplier
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

    nonisolated fileprivate static func convert(_ src: AVAudioPCMBuffer, to dst: AVAudioFormat) -> AVAudioPCMBuffer? {
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

    /// Joue une phrase et attend la fin.
    func play(_ spoken: SpokenAudio) async {
        start()
        guard !spoken.buffers.isEmpty else { return }
        let node = spoken.kind == .elf ? elf : speech
        if spoken.kind != .elf {
            // La voix enregistrée est déjà celle du Père Noël ; la synthèse de secours est rendue plus grave.
            let device = spoken.kind == .santaDevice
            // (la voix enregistrée est un rien descendue : un Père Noël un peu plus grave, sans la déformer)
            pitch.pitch = device ? -180 : -60
            eq.bands[0].gain = device ? 3.5 : 2.5
            reverb.wetDryMix = device ? 14 : 7
        }
        if !node.isPlaying { node.play() }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            for (i, b) in spoken.buffers.enumerated() {
                if i == spoken.buffers.count - 1 {
                    node.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in cont.resume() }
                } else {
                    node.scheduleBuffer(b)
                }
            }
        }
        if spoken.kind == .elf { elfLevel = 0 } else { level = 0 }
    }

    func stopSpeech() {
        speech.stop()
        elf.stop()
        level = 0
        elfLevel = 0
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
        music.volume = 0.22
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
        speech.stop(); elf.stop(); music.stop(); fx.stop()
        level = 0
        elfLevel = 0
    }
}

/// Les répliques enregistrées. Pas d'index : le nom du fichier est l'empreinte de « langue|clé » (les mêmes clés
/// que tools/voice.py), dans Resources/Audio/voice/<langue>/. Un fichier absent, et l'app le sait tout de suite.
final class VoiceLibrary {
    static let shared = VoiceLibrary()

    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var found: [String: URL?] = [:]
    private var complete: [String: Bool] = [:]
    private let lock = NSLock()

    static func lineKey(_ text: String) -> String { "line|" + text }
    static func helloKey(_ name: String) -> String { "hello|" + normalized(name) }
    static func byeKey(_ name: String) -> String { "bye|" + normalized(name) }

    /// Le prénom tel qu'il est rangé : sans accents, en minuscules, espaces simples (« Léa », « lea », « LÉA »).
    static func normalized(_ name: String) -> String {
        let decomposed = name.decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        for u in decomposed.unicodeScalars where u.properties.generalCategory != .nonspacingMark { out.append(u) }
        return String(out).lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "_" }).joined(separator: " ")
    }

    static func fileName(lang: String, key: String) -> String {
        let digest = SHA256.hash(data: Data((lang + "|" + key).utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(20).description
    }

    func url(lang: String, key: String) -> URL? {
        let name = Self.fileName(lang: lang, key: key)
        let id = lang + "/" + name
        lock.lock(); defer { lock.unlock() }
        // Une langue dont toutes les répliques ne sont pas encore enregistrées garde la voix de l'iPhone du début
        // à la fin (tools/voice.py pose « complet.txt » quand tout y est) : jamais deux voix dans un même appel.
        if complete[lang] == nil {
            complete[lang] = Bundle.main.url(forResource: "complet", withExtension: "txt", subdirectory: "voice/" + lang) != nil
        }
        guard complete[lang] == true else { return nil }
        if let known = found[id] { return known }
        var url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "voice/" + lang)
        if url == nil { url = Bundle.main.url(forResource: name, withExtension: "m4a") }
        found[id] = url
        return url
    }

    /// La voix enregistrée sert-elle dans cette langue (toutes ses répliques y sont) ? Sinon c'est la voix de l'iPhone,
    /// du début à la fin.
    func ready(lang: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if complete[lang] == nil {
            complete[lang] = Bundle.main.url(forResource: "complet", withExtension: "txt", subdirectory: "voice/" + lang) != nil
        }
        return complete[lang] == true
    }

    /// Le Père Noël a-t-il enregistré son bonjour à ce prénom ?
    func knows(name: String, lang: String) -> Bool {
        let n = Self.normalized(name)
        guard !n.isEmpty else { return false }
        return url(lang: lang, key: Self.helloKey(n)) != nil
    }

    /// Et son au revoir ? (Sinon il dit au revoir sans le prénom.)
    func knowsBye(name: String, lang: String) -> Bool {
        let n = Self.normalized(name)
        guard !n.isEmpty else { return false }
        return url(lang: lang, key: Self.byeKey(n)) != nil
    }

    /// Les répliques dans l'ordre, ou rien si l'une d'elles manque (on retombe alors sur la synthèse, d'une seule voix).
    func sequence(_ keys: [String], lang: String, format: AVAudioFormat, gap: Double) -> [AVAudioPCMBuffer]? {
        guard !keys.isEmpty else { return nil }
        var out: [AVAudioPCMBuffer] = []
        for (index, key) in keys.enumerated() {
            guard let buffer = buffer(lang: lang, key: key, format: format) else { return nil }
            if index > 0, let silence = Self.silence(gap, format: format) { out.append(silence) }
            out.append(buffer)
        }
        return out
    }

    private func buffer(lang: String, key: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = url(lang: lang, key: key) else { return nil }
        let id = url.lastPathComponent + "@" + lang
        lock.lock()
        let cached = cache[id]
        lock.unlock()
        if let cached { return cached }
        guard let buffer = Self.read(url, format: format) else { return nil }
        lock.lock()
        // Les prénoms et les phrases d'un appel : quelques dizaines de fichiers, pas toute la banque.
        if cache.count > 160 { cache.removeAll() }
        cache[id] = buffer
        lock.unlock()
        return buffer
    }

    private static func read(_ url: URL, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do { try file.read(into: raw) } catch { return nil }
        if file.processingFormat == format { return raw }
        return SantaVoice.convert(raw, to: format)
    }

    private static func silence(_ seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(max(1, format.sampleRate * seconds))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        return buffer
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
