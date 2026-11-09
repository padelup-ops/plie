import SwiftUI
import AVFoundation

// MARK: - Waffle Fold

@main
struct WaffleApp: App {
    @State private var store = Store()
    @State private var progress = Career()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(progress)
                .task { await store.start() }
                .preferredColorScheme(.light)
                .statusBarHidden()
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

/// Les couleurs du jeu.
enum Ink {
    static let line = Color(hex: 0x3B2418)
    static let cream = Color(hex: 0xFFF6E6)
    static let paper = Color(hex: 0xFFFDF8)
    static let orange = Color(hex: 0xFF8A3D)
    static let red = Color(hex: 0xE8453C)
    static let green = Color(hex: 0x5BC25A)
    static let gold = Color(hex: 0xFFC93C)
    static let wood = Color(hex: 0xC98A4E)
    static let woodDark = Color(hex: 0x8A5530)
}

extension Font {
    static func toon(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// Bouton cartoon : couleur pleine, contour brun, et une épaisseur dessous qui s'écrase quand on appuie.
struct ToonButton: ButtonStyle {
    var color: Color = Ink.orange
    var text: Color = .white
    var radius: CGFloat = 20
    var depth: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .foregroundStyle(text)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius).fill(color)
                    RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.line, lineWidth: 3)
                }
            )
            .offset(y: down ? depth : 0)
            .background(
                RoundedRectangle(cornerRadius: radius).fill(Ink.line).offset(y: depth)
            )
            .scaleEffect(down ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: down)
    }
}

/// Une étiquette ronde (pastilles du haut de l'écran).
struct Pill<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 6) { content() }
            .font(.toon(17))
            .foregroundStyle(Ink.line)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(Ink.paper))
            .overlay(Capsule().strokeBorder(Ink.line, lineWidth: 3))
            .background(Capsule().fill(Ink.line).offset(y: 3))
    }
}

// MARK: - Sons et vibrations

enum Sound: String {
    case pop, chime, win, wrong, clack, clunk, whoosh, bell, applause, tock, buzzer, chomp, sizzle

    private static var players: [Sound: AVAudioPlayer] = [:]
    private static var loopPlayer: AVAudioPlayer?

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

    static func loop(_ s: Sound, volume: Float = 1) {
        stopLoop()
        guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = volume
        p.play()
        loopPlayer = p
    }

    static func stopLoop() {
        loopPlayer?.stop()
        loopPlayer = nil
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - La charnière de l'iPhone Duo

/// La charnière du Duo : fermé ou ouvert (si iOS le sait) et l'angle.
struct HingeReader: ViewModifier {
    let action: (Bool?, Double?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, ctx in
                guard let hinge = ctx.hinge else { action(nil, nil); return }
                let closed: Bool? = hinge.status == .closed ? true : (hinge.status == .fullyOpen || hinge.status == .partiallyOpen ? false : nil)
                action(closed, hinge.angle.degrees)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func onHinge(_ action: @escaping (Bool?, Double?) -> Void) -> some View { modifier(HingeReader(action: action)) }
}

// MARK: - L'écran principal

enum Screen: Equatable {
    case menu
    case play(day: Int)
    case rush
    case free
}

struct RootView: View {
    @Environment(Store.self) private var store
    @State private var screen: Screen = .menu
    @State private var showPaywall = false
    @State private var showBook = false
    @State private var showDecor = false

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MenuView(onPlay: { day in
                    if day > Kitchen.freeDays && !store.purchased { showPaywall = true } else { screen = .play(day: day) }
                }, onRush: {
                    if store.purchased { screen = .rush } else { showPaywall = true }
                }, onShop: { showPaywall = true },
                   onFree: { screen = .free }, onBook: { showBook = true }, onDecor: { showDecor = true })
                .transition(.opacity)
            case .play(let day):
                KitchenView(kitchen: Kitchen(day: day), onExit: { screen = .menu }, onNext: {
                    let next = day + 1
                    if next > Kitchen.lastDay { screen = .menu }
                    else if next > Kitchen.freeDays && !store.purchased { screen = .menu; showPaywall = true }
                    else { screen = .play(day: next) }
                })
                .id(day)
                .transition(.opacity)
            case .rush:
                KitchenView(kitchen: Kitchen(day: Kitchen.lastDay, rush: true), onExit: { screen = .menu }, onNext: { screen = .menu })
                    .id("rush")
                    .transition(.opacity)
            case .free:
                KitchenView(kitchen: Kitchen(day: Kitchen.lastDay, free: true), onExit: { screen = .menu }, onNext: { screen = .menu })
                    .id("free")
                    .transition(.opacity)
            }
            if showBook {
                RecipeBookView(onClose: { showBook = false }).transition(.move(edge: .bottom))
            }
            if showDecor {
                DecorView(onClose: { showDecor = false }).transition(.move(edge: .bottom))
            }
            if showPaywall {
                PaywallView(onClose: { showPaywall = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .animation(.easeInOut(duration: 0.2), value: showPaywall)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showBook)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDecor)
        .onChange(of: store.purchased) { _, owned in if owned { showPaywall = false } }
        .onAppear {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "shot") ?? "" {
            case "paywall": showPaywall = true
            case "free", "created": screen = .free
            case "book": showBook = true
            case "decor": showDecor = true
            case "ready", "pour", "poured", "assemble", "topping", "cook", "closed", "result", "summary": screen = .play(day: 3)
            default: break
            }
            #endif
        }
    }
}
