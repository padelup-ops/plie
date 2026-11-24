// Call.swift — Allô Père Noël
//
// Le déroulé d'un appel : on prépare toutes les phrases pendant que le téléphone sonne (aucun blanc pendant
// l'appel), puis le Père Noël parle, laisse à l'enfant le temps de répondre en l'écoutant, fait sa surprise,
// et dit au revoir. Le parent peut raccrocher à tout moment.

import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class CallController {
    enum Phase: Equatable { case idle, ringing, talking, ended }

    private(set) var phase: Phase = .idle
    private(set) var caption = ""
    private(set) var mood: SantaMood = .idle
    private(set) var surpriseAt: Date?
    private(set) var startedAt: Date?
    let voice = SantaVoice()

    private var segments: [Segment] = []
    private var audio: [Int: [AVAudioPCMBuffer]] = [:]
    private var renderTask: Task<Void, Never>?
    private var callTask: Task<Void, Never>?
    private var hapticTask: Task<Void, Never>?

    var mouth: Double { voice.level }

    /// Prépare l'appel : le texte, puis les sons de chaque phrase, en arrière-plan.
    func prepare(profile: ChildProfile, scenario: Scenario, premium: Bool, audio withAudio: Bool = true) {
        let (book, lang) = ScriptBook.load()
        voice.configure(book: book)
        segments = ScriptBuilder(book: book, lang: lang, profile: profile, premium: premium).build(scenario)
        audio = [:]
        caption = ""
        mood = .idle
        surpriseAt = nil
        startedAt = nil
        renderTask?.cancel()
        guard withAudio else { return }
        let segs = segments
        renderTask = Task { [weak self] in
            for (i, s) in segs.enumerated() {
                guard let self, !Task.isCancelled else { return }
                if let text = s.text { self.audio[i] = await self.voice.render(text) }
            }
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
        voice.ambience(on: true)
        callTask?.cancel()
        callTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(900))
            await self.run()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            self.voice.ambience(on: false)
            self.phase = .ended
            onEnd()
        }
    }

    private func run() async {
        for (i, s) in segments.enumerated() {
            if Task.isCancelled { return }
            switch s {
            case let .say(text, laugh, wave):
                caption = text
                mood = wave ? .waving : (laugh ? .laughing : .talking)
                // si la phrase n'est pas encore prête (première phrase), on l'attend un peu
                var waited = 0
                while audio[i] == nil && waited < 60 && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
                let bufs = audio[i] ?? []
                if bufs.isEmpty {
                    // pas de voix disponible : on laisse le temps de lire le sous-titre
                    try? await Task.sleep(for: .seconds(max(2.2, Double(text.count) / 14)))
                } else {
                    await voice.play(bufs)
                }
                if !wave { mood = .idle }
                try? await Task.sleep(for: .milliseconds(380))
            case let .listen(sec):
                mood = .listening
                try? await Task.sleep(for: .seconds(sec))
                mood = .idle
            case let .spark(sec):
                mood = .surprised
                surpriseAt = Date()
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
        phase = .idle
        mood = .idle
    }

    /// « Écouter le Père Noël » : une courte phrase, sans prénom (découverte, réglages).
    private(set) var previewing = false
    func preview() {
        guard !previewing else { return }
        let (book, lang) = ScriptBook.load()
        voice.configure(book: book)
        let segs = ScriptBuilder(book: book, lang: lang, profile: ChildProfile(), premium: false).block("sample")
        previewing = true
        Task {
            for s in segs { if let t = s.text { await voice.play(await voice.render(t)) } }
            previewing = false
        }
    }

    /// Pour les captures : un instant précis de l'appel, sans son.
    func pose(caption: String, mood: SantaMood, surprise: Bool = false) {
        phase = .talking
        startedAt = Date().addingTimeInterval(-42)
        self.caption = caption
        self.mood = mood
        if surprise { surpriseAt = Date().addingTimeInterval(-0.6) }
    }
}
