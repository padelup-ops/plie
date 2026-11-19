import AVFoundation
import FluidAudio
import Foundation
import UIKit

/// La dictée Parakeet (NVIDIA Parakeet TDT 0.6B v3, via FluidAudio, licence Apache 2.0) : 25 langues européennes,
/// ponctuation et majuscules, tout sur l'iPhone (Neural Engine). Le modèle se télécharge une fois depuis l'app
/// (environ 480 Mo) ; tant qu'il n'est pas là, la dictée d'Apple prend le relais.
///
/// Le modèle n'est chargé en mémoire que pendant qu'on dicte, et quelques minutes après : l'app reste légère en
/// arrière-plan, donc iOS ne la ferme pas et le clavier n'a pas à la rouvrir.
@Observable
final class ParakeetModel {
    static let shared = ParakeetModel()

    enum State: Equatable { case absent, downloading(Double), preparing, installed, failed(String) }
    var state: State = .absent

    /// L'utilisateur peut garder la dictée d'Apple même avec le modèle téléchargé.
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "parakeet.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "parakeet.enabled"); bump += 1 }
    }
    private var bump = 0

    @ObservationIgnored private let manager = AsrManager(config: .default)
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loading: Task<Void, Error>?
    @ObservationIgnored private var unloadTimer: Timer?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    static let version: AsrModelVersion = .v3
    static var directory: URL { AsrModels.defaultCacheDirectory(for: version) }
    /// La taille annoncée avant le téléchargement.
    static let approxMB = 480

    private init() {
        state = AsrModels.modelsExist(at: Self.directory, version: Self.version) ? .installed : .absent
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.unloadNow()
        }
    }

    var isInstalled: Bool { state == .installed }
    /// Parakeet sera utilisé pour la prochaine dictée.
    var isActive: Bool { _ = bump; return isInstalled && enabled }

    func download() {
        guard downloadTask == nil else { return }
        state = .downloading(0)
        downloadTask = Task { [weak self] in
            do {
                // L'écran reste allumé pendant le téléchargement (sinon iOS le met en pause).
                await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
                let dir = try await AsrModels.download(version: Self.version) { p in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if case .compiling = p.phase { self.state = .preparing } else { self.state = .downloading(p.fractionCompleted) }
                    }
                }
                Self.excludeFromBackup(dir.deletingLastPathComponent())
                // Premier chargement tout de suite (iOS prépare le modèle pour le Neural Engine une fois pour toutes).
                await MainActor.run { self?.state = .preparing }
                try await self?.ensureLoaded()
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self?.state = .installed
                    self?.downloadTask = nil
                    self?.scheduleUnload()
                }
            } catch {
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self?.state = .failed(error.localizedDescription)
                    self?.downloadTask = nil
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = AsrModels.modelsExist(at: Self.directory, version: Self.version) ? .installed : .absent
    }

    func delete() {
        unloadNow()
        try? FileManager.default.removeItem(at: Self.directory)
        state = .absent
    }

    /// Charge le modèle (une seconde ou deux) ; les dictées attendent ce chargement.
    func ensureLoaded() async throws {
        unloadTimer?.invalidate()
        if loaded { return }
        if let loading { return try await loading.value }
        let t = Task {
            let models = try await AsrModels.load(from: Self.directory, version: Self.version)
            try await manager.loadModels(models)
        }
        loading = t
        do {
            try await t.value
            loaded = true
            loading = nil
        } catch {
            loading = nil
            throw error
        }
    }

    /// Le texte de tout ce qui a été dit (16 kHz, mono).
    func transcribe(_ samples: [Float]) async throws -> String {
        try await ensureLoaded()
        var s = samples
        // Le modèle veut au moins une seconde de son.
        if s.count < 16_000 { s += [Float](repeating: 0, count: 16_000 - s.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let r = try await manager.transcribe(s, decoderState: &state)
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le modèle quitte la mémoire trois minutes après la dernière dictée.
    func scheduleUnload() {
        DispatchQueue.main.async {
            self.unloadTimer?.invalidate()
            self.unloadTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in self?.unloadNow() }
        }
    }

    private func unloadNow() {
        unloadTimer?.invalidate()
        guard loaded else { return }
        loaded = false
        let m = manager
        Task { await m.cleanup() }
    }

    private static func excludeFromBackup(_ url: URL) {
        var u = url
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
    }
}

/// Une dictée avec Parakeet : le son du micro arrive (au format du micro), on le ramène à 16 kHz mono, et on
/// retranscrit régulièrement le tout pour afficher le texte pendant qu'on parle. Le texte final arrive à la fin.
final class ParakeetDictation {
    private let model = ParakeetModel.shared
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var inFormat: AVAudioFormat?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var finished = false
    private var loop: Task<Void, Never>?
    private var onText: ((String, Bool) -> Void)?

    /// Commence : le modèle se charge pendant qu'on parle déjà (le son est gardé).
    func start(onText: @escaping (String, Bool) -> Void) {
        self.onText = onText
        loop = Task { [weak self] in
            do { try await self?.model.ensureLoaded() } catch {
                self?.fail()
                return
            }
            var done = 0
            while let self, !Task.isCancelled {
                if self.isFinished { break }
                let count = self.sampleCount
                // Le texte en direct : toutes les 0,6 s (puis moins souvent pour les longues dictées).
                let wait: Double = count > 16_000 * 25 ? 2.0 : 0.6
                if count - done >= 16_000 / 4 {
                    done = count
                    if let t = try? await self.model.transcribe(self.snapshot()), !self.isFinished {
                        self.onText?(t, false)
                    }
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    private var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
    private func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }

    /// Le son du micro (appelé depuis le fil audio).
    func append(_ buffer: AVAudioPCMBuffer) {
        if inFormat == nil || inFormat != buffer.format {
            inFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
        }
        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let ch = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        lock.lock()
        if !finished { samples.append(contentsOf: chunk) }
        lock.unlock()
    }

    /// Fin de la dictée : le texte de tout ce qui a été dit.
    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let all = samples
        lock.unlock()
        loop?.cancel()
        Task { [weak self] in
            await self?.loop?.value
            guard let self else { return }
            defer { self.model.scheduleUnload() }
            // Moins d'un quart de seconde : rien n'a été dit.
            guard all.count > 16_000 / 4 else { self.sendFinal(""); return }
            if let t = try? await self.model.transcribe(all) { self.sendFinal(t) } else { self.fail() }
        }
    }

    func cancel() {
        lock.lock(); finished = true; lock.unlock()
        loop?.cancel()
        model.scheduleUnload()
    }

    private var sent = false

    /// Le texte final, une seule fois.
    private func sendFinal(_ text: String) {
        lock.lock()
        finished = true
        let first = !sent
        sent = true
        lock.unlock()
        if first { onText?(text, true) }
    }

    /// Le modèle n'a pas pu servir : on rend la main (texte vide, final) et l'app revient à la dictée d'Apple.
    private func fail() {
        failed = true
        sendFinal("")
    }

    /// Le modèle a refusé de se charger ou de transcrire (l'app revient à la dictée d'Apple).
    private(set) var failed = false
}

/// Essai de bout en bout pour la CI (simulateur) : téléchargement, puis le fichier passe par le même chemin que le
/// micro (morceaux de 1024 échantillons au format du fichier), et le texte final est écrit dans Documents.
enum ParakeetSelfTest {
    static func run(_ path: String) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let out = docs.appendingPathComponent("parakeet-result.txt")
        func write(_ s: String) { try? s.write(to: out, atomically: true, encoding: .utf8); print("PARAKEET", s) }
        do {
            let t0 = Date()
            if !AsrModels.modelsExist(at: ParakeetModel.directory, version: ParakeetModel.version) {
                _ = try await AsrModels.download(version: ParakeetModel.version)
            }
            let t1 = Date()
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let fmt = file.processingFormat
            let d = ParakeetDictation()
            let result: String = await withCheckedContinuation { cont in
                var partials = 0
                d.start { text, final in
                    if final { cont.resume(returning: "\(text)\npartials=\(partials)") } else { partials += 1 }
                }
                Task {
                    while true {
                        guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024) else { break }
                        do { try file.read(into: b, frameCount: 1024) } catch { break }
                        if b.frameLength == 0 { break }
                        d.append(b)
                        // En temps réel, comme le micro.
                        try? await Task.sleep(for: .seconds(Double(b.frameLength) / fmt.sampleRate))
                    }
                    d.finish()
                }
            }
            write("OK download=\(Int(t1.timeIntervalSince(t0)))s total=\(Int(Date().timeIntervalSince(t0)))s\n\(result)")
        } catch {
            write("ERROR \(error)")
        }
    }
}
