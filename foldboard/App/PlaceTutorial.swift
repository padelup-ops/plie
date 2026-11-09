import SwiftUI
import UIKit

/// Le tutoriel animé : on apprend en le faisant. Une cible clignote dans la place libre à côté des touches ;
/// on la touche, le clavier vient de ce côté. À gauche, puis à droite.
struct PlaceTutorial: View {
    /// Premier lancement : passe à la suite quand c'est fini.
    var onFinish: (() -> Void)? = nil
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 0 : toucher à gauche, 1 : toucher à droite, 2 : fini.
    @State private var step = 0
    @State private var demo = KBSettings()
    @State private var text = ""
    @State private var pulse = false
    @State private var ready = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if onFinish == nil {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.headline)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                    }
                    ForEach(0..<2, id: \.self) { i in
                        Capsule()
                            .fill(i < step ? Color.green : (i == step ? Color.accentColor : Color(.systemFill)))
                            .frame(height: 5)
                    }
                }
                .padding(.horizontal, onFinish == nil ? 0 : 30)
                .animation(.easeInOut, value: step)

                Spacer(minLength: 0)
                Image(systemName: step == 2 ? "checkmark.circle.fill" : (step == 0 ? "arrow.left.to.line" : "arrow.right.to.line"))
                    .font(.system(size: 54))
                    .foregroundStyle(step == 2 ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.title2.bold()).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if step == 2 {
                    Button {
                        var s = model.settings
                        s.mode = .auto
                        s.autoTwo = false
                        s.autoRight = demo.autoRight
                        model.settings = s
                        if let onFinish { onFinish() } else { dismiss() }
                    } label: {
                        Text(onFinish == nil ? "Done" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Start again") { restart() }.font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            if ready {
                KeyboardPreview(settings: demo, pro: true, text: $text, onSettings: { s in
                    demo = s
                    check(s)
                }, demoOneHand: true)
                .frame(height: KeyboardPreview.height(demo))
                .overlay { target }
                .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        .onAppear { restart() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var title: LocalizedStringKey {
        switch step {
        case 0: return "Tap the free space on the left"
        case 1: return "Now tap the free space on the right"
        default: return "That's it!"
        }
    }

    private var detail: LocalizedStringKey {
        step == 2
            ? "Outer screen: tap a side and the keyboard comes there, and stays. Inner screen: it splits in two by itself, and is full width in landscape."
            : "The keyboard comes to the side you tap, right under your thumb."
    }

    /// La cible qui clignote dans la place libre, avec le doigt qui tape.
    private var target: some View {
        GeometryReader { g in
            let W = g.size.width
            let block = min(W - 8, max(min(W - 8, 250), W * demo.oneHandWidth))
            let free = max(40, W - block)
            let x = step == 0 ? free / 2 : W - free / 2
            let y = g.size.height / 2 + 22
            if step < 2 {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulse ? 1.25 : 0.6)
                        .opacity(pulse ? 0 : 1)
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: 44, height: 44)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .offset(y: pulse ? 0 : 5)
                }
                .position(x: x, y: y)
                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulse)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            }
        }
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }

    private func check(_ s: KBSettings) {
        guard !s.autoTwo else { return }
        if step == 0 && !s.autoRight { advance() }
        else if step == 1 && s.autoRight { advance() }
    }

    private func advance() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { step += 1 }
    }

    private func restart() {
        var s = model.settings
        s.mode = .auto
        s.autoRight = true
        s.autoTwo = false
        // Les réglages de départ pour la démonstration (largeur, écart) : la cible tombe au bon endroit.
        s.edgeMargin = KBSettings().edgeMargin
        s.oneHandWidth = KBSettings().oneHandWidth
        demo = s
        step = 0
        ready = true
    }
}
