import SwiftUI
import AVFoundation

// MARK: - Peekaclaw

@main
struct PinceApp: App {
    @State private var game = Game()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(game)
                .preferredColorScheme(.light)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .onChange(of: scenePhase) { _, phase in game.setActive(phase == .active) }
        }
    }
}

enum Lang {
    static let french: Bool = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")
}

func T(_ fr: String, _ en: String) -> String { Lang.french ? fr : en }

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Les couleurs du jeu (les mêmes pour la machine en 3D et pour les boutons).
enum Tint {
    static let cream: UInt32 = 0xFFF6EA
    static let paper: UInt32 = 0xFFFDF8
    static let coral: UInt32 = 0xFF8FA3
    static let rose: UInt32 = 0xF2647E
    static let plum: UInt32 = 0x6A3B5C
    static let mint: UInt32 = 0xA8E6CF
    static let butter: UInt32 = 0xFFE08A
    static let sky: UInt32 = 0x9AD4F5
    static let lilac: UInt32 = 0xC9B6F2
    static let floor: UInt32 = 0xBDB4F0
    static let gold: UInt32 = 0xFFC93C
}

extension Font {
    static func toon(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

// MARK: - Sons et vibrations

enum Sound: String {
    case pop, coin, clack, win, aww, plop, motor, music

    private static var players: [Sound: AVAudioPlayer] = [:]

    private static func player(_ s: Sound) -> AVAudioPlayer? {
        if let p = players[s] { return p }
        guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[s] = p
        return p
    }

    static func play(_ s: Sound, volume: Float = 1) {
        guard let p = player(s) else { return }
        p.volume = volume
        p.currentTime = 0
        p.play()
    }

    /// Lance ou arrête un son qui tourne en boucle (le moteur de la pince, la musique).
    static func loop(_ s: Sound, on: Bool, volume: Float = 1) {
        guard let p = player(s) else { return }
        if on {
            guard !p.isPlaying else { return }
            p.numberOfLoops = -1
            p.volume = volume
            p.play()
        } else if p.isPlaying {
            p.pause()
        }
    }
}

/// Les vibrations. Chaque moment de la partie a la sienne : on sent la pince travailler sans regarder.
enum Haptics {
    static var enabled = true

    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()

    private static func hit(_ generator: UIImpactFeedbackGenerator, _ strength: CGFloat, after delay: Double = 0) {
        guard enabled else { return }
        if delay == 0 {
            generator.impactOccurred(intensity: strength)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if enabled { generator.impactOccurred(intensity: strength) }
            }
        }
    }

    /// Un bouton de l'interface.
    static func tap() { hit(light, 0.7) }
    /// Le gros bouton rouge : la pince part.
    static func press() { hit(medium, 1); heavy.prepare(); rigid.prepare() }
    /// Le treuil qui tourne : un petit cran, répété tant que la pince bouge.
    static func tick(_ strength: CGFloat) { hit(soft, strength) }
    /// Les griffes se referment : un claquement sec.
    static func clack() { hit(rigid, 0.9) }
    /// Un doudou est pris : un choc franc, puis son poids au bout du câble.
    static func grab() { hit(heavy, 1); hit(soft, 0.8, after: 0.13) }
    /// Les griffes se referment sur rien : deux petits coups dans le vide.
    static func miss() { hit(light, 0.6, after: 0.05); hit(soft, 0.4, after: 0.17) }
    /// Le doudou glisse et retombe.
    static func slip() {
        guard enabled else { return }
        notice.notificationOccurred(.warning)
        hit(medium, 0.7, after: 0.42)
    }
    /// La pince s'ouvre au-dessus de la trappe.
    static func release() { hit(light, 0.8) }
    /// Le doudou tombe dans le bac.
    static func plop() { hit(heavy, 0.85); hit(soft, 0.5, after: 0.1) }
    /// Gagné.
    static func success() { if enabled { notice.notificationOccurred(.success) } }
    /// De nouveaux doudous tombent dans la machine.
    static func rain() {
        for i in 0..<5 { hit(soft, 0.55, after: 0.35 + Double(i) * 0.09) }
    }
}

// MARK: - La partie

struct Prize: Equatable {
    let species: Species
    let isNew: Bool
    let reward: Int
}

/// Tout ce qui dure : les pièces, la collection, les réglages. Relie la machine, le suivi de la tête et l'écran.
@Observable
final class Game {
    static let cost = 10
    static let gift = 60

