// RomLibrary.swift
// RetroCartridge
//
// The player's own Game Boy games, imported from Files. RetroFold ships no
// games: each file is copied into the app's private storage, with the
// cartridge's battery save and a snapshot to pick up where the player left off.

import Foundation
import UniformTypeIdentifiers

struct RomEntry: Codable, Identifiable, Equatable {
    /// The file name in the library folder.
    let id: String
    /// The title from the cartridge header, or the file name.
    var title: String
    var added: Date
    var lastPlayed: Date?
}

enum RomLibrary {
    /// Asked by the Game Pak when the player picks "Load a game".
    static let importRequested = Notification.Name("RetroFold.importROM")
    /// Sent after a file was added, with the entry's id as the object.
    static let imported = Notification.Name("RetroFold.romImported")

    /// .gb and .gbc files (declared loosely: Files often reports them as plain data).
    static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        if let gb = UTType(filenameExtension: "gb") { types.insert(gb, at: 0) }
        if let gbc = UTType(filenameExtension: "gbc") { types.insert(gbc, at: 0) }
        return types
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GamePak", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var indexURL: URL { folder.appendingPathComponent("library.json") }

    static func entries() -> [RomEntry] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([RomEntry].self, from: data) else { return [] }
        return list
            .filter { FileManager.default.fileExists(atPath: romURL($0).path) }
            .sorted { ($0.lastPlayed ?? $0.added) > ($1.lastPlayed ?? $1.added) }
    }

    private static func save(_ list: [RomEntry]) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: indexURL, options: .atomic) }
    }

    static func romURL(_ e: RomEntry) -> URL { folder.appendingPathComponent(e.id) }
    static func batteryURL(_ e: RomEntry) -> URL { folder.appendingPathComponent(e.id + ".sav") }
    static func stateURL(_ e: RomEntry) -> URL { folder.appendingPathComponent(e.id + ".state") }

    enum ImportError: LocalizedError {
        case notAGame
        var errorDescription: String? { String(localized: "This file isn't a Game Boy game (.gb or .gbc).") }
    }

    /// Copies a picked file into the library. Checks the cartridge header (the Nintendo logo area must be there
    /// and the size must make sense), so random files are refused.
    @discardableResult
    static func importFile(_ url: URL) throws -> RomEntry {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count >= 0x8000, data.count <= 8 * 1024 * 1024, data.count % 0x4000 == 0 || data.count == 0x8000 else {
            throw ImportError.notAGame
        }
        let title = headerTitle(data) ?? url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased() == "gbc" ? "gbc" : "gb"
        let id = "\(stableHash(data)).\(ext)"
        let dest = folder.appendingPathComponent(id)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try data.write(to: dest, options: .atomic)
        }
        var list = (try? JSONDecoder().decode([RomEntry].self, from: Data(contentsOf: indexURL))) ?? []
        if let i = list.firstIndex(where: { $0.id == id }) {
            return list[i]
        }
        let entry = RomEntry(id: id, title: title, added: Date())
        list.append(entry)
        save(list)
        return entry
    }

    static func markPlayed(_ e: RomEntry) {
        var list = (try? JSONDecoder().decode([RomEntry].self, from: Data(contentsOf: indexURL))) ?? []
        if let i = list.firstIndex(where: { $0.id == e.id }) {
            list[i].lastPlayed = Date()
            save(list)
        }
    }

    static func delete(_ e: RomEntry) {
        for u in [romURL(e), batteryURL(e), stateURL(e)] { try? FileManager.default.removeItem(at: u) }
        var list = (try? JSONDecoder().decode([RomEntry].self, from: Data(contentsOf: indexURL))) ?? []
        list.removeAll { $0.id == e.id }
        save(list)
    }

    /// The title in the cartridge header (0x134–0x143), printable characters only.
    static func headerTitle(_ data: Data) -> String? {
        guard data.count > 0x143 else { return nil }
        let bytes = data[0x134...0x143].prefix { $0 != 0 }
        let s = String(bytes: bytes.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces)
        return (s?.isEmpty ?? true) ? nil : s
    }

    private static func stableHash(_ data: Data) -> String {
        // FNV-1a 64 bits: a stable file name for the same game.
        var h: UInt64 = 0xcbf29ce484222325
        for b in data { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}
