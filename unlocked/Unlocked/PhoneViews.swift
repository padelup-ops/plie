import SwiftUI

// MARK: - Pièces communes : avatar, fin de chapitre

let ink = Color(red: 0.07, green: 0.07, blue: 0.1)

struct Avatar: View {
    let contact: Contact
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(red: 0.66, green: 0.68, blue: 0.73), Color(red: 0.53, green: 0.55, blue: 0.6)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Text(contact.initials).font(.system(size: size * 0.42, weight: .medium, design: .rounded)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

struct ChapterEndCard: View {
    @Environment(GameState.self) private var state
    let number: Int

    var body: some View {
        let chapter = state.story.chapters[max(0, min(number - 1, state.story.chapters.count - 1))]
        let last = number >= state.story.chapters.count
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(last ? T("FIN", "THE END") : T("FIN DU CHAPITRE \(number)", "END OF CHAPTER \(number)"))
                    .font(.system(.footnote, design: .rounded, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(chapter.title)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(chapter.endText)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, design: .rounded))
                if state.needsPurchase && number == state.story.freeChapters {
                    Button {
                        state.showChapterEnd = nil
                        state.showPaywall = true
                    } label: {
                        Text(T("Lire la suite", "Keep reading"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                    Button(T("Plus tard", "Later")) { state.showChapterEnd = nil }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        state.showChapterEnd = nil
                    } label: {
                        Text(T("Continuer", "Continue"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.12)))
            .foregroundStyle(.white)
            .padding(24)
        }
    }
}
