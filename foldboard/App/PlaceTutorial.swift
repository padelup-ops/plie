import SwiftUI
import UIKit

/// Le réglage « quelle main tient le téléphone », comme l'app japonaise de la vidéo : on tient le téléphone dans
/// la main droite et on appuie trois fois sur le gros bouton sous le pouce, puis pareil dans la main gauche.
/// Chaque appui enregistre comment le téléphone penche à ce moment-là (dans le plan de l'écran et vers soi).
/// Ensuite, dans toutes les apps, le clavier sort du côté de la main qui le tient.
struct PlaceTutorial: View {
    /// Premier lancement : passe à la suite quand c'est fini.
    var onFinish: (() -> Void)? = nil
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 0 : main droite, 1 : main gauche, 2 : essai, 3 : fini.
    @State private var step = 0
    @State private var presses: [[(roll: Double, incline: Double)]] = [[], []]
    @State private var reader = TiltReader()
    @State private var hingeClosed: Bool?
    @State private var warn = false
    @State private var pressed = false
    // Essai
    @State private var shown = false
    @State private var demo = KBSettings()
    @State private var text = ""
    @State private var side: KBGrip?
    @State private var pulse = false

    static let needed = 3

    private var context: String {
        _ = reader.tick
        return kbCurrentContext(closed: hingeClosed, known: model.settings.screenWidths)
    }

    /// La posture moyenne de chaque main (droite, gauche).
    private func mean(_ i: Int) -> (roll: Double, incline: Double)? {
        let p = presses[i]
        guard let f = p.first else { return nil }
        let r = kbWrap(f.roll + p.map { kbWrap($0.roll - f.roll) }.reduce(0, +) / Double(p.count))
        let inc = p.map(\.incline).reduce(0, +) / Double(p.count)
        return (r, inc)
    }

    /// L'écart entre les deux mains (en degrés).
    private var gap: Double? {
        guard let r = mean(0), let l = mean(1) else { return nil }
        return abs(kbWrap(r.roll - l.roll))
    }

    /// La main d'après la posture du moment (pour l'essai).
    private var liveHand: KBGrip? {
        guard let r = mean(0), let l = mean(1), let roll = reader.roll, let inc = reader.incline else { return nil }
        func d(_ p: (roll: Double, incline: Double)) -> Double {
            let a = kbWrap(roll - p.roll), b = (inc - p.incline) * 0.15
            return (a * a + b * b).squareRoot()
        }
        return d(r) <= d(l) ? .right : .left
    }

    var body: some View {
        ZStack {
            if step < 2 { glow }
            VStack(spacing: 0) {
                header
                switch step {
                case 0, 1: pressStep
                case 2: tryStep
                default: done.padding(.horizontal, 20)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shown)
        .onAppear { reader.start(); pulse = true }
        .onDisappear { reader.stop() }
        .modifier(HingeWatch { hingeClosed = $0 })
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            if onFinish == nil {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.headline)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i < step ? Color.green : (i == step ? Color.accentColor : Color(.systemFill)))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, onFinish == nil ? 20 : 50)
        .padding(.top, 12)
    }

    // MARK: Appuyer sous le pouce