    var coins: Int
    var owned: [String: Int]
    var busy = false
    var prize: Prize?
    var lastPrize: Species?
    var delta: Int?
    var deltaTick = 0
    var soundOn: Bool
    var musicOn: Bool
    var hapticsOn: Bool
    /// Avance d'un cran à chaque doudou gagné : le bac du pupitre s'anime.
    var winTick = 0
    /// 0 : à plat, 1 : relief normal, 2 : relief accentué.
    var depth: Int
    var introSeen: Bool
    var tracking: HeadTracker.Mode = .none
    /// Le visage est-il vu par la caméra, et à combien de centimètres ?
    var faceSeen = false
    var faceDistance = 0
    /// Vrai : suivre le visage avec la caméra ordinaire, sans passer par le capteur 3D.
    var simpleCamera: Bool
    var showCollection = false
    var showSettings = false

    let machine = Machine()
    let tracker = HeadTracker()
    private var active = true
    private var winchTimer: Timer?
    /// Vrai pendant une mise en scène pour les captures : le point de vue est imposé, rien n'est enregistré.
    private var staged = false
    private let store = UserDefaults.standard

    init() {
        coins = store.object(forKey: "coins") as? Int ?? 150
        owned = store.dictionary(forKey: "owned") as? [String: Int] ?? [:]
        soundOn = store.object(forKey: "soundOn") as? Bool ?? true
        musicOn = store.object(forKey: "musicOn") as? Bool ?? true
        simpleCamera = store.bool(forKey: "simpleCamera")
        let haptics = store.object(forKey: "hapticsOn") as? Bool ?? true
        hapticsOn = haptics
        Haptics.enabled = haptics
        depth = store.object(forKey: "depth") as? Int ?? 1
        introSeen = store.bool(forKey: "introSeen")
        if let last = store.string(forKey: "lastPrize") { lastPrize = Species(rawValue: last) }

        machine.onEvent = { [weak self] event in self?.handle(event) }
        tracker.onEye = { [weak self] eye in self?.machine.setEye(eye) }
        tracker.onMode = { [weak self] mode in self?.tracking = mode }
        tracker.onSeen = { [weak self] seen, distance in
            self?.faceSeen = seen
            self?.faceDistance = Int((distance * 100).rounded())
        }
        tracker.prefersCamera = simpleCamera
        machine.setGain(gain)

        #if DEBUG
        if let shot = store.string(forKey: "shot"), !shot.isEmpty { stage(shot); return }
        #endif
        if introSeen { begin() }
    }

    private var gain: Float { depth == 0 ? 0 : (depth == 1 ? 1 : 1.7) }

    var collected: Int { Species.allCases.filter { (owned[$0.rawValue] ?? 0) > 0 }.count }
    var canDrop: Bool { !busy && prize == nil && coins >= Game.cost }
    var broke: Bool { !busy && coins < Game.cost }

    /// Après l'écran d'accueil : la musique et le suivi de la tête démarrent.
    func begin() {
        if !introSeen {
            introSeen = true
            store.set(true, forKey: "introSeen")
        }
        if depth > 0, !staged { tracker.start() }
        Sound.loop(.music, on: musicOn && active, volume: 0.35)
    }

    func setActive(_ on: Bool) {
        active = on
        machine.setStick(.zero)
        guard introSeen else { return }
        if on {
            if depth > 0, !staged { tracker.start() }
        } else {
            tracker.stop()
            Sound.loop(.motor, on: false)
            winch(false)
        }
        Sound.loop(.music, on: on && musicOn, volume: 0.35)
    }

    func stick(_ v: CGSize) {
        machine.setStick(SIMD2<Float>(Float(v.width), Float(v.height)))
    }

    func drop() {
        guard canDrop else { return }
        coins -= Game.cost
        flash(-Game.cost)
        save()
        say(.coin)
        Haptics.press()
        busy = true
        machine.drop()
    }

    func takeGift() {
        guard broke else { return }
        coins += Game.gift
        flash(Game.gift)
        save()
        say(.coin)
        Haptics.success()
    }

    func closePrize() {
        prize = nil
        say(.pop)
        Haptics.tap()
    }

    func setHaptics(_ on: Bool) {
        hapticsOn = on
        Haptics.enabled = on
        if on { Haptics.grab() } else { winch(false) }
        save()
    }

