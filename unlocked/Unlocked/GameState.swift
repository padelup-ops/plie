import SwiftUI
import AVFoundation

// MARK: - L'avancée du joueur dans un téléphone
//
// Des « faits » (unlocked, ines_told, h_found…) avec l'heure où ils sont devenus vrais.
// Les messages en direct arrivent quelques secondes après leur fait ; les réponses du joueur posent de nouveaux faits.
// Tout est sauvegardé sur l'appareil : on reprend là où on s'était arrêté.

@Observable
final class GameState {
    let story: PhoneStory
    private let key: String

    private(set) var facts: [String: Date] = [:]
    /// Les messages arrivés en direct et ceux envoyés par le joueur, dans l'ordre.
    private(set) var extra: [Message] = []
    private(set) var readThreads: Set<String> = []
    /// La bannière en haut de l'écran (le dernier message arrivé).
    var banner: Message?
    var openApp: AppKind?
    var openThread: String?
    var showChapterEnd = false
    var lockedAppAlert: AppKind?

    private var timer: Timer?
    private let speech = AVSpeechSynthesizer()

    init(story: PhoneStory, key: String) {
        self.story = story
        self.key = key
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: Faits

    func has(_ fact: String) -> Bool { facts[fact] != nil }

    func set(_ fact: String) {
        guard facts[fact] == nil else { return }
        facts[fact] = Date()
        if fact == story.chapterOneEnd { showChapterEnd = true }
        save()
    }

    var unlocked: Bool { has("unlocked") }
    var chapter: Int { has(story.chapterOneEnd) ? 2 : 1 }

    // MARK: Déverrouillage

    /// Vrai si le code est bon.
    func tryCode(_ code: String) -> Bool {
        guard code == story.passcode else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        set("unlocked")
        return true
    }

    // MARK: Messages

    func messages(in thread: String) -> [Message] {
        let base = story.conversations.first { $0.id == thread }?.history ?? []
        return base + extra.filter { $0.thread == thread }
    }

    func lastMessage(in thread: String) -> Message? { messages(in: thread).last }

    func unread(_ thread: String) -> Bool {
        if !readThreads.contains(thread) { return true }
        return false
    }

    func markRead(_ thread: String) {
        if readThreads.insert(thread).inserted { save() }
    }

    /// Les conversations, la plus récente en haut.
    var threadOrder: [String] {
        let ids = story.conversations.map(\.id)
        let lastLive = Dictionary(extra.enumerated().map { ($0.element.thread, $0.offset) }, uniquingKeysWith: max)
        return ids.sorted { a, b in
            let la = lastLive[a] ?? -1, lb = lastLive[b] ?? -1
            if la != lb { return la > lb }
            return (ids.firstIndex(of: a) ?? 0) < (ids.firstIndex(of: b) ?? 0)
        }
    }

    func choices(in thread: String) -> [ReplyChoice] {
        story.replies.filter { r in
            r.thread == thread && r.when.allSatisfy { has($0) } && !has(r.until) && !has("said_" + r.id)
        }
    }

    func send(_ choice: ReplyChoice) {
        extra.append(Message(id: "me_" + choice.id, thread: choice.thread, fromMe: true, text: choice.text, time: T("maintenant", "now")))
        facts["said_" + choice.id] = Date()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        set(choice.sets)
        save()
    }

    // MARK: Le temps qui passe

    private func tick() {
        guard unlocked else { return }
        let now = Date()
        for live in story.live where !extra.contains(where: { $0.id == live.message.id }) {
            guard let since = facts[live.after], now.timeIntervalSince(since) >= live.delay else { continue }
            extra.append(live.message)
            readThreads.remove(live.message.thread)
            if openThread != live.message.thread || openApp != .messages {
                banner = live.message
                let shown = live.message.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    if self?.banner?.id == shown { self?.banner = nil }
                }
            } else {
                readThreads.insert(live.message.thread)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if let s = live.sets { set(s) }
            save()
            break   // un message à la fois
        }
    }

    // MARK: Messagerie vocale

    func play(_ voicemail: Voicemail) {
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: voicemail.transcript)
        u.voice = AVSpeechSynthesisVoice(language: Lang.french ? "fr-FR" : "en-US")
        u.rate = 0.48
        u.pitchMultiplier = voicemail.contact == "h" ? 0.8 : 1.05
        speech.speak(u)
        set("heard_" + voicemail.id)
    }

    func stopVoice() { speech.stopSpeaking(at: .immediate) }

    // MARK: Recommencer

    func reset() {
        facts = [:]
        extra = []
        readThreads = []
        banner = nil
        openApp = nil
        openThread = nil
        showChapterEnd = false
        save()
    }

    // MARK: Sauvegarde

    private struct Saved: Codable {
        var facts: [String: Date]
        var extra: [String]
        var read: [String]
    }

    private func save() {
        let s = Saved(facts: facts, extra: extra.map(\.id), read: Array(readThreads))
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        facts = s.facts
        readThreads = Set(s.read)
        // Les messages du joueur et ceux arrivés en direct sont retrouvés dans l'histoire.
        var all: [Message] = story.live.map(\.message)
        all += story.replies.map { Message(id: "me_" + $0.id, thread: $0.thread, fromMe: true, text: $0.text, time: T("plus tôt", "earlier")) }
        extra = s.extra.compactMap { id in all.first { $0.id == id } }
    }
}
