import CoreMotion
import SwiftUI
import UIKit

// MARK: - Installation

struct SetupView: View {
    @Binding var done: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                step(1, "Open Foldboard’s page in Settings with the button below.")
                step(2, "Tap **Keyboards**, turn on **Foldboard**, then **Allow Full Access**.")
                step(3, "In any app, hold the globe key 🌐 under the keyboard and pick **Foldboard**.")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .listRowSeparator(.hidden)
            } header: {
                Text("3 steps")
            }

            Section {
                Label("Full Access is only used for vibrations, typing sounds and to share your settings between the app and the keyboard.", systemImage: "hand.raised")
                Label("Foldboard has no internet access: what you type stays on your iPhone.", systemImage: "wifi.slash")
            } header: {
                Text("Why Full Access?")
            }
            .font(.subheadline)

            Section {
                Toggle("Foldboard is set up", isOn: $done)
            }
        }
        .navigationTitle("Add the keyboard")
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Aperçu en bas des réglages

struct PreviewDock: View {
    @Environment(SettingsModel.self) private var model
    @Environment(Store.self) private var store
    @Environment(\.verticalSizeClass) private var vClass
    @State private var text = ""
    /// En paysage, l'aperçu se replie (sinon il cache tout) : on l'ouvre d'un toucher.
    @State private var open: Bool?
    /// Replié au départ (premier lancement : les réglages d'abord).
    var startClosed = false
    @State private var width: CGFloat = 0

    /// Assez de hauteur pour l'aperçu (pas en paysage sur le Duo ni sur l'iPhone).
    private var roomy: Bool {
        _ = width
        if vClass == .compact { return false }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let h = scene?.windows.first { $0.isKeyWindow }?.bounds.height ?? 800
        return h >= 600
    }

    private var shown: Bool { open ?? (roomy && !startClosed) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(text.isEmpty ? NSLocalizedString("Preview: try the keys", comment: "") : text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                Spacer()
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { open = !shown }
                } label: {
                    Image(systemName: shown ? "keyboard.chevron.compact.down" : "keyboard")
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            if shown {
                KeyboardPreview(settings: model.settings, pro: true, text: $text) { s in model.settings = s }
                    .frame(height: KeyboardPreview.height(model.settings))
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Color(.systemBackground))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            if w != width { width = w; open = nil }
        }
    }
}

/// L'écran entier du Duo : l'écran intérieur réserve une colonne d'un seul côté (appareil photo, heure) ;
/// l'app passe dessous. Les marges d'un iPhone classique (des deux côtés, ou en haut) ne bougent pas.
struct DuoFullWidth: ViewModifier {
    @State private var edges: Edge.Set = []

    /// Réglage d'essai (captures sur simulateur) : façon de garder les marges des listes égales des deux côtés.
    static var variant: String { UserDefaults.standard.string(forKey: "duoVariant") ?? "d" }

    @ViewBuilder
    private func fitted(_ content: Content) -> some View {
        switch Self.variant {
        case "a":
            content.ignoresSafeArea(.container, edges: edges)
        case "b":
            content.contentMargins(.horizontal, edges.isEmpty ? nil : 20, for: .scrollContent)
                .ignoresSafeArea(.container, edges: edges)
        case "c":
            content.safeAreaPadding(edges, edges.isEmpty ? 0 : 20)
                .ignoresSafeArea(.container, edges: edges)
        default:
            content.contentMargins(edges, edges.isEmpty ? nil : 20, for: .scrollContent)
                .ignoresSafeArea(.container, edges: edges)
        }
    }

    func body(content: Content) -> some View {
        fitted(content)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { update(g.safeAreaInsets) }
                    .onChange(of: g.safeAreaInsets) { _, v in update(v) }
            })
            .statusBarHidden(true)
    }

    private func update(_ i: EdgeInsets) {
        var e: Edge.Set = []
        if i.trailing > 30 && i.leading < 8 { e.insert(.trailing) }
        if i.leading > 30 && i.trailing < 8 { e.insert(.leading) }
        if e != edges { edges = e }
    }
}

/// Apprend la largeur de chaque écran du Duo (la charnière dit lequel est utilisé) : le clavier, qui ne voit pas
/// la charnière dans les autres apps, s'en sert pour savoir s'il est sur l'écran extérieur ou intérieur.
/// Le petit côté de l'écran utilisé, en pixels.
func kbNativeShort() -> Double? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return nil }
    let b = scene.screen.nativeBounds
    return b.width > 0 ? Double(min(b.width, b.height)) : nil
}

