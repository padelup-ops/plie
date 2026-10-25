import SwiftUI
import AVFoundation
import Observation

enum SoleilPhase: Equatable {
    case setup
    case countdown(Int)
    case go
    case freezing
    case stop
    case caught
    case won
}

enum SoleilSensitivity: String, CaseIterable, Identifiable {
    case cool, normal, strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cool: return L("Cool")
        case .normal: return L("Normal")
        case .strict: return L("Strict")
        }
    }

    var detail: String {
        switch self {
        case .cool: return L("Seuls les grands gestes comptent. Idéal avec des enfants.")
        case .normal: return L("Un pas ou un bras qui bouge, et c'est perdu.")
        case .strict: return L("Le moindre frisson est repéré. Bonne chance.")
        }
    }

    /// Part de l'image qui doit changer pour qu'on considère que quelqu'un a bougé.
    var threshold: Double {
        switch self {
        case .cool: return 0.03
        case .normal: return 0.013
        case .strict: return 0.006
        }
    }
}

/// La voix qui annonce « Un, deux, trois… soleil ! ».
final class SoleilCaller: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String, rate: Float, delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Lang.shared.speechLanguage)
        utterance.rate = rate
        utterance.preUtteranceDelay = delay
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let done = completion
        completion = nil
        DispatchQueue.main.async { done?() }
    }
}

@Observable
final class SoleilGame {
    var phase: SoleilPhase = .setup
    var sensitivity: SoleilSensitivity = .normal

    // Caméra
    var cameraAllowed = true
    var cameraReady = false
    var cameraToken = 0
    var cameraPosition: AVCaptureDevice.Position = .front
    /// Caméra choisie par les joueurs : celle de l'écran (avant) ou celle du dos (arrière).
    var cameraChoice: AVCaptureDevice.Position = .front
    var motionLevel: Double = 0
    var unstable = false

    // iPhone Duo
    var hingeDetected = false
    var useOuterScreen = false
    var outerEnabled = true
    var outerAvailable = false

    // Partie
    var catches = 0
    var snapshots: [UIImage] = []
    var lastSnapshot: UIImage?
    var lastSide: Double = 0.5
    var elapsed: Double = 0

    @ObservationIgnored let camera = SoleilCamera()
    @ObservationIgnored private let caller = SoleilCaller()
    @ObservationIgnored private var cycle = 0
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var unstableTask: Task<Void, Never>?

    /// Les joueurs regardent l'écran extérieur du Duo (sinon, l'écran principal).
    var playersUseOuterScreen: Bool { useOuterScreen && outerAvailable }

    var isPlaying: Bool {
        switch phase {
        case .countdown, .go, .freezing, .stop, .caught: return true
        default: return false
        }
    }

