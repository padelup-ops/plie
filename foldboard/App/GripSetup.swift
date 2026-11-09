import SwiftUI
import UIKit

/// Le nom d'une situation (Duo fermé ou ouvert, portrait ou paysage).
func kbContextName(_ c: String) -> String {
    switch c {
    case "open-portrait": return NSLocalizedString("Open · portrait", comment: "")
    case "open-landscape": return NSLocalizedString("Open · landscape", comment: "")
    case "closed-landscape": return NSLocalizedString("Closed · landscape", comment: "")
    default: return NSLocalizedString("Closed · portrait", comment: "")
    }
}

/// L'anneau façon Face ID : des petits traits qui s'allument à chaque appui, l'empreinte au centre,
/// et une coche verte quand c'est fini.
struct ThumbRing: View {
    var progress: Double
    var done: Bool
    var symbol: String = "touchid"
    var size: CGFloat = 150
    private let ticks = 56

    var body: some View {
        ZStack {
            ForEach(0..<ticks, id: \.self) { i in
                let lit = Double(i) < progress * Double(ticks)
                Capsule()
                    .fill(done ? Color.green : (lit ? Color.accentColor : Color.secondary.opacity(0.25)))
                    .frame(width: 3, height: lit || done ? size * 0.085 : size * 0.06)
                    .offset(y: -size * 0.41)
                    .rotationEffect(.degrees(Double(i) / Double(ticks) * 360))
                    .shadow(color: lit && !done ? Color.accentColor.opacity(0.8) : .clear, radius: 4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6).delay(Double(i % 8) * 0.01), value: lit)
            }
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(done ? 0 : 0.28), .clear], center: .center, startRadius: 4, endRadius: 70))
                .frame(width: size * 0.74, height: size * 0.74)
            Image(systemName: done ? "checkmark" : symbol)
                .font(.system(size: size * (done ? 0.28 : 0.34), weight: done ? .bold : .regular))
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: !done && progress > 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
    }
}

/// Apprendre les pouces : on tape une petite phrase avec le pouce droit, puis le pouce gauche, puis les deux.
/// Le clavier reconnaît ensuite quel pouce tape : droit → à droite, gauche → à gauche, les deux → au milieu.
struct GripSetup: View {
    /// Premier lancement : passe à la suite quand c'est fini.
    var onFinish: (() -> Void)? = nil
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    /// L'étape vient d'être réussie : on attend « Suivant » (les appuis en trop ne comptent pas).
    @State private var stepDone = false
    @State private var text = ""
    @State private var samples: [[Double]] = []
    @State private var kbWidth: CGFloat = 0
    @State private var hingeClosed: Bool?
    @State private var reader = TiltReader()
    static let needed = 14

    private let grips: [KBGrip] = [.right, .left, .two]
    private var grip: KBGrip { grips[min(step, 2)] }
    private var finished: Bool { step >= grips.count }
    private var fr: Bool { Locale.current.language.languageCode?.identifier == "fr" }

    /// La situation en ce moment (d'après la fenêtre : écran du Duo, sens).
    private var context: String {
        _ = reader.tick
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        let size = window?.bounds.size ?? scene?.screen.bounds.size ?? .zero
        return KBSettings.context(screen: size, closed: hingeClosed, known: model.settings.screenWidths)
    }

    private var title: LocalizedStringKey {
        switch grip {
        case .right: return "Right thumb"
        case .left: return "Left thumb"
        case .two: return "Both thumbs"
        }
    }

    private var instruction: LocalizedStringKey {
        switch grip {
        case .right: return "Hold the phone in your right hand and type with your right thumb."
        case .left: return "Hold the phone in your left hand and type with your left thumb."
        case .two: return "Hold the phone with both hands and type with both thumbs."
        }
    }

    private var sentence: String { fr ? "salut, à tout à l’heure" : "hi, see you later" }

    private var recordSettings: KBSettings {
        var s = model.settings
        s.mode = .full
        s.autocorrect = false
        s.suggestions = false
        return s
    }

    /// Les situations déjà apprises.
    private var learned: [String] {
        KBSettings.contexts.filter { c in
            let t = model.settings.taps[c] ?? [:]
            return (t["right"]?.count ?? 0) >= 6 && (t["left"]?.count ?? 0) >= 6
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if onFinish == nil {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.headline)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                    }
                    ForEach(0..<grips.count, id: \.self) { i in
                        Capsule()
                            .fill(i < step ? Color.green : (i == step ? Color.accentColor : Color(.systemFill)))
                            .frame(height: 5)
                    }
                }
                .padding(.horizontal, onFinish == nil ? 0 : 30)
                .animation(.easeInOut, value: step)

                Spacer(minLength: 0)
                ThumbRing(progress: finished || stepDone ? 1 : Double(samples.count) / Double(Self.needed), done: finished || stepDone,
                          symbol: grip == .two ? "hands.clap" : "touchid", size: finished ? 170 : 140)

                if finished {
                    Text("Your thumbs are learned").font(.title2.bold())
                    Text("Foldboard now knows your right thumb from your left: the keyboard comes to the thumb that types, and goes to the middle with both.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: NSLocalizedString("Learned for: %@. If you also type with the Duo %@, do it once that way too.", comment: ""),
                                learned.map(kbContextName).joined(separator: ", "),
                                context.hasPrefix("open") ? NSLocalizedString("closed", comment: "") : NSLocalizedString("open", comment: "")))
                        .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button {
                        if let onFinish { onFinish() } else { dismiss() }
                    } label: {
                        Text(onFinish == nil ? "Done" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Start again") { restart() }.font(.subheadline)
                } else if stepDone {
                    Text(grip == .right ? "Right thumb: done!" : "Left thumb: done!").font(.title2.bold())
                    Text(grip == .right ? "Now take the phone in your left hand." : "Now hold the phone with both hands.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        next()
                    } label: {
                        Text(grip == .right ? "Next: left thumb" : "Next: both thumbs")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(title).font(.title2.bold())
                    Text(instruction).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sentence).font(.title3.weight(.semibold)).padding(.top, 2)
                    Text(text.isEmpty ? " " : text)
                        .lineLimit(1).truncationMode(.head)
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(kbContextName(context)).font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            if !finished && !stepDone {
                KeyboardPreview(settings: recordSettings, pro: true, text: $text, record: grip, onSample: { f in add(f) })
                    .frame(height: KeyboardPreview.height(recordSettings))
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { kbWidth = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: finished)
        .animation(.easeInOut(duration: 0.3), value: stepDone)
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
        .modifier(HingeWatch { hingeClosed = $0 })
        .toolbar(.hidden, for: .navigationBar)
    }

    private func add(_ f: [Double]) {
        guard !finished, !stepDone else { return }
        samples.append(f)
        guard samples.count >= Self.needed else { return }
        var s = model.settings
        s.setTaps(samples, grip: grip.rawValue, context: context)
        if kbWidth > 50 { s.widths[context] = Double(kbWidth) }
        model.settings = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if step == grips.count - 1 {
                samples = []
                text = ""
                step += 1
            } else {
                stepDone = true
            }
        }
    }

    /// Étape suivante, quand on a changé de main.
    private func next() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            samples = []
            text = ""
            stepDone = false
            step += 1
        }
    }

    private func restart() {
        var s = model.settings
        s.taps[context] = nil
        s.calib[context] = nil
        s.learned[context] = nil
        s.swipes[context] = nil
        model.settings = s
        withAnimation { samples = []; text = ""; stepDone = false; step = 0 }
    }
}