struct ScreenLearner: ViewModifier {
    @Environment(SettingsModel.self) private var model
    @State private var closed: Bool?

    func body(content: Content) -> some View {
        content
            .modifier(HingeWatch { c in closed = c; learn() })
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in learn() }
    }

    private func learn() {
        guard let closed else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let size = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?.bounds.size,
              size.width > 0, size.height > 0 else { return }
        let short = Double(min(size.width, size.height))
        let px = scene.map { Double(min($0.screen.nativeBounds.width, $0.screen.nativeBounds.height)) } ?? 0
        let key = closed ? "closed" : "open"
        guard abs((model.settings.screenWidths[key] ?? 0) - short) > 1
                || (px > 0 && abs((model.settings.screenWidths[key + "Px"] ?? 0) - px) > 1) else { return }
        var s = model.settings
        s.screenWidths[key] = short
        if px > 0 { s.screenWidths[key + "Px"] = px }
        model.settings = s
    }
}

extension View {
    /// Tout l'écran du Duo, sans la colonne de l'heure (l'heure est masquée dans l'app).
    func fullScreenDuo() -> some View { modifier(DuoFullWidth()) }
}

extension KeyboardPreview {
    static func height(_ s: KBSettings) -> CGFloat {
        KeyboardCanvas.topBarHeight + 6 + 4 * CGFloat(s.keyHeight) + 30 + 8
    }
}

/// Un rappel discret : ce réglage ne s'applique qu'avec Foldboard Pro (ou pendant l'essai).
struct ProBadge: View {
    @Environment(Store.self) private var store
    var body: some View {
        if !store.isPro {
            Text("Pro")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor))
        }
    }
}

// MARK: - Position et taille

struct PositionView: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                Picker("Layout", selection: $m.settings.layout) {
                    ForEach(KBLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Layout")
            }

            Section {
                ForEach(KBMode.allCases) { mode in
                    Button {
                        m.settings.mode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modeTitle(mode)).foregroundStyle(.primary)
                                Text(modeDetail(mode)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if mode == .auto || mode == .split { ProBadge() }
                            if m.settings.mode == mode { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            } header: {
                Text("Position")
            }

            if m.settings.mode == .auto {
                TiltCalibration()
            }

            Section {
                slider("One-hand width", value: $m.settings.oneHandWidth, in: 0.45...0.95, format: { "\(Int($0 * 100)) %" })
                slider("One-hand width, Duo open", value: $m.settings.oneHandWidthOpen, in: 0.4...0.9, format: { "\(Int($0 * 100)) %" })
                slider("Two-hand width (each side)", value: $m.settings.splitWidth, in: 0.22...0.48, format: { "\(Int($0 * 100)) %" })
                slider("Distance from the edge", value: $m.settings.edgeMargin, in: 0...120, format: { "\(Int($0)) pt" })
                slider("Key height", value: $m.settings.keyHeight, in: 34...60, format: { "\(Int($0)) pt" })
            } header: {
                Text("Size")
            } footer: {
                Text("The keyboard can also be moved from its top bar: tap the position button, or the arrows to switch sides.")
            }
        }
        .navigationTitle("Position and size")
        .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }

    private func modeTitle(_ m: KBMode) -> LocalizedStringKey {
        switch m {
        case .auto: return "Follows your hand"
        case .left: return "One hand, left"
        case .right: return "One hand, right"
        case .full: return "Full width"
        case .split: return "Two hands"
        }
    }

    private func modeDetail(_ m: KBMode) -> LocalizedStringKey {
        switch m {
        case .auto: return "Comes to the hand holding the phone. Both hands: split on the open Duo, full width on the outer screen."
        case .left: return "For your left thumb."
        case .right: return "For your right thumb."
        case .full: return "The classic keyboard, edge to edge."
        case .split: return "Two halves at both edges of the open Duo."
        }
    }
}

func slider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(title)
            Spacer()
            Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
        }
        Slider(value: value, in: range)
    }
}

// MARK: - Couleurs et police

