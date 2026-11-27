// Call.swift — Allô Père Noël
//
// Le déroulé d'un appel : on prépare toutes les phrases pendant que le téléphone sonne (aucun blanc pendant
// l'appel), puis le Père Noël parle, laisse à l'enfant le temps de répondre en l'écoutant, donne la parole à son
// lutin pour ce que le parent a écrit, fait sa surprise, et dit au revoir. Le parent peut raccrocher à tout moment.

import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class CallController {
    enum Phase: Equatable { case idle, ringing, talking, ended }

    private(set) var phase: Phase = .idle
    private(set) var caption = ""
    /// Qui dit la phrase affichée.
    private(set) var speaker: Speaker = .santa
    private(set) var mood: SantaMood = .idle
    private(set) var surpriseAt: Date?
    private(set) var startedAt: Date?
    /// L'appel préparé est l'aperçu gratuit : il s'arrête avant la fin de l'histoire.
    private(set) var isPreview = false
    /// L'aperçu gratuit a été écouté jusqu'au bout.
    private(set) var previewCut = false
    /// Le nom du lutin, pour l'étiquette de ses sous-titres.
    private(set) var elfLabel = ""
    let voice = SantaVoice()
    /// La caméra avant, si le parent l'a demandée : l'enfant se voit dans un coin, comme en appel vidéo.
    let reactionCamera = ReactionCamera()
    private(set) var cameraOn = false
    /// Les photos de la réaction de l'enfant (Pass Noël) : en mémoire seulement, montrées au parent à la fin.
    private(set) var reactions: [UIImage] = []
    /// La pièce est sombre : l'écran éclaire le visage de l'enfant (halo clair, luminosité au maximum) jusqu'à la fin.
    private(set) var lowLight = false
    /// Il faisait trop sombre pour garder des photos : on le dit au parent à la fin, plutôt que de montrer du noir.
    private(set) var tooDarkForPhotos = false
    private var savedBrightness: CGFloat?
    private var lightTask: Task<Void, Never>?
    private var showChild = false
    private var keepReactions = false

    private var segments: [Segment] = []
    private var audio: [Int: SantaVoice.SpokenAudio] = [:]
    private var renderTask: Task<Void, Never>?
    private var callTask: Task<Void, Never>?
    private var hapticTask: Task<Void, Never>?

    var mouth: Double { max(voice.level, posedMouth) }

    /// Prépare l'appel : le texte, puis les sons de chaque phrase, en arrière-plan.
    func prepare(profile: ChildProfile, scenario: Scenario, premium: Bool, audio withAudio: Bool = true) {
        let (book, lang) = ScriptBook.load()
        voice.configure(book: book, lang: lang)
        elfLabel = book.elfLabel
        let built = ScriptBuilder(book: book, lang: lang, profile: profile, premium: premium).build(scenario)
        segments = built.segments
        isPreview = built.preview
        audio = [:]
        caption = ""
        speaker = .santa
        mood = .idle
        surpriseAt = nil
        startedAt = nil
        previewCut = false
        reactions = []
        tooDarkForPhotos = false
        renderTask?.cancel()
        guard withAudio else { return }
        let segs = segments
        renderTask = Task { [weak self] in
            for (i, s) in segs.enumerated() {
                guard let self, !Task.isCancelled else { return }
                if case let .say(_, _, _, _, cue) = s { self.audio[i] = await self.voice.render(cue: cue) }
            }
        }
    }

    /// Ce que le parent a choisi avant l'appel.
    func camera(show: Bool, keep: Bool) {
        showChild = show
        keepReactions = show && keep
    }

    func forgetReactions() { reactions = [] }

    /// Une photo de la réaction, un instant après un moment fort.
    private func snap(after seconds: Double) {
        guard cameraOn, keepReactions, reactions.count < 6 else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            // Jamais pendant que la caméra règle sa lumière : on lui laisse jusqu'à deux secondes.
            for _ in 0..<6 {
                guard let self, self.cameraOn else { return }
                if !self.reactionCamera.isSettling { break }
                try? await Task.sleep(for: .milliseconds(330))
            }
            guard let self, self.phase == .talking, self.cameraOn, self.reactions.count < 6 else { return }
            switch self.reactionCamera.snapshot() {
            case let .image(image): self.reactions.append(image)
            case .tooDark: self.tooDarkForPhotos = true
            case nil: break
            }
        }
    }

    private func startCamera() {
        reactionCamera.start()
        cameraOn = true
        lowLight = false
        lightTask?.cancel()
        lightTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.cameraOn else { return }
                if !self.lowLight, self.reactionCamera.isDim {
                    self.lowLight = true
                    self.lightScreen()
                }
            }
        }
    }

    private func stopCamera() {
        guard cameraOn else { return }
        lightTask?.cancel()
        reactionCamera.stop()
        cameraOn = false
        lowLight = false
        restoreScreen()
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    /// Dans une pièce sombre, c'est l'écran qui éclaire le visage : luminosité au maximum, le temps de l'appel.
    private func lightScreen() {
        guard savedBrightness == nil, let screen else { return }
        savedBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreScreen() {
        if let saved = savedBrightness, let screen { screen.brightness = saved }
        savedBrightness = nil
    }

    /// L'app passe à l'arrière-plan pendant un appel : l'iPhone retrouve sa luminosité ; elle remonte au retour.
    func appActive(_ active: Bool) {
        if !active {
            restoreScreen()
        } else if cameraOn, lowLight {
            lightScreen()
        }
    }

    /// Le texte de l'appel (pour l'aperçu et les captures).
    var script: [Segment] { segments }

    func ring() {
        phase = .ringing
        voice.ring()
        hapticTask?.cancel()
        hapticTask = Task {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            while !Task.isCancelled {
                for _ in 0..<2 { gen.impactOccurred(); try? await Task.sleep(for: .milliseconds(160)) }
                try? await Task.sleep(for: .milliseconds(1700))
            }
        }
    }

    func decline() {
        hapticTask?.cancel()
        voice.stopRing()
        phase = .idle
    }

    func answer(onEnd: @escaping @MainActor () -> Void) {
        hapticTask?.cancel()
        voice.stopRing()
        phase = .talking
        startedAt = Date()
        if showChild, ReactionCamera.authorized { startCamera() }
        voice.ambience(on: true)
        callTask?.cancel()
        callTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(900))
            await self.run()
            guard !Task.isCancelled else { return }
            self.previewCut = self.isPreview
            try? await Task.sleep(for: .milliseconds(1400))
            self.voice.ambience(on: false)
            self.stopCamera()
            self.phase = .ended
            onEnd()
        }
    }

    private func run() async {
        let firstLine = segments.firstIndex { if case .say = $0 { return true }; return false }
        for (i, s) in segments.enumerated() {
            if Task.isCancelled { return }
            switch s {
            case let .say(text, who, laugh, wave, _):
                // Les moments forts : le bonjour (l'enfant entend le Père Noël, et souvent son prénom), les rires,
                // l'au revoir.
                if i == firstLine { snap(after: 3.0) } else if wave { snap(after: 1.0) } else if laugh { snap(after: 1.6) }
                caption = text
                speaker = who
                // Pendant que le lutin parle, le Père Noël l'écoute.
                mood = who == .elf ? .listening : (wave ? .waving : (laugh ? .laughing : .talking))
                // si la phrase n'est pas encore prête (première phrase), on l'attend un peu
                var waited = 0
                while audio[i] == nil && waited < 60 && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
                if let spoken = audio[i], !spoken.buffers.isEmpty {
                    await voice.play(spoken)
                } else {
                    // pas de voix disponible : on laisse le temps de lire le sous-titre
                    try? await Task.sleep(for: .seconds(max(2.2, Double(text.count) / 14)))
                }
                if !wave { mood = .idle }
                try? await Task.sleep(for: .milliseconds(who == .elf ? 260 : 380))
            case let .listen(sec):
                mood = .listening
                try? await Task.sleep(for: .seconds(sec))
                mood = .idle
            case let .spark(sec):
                mood = .surprised
                surpriseAt = Date()
                snap(after: 1.4)
                voice.sparkle()
                try? await Task.sleep(for: .seconds(sec))
                mood = .idle
            }
        }
    }

    func hangUp() {
        callTask?.cancel()
        hapticTask?.cancel()
        renderTask?.cancel()
        voice.stopAll()
        stopCamera()
        // Raccroché en plein aperçu : la fin de l'appel propose aussi d'entendre la suite.
        if phase == .talking, isPreview { previewCut = true }
        phase = .idle
        mood = .idle
    }

    /// Une phrase hors appel est en train d'être dite (accueil, calendrier de l'Avent, découverte).
    private(set) var previewing = false
    private var soloTask: Task<Void, Never>?

    /// Une réplique seule (calendrier de l'Avent).
    func speakLine(_ text: String) async {
        await speak([ScriptBuilder.line(text)])
    }

    /// Un bloc du livre, sans prénom : « welcome » (l'accueil), « sample » (écouter le Père Noël).
    func speakBlock(_ name: String) async {
        let (book, lang) = ScriptBook.load()
        await speak(ScriptBuilder(book: book, lang: lang, profile: ChildProfile(), premium: false).block(name))
    }

    func preview() {
        guard !previewing else { return }
        soloTask = Task { await speakBlock("sample") }
    }

    private func speak(_ segs: [Segment]) async {
        guard !previewing, phase == .idle || phase == .ended else { return }
        let (book, lang) = ScriptBook.load()
        voice.configure(book: book, lang: lang)
        previewing = true
        mood = .talking
        for s in segs {
            if Task.isCancelled { break }
            if case let .say(_, _, laugh, _, cue) = s {
                mood = laugh ? .laughing : .talking
                await voice.play(await voice.render(cue: cue))
            }
        }
        mood = .idle
        previewing = false
    }

    /// Coupe la phrase hors appel en cours (on quitte l'écran).
    func stopSolo() {
        soloTask?.cancel()
        voice.stopSpeech()
        if phase != .talking { mood = .idle }
        previewing = false
    }

    /// Pour les captures : un instant précis de l'appel, sans son.
    func pose(caption: String, mood: SantaMood, surprise: Bool = false, mouth: Double = 0) {
        phase = .talking
        startedAt = Date().addingTimeInterval(-42)
        self.caption = caption
        self.mood = mood
        posedMouth = mouth
        if surprise { surpriseAt = Date().addingTimeInterval(-0.6) }
    }
    /// Captures : la bouche figée à cette ouverture.
    private(set) var posedMouth: Double = 0
}