    init() {
        camera.onMotionLevel = { [weak self] level in
            guard let self, self.phase == .stop else { return }
            self.motionLevel = level
        }
        camera.onCatch = { [weak self] snapshot in
            self?.caught(snapshot.image, side: snapshot.side)
        }
        camera.onCovered = { [weak self] in
            guard let self, self.phase == .go else { return }
            self.win()
        }
        camera.onUnstable = { [weak self] in
            guard let self else { return }
            self.unstable = true
            self.unstableTask?.cancel()
            self.unstableTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled { self.unstable = false }
            }
        }
    }

    // MARK: Caméra

    @MainActor
    func prepareCamera() async {
        let allowed = await SoleilCamera.requestAccess()
        cameraAllowed = allowed
        guard allowed else { return }
        let position = wantedCameraPosition
        let ok = await camera.configure(position: position)
        cameraReady = ok
        cameraPosition = position
        cameraToken += 1
        if ok { camera.start() }
    }

    /// Caméra tournée vers les joueurs.
    /// iPhone Duo ouvert avec l'écran extérieur : caméra arrière, du même côté que l'écran extérieur.
    /// Sinon (Duo fermé ou autre iPhone) : caméra avant, du côté de l'écran principal.
    var wantedCameraPosition: AVCaptureDevice.Position {
        cameraChoice
    }

    /// Les joueurs choisissent la caméra qui les voit.
    @MainActor
    func setCamera(_ position: AVCaptureDevice.Position) async {
        guard position != cameraChoice else { return }
        cameraChoice = position
        await syncCamera()
    }

    @MainActor
    func setUseOuterScreen(_ value: Bool) async {
        guard value != useOuterScreen else { return }
        useOuterScreen = value
        await syncCamera()
    }

    /// Change de caméra si les joueurs ne regardent plus le même écran.
    @MainActor
    func syncCamera() async {
        guard cameraAllowed, cameraReady else { return }
        let wanted = wantedCameraPosition
        guard wanted != cameraPosition else { return }
        let ok = await camera.configure(position: wanted)
        if ok {
            cameraPosition = wanted
            cameraToken += 1
        }
    }

    // MARK: Déroulement

    func start() {
        cycle += 1
        let current = cycle
        catches = 0
        snapshots = []
        lastSnapshot = nil
        elapsed = 0
        motionLevel = 0
        UIApplication.shared.isIdleTimerDisabled = true
        // Tout est annoncé à voix haute : les joueurs n'ont pas besoin de voir l'écran.
        caller.say(L("Posez le téléphone, la caméra vers vous, et placez-vous au fond. Départ dans dix secondes !"), rate: 0.5)

        Task { @MainActor in
            for n in stride(from: 10, through: 1, by: -1) {
                guard self.cycle == current else { return }
                self.phase = .countdown(n)
                SoundPlayer.shared.play(.notch)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard self.cycle == current else { return }
            self.startDate = Date()
            self.startClock()
            self.go()
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let start = self.startDate, self.isPlaying {
                    self.elapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    private func go() {
        cycle += 1
        let current = cycle
        phase = .go
        motionLevel = 0
        camera.disarm()
        camera.watchCover(true)
        SoundPlayer.shared.play(.go)

        let variants: [(String, ClosedRange<Float>)] = [
            (L("Un, deux, trois, soleil !"), 0.42...0.56),
            (L("Un… deux… trois… soleil !"), 0.40...0.48),
            (L("Un deux trois soleil !"), 0.58...0.64),
            (L("Un, deux… trois… soleil !"), 0.45...0.55)
        ]
        let pick = variants.randomElement() ?? variants[0]
        let delay = Double.random(in: 0.3...1.6)
        caller.say(pick.0, rate: Float.random(in: pick.1), delay: delay) { [weak self] in
            guard let self, self.cycle == current, self.phase == .go else { return }
            self.freeze()
        }
        // Sécurité si la voix ne répond pas.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if self.cycle == current && self.phase == .go { self.freeze() }
        }
    }

    private func freeze() {
        cycle += 1
        let current = cycle
        phase = .freezing
        camera.watchCover(false)
        SoundPlayer.shared.play(.stop)
        Task { @MainActor in
            // Une demi-seconde pour s'arrêter, puis la caméra surveille.
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard self.cycle == current, self.phase == .freezing else { return }
            self.phase = .stop
            self.camera.arm(threshold: self.sensitivity.threshold)
            let stopDuration = Double.random(in: 2.5...5.0)
            try? await Task.sleep(nanoseconds: UInt64(stopDuration * 1_000_000_000))
            guard self.cycle == current, self.phase == .stop else { return }
            self.go()
        }
    }

    private func caught(_ image: UIImage, side: Double) {
        guard phase == .stop else { return }
        cycle += 1
        let current = cycle
        phase = .caught
        catches += 1
        lastSnapshot = image
        snapshots.append(image)
        camera.disarm()
        SoundPlayer.shared.play(.caught)
        let who: String
        if side < 0.36 {
            who = L("Bougé ! Le joueur de gauche retourne au départ !")
        } else if side > 0.64 {
            who = L("Bougé ! Le joueur de droite retourne au départ !")
        } else {
            who = L("Bougé ! Le joueur du milieu retourne au départ !")
        }
        lastSide = side
        caller.say(who, rate: 0.52)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            guard self.cycle == current, self.phase == .caught else { return }
            self.go()
        }
    }

    func win() {
        guard isPlaying else { return }
        cycle += 1
        phase = .won
        if let start = startDate { elapsed = Date().timeIntervalSince(start) }
        clockTask?.cancel()
        camera.disarm()
        camera.watchCover(false)
        caller.say(L("Touché ! Bravo, on a un gagnant !"), rate: 0.5)
        SoundPlayer.shared.play(.win)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func backToSetup() {
        cycle += 1
        caller.stop()
        camera.disarm()
        camera.watchCover(false)
        clockTask?.cancel()
        phase = .setup
        motionLevel = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func shutdown() {
        cycle += 1
        caller.stop()
        clockTask?.cancel()
        unstableTask?.cancel()
        camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
