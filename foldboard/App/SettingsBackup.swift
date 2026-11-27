// SettingsBackup.swift — Foldboard
//
// Sauvegarder, partager et reprendre tous les réglages du clavier (demande d'un testeur) : un seul fichier, que l'on
// garde dans Fichiers, que l'on s'envoie d'une version de l'app à l'autre, ou que l'on donne à quelqu'un.

import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackupView: View {
    @Environment(SettingsModel.self) private var model
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var pending: KBSettings?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export my settings", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("One file with everything: positions, sizes, colors, buttons, your phrases, your words and what the keyboard learned from your thumbs. Save it in Files, send it to yourself or to a friend.")
            }
            Section {
                Button { importing = true } label: {
                    Label("Import settings", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Choose a Foldboard settings file. It replaces all the settings on this iPhone.")
            }
        }
        .navigationTitle("Backup")
        .onAppear { exportURL = Self.write(model.settings) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let found = KBSettingsFile.read(data) {
                pending = found
            } else {
                message = NSLocalizedString("This file isn’t a Foldboard settings file.", comment: "")
            }
        }
        .confirmationDialog("Replace all your settings with this file?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Replace my settings", role: .destructive) {
                if var s = pending {
                    s.stamp = Date()
                    model.settings = s
                    exportURL = Self.write(s)
                    message = NSLocalizedString("Settings imported.", comment: "")
                }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Done", role: .cancel) { message = nil }
        }
    }

    /// Le fichier à partager, écrit d'avance (la feuille de partage veut un fichier qui existe déjà).
    private static func write(_ settings: KBSettings) -> URL? {
        guard let data = KBSettingsFile.data(settings) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Foldboard settings.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