struct LookView: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                    ForEach(KBTheme.all) { t in
                        Button { m.settings.theme = t.id } label: {
                            VStack(spacing: 6) {
                                ThemeSwatch(theme: t)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: m.settings.theme == t.id ? 3 : 0))
                                Text(LocalizedStringKey(t.name)).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                HStack { Text("Colors"); ProBadge() }
            }

            Section {
                Picker("Font", selection: $m.settings.font) {
                    ForEach(KBFont.allCases) { f in
                        Text(fontName(f)).font(.system(size: 17, design: f.design)).tag(f)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                HStack { Text("Font"); ProBadge() }
            }
        }
        .navigationTitle("Colors and font")
        .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }

    private func fontName(_ f: KBFont) -> LocalizedStringKey {
        switch f {
        case .system: return "Classic"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        }
    }
}

struct ThemeSwatch: View {
    let theme: KBTheme
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(theme.id == "glass"
                  ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.95), Color(red: 0.62, green: 0.38, blue: 0.86)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(Color(uiColor: theme.background)))
            .frame(height: 58)
            .overlay(
                VStack(spacing: 4) {
                    HStack(spacing: 4) { ForEach(0..<4, id: \.self) { _ in key(Color(uiColor: theme.key)) } }
                    HStack(spacing: 4) {
                        key(Color(uiColor: theme.special))
                        key(Color(uiColor: theme.key)).frame(width: 30)
                        key(Color(uiColor: theme.accent))
                    }
                }
                .padding(8)
            )
    }

    private func key(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(height: 16)
    }
}

// MARK: - Son, vibrations, glissement

struct FeelView: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                slider("Vibration strength", value: $m.settings.haptics, in: 0...1, format: { $0 < 0.01 ? NSLocalizedString("Off", comment: "") : "\(Int($0 * 100)) %" })
            } header: {
                HStack { Text("Vibrations"); ProBadge() }
            } footer: {
                Text("Vibrations and sounds need Full Access in the keyboard settings.")
            }

            Section {
                Picker("Typing sound", selection: $m.settings.sound) {
                    ForEach(KBSound.allCases) { s in Text(soundName(s)).tag(s) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: m.settings.sound) { _, s in KBFeedback.shared.tap(sound: s, haptics: m.settings.haptics) }
            } header: {
                HStack { Text("Typing sound"); ProBadge() }
            } footer: {
                Text("Sounds follow the silent switch of your iPhone.")
            }

            Section {
                slider("Swipe sensitivity", value: $m.settings.swipe, in: 0...1, format: { "\(Int($0 * 100)) %" })
            } header: {
                HStack { Text("Swipe on the space bar"); ProBadge() }
            } footer: {
                Text("Slide your thumb on the space bar to move the cursor. Higher is faster.")
            }
        }
        .navigationTitle("Sound, vibrations and swipe")
        .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }

    private func soundName(_ s: KBSound) -> LocalizedStringKey {
        switch s {
        case .off: return "Off"
        case .click: return "Click"
        case .soft: return "Soft"
        case .pop: return "Pop"
        case .wood: return "Wood"
        }
    }
}

// MARK: - Phrases et emojis

struct PhrasesView: View {
    @Environment(SettingsModel.self) private var model
    @State private var newPhrase = ""
    @State private var emojiText = ""

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                ForEach(Array(m.settings.phrases.enumerated()), id: \.offset) { item in
                    Text(item.element)
                }
                .onDelete { m.settings.phrases.remove(atOffsets: $0) }
                .onMove { m.settings.phrases.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("New phrase", text: $newPhrase)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                HStack { Text("Your phrases"); ProBadge() }
            } footer: {
                Text("They show above the keys: one tap writes the whole phrase.")
            }

            Section {
                TextField("Emoji", text: $emojiText)
                    .font(.title2)
                    .onChange(of: emojiText) { _, t in
                        let list = t.filter { $0.isEmojiLike }.map(String.init)
                        if !list.isEmpty { m.settings.emojis = Array(list.prefix(24)) }
                    }
                Button("Back to the default emoji") {
                    m.settings.emojis = KBSettings.defaultEmojis
                    emojiText = KBSettings.defaultEmojis.joined()
                }
            } header: {
                HStack { Text("Emoji next to the keys"); ProBadge() }
            } footer: {
                Text("In one-hand mode, the free space next to the keyboard shows these emoji (up to 24).")
            }

