import SwiftUI

/// Écrans pour les captures de l'App Store (lancement avec « -shot nom »), avec le vrai clavier Foldboard.
struct ShotView: View {
    let name: String
    @State private var text = ""
    @Environment(Store.self) private var store

    private var base: String { String(name.split(separator: "~").first ?? "") }

    var body: some View {
        switch base {
        case "home":
            HomeView().onAppear { UserDefaults.standard.set(true, forKey: "onboarded") }
        case "pro":
            ProView()
        case "themes":
            NavigationStack { LookView().fullScreenDuo() }
        case "phrases":
            NavigationStack { PhrasesView().fullScreenDuo() }
        case "calib":
            NavigationStack { GripSetup().fullScreenDuo() }
        case "onboarding":
            OnboardingView(onDone: {})
        case "tutorial":
            NavigationStack { PlaceTutorial().fullScreenDuo() }
        case "handtest":
            NavigationStack { HandTest().fullScreenDuo() }
        case "onboarding3":
            OnboardingView(start: 5, onDone: {})
        case "open-land":
            scaled(width: 951, height: 669)
        case "open-small", "open-big", "open-split":
            scaled(width: 669, height: 951)
        default:
            chat
        }
    }

    /// L'écran intérieur du Duo (669 × 951 pt) dessiné en réduction sur l'écran du simulateur : pour les vidéos.
    private func scaled(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { g in
            let k = g.size.width / width
            chat
                .padding(.top, 24)
                .frame(width: width, height: height)
                .background(Color(.systemBackground))
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: g.size.width, height: height * k, alignment: .topLeading)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
    }

    private var demoContext: String? {
        switch base {
        case "open-land": return "open-landscape"
        case "open-small", "open-big", "open-split": return "open-portrait"
        default: return nil
        }
    }

    private var fr: Bool { lang == "fr" }
    private var lang: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private var settings: KBSettings {
        var s = KBSettings()
        s.layout = lang == "fr" ? .azerty : lang == "de" ? .qwertz : lang == "es" ? .spanish : .qwerty
        switch base {
        case "left":
            s.mode = .left
            s.sidePanel = .phrases
            s.theme = "lavender"
        case "split":
            s.mode = .split
            s.theme = "night"
        case "leftsame":
            s.mode = .left
            s.sidePanel = .emoji
        case "open-land", "open-big":
            s.mode = .full
        case "open-split":
            s.mode = .split
        default:
            s.mode = .right
            s.sidePanel = .emoji
        }
        return s
    }

    /// La conversation de la capture, dans la langue de l'écran (en anglais pour les langues que le clavier n'écrit pas).
    private static let talk: [String: ([String], [String])] = [
        "fr": (["Tu arrives à quelle heure ?", "Vers 19h, je finis un truc 🙂", "Top, on se retrouve devant le ciné"],
               ["D’accord, j’arrive dans dix minu", "Parfait, je suis en rou", "Merci beaucoup, à tout à "]),
        "en": (["What time are you getting here?", "Around 7, just finishing something 🙂", "Great, meet you outside the cinema"],
               ["Sure, I’ll be there in ten minu", "Perfect, I’m on my wa", "Thanks a lot, see you "]),
        "de": (["Wann bist du da?", "Gegen 19 Uhr, mache noch was fertig 🙂", "Super, wir treffen uns vor dem Kino"],
               ["Klar, ich bin in zehn Minu", "Perfekt, ich bin unterw", "Vielen Dank, bis "]),
        "es": (["¿A qué hora llegas?", "Sobre las 7, termino una cosa 🙂", "Genial, nos vemos en la puerta del cine"],
               ["Vale, llego en diez minu", "Perfecto, ya voy de cam", "Muchas gracias, nos vem"]),
        "it": (["A che ora arrivi?", "Verso le 7, finisco una cosa 🙂", "Perfetto, ci vediamo davanti al cinema"],
               ["Ok, arrivo tra dieci minu", "Perfetto, sono per str", "Grazie mille, a dop"]),
        "nl": (["Hoe laat ben je er?", "Rond 7 uur, ik maak iets af 🙂", "Top, we zien elkaar bij de bioscoop"],
               ["Prima, ik ben er over tien minu", "Perfect, ik ben onderw", "Heel erg bedankt, tot "]),
        "pt": (["Que horas você chega?", "Lá pelas 7, tô terminando uma coisa 🙂", "Ótimo, te encontro na frente do cinema"],
               ["Beleza, chego em dez minu", "Perfeito, já estou a cami", "Muito obrigado, até "]),
    ]
    private var lines: ([String], [String]) { Self.talk[lang] ?? Self.talk["en"]! }

    private var messages: [(String, Bool)] {
        let m = lines.0
        return [(m[0], false), (m[1], true), (m[2], false)]
    }

    private var draft: String {
        switch base {
        case "clip": return ""
        case "left": return lines.1[2]
        case "split": return lines.1[1]
        default: return lines.1[0]
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
            KeyboardPreview(settings: settings, pro: true, text: $text, demoContext: demoContext)
                .frame(height: KeyboardPreview.height(settings))
        }
        .onAppear { text = draft }
    }
}
