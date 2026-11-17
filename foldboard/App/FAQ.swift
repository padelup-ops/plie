import SwiftUI

// MARK: - Questions fréquentes
//
// Les questions que les testeurs et les avis posent le plus. Les textes sont des clés anglaises traduites dans
// Localizable.strings (11 langues) ; les réponses acceptent le gras Markdown (**…**) pour les noms de réglages.

enum FAQTopic: CaseIterable {
    case start, typing, duo, pro

    var title: LocalizedStringKey {
        switch self {
        case .start: return "Getting started"
        case .typing: return "Typing"
        case .duo: return "Your Duo"
        case .pro: return "Purchase and privacy"
        }
    }
}

struct FAQItem: Identifiable {
    let id: Int
    let topic: FAQTopic
    let q: String
    let a: String

    var question: String { NSLocalizedString(q, comment: "") }
    var answerText: String { NSLocalizedString(a, comment: "") }
    var answer: AttributedString {
        (try? AttributedString(markdown: answerText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(answerText)
    }
}

enum FAQ {
    static let items: [FAQItem] = [
        FAQItem(id: 1, topic: .start,
                q: "How do I add Foldboard to my keyboards?",
                a: "On the home screen, tap **Add Foldboard to your keyboards**: Settings opens on Foldboard’s page. Tap **Keyboards** and turn on Foldboard. Then, in any app, hold the globe key under the keyboard and pick Foldboard."),
        FAQItem(id: 2, topic: .start,
                q: "Why does Foldboard ask for Full Access?",
                a: "Only for vibrations, typing sounds, the clipboard and to share your settings between the app and the keyboard. The keyboard has no internet access: nothing you type leaves your iPhone."),
        FAQItem(id: 3, topic: .start,
                q: "Why does Apple’s keyboard sometimes show up instead?",
                a: "iOS always uses its own keyboard for passwords and phone numbers, and some apps (banks, for example) don’t allow other keyboards. Foldboard comes back on its own in the next field. If it switches while you are typing, update Foldboard: recent versions use much less memory."),
        FAQItem(id: 4, topic: .start,
                q: "Can I dictate with Foldboard?",
                a: "Yes. Tap the mic above the keys. The first time, Foldboard opens for a moment to turn on the microphone (iOS doesn’t let keyboards use it), then go back to your app. For the next 10 minutes, just tap the mic and talk, and tap it again to stop. Your voice is transcribed on your iPhone: nothing is sent."),
        FAQItem(id: 5, topic: .typing,
                q: "How do I move the cursor?",
                a: "Hold the space bar: the letters fade and the whole keyboard becomes a trackpad. Slide to move the cursor anywhere, up and down too."),
        FAQItem(id: 6, topic: .typing,
                q: "How does slide to type work?",
                a: "Slide your thumb from letter to letter without lifting it: the word appears when you lift. If it’s not the right one, the other words are in the suggestion bar. Turn it on or off in **Typing**."),
        FAQItem(id: 7, topic: .typing,
                q: "How do I undo an autocorrection?",
                a: "Tap delete right after the correction: your word comes back as you typed it, and Foldboard leaves it alone."),
        FAQItem(id: 8, topic: .typing,
                q: "How do I get emoji?",
                a: "Tap the emoji key, or just type a word like “love”, “pizza” or “merci”: an emoji shows up in the suggestion bar. You can turn this off in **Typing**."),
        FAQItem(id: 9, topic: .typing,
                q: "How do I paste?",
                a: "When you copy something, a Paste button shows up in the suggestion bar. Turn on **Save everything I copy** in **Typing** to find what you copied later with the clipboard button above the keys (it needs Full Access)."),
        FAQItem(id: 10, topic: .typing,
                q: "Which languages and layouts?",
                a: "Layouts: AZERTY, QWERTY, QWERTZ, Spanish and Swedish (**Position and size › Layout**). Suggestions and autocorrect are made for French and English."),
        FAQItem(id: 11, topic: .duo,
                q: "How does the keyboard know which hand I’m using?",
                a: "Foldboard looks at how you hold your Duo and where your thumbs tap, and learns your habits. If it picks the wrong side, tap ⇆ above the keys: it moves and remembers. **Teach your thumbs** (30 seconds) helps it learn faster. Everything stays on your iPhone."),
        FAQItem(id: 12, topic: .duo,
                q: "How do I type with both hands?",
                a: "Tap the middle button above the keys: the keyboard goes full width. On the open Duo, the ••• button lets you choose full width, follows your hand or split keyboard. Foldboard remembers your choice for each screen."),
        FAQItem(id: 13, topic: .duo,
                q: "How do I make the keys bigger or smaller?",
                a: "Tap the sliders button above the keys and drag the keyboard, or go to **Position and size** in the app. **Reset size to default** brings back the original size."),
        FAQItem(id: 14, topic: .duo,
                q: "Why are there empty bands on the sides in landscape?",
                a: "In landscape, iOS gives keyboards from other apps only the space between the rounded corners and the camera. Foldboard fills all the space it gets: the bands on the sides are kept by iOS."),
        FAQItem(id: 15, topic: .pro,
                q: "How much does Foldboard cost?",
                a: "You can try everything free for 3 days. Then Foldboard Pro is a one-time purchase, with no subscription. Without Pro, the keyboard keeps working with the basics."),
        FAQItem(id: 16, topic: .pro,
                q: "I changed iPhone. How do I get Pro back?",
                a: "Open **Foldboard Pro** and tap **Restore purchases**, with the same Apple account."),
        FAQItem(id: 17, topic: .pro,
                q: "Does Foldboard read what I type?",
                a: "No. The keyboard has no internet access, and Foldboard has no account and no ads. What it learns (your words, how you hold your Duo) stays on your iPhone."),
    ]

    static func items(_ t: FAQTopic) -> [FAQItem] { items.filter { $0.topic == t } }

    /// Sans accents ni majuscules ; chaque mot cherché doit se trouver dans la question ou la réponse.
    static func search(_ query: String) -> [FAQItem] {
        let terms = SettingsEntry.norm(query).split(separator: " ").map(String.init).filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }
        return items.filter { i in
            let hay = SettingsEntry.norm(i.question + " " + i.answerText)
            return terms.allSatisfy { hay.contains($0) }
        }
    }
}

/// Les questions, rangées par thème ; un toucher ouvre la réponse.
struct FAQView: View {
    var open: Int? = nil
    var expandAll = false
    @State private var expanded: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Atelier.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Questions and answers")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(Atelier.ink)
                    Text("The questions people ask most")
                        .font(.subheadline)
                        .foregroundStyle(Atelier.muted)
                }
                ForEach(FAQTopic.allCases, id: \.self) { t in
                    VStack(alignment: .leading, spacing: Atelier.s1) {
                        Text(t.title)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(Atelier.accent)
                        VStack(spacing: 0) {
                            ForEach(Array(FAQ.items(t).enumerated()), id: \.element.id) { i, q in
                                if i > 0 { Rectangle().fill(Atelier.line).frame(height: 1).padding(.leading, Atelier.s2) }
                                item(q)
                            }
                        }
                        .atelierCard()
                    }
                }
            }
            .padding(.horizontal, Atelier.s2)
            .padding(.top, Atelier.s1)
            .padding(.bottom, Atelier.s4)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Atelier.bg.ignoresSafeArea())
        .tint(Atelier.accent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if expandAll { expanded = Set(FAQ.items.map(\.id)) } else if let open { expanded.insert(open) }
        }
    }

    private func item(_ q: FAQItem) -> some View {
        let isOpen = expanded.contains(q.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { expanded.remove(q.id) } else { expanded.insert(q.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: Atelier.s1) {
                    Text(q.question)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Atelier.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Atelier.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.top, 4)
                }
                .padding(.horizontal, Atelier.s2)
                .padding(.vertical, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])
            if isOpen {
                Text(q.answer)
                    .font(.subheadline)
                    .foregroundStyle(Atelier.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Atelier.s2)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    /// Une carte de l'accueil « Atelier » : surface claire, coins doux, filet fin.
    func atelierCard() -> some View {
        background(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).fill(Atelier.surface))
            .overlay(RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous).strokeBorder(Atelier.line))
    }
}