            Section {
                Picker("Next to the keyboard", selection: $m.settings.sidePanel) {
                    Text("Emoji").tag(KBSidePanel.emoji)
                    Text("Phrases").tag(KBSidePanel.phrases)
                    Text("Nothing").tag(KBSidePanel.none)
                }
            }
        }
        .navigationTitle("Phrases and emoji")
        .toolbar { EditButton() }
        .onAppear { emojiText = model.settings.emojis.joined() }
        .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }

    private func add() {
        let p = newPhrase.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        model.settings.phrases.append(p)
        newPhrase = ""
    }
}

extension Character {
    var isEmojiLike: Bool {
        guard let s = unicodeScalars.first else { return false }
        return s.properties.isEmojiPresentation || (s.properties.isEmoji && unicodeScalars.count > 1)
    }
}

// MARK: - Écriture

struct TypingView: View {
    @Environment(SettingsModel.self) private var model

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                Toggle("Auto-correction", isOn: $m.settings.autocorrect)
                Toggle("Slide to type", isOn: $m.settings.glide)
                Toggle("Word suggestions", isOn: $m.settings.suggestions)
                Toggle("Capital letter at the start of a sentence", isOn: $m.settings.autoCaps)
                Toggle("Double space adds a period", isOn: $m.settings.doubleSpacePeriod)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hold a letter for its accents (é, è, à, ç…). Hold delete to erase word by word.")
                    Text("Word lists: FrequencyWords by Hermit Dave, CC BY-SA 4.0.").font(.caption2)
                    Text("Language model: Leipzig Corpora Collection, CC BY 4.0.").font(.caption2)
                }
            }
        }
        .navigationTitle("Typing")
        .safeAreaInset(edge: .bottom, spacing: 0) { PreviewDock() }
    }
}

// MARK: - Foldboard Pro

