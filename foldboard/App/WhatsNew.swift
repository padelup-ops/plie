import SwiftUI

/// « Quoi de neuf » : montré une fois, à l'ouverture de l'app après la mise à jour, à ceux qui avaient déjà l'app.
/// Aussi dans les réglages (Quoi de neuf). Changer `edition` pour la prochaine grande mise à jour.
struct WhatsNewView: View {
    static let edition = "2026-11-b"
    var onDone: (() -> Void)? = nil

    private struct Item: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let tint: Color
        var id: String { icon }
    }

    private let items: [Item] = [
        Item(icon: "iphone.radiowaves.left.and.right", title: "Knock the side to move it",
             detail: "Tap the left or right edge of your iPhone: the one-hand keyboard jumps to that side. You can also tap the empty space next to it.", tint: .orange),
        Item(icon: "translate", title: "Translate as you dictate",
             detail: "Speak French, get English (and the other way round, in many languages). The 🌐 button translates what you just typed.", tint: .blue),
        Item(icon: "waveform", title: "A brand-new dictation",
             detail: "A glowing new look, and it keeps everything you say until you close it, even after a pause.", tint: .purple),
        Item(icon: "text.badge.checkmark", title: "Smarter autocorrect",
             detail: "About 100,000 French and 80,000 English words. Fewer wrong guesses, brand names done right.", tint: .green),
        Item(icon: "rectangle.topthird.inset.filled", title: "Your bar, your way",
             detail: "Buttons on the right, on the left or on both sides. Suggestions never cover them, and the clipboard stays in reach.", tint: .pink),
        Item(icon: "hand.raised.fingers.spread", title: "You choose the side",
             detail: "Pick one hand left, one hand right, full width or two hands: it stays there on every screen. \"Forget my hands\" starts the learning over.", tint: .teal),
        Item(icon: "mic.badge.plus", title: "The mic where you want it",
             detail: "Next to return, or in the bar. Turn on \"Hold the mic to dictate\" so it never starts by accident.", tint: .red),
        Item(icon: "doc.on.clipboard", title: "Paste without the prompt",
             detail: "No more \"Allow Paste\" every time you copy something.", tint: .indigo),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("What's new in Foldboard").font(.largeTitle.bold())
                    Text("Thanks to everyone who sent their ideas and bug reports. Here's what changed.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(items) { i in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: i.icon)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(i.tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(i.title).font(.headline)
                                Text(i.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let onDone {
                    Button(action: onDone) {
                        Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(onDone == nil ? Text("What's new") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
