import SwiftUI

/// « Mes mots » : les mots que Foldboard ne corrige jamais (argot, noms, marques…). On en ajoute ici, et le clavier
/// y met tout seul un mot dont on a annulé la correction. Partagé avec le clavier par les réglages.
struct MyWordsView: View {
    @Environment(SettingsModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                HStack {
                    TextField("Add a word", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Words Foldboard never corrects. When you undo a correction, the word is added here.")
            }
            Section {
                if m.settings.myWords.isEmpty {
                    Text("No words yet. Add the words Foldboard should never correct: slang, names, brands…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(m.settings.myWords, id: \.self) { w in
                        Text(w)
                    }
                    .onDelete { m.settings.myWords.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("My words")
        .toolbar { if !m.settings.myWords.isEmpty { EditButton() } }
    }

    private func add() {
        // Plusieurs mots d'un coup (« spendy, yeet ») : chacun est ajouté.
        let parts = draft.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" || $0 == "\n" }).map(String.init)
        var s = model.settings
        for p in parts.reversed() { s.addMyWord(p) }
        model.settings = s
        draft = ""
        focused = true
    }
}