struct ProView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                    Text("Foldboard Pro").font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 12) {
                        feature("rectangle.split.2x1", "Two hands", "Two halves at both edges of the open Duo.")
                        feature("hand.raised.fingers.spread", "Follows your hand", "The keyboard comes to the hand holding the phone, or splits for two hands.")
                        feature("paintpalette", "Colors and fonts", "8 color themes and 4 fonts.")
                        feature("text.bubble", "Your phrases and emoji", "Write your usual phrases in one tap.")
                        feature("waveform", "Sounds, vibrations, swipe", "Pick the sound, the vibration strength and the cursor speed.")
                    }
                    Text("One-hand left and right, full width, AZERTY and QWERTY stay free forever.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if store.access.purchased {
                        Label("Foldboard Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                    } else {
                        if store.access.trialStart == nil {
                            Button {
                                Task { await store.buy(KBProducts.trial) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text("Start the 3-day free trial").font(.headline)
                                    Text("Free, nothing renews").font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if let end = store.access.trialEnd, store.isPro {
                            Text(String(format: NSLocalizedString("Free trial until %@", comment: ""), end.formatted(date: .abbreviated, time: .shortened)))
                                .font(.subheadline.weight(.semibold))
                        }
                        if store.access.trialStart == nil {
                            buyButton.buttonStyle(.bordered)
                        } else {
                            buyButton.buttonStyle(.borderedProminent)
                        }
                        Text("One payment, yours forever. No subscription.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    if store.busy { ProgressView().frame(maxWidth: .infinity) }
                    if let msg = store.message {
                        Text(msg).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await store.load() }
        }
    }

    private var buyButton: some View {
        Button {
            Task { await store.buy(KBProducts.pro) }
        } label: {
            Text(buyTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    private var buyTitle: String {
        let price = store.price(KBProducts.pro) ?? ""
        return price.isEmpty ? NSLocalizedString("Unlock Foldboard Pro", comment: "")
            : String(format: NSLocalizedString("Unlock Foldboard Pro for %@", comment: ""), price)
    }

    private func feature(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

extension KBFont {
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

// MARK: - Étalonnage de la prise en main (clavier qui suit la main)

@Observable
final class TiltReader {
    var roll: Double?
    var incline: Double?
    /// Change à chaque mesure : l'écran relit alors la fenêtre (Duo plié / déplié, rotation).
    var tick = 0
    @ObservationIgnored private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let planar = (g.x * g.x + g.y * g.y).squareRoot()
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            let a = kbWrap(atan2(g.x, -g.y) * 180 / .pi - kbAngleOffset(scene?.interfaceOrientation))
            let i = asin(max(-1, min(1, -g.z))) * 180 / .pi
            self.roll = planar > 0.2 ? (self.roll.map { kbWrap($0 + kbWrap(a - $0) * 0.2) } ?? a) : nil
            self.incline = self.incline.map { $0 * 0.8 + i * 0.2 } ?? i
            self.tick &+= 1
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

struct TiltCalibration: View {
    @Environment(SettingsModel.self) private var model
    @State private var reader = TiltReader()

    /// La situation choisie à la main dans la liste (sinon celle détectée).
    @State private var picked: String?

    /// La situation détectée : Duo fermé ou ouvert, portrait ou paysage (d'après la fenêtre active).
    private var detected: String {
        _ = reader.tick
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        let size = window?.bounds.size ?? scene?.screen.bounds.size ?? .zero
        return KBSettings.context(screen: size, closed: hingeClosed, known: model.settings.screenWidths, native: kbNativeShort())
    }

    /// La charnière du Duo (fermé / ouvert), lue par l'API d'Apple quand elle existe.
    @State private var hingeClosed: Bool?

    /// La situation qu'on étalonne.
    private var context: String { picked ?? detected }

    /// La prise qu'on enregistre (feuille d'étalonnage par la frappe).
    @State private var recordingGrip: KBGrip?

    var body: some View {
        Section {
            HStack {
                Label(contextName(context), systemImage: context.hasPrefix("open") ? "rectangle.portrait.split.2x1" : "iphone")
                    .font(.headline)
                Spacer()
                Text(reader.roll.map { String(format: "%+.0f°", $0) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
            }
            .fullScreenCover(item: $recordingGrip) { g in
                GripRecorder(grip: g, context: context).environment(model)
            }
            button("Right hand", "hand.point.right", grip: .right)
            button("Left hand", "hand.point.left", grip: .left)
            button("Both hands", "hands.clap", grip: .two)
        } header: {
            HStack { Text("Follow your hand"); ProBadge() }
        } footer: {
            Text("For each grip, hold the phone as you usually do and type a short sentence: Foldboard learns how the phone moves under your thumb. Do it closed and open, in portrait and in landscape if you type that way: Foldboard keeps a calibration for each.")
        }

        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
        .modifier(HingeWatch { hingeClosed = $0 })

        Section {
            ForEach(KBSettings.contexts, id: \.self) { c in
                let n = model.settings.calib[c]?.count ?? 0
                Button {
                    picked = c == detected ? nil : c
                } label: {
                    HStack {
                        Image(systemName: c == context ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(c == context ? Color.accentColor : Color.secondary)
                        Text(contextName(c)).foregroundStyle(.primary)
                        if c == detected { Image(systemName: "location.fill").font(.caption).foregroundStyle(Color.accentColor) }
                        Spacer()
                        Text(n == 0 ? NSLocalizedString("Not calibrated", comment: "") : String(format: NSLocalizedString("%lld of 3", comment: ""), n))
                            .foregroundStyle(n == 3 ? .green : .secondary)
                    }
                }
            }
            if !model.settings.calib.isEmpty || !model.settings.learned.isEmpty {
                Button(role: .destructive) {
                    var s = model.settings
                    s.resetCalibration()
                    model.settings = s
                } label: {
                    Label("Reset calibration", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Calibrations")
        } footer: {
            Text("Tap a situation to calibrate it. The arrow shows the one detected right now. For landscape, turn off the rotation lock.")
        }
    }

    private func contextName(_ c: String) -> String {
        switch c {
        case "open-portrait": return NSLocalizedString("Open · portrait", comment: "")
        case "open-landscape": return NSLocalizedString("Open · landscape", comment: "")
        case "closed-landscape": return NSLocalizedString("Closed · landscape", comment: "")
        default: return NSLocalizedString("Closed · portrait", comment: "")
        }
    }

    private func button(_ title: LocalizedStringKey, _ icon: String, grip: KBGrip) -> some View {
        let n = model.settings.taps[context]?[grip.rawValue]?.count ?? 0
        let done = n >= GripRecorder.needed || (n == 0 && model.settings.calib[context]?[grip.rawValue] != nil)
        return Button {
            recordingGrip = grip
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if n >= GripRecorder.needed {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                } else if done {
                    Text("Redo").font(.footnote).foregroundStyle(.orange)
                } else {
                    Text("Calibrate").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Suit la charnière du Duo : fermé (true), ouvert (false), inconnue (nil).
struct HingeWatch: ViewModifier {
    let action: (Bool?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                switch context.hinge?.status {
                case .closed?: action(true)
                case .partiallyOpen?, .fullyOpen?: action(false)
                default: action(nil)
                }
            }
        } else {
            content
        }
    }
}

extension KBGrip: Identifiable {
    var id: String { rawValue }
}

/// L'étalonnage par la frappe : on tient le téléphone comme d'habitude et on tape une petite phrase.
/// Chaque appui enregistre comment le téléphone bouge sous le pouce, son inclinaison, la position et la taille du toucher.
struct GripRecorder: View {
    let grip: KBGrip
    let context: String
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var samples: [[Double]] = []
    @State private var kbWidth: CGFloat = 0
    @State private var swipes: [[Double]] = []
    static let needed = 16
    /// Puis quelques glissements du pouce vers le haut (le geste le plus sûr pour reconnaître la main).
    private var swipesNeeded: Int { grip == .two ? 0 : 5 }
    private var typingDone: Bool { samples.count >= Self.needed }
    private var allDone: Bool { typingDone && swipes.count >= swipesNeeded }

    private var fr: Bool { Locale.current.language.languageCode?.identifier == "fr" }

    private var title: LocalizedStringKey {
        switch grip {
        case .right: return "Right hand"
        case .left: return "Left hand"
        case .two: return "Both hands"
        }
    }

    private var instruction: LocalizedStringKey {
        switch grip {
        case .right: return "Hold the phone in your right hand and type with your right thumb."
        case .left: return "Hold the phone in your left hand and type with your left thumb."
        case .two: return "Hold the phone with both hands and type with both thumbs."
        }
    }

    private var sentence: String {
        fr ? "bonjour, je tape avec mon pouce sur foldboard" : "hello, i am typing with my thumb on foldboard"
    }

    /// Toute la largeur pendant l'enregistrement : des appuis partout, quelle que soit la main.
    private var recordSettings: KBSettings {
        var s = model.settings
        s.mode = .full
        s.autocorrect = false
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.title2.bold())
                    Spacer()
                    Button("Cancel") { dismiss() }
                }
                Text(instruction).foregroundStyle(.secondary)
                if typingDone && swipesNeeded > 0 {
                    Label("Now slide your thumb up across the keys, 5 times, holding the phone the same way.", systemImage: "hand.draw")
                        .font(.title3.weight(.semibold))
                        .padding(.vertical, 4)
                } else {
                    Text(sentence)
                        .font(.title3.weight(.semibold))
                        .padding(.vertical, 4)
                }
                Text(text.isEmpty ? " " : text)
                    .font(.body.monospaced())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                ProgressView(value: Double(min(samples.count, Self.needed) + min(swipes.count, swipesNeeded)),
                             total: Double(Self.needed + swipesNeeded))
                Text(allDone ? NSLocalizedString("Done! You can keep typing to improve it, or save.", comment: "")
                     : typingDone ? String(format: NSLocalizedString("%lld of %lld slides", comment: ""), swipes.count, swipesNeeded)
                     : String(format: NSLocalizedString("%lld of %lld taps", comment: ""), samples.count, Self.needed))
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    var s = model.settings
                    s.setTaps(samples, grip: grip.rawValue, context: context)
                    if kbWidth > 50 { s.widths[context] = Double(kbWidth) }
                    if !swipes.isEmpty {
                        var c = s.swipes[context] ?? [:]
                        c[grip.rawValue] = Array(swipes.suffix(12))
                        s.swipes[context] = c
                    }
                    model.settings = s
                    dismiss()
                } label: {
                    Text("Save").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allDone)
            }
            .padding(20)
            Spacer(minLength: 0)
            KeyboardPreview(settings: recordSettings, pro: true, text: $text, record: grip, onSample: { f in
                samples.append(f)
                if samples.count > 30 { samples.removeFirst() }
            }, onSwipe: { f in
                if typingDone { swipes.append(f) }
            })
            .frame(height: KeyboardPreview.height(recordSettings))
            .ignoresSafeArea(.container, edges: .horizontal)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { kbWidth = $0 }
        }
        .interactiveDismissDisabled(!samples.isEmpty && !allDone)
        .fullScreenDuo()
    }
}
