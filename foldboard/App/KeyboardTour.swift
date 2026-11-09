import SwiftUI

/// La visite animée, après le réglage du début : ce que fait le clavier, en cinq petites scènes qui se jouent
/// toutes seules (suivre la main, toucher la place libre, Duo ouvert, ajuster, emojis).
struct KeyboardTour: View {
    var onFinish: () -> Void
    @State private var page = 0
    private let count = 5

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.03, blue: 0.06), Color(red: 0.06, green: 0.05, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [Color.accentColor.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .offset(y: 40)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { onFinish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                TabView(selection: $page) {
                    TourScene(title: "It follows your hand",
                              text: "Hold the phone in your left hand, the keyboard comes left. In your right hand, it comes right. In every app.") {
                        FollowDemo()
                    }.tag(0)
                    TourScene(title: "Tap the free space",
                              text: "Not on the right side? Tap the empty space next to the keys: the keyboard slides there and stays.") {
                        TapDemo()
                    }.tag(1)
                    TourScene(title: "Duo open",
                              text: "Landscape: the full keyboard. Portrait: the small one that follows you, full width with one tap, or split in two from the hand menu.") {
                        OpenDemo()
                    }.tag(2)
                    TourScene(title: "Make it yours",
                              text: "The sliders button: drag the keyboard, pull its edges, change the key height. ✓ to keep, ✕ to cancel.") {
                        AdjustDemo()
                    }.tag(3)
                    TourScene(title: "Emoji and words",
                              text: "The emoji key opens them all. Suggestions and your favourite phrases sit in the bar above the keys.") {
                        EmojiDemo()
                    }.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                .padding(.bottom, 16)

                Button {
                    if page < count - 1 { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 } }
                    else { onFinish() }
                } label: {
                    Text(page < count - 1 ? "Next" : "Let's go")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }
}

/// La visite depuis l'accueil.
struct KeyboardTourScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        KeyboardTour { dismiss() }
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Une scène : l'animation en haut, le titre et le texte dessous.
private struct TourScene<Demo: View>: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var demo: () -> Demo

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            demo()
                .frame(height: 300)
            VStack(spacing: 8) {
                Text(title).font(.title.bold()).foregroundStyle(.white)
                Text(text).font(.body).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Le téléphone et le clavier dessinés

/// Une étape qui avance toute seule (l'animation se rejoue en boucle).
private struct Ticker<Content: View>: View {
    let every: Double
    let steps: Int
    @ViewBuilder var content: (Int) -> Content
    @State private var step = 0
    @State private var timer: Timer?

    var body: some View {
        content(step)
            .onAppear {
                step = 0
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { step = (step + 1) % steps }
                }
            }
            .onDisappear { timer?.invalidate(); timer = nil }
    }
}

/// Un téléphone : l'écran, un champ de texte en haut, et le clavier en bas.
private struct MockPhone<Keyboard: View>: View {
    var size: CGSize
    var text: String = ""
    @ViewBuilder var keyboard: () -> Keyboard

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.09))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 2)
            VStack {
                HStack(spacing: 4) {
                    Text(text.isEmpty ? " " : text).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                        .lineLimit(1)
                    Capsule().fill(Color.accentColor).frame(width: 2, height: 12)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .padding(.horizontal, 12)
                .padding(.top, 18)
                Spacer()
            }
            keyboard()
                .padding(.bottom, 10)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: Color.accentColor.opacity(0.35), radius: 24)
    }
}

/// Un bloc de touches dessiné : quatre rangées comme le vrai clavier.
private struct MockKeys: View {
    var width: CGFloat
    var keyHeight: CGFloat = 15
    var highlight: Int? = nil   // une touche qui s'allume (index dans la dernière rangée)

    var body: some View {
        let rows: [[CGFloat]] = [
            Array(repeating: 1, count: 10),
            Array(repeating: 1, count: 10),
            [1.5] + Array(repeating: 1, count: 7) + [1.5],
            [1.5, 1.1, 1.1, 1, 3.3, 2],
        ]
        VStack(spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<rows[r].count, id: \.self) { k in
                        let special = (r == 2 && (k == 0 || k == rows[r].count - 1)) || (r == 3 && k != 4)
                        let lit = r == 3 && highlight == k
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(lit ? Color.accentColor : (special ? Color.white.opacity(0.18) : Color.white.opacity(0.32)))
                            .frame(width: max(2, (width - 27 - 6) / 10 * rows[r][k]), height: keyHeight)
                            .scaleEffect(lit ? 1.25 : 1)
                    }
                }
            }
        }
        .padding(3)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Un cercle qui s'étend : l'endroit touché.
private struct Ripple: View {
    var active: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 36, height: 36)
                .scaleEffect(active ? 1.6 : 0.4)
                .opacity(active ? 0 : 0.9)
            Circle().fill(Color.white.opacity(active ? 0.9 : 0))
                .frame(width: 14, height: 14)
        }
        .animation(.easeOut(duration: 0.7), value: active)
    }
}

// MARK: - Les scènes

