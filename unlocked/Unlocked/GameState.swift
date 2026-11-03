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
    /// Le numéro du chapitre qui vient de se terminer (la carte de fin s'affiche).
    var showChapterEnd: Int?
    /// L'histoire complète a été achetée.
    var fullStory = false {
        didSet { startChapters() }
    }
    var lockedAppAlert: AppKind?
    var showPaywall = false

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
        if let i = story.chapters.firstIndex(where: { $0.end == fact }) { showChapterEnd = i + 1 }
        save()
        startChapters()
    }

    var unlocked: Bool { has("unlocked") }

    /// Les chapitres terminés, dans l'ordre.
    var chaptersDone: Int {
        var n = 0
        for c in story.chapters { if has(c.end) { n += 1 } else { break } }
        return n
    }

    /// Le chapitre où l'on en est (on reste au dernier chapitre gratuit tant que la suite n'est pas achetée).
    var chapter: Int {
        let next = min(chaptersDone + 1, story.chapters.count)
        return fullStory ? next : min(next, story.freeChapters)
    }

    /// Le chapitre gratuit est fini et la suite n'est pas achetée.
    var needsPurchase: Bool { !fullStory && chaptersDone >= story.freeChapters }

    /// Toute l'histoire est terminée.
    var finished: Bool { chaptersDone >= story.chapters.count }

    /// Pose le fait de début de chaque chapitre ouvert (ses messages en direct démarrent).
    private func startChapters() {
        guard unlocked else { return }
        for (i, c) in story.chapters.enumerated() where i < chapter && facts[c.start] == nil {
            facts[c.start] = Date()
            save()
        }
    }

    /// Le mode avion se met et s'enlève.
    func setAirplane(_ on: Bool) {
        if on { set("airplane") } else { facts.removeValue(forKey: "airplane"); save() }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: L'album masqué

    var albumOpen: Bool { has("album_open") }

    func tryAlbum(_ code: String) -> Bool {
        guard let album = story.hiddenAlbum, code == album.code else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        set("album_open")
        return true
    }

    /// Le joueur a touché la voiture sur cette photo.
    func spotCar(on photo: PhotoItem) {
        set("car_" + photo.id)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let all = (story.hiddenAlbum?.photos ?? []).filter { $0.car != nil }
        if !all.isEmpty, all.allSatisfy({ has("car_" + $0.id) }) { set("car_all") }
    }

    var carsSpotted: Int { (story.hiddenAlbum?.photos ?? []).filter { has("car_" + $0.id) }.count }
    var carsTotal: Int { (story.hiddenAlbum?.photos ?? []).filter { $0.car != nil }.count }

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
        showChapterEnd = nil
        showPaywall = false
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
