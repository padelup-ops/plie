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

    /// Which console the game is for (from the file's extension in the library).
    var system: PakSystem {
        switch (id as NSString).pathExtension {
        case "gba": return .gba
        case "nds": return .nds
        default: return .gb
        }
    }
}

enum PakSystem: String {
    case gb, gba, nds

    /// The short name shown in the library.
    var badge: String {
        switch self {
        case .gb: return "GB"
        case .gba: return "GBA"
        case .nds: return "DS"
        }
    }
}

enum RomLibrary {
    /// Asked by the Game Pak when the player picks "Load a game".
    static let importRequested = Notification.Name("RetroFold.importROM")
    /// Sent after a file was added, with the entry's id as the object.
    static let imported = Notification.Name("RetroFold.romImported")

    /// Any file or folder: Files greys out what it doesn't know, and game files often have no registered type.
    /// The import itself checks each file.
    static var contentTypes: [UTType] { [.item, .folder] }

    static let romExtensions: Set<String> = ["gb", "gbc", "cgb", "sgb", "dmg", "gba", "agb", "nds"]

    /// What an import did, for the Game Pak screen.
    struct Outcome {
        var added: [RomEntry] = []
        var skipped = 0
        var message: String? {
            if added.isEmpty {
                return String(localized: "NO GAME FOUND (.GB / .GBC / .GBA / .NDS / .ZIP)")
            }
            if added.count == 1 && skipped == 0 { return nil }
            return String(localized: "\(added.count) GAMES ADDED")
        }
    }

    /// Imports everything picked: game files, .zip archives and whole folders (searched inside).
    static func importAll(_ urls: [URL]) -> Outcome {
        var out = Outcome()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                           options: [.skipsHiddenFiles])
                var seen = 0
                while let f = files?.nextObject() as? URL, seen < 2000 {
                    seen += 1
                    importOne(f, into: &out)
                }
            } else {
                importOne(url, into: &out)
            }
        }
        return out
    }

    private static func importOne(_ url: URL, into out: inout Outcome) {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { out.skipped += 1; return }
            let games = ZipReader.files(in: data) { romExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            if games.isEmpty { out.skipped += 1 }
            for (name, bytes) in games {
                if let e = try? add(bytes, name: name) { out.added.append(e) } else { out.skipped += 1 }
            }
            return
        }
        guard romExtensions.contains(ext) || ext.isEmpty || ext == "bin" else { return }
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { out.skipped += 1; return }
        if let e = try? add(data, name: url.lastPathComponent) { out.added.append(e) } else { out.skipped += 1 }
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
    /// Where a GBA or DS core keeps its own files for a game.
    static func saveFolder(_ e: RomEntry) -> URL { folder.appendingPathComponent("saves/" + e.id, isDirectory: true) }

    enum ImportError: LocalizedError {
        case notAGame
        var errorDescription: String? { String(localized: "This file isn't a Game Boy, Game Boy Advance or DS game.") }
    }

    /// Adds a game to the library. Checks the cartridge header (the Nintendo logo's first bytes and a sane
    /// size), so random files are refused.
    @discardableResult
    static func add(_ data: Data, name: String) throws -> RomEntry {
        let base = (name as NSString).deletingPathExtension
        // Each console's header carries the start of the boot logo at a known place.
        let gbLogo: [UInt8] = [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B]
        let advLogo: [UInt8] = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21]
        func has(_ logo: [UInt8], at o: Int) -> Bool { data.count >= o + 8 && Array(data[o..<(o + 8)]) == logo }
        let ext: String
        var title: String?
        if data.count >= 0x8000, data.count <= 8 << 20, has(gbLogo, at: 0x104) {
            ext = (name as NSString).pathExtension.lowercased() == "gbc" || data[0x143] & 0x80 != 0 ? "gbc" : "gb"
            title = headerTitle(data)
        } else if data.count >= 0x200, data.count <= 512 << 20, has(advLogo, at: 0xC0) {
            ext = "nds"
            title = asciiTitle(data, 0..<12)
        } else if data.count >= 0x200, data.count <= 32 << 20, has(advLogo, at: 0x04) {
            ext = "gba"
            title = asciiTitle(data, 0xA0..<0xAC)
        } else {
            throw ImportError.notAGame
        }
        let title2 = title ?? base
        let id = "\(stableHash(data)).\(ext)"
        let dest = folder.appendingPathComponent(id)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try data.write(to: dest, options: .atomic)
        }
        var list = (try? JSONDecoder().decode([RomEntry].self, from: Data(contentsOf: indexURL))) ?? []
        if let existing = list.first(where: { $0.id == id }) { return existing }
        // A file name usually says more than the 11-16 letters of the header.
        let entry = RomEntry(id: id, title: base.count > 2 ? base : title2, added: Date())
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
        for u in [romURL(e), batteryURL(e), stateURL(e), saveFolder(e)] { try? FileManager.default.removeItem(at: u) }
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

    private static func asciiTitle(_ data: Data, _ r: Range<Int>) -> String? {
        guard data.count >= r.upperBound else { return nil }
        let t = String(bytes: data[r].filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
        return (t?.isEmpty ?? true) ? nil : t
    }

    private static func stableHash(_ data: Data) -> String {
        // FNV-1a 64 bits over the size and the first 4 MB (DS games are large): a stable file name per game.
        var h: UInt64 = 0xcbf29ce484222325 ^ UInt64(data.count)
        data.prefix(4 << 20).withUnsafeBytes { raw in
            for b in raw.bindMemory(to: UInt8.self) { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        }
        return String(h, radix: 16)
    }
}

/// Reads the files of a .zip archive (stored or deflated), enough for game archives.
enum ZipReader {
    static func files(in data: Data, where keep: (String) -> Bool) -> [(String, Data)] {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < b.count ? u16(o) | u16(o + 2) << 16 : 0 }
        // End of central directory: the last "PK\u{5}\u{6}".
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 66_000) {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 5, b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return [] }
        var p = u32(eocd + 16)
        let count = u16(eocd + 10)
        var out: [(String, Data)] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014B50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<min(b.count, p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + elen + clen
            guard keep(name), !name.hasPrefix("__MACOSX"), usize <= 256 * 1024 * 1024, local + 30 <= b.count,
                  u32(local) == 0x04034B50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { continue }
            let chunk = Data(b[start..<(start + csize)])
            switch method {
            case 0: out.append((name, chunk))
            case 8:
                if let d = try? (chunk as NSData).decompressed(using: .zlib) as Data { out.append((name, d)) }
            default: continue
            }
        }
        return out
    }
}