/// Le téléphone change de main, le clavier glisse sous le bon pouce.
private struct FollowDemo: View {
    var body: some View {
        Ticker(every: 1.8, steps: 2) { s in
            let right = s == 1
            let phone = CGSize(width: 190, height: 270)
            ZStack {
                MockPhone(size: phone, text: right ? "J'arrive" : "Salut !") {
                    HStack {
                        if right { Spacer(minLength: 0) }
                        MockKeys(width: phone.width * 0.74)
                        if !right { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 8)
                }
                .rotationEffect(.degrees(right ? 7 : -7))
                Image(systemName: right ? "hand.raised.fill" : "hand.raised.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .scaleEffect(x: right ? -1 : 1, y: 1)
                    .offset(x: right ? 110 : -110, y: 90)
                Text(right ? "Right hand" : "Left hand")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .offset(y: -160)
            }
        }
    }
}

/// Un toucher dans la place libre, et le clavier y glisse.
private struct TapDemo: View {
    var body: some View {
        Ticker(every: 1.3, steps: 4) { s in
            // 0 : à droite · 1 : toucher à gauche · 2 : à gauche · 3 : toucher à droite
            let right = s == 0 || s == 3
            let phone = CGSize(width: 200, height: 270)
            MockPhone(size: phone, text: "Bonne idée") {
                ZStack(alignment: .bottom) {
                    HStack {
                        if right { Spacer(minLength: 0) }
                        MockKeys(width: phone.width * 0.74)
                        if !right { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 8)
                    Ripple(active: s == 1 || s == 3)
                        .offset(x: s == 1 || s == 0 ? -phone.width * 0.38 : phone.width * 0.38, y: -40)
                        .opacity(s == 1 || s == 3 ? 1 : 0)
                }
            }
        }
    }
}

/// Duo ouvert : paysage entier, portrait petit qui suit, en grand, puis en deux.
private struct OpenDemo: View {
    var body: some View {
        Ticker(every: 1.7, steps: 4) { s in
            let landscape = s == 0
            let phone = landscape ? CGSize(width: 300, height: 210) : CGSize(width: 240, height: 290)
            VStack(spacing: 12) {
                MockPhone(size: phone, text: "Écran ouvert") {
                    Group {
                        switch s {
                        case 0:
                            MockKeys(width: phone.width - 20, keyHeight: 13)
                        case 1:
                            HStack { Spacer(minLength: 0); MockKeys(width: phone.width * 0.6) }.padding(.horizontal, 8)
                        case 2:
                            MockKeys(width: phone.width - 20)
                        default:
                            HStack {
                                MockKeys(width: phone.width * 0.42)
                                Spacer(minLength: 0)
                                MockKeys(width: phone.width * 0.42)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: icon(s))
                    Text(label(s))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .contentTransition(.opacity)
            }
        }
    }

    private func icon(_ s: Int) -> String {
        ["rectangle.landscape.rotate", "hand.raised.fill", "arrow.up.left.and.arrow.down.right", "rectangle.split.2x1"][s]
    }

    private func label(_ s: Int) -> LocalizedStringKey {
        switch s {
        case 0: return "Landscape: full keyboard"
        case 1: return "Portrait: follows your hand"
        case 2: return "One tap: big keyboard"
        default: return "Or split in two"
        }
    }
}

/// Ajuster : le clavier s'élargit, se déplace, puis ✓.
private struct AdjustDemo: View {
    var body: some View {
        Ticker(every: 1.2, steps: 4) { s in
            let phone = CGSize(width: 200, height: 270)
            let widths: [CGFloat] = [0.7, 0.86, 0.62, 0.74]
            let w = phone.width * widths[s]
            MockPhone(size: phone, text: "") {
                ZStack {
                    HStack {
                        Spacer(minLength: 0)
                        MockKeys(width: w)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, lineWidth: 2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor).frame(width: 5, height: 30).offset(x: -3)
                            }
                    }
                    .padding(.horizontal, 8)
                    VStack(spacing: 8) {
                        Text("\(Int(phone.width - w - 8)) pt")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(.black)
                            .contentTransition(.numericText())
                        HStack(spacing: 10) {
                            ForEach(["arrow.counterclockwise", "xmark", "checkmark"], id: \.self) { n in
                                Image(systemName: n)
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(n == "checkmark" ? (s == 3 ? Color.green : Color.black) : Color.white))
                                    .foregroundStyle(n == "checkmark" ? Color.white : Color.black)
                                    .scaleEffect(n == "checkmark" && s == 3 ? 1.2 : 1)
                            }
                        }
                    }
                    .offset(y: -10)
                }
            }
        }
    }
}

/// La touche emoji, puis la grille d'emojis.
private struct EmojiDemo: View {
    var body: some View {
        Ticker(every: 1.4, steps: 3) { s in
            let phone = CGSize(width: 200, height: 270)
            MockPhone(size: phone, text: s == 2 ? "Trop bien 😍" : "Trop bien") {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        ForEach(["Merci !", "J'arrive", "OK 👍"], id: \.self) { w in
                            Text(w).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                    }
                    if s == 2 {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 7), spacing: 4) {
                            ForEach(Array("😂❤️👍🙏😊😭😍🔥✨🥹😅🎉👀💯🤔😎🥳🙌💪😉🤩".map(String.init).prefix(21)), id: \.self) { e in
                                Text(e).font(.system(size: 15))
                            }
                        }
                        .frame(width: phone.width - 20, height: 86)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        MockKeys(width: phone.width - 20, highlight: s == 1 ? 2 : nil)
                            .transition(.opacity)
                    }
                }
            }
        }
    }
}
