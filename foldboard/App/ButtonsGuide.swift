import SwiftUI

/// « Les boutons du clavier » : chaque bouton de la barre du haut, et comment apprendre au clavier où le mettre.
struct ButtonsGuide: View {
    var onDone: (() -> Void)? = nil
    @State private var demo = 0
    private let timer = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The keyboard buttons").font(.largeTitle.bold())
                    Text("The bar above the keys, from left to right.").foregroundStyle(.secondary)
                }

                bar

                VStack(spacing: 14) {
                    row("hand.raised.fingers.spread", "Position",
                        "Choose where the keyboard goes: following your hand, always left, always right, full width or split.")
                    row("arrow.left.arrow.right", "Switch side",
                        "The keyboard is on the wrong side? Tap it: it moves to the other side and remembers how you are holding the phone.")
                    row("rectangle.center.inset.filled", "Keyboard in the middle",
                        "Typing with both hands, Duo closed? Tap it: the keyboard goes in the middle, full width, and Foldboard remembers this grip too. Tap ⇆ to go back to one hand.")
                    row("rectangle.split.2x1", "Big or split (Duo open)",
                        "On the open Duo: switch between the small keyboard that follows your hand, the full keyboard, and two halves.")
                    row("slider.horizontal.3", "Adjust",
                        "Drag the keyboard to change its size, its height and its distance from the edge.")
                    row("face.smiling", "Emoji and 🌐",
                        "With the small one-hand keyboard, emoji and the globe move up here to save room.")
                    row("keyboard.chevron.compact.down", "Hide",
                        "Hides the keyboard.")
                }

                teach

                VStack(alignment: .leading, spacing: 8) {
                    Label("Trackpad", systemImage: "hand.point.up.left").font(.headline)
                    Text("Hold the space bar: the letters fade and the whole keyboard becomes a trackpad. Slide to move the cursor anywhere, up and down too.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let onDone {
                    Button(action: onDone) {
                        Text("Got it").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                }
            }
            .padding(20)
        }
        .onReceive(timer) { _ in withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { demo = (demo + 1) % 3 } }
        .navigationTitle("The buttons")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// La barre du haut, comme dans le clavier.
    private var bar: some View {
        HStack(spacing: 16) {
            ForEach(["hand.raised.fingers.spread", "arrow.left.arrow.right", "rectangle.center.inset.filled", "rectangle.split.2x1"], id: \.self) {
                Image(systemName: $0).font(.system(size: 19, weight: .medium))
            }
            Spacer()
            ForEach(["face.smiling", "slider.horizontal.3", "keyboard.chevron.compact.down"], id: \.self) {
                Image(systemName: $0).font(.system(size: 19, weight: .medium))
            }
        }
        .foregroundStyle(.primary.opacity(0.8))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Apprendre au clavier : une petite animation (gauche, milieu, droite), puis la règle.
    private var teach: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Teach it where you want it", systemImage: "brain.head.profile").font(.headline)
            GeometryReader { g in
                let w = g.size.width
                let kw = demo == 1 ? w - 24 : w * 0.62
                let x: CGFloat = demo == 0 ? 12 : (demo == 1 ? 12 : w - 12 - kw)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemBackground))
                    VStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.18))
                                }
                            }
                        }
                    }
                    .frame(width: kw, height: 64)
                    .offset(x: x, y: 14)
                    Image(systemName: demo == 0 ? "arrow.left.arrow.right" : (demo == 1 ? "rectangle.center.inset.filled" : "arrow.left.arrow.right"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 10, y: 86)
                }
            }
            .frame(height: 124)
            Text("Each time you put the keyboard where you want it (⇆ for the other side, the middle button for both hands), Foldboard remembers how you were holding your Duo. Next time you hold it that way, the keyboard goes there by itself. The more you correct it, the less you need to.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