    /// La lueur du côté de la main, comme dans l'app de la vidéo.
    private var glow: some View {
        RadialGradient(colors: [Color.accentColor.opacity(0.45), .clear],
                       center: step == 0 ? .bottomTrailing : .bottomLeading, startRadius: 10, endRadius: 520)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: step)
    }

    private var pressStep: some View {
        let right = step == 0
        let count = presses[step].count
        return VStack(alignment: right ? .trailing : .leading, spacing: 10) {
            Text(right ? "Hold it in your right hand" : "Now in your left hand")
                .font(.largeTitle.bold())
                .multilineTextAlignment(right ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(right ? "As when you type. Press the button with your right thumb, 3 times."
                       : "As when you type. Press the button with your left thumb, 3 times.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(right ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if warn {
                Text("Hold the phone upright, facing you, not flat on a table.")
                    .font(.footnote).foregroundStyle(.orange)
                    .multilineTextAlignment(right ? .trailing : .leading)
            }
            Spacer(minLength: 0)
            HStack {
                if right { Spacer() }
                pressButton(count: count)
                if !right { Spacer() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
    }

    private func pressButton(count: Int) -> some View {
        Button { press() } label: {
            ZStack {
                Circle().fill(Color(white: 0.13))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(count) / CGFloat(Self.needed))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)
                VStack(spacing: 4) {
                    Text("Press").font(.title3.bold()).foregroundStyle(.white)
                    Text("\(count)/\(Self.needed)").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 150, height: 150)
            .scaleEffect(pressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Un appui : on note la posture du téléphone à ce moment-là.
    private func press() {
        guard step < 2 else { return }
        guard let r = reader.roll, let i = reader.incline else {
            warn = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        warn = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pressed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false }
        }
        presses[step].append((r, i))
        if presses[step].count >= Self.needed {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                step += 1
                if step == 2 { save() }
            }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    // MARK: Essai

    private var tryStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Image(systemName: shown ? "checkmark.circle.fill" : "hand.tap.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(shown ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                Text(shown ? (side == .left ? "It came out on the left" : "It came out on the right") : "Try it")
                    .font(.title2.bold())
                Text(shown ? "Change hands and tap the field again: the keyboard follows."
                           : "Hold the phone in one hand and tap the field with that thumb.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let gap, gap < 4 {
                    Label("You hold the phone almost the same way in both hands: use the tap to place it.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                field
                HStack(spacing: 10) {
                    Button { restart() } label: {
                        Text("Start again").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    Button { shown = false; step = 3 } label: {
                        Text("Finish").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            if shown {
                KeyboardPreview(settings: demo, pro: true, text: $text, onSettings: { _ in }, demoOneHand: true)
                    .frame(height: KeyboardPreview.height(demo))
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .transition(.move(edge: .bottom))
            }
        }
    }

    private var field: some View {
        Button { touched() } label: {
            HStack {
                if !shown {
                    Image(systemName: "hand.tap.fill").foregroundStyle(Color.accentColor)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                }
                Text(text.isEmpty ? NSLocalizedString("Tap here to write", comment: "") : text)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    /// La zone de texte est touchée : le clavier sort du côté de la main qui tient le téléphone.
    private func touched() {
        let g = liveHand ?? .right
        var s = model.settings
        s.mode = g == .left ? .left : .right
        s.edgeMargin = KBSettings().edgeMargin
        side = g
        if shown && demo.mode == s.mode { return }
        demo = s
        UISelectionFeedbackGenerator().selectionChanged()
        shown = true
    }

    // MARK: Fin

    private var done: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("That's it!").font(.title2.bold())
            Text("Foldboard remembers how you hold the phone in each hand: the keyboard now comes out on the right side by itself, in every app.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Not on the right side? Tap the free space next to the keys: it goes there, and remembers.", systemImage: "hand.tap")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let onFinish { onFinish() } else { dismiss() }
            } label: {
                Text(onFinish == nil ? "Done" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button("Start again") { restart() }.font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private func restart() {
        presses = [[], []]
        shown = false
        text = ""
        side = nil
        step = 0
    }

    /// Enregistre la posture de chaque main pour cette situation (écran, sens).
    private func save() {
        guard let r = mean(0), let l = mean(1) else { return }
        var s = model.settings
        let c = context
        s.calibrate("right", roll: r.roll, incline: r.incline, context: c)
        s.calibrate("left", roll: l.roll, incline: l.incline, context: c)
        // Ces mesures remplacent l'ancien apprentissage de cette situation.
        s.calib[c]?["two"] = nil
        s.taps[c] = nil
        s.swipes[c] = nil
        s.mode = .auto
        s.autoTwo = false
        s.autoRight = true
        model.settings = s
    }
}
