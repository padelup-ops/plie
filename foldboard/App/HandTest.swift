import SwiftUI
import UIKit

/// La situation en ce moment (écran du Duo utilisé, sens), d'après la fenêtre active.
func kbCurrentContext(closed: Bool?) -> String {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    let size = window?.bounds.size ?? scene?.screen.bounds.size ?? .zero
    return KBSettings.context(screen: size, closed: closed)
}

/// Le test « main droite / main gauche » : on tient le téléphone 3 secondes dans chaque main, sans rien taper.
/// Foldboard mesure comment le téléphone penche dans chaque main, dit si la différence suffit pour suivre la main
/// tout seul, puis on vérifie en vrai : on change de main et le clavier doit suivre.
struct HandTest: View {
    enum Step { case intro, right, left, result }

    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .intro
    @State private var reader = TiltReader()
    @State private var hingeClosed: Bool?
    @State private var samples: [(roll: Double, incline: Double)] = []
    @State private var timer: Timer?
    @State private var right: (roll: Double, incline: Double, spread: Double)?
    @State private var left: (roll: Double, incline: Double, spread: Double)?
    @State private var retry = false
    @State private var text = ""
    @State private var kbWidth: CGFloat = 0
    private static let needed = 60   // 3 secondes à 20 mesures par seconde

    private var context: String {
        _ = reader.tick
        return kbCurrentContext(closed: hingeClosed)
    }

    private var gap: Double {
        guard let right, let left else { return 0 }
        return abs(kbWrap(right.roll - left.roll))
    }

    private var noise: Double { max(right?.spread ?? 0, left?.spread ?? 0, 1) }

    /// 2 : fiable, 1 : moyen, 0 : les deux mains penchent presque pareil.
    private var verdict: Int {
        if gap >= 8 && gap >= noise * 3 { return 2 }
        if gap >= 4 && gap >= noise * 1.5 { return 1 }
        return 0
    }

    /// La main reconnue en ce moment (pour l'indicateur), d'après l'inclinaison.
    private var liveHand: KBGrip? {
        guard let right, let left, let roll = reader.roll else { return nil }
        let dr = abs(kbWrap(roll - right.roll)), dl = abs(kbWrap(roll - left.roll))
        guard abs(dr - dl) >= max(1.5, gap * 0.1) else { return nil }
        return dr < dl ? .right : .left
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Button { stop(); dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    Spacer()
                    Text(kbContextName(context)).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                switch step {
                case .intro: intro
                case .right, .left: hold
                case .result: result
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            if step == .result && verdict > 0 {
                KeyboardPreview(settings: model.settings, pro: true, text: $text) { s in model.settings = s }
                    .frame(height: KeyboardPreview.height(model.settings))
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        kbWidth = w
                        if w > 50, model.settings.widths[context] != Double(w) {
                            var s = model.settings
                            s.widths[context] = Double(w)
                            model.settings = s
                        }
                    }
            }
        }
        .onAppear { reader.start() }
        .onDisappear { stop(); reader.stop() }
        .modifier(HingeWatch { hingeClosed = $0 })
        .toolbar(.hidden, for: .navigationBar)
    }

    private var intro: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread").font(.system(size: 60)).foregroundStyle(Color.accentColor)
            Text("Right hand, left hand").font(.title2.bold())
            Text("Hold the phone 3 seconds in each hand, as when you type. Nothing to type: Foldboard measures how the phone leans in each hand.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { begin(.right) } label: {
                Text("Start the test").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var hold: some View {
        VStack(spacing: 12) {
            ThumbRing(progress: Double(samples.count) / Double(Self.needed), done: false,
                      symbol: step == .right ? "hand.point.right" : "hand.point.left", size: 150)
            Text(step == .right ? "Hold it in your right hand" : "Now in your left hand").font(.title2.bold())
            Text(retry ? "Hold the phone upright, facing you, not flat on a table."
                       : "As when you type with one thumb. Don't move for 3 seconds.")
                .multilineTextAlignment(.center).foregroundStyle(retry ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(reader.roll.map { String(format: "%+.0f°", $0) } ?? "—")
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var result: some View {
        VStack(spacing: 10) {
            if verdict > 0 {
                // L'indicateur en direct : la main reconnue.
                HStack(spacing: 14) {
                    handBadge(.left)
                    handBadge(.right)
                }
                Text(verdict == 2 ? "Reliable: change hands, the keyboard follows" : "It works, but your two grips are close")
                    .font(.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "equal.circle").font(.system(size: 54)).foregroundStyle(.orange)
                Text("Your two hands hold the phone almost the same way").font(.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The lean is not enough to tell them apart. Keep the tap: touch the free space on a side and the keyboard comes to it.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let right, let left {
                Text(String(format: NSLocalizedString("Right %+.0f° · Left %+.0f° · Gap %.0f° · Shake ±%.1f°", comment: ""),
                            right.roll, left.roll, gap, noise))
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { begin(.right) } label: {
                    Text("Redo").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                if verdict > 0 {
                    Button { forget(); dismiss() } label: {
                        Text("Turn off").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    Button { dismiss() } label: {
                        Text("Keep").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { forget(); dismiss() } label: {
                        Text("OK").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func handBadge(_ g: KBGrip) -> some View {
        let on = liveHand == g
        return VStack(spacing: 4) {
            Image(systemName: g == .right ? "hand.point.right.fill" : "hand.point.left.fill").font(.system(size: 30))
            Text(g == .right ? "Right hand" : "Left hand").font(.caption.weight(.semibold))
        }
        .foregroundStyle(on ? Color.white : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(on ? Color.accentColor : Color(.secondarySystemBackground)))
        .animation(.easeInOut(duration: 0.15), value: on)
    }

    // MARK: Mesure

    private func begin(_ s: Step) {
        stop()
        samples = []
        retry = false
        if s == .right { right = nil; left = nil }
        step = s
        var idle = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let r = reader.roll, let i = reader.incline {
                // On ignore la première demi-seconde, le temps de bien prendre le téléphone.
                idle += 1
                if idle > 10 { samples.append((r, i)) }
            } else {
                retry = true
            }
            if samples.count >= Self.needed { finish() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func finish() {
        stop()
        let f = samples[0].roll
        let dev = samples.map { kbWrap($0.roll - f) }
        let mean = dev.reduce(0, +) / Double(dev.count)
        let spread = (dev.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(dev.count)).squareRoot()
        let roll = kbWrap(f + mean)
        let inc = samples.map(\.incline).reduce(0, +) / Double(samples.count)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if step == .right {
            right = (roll, inc, spread)
            // Une seconde pour changer de main.
            samples = []
            step = .left
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { begin(.left) }
        } else {
            left = (roll, inc, spread)
            save()
            withAnimation { step = .result }
        }
    }

    /// Enregistre les deux inclinaisons pour cette situation : le clavier suit alors la main tout seul.
    private func save() {
        guard let right, let left, verdict > 0 else { return }
        var s = model.settings
        s.calibrate("right", roll: right.roll, incline: right.incline, context: context)
        s.calibrate("left", roll: left.roll, incline: left.incline, context: context)
        // La mesure au repos remplace l'ancien apprentissage par la frappe pour cette situation.
        s.taps[context] = nil
        s.swipes[context] = nil
        s.calib[context]?["two"] = nil
        s.mode = .auto
        s.autoTwo = false
        model.settings = s
    }

    /// Pas de suivi automatique pour cette situation : on garde le toucher.
    private func forget() {
        var s = model.settings
        s.calib[context] = nil
        s.learned[context] = nil
        s.taps[context] = nil
        s.swipes[context] = nil
        model.settings = s
    }
}
