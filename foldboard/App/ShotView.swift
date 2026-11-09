import SwiftUI

/// Écrans pour les captures de l'App Store (lancement avec « -shot nom »), avec le vrai clavier Foldboard.
struct ShotView: View {
    let name: String
    @State private var text = ""
    @Environment(Store.self) private var store

    var body: some View {
        switch name {
        case "pro":
            ProView()
        case "themes":
            NavigationStack { LookView().fullScreenDuo() }
        case "phrases":
            NavigationStack { PhrasesView().fullScreenDuo() }
        case "calib":
            NavigationStack { CalibrationScreen().fullScreenDuo() }
        case "onboarding":
            OnboardingView(onDone: {})
        case "onboarding3":
            OnboardingView(start: 3, onDone: {})
        default:
            chat
        }
    }

    private var fr: Bool { Locale.current.language.languageCode?.identifier == "fr" }

    private var settings: KBSettings {
        var s = KBSettings()
        s.layout = fr ? .azerty : .qwerty
        switch name {
        case "left":
            s.mode = .left
            s.sidePanel = .phrases
            s.theme = "lavender"
        case "split":
            s.mode = .split
            s.theme = "night"
        default:
            s.mode = .right
            s.sidePanel = .emoji
        }
        return s
    }

    private var messages: [(String, Bool)] {
        if fr {
            return [("Tu arrives à quelle heure ?", false), ("Vers 19h, je finis un truc 🙂", true), ("Top, on se retrouve devant le ciné", false)]
        }
        return [("What time are you getting here?", false), ("Around 7, just finishing something 🙂", true), ("Great, meet you outside the cinema", false)]
    }

    private var draft: String {
        switch name {
        case "left": return fr ? "Merci beaucoup, à tout à " : "Thanks a lot, see you "
        case "split": return fr ? "Parfait, je suis en rou" : "Perfect, I’m on my wa"
        default: return fr ? "D’accord, j’arrive dans dix minu" : "Sure, I’ll be there in ten minu"
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { item in
                        let (t, me) = item.element
                        HStack {
                            if me { Spacer(minLength: 60) }
                            Text(t)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(me ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                                .foregroundStyle(me ? .white : .primary)
                            if !me { Spacer(minLength: 60) }
                        }
                    }
                }
                .padding(16)
            }
            HStack {
                Text(text.isEmpty ? " " : text + "|")
                    .lineLimit(2)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator)))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            KeyboardPreview(settings: settings, pro: true, text: $text)
                .frame(height: KeyboardPreview.height(settings))
        }
        .onAppear { text = draft }
    }
}