    /// Le treuil : de petits crans tant que la pince se déplace, plus marqués quand elle descend ou remonte.
    private func winch(_ on: Bool) {
        winchTimer?.invalidate()
        winchTimer = nil
        guard on, hapticsOn, active else { return }
        winchTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
            Haptics.tick(self?.busy == true ? 0.42 : 0.25)
        }
    }

    func setSound(_ on: Bool) {
        soundOn = on
        if !on { Sound.loop(.motor, on: false) }
        save()
    }

    func setMusic(_ on: Bool) {
        musicOn = on
        Sound.loop(.music, on: on, volume: 0.35)
        save()
    }

    func setDepth(_ d: Int) {
        depth = d
        machine.setGain(gain)
        if d == 0 {
            tracker.stop()
            machine.setEye(nil)
        } else if !staged {
            tracker.start()
        }
        save()
    }

    func setSimpleCamera(_ on: Bool) {
        simpleCamera = on
        tracker.prefersCamera = on
        if depth > 0, !staged {
            tracker.stop()
            tracker.start()
        }
        save()
    }

    func recenter() {
        tracker.recenter()
        say(.pop)
        Haptics.tap()
    }

    func say(_ s: Sound, volume: Float = 1) {
        if soundOn { Sound.play(s, volume: volume) }
    }

    private func flash(_ amount: Int) {
        delta = amount
        deltaTick += 1
        let tick = deltaTick
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            if self?.deltaTick == tick { self?.delta = nil }
        }
    }

    private func handle(_ event: Machine.Event) {
        switch event {
        case .busy(let on):
            busy = on
        case .motor(let on):
            Sound.loop(.motor, on: on && soundOn && active, volume: 0.22)
            winch(on)
        case .clack:
            say(.clack)
            Haptics.clack()
        case .grabbed:
            Haptics.grab()
        case .missed:
            Haptics.miss()
        case .slipped:
            say(.aww, volume: 0.8)
            Haptics.slip()
        case .released:
            Haptics.release()
        case .restocked:
            say(.pop, volume: 0.6)
            Haptics.rain()
        case .plop:
            say(.plop)
            Haptics.plop()
        case .won(let species):
            winTick += 1
            let isNew = (owned[species.rawValue] ?? 0) == 0
            owned[species.rawValue, default: 0] += 1
            coins += species.rarity.reward
            lastPrize = species
            save()
            // Le doudou tombe dans la trappe, puis la carte arrive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.prize = Prize(species: species, isNew: isNew, reward: species.rarity.reward)
                self.flash(species.rarity.reward)
                self.say(.win)
                Haptics.success()
            }
        }
    }

    private func save() {
        guard !staged else { return }
        store.set(coins, forKey: "coins")
        store.set(owned, forKey: "owned")
        store.set(soundOn, forKey: "soundOn")
        store.set(musicOn, forKey: "musicOn")
        store.set(hapticsOn, forKey: "hapticsOn")
        store.set(simpleCamera, forKey: "simpleCamera")
        store.set(depth, forKey: "depth")
        store.set(lastPrize?.rawValue, forKey: "lastPrize")
    }

    #if DEBUG
    /// Mises en scène pour les captures d'écran (`-shot side`, `-shot grab`…). Rien n'est enregistré.
    private func stage(_ shot: String) {
        staged = true
        introSeen = shot != "intro"
        coins = 240
        soundOn = false
        musicOn = false
        owned = ["frog": 3, "bunny": 1, "whale": 2, "mushroom": 1, "strawberry": 1]
        lastPrize = .bunny
        tracking = .face
        faceSeen = true
        faceDistance = 38
        switch shot {
        case "left": machine.setEye(SIMD3<Float>(-0.17, 0.05, 0.36))
        case "right": machine.setEye(SIMD3<Float>(0.17, 0.02, 0.36))
        case "high": machine.setEye(SIMD3<Float>(0.03, 0.2, 0.34))
        case "plain": machine.usePlainCamera()
        case "grab":
            machine.setEye(SIMD3<Float>(-0.1, 0.07, 0.36))
            machine.demo(freezeOnLift: true)
            busy = true
        case "win":
            machine.demo(freezeOnLift: false)
            busy = true
        case "collection": showCollection = true
        case "settings": showSettings = true
        case "all": owned = Dictionary(uniqueKeysWithValues: Species.allCases.map { ($0.rawValue, 1) }); showCollection = true
        default: break
        }
    }
    #endif
}
