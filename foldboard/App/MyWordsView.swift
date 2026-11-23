import SwiftUI

/// « Mes mots » : les mots que Foldboard ne corrige jamais (argot, noms, marques…). On en ajoute ici ; le clavier y
/// met aussi un mot dont on a annulé la correction deux fois (une seule annulation par erreur n'y met plus de faute).
/// Sélection de plusieurs mots pour les supprimer d'un coup. Partagé avec le clavier par les réglages.
struct MyWordsView: View {
    @Environment(SettingsModel.self) private var model
    @State private var draft = ""
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmAll = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var m = model
        List(selection: $selection) {
            Section {
                Toggle("Use My words", isOn: $m.settings.myWordsOn)
                Toggle("Add a word when I undo its correction twice", isOn: $m.settings.learnOnUndo)
            } footer: {
                Text("Off: Foldboard corrects as if the list were empty, and your words stay here for later.")
            }
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
                Text("Words Foldboard never corrects. When you undo the correction of the same word twice, it's added here.")
            }
            Section {
                if m.settings.myWords.isEmpty {
                    Text("No words yet. Add the words Foldboard should never correct: slang, names, brands…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(m.settings.myWords, id: \.self) { w in
                        Text(w).tag(w)
                    }
                    .onDelete { m.settings.myWords.remove(atOffsets: $0) }
                }
            } footer: {
                if !m.settings.myWords.isEmpty {
                    Text("Tap Select to pick several words and delete them at once.")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("My words")
        .toolbar {
            if !m.settings.myWords.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        selection.removeAll()
                    }
                }
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Delete all", role: .destructive) { confirmAll = true }
                    Spacer()
                    Button(role: .destructive) {
                        m.settings.myWords.removeAll { selection.contains($0) }
                        selection.removeAll()
                    } label: {
                        Text("Delete \(selection.count)")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .confirmationDialog("Delete all your words?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                m.settings.myWords.removeAll()
                m.settings.undoneOnce.removeAll()
                selection.removeAll()
                editMode = .inactive
            }
        }
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
