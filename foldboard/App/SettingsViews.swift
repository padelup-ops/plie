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
    @State private var text = ""

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
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            KeyboardPreview(settings: model.settings, pro: true, text: $text) { s in model.settings = s }
                .frame(height: KeyboardPreview.height(model.settings))
        }
    }
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
                .pickerStyle(.segmented)
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
            .fill(Color(uiColor: theme.background))
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
                Toggle("Word suggestions", isOn: $m.settings.suggestions)
                Toggle("Capital letter at the start of a sentence", isOn: $m.settings.autoCaps)
                Toggle("Double space adds a period", isOn: $m.settings.doubleSpacePeriod)
            } footer: {
                Text("Hold a letter for its accents (é, è, à, ç…). Hold delete to erase word by word.")
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
    @ObservationIgnored private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let planar = (g.x * g.x + g.y * g.y).squareRoot()
            let a = atan2(g.x, -g.y) * 180 / .pi
            let i = asin(max(-1, min(1, -g.z))) * 180 / .pi
            self.roll = planar > 0.2 ? (self.roll.map { $0 * 0.8 + a * 0.2 } ?? a) : nil
            self.incline = self.incline.map { $0 * 0.8 + i * 0.2 } ?? i
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

struct TiltCalibration: View {
    @Environment(SettingsModel.self) private var model
    @State private var reader = TiltReader()

    var body: some View {
        Section {
            HStack {
                Text("Tilt now")
                Spacer()
                Text(reader.roll.map { String(format: "%+.0f°", $0) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                Text(reader.incline.map { String(format: "%.0f°", $0) } ?? "").monospacedDigit().foregroundStyle(.tertiary)
            }
            button("Right hand", "hand.point.right", done: !model.settings.postureRight.isEmpty) { s, p in
                s.postureRight = p
                s.tiltRightSamples = [p[0]]
            }
            button("Left hand", "hand.point.left", done: !model.settings.postureLeft.isEmpty) { s, p in
                s.postureLeft = p
                s.tiltLeftSamples = [p[0]]
            }
            button("Both hands", "hands.clap", done: !model.settings.postureTwo.isEmpty) { s, p in
                s.postureTwo = p
            }
            if model.settings.tiltCalibrated {
                Label(model.settings.postureTwo.isEmpty ? "Calibrated" : "Calibrated, both hands too", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            HStack { Text("Follow your hand"); ProBadge() }
        } footer: {
            Text("Hold the phone as you usually type, then tap the matching button: right hand, left hand, and both hands. With both hands, the keyboard splits in two on the open Duo and goes full width on the outer screen.")
        }
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
    }

    private func button(_ title: LocalizedStringKey, _ icon: String, done: Bool, _ apply: @escaping (inout KBSettings, [Double]) -> Void) -> some View {
        Button {
            guard let r = reader.roll, let i = reader.incline else { return }
            var s = model.settings
            apply(&s, [r, i])
            if !s.tiltRightSamples.isEmpty, !s.tiltLeftSamples.isEmpty {
                s.learnTilt(s.tiltRightSamples.last ?? r, right: true)
            }
            model.settings = s
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if done { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .disabled(reader.roll == nil)
    }
}
