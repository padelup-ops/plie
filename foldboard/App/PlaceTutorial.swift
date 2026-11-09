import SwiftUI
import UIKit

/// Le tutoriel animé : on prend le téléphone dans la main gauche et on touche la zone de texte, le clavier sort
/// à gauche ; puis la main droite, il sort à droite. Au passage, Foldboard retient comment le téléphone penche
/// dans chaque main : c'est ce qui lui permet ensuite de sortir du bon côté tout seul, dans toutes les apps.
struct PlaceTutorial: View {
    /// Premier lancement : passe à la suite quand c'est fini.
    var onFinish: (() -> Void)? = nil
    @Environment(SettingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 0 : main gauche, 1 : main droite, 2 : fini.
    @State private var step = 0
    /// Le clavier est sorti pour cette étape.
    @State private var shown = false
    @State private var demo = KBSettings()
    @State private var text = ""
    @State private var pulse = false
    @State private var reader = TiltReader()
    @State private var hingeClosed: Bool?
    @State private var rolls: [Double?] = [nil, nil]

    private var context: String {
        _ = reader.tick
        return kbCurrentContext(closed: hingeClosed, known: model.settings.screenWidths)
    }

    /// Ouvert seulement si la charnière le dit (sinon on ne dérange pas avec un faux avertissement).
    private var open: Bool { hingeClosed == false }

    /// L'écart d'inclinaison entre les deux mains (nil si on n'a pas pu mesurer).
    private var gap: Double? {
        guard let l = rolls[0], let r = rolls[1] else { return nil }
        return abs(kbWrap(r - l))
    }

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
                if step == 2 {
                    done
                } else {
                    Image(systemName: shown ? "checkmark.circle.fill" : (step == 0 ? "hand.point.left.fill" : "hand.point.right.fill"))
                        .font(.system(size: 50))
                        .foregroundStyle(shown ? Color.green : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                    Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if open {
                        Label("Close your Duo: this works on the outer screen.", systemImage: "iphone")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    field
                    if shown {
                        Button { next() } label: {
                            Text(step == 0 ? "Next: right hand" : "Finish")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            if shown && step < 2 {
                KeyboardPreview(settings: demo, pro: true, text: $text, onSettings: { _ in }, demoOneHand: true)
                    .frame(height: KeyboardPreview.height(demo))
                    .ignoresSafeArea(.container, edges: .horizontal)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shown)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .onAppear { reader.start(); pulse = true }
        .onDisappear { reader.stop() }
        .modifier(HingeWatch { hingeClosed = $0 })
        .toolbar(.hidden, for: .navigationBar)
    }

    /// La zone de texte à toucher : une cible clignote du côté du pouce.
    private var field: some View {
        Button { touched() } label: {
            HStack {
                if step == 1 { Spacer() }
                if !shown { target }
                Text(text.isEmpty ? NSLocalizedString("Tap here to write", comment: "") : text)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if step == 0 { Spacer() }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor.opacity(shown ? 0 : 0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(shown)
    }

    private var target: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: 40, height: 40)
                .scaleEffect(pulse ? 1.3 : 0.6)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulse)
            Image(systemName: "hand.tap.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
        }
        .frame(width: 44, height: 44)
    }

    private var done: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("That's it!").font(.title2.bold())
            Text("Foldboard remembers how you hold the phone in each hand: the keyboard now comes out on the right side by itself, in every app.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Not on the right side? Tap the free space next to the keys: it goes there, and remembers.", systemImage: "hand.tap")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let gap, gap < 4 {
                Label("You hold the phone almost the same way in both hands: use the tap to place it.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let onFinish { onFinish() } else { dismiss() }
            } label: {
                Text(onFinish == nil ? "Done" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button("Start again") { step = 0; shown = false; text = ""; rolls = [nil, nil] }.font(.subheadline)
        }
    }

    private var title: LocalizedStringKey {
        if shown { return step == 0 ? "It came out on the left" : "It came out on the right" }
        return step == 0 ? "Hold the phone in your left hand" : "Now in your right hand"
    }

    private var detail: LocalizedStringKey {
        if shown { return "The keyboard comes out under the thumb of the hand holding the phone." }
        return step == 0 ? "Then tap the text field with your left thumb." : "Then tap the text field with your right thumb."
    }

    /// La zone de texte vient d'être touchée : on note comment le téléphone penche dans cette main,
    /// et le clavier sort de ce côté.
    private func touched() {
        rolls[step] = reader.roll
        var s = model.settings
        s.mode = step == 0 ? .left : .right
        s.edgeMargin = KBSettings().edgeMargin
        demo = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        shown = true
    }

    private func next() {
        shown = false
        text = ""
        if step == 1 { save() }
        step += 1
    }

    /// Enregistre les deux inclinaisons pour l'écran extérieur : le clavier sort ensuite du côté de la main.
    private func save() {
        var s = model.settings
        s.mode = .auto
        s.autoTwo = false
        s.autoRight = true
        if !open, let l = rolls[0], let r = rolls[1] {
            var c = s.learned[context] ?? [:]
            c["left"] = [l]
            c["right"] = [r]
            s.learned[context] = c
            // Ces mesures remplacent un ancien étalonnage de cette situation.
            s.calib[context] = nil
            s.taps[context] = nil
            s.swipes[context] = nil
        }
        model.settings = s
    }
}
